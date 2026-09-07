## `move` - the data-movement instruction group of the ColdFire ISA_A core.
##
## This module executes MOVE, MOVEA, MOVEQ, MOVEM, LEA, PEA, LINK and UNLK,
## and nothing else. The register file, the condition-code bits, the board
## accesses and the effective-address evaluation live in `mcf5307/machine`,
## which sits at the `decode_types` level.
##
## The decoder (`mcf5307/decode`) recognizes the instruction words and supplies
## the effective address in bits 5..0 of the word; this module executes them.
## The extension words of an instruction (displacements, index words, immediate
## values, and the MOVEM register mask) live in the instruction stream after
## the opcode word, and are consumed here as the operand evaluation walks them.
## The MOVEM mask precedes the EA extension words, so the mask is fetched
## before the EA's own words.
##
## CYCLES. See the block above the constants in `cpu.nim`. Every instruction in
## this group HAS a timing row - MOVE and MOVEA in Table 2-11 "Move Byte and
## Word" (folio 2-25) and Table 2-12 "Move Long" (2-25 and 2-26), MOVEQ in
## Table 2-13 "Miscellaneous Move" (2-26), LEA in Table 2-15 (2-28), SWAP in
## Table 2-14
## (2-27), and PEA, LINK, UNLK and MOVEM in Table 2-16 (2-29 and 2-30) - and
## NONE OF THE
## RETURNS HERE WAS DERIVED FROM ONE. Some of those rows carry a SINGLE cell
## that the return contradicts outright, so no effective-address flattening
## explains them: `moveq #imm,Dx` is 1(0/0) against the 4 returned, `swap Dx`
## is 1(0/0) against 4, `link.w Ay,#imm` is 2(0/1) against 8, and `unlk Ax` is
## 1(1/0) against 6. `movem.l` is `n(n/0)` loading and `n(0/n)` storing against
## the `8+2n` here.
##
## Instruction semantics, register numbering and addressing-mode behaviour are
## taken from the ColdFire Family Programmer's Reference Manual and the
## MCF5407 User's Manual, and from this project's own measurements.

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
  ## Table 2-8, "User-Level Instruction Set Summary", folio 2-22:
  ## `MSW of Dx <-> LSW of Dx`.
  ##
  ## THE CONDITION CODES COME FROM THE GENERIC CCR RULE, section 2.2.1.5,
  ## folio 2-9. There is no PER-INSTRUCTION rule to find: Table 2-8's Operation
  ## column carries no condition-code clause for SWAP and Table 2-14 gives
  ## timing alone, and those two rows are the only places the manual names SWAP
  ## at all. But the GENERIC rule settles it. Section 2.2.1.5 opens on folio
  ## 2-9 with the CCR bit-field figure and does not end there; Table 2-1,
  ## "CCR Field Descriptions", overleaf on folio 2-10,
  ## carries the per-bit definitions and fixes every one - N "Set if the msb
  ## of the result is set; otherwise cleared", Z "Set if the
  ## result equals zero; otherwise cleared", V "Set if an arithmetic overflow
  ## occurs, implying that the result cannot be represented in the operand
  ## size; otherwise cleared", C "Set if a carry-out of the data operand msb
  ## occurs
  ## for an addition or if a borrow occurs in a subtraction; otherwise
  ## cleared", and X "Assigned the value of the carry bit for arithmetic
  ## operations; otherwise not affected or set to a specified result". An
  ## exchange of a register's halves
  ## is not an addition, not a subtraction and not an arithmetic operation,
  ## so V and C are cleared and X is untouched, and N and Z come from the
  ## result. That is `setNzClearVc` at size 4, which MOVE, MOVEQ, EXT, EXTB
  ## and the 32-bit multiply share. `logic.nim` derives AND, OR, EOR and NOT
  ## from the same clauses.
  ##
  ## Section 2.6 is not an oracle, and the reason has changed with the part.
  ##
  ##   THE REMOVED-LIST OBJECTION IS GONE ON THE MCF5407, AND ITS DISAPPEARANCE
  ##   IS ITSELF A CHANGE OF SUBSTANCE. The MCF5307's section 3.9, page 3-21,
  ##   named "integer division" among the removed instructions while its own
  ##   Table 3-7 carried DIVS and DIVU rows - a list contradicting its tables.
  ##   The MCF5407's section 2.6, folio 2-15, names "BCD, bit field, logical
  ##   rotate, decrement and branch, and integer multiply with a 64-bit result"
  ##   and does NOT name integer division, because the V4 core has a hardware
  ##   divide unit (section 2.1.2.2.3, folio 2-6). Table 2-8 carries DIVS,
  ##   DIVU, REMS and REMU and Table 2-15 times `divs.w`, `divu.w`, `divs.l`,
  ##   `divu.l`, `rems.l` and `remu.l`. List and tables now agree.
  ##
  ##   What still stands is the second reason, which never depended on the
  ##   first. "A simplified version of the M68000 instruction set" is a claim
  ##   about set
  ##   membership, not about per-instruction semantics. Table 2-8 gives ADD,
  ##   SUB, AND, OR and EOR an operand size of `.L` alone where the 68000
  ##   has `.b`, `.w` and `.l`. (CMP and CMPI are no longer among them: the
  ##   V4's ISA_B additions restore their byte and word forms, section 2.6.1,
  ##   folio 2-18.) Retained instructions on this part are not
  ##   semantically identical to their 68000 originals, so "retained,
  ##   therefore 68000 semantics" does not follow in general - and it is not
  ##   what pins these flags. Section 2.2.1.5 is.
  ##
  ## The width is settled, and the User's Manual alone did not settle it:
  ## section 2.2.1.5 says only "the result" and Table 2-8's Operand Size column
  ## for SWAP says `.W`, which reads as the low half. CFPRM folio 4-81 gives
  ## the
  ## operation as `Register[31:16] <-> Register[15:0]` and N as "Set if the msb
  ## of the result is set", Z as "Set if the result is zero". The result of
  ## that operation is the whole register, so N is bit 31 and Z spans all 32
  ## bits - which is the size argument of 4 below, not 2.
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
    # No test should be written to reach it: reaching it needs a
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
    # Unreachable from `cpu.nim`, which routes exact opcodes. It refuses rather
    # than returning 0 because returning 0 costs nothing and halts nothing: the
    # program counter would advance past an instruction that never executed and
    # the core would run on into whatever followed. Refusing is the same
    # observable `aluFamily` gives an opcode it does not carry.
    ctx.fault = true
    ctx.halted = true
    result = 0'u32
