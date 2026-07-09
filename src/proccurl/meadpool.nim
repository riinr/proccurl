import std/atomics

type
  FreeBlock = object
    next: ptr FreeBlock

  MemPool* = object
    start: ptr UncheckedArray[byte]
    blockSize: int
    total: int
    avail: Atomic[int]
    head: Atomic[ptr FreeBlock]

proc createMemPool*(blockSize, count: int): ptr MemPool =
  doAssert blockSize >= sizeof(ptr FreeBlock), "blockSize too small: " & $blockSize & " < " & $sizeof(ptr FreeBlock)
  doAssert count > 0, "count must be positive, got " & $count
  let allocSize = sizeof(MemPool) + blockSize * count
  result = cast[ptr MemPool](allocShared(allocSize))
  result.blockSize = blockSize
  result.total = count
  result.avail.store(count, moRelaxed)
  result.start = cast[ptr UncheckedArray[byte]](cast[int](result) + sizeof(MemPool))
  var prev = cast[ptr FreeBlock](result.start)
  for i in 1..<count:
    let cur = cast[ptr FreeBlock](cast[int](result.start) + i * blockSize)
    prev.next = cur
    prev = cur
  prev.next = nil
  result.head.store(cast[ptr FreeBlock](result.start), moRelease)

proc delete*(pool: ptr MemPool): void =
  if pool != nil:
    deallocShared(pool)

proc alloc*[T](pool: ptr MemPool; t: typedesc[T]): ptr T =
  doAssert sizeof(T) <= pool.blockSize, "type too large: " & $sizeof(T) & " > " & $pool.blockSize
  var head = pool.head.load(moRelaxed)
  while true:
    if head == nil:
      return nil
    let next = head.next
    if pool.head.compareExchange(head, next, moAcquire, moRelaxed):
      pool.avail.atomicDec
      return cast[ptr T](head)

proc dealloc*(pool: ptr MemPool; p: pointer): void =
  if p == nil: return
  var blk = cast[ptr FreeBlock](p)
  while true:
    var head = pool.head.load(moRelaxed)
    blk.next = head
    if pool.head.compareExchange(head, blk, moRelease, moRelaxed):
      pool.avail.atomicInc
      return

proc len*(pool: ptr MemPool): int =
  pool.total

proc available*(pool: ptr MemPool): int =
  pool.avail.load(moRelaxed)

proc used*(pool: ptr MemPool): int =
  pool.total - pool.available

when isMainModule:
  proc main: void =
    let pool = createMemPool(64, 10)
    assert pool.len       == 10
    assert pool.available == 10
    assert pool.used      == 0

    let a = pool.alloc(int)
    assert a != nil
    assert pool.available == 9
    assert pool.used == 1
    a[] = 42
    assert a[] == 42

    let b = pool.alloc(array[4, int])
    assert b != nil
    assert pool.available == 8
    b[0] = 1
    b[3] = 4

    pool.dealloc(a)
    assert pool.available == 9
    assert pool.used == 1

    let c = pool.alloc(int)
    assert c != nil
    assert c == a
    assert pool.available == 8

    pool.dealloc(b)
    pool.dealloc(c)
    assert pool.available == 10
    assert pool.used == 0

    pool.delete
    echo "OK"

  main()
