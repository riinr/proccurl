import std/[monotimes, times, atomics]
import proccurl/boring

const SLOTS* {.intdefine: "boring.benchslots".} = 10
const RUNS* {.intdefine: "boring.benchruns".} = 100

var queue = newQueue[SLOTS, SP[SLOTS], MC[SLOTS], MonoTime]()
var results: array[RUNS, array[4, MonoTime]]
var attempts: array[RUNS, array[2, int]]
var idx: Atomic[int]


proc producer(thr: int): void {.thread.} =
  var cur = queue.producer
  var vRD = RD
  var t   = getMonoTime()

  for i in 0..high(results):
    t = getMonoTime()
    var a = 0
    while not queue.enqueue(cur, t, vRD):
      vRD = RD
      inc a
      t = getMonoTime()
    results[i][1]  = getMonoTime()
    results[i][0]  = t
    attempts[i][0] = a


proc consumer(thr: int): void {.thread.} =
  var cur = queue.consumer
  var vWD = WD
  var t   = getMonoTime()
  var ttt = getMonoTime()
  var ii  = idx.load(moRelaxed)

  for i in 0..<(RUNS div 2):
    ttt = getMonoTime()
    var a = 0
    while not queue.dequeue(cur, t, vWD):
      vWD = WD
      inc a
      cur = queue.consumer
      ttt = getMonoTime()
    ii = idx.fetchAdd(1)
    results[ii][3]  = getMonoTime()
    results[ii][2]  = ttt
    attempts[ii][1] = a


proc main(): void =
  idx.store(0)
  var
    thr: array[3, Thread[int]]
  createThread[int](thr[0], producer, 0)
  createThread[int](thr[1], consumer, 1)
  createThread[int](thr[2], consumer, 2)
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
