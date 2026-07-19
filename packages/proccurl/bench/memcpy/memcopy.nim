import std/[macros, monotimes, strformat, strutils, times]
import chicks


# https://forum.nim-lang.org/t/9504
macro unroll(x: static int, name, body: untyped) =
  result = newStmtList()
  var a = 512
  while a < x:
    a = a * 2
    result.add newBlockStmt newStmtList(
      newConstStmt(name, newLit a),
      copy body
    )
    result.add newBlockStmt newStmtList(
      newConstStmt(name, newLit (a + (a div 2))),
      copy body
    )
    result.add newBlockStmt newStmtList(
      newConstStmt(name, newLit (a + (a div 2) + (a div 4))),
      copy body
    )
    result.add newBlockStmt newStmtList(
      newConstStmt(name, newLit (a + (a div 2) + (a div 4) + (a div 8))),
      copy body
    )
    result.add newBlockStmt newStmtList(
      newConstStmt(name, newLit (a + (a div 2) + (a div 4) + (a div 8) + (a div 16))),
      copy body
    )


template timeInNS(body: untyped): int64 =
  var
    start = getMonotime()
    endt  = getMonotime()
    noise = (endt - start).inNanoseconds

  start = getMonotime()
  body
  endt  = getMonotime()
  abs((endt - start).inNanoseconds - noise) + 1


template ticks(body: untyped): int64 =
  var 
    start = getCpuTicksStart()
    endt  = getCpuTicksEnd()
    noise = endt - start

  start = getCpuTicksStart()
  body
  endt  = getCpuTicksEnd()
  abs(endt - start - noise) + 1


proc cope(size: static int): void =
  var 
    bufferA = create(uint8, size)
    bufferB = create(uint8, size)
    chicks  = ticks:
      copyMem bufferB, bufferA, size
    tns     = timeInNS:
      copyMem bufferA, bufferB, size

  echo &"{size:>8} bytes, {chicks:>8} ticks, {(size div chicks):>4} B/tick, {tns:>8} ns, {(size div tns):>4} B/ns"


const maxSize {.intdefine: ".maxSize".} = 262144

unroll(maxSize, size):
  cope(size)
  cope(size)

