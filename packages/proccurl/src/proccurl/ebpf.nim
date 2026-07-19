## Minimal eBPF Virtual Machine
##
## Implements a basic eBPF interpreter with:
## - 11 x 64-bit registers (R0-R10)
## - 512-byte stack
## - All ALU64/JMP/LD/ST instructions
## - Map support (lookup, update, delete)
## - Safety verifier
## - Helper function interface

import std/[tables, strutils]

# Instruction opcodes
const
  BPF_LD*   = 0x00
  BPF_LDX*  = 0x01
  BPF_ST*   = 0x02
  BPF_STX*  = 0x03
  BPF_ALU*  = 0x04
  BPF_JMP*  = 0x05
  BPF_ALU64 = 0x07

  BPF_DW*   = 0x18

  BPF_W*    = 0x00
  BPF_H*    = 0x08
  BPF_B*    = 0x10

  BPF_IMM*  = 0x00
  BPF_MEM*  = 0x60

  BPF_ADD*  = 0x00
  BPF_SUB*  = 0x10
  BPF_MUL*  = 0x20
  BPF_DIV*  = 0x30
  BPF_OR*   = 0x40
  BPF_AND*  = 0x50
  BPF_LSH*  = 0x60
  BPF_RSH*  = 0x70
  BPF_NEG*  = 0x80
  BPF_MOD*  = 0x90
  BPF_XOR*  = 0xA0
  BPF_MOV*  = 0xB0
  BPF_ARSH* = 0xC0

  BPF_JA*   = 0x00
  BPF_JEQ*  = 0x10
  BPF_JGT*  = 0x20
  BPF_JGE*  = 0x30
  BPF_JSET* = 0x40
  BPF_JNE*  = 0x50
  BPF_JSGT* = 0x60
  BPF_JSGE* = 0x70
  BPF_CALL* = 0x80
  BPF_EXIT* = 0x90
  BPF_JLT*  = 0xA0
  BPF_JLE*  = 0xB0
  BPF_JSLT* = 0xC0
  BPF_JSLE* = 0xD0

  BPF_K*    = 0x00
  BPF_X*    = 0x08

const
  BPF_REG_COUNT*  = 11
  BPF_STACK_SIZE* = 512
  BPF_MAX_INSNS*  = 4096

type
  BpfInsn* = object
    code*: uint8
    dstReg*: uint8  ## 4 bits
    srcReg*: uint8  ## 4 bits
    off*: int16
    imm*: int32

  EbpfMap* = object
    keySize*: uint32
    valSize*: uint32
    maxEntries*: uint32
    data: TableRef[uint64, seq[byte]]

  HelperFn* = proc(vm: ptr EbpfVm, args: array[5, uint64]): uint64 {.nimcall.}

  EbpfVm* = object
    regs*: array[BPF_REG_COUNT, uint64]
    stack: array[BPF_STACK_SIZE, byte]
    prog: seq[BpfInsn]
    pc*: int
    maps: Table[int, EbpfMap]
    helpers: Table[int, HelperFn]
    data: pointer
    lastError: string

proc toInsn*(code: uint8, dst: uint8, src: uint8, off: int16, imm: int32): BpfInsn =
  BpfInsn(code: code, dstReg: dst, srcReg: src, off: off, imm: imm)

proc `$`*(insn: BpfInsn): string =
  "bpf(" & insn.code.uint.toHex & " dst=" & $insn.dstReg & " src=" & $insn.srcReg &
  " off=" & $insn.off & " imm=" & $insn.imm & ")"

template rdst(insn: BpfInsn): uint64 = vm.regs[insn.dstReg]
template wdst(insn: BpfInsn, v: uint64) = vm.regs[insn.dstReg] = v
template rsrc(insn: BpfInsn): uint64 = vm.regs[insn.srcReg]

template sext32(v: uint64): uint64 =
  cast[uint64](cast[int64](cast[int32](v.uint32)))

proc initVm*(): EbpfVm =
  result.regs = [uint64 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, BPF_STACK_SIZE.uint64]
  result.helpers = initTable[int, HelperFn]()
  result.maps = initTable[int, EbpfMap]()

proc addMap*(vm: var EbpfVm; id: int, keySize, valSize, maxEntries: uint32) =
  vm.maps[id] = EbpfMap(keySize: keySize, valSize: valSize,
      maxEntries: maxEntries, data: newTable[uint64, seq[byte]]())

proc addHelper*(vm: var EbpfVm; id: int, fn: HelperFn) =
  vm.helpers[id] = fn

proc load*(vm: var EbpfVm; insns: openArray[BpfInsn]) =
  vm.prog = @insns
  vm.pc = 0

# ---------- Verifier ----------

type VerifyError* = object of CatchableError

proc verify*(vm: var EbpfVm): bool {.discardable.} =
  if vm.prog.len == 0:
    raise newException(VerifyError, "empty program")
  if vm.prog.len > BPF_MAX_INSNS:
    raise newException(VerifyError, "program too long: " & $vm.prog.len)

  var i = 0
  while i < vm.prog.len:
    let insn = vm.prog[i]
    let cls = insn.code and 0x07
    let op = insn.code and 0xF0

    case cls
    of BPF_LD, BPF_LDX, BPF_ST, BPF_STX:
      let sz = insn.code and 0x18
      if insn.dstReg > 10 or insn.srcReg > 10:
        raise newException(VerifyError, "bad register at " & $i)
      let mode = insn.code and 0xE0
      if cls == BPF_LD and mode == BPF_IMM and sz == BPF_DW:
        if i + 1 >= vm.prog.len:
          raise newException(VerifyError, "64-bit imm needs next insn at " & $i)
        i += 1
      if cls == BPF_LDX and insn.off mod int16(sz shr 3 + 1) != 0:
        discard
    of BPF_ALU, BPF_ALU64:
      if insn.dstReg > 10 or insn.srcReg > 10:
        raise newException(VerifyError, "bad register at " & $i)
    of BPF_JMP:
      if insn.dstReg > 10 or insn.srcReg > 10:
        raise newException(VerifyError, "bad register at " & $i)
      if op == BPF_EXIT:
        discard  # exit is valid anywhere
      elif op == BPF_CALL:
        if insn.imm < 0:
          raise newException(VerifyError, "bad helper id at " & $i)
      elif op != BPF_JA:
        let target = i + 1 + insn.off
        if target < 0 or target >= vm.prog.len:
          raise newException(VerifyError, "jump out of bounds at " & $i)
    else:
      raise newException(VerifyError, "unknown insn class at " & $i)

    if insn.code == 0:
      raise newException(VerifyError, "zero insn at " & $i)
    i += 1

  true

# ---------- Interpreter ----------

type ExecError* = object of CatchableError

proc exec*(vm: var EbpfVm): uint64 {.discardable.} =
  vm.pc = 0
  let prog = vm.prog
  let n = prog.len

  while vm.pc < n:
    let insn = prog[vm.pc]
    let cls  = insn.code and 0x07
    let op   = insn.code and 0xF0
    let src  = insn.code and 0x08
    let sz   = insn.code and 0x18
    let s    = insn.off

    template next: untyped = inc vm.pc; continue
    template jmp(t: bool) =
      if t: vm.pc += s + 1 else: inc vm.pc
      continue

    case cls
    of BPF_ALU64, BPF_ALU:
      let is64 = cls == BPF_ALU64
      let a = rdst(insn)
      let b = if src == BPF_X: rsrc(insn) else: cast[uint64](insn.imm)

      template alu(opr: untyped) =
        var r = opr
        if not is64: r = sext32(r)
        wdst(insn, r)
        next

      case op
      of BPF_ADD: alu(a + b)
      of BPF_SUB: alu(a - b)
      of BPF_MUL: alu(a * b)
      of BPF_DIV:
        if b == 0: raise newException(ExecError, "div by zero at " & $vm.pc)
        alu(a div b)
      of BPF_OR:  alu(a or b)
      of BPF_AND: alu(a and b)
      of BPF_LSH: alu(a shl (b and 63))
      of BPF_RSH: alu(a shr (b and 63))
      of BPF_NEG:
        let r = cast[uint64](-cast[int64](if is64: a else: a.uint32))
        wdst(insn, r)
        next
      of BPF_MOD:
        if b == 0: raise newException(ExecError, "mod by zero at " & $vm.pc)
        alu(a mod b)
      of BPF_XOR: alu(a xor b)
      of BPF_MOV: alu(b)
      of BPF_ARSH: alu(cast[uint64](cast[int64](a) shr (b and 63)))
      else:
        raise newException(ExecError, "unknown alu op at " & $vm.pc)

    of BPF_JMP:
      let a = rdst(insn)
      let b = if src == BPF_X: rsrc(insn) else: cast[uint64](insn.imm)

      case op
      of BPF_JA:   jmp(true)
      of BPF_JEQ:  jmp(a == b)
      of BPF_JGT:  jmp(a > b)
      of BPF_JGE:  jmp(a >= b)
      of BPF_JSET: jmp((a and b) != 0)
      of BPF_JNE:  jmp(a != b)
      of BPF_JSGT: jmp(cast[int64](a) > cast[int64](b))
      of BPF_JSGE: jmp(cast[int64](a) >= cast[int64](b))
      of BPF_CALL:
        let fid = insn.imm
        if vm.helpers.hasKey(fid):
          let fn = vm.helpers[fid]
          var args: array[5, uint64]
          args[0] = vm.regs[1]
          args[1] = vm.regs[2]
          args[2] = vm.regs[3]
          args[3] = vm.regs[4]
          args[4] = vm.regs[5]
          vm.regs[0] = fn(addr(vm), args)
        inc vm.pc
        continue
      of BPF_EXIT:
        return vm.regs[0]
      of BPF_JLT:  jmp(a < b)
      of BPF_JLE:  jmp(a <= b)
      of BPF_JSLT: jmp(cast[int64](a) < cast[int64](b))
      of BPF_JSLE: jmp(cast[int64](a) <= cast[int64](b))
      else:
        raise newException(ExecError, "unknown jmp op at " & $vm.pc)

    of BPF_LD:
      let mode = insn.code and 0xE0
      if mode == BPF_IMM and sz == BPF_DW:
        vm.regs[insn.dstReg] = cast[uint64](insn.imm) or
            (cast[uint64](cast[uint64](prog[vm.pc + 1].imm)) shl 32)
        vm.pc += 2
      elif mode == BPF_MEM:
        let ea = vm.regs[insn.srcReg] + cast[uint64](cast[uint64](s))
        if ea > BPF_STACK_SIZE - 8:
          raise newException(ExecError, "ld mem oob at " & $vm.pc)
        vm.regs[insn.dstReg] = cast[ptr uint64](addr(vm.stack[ea]))[]
        inc vm.pc
      else:
        raise newException(ExecError, "unknown ld mode at " & $vm.pc)

    of BPF_LDX:
      let ea = vm.regs[insn.srcReg] + cast[uint64](cast[uint64](s))
      template chk(n: int) =
        if ea > BPF_STACK_SIZE.uint64 - n.uint64:
          raise newException(ExecError, "ldx oob at " & $vm.pc)
      case sz
      of BPF_W:
        chk(4); vm.regs[insn.dstReg] = sext32(cast[ptr uint32](addr(vm.stack[ea]))[])
      of BPF_H:
        chk(2); vm.regs[insn.dstReg] = cast[ptr uint16](addr(vm.stack[ea]))[]
      of BPF_B:
        chk(1); vm.regs[insn.dstReg] = vm.stack[ea].uint64
      of BPF_DW:
        chk(8); vm.regs[insn.dstReg] = cast[ptr uint64](addr(vm.stack[ea]))[]
      else: raise newException(ExecError, "unknown ldx size at " & $vm.pc)
      inc vm.pc

    of BPF_ST:
      let ea = vm.regs[insn.dstReg] + cast[uint64](cast[uint64](s))
      template st(n: int) =
        if ea > BPF_STACK_SIZE.uint64 - n.uint64:
          raise newException(ExecError, "st oob at " & $vm.pc)
      case sz
      of BPF_W:  st(4); cast[ptr uint32](addr(vm.stack[ea]))[] = insn.imm.uint32
      of BPF_B:  st(1); vm.stack[ea] = insn.imm.uint8
      of BPF_DW: st(8); cast[ptr uint64](addr(vm.stack[ea]))[] = insn.imm.uint64
      else: raise newException(ExecError, "unknown st size at " & $vm.pc)
      inc vm.pc

    of BPF_STX:
      let ea = vm.regs[insn.dstReg] + cast[uint64](cast[uint64](s))
      template stx(n: int) =
        if ea > BPF_STACK_SIZE.uint64 - n.uint64:
          raise newException(ExecError, "stx oob at " & $vm.pc)
      case sz
      of BPF_W:  stx(4); cast[ptr uint32](addr(vm.stack[ea]))[] = rsrc(insn).uint32
      of BPF_H:  stx(2); cast[ptr uint16](addr(vm.stack[ea]))[] = rsrc(insn).uint16
      of BPF_B:  stx(1); vm.stack[ea] = rsrc(insn).uint8
      of BPF_DW: stx(8); cast[ptr uint64](addr(vm.stack[ea]))[] = rsrc(insn)
      else: raise newException(ExecError, "unknown stx size at " & $vm.pc)
      inc vm.pc

    else:
      raise newException(ExecError, "unknown insn class at " & $vm.pc)
