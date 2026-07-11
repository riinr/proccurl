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
import proccurl/[dreads_loony_workers, ptrmath, sleez, stats]


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
    let pool = newPool(2, 10)
    let setu = getMonoTime().ticks

    for i in 0..<MAX_ITEMS:
      args[i] = 0
      tasks[i] = TaskObj(
        idx:  i.int64,
        args: args[i],
        req:  helloWorld,
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
    
    var range = 200
    let (st12, nd22, rd32, th42, th52) = top_items(cast[ptr UncheckedArray[int64]](send), cast[ptr UncheckedArray[int64]](sent), range, MAX_ITEMS)
    printCluster(st12, nd22, rd32, th42, th52, range, "Send¹   ")
    printTotalSending(tasksSent - args[0][], (tasksSent - args[0][]) div MAX_ITEMS)

    range = 200
    let (st11, nd21, rd31, th41, th51) = top_items(cast[ptr UncheckedArray[int64]](args), cast[ptr UncheckedArray[int64]](res), range, MAX_ITEMS)
    printCluster(st11, nd21, rd31, th41, th51, range, "Latency² ")

    printJoinSummary(ta - tasksSent, ta - args[0][], ta - epoc, MAX_ITEMS)
    echo "\n¹ How much time main thread locked scheduling the task\n² How long took to any thread work on task"
 

    freeShared res
    freeShared args
    freeShared sent
    freeShared tasks
    freeShared args
    freePool pool

  main()
