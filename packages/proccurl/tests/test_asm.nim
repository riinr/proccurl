import std/unittest
import proccurl/ebpf
import proccurl/ebpf_asm

test "mov imm and exit":
  let prog = ebpf:
    mov r0, 42
    exit
  var vm = initVm()
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 42

test "alu64 add registers":
  let prog = ebpf:
    mov r1, 10
    mov r2, 32
    mov r0, 0
    add64 r0, r1
    add64 r0, r2
    exit
  var vm = initVm()
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 42

test "alu64 add immediate":
  let prog = ebpf:
    mov r0, 10
    add64 r0, 32
    exit
  var vm = initVm()
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 42

test "conditional jump jeq":
  let prog = ebpf:
    mov r0, 1
    mov r1, 1
    jeq r0, r1, +1
    mov r0, 0
    exit
  var vm = initVm()
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 1

test "conditional jump with imm":
  let prog = ebpf:
    mov r0, 42
    jeq r0, 42, +1
    mov r0, 0
    exit
  var vm = initVm()
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 42

test "jne takes branch":
  let prog = ebpf:
    mov r0, 1
    mov r1, 99
    jne r1, r1, +1
    mov r0, 0
    exit
  var vm = initVm()
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 0

test "exit only":
  let prog = ebpf:
    exit
  var vm = initVm()
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 0

test "alu64 sub":
  let prog = ebpf:
    mov r0, 100
    sub64 r0, 58
    exit
  var vm = initVm()
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 42

test "alu64 mul":
  let prog = ebpf:
    mov r0, 6
    mul64 r0, 7
    exit
  var vm = initVm()
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 42

test "alu64 or/and/xor":
  let prog = ebpf:
    mov r0, 0xFF
    and64 r0, 0x0F
    exit
  var vm = initVm()
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 0x0F

test "alu64 lsh/rsh":
  let prog = ebpf:
    mov r0, 1
    lsh64 r0, 5
    rsh64 r0, 2
    exit
  var vm = initVm()
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 8

test "ja unconditional jump":
  let prog = ebpf:
    mov r0, 0
    ja +2
    mov r0, 1
    mov r0, 2
    exit
  var vm = initVm()
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 0

test "jgt signed comparison":
  let prog = ebpf:
    mov r0, 10
    mov r1, 5
    jgt r0, r1, +1
    mov r0, 0
    exit
  var vm = initVm()
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 10

test "jge with immediate":
  let prog = ebpf:
    mov r0, 10
    jge r0, 10, +1
    mov r0, 0
    exit
  var vm = initVm()
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 10

test "lddw 64-bit immediate":
  let prog = ebpf:
    lddw r0, 0xABCD
    exit
  var vm = initVm()
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 0xABCD

test "lddw large value":
  let prog = ebpf:
    lddw r0, 0x100000000
    exit
  var vm = initVm()
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 0x100000000.uint64

test "stx/ldx stack":
  let prog = ebpf:
    mov r1, 42
    stx_dw r10, r1, -8
    mov r0, 0
    ldx_dw r0, r10, -8
    exit
  var vm = initVm()
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 42

test "stx_b byte store":
  let prog = ebpf:
    mov r1, 0xFF
    stx_b r10, r1, -1
    mov r0, 0
    ldx_b r0, r10, -1
    exit
  var vm = initVm()
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 0xFF

test "call helper":
  proc answer(vm: ptr EbpfVm; args: array[5, uint64]): uint64 {.nimcall.} = 42
  let prog = ebpf:
    call 0
    exit
  var vm = initVm()
  vm.addHelper(0, answer)
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 42

test "neg64":
  let prog = ebpf:
    mov r0, 42
    neg64 r0
    exit
  var vm = initVm()
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == cast[uint64](-42)

test "jsgt signed greater than":
  let prog = ebpf:
    mov r0, 5
    lddw r1, 0xFFFFFFFF  # r1 = -1 as signed
    jsgt r0, r1, +1       # 5 > -1 (signed), skip next
    mov r0, 0
    exit
  var vm = initVm()
  vm.load(prog)
  discard vm.verify()
  check vm.exec() == 5
