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
    echo "Send   ", st11.perc, ":\t", (st11.time).ns, "\t ", st11.count.zeroFill , " tasks\t", "+/-025ns"
    echo "Send   ", nd21.perc, ":\t", (nd21.time).ns, "\t ", nd21.count.zeroFill , " tasks\t", "+/-025ns"
    echo "Send   ", rd31.perc, ":\t", (rd31.time).ns, "\t ", rd31.count.zeroFill , " tasks\t", "+/-025ns"
    echo "Send   ", th41.perc, ":\t", (th41.time).ns, "\t ", th41.count.zeroFill , " tasks\t", "+/-025ns"
    echo "Send   ", th51.perc, ":\t", (th51.time).ns, "\t ", th51.count.zeroFill , " tasks\t", "+/-025ns"
    echo "Latency ", st12.perc, ":\t", (st12.time).ns, "\t ", st12.count.zeroFill , " tasks\t", "+/-002ns"
    echo "Latency ", nd22.perc, ":\t", (nd22.time).ns, "\t ", nd22.count.zeroFill , " tasks\t", "+/-002ns"
    echo "Latency ", rd32.perc, ":\t", (rd32.time).ns, "\t ", rd32.count.zeroFill , " tasks\t", "+/-002ns"
    echo "Latency ", th42.perc, ":\t", (th42.time).ns, "\t ", th42.count.zeroFill , " tasks\t", "+/-002ns"
    echo "Latency ", th52.perc, ":\t", (th52.time).ns, "\t ", th52.count.zeroFill , " tasks\t", "+/-002ns"
    echo "Join:     \t", (ta - tasksSent).ns, "\t", "         \t", "Waiting all tasks to complete"
    echo "Snd+Join: \t", (ta - args[0][]).ns, "\t", ((ta - args[0][]) div MAX_ITEMS).ns, "/task\t", "Send + Join"
    echo "Total:    \t", (ta - epoc).ns
 

    freeShared res
    freeShared args
    freeShared sent
    freeShared args

  waitFor main()
