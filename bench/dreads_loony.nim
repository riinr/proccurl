##
## The objective of this benchmark is following:
## 1. Calculate the thread pool creation overhead
## 2. Calculate how much time is required to send/schedule 1000 tasks
##   2.1 Calculate the avg
##   2.2 Group in ranges of 250 and show 5 biggest clusters
## 3. Calculate how much time is lost after task was scheduled (jitter)
##   3.1 Group in ranges of 250 and show 5 biggest clusters
## 4. Calculate how much time it takes to wait all task to be completed after being scheduled
##
##
##   Tasks:    	1000	DONE
##   Setup:     	     092us873ns	         	Initializing
##   Send  100%:	     925us739ns	925ns/task	To schedule tasks
##   Send   28%:	     000us250ns	 282 tasks	+/-250ns
##   Send   23%:	     000us500ns	 238 tasks	+/-250ns
##   Send   23%:	     000us750ns	 237 tasks	+/-250ns
##   Send   11%:	     001us000ns	 116 tasks	+/-250ns
##   Send   05%:	     001us250ns	 055 tasks	+/-250ns
##   Latency 83%:	     000us250ns	 832 tasks	+/-250ns
##   Latency 03%:	     001us500ns	 030 tasks	+/-250ns
##   Latency 02%:	     001us250ns	 025 tasks	+/-250ns
##   Latency 01%:	     001us750ns	 018 tasks	+/-250ns
##   Latency 01%:	     001us000ns	 013 tasks	+/-250ns
##   Join:      	     040us748ns	         	Waiting all tasks to complete
##   Snd+Join:  	     966us487ns	966ns/task	Send + Join
##   Total:     	001ms245us195ns
##

import std/[atomics, monotimes, options]
import proccurl/[dreads_loony, ptrmath, sleez, stats]


when isMainModule:
  proc helloWorld(args, res: pointer): void =
    cast[ptr int64](res)[] = getMonoTime().ticks

  const MAX_ITEMS = 1000

  proc main(): void =
    ## Room for work
    let send  = createShared(int64,   MAX_ITEMS)
    let sent  = createShared(int64,   MAX_ITEMS)
    let args  = createShared(int64,   MAX_ITEMS)
    let res   = createShared(int64,   MAX_ITEMS)
    let tasks = createShared(TaskObj, MAX_ITEMS)
    let epoc = getMonoTime().ticks
    let pool = newPool(2, 8)
    let setu = getMonoTime().ticks

    for i in 0..<MAX_ITEMS:
      args[i] = 0
      tasks[i] = TaskObj(
        idx:  i.int64,
        args: args[i],
        fn:   helloWorld,
        res:  res[i],
      )

      res[i] = 0

      send[i][] = getMonoTime().ticks
      args[i][] = getMonoTime().ticks
      pool.whileSchedule tasks[i].some:
        args[i][] = getMonoTime().ticks
      sent[i][] = getMonoTime().ticks

    let tasksSent = getMonoTime().ticks
    pool.whileJoin:
      spin()

    for i in 0..<MAX_ITEMS:
      assert tasks[i].isDone, "Task " & $i & " not DONE but " & $tasks[i].stat.load & " and res is " & $res[i][]

    let ta = getMonoTime().ticks


    echo "Tasks:    \t", MAX_ITEMS
    echo "Setup:    \t", (setu - epoc).ns, "\t", "         \t"
    
    var range = 50
    let (st12, nd22, rd32, th42, th52) = top_items(cast[ptr UncheckedArray[int64]](send), cast[ptr UncheckedArray[int64]](sent), range, MAX_ITEMS)
    if st12.count > 0: echo "Send¹   ",  st12.perc, ":\t", (st12.time - range).ns, "~", st12.time.ns, "\t", st12.count.zeroFill, " tasks"
    if nd22.count > 0: echo "Send¹   ",  nd22.perc, ":\t", (nd22.time - range).ns, "~", nd22.time.ns, "\t", nd22.count.zeroFill, " tasks"
    if rd32.count > 0: echo "Send¹   ",  rd32.perc, ":\t", (rd32.time - range).ns, "~", rd32.time.ns, "\t", rd32.count.zeroFill, " tasks"
    if th42.count > 0: echo "Send¹   ",  th42.perc, ":\t", (th42.time - range).ns, "~", th42.time.ns, "\t", th42.count.zeroFill, " tasks"
    if th52.count > 0: echo "Send¹   ",  th52.perc, ":\t", (th52.time - range).ns, "~", th52.time.ns, "\t", th52.count.zeroFill, " tasks"
    echo "Total sending:\t", (tasksSent - send[0][]).ns,   ((tasksSent - send[0][]) div MAX_ITEMS).ns, "/task\t", "To schedule tasks"

    range = 50_000
    let (st11, nd21, rd31, th41, th51) = top_items(cast[ptr UncheckedArray[int64]](args), cast[ptr UncheckedArray[int64]](res), range, MAX_ITEMS)
    if st11.count > 0: echo "Latency² ", st11.perc, ":\t", (st11.time - range).ns, "~", st11.time.ns, "\t", st11.count.zeroFill, " tasks"
    if nd21.count > 0: echo "Latency² ", nd21.perc, ":\t", (nd21.time - range).ns, "~", nd21.time.ns, "\t", nd21.count.zeroFill, " tasks"
    if rd31.count > 0: echo "Latency² ", rd31.perc, ":\t", (rd31.time - range).ns, "~", rd31.time.ns, "\t", rd31.count.zeroFill, " tasks"
    if th41.count > 0: echo "Latency² ", th41.perc, ":\t", (th41.time - range).ns, "~", th41.time.ns, "\t", th41.count.zeroFill, " tasks"
    if th51.count > 0: echo "Latency² ", th51.perc, ":\t", (th51.time - range).ns, "~", th51.time.ns, "\t", th51.count.zeroFill, " tasks"

    echo "Join:     \t", (ta - tasksSent).ns, "\t", "         \t", "Waiting all tasks to complete"
    echo "Snd+Join: \t", (ta - send[0][]).ns, ((ta - send[0][]) div MAX_ITEMS).ns, "/task\t", "Send + Join"
    echo "Total:    \t", (ta - epoc).ns
    echo "\n¹ How much time main thread locked scheduling the task\n² How long took to any thread work on task"
 

    freeShared res
    freeShared args
    freeShared sent
    freeShared tasks
    freeShared args
    freePool pool

  main()
