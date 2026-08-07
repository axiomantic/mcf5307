# src/mcf5307_exec.nim - MCF5307 Core Execution Engine & Instructions

import mcf5307_registers, mcf5307_decode, mcf5307_mac

type
  mcf5307_bus_status* {.size: sizeof(cint).} = enum
    MCF5307_BUS_OK = 0
    MCF5307_BUS_UNMAPPED = 1
    MCF5307_BUS_SIZE_ILLEGAL = 2
    MCF5307_BUS_FAULT = 3

  mcf5307_read_fn* = proc(user: pointer, `addr`: uint32, size: cint, status: ptr mcf5307_bus_status): uint32 {.cdecl.}
  mcf5307_write_fn* = proc(user: pointer, `addr`: uint32, size: cint, value: uint32, status: ptr mcf5307_bus_status) {.cdecl.}
  mcf5307_iack_fn* = proc(user: pointer, level: cint, vector: uint8) {.cdecl.}

  mcf5307_ctx_obj* = object
    regs*: Mcf5307Registers
    mac*: Mcf5307Mac
    user*: pointer
    rd*: mcf5307_read_fn
    wr*: mcf5307_write_fn
    iack*: mcf5307_iack_fn
    irqLevel*: cint
    irqVector*: uint8
    irqAutovector*: cint
    irqNmiLatched*: bool
    halted*: bool
    cycles*: uint64

  Mcf5307Snapshot* {.packed.} = object
    magic*: uint32             # 0x53070001
    version*: uint32           # 1
    d*: array[8, uint32]
    a*: array[8, uint32]
    pc*: uint32
    sr*: uint16
    vbr*: uint32
    mbar*: uint32
    rambar0*: uint32
    rambar1*: uint32
    cacr*: uint32
    acr0*: uint32
    acr1*: uint32
    acc*: uint32
    macsr*: uint32
    mask*: uint32
    irqLevel*: int32
    irqVector*: uint8
    irqAutovector*: int32
    irqNmiLatched*: uint8
    halted*: uint8
    reserved*: uint8
    cycles*: uint64

proc readMem*(ctx: ptr mcf5307_ctx_obj, `addr`: uint32, size: cint): uint32 =
  var st = MCF5307_BUS_OK
  if ctx.rd != nil:
    result = ctx.rd(ctx.user, `addr`, size, addr st)
  else:
    result = 0u32

proc writeMem*(ctx: ptr mcf5307_ctx_obj, `addr`: uint32, size: cint, val: uint32) =
  var st = MCF5307_BUS_OK
  if ctx.wr != nil:
    ctx.wr(ctx.user, `addr`, size, val, addr st)

proc fetch16*(ctx: ptr mcf5307_ctx_obj): uint16 =
  result = uint16(readMem(ctx, ctx.regs.pc, 2) and 0xFFFFu32)
  ctx.regs.pc += 2u32

proc fetch32*(ctx: ptr mcf5307_ctx_obj): uint32 =
  let hi = fetch16(ctx)
  let lo = fetch16(ctx)
  result = (uint32(hi) shl 16) or uint32(lo)

proc push32*(ctx: ptr mcf5307_ctx_obj, val: uint32) =
  ctx.regs.sp -= 4u32
  writeMem(ctx, ctx.regs.sp, 4, val)

proc pop32*(ctx: ptr mcf5307_ctx_obj): uint32 =
  result = readMem(ctx, ctx.regs.sp, 4)
  ctx.regs.sp += 4u32

proc push16*(ctx: ptr mcf5307_ctx_obj, val: uint16) =
  ctx.regs.sp -= 2u32
  writeMem(ctx, ctx.regs.sp, 2, uint32(val))

proc pop16*(ctx: ptr mcf5307_ctx_obj): uint16 =
  result = uint16(readMem(ctx, ctx.regs.sp, 2) and 0xFFFFu32)
  ctx.regs.sp += 2u32

proc triggerException*(ctx: ptr mcf5307_ctx_obj, vector: uint8) =
  let oldSr = ctx.regs.sr
  let returnPc = ctx.regs.pc
  push32(ctx, returnPc)
  let formatVec = 0x4000u16 or uint16(vector)
  push16(ctx, formatVec)
  push16(ctx, oldSr)
  setSupervisor(ctx.regs, true)
  let vecAddr = ctx.regs.vbr + uint32(vector) * 4u32
  ctx.regs.pc = readMem(ctx, vecAddr, 4)

proc checkAndTakeInterrupt*(ctx: ptr mcf5307_ctx_obj) =
  if ctx.irqLevel <= 0: return

  let currentIpl = cint((ctx.regs.sr shr 8) and 0x7u16)
  var shouldTake = false
  var vec = ctx.irqVector

  if ctx.irqLevel == 7:
    if ctx.irqNmiLatched:
      shouldTake = true
      ctx.irqNmiLatched = false
      if ctx.irqAutovector != 0: vec = 31u8
  elif ctx.irqLevel > currentIpl:
    shouldTake = true
    if ctx.irqAutovector != 0: vec = uint8(24 + ctx.irqLevel)

  if shouldTake:
    ctx.halted = false
    triggerException(ctx, vec)
    let newSr = (ctx.regs.sr and 0xF8FFu16) or (uint16(ctx.irqLevel) shl 8)
    ctx.regs.sr = newSr
    if ctx.iack != nil:
      ctx.iack(ctx.user, ctx.irqLevel, vec)

proc updateLogicFlags*(ctx: ptr mcf5307_ctx_obj, val: uint32, size: cint) =
  let masked = case size
    of 1: val and 0xFFu32
    of 2: val and 0xFFFFu32
    else: val
  setZero(ctx.regs, masked == 0u32)
  let msb = case size
    of 1: (masked and 0x80u32) != 0u32
    of 2: (masked and 0x8000u32) != 0u32
    else: (masked and 0x80000000u32) != 0u32
  setNegative(ctx.regs, msb)
  setOverflow(ctx.regs, false)
  setCarry(ctx.regs, false)

proc updateAddFlags*(ctx: ptr mcf5307_ctx_obj, src: uint32, dst: uint32, res: uint32, size: cint) =
  let maskedRes = case size
    of 1: res and 0xFFu32
    of 2: res and 0xFFFFu32
    else: res
  setZero(ctx.regs, maskedRes == 0u32)
  let msb = case size
    of 1: (maskedRes and 0x80u32) != 0u32
    of 2: (maskedRes and 0x8000u32) != 0u32
    else: (maskedRes and 0x80000000u32) != 0u32
  setNegative(ctx.regs, msb)

  let sm = case size
    of 1: (src and 0x80u32) != 0u32
    of 2: (src and 0x8000u32) != 0u32
    else: (src and 0x80000000u32) != 0u32
  let dm = case size
    of 1: (dst and 0x80u32) != 0u32
    of 2: (dst and 0x8000u32) != 0u32
    else: (dst and 0x80000000u32) != 0u32
  let rm = msb

  let ovf = (sm == dm) and (sm != rm)
  setOverflow(ctx.regs, ovf)

  let carry = case size
    of 1: (uint64(src and 0xFFu32) + uint64(dst and 0xFFu32)) > 0xFFu64
    of 2: (uint64(src and 0xFFFFu32) + uint64(dst and 0xFFFFu32)) > 0xFFFFu64
    else: (uint64(src) + uint64(dst)) > 0xFFFFFFFFu64
  setCarry(ctx.regs, carry)
  setExtend(ctx.regs, carry)

proc updateSubFlags*(ctx: ptr mcf5307_ctx_obj, src: uint32, dst: uint32, res: uint32, size: cint) =
  let maskedRes = case size
    of 1: res and 0xFFu32
    of 2: res and 0xFFFFu32
    else: res
  setZero(ctx.regs, maskedRes == 0u32)
  let msb = case size
    of 1: (maskedRes and 0x80u32) != 0u32
    of 2: (maskedRes and 0x8000u32) != 0u32
    else: (maskedRes and 0x80000000u32) != 0u32
  setNegative(ctx.regs, msb)

  let sm = case size
    of 1: (src and 0x80u32) != 0u32
    of 2: (src and 0x8000u32) != 0u32
    else: (src and 0x80000000u32) != 0u32
  let dm = case size
    of 1: (dst and 0x80u32) != 0u32
    of 2: (dst and 0x8000u32) != 0u32
    else: (dst and 0x80000000u32) != 0u32
  let rm = msb

  let ovf = (sm != dm) and (rm != dm)
  setOverflow(ctx.regs, ovf)

  let borrow = case size
    of 1: (dst and 0xFFu32) < (src and 0xFFu32)
    of 2: (dst and 0xFFFFu32) < (src and 0xFFFFu32)
    else: dst < src
  setCarry(ctx.regs, borrow)
  setExtend(ctx.regs, borrow)

proc getEAAddr*(ctx: ptr mcf5307_ctx_obj, mode: uint8, reg: uint8, size: cint): uint32 =
  case mode
  of 2u8: # (An)
    result = ctx.regs.a[reg]
  of 3u8: # (An)+
    result = ctx.regs.a[reg]
    let inc = if size == 1 and reg == 7: 2u32 else: uint32(size)
    ctx.regs.a[reg] += inc
  of 4u8: # -(An)
    let dec = if size == 1 and reg == 7: 2u32 else: uint32(size)
    ctx.regs.a[reg] -= dec
    result = ctx.regs.a[reg]
  of 5u8: # (d16, An)
    let disp = int32(int16(fetch16(ctx)))
    result = uint32(int32(ctx.regs.a[reg]) + disp)
  of 6u8: # (d8, An, Xi)
    let ext = fetch16(ctx)
    let idxReg = (ext shr 12) and 0x0Fu16
    let isAddr = (ext and 0x8000u16) != 0u16
    let scale = 1i32 shl (int((ext shr 9) and 0x03u16))
    let disp8 = int32(int8(ext and 0xFFu16))
    let idxVal = if isAddr: int32(ctx.regs.a[idxReg and 7]) else: int32(ctx.regs.d[idxReg and 7])
    result = uint32(int32(ctx.regs.a[reg]) + idxVal * scale + disp8)
  of 7u8:
    case reg
    of 0u8: # (xxx).w
      result = uint32(int32(int16(fetch16(ctx))))
    of 1u8: # (xxx).l
      result = fetch32(ctx)
    of 2u8: # (d16, PC)
      let pcBase = ctx.regs.pc
      let disp = int32(int16(fetch16(ctx)))
      result = uint32(int32(pcBase) + disp)
    of 3u8: # (d8, PC, Xi)
      let pcBase = ctx.regs.pc
      let ext = fetch16(ctx)
      let idxReg = (ext shr 12) and 0x0Fu16
      let isAddr = (ext and 0x8000u16) != 0u16
      let scale = 1i32 shl (int((ext shr 9) and 0x03u16))
      let disp8 = int32(int8(ext and 0xFFu16))
      let idxVal = if isAddr: int32(ctx.regs.a[idxReg and 7]) else: int32(ctx.regs.d[idxReg and 7])
      result = uint32(int32(pcBase) + idxVal * scale + disp8)
    else:
      result = 0u32
  else:
    result = 0u32

proc readEAValue*(ctx: ptr mcf5307_ctx_obj, mode: uint8, reg: uint8, size: cint): uint32 =
  case mode
  of 0u8: # Dn
    result = case size
      of 1: ctx.regs.d[reg] and 0xFFu32
      of 2: ctx.regs.d[reg] and 0xFFFFu32
      else: ctx.regs.d[reg]
  of 1u8: # An
    result = case size
      of 2: ctx.regs.a[reg] and 0xFFFFu32
      else: ctx.regs.a[reg]
  of 7u8:
    if reg == 4u8: # #imm
      result = case size
        of 1: uint32(fetch16(ctx) and 0xFFu16)
        of 2: uint32(fetch16(ctx))
        else: fetch32(ctx)
    else:
      let ea = getEAAddr(ctx, mode, reg, size)
      result = readMem(ctx, ea, size)
  else:
    let ea = getEAAddr(ctx, mode, reg, size)
    result = readMem(ctx, ea, size)

proc writeEAValue*(ctx: ptr mcf5307_ctx_obj, mode: uint8, reg: uint8, size: cint, val: uint32) =
  case mode
  of 0u8: # Dn
    case size
    of 1: ctx.regs.d[reg] = (ctx.regs.d[reg] and 0xFFFFFF00u32) or (val and 0xFFu32)
    of 2: ctx.regs.d[reg] = (ctx.regs.d[reg] and 0xFFFF0000u32) or (val and 0xFFFFu32)
    else: ctx.regs.d[reg] = val
  of 1u8: # An
    case size
    of 2: ctx.regs.a[reg] = uint32(int32(int16(val and 0xFFFFu32)))
    else: ctx.regs.a[reg] = val
  else:
    let ea = getEAAddr(ctx, mode, reg, size)
    writeMem(ctx, ea, size, val)

proc evalCondition*(ctx: ptr mcf5307_ctx_obj, cond: uint8): bool =
  let c = getCarry(ctx.regs)
  let v = getOverflow(ctx.regs)
  let z = getZero(ctx.regs)
  let n = getNegative(ctx.regs)
  case cond and 0x0Fu8
  of 0x0u8: true # BRA
  of 0x1u8: false
  of 0x2u8: not c and not z # BHI
  of 0x3u8: c or z # BLS
  of 0x4u8: not c # BCC/BHS
  of 0x5u8: c # BCS/BLO
  of 0x6u8: not z # BNE
  of 0x7u8: z # BEQ
  of 0x8u8: not v # BVC
  of 0x9u8: v # BVS
  of 0xAu8: not n # BPL
  of 0xBu8: n # BMI
  of 0xCu8: (n and v) or (not n and not v) # BGE
  of 0xDu8: (n and not v) or (not n and v) # BLT
  of 0xEu8: not z and ((n and v) or (not n and not v)) # BGT
  of 0xFu8: z or (n and not v) or (not n and v) # BLE
  else: false

proc execStep*(ctx: ptr mcf5307_ctx_obj): uint32 =
  if ctx == nil: return 0u32

  checkAndTakeInterrupt(ctx)

  if ctx.halted:
    ctx.cycles += 1u64
    return 1u32

  let opcode = fetch16(ctx)
  let entry = decodeSingleOpcode(opcode)

  case entry.kind
  of opNop:
    discard
  of opHalt:
    ctx.halted = true
  of opStop:
    let imm = fetch16(ctx)
    if getSupervisor(ctx.regs):
      ctx.regs.sr = imm
      ctx.halted = true
    else:
      triggerException(ctx, 8u8)
  of opRts:
    ctx.regs.pc = pop32(ctx)
  of opRte:
    if getSupervisor(ctx.regs):
      let oldSr = pop16(ctx)
      let fmtVec = pop16(ctx)
      let oldPc = pop32(ctx)
      discard fmtVec
      ctx.regs.sr = oldSr
      ctx.regs.pc = oldPc
    else:
      triggerException(ctx, 8u8)
  of opTrap:
    let vec = uint8(32u16 + (opcode and 0x0Fu16))
    triggerException(ctx, vec)
  of opIllegal:
    triggerException(ctx, 4u8)
  of opMovec:
    if not getSupervisor(ctx.regs):
      triggerException(ctx, 8u8)
    else:
      let ext = fetch16(ctx)
      let cr = ext and 0x0FFFu16
      let regNum = uint8((ext shr 12) and 0x07u16)
      let isAddr = (ext and 0x8000u16) != 0u16
      let dirToCr = (opcode and 0x0001u16) != 0u16 # movec Rn, Rc
      if dirToCr:
        let val = if isAddr: ctx.regs.a[regNum] else: ctx.regs.d[regNum]
        writeControlRegister(ctx.regs, cr, val)
      else:
        let val = readControlRegister(ctx.regs, cr)
        if isAddr: ctx.regs.a[regNum] = val else: ctx.regs.d[regNum] = val
  of opMove:
    let szBit = (opcode shr 12) and 0x3u16
    let size = case szBit
      of 1u16: cint(1)
      of 3u16: cint(2)
      else: cint(4)
    let srcReg = uint8(opcode and 0x7u16)
    let srcMode = uint8((opcode shr 3) and 0x7u16)
    let dstReg = uint8((opcode shr 9) and 0x7u16)
    let dstMode = uint8((opcode shr 6) and 0x7u16)

    let val = readEAValue(ctx, srcMode, srcReg, size)
    writeEAValue(ctx, dstMode, dstReg, size, val)
    if dstMode != 1u8: # Not address register target
      updateLogicFlags(ctx, val, size)
  of opMoveq:
    let reg = uint8((opcode shr 9) and 0x7u16)
    let imm8 = int32(int8(opcode and 0xFFu16))
    ctx.regs.d[reg] = uint32(imm8)
    updateLogicFlags(ctx, ctx.regs.d[reg], 4)
  of opLea:
    let reg = uint8((opcode shr 9) and 0x7u16)
    let srcReg = uint8(opcode and 0x7u16)
    let srcMode = uint8((opcode shr 3) and 0x7u16)
    let ea = getEAAddr(ctx, srcMode, srcReg, 4)
    ctx.regs.a[reg] = ea
  of opPea:
    let srcReg = uint8(opcode and 0x7u16)
    let srcMode = uint8((opcode shr 3) and 0x7u16)
    let ea = getEAAddr(ctx, srcMode, srcReg, 4)
    push32(ctx, ea)
  of opClr:
    let size = cint(4)
    let srcReg = uint8(opcode and 0x7u16)
    let srcMode = uint8((opcode shr 3) and 0x7u16)
    writeEAValue(ctx, srcMode, srcReg, size, 0u32)
    updateLogicFlags(ctx, 0u32, size)
  of opTst:
    let size = cint(4)
    let srcReg = uint8(opcode and 0x7u16)
    let srcMode = uint8((opcode shr 3) and 0x7u16)
    let val = readEAValue(ctx, srcMode, srcReg, size)
    updateLogicFlags(ctx, val, size)
  of opMvs:
    let isWord = (opcode and 0x0040u16) != 0u16
    let reg = uint8((opcode shr 9) and 0x7u16)
    let srcReg = uint8(opcode and 0x7u16)
    let srcMode = uint8((opcode shr 3) and 0x7u16)
    let val = readEAValue(ctx, srcMode, srcReg, if isWord: cint(2) else: cint(1))
    let sext = if isWord: uint32(int32(int16(val))) else: uint32(int32(int8(val)))
    ctx.regs.d[reg] = sext
    updateLogicFlags(ctx, sext, 4)
  of opMvz:
    let isWord = (opcode and 0x0040u16) != 0u16
    let reg = uint8((opcode shr 9) and 0x7u16)
    let srcReg = uint8(opcode and 0x7u16)
    let srcMode = uint8((opcode shr 3) and 0x7u16)
    let val = readEAValue(ctx, srcMode, srcReg, if isWord: cint(2) else: cint(1))
    let zext = if isWord: val and 0xFFFFu32 else: val and 0xFFu32
    ctx.regs.d[reg] = zext
    updateLogicFlags(ctx, zext, 4)
  of opExt:
    let reg = uint8(opcode and 0x7u16)
    let isLong = (opcode and 0x0040u16) != 0u16
    if isLong:
      let sext = uint32(int32(int16(ctx.regs.d[reg] and 0xFFFFu32)))
      ctx.regs.d[reg] = sext
      updateLogicFlags(ctx, sext, 4)
    else:
      let sext = uint32(int16(int8(ctx.regs.d[reg] and 0xFFu32)))
      ctx.regs.d[reg] = (ctx.regs.d[reg] and 0xFFFF0000u32) or (sext and 0xFFFFu32)
      updateLogicFlags(ctx, sext, 2)
  of opExtb:
    let reg = uint8(opcode and 0x7u16)
    let sext = uint32(int32(int8(ctx.regs.d[reg] and 0xFFu32)))
    ctx.regs.d[reg] = sext
    updateLogicFlags(ctx, sext, 4)
  of opSwap:
    let reg = uint8(opcode and 0x7u16)
    let val = ctx.regs.d[reg]
    let swapped = (val shl 16) or (val shr 16)
    ctx.regs.d[reg] = swapped
    updateLogicFlags(ctx, swapped, 4)

  of opAdd, opAdda, opAddi, opAddq, opAddx:
    if entry.kind == opAddi:
      let reg = uint8(opcode and 0x7u16)
      let imm = fetch32(ctx)
      let dst = ctx.regs.d[reg]
      let res = dst + imm
      ctx.regs.d[reg] = res
      updateAddFlags(ctx, imm, dst, res, 4)
    elif entry.kind == opAddq:
      let qVal = (opcode shr 9) and 0x7u16
      let q = if qVal == 0u16: 8u32 else: uint32(qVal)
      let srcReg = uint8(opcode and 0x7u16)
      let srcMode = uint8((opcode shr 3) and 0x7u16)
      if srcMode == 1u8:
        ctx.regs.a[srcReg] += q
      else:
        let dst = readEAValue(ctx, srcMode, srcReg, 4)
        let res = dst + q
        writeEAValue(ctx, srcMode, srcReg, 4, res)
        updateAddFlags(ctx, q, dst, res, 4)
    elif entry.kind == opAdda:
      let reg = uint8((opcode shr 9) and 0x7u16)
      let srcReg = uint8(opcode and 0x7u16)
      let srcMode = uint8((opcode shr 3) and 0x7u16)
      let val = readEAValue(ctx, srcMode, srcReg, 4)
      ctx.regs.a[reg] += val
    elif entry.kind == opAddx:
      let rx = uint8((opcode shr 9) and 0x7u16)
      let ry = uint8(opcode and 0x7u16)
      let c = if getCarry(ctx.regs): 1u32 else: 0u32
      let src = ctx.regs.d[ry]
      let dst = ctx.regs.d[rx]
      let res = dst + src + c
      ctx.regs.d[rx] = res
      updateAddFlags(ctx, src, dst, res, 4)
      if res != 0u32: setZero(ctx.regs, false)
    else: # opAdd
      let reg = uint8((opcode shr 9) and 0x7u16)
      let srcReg = uint8(opcode and 0x7u16)
      let srcMode = uint8((opcode shr 3) and 0x7u16)
      let dirToReg = (opcode and 0x0100u16) == 0u16
      if dirToReg:
        let src = readEAValue(ctx, srcMode, srcReg, 4)
        let dst = ctx.regs.d[reg]
        let res = dst + src
        ctx.regs.d[reg] = res
        updateAddFlags(ctx, src, dst, res, 4)
      else:
        let src = ctx.regs.d[reg]
        let dst = readEAValue(ctx, srcMode, srcReg, 4)
        let res = dst + src
        writeEAValue(ctx, srcMode, srcReg, 4, res)
        updateAddFlags(ctx, src, dst, res, 4)

  of opSub, opSuba, opSubi, opSubq, opSubx:
    if entry.kind == opSubi:
      let reg = uint8(opcode and 0x7u16)
      let imm = fetch32(ctx)
      let dst = ctx.regs.d[reg]
      let res = dst - imm
      ctx.regs.d[reg] = res
      updateSubFlags(ctx, imm, dst, res, 4)
    elif entry.kind == opSubq:
      let qVal = (opcode shr 9) and 0x7u16
      let q = if qVal == 0u16: 8u32 else: uint32(qVal)
      let srcReg = uint8(opcode and 0x7u16)
      let srcMode = uint8((opcode shr 3) and 0x7u16)
      if srcMode == 1u8:
        ctx.regs.a[srcReg] -= q
      else:
        let dst = readEAValue(ctx, srcMode, srcReg, 4)
        let res = dst - q
        writeEAValue(ctx, srcMode, srcReg, 4, res)
        updateSubFlags(ctx, q, dst, res, 4)
    elif entry.kind == opSuba:
      let reg = uint8((opcode shr 9) and 0x7u16)
      let srcReg = uint8(opcode and 0x7u16)
      let srcMode = uint8((opcode shr 3) and 0x7u16)
      let val = readEAValue(ctx, srcMode, srcReg, 4)
      ctx.regs.a[reg] -= val
    elif entry.kind == opSubx:
      let rx = uint8((opcode shr 9) and 0x7u16)
      let ry = uint8(opcode and 0x7u16)
      let c = if getCarry(ctx.regs): 1u32 else: 0u32
      let src = ctx.regs.d[ry]
      let dst = ctx.regs.d[rx]
      let res = dst - src - c
      ctx.regs.d[rx] = res
      updateSubFlags(ctx, src, dst, res, 4)
      if res != 0u32: setZero(ctx.regs, false)
    else: # opSub
      let reg = uint8((opcode shr 9) and 0x7u16)
      let srcReg = uint8(opcode and 0x7u16)
      let srcMode = uint8((opcode shr 3) and 0x7u16)
      let dirToReg = (opcode and 0x0100u16) == 0u16
      if dirToReg:
        let src = readEAValue(ctx, srcMode, srcReg, 4)
        let dst = ctx.regs.d[reg]
        let res = dst - src
        ctx.regs.d[reg] = res
        updateSubFlags(ctx, src, dst, res, 4)
      else:
        let src = ctx.regs.d[reg]
        let dst = readEAValue(ctx, srcMode, srcReg, 4)
        let res = dst - src
        writeEAValue(ctx, srcMode, srcReg, 4, res)
        updateSubFlags(ctx, src, dst, res, 4)

  of opNeg, opNegx:
    let reg = uint8(opcode and 0x7u16)
    let dst = ctx.regs.d[reg]
    if entry.kind == opNegx:
      let c = if getCarry(ctx.regs): 1u32 else: 0u32
      let res = 0u32 - dst - c
      ctx.regs.d[reg] = res
      updateSubFlags(ctx, dst, 0u32, res, 4)
      if res != 0u32: setZero(ctx.regs, false)
    else:
      let res = 0u32 - dst
      ctx.regs.d[reg] = res
      updateSubFlags(ctx, dst, 0u32, res, 4)

  of opCmp, opCmpa, opCmpi:
    if entry.kind == opCmpi:
      let reg = uint8(opcode and 0x7u16)
      let imm = fetch32(ctx)
      let dst = ctx.regs.d[reg]
      let res = dst - imm
      updateSubFlags(ctx, imm, dst, res, 4)
    elif entry.kind == opCmpa:
      let reg = uint8((opcode shr 9) and 0x7u16)
      let srcReg = uint8(opcode and 0x7u16)
      let srcMode = uint8((opcode shr 3) and 0x7u16)
      let src = readEAValue(ctx, srcMode, srcReg, 4)
      let dst = ctx.regs.a[reg]
      let res = dst - src
      updateSubFlags(ctx, src, dst, res, 4)
    else:
      let reg = uint8((opcode shr 9) and 0x7u16)
      let srcReg = uint8(opcode and 0x7u16)
      let srcMode = uint8((opcode shr 3) and 0x7u16)
      let src = readEAValue(ctx, srcMode, srcReg, 4)
      let dst = ctx.regs.d[reg]
      let res = dst - src
      updateSubFlags(ctx, src, dst, res, 4)

  of opMuls, opMulu:
    let reg = uint8((opcode shr 9) and 0x7u16)
    let srcReg = uint8(opcode and 0x7u16)
    let srcMode = uint8((opcode shr 3) and 0x7u16)
    let src = readEAValue(ctx, srcMode, srcReg, 2)
    let dst = ctx.regs.d[reg] and 0xFFFFu32
    if entry.kind == opMuls:
      let prod = int32(int16(src)) * int32(int16(dst))
      ctx.regs.d[reg] = uint32(prod)
      updateLogicFlags(ctx, uint32(prod), 4)
    else:
      let prod = src * dst
      ctx.regs.d[reg] = prod
      updateLogicFlags(ctx, prod, 4)

  of opDivs, opDivu:
    let reg = uint8((opcode shr 9) and 0x7u16)
    let srcReg = uint8(opcode and 0x7u16)
    let srcMode = uint8((opcode shr 3) and 0x7u16)
    let src = readEAValue(ctx, srcMode, srcReg, 2)
    if src == 0u32:
      triggerException(ctx, 5u8)
    else:
      let dst = ctx.regs.d[reg]
      if entry.kind == opDivs:
        let quot = int32(dst) div int32(int16(src))
        let rem = int32(dst) mod int32(int16(src))
        let res = (uint32(rem and 0xFFFF) shl 16) or uint32(quot and 0xFFFF)
        ctx.regs.d[reg] = res
        updateLogicFlags(ctx, uint32(quot), 2)
      else:
        let quot = dst div src
        let rem = dst mod src
        let res = ((rem and 0xFFFFu32) shl 16) or (quot and 0xFFFFu32)
        ctx.regs.d[reg] = res
        updateLogicFlags(ctx, quot, 2)

  of opAnd, opAndi:
    let reg = uint8((opcode shr 9) and 0x7u16)
    if entry.kind == opAndi:
      let imm = fetch32(ctx)
      let res = ctx.regs.d[reg] and imm
      ctx.regs.d[reg] = res
      updateLogicFlags(ctx, res, 4)
    else:
      let srcReg = uint8(opcode and 0x7u16)
      let srcMode = uint8((opcode shr 3) and 0x7u16)
      let dirToReg = (opcode and 0x0100u16) == 0u16
      if dirToReg:
        let src = readEAValue(ctx, srcMode, srcReg, 4)
        let res = ctx.regs.d[reg] and src
        ctx.regs.d[reg] = res
        updateLogicFlags(ctx, res, 4)
      else:
        let src = ctx.regs.d[reg]
        let dst = readEAValue(ctx, srcMode, srcReg, 4)
        let res = dst and src
        writeEAValue(ctx, srcMode, srcReg, 4, res)
        updateLogicFlags(ctx, res, 4)

  of opOr, opOri:
    let reg = uint8((opcode shr 9) and 0x7u16)
    if entry.kind == opOri:
      let imm = fetch32(ctx)
      let res = ctx.regs.d[reg] or imm
      ctx.regs.d[reg] = res
      updateLogicFlags(ctx, res, 4)
    else:
      let srcReg = uint8(opcode and 0x7u16)
      let srcMode = uint8((opcode shr 3) and 0x7u16)
      let dirToReg = (opcode and 0x0100u16) == 0u16
      if dirToReg:
        let src = readEAValue(ctx, srcMode, srcReg, 4)
        let res = ctx.regs.d[reg] or src
        ctx.regs.d[reg] = res
        updateLogicFlags(ctx, res, 4)
      else:
        let src = ctx.regs.d[reg]
        let dst = readEAValue(ctx, srcMode, srcReg, 4)
        let res = dst or src
        writeEAValue(ctx, srcMode, srcReg, 4, res)
        updateLogicFlags(ctx, res, 4)

  of opEor, opEori:
    let reg = uint8((opcode shr 9) and 0x7u16)
    if entry.kind == opEori:
      let imm = fetch32(ctx)
      let res = ctx.regs.d[reg] xor imm
      ctx.regs.d[reg] = res
      updateLogicFlags(ctx, res, 4)
    else:
      let srcReg = uint8(opcode and 0x7u16)
      let srcMode = uint8((opcode shr 3) and 0x7u16)
      let src = ctx.regs.d[reg]
      let dst = readEAValue(ctx, srcMode, srcReg, 4)
      let res = dst xor src
      writeEAValue(ctx, srcMode, srcReg, 4, res)
      updateLogicFlags(ctx, res, 4)

  of opNot:
    let reg = uint8(opcode and 0x7u16)
    let res = not ctx.regs.d[reg]
    ctx.regs.d[reg] = res
    updateLogicFlags(ctx, res, 4)

  of opBtst, opBset, opBclr, opBchg:
    let srcReg = uint8(opcode and 0x7u16)
    let srcMode = uint8((opcode shr 3) and 0x7u16)
    let isImm = (opcode and 0x0800u16) != 0u16
    let bitNum = if isImm: uint32(fetch16(ctx) and 0x1Fu16) else: ctx.regs.d[(opcode shr 9) and 0x7u16] and 0x1Fu32
    let val = readEAValue(ctx, srcMode, srcReg, 4)
    let bitMask = 1u32 shl bitNum
    setZero(ctx.regs, (val and bitMask) == 0u32)

    case entry.kind
    of opBset:
      writeEAValue(ctx, srcMode, srcReg, 4, val or bitMask)
    of opBclr:
      writeEAValue(ctx, srcMode, srcReg, 4, val and (not bitMask))
    of opBchg:
      writeEAValue(ctx, srcMode, srcReg, 4, val xor bitMask)
    else: discard

  of opJmp:
    let srcReg = uint8(opcode and 0x7u16)
    let srcMode = uint8((opcode shr 3) and 0x7u16)
    let ea = getEAAddr(ctx, srcMode, srcReg, 4)
    ctx.regs.pc = ea
  of opJsr:
    let srcReg = uint8(opcode and 0x7u16)
    let srcMode = uint8((opcode shr 3) and 0x7u16)
    let ea = getEAAddr(ctx, srcMode, srcReg, 4)
    push32(ctx, ctx.regs.pc)
    ctx.regs.pc = ea
  of opBcc:
    let cond = uint8((opcode shr 8) and 0x0Fu16)
    var disp = int32(int8(opcode and 0xFFu16))
    let pcBase = ctx.regs.pc
    if disp == 0:
      disp = int32(int16(fetch16(ctx)))

    if cond == 1u8: # BSR
      push32(ctx, ctx.regs.pc)
      ctx.regs.pc = uint32(int32(pcBase) + disp)
    elif evalCondition(ctx, cond):
      ctx.regs.pc = uint32(int32(pcBase) + disp)

  of opMac:
    let ext = fetch16(ctx)
    let isSigned = (ext and 0x0800u16) == 0u16
    let subOp = (ext shr 4) and 0x07u16
    let rx = uint8((opcode shr 9) and 0x7u16)
    let ry = uint8(opcode and 0x7u16)
    let val1 = ctx.regs.d[rx]
    let val2 = ctx.regs.d[ry]

    case subOp
    of 0u16: # mpy.w
      mpyW(ctx.mac, uint16(val1 and 0xFFFFu32), uint16(val2 and 0xFFFFu32), isSigned)
    of 1u16: # mac.w
      macW(ctx.mac, uint16(val1 and 0xFFFFu32), uint16(val2 and 0xFFFFu32), isSigned)
    of 2u16: # msac.w
      msacW(ctx.mac, uint16(val1 and 0xFFFFu32), uint16(val2 and 0xFFFFu32), isSigned)
    of 4u16: # mpy.l
      mpyL(ctx.mac, val1, val2, isSigned)
    of 5u16: # mac.l
      macL(ctx.mac, val1, val2, isSigned)
    of 6u16: # msac.l
      msacL(ctx.mac, val1, val2, isSigned)
    else:
      # movel
      let macReg = uint8(ext and 0x3u16)
      let dirToMac = (ext and 0x0100u16) != 0u16
      if dirToMac:
        writeMacRegister(ctx.mac, macReg, val1)
      else:
        ctx.regs.d[rx] = readMacRegister(ctx.mac, macReg)

  else:
    discard

  let stepCycles = 2u32
  ctx.cycles += uint64(stepCycles)
  return stepCycles

proc execMcf5307Loop*(ctx: ptr mcf5307_ctx_obj, max_cycles: uint32): uint32 =
  if ctx == nil: return 0u32

  var spent = 0u32
  while spent < max_cycles:
    let step = execStep(ctx)
    if step == 0: break
    spent += step
  return spent

proc setMcf5307IrqState*(ctx: ptr mcf5307_ctx_obj, level: cint, vector: uint8, autovector: cint) =
  if ctx == nil: return

  let oldLevel = ctx.irqLevel
  ctx.irqLevel = level
  ctx.irqVector = vector
  ctx.irqAutovector = autovector

  if level == 7 and oldLevel != 7:
    ctx.irqNmiLatched = true

proc mcf5307CoreStateSize*(): csize_t =
  return csize_t(sizeof(Mcf5307Snapshot))

proc mcf5307CoreStateSave*(ctx: ptr mcf5307_ctx_obj, dst: pointer) =
  if ctx == nil or dst == nil: return

  var snap = cast[ptr Mcf5307Snapshot](dst)
  snap.magic = 0x53070001u32
  snap.version = 1u32
  for i in 0..7:
    snap.d[i] = ctx.regs.d[i]
    snap.a[i] = ctx.regs.a[i]
  snap.pc = ctx.regs.pc
  snap.sr = ctx.regs.sr
  snap.vbr = ctx.regs.vbr
  snap.mbar = ctx.regs.mbar
  snap.rambar0 = ctx.regs.rambar0
  snap.rambar1 = ctx.regs.rambar1
  snap.cacr = ctx.regs.cacr
  snap.acr0 = ctx.regs.acr0
  snap.acr1 = ctx.regs.acr1
  snap.acc = ctx.mac.acc
  snap.macsr = ctx.mac.macsr
  snap.mask = ctx.mac.mask
  snap.irqLevel = int32(ctx.irqLevel)
  snap.irqVector = ctx.irqVector
  snap.irqAutovector = int32(ctx.irqAutovector)
  snap.irqNmiLatched = if ctx.irqNmiLatched: 1u8 else: 0u8
  snap.halted = if ctx.halted: 1u8 else: 0u8
  snap.cycles = ctx.cycles

proc mcf5307CoreStateLoad*(ctx: ptr mcf5307_ctx_obj, src: pointer) =
  if ctx == nil or src == nil: return

  let snap = cast[ptr Mcf5307Snapshot](src)
  if snap.magic != 0x53070001u32 or snap.version != 1u32: return

  for i in 0..7:
    ctx.regs.d[i] = snap.d[i]
    ctx.regs.a[i] = snap.a[i]
  ctx.regs.pc = snap.pc
  ctx.regs.sr = snap.sr
  ctx.regs.vbr = snap.vbr
  ctx.regs.mbar = snap.mbar
  ctx.regs.rambar0 = snap.rambar0
  ctx.regs.rambar1 = snap.rambar1
  ctx.regs.cacr = snap.cacr
  ctx.regs.acr0 = snap.acr0
  ctx.regs.acr1 = snap.acr1
  ctx.mac.acc = snap.acc
  ctx.mac.macsr = snap.macsr
  ctx.mac.mask = snap.mask
  ctx.irqLevel = cint(snap.irqLevel)
  ctx.irqVector = snap.irqVector
  ctx.irqAutovector = cint(snap.irqAutovector)
  ctx.irqNmiLatched = snap.irqNmiLatched != 0u8
  ctx.halted = snap.halted != 0u8
  ctx.cycles = snap.cycles
