import std/[monotimes, times]
import proccurl/boring

const SLOTS* {.intdefine: "boring.benchslots".} = 10
const RUNS* {.intdefine: "boring.benchruns".} = 100

var queue = newQueue[SLOTS, SP[SLOTS], SC[SLOTS], MonoTime]()
var results: array[RUNS, array[4, MonoTime]]
var attempts: array[RUNS, array[2, int]]


proc producer(): void {.thread.} =
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


proc consumer(): void {.thread.} =
  var cur = queue.consumer
  var vWD = WD
  var t   = getMonoTime()
  var ttt = getMonoTime()
  for i in 0..high(results):
    ttt = getMonoTime()
    var a = 0
    while not queue.dequeue(cur, t, vWD):
      vWD = WD
      inc a
      ttt = getMonoTime()
    results[i][3]  = getMonoTime()
    results[i][2]  = ttt
    attempts[i][1] = a


proc main(): void =
  var
    thr: array[2, Thread[void]]
  createThread[void](thr[0], producer)
  createThread[void](thr[1], consumer)
  joinThreads[void](thr)
  echo("Send\tRecv\tLate\tSRetry\tRRetry")
  for i in 0..high(results):
    echo(   inNanoseconds(results[i][1] - results[i][0]),
      "\t", inNanoseconds(results[i][3] - results[i][2]),
      "\t", inNanoseconds(results[i][3] - results[i][1]),
      "\t", attempts[i][0],
      "\t", attempts[i][1],
    )

main()
