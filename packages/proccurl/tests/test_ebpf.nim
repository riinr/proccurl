import std/unittest
import proccurl/ebpf

test "Return immediate":
  var vm = initVm()
  vm.load(@[
    toInsn(0xB7, 0, 0, 0, 42),  # r0 = 42
    toInsn(0x95, 0, 0, 0, 0),   # EXIT
  ])
  discard vm.verify()
  check vm.exec() == 42

test "ALU64 add":
  var vm = initVm()
  vm.load(@[
    toInsn(0xB7, 1, 0, 0, 10),  # r1 = 10
    toInsn(0xB7, 2, 0, 0, 32),  # r2 = 32
    toInsn(0x0F, 0, 1, 0, 0),   # r0 += r1
    toInsn(0x0F, 0, 2, 0, 0),   # r0 += r2
    toInsn(0x95, 0, 0, 0, 0),   # EXIT
  ])
  discard vm.verify()
  check vm.exec() == 42

test "Conditional jump JEQ":
  var vm = initVm()
  vm.regs[1] = 1
  vm.load(@[
    toInsn(0xB7, 0, 0, 0, 1),   # r0 = 1
    toInsn(0x1D, 0, 1, 1, 0),   # JEQ r0==r1, skip next
    toInsn(0xB7, 0, 0, 0, 0),   # r0 = 0 (skipped)
    toInsn(0x95, 0, 0, 0, 0),   # EXIT
  ])
  discard vm.verify()
  check vm.exec() == 1

test "Conditional jump JNE":
  var vm = initVm()
  vm.regs[1] = 99
  vm.load(@[
    toInsn(0xB7, 0, 0, 0, 1),   # r0 = 1
    toInsn(0x5D, 0, 1, 1, 0),   # JNE r0!=r1, skip next
    toInsn(0xB7, 0, 0, 0, 0),   # r0 = 0 (skipped since 1!=99)
    toInsn(0x95, 0, 0, 0, 0),   # EXIT
  ])
  discard vm.verify()
  check vm.exec() == 1

test "Stack store and load (DW)":
  var vm = initVm()
  vm.load(@[
    toInsn(0xB7, 1, 0, 0, 42),  # r1 = 42
    toInsn(0x7B, 10, 1, -8, 0), # STX_DW [r10-8] = r1
    toInsn(0x79, 0, 10, -8, 0), # LDX_DW r0 = [r10-8]
    toInsn(0x95, 0, 0, 0, 0),   # EXIT
  ])
  discard vm.verify()
  check vm.exec() == 42

test "Helper call":
  proc addArgs(vm: ptr EbpfVm; args: array[5, uint64]): uint64 {.nimcall.} =
    args[0] + args[1]
  var vm = initVm()
  vm.addHelper(1, addArgs)
  vm.regs[1] = 20
  vm.regs[2] = 22
  vm.load(@[
    toInsn(0x85, 0, 0, 0, 1),   # CALL 1
    toInsn(0x95, 0, 0, 0, 0),   # EXIT
  ])
  discard vm.verify()
  check vm.exec() == 42

test "64-bit immediate (LD_DW_IMM)":
  var vm = initVm()
  vm.load(@[
    toInsn(0x18, 0, 0, 0, 0xABCD),      # r0 = 0xABCD00000000ABCD (pseudo)
    toInsn(0x00, 0, 0, 0, 0x00000001),  # high 32 bits: (1 << 32) | 0xABCD
    toInsn(0x95, 0, 0, 0, 0),           # EXIT
  ])
  discard vm.verify()
  let expected = (0x00000001.uint64 shl 32) or 0xABCD.uint64
  check vm.exec() == expected

test "ALU64 sub":
  var vm = initVm()
  vm.load(@[
    toInsn(0xB7, 0, 0, 0, 100), # r0 = 100
    toInsn(0x17, 0, 0, 0, 58),  # r0 -= 58 (ALU64_SUB_K)
    toInsn(0x95, 0, 0, 0, 0),   # EXIT
  ])
  discard vm.verify()
  check vm.exec() == 42

test "Unconditional jump JA":
  var vm = initVm()
  vm.load(@[
    toInsn(0xB7, 0, 0, 0, 0),   # r0 = 0
    toInsn(0x05, 0, 0, 2, 0),   # JA +2 (skip r0=1, r0=2, land on exit)
    toInsn(0xB7, 0, 0, 0, 1),   # r0 = 1 (skipped)
    toInsn(0xB7, 0, 0, 0, 2),   # r0 = 2 (skipped)
    toInsn(0x95, 0, 0, 0, 0),   # EXIT
  ])
  discard vm.verify()
  check vm.exec() == 0

test "ALU64 mov (immediate)":
  var vm = initVm()
  vm.load(@[
    toInsn(0xB7, 5, 0, 0, 77),  # r5 = 77
    toInsn(0xBF, 0, 5, 0, 0),   # r0 = r5 (MOV64_X)
    toInsn(0x95, 0, 0, 0, 0),   # EXIT
  ])
  discard vm.verify()
  check vm.exec() == 77

test "Verify rejects empty program":
  var vm = initVm()
  expect(VerifyError):
    vm.load(@[])
    discard vm.verify()

test "Verify rejects zero instruction":
  var vm = initVm()
  vm.load(@[toInsn(0x00, 0, 0, 0, 0)])
  expect(VerifyError):
    discard vm.verify()

test "Verify accepts single exit":
  var vm = initVm()
  vm.load(@[toInsn(0x95, 0, 0, 0, 0)])
  discard vm.verify()
  check vm.exec() == 0
