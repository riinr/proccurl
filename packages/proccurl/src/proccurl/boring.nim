## This is a Ring Buffer implementation
##
## It has some advantages
## - Works with Multiple Producer Multiple Consumer
## - Is reasonable simple:
##   - You can only write next if next is writable
##   - You can only read  next if next is readable
##   - Unwritable/Unreadable means full/empty or busy
##     taken by another thread/process
## - It doesn't apply pooling (async friendly):
##   - Instead of wait it returns to caller, to call again or reeschedule
##   - Only success blocks for copy
##   - Copy is done on len of msg (instead of full buffer size)
##   - My tests copies 4KB in ~100ns, 8KB in ~200ns, 12KB in ~350ns
## - I'm trying to make it work with mmap to use as IPC
##   - Most implementation can only be used with threads
##
## It has some flaws:
## - Memory copy, no clue how to do it with zero copy
## - latency is (copyOf(buff, len) x 2) + (copyOf(uint32) + reeschedules/calls)
## - Contention when used as Multiple Produces Multiple Consumer
## - Isn't the most space efficient solution
## - Size of buffer is bounded
##  - For dynamic size responses (like my case curl) you have
##    check if size fits, and slice msgs

when defined profiler:
  import nimprof


import std/[atomics, options]

const PAGE* {.intdefine: "boring.mempage".} = 4096 # 4 KB

type
  IStat* = enum
    ## STATE MACHINE RD -> WW -> WD  -> RR -> RD
    RD,          ## Reader Done:     can  push
    WW,          ## Writer Writing:  wait before shift
    WD,          ## Writer Done:     can  shift
    RR,          ## Reader Reading:  wait before push

  Idx*[SLOTS: static int] = distinct range[0..(SLOTS - 1)]

  Slot*[T] = object
    stat*: Atomic[IStat]   ## Slot status
    size*: uint32          ## Slot content len
    data*: T               ## Slot content bytes

  Ram*[SLOTS: static int, T] = array[SLOTS, Slot[T]]


proc `$`*[T](r: ptr Slot[T]): string =
  r.repr


template state*[T](r: ptr Slot[T]; v: IStat): void =
  ## Set Slot stat
  r.stat.store cast[uint8](v), moAcquireRelease


template state*[T](r: ptr Slot[T]): IStat =
  ## Get Slot stat
  cast[IStat](r.stat.load moAcquireRelease)


template start_reading* [T](
    r: ptr Slot[T];
    s: var IStat;
): bool =
  ## try to set Slot as reading
  ##
  ## If false, returns false and changes `s` to reason, if reason is:
  ## - RR means other thread is already reading from Slot
  ## - RD means it is empty shouldn't read from Slot
  ## - WW means it is not ready to read Slot
  ##
  ## If true, returns true and sets internal state to RR (reader reading)
  ##
  r.stat.compareExchangeWeak s, RR, moAcquire, moRelaxed


template stop_reading*[T](
    r: ptr Slot[T];
): void =
  ## set the internal state of Slot[i] to reader done
  ## freeing it so other threads can write
  r.stat.store RD, moRelease


template start_writing*[T](
    r: ptr Slot[T];
    s: var IStat
): bool =
  ## try to set Slot as writing
  ##
  ## If false, returns false and changes `s` to reason, if reason is:
  ## - WW means other thread is writing into Slot
  ## - WD means it is full shouldn't overwrite Slot
  ## - RR means is not ready to write in Slot
  ##
  ## If true, returns true and sets internal state to WW (writer writing)
  ##
  r.stat.compareExchangeWeak s, WW, moAcquire, moRelaxed


template stop_writing*[T](
  r: ptr Slot[T];
): void =
  ## set the internal state of Slot to writer done
  ## freeing it so other threads can read
  r.stat.store WD, moRelease


proc `$`[SLOTS: static int](idx: Idx[SLOTS]): string =
  ## convert Idx[SLOTS] to string
  $(cast[uint32](idx))


template `[]`*[SLOTS: static int, T](r: var Ram[SLOTS, T]; i: Idx[SLOTS]): ptr Slot[T] =
  ## get data from RAM[i]
  r[cast[uint32](i)].addr


type
  SC*[SLOTS: static int] = object
    ## Single Consumer Reader
    reader*: Idx[SLOTS]

  SP*[SLOTS: static int] = object
    ## Single Producer Writer
    writer*: Idx[SLOTS]

  MC*[SLOTS: static int] = object
    ## Multi Consumer Reader
    reader*: Atomic[Idx[SLOTS]]

  MP*[SLOTS: static int] = object
    ## Multi Producer Writer
    writer*: Atomic[Idx[SLOTS]]

  P*[SLOTS: static int] = SP[SLOTS]|MP[SLOTS]  ## Generic Producer
  C*[SLOTS: static int] = SC[SLOTS]|MC[SLOTS]  ## Generic Consumer


template producer*[SLOTS: static int](p: ptr SP[SLOTS]): Idx[SLOTS] =
  ## Get producer pointer position
  p.writer

template producer*[SLOTS: static int](p: ptr MP[SLOTS]): Idx[SLOTS] =
  ## Get producer pointer position
  p.writer.load moRelaxed

template inc*     [SLOTS: static int](p: ptr SP[SLOTS]; prev: Idx[SLOTS]): Idx[SLOTS] =
  ## Move producer pointer to next position
  var writer = cast[uint32](prev) + 1
  if writer == SLOTS:
    writer = 0
  p.writer = cast[Idx[SLOTS]](writer)
  p.writer

template inc*     [SLOTS: static int](p: ptr MP[SLOTS]; prev: Idx[SLOTS]): Idx[SLOTS] =
  ## Move producer pointer to next position
  var writer = cast[uint32](prev) + 1
  if writer == SLOTS:
    writer = 0
  p.writer.store cast[Idx[SLOTS]](writer), moRelaxed
  cast[Idx[SLOTS]](writer)

template inc*     [SLOTS: static int](p: ptr P[SLOTS]): Idx[SLOTS] =
  ## Move producer pointer to next position
  p.inc p.producer

template consumer*[SLOTS: static int](c: ptr SC[SLOTS]): Idx[SLOTS] =
  ## Get consumer pointer current position
  c.reader

template consumer*[SLOTS: static int](c: ptr MC[SLOTS]): Idx[SLOTS] =
  ## Get consumer current position
  c.reader.load moRelaxed

template dec*     [SLOTS: static int](c: ptr SC[SLOTS]; prev: Idx[SLOTS]): Idx[SLOTS] =
  ## Move consumer to next position
  var reader = cast[uint32](prev) + 1
  if reader == SLOTS:
    reader = 0
  c.reader = cast[Idx[SLOTS]](reader)
  c.reader

template dec*     [SLOTS: static int](c: ptr MC[SLOTS]; prev: Idx[SLOTS]): Idx[SLOTS] =
  ## Move consumer pointer to next position
  var reader = cast[uint32](prev) + 1
  if reader == SLOTS:
    reader = 0
  c.reader.store cast[Idx[SLOTS]](reader), moRelaxed
  cast[Idx[SLOTS]](reader)


template dec*     [SLOTS: static int](c: ptr C[SLOTS]): Idx[SLOTS] =
  ## Move consumer pointer to next position
  c.dec c.consumer


type
  QStat* = enum
    qsDirty,  ## Queue wasn't initialized
    qsWiping, ## Other thread is working on make it ready
    qsReady,  ## Queue is ready to use

  Queue*[
    SLOTS: static int,
    P: P[SLOTS],
    C: C[SLOTS],
    T
  ] = object
    ## Your boring buffer queue with SLOTS available
    s*: Atomic[QStat]  ## check if Queue is read to use
    p*: P              ## can be SP (single producer) or MP (multiple producers)
    c*: C              ## can be SC (single consumer) or SP (multiple consumers)
    a*: Ram[SLOTS, T]  ## to store our data and position status


proc sizeOfQ*         [SLOTS: static int, T](): int =
  ## Total size of our Queue
  sizeof Queue[SLOTS, SP[SLOTS], SC[SLOTS], T]

template `[]`*        [SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](q: ptr Queue[SLOTS, P, C, T]; i: Idx[SLOTS]): ptr Slot[T] =
  ## Get Queue[i] Slot
  q.a[i]

template producer*    [SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](q: ptr Queue[SLOTS, P, C, T]): Idx[SLOTS] =
  ## Get Queue current producer position
  q.p.addr.producer

template consumer*    [SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](q: ptr Queue[SLOTS, P, C, T]): Idx[SLOTS] =
  ## Get Queue current consumer position
  q.c.addr.consumer

template inc*         [SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](q: ptr Queue[SLOTS, P, C, T]; prev: Idx[SLOTS]): Idx[SLOTS] =
  ## Move Queue to next producer position
  q.p.addr.inc prev

template dec*         [SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](q: ptr Queue[SLOTS, P, C, T]; prev: Idx[SLOTS]): Idx[SLOTS] =
  ## Move Queue to next consumer position
  q.c.addr.dec prev

template inc*         [SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](q: ptr Queue[SLOTS, P, C, T]): Idx[SLOTS] =
  ## Move Queue to next producer position
  q.p.addr.inc

template dec*         [SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](q: ptr Queue[SLOTS, P, C, T]): Idx[SLOTS] =
  ## Move Queue to next consumer position
  q.c.addr.dec

template sizes*        [SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](q: ptr Queue[SLOTS, P, C, T]; i: Idx[SLOTS]): uint32 =
  ## Get slot content size at index i
  q[i].size

template stats*        [SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](q: ptr Queue[SLOTS, P, C, T]; i: Idx[SLOTS]): IStat =
  ## Get slot state at index i
  q[i].state

proc `$`*             [SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](q: ptr Queue[SLOTS, P, C, T]): string =
  ## Convert our queue to string
  q.repr


proc enqueue*[SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T, TT](
    q: ptr Queue[SLOTS, P, C, T];
    i: var Idx[SLOTS];
    v: var TT;
    s: var IStat;
    l: uint32;
): bool =
  ## This version let you reuse vars
  ## BEWARE of side effects
  ##
  ## Not only in queue:
  ## - i will be updated with next position only if done
  ## - s will change when FULL or BUSY (this happen very often)
  ##   - s == WD means FULL
  ##   - s == WW means BUSY i, other thread is enqueuing
  ##     - try fetching i again, it may be changed
  ##   - s == RR means BUSY i, other thread is dequeuing
  ##     - In a single   consumer, try same i again, it may be completed 
  ##     - In a multiple consumer, fetch i again (order safe) or try the same (order unsafe)
  var slot = q[i]
  if not slot.start_writing(s):
    return false

  i = q.inc i
  slot.size = l
  copyMem slot.data.addr, v.addr, l
  stop_writing slot
  return  true


template enqueue*[SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T, TT](
    q: ptr Queue[SLOTS, P, C, T];
    i: var Idx[SLOTS];
    v: var TT;
    s: var IStat;
): bool =
  q.enqueue i, v, s, sizeof(TT).uint32


template enqueue*[SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T, TT](
    q: ptr Queue[SLOTS, P, C, T];
    v: var TT;
): bool =
  var i = q.producer
  var s = RD
  q.enqueue i, v, s, sizeof(TT).uint32


proc dequeue*[SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T, TT](
    q: ptr Queue[SLOTS, P, C, T];
    i: var Idx[SLOTS];
    v: var TT;
    s: var IStat;
): bool =
  ## This version let you reuse vars
  ## BEWARE of side effects
  ##
  ## Not only in queue or buffer:
  ## - v will change when SUCCEEDED only if SUCCEEDED
  ## - i will be updated with next position only if SUCCEEDED
  ## - s  will change when EMPTY or BUSY (this happen very often)
  ##   - s == RD means i position is EMPTY
  ##   - s == RR means i position is BUSY, other thread is dequeuing
  ##     - try fetching i again, it may be changed
  ##   - s == WW means i position is BUSY, other thread is enqueuing
  ##     - In a single   consumer, try same i again, it may be completed 
  ##     - In a multiple consumer, fetch i again (order safe) or try the same (order unsafe)
  var slot = q[i]
  if not slot.start_reading(s):
    return false

  i = q.dec i
  copyMem v.addr, slot.data.addr, slot.size
  stop_reading slot
  return true


template dequeue*[SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T, TT](
    q: ptr Queue[SLOTS, P, C, T];
    v: TT
): bool =
  var i = q.consumer;
  var s = WD;
  q.dequeue(i, v, s)


template dequeue*[SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](
    q: ptr Queue[SLOTS, P, C, T];
    TT: typedesc
): Option[T] =
  var i = q.consumer;
  var s = WD;
  var v: TT;
  if q.dequeue(i, v, s):
    some(v)
  else:
    none(TT)


proc newQueue*[SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](
    arena: pointer;
    arenaSize: int;
): ptr Queue[SLOTS, P, C, T] =
  ## create newQueue
  ##
  ## - SLOTS: queue max length
  ## - P    : Single (SP) or Multiple (MP) producers
  ## - C    : Single (SC) or Multiple (MC) consumers
  ## - T    : object Type
  let required = sizeof(Queue[SLOTS, P, C, T])
  assert arenaSize >= required, "arena too small: " & $arenaSize & " < " & $required
  result = cast[ptr Queue[SLOTS, P, C, T]](arena)


proc newQueue*[SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](): ptr Queue[SLOTS, P, C, T] =
  ## create newQueue
  ##
  ## - SLOTS: queue max length
  ## - P    : Single (SP) or Multiple (MP) producers
  ## - C    : Single (SC) or Multiple (MC) consumers
  ## - T    : object Type
  ##
  result = createShared(Queue[SLOTS, P, C, T])
