import std/[monotimes, times, atomics]
import proccurl/boring

const SLOTS* {.intdefine: "boring.benchslots".} = 10
const RUNS* {.intdefine: "boring.benchruns".} = 100

var queue = newQueue[SLOTS, MP[SLOTS], MC[SLOTS], MonoTime]()
var results: array[RUNS, array[4, MonoTime]]
var attempts: array[RUNS, array[2, int]]
var pidx: Atomic[int]
var cidx: Atomic[int]


proc producer(thr: int): void {.thread.} =
  var cur = queue.producer
  var vRD = RD
  var t   = getMonoTime()
  var ii  = pidx.load(moRelaxed)

  for i in 0..<(RUNS div 2):
    t = getMonoTime()
    var a = 0
    while not queue.enqueue(cur, t, vRD):
      vRD = RD
      cur = queue.producer
      inc a
      t = getMonoTime()
    ii = pidx.fetchAdd(1)
    results[ii][1]  = getMonoTime()
    results[ii][0]  = t
    attempts[ii][0] = a


proc consumer(thr: int): void {.thread.} =
  var cur = queue.consumer
  var vWD = WD
  var t   = getMonoTime()
  var ttt = getMonoTime()
  var ii  = cidx.load(moRelaxed)

  for i in 0..<(RUNS div 2):
    ttt = getMonoTime()
    var a = 0
    while not queue.dequeue(cur, t, vWD):
      vWD = WD
      cur = queue.consumer
      inc a
      ttt = getMonoTime()
    ii    = cidx.fetchAdd(1)
    results[ii][3]  = getMonoTime()
    results[ii][2]  = ttt
    attempts[ii][1] = a


proc main(): void =
  pidx.store(0)
  cidx.store(0)
  var
    thr: array[4, Thread[int]]
  createThread[int](thr[0], producer, 0)
  createThread[int](thr[1], producer, 1)
  createThread[int](thr[2], consumer, 2)
  createThread[int](thr[3], consumer, 3)
  joinThreads[int](thr)
  echo("Send\tRecv\tLate\tSRetry\tRRetry")
  for i in 0..high(results):
    echo(   inNanoseconds(results[i][1] - results[i][0]),
      "\t", inNanoseconds(results[i][3] - results[i][2]),
      "\t", inNanoseconds(results[i][3] - results[i][1]),
      "\t", attempts[i][0],
      "\t", attempts[i][1],
    )

main()
