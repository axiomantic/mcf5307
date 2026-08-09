## `move` - the data-movement instruction group of the ColdFire ISA_A core.
## Task CPU-7 creates this file. Design section 6.1.
##
## This module executes MOVE, MOVEA, MOVEQ, MOVEM, LEA, PEA, LINK and UNLK,
## and it owns the register file (d0..d7, a0..a6; a7 is the single stack
## pointer, kept in the context's `sp`) that the instruction groups CPU-7 to
## CPU-10 share.
##
## The decoder (`mcf5307/decode`, CPU-6) recognizes the instruction words and
## supplies the effective address in bits 5..0 of the word; this module
## executes them. The extension words of an instruction (displacements,
## index words, immediate values, and the MOVEM register mask) live in the
## instruction stream after the opcode word, and are consumed here as the
## operand evaluation walks them. The MOVEM mask precedes the EA extension
## words, so the mask is fetched before the EA's own words.
##
## CYCLES ARE NOMINAL. The per-instruction cycle budget on serial MCF5307
## silicon needs the clock work of open question 6 in AGENTS.md; until it is
## settled no exact cost is asserted anywhere (decode.nim carries the same
## note). A later task replaces the constants when the clock is settled.
##
## MIT licensed and clean-room with respect to GPL and LGPL code. Instruction
## semantics, register numbering and addressing-mode behaviour are facts
## about Motorola silicon; they are taken from the ColdFire Family
## Programmer's Reference Manual and the MCF5307 User's Manual (AGENTS.md
## section 11) and from this project's own measurements.

import std/bitops
import mcf5307/decode
import mcf5307/ea

# ---------------------------------------------------------------------------
# The register file.
#
# d0..d7 live in `ctx.dRegs`, a0..a6 in `ctx.aRegs`, and a7 is `ctx.sp`.
# `regFileGet`/`regFileSet` are the single-index view the ABI accessors and
# the MOVEM mask use: 0..7 = d0..d7, 8..15 = a0..a7, 16 = sr, 17 = pc.

proc regD(ctx: MCF5307Ctx; n: uint8): uint32 =
  ctx.dRegs[n and 7]

proc regA(ctx: MCF5307Ctx; n: uint8): uint32 =
  let k = n and 7
  if k == 7: ctx.sp else: ctx.aRegs[k]

proc setRegD(ctx: MCF5307Ctx; n: uint8; v: uint32) =
  ctx.dRegs[n and 7] = v

proc setRegA(ctx: MCF5307Ctx; n: uint8; v: uint32) =
  let k = n and 7
  if k == 7: ctx.sp = v else: ctx.aRegs[k] = v

proc regFileGet(ctx: MCF5307Ctx; index: int): uint32 =
  if index in 0 .. 7:
    ctx.dRegs[index]
  elif index in 8 .. 14:
    ctx.aRegs[index - 8]
  elif index == 15:
    ctx.sp
  elif index == 16:
    ctx.sr
  elif index == 17:
    ctx.pc
  else:
    0

proc regFileSet(ctx: MCF5307Ctx; index: int; v: uint32): bool =
  if index in 0 .. 7:
    ctx.dRegs[index] = v
    true
  elif index in 8 .. 14:
    ctx.aRegs[index - 8] = v
    true
  elif index == 15:
    ctx.sp = v
    true
  elif index == 16:
    ctx.sr = v and 0xFFFF'u32
    true
  else:
    false

# ---------------------------------------------------------------------------
# The condition-code bits of the status register. ColdFire keeps the 68k CCR
# in bits 0..4: C at 0, V at 1, Z at 2, N at 3, X at 4.

const
  ccrC = 0x0001'u32
  ccrV = 0x0002'u32
  ccrZ = 0x0004'u32
  ccrN = 0x0008'u32
  ccrX = 0x0010'u32

proc sizeMask(size: uint8): uint32 =
  if size == 4: 0xFFFF_FFFF'u32
  else: (1'u32 shl (8 * size)) - 1'u32

proc setMoveCc(ctx: MCF5307Ctx; value: uint32; size: uint8) =
  ## MOVE, MOVEQ and the other data moves set N and Z from the result and
  ## clear V and C. X is unchanged.
  ctx.sr = ctx.sr and not (ccrN or ccrZ or ccrV or ccrC)
  let msb = 8 * size - 1
  if ((value shr msb) and 1'u32) != 0'u32:
    ctx.sr = ctx.sr or ccrN
  if (value and sizeMask(size)) == 0'u32:
    ctx.sr = ctx.sr or ccrZ

# ---------------------------------------------------------------------------
# Board access, extension words, and the effective-address evaluators.
#
# A bus fault anywhere in an operand access halts the context with `fault`
# set; the callers check `ctx.halted` after each step and unwind.

proc readMem(ctx: MCF5307Ctx; address: uint32; size: uint8): uint32 =
  var st = Mcf5307BusStatus.busOk
  result = ctx.readFn(ctx.user, address, cint(size), addr st)
  if st != Mcf5307BusStatus.busOk:
    ctx.fault = true
    ctx.halted = true

proc writeMem(ctx: MCF5307Ctx; address: uint32; size: uint8; value: uint32) =
  var st = Mcf5307BusStatus.busOk
  ctx.writeFn(ctx.user, address, cint(size), value and sizeMask(size), addr st)
  if st != Mcf5307BusStatus.busOk:
    ctx.fault = true
    ctx.halted = true

proc fetchExt(ctx: MCF5307Ctx): uint16 =
  ## Read one extension word from the instruction stream and advance the pc
  ## past it. The pc-relative base of a PC mode is the pc AFTER its last
  ## extension word, which is exactly where the next instruction begins.
  var st = Mcf5307BusStatus.busOk
  let v = ctx.readFn(ctx.user, ctx.pc, 2, addr st)
  if st != Mcf5307BusStatus.busOk:
    ctx.fault = true
    ctx.halted = true
    return 0'u16
  ctx.pc = ctx.pc + 2'u32
  uint16(v and 0xFFFF'u32)

func s16(x: uint16): int32 =
  int32(int16(x))

func s8(x: uint16): int32 =
  int32(int8(uint8(x and 0xFF'u16)))

proc indexOperand(ctx: MCF5307Ctx; ext: uint16): uint32 =
  ## The scaled index operand of an indexed extension word. Bit 15 selects
  ## Dn(0) or An(1), bits 14..12 the index register, bits 10..9 the scale
  ## (1, 2, 4, 8), bit 8 word(0) or long(1) index, bits 7..0 the signed d8.
  let isAn = (ext and 0x8000'u16) != 0'u16
  let n = (ext shr 12) and 0x7'u16
  let scale = (ext shr 9) and 0x3'u16
  let longIndex = (ext and 0x0100'u16) != 0'u16
  var v = if isAn: regA(ctx, uint8(n)) else: regD(ctx, uint8(n))
  if not longIndex:
    v = uint32(s16(uint16(v and 0xFFFF'u32)))
  v shl scale

proc eaAddr(ctx: MCF5307Ctx; ea: EA; size: uint8): uint32 =
  ## The effective address of a memory-addressing mode. Register and
  ## immediate modes have no address; a caller that asks for one gets 0.
  case ea.mode
  of eaAnInd:
    result = regA(ctx, ea.reg)
  of eaAnPost:
    result = regA(ctx, ea.reg)
    setRegA(ctx, ea.reg, result + uint32(size))
  of eaAnPre:
    result = regA(ctx, ea.reg) - uint32(size)
    setRegA(ctx, ea.reg, result)
  of eaAnDisp:
    result = regA(ctx, ea.reg) + uint32(s16(fetchExt(ctx)))
  of eaAnIndex:
    let ext = fetchExt(ctx)
    result = regA(ctx, ea.reg) + uint32(s8(ext)) + indexOperand(ctx, ext)
  of eaMode7:
    case EA7(ea.reg)
    of ea7AbsW:
      result = uint32(s16(fetchExt(ctx)))
    of ea7AbsL:
      let lo = fetchExt(ctx)
      let hi = fetchExt(ctx)
      result = (uint32(hi) shl 16) or uint32(lo)
    of ea7PCDisp:
      let d = s16(fetchExt(ctx))
      result = ctx.pc + uint32(d)
    of ea7PCIndex:
      let ext = fetchExt(ctx)
      result = ctx.pc + uint32(s8(ext)) + indexOperand(ctx, ext)
    else:
      # ea7Unused5 / ea7Invalid / ea7Unused7: reserved, never a legal EA.
      ctx.fault = true
      ctx.halted = true
      result = 0
  else:
    discard

proc eaRead(ctx: MCF5307Ctx; ea: EA; size: uint8): uint32 =
  ## Read the operand of an effective address. Immediate mode reads its
  ## extension words; register modes read the register (low bits used by the
  ## caller's size); memory modes read through the board.
  case ea.mode
  of eaDn:
    result = regD(ctx, ea.reg)
  of eaAn:
    result = regA(ctx, ea.reg)
  of eaAnInd, eaAnPost, eaAnPre, eaAnDisp, eaAnIndex:
    result = readMem(ctx, eaAddr(ctx, ea, size), size)
  of eaMode7:
    case EA7(ea.reg)
    of ea7AbsW, ea7AbsL, ea7PCDisp, ea7PCIndex:
      result = readMem(ctx, eaAddr(ctx, ea, size), size)
    of ea7Imm:
      if size == 4:
        let hi = fetchExt(ctx)
        let lo = fetchExt(ctx)
        result = (uint32(hi) shl 16) or uint32(lo)
      else:
        result = uint32(fetchExt(ctx))
    else:
      ctx.fault = true
      ctx.halted = true
      result = 0

proc eaWrite(ctx: MCF5307Ctx; ea: EA; size: uint8; value: uint32) =
  ## Write the operand of an alterable effective address. A Dn write keeps
  ## the low size bits; memory modes write through the board; PC-relative
  ## and immediate mode-7 sub-variants are not alterable and trap.
  case ea.mode
  of eaDn:
    setRegD(ctx, ea.reg, value and sizeMask(size))
  of eaAn:
    setRegA(ctx, ea.reg, value)
  of eaAnInd, eaAnPost, eaAnPre, eaAnDisp, eaAnIndex:
    writeMem(ctx, eaAddr(ctx, ea, size), size, value)
  of eaMode7:
    case EA7(ea.reg)
    of ea7AbsW, ea7AbsL:
      writeMem(ctx, eaAddr(ctx, ea, size), size, value)
    else:
      ctx.fault = true
      ctx.halted = true
  else:
    discard

# ---------------------------------------------------------------------------
# The instruction executors.

proc execMove(ctx: MCF5307Ctx; d: Decoded): uint32 =
  ## MOVE.<sz> <ea>,<ea> and MOVEA.<sz> <ea>,An. The source is read first
  ## and the destination second, so a memory-to-memory move observes the
  ## pre-instruction memory.
  let src = eaRead(ctx, d.ea, d.size)
  if ctx.halted:
    return 0
  if d.destMode == 1'u8:
    # MOVEA: no condition-code update, and a .W source sign-extends to 32
    # bits. MOVE.B to an address register is an illegal encoding and is
    # rejected by the caller (moveFamily checks size == 1 before this).
    var v = src
    if d.size == 2:
      v = uint32(s16(uint16(src and 0xFFFF'u32)))
    setRegA(ctx, d.destReg, v)
  else:
    let dst = EA(mode: EAMode(d.destMode), reg: d.destReg)
    if dst.mode == eaMode7 and
        EA7(dst.reg) notin {ea7AbsW, ea7AbsL}:
      # A destination cannot be PC-relative or immediate.
      ctx.fault = true
      ctx.halted = true
      return 0
    eaWrite(ctx, dst, d.size, src)
    if ctx.halted:
      return 0
    setMoveCc(ctx, src, d.size)
  result = 4'u32

proc execMoveq(ctx: MCF5307Ctx; word: uint16; d: Decoded): uint32 =
  let v = uint32(s8(word and 0xFF'u16))
  setRegD(ctx, d.destReg, v)
  setMoveCc(ctx, v, 4)
  result = 4'u32

proc execLea(ctx: MCF5307Ctx; d: Decoded): uint32 =
  let eaAddress = eaAddr(ctx, d.ea, 4)
  if ctx.halted:
    return 0
  setRegA(ctx, d.destReg, eaAddress)
  result = 6'u32

proc execPea(ctx: MCF5307Ctx; d: Decoded): uint32 =
  let eaAddress = eaAddr(ctx, d.ea, 4)
  if ctx.halted:
    return 0
  ctx.sp = ctx.sp - 4'u32
  writeMem(ctx, ctx.sp, 4, eaAddress)
  result = 6'u32

proc execLink(ctx: MCF5307Ctx; d: Decoded): uint32 =
  ## LINK An,#<d16>: push An, set An to the new frame base, then add the
  ## signed displacement to the stack pointer.
  ctx.sp = ctx.sp - 4'u32
  writeMem(ctx, ctx.sp, 4, regA(ctx, d.destReg))
  setRegA(ctx, d.destReg, ctx.sp)
  ctx.sp = ctx.sp + uint32(s16(fetchExt(ctx)))
  result = 8'u32

proc execUnlk(ctx: MCF5307Ctx; d: Decoded): uint32 =
  ## UNLK An: the stack pointer becomes An, An is reloaded from the stack,
  ## and the pointer is advanced past the saved value.
  ctx.sp = regA(ctx, d.destReg)
  setRegA(ctx, d.destReg, readMem(ctx, ctx.sp, 4))
  ctx.sp = ctx.sp + 4'u32
  result = 6'u32

proc execMovem(ctx: MCF5307Ctx; d: Decoded): uint32 =
  ## MOVEM.L reglist,<ea> and MOVEM.L <ea>,reglist. The register mask is
  ## the word that follows the opcode; the EA's own extension words follow
  ## the mask. Registers are stored/loaded in ascending order (d0 first).
  ## MOVEM takes control addressing only, so (An)+ and -(An) never reach
  ## this executor - the legality check in `moveFamily` traps them.
  let mask = fetchExt(ctx)
  if ctx.halted:
    return 0
  let count = countSetBits(mask)
  let base = eaAddr(ctx, d.ea, 4)
  if ctx.halted:
    return 0
  var writeAddr = base
  if not d.memDir:
    # registers -> memory
    for i in 0'u16 .. 15'u16:
      if (mask and (1'u16 shl i)) != 0'u16:
        writeMem(ctx, writeAddr, 4, regFileGet(ctx, int(i)))
        if ctx.halted:
          return 0
        writeAddr = writeAddr + 4'u32
  else:
    # memory -> registers
    for i in 0'u16 .. 15'u16:
      if (mask and (1'u16 shl i)) != 0'u16:
        discard regFileSet(ctx, int(i), readMem(ctx, writeAddr, 4))
        if ctx.halted:
          return 0
        writeAddr = writeAddr + 4'u32
  result = 8'u32 + 2'u32 * uint32(count)

# ---------------------------------------------------------------------------
# The dispatch entry the decoder calls.

proc moveFamily*(ctx: MCF5307Ctx; word: uint16; d: Decoded): uint32 =
  ## Execute one data-movement instruction. Called from the decoder's step
  ## loop with the opcode word and the decoded operation. Returns the
  ## instruction's nominal cycles excluding the fetch; halts the context
  ## with `fault` set on an illegal encoding or an illegal effective
  ## address.
  case d.op
  of opMove, opMovea:
    if d.size == 0 or (d.op == opMovea and d.size == 1):
      # size 00 is the immediate-logic group, not MOVE; MOVE.B to an
      # address register does not exist.
      ctx.fault = true
      ctx.halted = true
      return 0
    if not eaIsLegalFor(d.op, d.ea):
      ctx.fault = true
      ctx.halted = true
      return 0
    result = execMove(ctx, d)
  of opMoveq:
    result = execMoveq(ctx, word, d)
  of opLea:
    if not eaIsLegalFor(opLea, d.ea):
      ctx.fault = true
      ctx.halted = true
      return 0
    result = execLea(ctx, d)
  of opPea:
    if not eaIsLegalFor(opPea, d.ea):
      ctx.fault = true
      ctx.halted = true
      return 0
    result = execPea(ctx, d)
  of opMovem:
    if not eaIsLegalFor(opMovem, d.ea):
      ctx.fault = true
      ctx.halted = true
      return 0
    result = execMovem(ctx, d)
  of opLink:
    result = execLink(ctx, d)
  of opUnlk:
    result = execUnlk(ctx, d)
  else:
    discard

# ---------------------------------------------------------------------------
# The register access the conformance harness needs. The C ABI in
# `include/mcf5307.h` (CPU-0) declares these; the runner's register bridge
# (CPU-5) is the only caller today. `index` 0..7 is d0..d7, 8..14 is a0..a6,
# 15 is a7 (the single stack pointer), 16 is the status register, and 17 is
# the program counter (read-only through this call).

proc mcf5307_set_reg*(ctx: MCF5307Ctx; index: cint; value: uint32): cint
    {.exportc: "mcf5307_set_reg", cdecl, dynlib.} =
  if ctx.isNil or index < 0 or index > 16:
    return cast[cint](0)
  if regFileSet(ctx, int(index), value):
    return cast[cint](1)
  cast[cint](0)

proc mcf5307_get_reg*(ctx: MCF5307Ctx; index: cint): uint32
    {.exportc: "mcf5307_get_reg", cdecl, dynlib.} =
  if ctx.isNil or index < 0 or index > 17:
    return 0'u32
  regFileGet(ctx, int(index))
