## `move` - the data-movement instruction group of the ColdFire ISA_A core.
##
## This module executes MOVE, MOVEA, MOVEQ, MOVEM, LEA, PEA, LINK and UNLK,
## AND NOTHING ELSE.
##
## The register file, the condition-code bits, the board accesses and the
## effective-address evaluation live in `mcf5307/machine`, which sits at the
## `decode_types` level and which both this module and `alu.nim` import.
## `alu.nim` importing `move.nim` for them would have put one executor under
## another. What is left here is the data-movement SEMANTICS alone.
##
## The decoder (`mcf5307/decode`) recognizes the instruction words and
## supplies the effective address in bits 5..0 of the word; this module
## executes them. THIS MODULE AND THE DECODER ARE SIBLINGS. Both read the
## shared types from `mcf5307/decode_types`, and neither imports the other.
## `mcf5307/cpu` sits above both: it owns `step`, and `step` is the one
## procedure that calls the decoder and then calls `moveFamily` below.
## The extension words of an instruction (displacements,
## index words, immediate values, and the MOVEM register mask) live in the
## instruction stream after the opcode word, and are consumed here as the
## operand evaluation walks them. The MOVEM mask precedes the EA extension
## words, so the mask is fetched before the EA's own words.
##
## CYCLES. The block above the constants in `cpu.nim` says why nothing checks
## any of them. Every instruction in this group HAS a timing row, and NONE OF
## THE RETURNS HERE WAS DERIVED FROM ONE. Some of those rows carry a SINGLE
## cell that the return contradicts outright, so no effective-address
## flattening explains them: `moveq #imm,Dx` is 1(0/0) against the 4 returned,
## `swap Dx` is 1(0/0) against 4, `link.w Ay,#imm` is 2(0/1) against 8, and
## `unlk Ax` is 3(1/0) against 6. `movem.l` is `2+n` against the `8+2n` here.
##
## MIT licensed and clean-room with respect to GPL and LGPL code. Instruction
## semantics, register numbering and addressing-mode behaviour are facts
## about Motorola silicon; they are taken from the ColdFire Family
## Programmer's Reference Manual and the MCF5307 User's Manual and from this
## project's own measurements.

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

proc execSwap(ctx: MCF5307Ctx; d: Decoded): uint32 =
  ## SWAP Dn: the upper and lower 16-bit halves of a data register exchange -
  ## `MSW of Dn <-> LSW of Dn`.
  ##
  ## THE CONDITION CODES COME FROM THE GENERIC CCR RULE. There is no
  ## PER-INSTRUCTION rule to find: the OPERATION column carries no
  ## condition-code clause for SWAP and the timing table gives timing alone,
  ## and those rows are the only places SWAP is named at all. But the GENERIC
  ## rule settles it. The per-bit definitions fix every one - N "Set if the most
  ## significant bit of the result is set; otherwise cleared", Z "Set if the
  ## result equals zero; otherwise cleared", V "Set if an arithmetic overflow
  ## occurs implying that the result cannot be represented in the operand
  ## size; otherwise cleared", C "Set if a carryout of the operand MSB occurs
  ## for an addition, or if a borrow occurs in a subtraction; otherwise
  ## cleared", and X "Set to the value of the C-bit for arithmetic
  ## operations; otherwise not affected". An exchange of a register's halves
  ## is not an addition, not a subtraction and not an arithmetic operation,
  ## so V and C are CLEARED and X is UNTOUCHED, and N and Z come from the
  ## result. That is `setNzClearVc` at size 4, which MOVE, MOVEQ, EXT, EXTB
  ## and the 32-bit multiply share.
  ##
  ## THIS IS THE ARGUMENT `logic.nim` ALREADY RUNS, not a new one. It derives
  ## AND, OR, EOR and NOT from these same clauses - "a logical operation is
  ## none of those things" - and guards X on a shift by zero from the same
  ## "otherwise not affected". One derivation used twice.
  ##
  ## THE REMOVED-INSTRUCTION LIST IS NOT AN ORACLE, for two independent
  ## reasons:
  ##
  ##   It is not reliable. It names "integer division" among the removed
  ##   instructions, while the instruction summary carries both a DIVS row and
  ##   a DIVU row and the timing table times `divs.w`, `divu.w`, `divs.l` and
  ##   `divu.l`. A list that contradicts the tables cannot settle a question on
  ##   its own.
  ##
  ##   "A reduced version of the 68000 instruction set" is a claim about SET
  ##   MEMBERSHIP, not about per-instruction semantics. ADD, SUB, AND, OR, EOR
  ##   and CMP are given an OPERAND SIZE of 32 ALONE where the 68000 has `.b`,
  ##   `.w` and `.l`. Retained instructions on this part are NOT semantically
  ##   identical to their 68000 originals, so "retained, therefore 68000
  ##   semantics" does not follow in general - and it is not what pins these
  ##   flags. The generic CCR rule is.
  ##
  ## WHAT REMAINS UNPINNED IS THE WIDTH, AND IT IS REAL. The generic rule says
  ## "the result" and never says how wide that result is, and SWAP's OPERAND
  ## SIZE says 16. A reader who reads "the result" as the 16-bit half takes N
  ## from bit 15 and Z from the low half. This core reads it as the whole
  ## 32-bit register, because the register is what the instruction writes -
  ## THE SIZE ARGUMENT IS 4 AND NOT 2 FOR EXACTLY THAT REASON. A
  ## per-instruction reference would close the width question outright; it is
  ## unobtainable.
  ##
  ## THE PRECEDENT IS DISCIPLINE, NOT LICENCE. `logic.nim` met the same wall on
  ## `ASL`'s overflow reading and on the status word of a shift by zero,
  ## derived from the generic rule everything it could, and then DECLINED to
  ## pin the residue. Citing that as permission to infer inverts it. These
  ## flags are pinned because the generic rule DERIVES them; the width, which
  ## it does not derive, is called out above rather than asserted.
  let v = regD(ctx, d.destReg)
  let swapped = (v shr 16'u32) or (v shl 16'u32)
  setRegD(ctx, d.destReg, swapped)
  setNzClearVc(ctx, swapped, 4)
  result = 4'u32

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
  ## `mcf5307/cpu` with the opcode word and the decoded operation. Returns a
  ## PLACEHOLDER cycle count excluding the fetch - see the cycle block in
  ## `cpu.nim` - and halts the context with `fault` set on an illegal encoding
  ## or an illegal effective address.
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
  of opSwap:
    # THIS GUARD CANNOT CURRENTLY TAKE ITS FALSE BRANCH, AND THAT IS
    # DISCLOSED HERE RATHER THAN LEFT FOR A READER TO DISCOVER. By
    # construction: `opSwap` has exactly one producer, the `decodeWord` arm
    # guarded by `(word and 0xFFF8) == 0x4840`, so every word reaching here
    # is in `4840`-`4847`; `decodeEa` takes the mode from bits 5..3, which
    # are `000` in all eight of those words; and `eaLegalityFor(opSwap)` is
    # `{eaDn}`, which mode `000` is inside. So `eaIsLegalFor` is always true
    # for `opSwap` and the fault below is unreachable TODAY.
    #
    # IT IS KEPT, NOT DELETED, because the decoder arm that makes it dead
    # says in its own comment that widening its mask back to `0xFFC0` is the
    # regression to fear. That widening is what would make this branch
    # reachable: `4840`-`487f` would then decode as SWAP, modes other than
    # `000` would arrive, and this guard would fault them instead of letting
    # `execSwap` exchange the halves of a register the operand never named.
    # For that to be correct, `eaLegalityFor(opSwap)` must still be `{eaDn}`
    # - the legality table, not this call site, is where SWAP's operand rule
    # lives. Deleting the guard would also make `opSwap` the only arm of this
    # `case` without the check its siblings all perform.
    #
    # NO TEST SHOULD BE WRITTEN TO REACH IT. Reaching it needs a decoder
    # change, so a test that covered it would have to introduce the very
    # defect the mask ordering prevents.
    if not eaIsLegalFor(opSwap, d.ea):
      ctx.fault = true
      ctx.halted = true
      return 0
    result = execSwap(ctx, d)
  of opLink:
    result = execLink(ctx, d)
  of opUnlk:
    result = execUnlk(ctx, d)
  else:
    discard
