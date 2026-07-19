import std/[monotimes, posix, strutils]

const ITERATIONS = 1000

proc cpuRelaxOnly(): int64 =
  let start = getMonoTime().ticks
  for _ in 0..<ITERATIONS:
    cpuRelax()
  getMonoTime().ticks - start

proc getMonoTimeOnly(): int64 =
  let start = getMonoTime().ticks
  for _ in 0..<ITERATIONS:
    discard getMonoTime()
  getMonoTime().ticks - start

proc schedYield(): int64 =
  let start = getMonoTime().ticks
  for _ in 0..<ITERATIONS:
    discard posix.sched_yield()
  getMonoTime().ticks - start

proc nanosleep1ns(): int64 =
  let start = getMonoTime().ticks
  var ts: Timespec
  ts.tv_sec = posix.Time 0
  ts.tv_nsec = 1
  for _ in 0..<ITERATIONS:
    discard posix.nanosleep(ts, ts)
  getMonoTime().ticks - start

when isMainModule:
  let r1 = cpuRelaxOnly()
  let r2 = getMonoTimeOnly()
  let r3 = schedYield()
  let r4 = nanosleep1ns()

  echo ""
  echo "Method                          Total ns     Avg ns"
  echo "──────────────────────────────  ──────────── ──────────"
  let a1 = r1 div ITERATIONS
  let a2 = r2 div ITERATIONS
  let a3 = r3 div ITERATIONS
  let a4 = r4 div ITERATIONS
  echo "cpuRelax()                       " & align($r1, 12) & " " & align($a1, 10)
  echo "getMonoTime()                     " & align($r2, 12) & " " & align($a2, 10)
  echo "posix.sched_yield()              " & align($r3, 12) & " " & align($a3, 10)
  echo "posix.nanosleep(1ns)             " & align($r4, 12) & " " & align($a4, 10)
  echo ""
