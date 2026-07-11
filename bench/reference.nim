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

    echo "Tasks:    \t", MAX_ITEMS
    echo "Setup:    \t", (send[0][] - epoc).ns, "\t", "         \t", "Initializing"
    echo "Send  100%:\t", (tasksSent - args[0][]).ns,   "\t", ((tasksSent - args[0][]) div MAX_ITEMS).ns, "/task\t", "To schedule tasks"
    echo "Send   ", st12.perc, ":\t", (st12.time - 2).ns, "\t ", st12.count.zeroFill , " tasks\t", "+/-2ns"
    echo "Send   ", nd22.perc, ":\t", (nd22.time - 2).ns, "\t ", nd22.count.zeroFill , " tasks\t", "+/-2ns"
    echo "Send   ", rd32.perc, ":\t", (rd32.time - 2).ns, "\t ", rd32.count.zeroFill , " tasks\t", "+/-2ns"
    echo "Send   ", th42.perc, ":\t", (th42.time - 2).ns, "\t ", th42.count.zeroFill , " tasks\t", "+/-2ns"
    echo "Send   ", th52.perc, ":\t", (th52.time - 2).ns, "\t ", th52.count.zeroFill , " tasks\t", "+/-2ns"
    echo "Latency ", st11.perc, ":\t", (st11.time - 2).ns, "\t ", st11.count.zeroFill , " tasks\t", "+/-2ns"
    echo "Latency ", nd21.perc, ":\t", (nd21.time - 2).ns, "\t ", nd21.count.zeroFill , " tasks\t", "+/-2ns"
    echo "Latency ", rd31.perc, ":\t", (rd31.time - 2).ns, "\t ", rd31.count.zeroFill , " tasks\t", "+/-2ns"
    echo "Latency ", th41.perc, ":\t", (th41.time - 2).ns, "\t ", th41.count.zeroFill , " tasks\t", "+/-2ns"
    echo "Latency ", th51.perc, ":\t", (th51.time - 2).ns, "\t ", th51.count.zeroFill , " tasks\t", "+/-2ns"
    echo "Join:     \t", (ta - tasksSent).ns, "\t", "         \t", "Waiting all tasks to complete"
    echo "Snd+Join: \t", (ta - args[0][]).ns, "\t", ((ta - args[0][]) div MAX_ITEMS).ns, "/task\t", "Send + Join"
    echo "Total:    \t", (ta - epoc).ns
 

    freeShared res
    freeShared args
    freeShared sent
    freeShared args

  main()
