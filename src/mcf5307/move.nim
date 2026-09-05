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
## Cycles. The block above the constants in `cpu.nim` says why nothing checks
## any of them. Every instruction in this group has a timing row - MOVE and
## MOVEA in Tables 3-9 and 3-10 (folios 3-26 and 3-27), MOVEQ and LEA in Table
## 3-13 (3-28), SWAP in Table 3-12 (3-27), and PEA, LINK, UNLK and MOVEM in
## Table 3-14 (3-29) - and none of the returns here was derived from one. Four
## of those rows carry a single cell that the return contradicts outright, so
## no effective-address flattening explains them: `moveq #imm,Dx` is 1(0/0)
## against the 4 returned, `swap Dx` is 1(0/0) against 4, `link.w Ay,#imm` is
## 2(0/1) against 8, and `unlk Ax` is 3(1/0) against 6. `movem.l` is `2+n`
## against the `8+2n` here.
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

proc execSwap(ctx: MCF5307Ctx; d: Decoded): uint32 =
  ## SWAP Dn: the upper and lower 16-bit halves of a data register exchange.
  ## Table 3-7, page 3-25: `MSW of Dn <-> LSW of Dn`.
  ##
  ## The condition codes come from section 3.2.1.5, page 3-9. There is no
  ## per-instruction rule to find: Table 3-7's operation column carries no
  ## condition-code clause for SWAP and Table 3-12 gives timing alone, and
  ## those two rows are the only places the manual names SWAP at all. The
  ## generic rule settles it. Section 3.2.1.5 opens at the foot of page 3-8
  ## with the CCR bit-field figure and does not end there; page 3-9 carries
  ## the per-bit definitions and fixes all five - N "Set if the most
  ## significant bit of the result is set; otherwise cleared", Z "Set if the
  ## result equals zero; otherwise cleared", V "Set if an arithmetic overflow
  ## occurs implying that the result cannot be represented in the operand
  ## size; otherwise cleared", C "Set if a carryout of the operand MSB occurs
  ## for an addition, or if a borrow occurs in a subtraction; otherwise
  ## cleared", and X "Set to the value of the C-bit for arithmetic
  ## operations; otherwise not affected". An exchange of a register's halves
  ## is not an addition, not a subtraction and not an arithmetic operation,
  ## so V and C are cleared and X is untouched, and N and Z come from the
  ## result. That is `setNzClearVc` at size 4, which MOVE, MOVEQ, EXT, EXTB
  ## and the 32-bit multiply share. `logic.nim` derives AND, OR, EOR and NOT
  ## from the same clauses.
  ##
  ## Section 3.9 is not an oracle. Two independent reasons it cannot be:
  ##
  ##   Its removed list is not reliable. Page 3-21 names "integer division"
  ##   among the removed instructions, while Table 3-7 on page 3-23 carries
  ##   both a DIVS row and a DIVU row and Table 3-13 on page 3-28 times
  ##   `divs.w`, `divu.w`, `divs.l` and `divu.l`. A list that contradicts two
  ##   tables cannot settle a question on its own.
  ##
  ##   "A reduced version of the 68000 instruction set" is a claim about set
  ##   membership, not about per-instruction semantics. Table 3-7 gives ADD,
  ##   SUB, AND, OR, EOR and CMP an operand size of 32 alone where the 68000
  ##   has `.b`, `.w` and `.l`. Retained instructions on this part are not
  ##   semantically identical to their 68000 originals, so "retained,
  ##   therefore 68000 semantics" does not follow in general - and it is not
  ##   what pins these flags. Section 3.2.1.5 is.
  ##
  ## What remains unpinned is the width. Section 3.2.1.5 says
  ## "the result" and never says how wide that result is, and Table 3-7's
  ## operand size column for SWAP says 16. A reader who reads "the result" as
  ## the 16-bit half takes N from bit 15 and Z from the low half. This core
  ## reads it as the whole 32-bit register, because the register is what the
  ## instruction writes - the size argument is 4 and not 2 for exactly that
  ## reason. The ambiguity shows on `0x0000FFFF` and `0xFFFF0000`, the two
  ## shapes whose halves disagree in their top bit. The CFPRM would close the
  ## width question outright.
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
  ## placeholder cycle count excluding the fetch - see the cycle block in
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
    # This guard cannot currently take its false branch. By
    # construction: `opSwap` has exactly one producer, the `decodeWord` arm
    # guarded by `(word and 0xFFF8) == 0x4840`, so every word reaching here
    # is in `4840`-`4847`; `decodeEa` takes the mode from bits 5..3, which
    # are `000` in all eight of those words; and `eaLegalityFor(opSwap)` is
    # `{eaDn}`, which mode `000` is inside. So `eaIsLegalFor` is always true
    # for `opSwap` and the fault below is unreachable today.
    #
    # It is kept, not deleted, because the decoder arm that makes it dead
    # says in its own comment that widening its mask back to `0xFFC0` is the
    # regression to fear. That widening is what would make this branch
    # reachable: `4840`-`487f` would then decode as SWAP, modes other than
    # `000` would arrive, and this guard would fault them instead of letting
    # `execSwap` exchange the halves of a register the operand never named.
    # For that to be correct, `eaLegalityFor(opSwap)` must still be `{eaDn}`
    # - the legality table, not this call site, is where SWAP's operand rule
    # lives.
    #
    # None should be written to: reaching it needs a
    # decoder change, so a test that covered it would have to introduce the
    # very defect the mask ordering prevents.
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
