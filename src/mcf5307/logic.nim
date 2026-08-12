## `logic` - the logic, bit-operation and shift instruction group of the
## ColdFire ISA_A core. Task CPU-9 creates this file. Design section 6.1.
##
## This module executes AND, ANDI, OR, ORI, EOR, EORI, NOT, BTST, BSET, BCLR,
## BCHG, LSL, LSR, ASL and ASR, AND NOTHING ELSE. The register file, the board
## accesses and the effective-address evaluation are `mcf5307/machine`'s.
##
## THIS MODULE IS A SIBLING OF `move.nim`, `alu.nim` AND `decode.nim`. It
## imports none of them and none of them imports it; its whole import list is
## `{decode_types, ea, machine}`. Adding this group cost one new module, one
## `import` line in `cpu.nim` and one arm of the `case` there, and
## `decode.nim` gained the opcodes and NO import. The rule and the reason are
## in `~/Desktop/avoiding-cycles.md`: an executor that reaches into another
## executor for a helper rebuilds the decoder-under-executor cycle one layer
## down, and a shape that is merely awkward at two siblings is unworkable at
## four.
##
## THE SIZE IS LONG AND THE EXCEPTIONS ARE NAMED. Every operation in this
## group is 32-bit on this part, which the MCF5307 User's Manual Table 3-7
## states for each of them, and `m68k-elf-as -mcpu=5307` confirms by rejecting
## `and.b %d0,%d1`, `not.w %d0`, `andi.b #5,%d1` and `lsl.w #1,%d0`. The one
## exception is the bit operations, whose operand is 32 bits WHEN IT IS A DATA
## REGISTER and 8 bits otherwise - the "8,32" of that same table. Every byte
## and word form of everything else TRAPS here; CPU-13 carries them as
## negative cases.
##
## EVERY SHIFT IS REGISTER-ONLY AND A MEMORY SHIFT TRAPS. MCF5307 User's
## Manual Table 3-13, page 3-28: the `asl.l`, `asr.l`, `lsl.l` and `lsr.l`
## rows all read `<ea>,Dx` and carry a time under `Rn` and under `#xxx` ALONE
## - `1(0/0)` in each - with A DASH under `(An)`, `(An)+`, `-(An)`,
## `(d16,An)`, `(d8,An,Xi*SF)` and `xxx.wl`. A shift on this part reaches a
## data register and an immediate COUNT and no memory operand at all, and the
## `{Dn}` mask in `decode_types` refuses that operand.
##
## THE WITNESS IS `e2d0` AND NOT `e0c0`. `e2d0` is `1110 001 0 11 010 000` -
## a memory shift whose operand is `(%a0)` - and it decodes as `lsrw %a0@` on
## `m68k-elf-objdump -m m68k:68000` and as `.short 0xe2d0` on `-m m68k:5307`,
## which is the whole demonstration. An earlier revision cited `e0c0` beside
## it. THAT WORD DEMONSTRATES NOTHING: it decodes on NEITHER architecture,
## because its low six bits are mode 000 - a data register - which is not a
## memory operand on the 68000 either, so its refusal is not ColdFire's doing.
##
## THE ROTATES ARE GONE TOO: manual section 3.9 lists "logical rotate" among
## the removed instructions, and `decode.nim` never produces an operation for
## them. CPU-13 owns both negative cases; this module and that mask are the
## mechanism they assert through.
##
## THE CONDITION CODES, AND WHERE EACH RULE COMES FROM.
##
##   AND, ANDI, OR, ORI, EOR, EORI, NOT
##       N and Z from the result, V and C cleared, X UNTOUCHED. Manual section
##       3.2.1.5 defines V as an ARITHMETIC overflow, C as a carry out of an
##       ADDITION or a borrow in a SUBTRACTION, and X as taking C's value "for
##       arithmetic operations; otherwise not affected". A logical operation
##       is none of those things. That is exactly `setNzClearVc`, which
##       `machine.nim` already holds for the same rule under MOVE, and this
##       module calls it rather than write a second copy.
##
##   BTST, BSET, BCLR, BCHG
##       Z ALONE, and Z is the COMPLEMENT of the bit tested. Manual Table 3-7
##       gives the operation as `~(<Bit Number> of Destination) -> Z` and
##       names no other bit, so N, V, C and X are left exactly as they were.
##
##   LSL, LSR, ASL, ASR
##       X AND C BOTH TAKE THE LAST BIT SHIFTED OUT, which Table 3-7 states
##       for all four (`X/C <- (Dy << Dx) <- 0` and the two right-shift
##       forms). N and Z come from the result. V IS CLEARED BY ALL FOUR, ASL
##       INCLUDED, and the ColdFire Family Programmer's Reference Manual says
##       so in its own words rather than by inference from the word
##       "arithmetic". Folio 4-12 gives V a flat "Always cleared" in the
##       condition-code table and adds "Note that CCR[V] is always cleared by
##       ASL and ASR, unlike on the 68K family processors"; folio 4-11 says
##       "The overflow bit is always zero". THIS PART COMPUTES NO SHIFT
##       OVERFLOW AT ALL.
##
##       AN EARLIER REVISION IMPLEMENTED THE 68000 RULE - V set when the sign
##       changed - and reasoned its way there from section 3.2.1.5's
##       definition of V as an ARITHMETIC overflow: LSL and LSR are logical so
##       V is clear, ASR cannot leave the operand size, ASL can and therefore
##       sets V. The reasoning is sound about the 68000 and wrong about this
##       part, which is exactly what the CFPRM note calls out. The User's
##       Manual never contradicted it; it simply does not carry the
##       per-instruction flag table that settles it.
##
## THE SHIFT IS PERFORMED ONE BIT AT A TIME, ON PURPOSE. A count is at most 63
## and the loop costs nothing, and it makes the carry rule that is easy to get
## wrong in closed form come out by construction: the carry is THE LAST BIT
## THAT LEFT THE WORD rather than a bit of the result.
##
## AN EARLIER REVISION OF THIS PARAGRAPH FRAMED A DICHOTOMY THAT DOES NOT
## EXIST - "the sign changed AT ANY POINT during the shift" against "the sign
## of the result differs from the sign of the operand" - and then held the
## corpus back from asserting V at any count where the two readings disagree,
## on the stated ground that the document separating them was unavailable.
## BOTH HALVES WERE WRONG. The CFPRM is on disk, it names neither reading, and
## it gives V a flat "Always cleared" for ASL (folios 4-11 and 4-12). There is
## no reading to choose between and no count that separates anything.
##
## A SHIFT COUNT OF ZERO IS REACHABLE THROUGH THE REGISTER FORM ALONE, because
## the immediate form spends its zero slot on the value eight. It shifts
## nothing. ONE OF THE FIVE FLAGS HAS A REASON AND FOUR ARE A CHOICE, and the
## code and this paragraph now say the same thing about which is which:
##
##   X IS LEFT ALONE, AND THAT ONE IS REASONED. Section 3.2.1.5 gives X the
##   value of C "for arithmetic operations; otherwise not affected", and a
##   shift that moved no bit produced no carry to copy. `execShift` guards X
##   with `count != 0` for exactly this.
##
##   N, Z, V AND C ARE WRITTEN ANYWAY - N and Z from the unmoved operand, V
##   and C cleared - AND THAT IS THIS MODULE'S CHOICE AND NOT A RULE ANY
##   DOCUMENT ON THIS MACHINE STATES. An earlier revision of this paragraph
##   asserted "clears C" as a fact while also saying the status word of that
##   case cannot be decided; both cannot be true. It is undecided, the code
##   still has to do something, and what it does is written here so that a
##   reader is not left to infer it. THE CORPUS ASSERTS THE DESTINATION OF
##   THAT CASE AND NOT ITS STATUS WORD, which is what keeps the choice
##   unpinned.
##
## CYCLES ARE NOMINAL, for the reason `move.nim`, `alu.nim` and `cpu.nim` all
## give: the per-instruction budget needs the clock work of open question 6 in
## AGENTS.md and no exact cost is asserted anywhere.
##
## WHAT THIS MODULE DOES NOT KNOW. Five things, and the rule for every one of
## them is the same: THE IMPLEMENTATION PICKS A BEHAVIOUR AND NOTHING ASSERTS
## IT.
##
## THE LIST WAS SIX AND THE CFPRM SETTLED ONE OF THEM. An earlier revision
## recorded that the ColdFire Family Programmer's Reference Manual "is NOT on
## this machine" and hung five of the six entries on that absence. THE RECORD
## WAS FALSE. The manual is on disk at `~/Development/datasheets/CFPRM.pdf`
## (Rev. 3), its per-instruction pages give the flag rules directly, and its
## ASL page settled what was entry 1 - ASL'S OVERFLOW READING - by stating
## that ColdFire computes no ASL overflow at all. That entry is gone and the
## rest are renumbered.
##
## THE REMAINING FIVE HAVE NOT BEEN RE-CHECKED AGAINST IT. Entries 3, 4 and 5
## below are per-instruction questions of exactly the kind the CFPRM answers,
## and the change that deleted entry 1 did not open their pages. Treat "the
## document is unavailable" as retracted and "these are still open" as
## UNVERIFIED rather than as a standing finding.
##
##   1. THE STATUS WORD OF A SHIFT BY ZERO. See the paragraph above.
##
##   2. THE EXACT CYCLE COUNT of every instruction in this group. NOTHING
##      ASSERTS IT, AND `tests/t_logic.nim`'s `cycles` FIELD IS NOT A COUNTER-
##      CASE THOUGH ITS NAME READS LIKE ONE. That field is the return of
##      `mcf5307_exec(ctx, 1)`, and `mcf5307_exec` SATURATES AT ITS BUDGET: a
##      cost of 2 for the fetch plus anything this module returns already
##      exceeds a budget of one, so the value is 1 for an instruction that ran
##      and 0 for one that trapped, and it cannot see a count at all. MEASURED:
##      ALL NINE cycle returns in this module replaced by wrong numbers - 44,
##      66, 45, 65, 66, 46, 41, 61 and 47 in source order, `trap`'s zero left
##      alone - every one confirmed in the generated C, rebuilt from a fresh
##      configure of a fresh extract; all 74 `t_logic` cases and all 74 corpus
##      cases stayed GREEN.
##
##   3. WHETHER A DYNAMIC BTST MAY READ AN IMMEDIATE OPERAND. User's Manual
##      Table 3-13, page 3-28, dashes the `#xxx` column of the `btst Dy,<ea>`
##      row, and `m68k-elf-as -mcpu=5307` assembles `btst %d1,#5` anyway. The
##      mask follows the manual and traps it; the full evidence, including why
##      the assembler's acceptance is the 68000's rule rather than this part's,
##      is on `eaBitDynamic` in `decode_types.nim`.
##
##      THE SECOND TABLE IS TABLE 3-5 ON PAGE 3-21, AND IT IS NAMED HERE so
##      that "two tables of one manual disagree" is a sentence a reader can
##      check without leaving this list. That table is "Effective Addressing
##      Modes and Categories" and it marks Immediate `#<xxx>` with an `x` in
##      the DATA column. A dynamic BTST READS its operand, so the DATA class is
##      its class, and that column RESTORES the immediate the timing table
##      dashes. Cutting the other way, Table 3-7 on page 3-23 gives BTST's
##      operand syntax as `Dy,<ea>x`, and the `x` suffix is the manual's
##      DESTINATION mark - `CLR <ea>x` is "0 -> Destination" and
##      `CMP <ea>y,Dx` is "Destination - Source" - which an immediate cannot
##      be.
##
##      THIS ONE IS ASSERTED, in `tests/t_logic.nim`, because a mask must be
##      one thing or the other and a trap that no case covers is a trap nothing
##      measures. IT IS ASSERTED TWICE AND A READER WHO REVERSES IT MUST CHANGE
##      BOTH: the `btst %d1,#5` trap case, and the
##      `checkMask(eaIsLegalFor(opBtst, decodeEa(0x3C)), false, ...)` row that
##      this commit flipped from `true`. MEASURED: `eaBitDynamic`'s `ea7`
##      restored to the full valid mode-7 set (then `eaData7`, now
##      `eaValid7`), confirmed in the generated C as `{253, 31}`
##      against this commit's `{253, 15}`, rebuilt from a fresh configure of a
##      `git archive` of this commit - `t_logic: 2 of 74 cases failed`, exactly
##      those two, and the corpus stayed 41 of 41. It is the one entry on this
##      list that a future reader may have to REVERSE rather than merely fill
##      in.
##
##   4. THE BIT NUMBER'S MODULUS. `execBitOp` reduces the number modulo the
##      operand width - 32 for a data register, 8 for memory. Table 3-7 gives
##      the two WIDTHS ("8,32") and states no modulus anywhere, and no other
##      passage does either. Figure 3-8 on page 3-18 is the closest thing and
##      it does not carry the weight: its `BIT` row reads "BIT (0 <= MODULO
##      (OFFSET) < 31, OFFSET OF 0 = MSB)", which numbers from the MSB where
##      every bit operation here numbers from the LSB, stops at 31 rather than
##      including it, and uses the word OFFSET, which belongs to the bit-field
##      instructions section 3.9 lists among the REMOVED ones.
##
##      THE MEMORY HALF IS PINNED BY THE CORPUS AND THE REGISTER HALF IS NOT.
##      An earlier revision of this entry said the corpus "asserts no
##      out-of-range bit number", and that was false.
##      `bchg_b_memory_dynamic_bit_number` in
##      `conformance/corpus/logic_00.json` is `bchg %d1,(%a0)` WITH d1 = 9
##      AGAINST A BYTE MEMORY OPERAND - 9 is outside the range a byte holds -
##      and its expected result is the modulo-8 answer AND NOTHING ELSE: the
##      byte at 0x2000 goes 0x02 to 0x00, which is bit 1 cleared, and sr goes
##      0x271f to 0x271b, which is Z cleared because bit 1 was found SET.
##
##      THE RIVAL READINGS ALL MISS IT, AND TWO OF THE THREE ARE COVERED BY
##      THE MUTATION BELOW. MODULO 32 selects bit 9 of a byte that has no bit
##      9, so Z comes out SET and the byte keeps 0x02; NO REDUCTION AT ALL
##      selects bit 9 too, which is the same computation at this bit number, so
##      the same mutant answers for it. A CLAMP TO 7 selects bit 7, so Z comes
##      out SET and the byte becomes 0x82 - that third one is arithmetic a
##      reader can check and it was NOT RUN. Only the modulo-8 reading gives
##      0x00 with Z clear.
##
##      MEASURED: `and (8 * size - 1)` in `execBitOp` replaced by `and 31`,
##      confirmed in the generated C as
##      `bit_1 = (NU32)(bitNumber_1 & ((NU32)31));`, rebuilt from a fresh
##      configure of a fresh extract - `mcf5307_conformance_logic: 41 cases,
##      1 failed`, that case, `sr differs: expected=0x271b actual=0x271f`.
##
##      BOTH HALVES OF THE CASE FAIL AND THE RUNNER SHOWS ONLY THE FIRST. It
##      prints ONE mismatch per case and it compares the registers before the
##      memory. With that case's expected `sr` deleted IN A SCRATCH COPY, so
##      that the comparison reaches the byte, the same mutant reports
##      `mem[8192:1] differs: expected=0x0 actual=0x2`. The destination and the
##      status word are each the modulo-8 answer and each refuses the modulo-32
##      one.
##
##      All 74 `t_logic` cases stayed GREEN under the same mutation, so THE
##      CORPUS IS THE ONLY THING THAT HOLDS IT.
##
##      WHAT REMAINS UNPINNED IS THE 32-BIT MODULUS, and the bit numbers are
##      enumerated here rather than summarised. The corpus holds ELEVEN
##      bit-operation cases. The SEVEN with a DATA REGISTER operand use 4, 7,
##      9, 9, 7, 4 and 7; the FOUR with a MEMORY operand use 1, 0, 1 and the 9
##      above. `tests/t_logic.nim` executes bit numbers 3, 6 and 7 and every
##      one is inside the width its operand holds. So nothing separates modulo
##      32 from a wider reduction or from no reduction at all for a REGISTER
##      operand, and nothing pins the MEMORY reduction at any bit number except
##      9.
##
##   5. THE REGISTER SHIFT COUNT'S MODULUS. `execShift` takes it modulo 64.
##      Table 3-7 gives the shift operations as `X/C <- (Dy << Dx) <- 0` and
##      states no modulus, and no other passage does. No case in the corpus or
##      in `tests/t_logic.nim` uses a count above 31, so nothing distinguishes
##      modulo 64 from modulo 256 or from no reduction at all.
##
## MIT licensed and clean-room with respect to GPL and LGPL code. Instruction
## semantics, the condition-code rules and the encodings are facts about
## Motorola silicon; they are taken from the ColdFire Family Programmer's
## Reference Manual and the MCF5307 User's Manual (AGENTS.md section 11) and
## from this project's own measurements with the pinned cross assembler. No
## expression was taken from any copyleft source.

import mcf5307/decode_types
import mcf5307/ea
import mcf5307/machine

# ---------------------------------------------------------------------------
# Trapping.

proc trap(ctx: MCF5307Ctx): uint32 =
  ## Halt the context with `fault`. Every illegal size and illegal operand
  ## mode in this module ends here, so that "the core refused" is one
  ## observable and not several.
  ctx.fault = true
  ctx.halted = true
  0'u32

# ---------------------------------------------------------------------------
# The three bitwise combinations, named once.

proc combine(op: Operation; src, dst: uint32): uint32 =
  ## `src op dst`. THE ORDER OF THE TWO OPERANDS DOES NOT MATTER for any of
  ## the three, which is why one procedure serves both directions of AND and
  ## OR and the single direction of EOR.
  case op
  of opAnd, opAndi: src and dst
  of opOr, opOri: src or dst
  else: src xor dst

# ---------------------------------------------------------------------------
# AND and OR, both directions.

proc execAndOr(ctx: MCF5307Ctx; d: Decoded): uint32 =
  ## `<ea> op Dn -> Dn` when `dirToEa` is false, `Dn op <ea> -> <ea>` when it
  ## is true. THE TWO DIRECTIONS CARRY DIFFERENT OPERAND MASKS: the first
  ## READS any data-addressing mode, the immediate and the PC-relative pair
  ## included, and the second WRITES a memory-alterable one. A single mask
  ## would let `and.l %d1,(4,%pc)` through, which `m68k-elf-objdump` does not
  ## decode as an instruction at all.
  if d.size != 4'u8:
    return trap(ctx)
  if not d.dirToEa:
    if not eaIsLegalFor(d.op, d.ea):
      return trap(ctx)
    let src = eaRead(ctx, d.ea, 4)
    if ctx.halted: return 0'u32
    let res = combine(d.op, src, regD(ctx, d.destReg))
    setRegD(ctx, d.destReg, res)
    setNzClearVc(ctx, res, 4)
    return 4'u32
  if not isEaLegal(eaMemoryAlterable, d.ea):
    return trap(ctx)
  # THE DESTINATION IS RESOLVED ONCE. `(An)+` and `-(An)` adjust the address
  # register, and a read followed by an independent write would adjust it
  # twice and store to the wrong address.
  let dest = eaResolve(ctx, d.ea, 4)
  if ctx.halted: return 0'u32
  let dst = eaRefRead(ctx, dest, 4)
  if ctx.halted: return 0'u32
  let res = combine(d.op, regD(ctx, d.destReg), dst)
  eaRefWrite(ctx, dest, 4, res)
  if ctx.halted: return 0'u32
  setNzClearVc(ctx, res, 4)
  6'u32

proc execEor(ctx: MCF5307Ctx; d: Decoded): uint32 =
  ## `Dn ^ <ea> -> <ea>`. EOR HAS ONE DIRECTION on this part and the
  ## destination is always the effective address: `m68k-elf-as -mcpu=5307`
  ## rejects `eor.l (%a0),%d1`, so `eor.l %d0,%d1` puts the SOURCE in bits
  ## 11..9 and the destination in the low six bits, which is the opposite way
  ## round from `and.l %d0,%d1`.
  if d.size != 4'u8:
    return trap(ctx)
  if not eaIsLegalFor(opEor, d.ea):
    return trap(ctx)
  let dest = eaResolve(ctx, d.ea, 4)
  if ctx.halted: return 0'u32
  let dst = eaRefRead(ctx, dest, 4)
  if ctx.halted: return 0'u32
  let res = dst xor regD(ctx, d.destReg)
  eaRefWrite(ctx, dest, 4, res)
  if ctx.halted: return 0'u32
  setNzClearVc(ctx, res, 4)
  if d.ea.mode == eaDn: 4'u32 else: 6'u32

# ---------------------------------------------------------------------------
# ANDI, ORI, EORI and NOT.

proc execImmediate(ctx: MCF5307Ctx; d: Decoded): uint32 =
  ## ANDI.L, ORI.L and EORI.L. The long immediate is the two words after the
  ## opcode, and the destination is a data register and nothing else.
  ##
  ## THE SIZE AND THE OPERAND ARE CHECKED BEFORE THE IMMEDIATE IS FETCHED. A
  ## byte or word form does not exist on this part, and a core that consumed
  ## its extension words before refusing it would leave the program counter
  ## somewhere the instruction stream does not begin.
  if d.size != 4'u8:
    return trap(ctx)
  if not eaIsLegalFor(d.op, d.ea):
    return trap(ctx)
  let hi = fetchExt(ctx)
  let lo = fetchExt(ctx)
  if ctx.halted: return 0'u32
  let src = (uint32(hi) shl 16) or uint32(lo)
  let res = combine(d.op, src, regD(ctx, d.ea.reg))
  setRegD(ctx, d.ea.reg, res)
  setNzClearVc(ctx, res, 4)
  6'u32

proc execNot(ctx: MCF5307Ctx; d: Decoded): uint32 =
  ## NOT.L Dn. THE MEMORY FORMS OF THE 68000 ARE GONE, AND THE MANUAL IS WHAT
  ## SAYS SO. MCF5307 User's Manual Table 3-12, "One Operand Instruction
  ## Execution Times", page 3-27: the `not.l` row carries `Dx` in the `<EA>`
  ## column, `1(0/0)` under `Rn`, and A DASH under every one of `(An)`,
  ## `(An)+`, `-(An)`, `(d16,An)`, `(d8,An,Xi*SF)`, `xxx.wl` and `#xxx`. The
  ## `clr.l` row SIX ROWS ABOVE it and the `tst.l` row FIVE ROWS BELOW it carry
  ## times in those same columns, so the dashes are this row's and not the
  ## table's. `m68k-elf-as -mcpu=5307` agrees: it rejects `not.l (%a0)`. So the
  ## operand mask is `{Dn}` and every other addressing mode traps.
  ##
  ## THEY ARE NOT "DIRECTLY ABOVE AND BELOW IT", which an earlier revision of
  ## this comment said. Counted in the table: `ext.w`, `ext.l`, `extb.l`,
  ## `neg.l` and `negx.l` sit between `clr.l` and `not.l`, and `scc`, `swap`,
  ## `tst.b` and `tst.w` sit between `not.l` and `tst.l`. The nearest TIMED row
  ## below `not.l` is `tst.b`, THREE rows down; the five rows between `clr.l`
  ## and `not.l` are dashed exactly as `not.l` is. The conclusion is unchanged
  ## - a dashed row sits between timed ones in the same columns - and only the
  ## distances are.
  ##
  ## DO NOT CITE OBJDUMP HERE. An earlier revision said `4690` is not an
  ## instruction `m68k-elf-objdump -m m68k:5307` decodes. IT DECODES IT, as
  ## `notl %d0` - measured - which is a laxity of that disassembler and not a
  ## fact about the part: `4690` has mode 010 (address-register indirect) in
  ## its low six bits, which `-m m68k:68000` prints correctly as `notl %a0@`.
  ## The conclusion is unchanged; only its ground is.
  if d.size != 4'u8:
    return trap(ctx)
  if not eaIsLegalFor(opNot, d.ea):
    return trap(ctx)
  let res = not regD(ctx, d.ea.reg)
  setRegD(ctx, d.ea.reg, res)
  setNzClearVc(ctx, res, 4)
  4'u32

# ---------------------------------------------------------------------------
# BTST, BSET, BCLR and BCHG.

proc execBitOp(ctx: MCF5307Ctx; d: Decoded): uint32 =
  ## One bit operation, in either of its two forms.
  ##
  ## THE OPERAND WIDTH DECIDES THE WIDTH OF THE ACCESS, AND THE MANUAL GIVES
  ## THE TWO WIDTHS. A data register operand is 32 bits and every memory
  ## operand is 8 bits AND THE ACCESS IS ONE BYTE - the "8,32" of Table 3-7's
  ## OPERAND SIZE column, which carries that pair for all four bit operations
  ## and for no other instruction in this group. A core that read or wrote a
  ## longword in memory here would answer a different question and would also
  ## disturb the three bytes beside the operand; the conformance corpus seeds
  ## those three bytes with distinct values and asserts them.
  ##
  ## THE MODULUS BELOW IS A CHOICE AND NOT A CITATION. Taking the bit number
  ## modulo the operand width - 32 for a register, 8 for memory - is what this
  ## core does with a number that does not fit, and NO PASSAGE IN THE USER'S
  ## MANUAL STATES IT. It is uncertainty 4 in this module's header, which
  ## says why Figure 3-8's `MODULO (OFFSET)` annotation does not settle it.
  ##
  ## THE MEMORY HALF OF IT IS ASSERTED, AND AN EARLIER REVISION OF THIS
  ## PARAGRAPH SAID NOTHING WAS. `bchg_b_memory_dynamic_bit_number` in
  ## `conformance/corpus/logic_00.json` is `bchg %d1,(%a0)` with d1 = 9 against
  ## a BYTE operand, and it expects the modulo-8 answer - which is what makes
  ## the sentence "the corpus asks for no bit number outside the range its
  ## operand holds" false. THE 32-BIT HALF IS NOT asserted: no case in the
  ## corpus or in `tests/t_logic.nim` uses a bit number of 32 or more. Both
  ## halves are enumerated, case by case, in uncertainty 4.
  ##
  ## THE STATIC FORM IS NARROWER THAN THE DYNAMIC ONE. `eaBitStatic` is its
  ## mask and the measurement behind it is beside that constant; the dynamic
  ## form reads the ordinary per-operation mask.
  let mask = if d.regOperand: eaLegalityFor(d.op) else: eaBitStatic
  if not isEaLegal(mask, d.ea):
    return trap(ctx)
  var bitNumber: uint32
  if d.regOperand:
    bitNumber = regD(ctx, d.destReg)
  else:
    # The static form's bit number is the extension word, and it is fetched
    # BEFORE the effective address's own extension words - the order the
    # assembler emits them in, measured: `btst #3,4(%a0)` is `0828 0003 0004`.
    bitNumber = uint32(fetchExt(ctx))
    if ctx.halted: return 0'u32
  let bit = bitNumber and (8'u32 * uint32(d.size) - 1'u32)
  let selector = 1'u32 shl bit
  # BTST READS AND THE OTHER THREE READ AND WRITE, AND THAT DECIDES WHICH
  # OPERAND EVALUATOR EACH ONE USES.
  #
  # `eaResolve` returns a reference a later write can reach, so it refuses
  # every operand that cannot be written: the PC-relative pair, the immediate
  # and the reserved mode-7 encodings. That is CORRECT FOR BSET, BCLR AND BCHG
  # and WRONG FOR BTST, whose mask is `eaBitDynamic` and which admits the two
  # PC-RELATIVE sub-variants. Measured: `btst %d1,(4,%pc)` (`033a 0004`) and
  # `btst %d1,(4,%pc,%d2)` (`033b 2804`) both assemble on `-mcpu=5307`, and
  # both halted with `fault` while this procedure resolved every operand
  # through `eaResolve`.
  #
  # THE IMMEDIATE IS NOT ONE OF THEM. `eaBitDynamic` excludes it, so the mask
  # check above refuses `btst %d1,#5` before either evaluator is reached. See
  # that constant in `decode_types.nim` for the manual rows behind it, and
  # uncertainty 3 in this module's header for what would overturn it.
  #
  # THE FIX IS HERE AND NOT IN `eaResolve`. Widening that procedure would let
  # a WRITE reach a PC-relative or an immediate operand, and the three bit
  # operations that write are not the only callers it has. BTST never writes,
  # so it reads through `eaRead`, which serves every mode its mask admits.
  # `tests/t_logic.nim` asserts all three halves: that BTST reaches the
  # PC-relative operands, that it refuses the immediate, and that BSET, BCLR
  # and BCHG refuse all three.
  var value: uint32
  if d.op == opBtst:
    value = eaRead(ctx, d.ea, d.size)
    if ctx.halted: return 0'u32
  else:
    # THE DESTINATION IS RESOLVED ONCE, for the reason `execAndOr` gives:
    # `(An)+` and `-(An)` adjust the address register, and a read followed by
    # an independent write would adjust it twice.
    let dest = eaResolve(ctx, d.ea, d.size)
    if ctx.halted: return 0'u32
    value = eaRefRead(ctx, dest, d.size)
    if ctx.halted: return 0'u32
    let written = case d.op
      of opBset: value or selector
      of opBclr: value and not selector
      else: value xor selector
    eaRefWrite(ctx, dest, d.size, written)
    if ctx.halted: return 0'u32
  let wasSet = (value and selector) != 0'u32
  # Z ALONE, AND IT IS THE COMPLEMENT OF THE BIT AS IT WAS FOUND. N, V, C and
  # X are not written: a bit operation is not an arithmetic result and must
  # not disturb a multi-precision sequence or a pending conditional branch.
  ctx.sr = ctx.sr and not ccrZ
  if not wasSet:
    ctx.sr = ctx.sr or ccrZ
  if d.op == opBtst: 4'u32 else: 6'u32

# ---------------------------------------------------------------------------
# LSL, LSR, ASL and ASR.

proc execShift(ctx: MCF5307Ctx; d: Decoded): uint32 =
  ## One register shift. See the module header for the one-bit-at-a-time note
  ## and for where each condition-code rule comes from.
  ##
  ## THE OPERAND IS CHECKED BEFORE THE SIZE, so that a MEMORY shift reports
  ## the reason it is refused - the operand - rather than the word size the
  ## memory encoding happens to carry.
  if not eaIsLegalFor(d.op, d.ea):
    return trap(ctx)
  if d.size != 4'u8:
    return trap(ctx)
  # AN IMMEDIATE COUNT IS 1 TO 8, which the encoding itself fixes. A REGISTER
  # COUNT IS TAKEN MODULO 64 - AND THAT NUMBER IS A CHOICE, NOT A CITATION.
  # Table 3-7 gives the four shifts as `X/C <- (Dy << Dx) <- 0` and the two
  # right-hand forms and STATES NO MODULUS, and no other passage of the
  # User's Manual does either. It is uncertainty 5 in this module's header.
  #
  # What the choice means, so that a reader can see what would change: the
  # modulus is treated as a property of the shift unit rather than of the
  # operand width, so a count of 40 shifts a 32-bit register 40 times and
  # leaves zero rather than shifting it 8. NOTHING ASSERTS IT - no case in
  # the corpus or in `tests/t_logic.nim` uses a count above eight, so modulo
  # 64, modulo 256 and no reduction at all are indistinguishable here.
  let count = if d.regOperand: regD(ctx, d.destReg) and 63'u32
              else: uint32(d.imm)
  let toLeft = d.op == opAsl or d.op == opLsl
  let arithmetic = d.op == opAsl or d.op == opAsr
  var value = regD(ctx, d.ea.reg)
  var carry = false
  for _ in 0 ..< int(count):
    let before = value
    if toLeft:
      carry = (before and 0x80000000'u32) != 0'u32
      value = before shl 1
      # NO OVERFLOW IS COMPUTED FOR ASL. CFPRM folio 4-12 gives V a flat
      # "Always cleared" and adds "Note that CCR[V] is always cleared by ASL
      # and ASR, unlike on the 68K family processors"; folio 4-11 says "The
      # overflow bit is always zero". The clearing at the foot of this proc is
      # the whole rule.
    else:
      carry = (before and 1'u32) != 0'u32
      value = before shr 1
      # AN ARITHMETIC RIGHT SHIFT REPLICATES THE SIGN. `shr` on the unsigned
      # register value feeds zeros in, which is what LSR wants and what ASR
      # must undo for a negative operand. The bit is put back explicitly
      # rather than by casting to a signed type and shifting, because Nim's
      # `shr` on a signed integer is not the operation this needs to be.
      if arithmetic and (before and 0x80000000'u32) != 0'u32:
        value = value or 0x80000000'u32
  setRegD(ctx, d.ea.reg, value)
  var sr = ctx.sr and not (ccrN or ccrZ or ccrV or ccrC)
  if (value and 0x80000000'u32) != 0'u32: sr = sr or ccrN
  if value == 0'u32: sr = sr or ccrZ
  if carry: sr = sr or ccrC
  # X TAKES C, AND A COUNT OF ZERO LEAVES X ALONE. A shift that moved no bit
  # produced no carry to copy, and X is the bit a multi-precision sequence is
  # holding across instructions.
  if count != 0'u32:
    sr = sr and not ccrX
    if carry: sr = sr or ccrX
  ctx.sr = sr
  4'u32

# ---------------------------------------------------------------------------
# The dispatch entry `step` calls.

proc logicFamily*(ctx: MCF5307Ctx; word: uint16; d: Decoded): uint32 =
  ## Execute one logic, bit-operation or shift instruction. Called from `step`
  ## in `mcf5307/cpu` with the opcode word and the decoded operation. Returns
  ## the instruction's nominal cycles excluding the fetch; halts the context
  ## with `fault` set on an illegal size or an illegal effective address.
  case d.op
  of opAnd, opOr: execAndOr(ctx, d)
  of opEor: execEor(ctx, d)
  of opAndi, opOri, opEori: execImmediate(ctx, d)
  of opNot: execNot(ctx, d)
  of opBtst, opBset, opBclr, opBchg: execBitOp(ctx, d)
  of opAsl, opAsr, opLsl, opLsr: execShift(ctx, d)
  else: trap(ctx)
