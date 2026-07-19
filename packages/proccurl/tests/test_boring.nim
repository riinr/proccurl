import std/[atomics, unittest]

import proccurl/boring

const SLOTS = 2
const ARENA_LEN = static  sizeOfQ[SLOTS, uint8]()


test "Fail with arena smaller than required":
  var arena: array[1, uint8]
  expect(AssertionDefect):
    discard newQueue[SLOTS, SP[SLOTS], SC[SLOTS], uint8](addr arena, arena.len)


test "Works with appropriate size":
  var arena: array[ARENA_LEN, uint8]
  discard newQueue[SLOTS, SP[SLOTS], SC[SLOTS], uint8](addr arena, arena.len)


test "Can enqueue":
  var queue = newQueue[SLOTS, SP[SLOTS], SC[SLOTS], uint8]()
  
  # 0 to 1
  var cur   = queue.producer
  let fst   = cur
  check cast[uint32](cur) == 0
  check queue.sizes(cur)  == 0.uint32
  var value = 2'u8
  var vRD   = RD
  check queue.enqueue(cur, value, vRD)
  check queue.sizes(fst)  == 1'u32
  check cast[uint32](cur) == 1
  check cast[uint32](cur) != cast[uint32](fst)
  check cast[uint32](cur) == cast[uint32](queue.producer)
  # 1 to 2 to 0 (since two is out of range reset to 0)
  let snd   = cur
  check queue.sizes(snd)  == 0'u32
  check queue.enqueue(cur, value, vRD)
  check queue.sizes(snd)  == 1'u32
  check cast[uint32](cur) == 0
  check cast[uint32](cur) != cast[uint32](snd)
  check cast[uint32](cur) == cast[uint32](queue.producer)
  # 0 to 0 (is full)
  check not queue.enqueue(cur, value, vRD)
  check cast[uint32](cur) == 0
  check cast[uint32](cur) == cast[uint32](queue.producer)
  check WD == vRD
  # 0 to 0 (is full, first implementation failed in this last test)
  vRD = RD
  check not queue.enqueue(cur, value, vRD)
  check cast[uint32](cur) == 0
  check cast[uint32](cur) == cast[uint32](queue.producer)
  check WD == vRD


test "Can dequeue":
  var queue = newQueue[SLOTS, SP[SLOTS], SC[SLOTS], uint8]()
  
  # 0 to 1 W
  var cur   = queue.producer
  var value = 2'u8
  var vRD   = RD
  check queue.enqueue(cur, value, vRD)
  # 0 to 1 R
  var rdr   = queue.consumer
  var vWD   = WD
  check cast[uint32](rdr)   == 0'u32
  check queue.stats(rdr)    == WD
  var r0: uint8
  check queue.dequeue(rdr, r0, vWD)
  check r0                  == 2'u8
  check cast[uint32](rdr)   == 1'u32
  # 1 to 2 W
  check queue.enqueue(cur, value, vRD)
  # 1 to 2 to 0 W (since two is out of range reset to 0)
  var r1: uint8
  check queue.dequeue(rdr, r1, vWD)
  check r1                  == 2'u8
  check cast[uint32](rdr)   == 0'u32
  # 0 to 0 (is empty)
  var r2: uint8
  check not queue.dequeue(rdr, r2, vWD)
  check cast[uint32](rdr)   == 0'u32
  check vWD                 == RD
  # 0 to 0 (is empty)
  var r3: uint8
  vWD = WD
  check not queue.dequeue(rdr, r3, vWD)
  check cast[uint32](rdr)   == 0'u32
  check vWD                 == RD
