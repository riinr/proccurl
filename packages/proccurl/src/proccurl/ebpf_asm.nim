## eBPF Macro Assembler
##
## Compiles a Nim-like DSL into eBPF bytecode at compile time.
##
## Usage:
##   let prog = ebpf:
##     mov r0, 42
##     exit
##
##   let prog = ebpf:
##     mov r1, 10
##     mov r2, 32
##     add64 r0, r1
##     add64 r0, r2
##     exit

import std/[macros, strutils]
import proccurl/ebpf

# ------------------------------------------------------------------
# Helpers to decode Nim AST nodes
# ------------------------------------------------------------------

const IntLitKinds = {nnkIntLit, nnkInt8Lit, nnkInt16Lit, nnkInt32Lit, nnkInt64Lit,
                      nnkUIntLit, nnkUInt8Lit, nnkUInt16Lit, nnkUInt32Lit, nnkUInt64Lit}

proc expectInt(n: NimNode): int =
  case n.kind
  of IntLitKinds: n.intVal.int
  of nnkPrefix:
    if n[0].eqIdent"+":
      n[1].intVal.int
    elif n[0].eqIdent"-":
      -n[1].intVal.int
    else:
      raise newException(ValueError, "bad prefix: " & n.repr)
  else: raise newException(ValueError, "expected int, got " & n.repr)

proc expectReg(n: NimNode): int =
  let s = n.repr
  if s.len >= 2 and s[0] == 'r':
    let n = s[1..^1].parseInt
    if n in 0..10: return n
  raise newException(ValueError, "expected r0..r10, got " & s.repr)

proc expectOff(n: NimNode): int =
  case n.kind
  of IntLitKinds: n.intVal.int
  of nnkPrefix:
    if n[0].eqIdent"+":
      n[1].intVal.int
    elif n[0].eqIdent"-":
      -n[1].intVal.int
    else:
      raise newException(ValueError, "bad prefix: " & n.repr)
  else: raise newException(ValueError, "expected offset, got " & n.repr)

# ------------------------------------------------------------------
# ALU64 / ALU32 opcode table
# ------------------------------------------------------------------

const
  AluOps64: array[13, tuple[name: string, opK, opX: int]] = [
    ("add64", 0x07, 0x0F),
    ("sub64", 0x17, 0x1F),
    ("mul64", 0x27, 0x2F),
    ("div64", 0x37, 0x3F),
    ("or64",  0x47, 0x4F),
    ("and64", 0x57, 0x5F),
    ("lsh64", 0x67, 0x6F),
    ("rsh64", 0x77, 0x7F),
    ("neg64", 0x87, 0x87),
    ("mod64", 0x97, 0x9F),
    ("xor64", 0xA7, 0xAF),
    ("mov",   0xB7, 0xBF),
    ("arsh64",0xC7, 0xCF),
  ]

  AluOps32: array[13, tuple[name: string, opK, opX: int]] = [
    ("add32", 0x04, 0x0C),
    ("sub32", 0x14, 0x1C),
    ("mul32", 0x24, 0x2C),
    ("div32", 0x34, 0x3C),
    ("or32",  0x44, 0x4C),
    ("and32", 0x54, 0x5C),
    ("lsh32", 0x64, 0x6C),
    ("rsh32", 0x74, 0x7C),
    ("neg32", 0x84, 0x84),
    ("mod32", 0x94, 0x9C),
    ("xor32", 0xA4, 0xAC),
    ("mov32", 0xB4, 0xBC),
    ("arsh32",0xC4, 0xCC),
  ]

  JmpOps: array[14, tuple[name: string, opK, opX: int]] = [
    ("ja",   0x05, 0x05),
    ("jeq",  0x15, 0x1D),
    ("jgt",  0x25, 0x2D),
    ("jge",  0x35, 0x3D),
    ("jset", 0x45, 0x4D),
    ("jne",  0x55, 0x5D),
    ("jsgt", 0x65, 0x6D),
    ("jsge", 0x75, 0x7D),
    ("call", 0x85, 0x85),
    ("exit", 0x95, 0x95),
    ("jlt",  0xA5, 0xAD),
    ("jle",  0xB5, 0xBD),
    ("jslt", 0xC5, 0xCD),
    ("jsle", 0xD5, 0xDD),
  ]

# ------------------------------------------------------------------
# Instruction code generation helpers
# ------------------------------------------------------------------

proc genInsn(code, dst, src, off, imm: int): NimNode =
  quote do: toInsn(`code`.uint8, `dst`.uint8, `src`.uint8, `off`.int16, cast[int32](`imm`.uint32))

proc genInsnD(c, d, s, o, i: int): NimNode =
  genInsn(c, d, s, o, i)

macro ebpf*(body: untyped): untyped =
  let stmts = if body.kind == nnkStmtList: body else: body[^1]
  var resultNodes: seq[NimNode]

  proc args(stmt: NimNode): seq[NimNode] =
    case stmt.kind
    of nnkIdent: result = @[]
    of nnkCommand, nnkCall:
      result = newSeq[NimNode](stmt.len - 1)
      for i in 1..<stmt.len: result[i-1] = stmt[i]
    else: result = @[]

  proc add(n: NimNode) =
    resultNodes.add n

  for stmt in stmts:
    let name = case stmt.kind
      of nnkIdent: stmt
      of nnkCommand, nnkCall: stmt[0]
      else: error("expected instruction, got " & stmt.repr, stmt)
    let nameStr = name.repr
    let a = stmt.args
    var matched = false

    # -- match ALU64 instructions --
    for (opName, opK, opX) in AluOps64:
      if matched: break
      if name.eqIdent(opName):
        case a.len
        of 2:
          let d = expectReg(a[0])
          if a[1].kind in IntLitKinds or a[1].kind == nnkPrefix:
            add genInsnD(opK, d, 0, 0, expectInt(a[1]))
          else:
            add genInsnD(opX, d, expectReg(a[1]), 0, 0)
        of 1:
          if opName == "neg64":
            add genInsnD(opK, expectReg(a[0]), 0, 0, 0)
          else:
            error("expected 1-2 args for " & opName, stmt)
        else:
          error("bad arg count for " & opName, stmt)
        matched = true

    # -- match ALU32 instructions --
    for (opName, opK, opX) in AluOps32:
      if matched: break
      if name.eqIdent(opName):
        case a.len
        of 2:
          let d = expectReg(a[0])
          if a[1].kind in IntLitKinds or a[1].kind == nnkPrefix:
            add genInsnD(opK, d, 0, 0, expectInt(a[1]))
          else:
            add genInsnD(opX, d, expectReg(a[1]), 0, 0)
        of 1:
          if opName == "neg32":
            add genInsnD(opK, expectReg(a[0]), 0, 0, 0)
          else:
            error("expected 1-2 args for " & opName, stmt)
        else:
          error("bad arg count for " & opName, stmt)
        matched = true

    # -- match JMP instructions --
    if not matched:
      for (opName, opK, opX) in JmpOps:
        if matched: break
        if name.eqIdent(opName):
          case opName
          of "exit":
            add genInsnD(opK, 0, 0, 0, 0)
          of "call":
            let imm = expectInt(a[0])
            add genInsnD(opK, 0, 0, 0, imm)
          of "ja":
            let off = expectOff(a[0])
            add genInsnD(opK, 0, 0, off, 0)
          else:
            if a.len != 3:
              error("expected 3 args for " & opName & ": rD, rS/imm, off", stmt)
            let d = expectReg(a[0])
            let off = expectOff(a[2])
            if a[1].kind in IntLitKinds or a[1].kind == nnkPrefix:
              add genInsnD(opK, d, 0, off, expectInt(a[1]))
            else:
              add genInsnD(opX, d, expectReg(a[1]), off, 0)
          matched = true

    # -- LD_DW (64-bit immediate) --
    if not matched and name.eqIdent("lddw"):
      let d = expectReg(a[0])
      let v = expectInt(a[1])
      let lo = v and 0xFFFF_FFFF
      let hi = (v shr 32) and 0xFFFF_FFFF
      add genInsnD(0x18, d, 0, 0, lo)
      add genInsnD(0x00, 0, 0, 0, hi)
      matched = true

    # -- STX (store register to memory) --
    if not matched and (name.eqIdent("stx_dw") or name.eqIdent("stx_w") or
       name.eqIdent("stx_h") or name.eqIdent("stx_b")):
      let sz = nameStr[^2..^1]
      let code = 0x03 or (if sz == "dw": 0x18 elif sz == "w": 0x00
                          elif sz == "h": 0x08 else: 0x10) or 0x60
      if a.len != 3:
        error("expected: stx_XX rD, rS, off", stmt)
      let d = expectReg(a[0])
      let s = expectReg(a[1])
      let off = expectOff(a[2])
      add genInsnD(code, d, s, off, 0)
      matched = true

    # -- LDX (load from memory to register) --
    if not matched and (name.eqIdent("ldx_dw") or name.eqIdent("ldx_w") or
       name.eqIdent("ldx_h") or name.eqIdent("ldx_b")):
      let sz = nameStr[^2..^1]
      let code = 0x01 or (if sz == "dw": 0x18 elif sz == "w": 0x00
                          elif sz == "h": 0x08 else: 0x10) or 0x60
      if a.len != 3:
        error("expected: ldx_XX rD, rS, off", stmt)
      let d = expectReg(a[0])
      let s = expectReg(a[1])
      let off = expectOff(a[2])
      add genInsnD(code, d, s, off, 0)
      matched = true

    # -- ST (store immediate to memory) --
    if not matched and (name.eqIdent("st_dw") or name.eqIdent("st_w") or
       name.eqIdent("st_h") or name.eqIdent("st_b")):
      let sz = nameStr[^2..^1]
      let code = 0x02 or (if sz == "dw": 0x18 elif sz == "w": 0x00
                          elif sz == "h": 0x08 else: 0x10) or 0x60
      if a.len != 3:
        error("expected: st_XX rD, off, imm", stmt)
      let d = expectReg(a[0])
      let off = expectOff(a[1])
      let imm = expectInt(a[2])
      add genInsnD(code, d, 0, off, imm)
      matched = true

    if not matched:
      error("unknown instruction: " & nameStr, stmt)

  # Build the seq literal
  if resultNodes.len == 0:
    result = newNimNode(nnkBracket)
  else:
    result = newNimNode(nnkBracket)
    for n in resultNodes:
      result.add n
  result = quote do:
    @`result`
