import std/[monotimes, locks, typedthreads, tables]
import proccurl/[ptrmath, sleez]

type
  Perc = object
    tot: int
    part: int

  Pos = object
    time: int64
    count: int
    perc: Perc

  Top = tuple
    st1: Pos
    nd2: Pos
    rd3: Pos
    th4: Pos
    th5: Pos

proc `$`(p: Perc): string =
  let i = (100 * p.part) div p.tot
  if i < 10: "0" & $i & "%" else: $i & "%"

proc cluster(i: int64; d: int): int64 =
  if i <= d: d else: i div d * d

proc top_items(a, b: ptr int64; clstr, I: int): Top =
  var h = initTable[int64, int]()
  for i in 1..<I:
    let k = cluster(b[i][] - a[i][], clstr)
    discard h.hasKeyOrPut(k, 0)
    h[k].inc

  var st1, nd2, rd3, th4, th5: Pos
  for k, v in h.pairs:
    if v > st1.count:
      th5 = th4; th4 = rd3; rd3 = nd2; nd2 = st1
      st1 = Pos(time: k + clstr, count: v)
    elif v > nd2.count:
      th5 = th4; th4 = rd3; rd3 = nd2
      nd2 = Pos(time: k + clstr, count: v)
    elif v > rd3.count:
      th5 = th4; th4 = rd3
      rd3 = Pos(time: k + clstr, count: v)
    elif v > th4.count:
      th5 = th4
      th4 = Pos(time: k + clstr, count: v)
    elif v > th5.count:
      th5 = Pos(time: k + clstr, count: v)

  let total = I
  st1.perc = Perc(tot: total, part: st1.count)
  nd2.perc = Perc(tot: total, part: nd2.count)
  rd3.perc = Perc(tot: total, part: rd3.count)
  th4.perc = Perc(tot: total, part: th4.count)
  th5.perc = Perc(tot: total, part: th5.count)
  (st1, nd2, rd3, th4, th5)

template zeroFill(t: int64): string =
  if   t < 010: "00" & $t
  elif t < 100:  "0" & $t
  else:                $t

when isMainModule:
  const MAX_ITEMS = 1000

  type TaskArgs = object
    lock: ptr Lock
    arg: ptr int64
    res: ptr int64

  proc task(args: ptr TaskArgs) {.thread.} =
    acquire(args.lock[])
    args.res[] = getMonoTime().ticks
    release(args.lock[])

  proc main =
    let send  = createShared(int64, MAX_ITEMS)
    let sent  = createShared(int64, MAX_ITEMS)
    let res   = createShared(int64, MAX_ITEMS)
    let args  = createShared(int64, MAX_ITEMS)
    let targs = createShared(TaskArgs, MAX_ITEMS)

    var lock: Lock
    initLock(lock)

    let epoc = getMonoTime().ticks

    for i in 0..<MAX_ITEMS:
      args[i] = 0
      targs[i] = TaskArgs(lock: addr lock, arg: args[i], res: res[i])

      send[i] = getMonoTime().ticks
      args[i] = getMonoTime().ticks

      var thr: Thread[ptr TaskArgs]
      createThread(thr, task, targs[i])
      sent[i] = getMonoTime().ticks
      joinThread(thr)

    let tasksSent = getMonoTime().ticks

    let ta = getMonoTime().ticks

    echo "Tasks:    \t", MAX_ITEMS
    echo "Setup:    \t", (send[0][] - epoc), "ns\t", "         \t", "Initializing"
    echo "Create 100%:\t", (tasksSent - args[0][]).ns, "ns\t", ((tasksSent - args[0][]) div MAX_ITEMS).ns, "ns/task\t", "Create + join threads"

    let (st11, nd21, rd31, th41, th51) = top_items(send, sent, 1000, MAX_ITEMS)
    echo "Create ", st11.perc, ":\t", st11.time.ns, "\t", st11.count.zeroFill, " tasks\t", "+/-250ns"
    echo "Create ", nd21.perc, ":\t", nd21.time.ns, "\t", nd21.count.zeroFill, " tasks\t", "+/-250ns"
    echo "Create ", rd31.perc, ":\t", rd31.time.ns, "\t", rd31.count.zeroFill, " tasks\t", "+/-250ns"
    echo "Create ", th41.perc, ":\t", th41.time.ns, "\t", th41.count.zeroFill, " tasks\t", "+/-250ns"
    echo "Create ", th51.perc, ":\t", th51.time.ns, "\t", th51.count.zeroFill, " tasks\t", "+/-250ns"

    let (st12, nd22, rd32, th42, th52) = top_items(sent, res,  5000, MAX_ITEMS)
    echo "Work    ", st12.perc, ":\t", st12.time.ns, "\t", st12.count.zeroFill, " tasks\t", "+/-250ns"
    echo "Work    ", nd22.perc, ":\t", nd22.time.ns, "\t", nd22.count.zeroFill, " tasks\t", "+/-250ns"
    echo "Work    ", rd32.perc, ":\t", rd32.time.ns, "\t", rd32.count.zeroFill, " tasks\t", "+/-250ns"
    echo "Work    ", th42.perc, ":\t", th42.time.ns, "\t", th42.count.zeroFill, " tasks\t", "+/-250ns"
    echo "Work    ", th52.perc, ":\t", th52.time.ns, "\t", th52.count.zeroFill, " tasks\t", "+/-250ns"

    echo "Total:   \t", (ta - epoc).ns, "ns"

    deinitLock(lock)
    freeShared res
    freeShared args
    freeShared sent
    freeShared targs

  main()
