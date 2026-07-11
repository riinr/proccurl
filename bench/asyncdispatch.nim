import std/[asyncfutures, asyncdispatch]
import std/monotimes
import proccurl/[ptrmath, sleez, stats]


when isMainModule:
  let doneFuture = newFuture[void]()
  doneFuture.complete

  proc helloWorld(args, res: pointer): Future[void] {.async.} =
    await doneFuture # makes sure we release to mainloop
    cast[ptr int64](res)[] = getMonoTime().ticks

  const MAX_ITEMS = 1000

  proc main(): Future[void] {.async.} =
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
      await helloWorld(args[i], res[i])
      sent[i] = getMonoTime().ticks

    let tasksSent = getMonoTime().ticks

    let ta = getMonoTime().ticks

    let (st11, nd21, rd31, th41, th51) = top_items(cast[ptr UncheckedArray[int64]](send), cast[ptr UncheckedArray[int64]](sent), 25, MAX_ITEMS)
    let (st12, nd22, rd32, th42, th52) = top_items(cast[ptr UncheckedArray[int64]](sent), cast[ptr UncheckedArray[int64]](res),  02, MAX_ITEMS)

    echo "Tasks:    \t", MAX_ITEMS
    echo "Setup:    \t", (send[0][] - epoc).ns, "\t", "         \t", "Initializing"
    echo "Send  100%:\t", (tasksSent - args[0][]).ns,   "\t", ((tasksSent - args[0][]) div MAX_ITEMS).ns, "/task\t", "To schedule tasks"
    printCluster(st11, nd21, rd31, th41, th51, 25, "Send   ")
    printCluster(st12, nd22, rd32, th42, th52, 02, "Latency ")

    printJoinSummary(ta - tasksSent, ta - args[0][], ta - epoc, MAX_ITEMS)
 

    freeShared res
    freeShared args
    freeShared sent
    freeShared args

  waitFor main()
