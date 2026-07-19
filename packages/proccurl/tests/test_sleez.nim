import std/[monotimes, times, unittest]
import proccurl/sleez

test "Constructors create distinct types":
  let
    s = 5.s
    ms = 500.ms
    us = 500_000.us
    ns = 500_000_000.ns
  check cast[int64](s)  == 5
  check cast[int64](ms) == 500
  check cast[int64](us) == 500_000
  check cast[int64](ns) == 500_000_000

test "Down-converters (big → small via converters)":
  let
    s  = 1.s
    ms = ms(s)
    us = us(s)
    ns = ns(s)
  check cast[int64](ms)   == 1000
  check cast[int64](us)   == 1_000_000
  check cast[int64](ns) == 1_000_000_000

test "Up-converters (small → big via converters)":
  let
    sFromNs     = ss(5_000_000_000.ns)
    sFromUs     = ss(5_000_000.us)
    sFromMs     = ss(5000.ms)
    msFromNs    = sm(5_000_000_000.ns)
    msFromUs    = sm(5_000_000.us)
    usFromNs    = su(5_000_000.ns)
  check cast[int64](sFromNs)  == 5
  check cast[int64](sFromUs)  == 5
  check cast[int64](sFromMs)  == 5
  check cast[int64](msFromNs) == 5000
  check cast[int64](msFromUs) == 5000
  check cast[int64](usFromNs) == 5000

test "String conversion contains unit suffix":
  let
    s  = $1.s
    ms = $(500).ms
    us = $(500).us
    ns = $(500).ns
  check s  == "\e[31m001s\e[0m"
  check ms == "\e[30m000s\e[0m\e[33m500ms\e[0m"
  check us == "\e[30m000s\e[0m\e[30m000ms\e[0m\e[34m500us\e[0m"
  check ns == "\e[30m000s\e[0m\e[30m000ms\e[0m\e[30m000us\e[0m\e[32m500ns\e[0m"

test "String conversion zero value is gray":
  let zs = $0.s
  let zms = $0.ms
  check zs == "\e[30m000s\e[0m"
  check zms == "\e[30m000s\e[0m\e[30m000ms\e[0m"

test "Addition":
  check cast[int64](1.s  + 1.ms) == 1001
  check cast[int64](1.s  + 1.us) == 1000_001
  check cast[int64](1.s  + 1.ns) == 1000_000_001
  check cast[int64](1.ms + 1.us) == 1001
  check cast[int64](1.ms + 1.ns) == 1000_001
  check cast[int64](1.us + 1.ns) == 1001

test "Subtraction":
  check cast[int64](2.s  - 1.s)  == 1
  check cast[int64](1.s  - 1.ms) == 999
  check cast[int64](1.s  - 1.us) == 999_999
  check cast[int64](1.s  - 1.ns) == 999_999_999

test "Multiplication":
  check cast[int64](2.s  * 3.s)   == 6
  check cast[int64](2.s  * 3.ms)  == 6000
  check cast[int64](2.s  * 3.us)  == 6000_000
  check cast[int64](2.s  * 3.ns)  == 6000_000_000
  check cast[int64](2.ms * 3.ms)  == 6
  check cast[int64](2.ms * 3.us)  == 6000
  check cast[int64](2.ms * 3.ns)  == 6000_000
  check cast[int64](2.us * 3.us)  == 6
  check cast[int64](2.us * 3.ns)  == 6000
  check cast[int64](2.ns * 3.ns)  == 6

test "sleep waits at least requested time":
  let start = getMonoTime()
  sleep 10_000_000.ns  # 10ms
  let elapsed = getMonoTime() - start
  check inNanoseconds(elapsed) >= 10_000_000

test "spin discards result by default":
  let start = getMonoTime()
  discard spin 10_000_000.ns  # 10ms
  let elapsed = getMonoTime() - start
  check inNanoseconds(elapsed) >= 10_000_000

test "spin returns elapsed nanoseconds":
  let elapsed = spin 10_000_000.ns
  check elapsed >= 10_000_000

test "spin with small value uses cpuRelax":
  let elapsed = spin 100.ns
  check elapsed >= 100

test "spin with medium value uses sched_yield":
  let elapsed = spin 10_000.ns
  check elapsed >= 10_000

test "progSpin iterates increases time":
  var count = 0
  var spinner = progSpin
  while count < 20:
    count.inc
    let elapsed = spinner()
    if   count <= 3:
      check elapsed >= 001
      check elapsed <= 200
    elif count <= 6:
      check elapsed >= 100
      check elapsed <= 400
    elif count <= 16:
      check elapsed >= 300
      check elapsed <= 700
    elif count <= 18:
      check elapsed >= 050_000
      check elapsed <= 200_000
    elif count <= 20:
      check elapsed >= 001
      check elapsed <= 200


test "progSpin iterates reset":
  var count = 0
  var spinner = progSpin
  while count < 8:
    count.inc
    let elapsed =
      if count == 7:
        spinner = progSpin
        spinner()
      else:
        spinner()
    if   count <= 3 or count > 6:
      check elapsed >= 001
      check elapsed <= 200
    elif count <= 6:
      check elapsed >= 100
      check elapsed <= 400
