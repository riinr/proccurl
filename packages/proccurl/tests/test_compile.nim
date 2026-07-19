import std/unittest
import proccurl/ebpf
import proccurl/ebpf_compile

test "return literal":
  let prog = compileEbpf:
    return 42
  var vm = initVm()
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 42

test "return via var":
  let prog = compileEbpf:
    var x = 42
    return x
  var vm = initVm()
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 42

test "add two vars":
  let prog = compileEbpf:
    var x = 10
    var y = 32
    return x + y
  var vm = initVm()
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 42

test "arithmetic chain":
  let prog = compileEbpf:
    var x = 100
    x = x - 30
    x = x - 28
    return x
  var vm = initVm()
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 42

test "mul and div":
  let prog = compileEbpf:
    var x = 6
    var y = 7
    var z = x * y
    return z
  var vm = initVm()
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 42

test "bitwise and/or/xor":
  let prog = compileEbpf:
    var x = 0xFF
    var y = x and 0x0F
    return y
  var vm = initVm()
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 0x0F

test "shift":
  let prog = compileEbpf:
    var x = 1
    x = x shl 5
    x = x shr 2
    return x
  var vm = initVm()
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 8

test "if true":
  let prog = compileEbpf:
    var x = 0
    if 1 == 1:
      x = 42
    return x
  var vm = initVm()
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 42

test "if false":
  let prog = compileEbpf:
    var x = 0
    if 1 == 2:
      x = 42
    return x
  var vm = initVm()
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 0

test "if/else":
  let prog = compileEbpf:
    var x = 0
    if 1 == 1:
      x = 42
    else:
      x = 99
    return x
  var vm = initVm()
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 42

test "if/else take else":
  let prog = compileEbpf:
    var x = 0
    if 1 == 2:
      x = 42
    else:
      x = 99
    return x
  var vm = initVm()
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 99

test "comparison expressions":
  let prog = compileEbpf:
    var x = 0
    if 5 > 3:
      x = 42
    else:
      x = 0
    return x
  var vm = initVm()
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 42

test "while loop":
  let prog = compileEbpf:
    var x = 0
    while x < 10:
      x = x + 1
    return x
  var vm = initVm()
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 10

test "nested expression":
  let prog = compileEbpf:
    var x = (1 + 2) * (3 + 4)
    return x
  var vm = initVm()
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 21

test "negation":
  let prog = compileEbpf:
    var x = 42
    return -x + 84
  var vm = initVm()
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 42

test "fibonacci with var":
  let prog = compileEbpf:
    var a = 0
    var b = 1
    var i = 0
    while i < 10:
      var t = a + b
      a = b
      b = t
      i = i + 1
    return a
  var vm = initVm()
  vm.load(prog)
  discard vm.verify()
  var result = vm.exec()
  check result == 55  # fib(11) = 89, so fib(10) = 55? let me check... fib(0)=0, fib(1)=1, fib(10)=55

test "multiple if/elif/else":
  let prog = compileEbpf:
    var x = 2
    var result = 0
    if x == 1:
      result = 10
    elif x == 2:
      result = 42
    elif x == 3:
      result = 30
    else:
      result = 99
    return result
  var vm = initVm()
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 42

test "discard":
  let prog = compileEbpf:
    var x = 0
    discard 1 + 2
    x = 42
    return x
  var vm = initVm()
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 42

test "call helper":
  proc answer(vm: ptr EbpfVm; args: array[5, uint64]): uint64 {.nimcall.} = 42
  let prog = compileEbpf:
    return call(0)
  var vm = initVm()
  vm.addHelper(0, answer)
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 42

test "call helper with args":
  proc add(vm: ptr EbpfVm; args: array[5, uint64]): uint64 {.nimcall.} = args[0] + args[1]
  let prog = compileEbpf:
    return call(1, 20, 22)
  var vm = initVm()
  vm.addHelper(1, add)
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 42

test "call as statement":
  proc answer(vm: ptr EbpfVm; args: array[5, uint64]): uint64 {.nimcall.} = 42
  let prog = compileEbpf:
    call(0)
    return
  var vm = initVm()
  vm.addHelper(0, answer)
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 42

test "call without parens":
  proc add(vm: ptr EbpfVm; args: array[5, uint64]): uint64 {.nimcall.} = args[0] + args[1]
  let prog = compileEbpf:
    call 1, 20, 22
    return
  var vm = initVm()
  vm.addHelper(1, add)
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 42

test "array store and load":
  let prog = compileEbpf:
    var arr: array[10, int]
    arr[0] = 42
    return arr[0]
  var vm = initVm()
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 42

test "array different indices":
  let prog = compileEbpf:
    var arr: array[10, int]
    arr[3] = 42
    arr[7] = 99
    return arr[3]
  var vm = initVm()
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 42

test "array dynamic index":
  let prog = compileEbpf:
    var arr: array[10, int]
    var i = 0
    arr[0] = 42
    arr[1] = 99
    return arr[i]
  var vm = initVm()
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 42

test "array in expression":
  let prog = compileEbpf:
    var arr: array[10, int]
    arr[0] = 20
    arr[1] = 22
    return arr[0] + arr[1]
  var vm = initVm()
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 42

test "multiple arrays":
  let prog = compileEbpf:
    var a: array[5, int]
    var b: array[5, int]
    a[0] = 30
    b[0] = 12
    return a[0] + b[0]
  var vm = initVm()
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 42
