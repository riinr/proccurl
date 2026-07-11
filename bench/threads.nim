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

import std/monotimes
import proccurl/[ptrmath, sleez, stats]


when isMainModule:
  proc helloWorld(res: ptr int64): void =
    res[] = getMonoTime().ticks

  const MAX_ITEMS = 1000

  proc main(): void =
    ## Room for work
    let send = createShared(int64,   MAX_ITEMS)
    let sent = createShared(int64,   MAX_ITEMS)
    let res  = createShared(int64,   MAX_ITEMS)
    let epoc = getMonoTime().ticks
    let thrs = createShared(Thread[ptr int64], MAX_ITEMS)
    let setu = getMonoTime().ticks

    for i in 0..<MAX_ITEMS:
      res[i] = 0
      send[i][] = getMonoTime().ticks
      createThread(thrs[i][], helloWorld, res[i])
      sent[i][] = getMonoTime().ticks

    let tasksSent = getMonoTime().ticks
    for i in 0..<MAX_ITEMS:
      thrs[i][].joinThread()

    let ta = getMonoTime().ticks


    echo "Tasks:    \t", MAX_ITEMS
    echo "Setup:    \t", (setu - epoc).ns, "\t", "         \t"
    
    var range = 10000
    let (st12, nd22, rd32, th42, th52) = top_items(cast[ptr UncheckedArray[int64]](send), cast[ptr UncheckedArray[int64]](sent), range, MAX_ITEMS)
    printCluster(st12, nd22, rd32, th42, th52, range, "Send¹   ")
    printTotalSending(tasksSent - send[0][], (tasksSent - send[0][]) div MAX_ITEMS)

    var sendCost = newSeq[int64](MAX_ITEMS)
    for i in 0..<MAX_ITEMS:
       sendCost[i] = (sent[i][] - send[i][]) div 1000

    range = 10000
    let (st11, nd21, rd31, th41, th51) = top_items(cast[ptr UncheckedArray[int64]](send), cast[ptr UncheckedArray[int64]](res), range, MAX_ITEMS)
    printCluster(st11, nd21, rd31, th41, th51, range, "Latency² ")

    printJoinSummary(ta - tasksSent, ta - send[0][], ta - epoc, MAX_ITEMS)
    echo "\n¹ How much time main thread locked scheduling the task\n² How long took to any thread work on task"
 
    #echo plot(sendCost)
    freeShared send
    freeShared res
    freeShared sent

  main()
