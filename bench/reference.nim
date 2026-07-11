import std/monotimes
import proccurl/[ptrmath, sleez, stats]


when isMainModule:
  proc helloWorld(args, res: pointer): void =
    cast[ptr int64](res)[] = getMonoTime().ticks

  const MAX_ITEMS = 1000

  proc main(): void =
    ## Room for work
    let send  = createShared(int64,  MAX_ITEMS)
    let sent  = createShared(int64,  MAX_ITEMS)
    let args  = createShared(int64,  MAX_ITEMS)
    let res   = createShared(int64,  MAX_ITEMS)

    let epoc = getMonoTime().ticks

    for i in 0..<MAX_ITEMS:
      args[i] = 0

      send[i] = getMonoTime().ticks
      args[i] = getMonoTime().ticks
      helloWorld(args[i], res[i])
      sent[i] = getMonoTime().ticks

    let tasksSent = getMonoTime().ticks

    let ta = getMonoTime().ticks

    let (st11, nd21, rd31, th41, th51) = top_items(cast[ptr UncheckedArray[int64]](sent), cast[ptr UncheckedArray[int64]](res), 2, MAX_ITEMS)
    let (st12, nd22, rd32, th42, th52) = top_items(cast[ptr UncheckedArray[int64]](send), cast[ptr UncheckedArray[int64]](sent), 2, MAX_ITEMS)

    printMdHeader()
    echo "| Tasks |  |  |  | ", MAX_ITEMS, " tasks |"
    echo "| Setup |  | ", (send[0][] - epoc).ns, " |  | Initializing |"
    echo "| Send 100% |  | ", (tasksSent - args[0][]).ns, " | ", ((tasksSent - args[0][]) div MAX_ITEMS).ns, "/task | To schedule tasks |"
    printCluster(st12, nd22, rd32, th42, th52, 2, "Send   ")
    printCluster(st11, nd21, rd31, th41, th51, 2, "Latency ")

    printJoinSummary(ta - tasksSent, ta - args[0][], ta - epoc, MAX_ITEMS)
 
    echo """

    This version, doesn't use any asynch/thread feature, just function call

    We are light years away from this.
    """

    freeShared res
    freeShared args
    freeShared sent
    freeShared args

  main()
