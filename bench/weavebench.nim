##
## The objective of this benchmark is following:
## 1. Calculate the thread pool creation overhead
## 2. Calculate how much time is required to send/schedule 1000 tasks
##   2.1 Calculate the avg
##   2.2 Group in ranges of 250 and show 5 biggest clusters
## 3. Calculate how much time was lot after task has been scheduled (jitter)
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
import proccurl/[sleez, stats]
import weave

const MAX_ITEMS = 1000

type
  Sa = object
    idx: int
    res: ptr UncheckedArray[int64]

proc work(sa: Sa): int64 {.gcsafe.} =
  result = getMonoTime().ticks
  sa.res[sa.idx] = result

when isMainModule:
  proc main(): void =
    let send_all = cast[ptr UncheckedArray[int64]](allocShared0(sizeof(int64) * MAX_ITEMS))
    let sent_all = cast[ptr UncheckedArray[int64]](allocShared0(sizeof(int64) * MAX_ITEMS))
    let args_all = cast[ptr UncheckedArray[int64]](allocShared0(sizeof(int64) * MAX_ITEMS))
    let res_all  = cast[ptr UncheckedArray[int64]](allocShared0(sizeof(int64) * MAX_ITEMS))
    var fvs = newSeq[Flowvar[int64]](MAX_ITEMS)

    let epoc = getMonoTime().ticks
    init(Weave)
    let setu = getMonoTime().ticks

    for i in 0..<MAX_ITEMS:
      send_all[i] = getMonoTime().ticks
      args_all[i] = getMonoTime().ticks
      fvs[i] = spawn work(Sa(idx: i, res: res_all))
      sent_all[i] = getMonoTime().ticks

    let tasksSent = getMonoTime().ticks

    for i in 0..<MAX_ITEMS:
      discard sync(fvs[i])

    let ta = getMonoTime().ticks
    exit(Weave)

    echo "Tasks:    \t", MAX_ITEMS
    echo "Setup:    \t", (setu - epoc).ns, "\t", "         \t"

    var range = 200
    let (st12, nd22, rd32, th42, th52) = top_items(send_all, sent_all, range, MAX_ITEMS)
    printCluster(st12, nd22, rd32, th42, th52, range, "Send¹   ")
    printTotalSending(tasksSent - args_all[0], (tasksSent - args_all[0]) div MAX_ITEMS)

    range = 100_000
    let (st11, nd21, rd31, th41, th51) = top_items(args_all, res_all, range, MAX_ITEMS)
    printCluster(st11, nd21, rd31, th41, th51, range, "Latency² ")

    printJoinSummary(ta - tasksSent, ta - args_all[0], ta - epoc, MAX_ITEMS)
    echo "\n¹ How much time main thread locked scheduling the task\n² How long took to any thread work on task"

    deallocShared(send_all)
    deallocShared(sent_all)
    deallocShared(args_all)
    deallocShared(res_all)

  main()
