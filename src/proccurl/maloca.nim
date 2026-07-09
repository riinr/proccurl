import std/atomics

type
  Arena* = object
    lock:  Atomic[bool]
    size:  int
    start: ptr UncheckedArray[byte]
    cur:   ptr UncheckedArray[byte]

proc createArena(size: int): ptr Arena =
  doAssert size > 0, "arena size must be positive, got " & $size
  result = cast[ptr Arena](allocShared(sizeOf(Arena) + size))
  result.size  = size
  result.start = cast[ptr UncheckedArray[byte]](cast[ptr UncheckedArray[byte]](result)[sizeOf(Arena)].addr)
  result.cur   = result.start

proc reset*(arena: ptr Arena): void =
  arena.cur = arena.start
  for i in 0..<arena.size:
    arena.start[i] = 0.byte; 

proc delete*(arena: ptr Arena): void =
  if arena.start != nil:
    deallocShared(arena)

proc len*(arena: ptr Arena): int =
  arena.size

proc remaining*(arena: ptr Arena): int =
  arena.size - (cast[int](arena.cur) - cast[int](arena.start))

proc used*(arena: ptr Arena): int =
  cast[int](arena.cur) - cast[int](arena.start)

template roundUp(x: int; alignment: int): int =
  (x + alignment - 1) and (not (alignment - 1))

proc alloc*[T](arena: ptr Arena; t: typedesc[T]): ptr T =
  let align   = alignof(T)
  let current = cast[int](arena.cur)
  let aligned = roundUp(current, align)
  let newCur  = aligned + sizeOf(T)
  if newCur > cast[int](arena.start) + arena.size:
    return nil
  arena.cur = cast[ptr UncheckedArray[byte]](newCur)
  result = cast[ptr T](aligned)

proc alloc*[T](arena: ptr Arena; t: typedesc[T]; n: int): ptr UncheckedArray[T] =
  let align   = alignof(T)
  let current = cast[int](arena.cur)
  let aligned = roundUp(current, align)
  let newCur  = aligned + sizeof(T) * n
  if newCur > cast[int](arena.start) + arena.size:
    return nil
  arena.cur = cast[ptr UncheckedArray[byte]](newCur)
  result = cast[ptr UncheckedArray[T]](aligned)

proc alignedAlloc*[T](arena: ptr Arena; t: typedesc[T]; alignment: Positive): ptr T =
  let current = cast[int](arena.cur)
  let aligned = roundUp(current, alignment)
  let newCur  = aligned + sizeof(T)
  if newCur > cast[int](arena.start) + arena.size:
    return nil
  arena.cur = cast[ptr UncheckedArray[byte]](newCur)
  result = cast[ptr T](aligned)

when isMainModule:
  proc main: void =
    let a = createArena(1024)
    assert a.len == 1024
    assert a.used == 0
    assert a.remaining == 1024

    let p = a.alloc(int)
    assert p != nil
    assert a.used == sizeof(int)
    p[] = 42
    assert p[] == 42

    let q = a.alloc(int, 10)
    assert q != nil
    q[0] = 1
    q[9] = 10

    a.reset
    assert a.used == 0
    assert a.remaining == 1024

    let r = a.alloc(int)
    assert r != nil
    r[] = 99

    a.delete

    echo "OK"

  main()
