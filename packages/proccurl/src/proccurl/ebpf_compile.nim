## Nim-to-eBPF Compiler
##
## Compiles Nim-like code into eBPF bytecode at compile time.
##
## Usage:
##   let prog = compileEbpf:
##     var x = 10
##     var y = 32
##     return x + y
##
##   var vm = initVm()
##   vm.load(prog)
##   discard vm.verify()
##   echo vm.exec()  # 42

import std/[macros, tables]
import proccurl/ebpf

const IntLitKinds = {nnkIntLit, nnkInt8Lit, nnkInt16Lit, nnkInt32Lit, nnkInt64Lit,
                      nnkUIntLit, nnkUInt8Lit, nnkUInt16Lit, nnkUInt32Lit, nnkUInt64Lit}

type
  ArrayInfo = object
    baseOff: int
    elemCount: int

  Compiler = ref object
    insns: seq[BpfInsn]
    vars: OrderedTable[string, int]
    arrays: OrderedTable[string, ArrayInfo]
    nextReg: int
    nextStackOff: int
    freeTemps: seq[int]
    labelCount: int
    fixups: seq[tuple[insnIdx: int, label: int]]
    labelPos: seq[int]

proc newCompiler(): Compiler =
  Compiler(insns: @[], vars: initOrderedTable[string, int](),
           arrays: initOrderedTable[string, ArrayInfo](),
           nextReg: 6, nextStackOff: 0, freeTemps: @[5, 4, 3, 2, 1],
           labelCount: 0, fixups: @[], labelPos: @[])

# ------------------------------------------------------------------
# Register management
# ------------------------------------------------------------------

proc allocTemp(c: Compiler): int =
  if c.freeTemps.len == 0:
    raise newException(ValueError, "out of temp registers")
  c.freeTemps.pop()

proc freeTemp(c: Compiler, r: int) =
  c.freeTemps.add(r)

# ------------------------------------------------------------------
# Instruction emission
# ------------------------------------------------------------------

proc emit(c: Compiler; code: uint8; dst, src: uint8; off: int16; imm: int32) =
  c.insns.add(toInsn(code, dst, src, off, imm))

template emitR(c: Compiler; code: int; dst, srcreg: int) =
  c.emit(code.uint8, dst.uint8, srcreg.uint8, 0, 0)

template emitK(c: Compiler; code: int; dst: int; imm: int32) =
  c.emit(code.uint8, dst.uint8, 0, 0, imm)

template emitJ(c: Compiler; code, dst: int; imm: int32) =
  c.emit(code.uint8, dst.uint8, 0, 0, imm)

template emitJA(c: Compiler; off: int) =
  c.emit(0x05.uint8, 0, 0, off.int16, 0)

# ------------------------------------------------------------------
# Labels and patching
# ------------------------------------------------------------------

proc newLabel(c: Compiler): int =
  result = c.labelCount
  c.labelCount += 1
  c.labelPos.add(-1)

proc defineLabel(c: Compiler, label: int) =
  c.labelPos[label] = c.insns.len
  var i = 0
  while i < c.fixups.len:
    if c.fixups[i].label == label:
      let insnIdx = c.fixups[i].insnIdx
      let target = c.insns.len
      c.insns[insnIdx].off = int16(target - insnIdx - 1)
      c.fixups.delete(i)
    else:
      i += 1

proc emitJumpFwd(c: Compiler; code, dst: int; imm: int32; label: int) =
  let idx = c.insns.len
  c.emit(code.uint8, dst.uint8, 0, 0, imm)
  c.fixups.add((idx, label))

# ------------------------------------------------------------------
# Expression compiler
# ------------------------------------------------------------------

proc compileExpr(c: Compiler, n: NimNode)

proc compileExpr(c: Compiler, n: NimNode) =
  case n.kind
  of IntLitKinds:
    let v = n.intVal
    if v in low(int32)..high(int32):
      c.emitK(0xB7, 0, v.int32)
    else:
      let lo = v and 0xFFFF_FFFF
      let hi = (v shr 32) and 0xFFFF_FFFF
      c.emit(0x18, 0, 0, 0, cast[int32](lo.uint32))
      c.emit(0x00, 0, 0, 0, cast[int32](hi.uint32))

  of nnkIdent:
    let name = n.repr
    if c.vars.hasKey(name):
      let reg = c.vars[name]
      if reg != 0:
        c.emitR(0xBF, 0, reg)
    else:
      raise newException(ValueError, "unknown variable: " & name)

  of nnkPrefix:
    if n[0].repr == "-":
      c.compileExpr(n[1])
      c.emitK(0x87, 0, 0)
    else:
      raise newException(ValueError, "unsupported prefix: " & n[0].repr)

  of nnkPar:
    c.compileExpr(n[0])

  of nnkInfix:
    let opStr = n[0].repr
    case opStr
    of "+", "-", "*", "div", "mod", "and", "or", "xor", "shl", "shr":
      let aluK = case opStr
        of "+":   0x07
        of "-":   0x17
        of "*":   0x27
        of "div": 0x37
        of "mod": 0x97
        of "and": 0x57
        of "or":  0x47
        of "xor": 0xA7
        of "shl": 0x67
        of "shr": 0x77
        else: 0
      let aluX = case opStr
        of "+":   0x0F
        of "-":   0x1F
        of "*":   0x2F
        of "div": 0x3F
        of "mod": 0x9F
        of "and": 0x5F
        of "or":  0x4F
        of "xor": 0xAF
        of "shl": 0x6F
        of "shr": 0x7F
        else: 0
      c.compileExpr(n[1])
      let temp = c.allocTemp()
      c.emitR(0xBF, temp, 0)
      let rightIsImm = n[2].kind in IntLitKinds
      if rightIsImm:
        c.emitK(aluK, temp, n[2].intVal.int32)
      else:
        c.compileExpr(n[2])
        c.emitR(aluX, temp, 0)
      c.emitR(0xBF, 0, temp)
      c.freeTemp(temp)

    of "==", "!=", "<", "<=", ">", ">=", "lt", "le", "gt", "ge":
      c.compileExpr(n[1])
      let temp = c.allocTemp()
      c.emitR(0xBF, temp, 0)
      c.compileExpr(n[2])
      let (jmpK, jmpX) = case opStr
        of "==": (0x15, 0x1D)
        of "!=": (0x55, 0x5D)
        of "<", "lt": (0xA5, 0xAD)
        of "<=", "le": (0xB5, 0xBD)
        of ">", "gt": (0x25, 0x2D)
        of ">=", "ge": (0x35, 0x3D)
        else: (0, 0)
      let rightIsImm = n[2].kind in IntLitKinds
      if rightIsImm:
        let imm = n[2].intVal.int32
        c.emitJ(jmpK, temp, imm)
      else:
        c.emitR(jmpX, temp, 0)
      let jmpIdx = c.insns.len - 1
      c.emitK(0xB7, 0, 0)
      c.emitJA(1)
      let target = c.insns.len
      c.insns[jmpIdx].off = int16(target - jmpIdx - 1)
      c.emitK(0xB7, 0, 1)
      c.freeTemp(temp)

    else:
      raise newException(ValueError, "unsupported operator: " & opStr)

  of nnkBracketExpr:
    let arrName = n[0].repr
    if c.arrays.hasKey(arrName):
      let info = c.arrays[arrName]
      c.compileExpr(n[1])
      c.emitK(0x67, 0, 3)
      c.emitK(0x87, 0, 0)
      c.emitK(0x07, 0, info.baseOff.int32)
      c.emitR(0x0F, 0, 10)
      let temp = c.allocTemp()
      c.emitR(0xBF, temp, 0)
      c.emitR(0x79, 0, temp)
      c.freeTemp(temp)
    else:
      raise newException(ValueError, "unknown array: " & arrName)

  of nnkCall, nnkCommand:
    let fnName = n[0].repr
    if fnName == "call":
      let helperId = n[1].intVal.int
      for i in 2..<n.len:
        let regIdx = i - 1
        if regIdx > 5:
          raise newException(ValueError, "too many args for helper call")
        c.compileExpr(n[i])
        c.emitR(0xBF, regIdx, 0)
      c.emitK(0x85, 0, helperId.int32)
    else:
      raise newException(ValueError, "unknown function: " & fnName)

  else:
    raise newException(ValueError, "unexpected expression node: " & n.repr)

# ------------------------------------------------------------------
# Statement compiler
# ------------------------------------------------------------------

proc compileStmt(c: Compiler, n: NimNode)

proc compileBody(c: Compiler, n: NimNode) =
  case n.kind
  of nnkStmtList:
    for child in n:
      c.compileStmt(child)
  else:
    c.compileStmt(n)

proc compileStmt(c: Compiler, n: NimNode) =
  case n.kind
  of nnkVarSection:
    for child in n:
      if child.kind == nnkIdentDefs:
        let name = child[0].repr
        let typeNode = child[1]
        let initExpr = child[2]
        if typeNode.kind == nnkBracketExpr and typeNode[0].repr == "array":
          if c.arrays.hasKey(name) or c.vars.hasKey(name):
            raise newException(ValueError, "duplicate variable: " & name)
          let elemCount = typeNode[1].intVal.int
          let baseOff = c.nextStackOff - 8
          c.nextStackOff -= elemCount * 8
          c.arrays[name] = ArrayInfo(baseOff: baseOff, elemCount: elemCount)
        else:
          if c.vars.hasKey(name) or c.arrays.hasKey(name):
            raise newException(ValueError, "duplicate variable: " & name)
          let reg = c.nextReg
          c.nextReg += 1
          c.vars[name] = reg
          if initExpr.kind != nnkEmpty:
            c.compileExpr(initExpr)
            if reg != 0:
              c.emitR(0xBF, reg, 0)

  of nnkAsgn:
    let lhs = n[0]
    let rhs = n[1]
    if lhs.kind == nnkIdent:
      let name = lhs.repr
      if not c.vars.hasKey(name):
        raise newException(ValueError, "unknown variable: " & name)
      c.compileExpr(rhs)
      let reg = c.vars[name]
      if reg != 0:
        c.emitR(0xBF, reg, 0)
    elif lhs.kind == nnkBracketExpr:
      let arrName = lhs[0].repr
      if not c.arrays.hasKey(arrName):
        raise newException(ValueError, "unknown array: " & arrName)
      let info = c.arrays[arrName]
      c.compileExpr(rhs)
      let tempVal = c.allocTemp()
      c.emitR(0xBF, tempVal, 0)
      c.compileExpr(lhs[1])
      c.emitK(0x67, 0, 3)
      c.emitK(0x87, 0, 0)
      c.emitK(0x07, 0, info.baseOff.int32)
      c.emitR(0x0F, 0, 10)
      c.emitR(0x7B, 0, tempVal)
      c.freeTemp(tempVal)
    else:
      raise newException(ValueError, "unsupported assignment target")

  of nnkDiscardStmt:
    if n[0].kind != nnkEmpty:
      c.compileExpr(n[0])

  of nnkReturnStmt:
    if n[0].kind != nnkEmpty:
      c.compileExpr(n[0])
    c.emitK(0x95, 0, 0)

  of nnkIfStmt:
    let endLabel = c.newLabel()
    var elseAt: seq[tuple[label: int, hasBody: bool]]

    for branch in n:
      case branch.kind
      of nnkElifBranch:
        if elseAt.len > 0 and not elseAt[^1].hasBody:
          c.defineLabel(elseAt[^1].label)
          elseAt[^1] = (elseAt[^1].label, true)
        c.compileExpr(branch[0])
        let elseLabel = c.newLabel()
        c.emitJumpFwd(0x15, 0, 0, elseLabel)
        c.compileBody(branch[1])
        c.emitJumpFwd(0x05, 0, 0, endLabel)
        elseAt.add((elseLabel, false))
      of nnkElse:
        if elseAt.len > 0 and not elseAt[^1].hasBody:
          c.defineLabel(elseAt[^1].label)
          elseAt[^1] = (elseAt[^1].label, true)
        c.compileBody(branch[0])
      else:
        raise newException(ValueError, "unexpected branch kind")

    for entry in elseAt:
      if not entry.hasBody:
        c.defineLabel(entry.label)
    c.defineLabel(endLabel)

  of nnkWhileStmt:
    let cond = n[0]
    let body = n[1]
    let startLabel = c.newLabel()
    let endLabel = c.newLabel()
    c.defineLabel(startLabel)
    c.compileExpr(cond)
    c.emitJumpFwd(0x15, 0, 0, endLabel)
    c.compileBody(body)
    let loopBackIdx = c.insns.len
    c.emitJA(0)
    let loopTarget = c.labelPos[startLabel]
    let loopOff = loopTarget - loopBackIdx - 1
    c.insns[loopBackIdx].off = int16(loopOff)
    c.defineLabel(endLabel)

  of nnkStmtList:
    for child in n:
      c.compileStmt(child)

  of nnkCall, nnkCommand:
    c.compileExpr(n)

  else:
    raise newException(ValueError, "unexpected statement node: " & n.repr)

# ------------------------------------------------------------------
# Macro interface
# ------------------------------------------------------------------

macro compileEbpf*(body: untyped): untyped =
  let stmts = if body.kind == nnkStmtList: body else: body[^1]
  var c = newCompiler()
  c.compileStmt(stmts)

  if c.fixups.len > 0:
    error("unresolved labels in eBPF compilation", body)

  proc genLit[T](v: T): NimNode =
    when T is uint8: newLit(v)
    elif T is int16: newLit(v)
    elif T is int32: newLit(v)
    else: newLit(v)

  var insnNodes: seq[NimNode]
  for insn in c.insns:
    insnNodes.add(newCall(bindSym"toInsn",
      genLit(insn.code),
      genLit(insn.dstReg),
      genLit(insn.srcReg),
      genLit(insn.off),
      genLit(insn.imm)))

  result = newNimNode(nnkBracket)
  for n in insnNodes:
    result.add(n)
  result = newCall(bindSym"@", result)
