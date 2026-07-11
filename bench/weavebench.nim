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

import std/[monotimes, tables]
import proccurl/[sleez]
import weave

const MAX_ITEMS = 1000

type
  Sa = object
    idx: int
    res: ptr UncheckedArray[int64]

proc work(sa: Sa): int64 {.gcsafe.} =
  result = getMonoTime().ticks
  sa.res[sa.idx] = result

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
  if i < 10:
    "0" & $i & "%"
  else:
    $i & "%"

proc cluster(i: int64; d: int): int64 =
  i div d * d

proc top_items(a, b: ptr UncheckedArray[int64]; clstr, I: int): Top =
  var h = initTable[int64, int]()

  for i in 1..<I:
    let k = cluster(b[i] - a[i], clstr)
    discard h.hasKeyOrPut(k, 0)
    h[k].inc

  var st1: Pos
  var nd2: Pos
  var rd3: Pos
  var th4: Pos
  var th5: Pos

  for k, v in h.pairs():
    if   v > st1.count:
      th5.time  = th4.time
      th5.count = th4.count
      th4.time  = rd3.time
      th4.count = rd3.count
      rd3.time  = nd2.time
      rd3.count = nd2.count
      nd2.time  = st1.time
      nd2.count = st1.count
      st1.time  = k + clstr
      st1.count = v
    elif v > nd2.count:
      th5.time  = th4.time
      th5.count = th4.count
      th4.time  = rd3.time
      th4.count = rd3.count
      rd3.time  = nd2.time
      rd3.count = nd2.count
      nd2.time  = k + clstr
      nd2.count = v
    elif v > rd3.count:
      th5.time  = th4.time
      th5.count = th4.count
      th4.time  = rd3.time
      th4.count = rd3.count
      rd3.time  = k + clstr
      rd3.count = v
    elif v > th4.count:
      th5.time  = th4.time
      th5.count = th4.count
      th4.time  = k + clstr
      th4.count = v
    elif v > th5.count:
      th5.time  = k + clstr
      th5.count = v

  st1.perc = Perc(tot: I, part: st1.count)
  nd2.perc = Perc(tot: I, part: nd2.count)
  rd3.perc = Perc(tot: I, part: rd3.count)
  th4.perc = Perc(tot: I, part: th4.count)
  th5.perc = Perc(tot: I, part: th5.count)
  (st1, nd2, rd3, th4, th5)

template zeroFill(t: int64): string =
  if   t < 010: "00" & $t
  elif t < 100:  "0" & $t
  else:                $t

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
    if st12.count > 0: echo "Send¹   ",  st12.perc, ":\t", (st12.time - range).ns, "~", st12.time.ns, "\t", st12.count.zeroFill, " tasks"
    if nd22.count > 0: echo "Send¹   ",  nd22.perc, ":\t", (nd22.time - range).ns, "~", nd22.time.ns, "\t", nd22.count.zeroFill, " tasks"
    if rd32.count > 0: echo "Send¹   ",  rd32.perc, ":\t", (rd32.time - range).ns, "~", rd32.time.ns, "\t", rd32.count.zeroFill, " tasks"
    if th42.count > 0: echo "Send¹   ",  th42.perc, ":\t", (th42.time - range).ns, "~", th42.time.ns, "\t", th42.count.zeroFill, " tasks"
    if th52.count > 0: echo "Send¹   ",  th52.perc, ":\t", (th52.time - range).ns, "~", th52.time.ns, "\t", th52.count.zeroFill, " tasks"
    echo "Total sending:\t", (tasksSent - args_all[0]).ns,   ((tasksSent - args_all[0]) div MAX_ITEMS).ns, "/task\t", "To schedule tasks"

    range = 100_000
    let (st11, nd21, rd31, th41, th51) = top_items(args_all, res_all, range, MAX_ITEMS)
    if st11.count > 0: echo "Latency² ", st11.perc, ":\t", (st11.time - range).ns, "~", st11.time.ns, "\t", st11.count.zeroFill, " tasks"
    if nd21.count > 0: echo "Latency² ", nd21.perc, ":\t", (nd21.time - range).ns, "~", nd21.time.ns, "\t", nd21.count.zeroFill, " tasks"
    if rd31.count > 0: echo "Latency² ", rd31.perc, ":\t", (rd31.time - range).ns, "~", rd31.time.ns, "\t", rd31.count.zeroFill, " tasks"
    if th41.count > 0: echo "Latency² ", th41.perc, ":\t", (th41.time - range).ns, "~", th41.time.ns, "\t", th41.count.zeroFill, " tasks"
    if th51.count > 0: echo "Latency² ", th51.perc, ":\t", (th51.time - range).ns, "~", th51.time.ns, "\t", th51.count.zeroFill, " tasks"

    echo "Join:     \t", (ta - tasksSent).ns, "\t", "         \t", "Waiting all tasks to complete"
    echo "Snd+Join: \t", (ta - args_all[0]).ns, ((ta - args_all[0]) div MAX_ITEMS).ns, "/task\t", "Send + Join"
    echo "Total:    \t", (ta - epoc).ns
    echo "\n¹ How much time main thread locked scheduling the task\n² How long took to any thread work on task"

    deallocShared(send_all)
    deallocShared(sent_all)
    deallocShared(args_all)
    deallocShared(res_all)

  main()
