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
## and word form of everything else TRAPS here.
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
## which is the whole demonstration. `e0c0` DEMONSTRATES NOTHING: it decodes
## on NEITHER architecture, because its low six bits are mode 000 - a data
## register - which is not a memory operand on the 68000 either, so its
## refusal is not ColdFire's doing.
##
## THE ROTATES ARE GONE TOO: manual section 3.9 lists "logical rotate" among
## the removed instructions, and `decode.nim` never produces an operation for
## them.
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
## THE SHIFT IS PERFORMED ONE BIT AT A TIME, ON PURPOSE. A count is at most 63
## and the loop costs nothing, and it makes the carry rule that is easy to get
## wrong in closed form come out by construction: the carry is THE LAST BIT
## THAT LEFT THE WORD rather than a bit of the result.
##
## A SHIFT COUNT OF ZERO IS REACHABLE THROUGH THE REGISTER FORM ALONE, because
## the immediate form spends its zero slot on the value eight. It shifts
## nothing. ONE OF THE FIVE FLAGS HAS A REASON AND FOUR ARE A CHOICE, and the
## code and this paragraph say the same thing about which is which:
##
##   X IS LEFT ALONE, AND THAT ONE IS REASONED. Section 3.2.1.5 gives X the
##   value of C "for arithmetic operations; otherwise not affected", and a
##   shift that moved no bit produced no carry to copy. `execShift` guards X
##   with `count != 0` for exactly this.
##
##   N, Z, V AND C ARE WRITTEN ANYWAY - N and Z from the unmoved operand, V
##   and C cleared - AND THAT IS THIS MODULE'S CHOICE AND NOT A RULE ANY
##   DOCUMENT ON THIS MACHINE STATES. It is undecided, the code still has to
##   do something, and what it does is written here so that a reader is not
##   left to infer it.
##
## CYCLES. See the block above the constants in `cpu.nim`; uncertainty 2 below
## is this group's entry. Every instruction here has a timing row - all of them
## in Table 3-13 (folios 3-28 and 3-29) except NOT, which is in Table 3-12
## (3-27) - and none of the returns here was derived from one. Eight of those
## rows carry `1(0/0)` in every cell they carry at all - `not.l Dx`, the three
## `#imm,Dx` immediate rows, and the four shifts, which are timed under `Rn`
## and `#xxx` and dashed everywhere else - against the 4 and 6 returned.
##
## WHAT THIS MODULE DOES NOT KNOW. Five things, and the rule for every one of
## them is the same: THE IMPLEMENTATION PICKS A BEHAVIOUR.
##
## The ColdFire Family Programmer's Reference Manual is on disk at
## `~/Development/datasheets/CFPRM.pdf` (Rev. 3), and its per-instruction pages
## give the flag rules directly. Entries 3, 4 and 5 below are per-instruction
## questions of exactly the kind the CFPRM answers.
##
##   1. THE STATUS WORD OF A SHIFT BY ZERO. See the paragraph above.
##
##   2. THE EXACT CYCLE COUNT of every instruction in this group. `cpu.nim`
##      states the mechanism once, above its cycle constants.
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
##      THIS IS THE ONE ENTRY on this list that a future reader may have to
##      REVERSE rather than merely fill in.
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
##   5. THE REGISTER SHIFT COUNT'S MODULUS. `execShift` takes it modulo 64.
##      Table 3-7 gives the shift operations as `X/C <- (Dy << Dx) <- 0` and
##      states no modulus, and no other passage does.
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
  ## Counted in the table: `ext.w`, `ext.l`, `extb.l`, `neg.l` and `negx.l`
  ## sit between `clr.l` and `not.l`, and `scc`, `swap`, `tst.b` and `tst.w`
  ## sit between `not.l` and `tst.l`. The nearest TIMED row below `not.l` is
  ## `tst.b`, THREE rows down; the five rows between `clr.l` and `not.l` are
  ## dashed exactly as `not.l` is: a dashed row sits between timed ones in the
  ## same columns.
  ##
  ## DO NOT CITE OBJDUMP HERE. `m68k-elf-objdump -m m68k:5307` DECODES `4690`,
  ## as `notl %d0` - measured - which is a laxity of that disassembler and not
  ## a fact about the part: `4690` has mode 010 (address-register indirect) in
  ## its low six bits, which `-m m68k:68000` prints correctly as `notl %a0@`.
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
  ## disturb the three bytes beside the operand.
  ##
  ## THE MODULUS BELOW IS A CHOICE AND NOT A CITATION. Taking the bit number
  ## modulo the operand width - 32 for a register, 8 for memory - is what this
  ## core does with a number that does not fit, and NO PASSAGE IN THE USER'S
  ## MANUAL STATES IT. It is uncertainty 4 in this module's header, which
  ## says why Figure 3-8's `MODULO (OFFSET)` annotation does not settle it.
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
  # `btst %d1,(4,%pc,%d2)` (`033b 2804`) both assemble on `-mcpu=5307`.
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
  # leaves zero rather than shifting it 8.
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
  ## in `mcf5307/cpu` with the opcode word and the decoded operation. Returns a
  ## PLACEHOLDER cycle count excluding the fetch - see the cycle block in
  ## `cpu.nim` - and halts the context with `fault` set on an illegal size or
  ## an illegal effective address.
  case d.op
  of opAnd, opOr: execAndOr(ctx, d)
  of opEor: execEor(ctx, d)
  of opAndi, opOri, opEori: execImmediate(ctx, d)
  of opNot: execNot(ctx, d)
  of opBtst, opBset, opBclr, opBchg: execBitOp(ctx, d)
  of opAsl, opAsr, opLsl, opLsr: execShift(ctx, d)
  else: trap(ctx)
