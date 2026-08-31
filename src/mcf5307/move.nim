## `move` - the data-movement instruction group of the ColdFire ISA_A core.
##
## This module executes MOVE, MOVEA, MOVEQ, MOVEM, LEA, PEA, LINK and UNLK,
## and nothing else. The register file, the condition-code bits, the board
## accesses and the effective-address evaluation live in `mcf5307/machine`,
## which sits at the `decode_types` level and which both this module and
## `alu.nim` import.
##
## The decoder (`mcf5307/decode`) recognizes the instruction words and
## supplies the effective address in bits 5..0 of the word; this module
## executes them. This module and the decoder are siblings. Both read the
## shared types from `mcf5307/decode_types`, and neither imports the other.
## `mcf5307/cpu` sits above both: it owns `step`, and `step` is the one
## procedure that calls the decoder and then calls `moveFamily` below.
## The extension words of an instruction (displacements,
## index words, immediate values, and the MOVEM register mask) live in the
## instruction stream after the opcode word, and are consumed here as the
## operand evaluation walks them. The MOVEM mask precedes the EA extension
## words, so the mask is fetched before the EA's own words.
##
## Cycles are nominal. The per-instruction cycle budget on serial MCF5307
## silicon is not settled, so no exact cost is asserted anywhere.
##
## Instruction semantics, register numbering and addressing-mode behaviour are
## taken from the ColdFire Family Programmer's Reference Manual and the
## MCF5307 User's Manual, and from this project's own measurements.

import std/bitops
import mcf5307/decode_types
import mcf5307/ea
import mcf5307/machine

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
    setNzClearVc(ctx, src, d.size)
  result = 4'u32

proc execMoveq(ctx: MCF5307Ctx; word: uint16; d: Decoded): uint32 =
  let v = uint32(s8(word and 0xFF'u16))
  setRegD(ctx, d.destReg, v)
  setNzClearVc(ctx, v, 4)
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
# The dispatch entry `step` calls.

proc moveFamily*(ctx: MCF5307Ctx; word: uint16; d: Decoded): uint32 =
  ## Execute one data-movement instruction. Called from `step` in
  ## `mcf5307/cpu` with the opcode word and the decoded operation. Returns the
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
