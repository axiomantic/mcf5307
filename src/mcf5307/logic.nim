## `logic` - the logic, bit-operation and shift instruction group of the
## ColdFire ISA_A core.
##
## This module executes AND, ANDI, OR, ORI, EOR, EORI, NOT, BTST, BSET, BCLR,
## BCHG, LSL, LSR, ASL and ASR, and nothing else. The register file, the board
## accesses and the effective-address evaluation are `mcf5307/machine`'s.
##
## Its whole import list is `{decode_types, ea, machine}`, and it imports no
## sibling executor. An executor that reaches into another executor for a
## helper rebuilds the decoder-under-executor cycle one layer down.
##
## Every operation in this group is 32-bit on this part, which the MCF5307
## User's Manual Table 3-7 states for each of them, and `m68k-elf-as
## -mcpu=5307` confirms by rejecting `and.b %d0,%d1`, `not.w %d0`,
## `andi.b #5,%d1` and `lsl.w #1,%d0`. The one exception is the bit
## operations, whose operand is 32 bits when it is a data register and 8 bits
## otherwise - the "8,32" of that same table. Every byte and word form of
## everything else traps here.
##
## Every shift is register-only and a memory shift traps. MCF5307 User's
## Manual Table 3-13, page 3-28: the `asl.l`, `asr.l`, `lsl.l` and `lsr.l`
## rows all read `<ea>,Dx` and carry a time under `Rn` and under `#xxx` alone
## - `1(0/0)` in each - with a dash under `(An)`, `(An)+`, `-(An)`,
## `(d16,An)`, `(d8,An,Xi*SF)` and `xxx.wl`. A shift on this part reaches a
## data register and an immediate count and no memory operand at all, and the
## `{Dn}` mask in `decode_types` refuses that operand.
##
## The witness is `e2d0`: `1110 001 0 11 010 000`, a memory shift whose
## operand is `(%a0)`, which decodes as `lsrw %a0@` on
## `m68k-elf-objdump -m m68k:68000` and as `.short 0xe2d0` on `-m m68k:5307`.
## `e0c0` demonstrates nothing: it decodes on neither architecture, because
## its low six bits are mode 000 - a data register - which is not a memory
## operand on the 68000 either, so its refusal is not ColdFire's doing.
##
## The rotates are gone too: manual section 3.9 lists "logical rotate" among
## the removed instructions, and `decode.nim` never produces an operation for
## them.
##
## The condition codes, and where each rule comes from.
##
##   AND, ANDI, OR, ORI, EOR, EORI, NOT
##       N and Z from the result, V and C cleared, X untouched. Manual section
##       3.2.1.5 defines V as an arithmetic overflow, C as a carry out of an
##       addition or a borrow in a subtraction, and X as taking C's value "for
##       arithmetic operations; otherwise not affected". A logical operation
##       is none of those things. That is `setNzClearVc`, which `machine.nim`
##       already holds for the same rule under MOVE.
##
##   BTST, BSET, BCLR, BCHG
##       Z alone, and Z is the complement of the bit tested. Manual Table 3-7
##       gives the operation as `~(<Bit Number> of Destination) -> Z` and
##       names no other bit, so N, V, C and X are left exactly as they were.
##
##   LSL, LSR, ASL, ASR
##       X and C both take the last bit shifted out, which Table 3-7 states
##       for all four (`X/C <- (Dy << Dx) <- 0` and the two right-shift
##       forms). N and Z come from the result. V is cleared by LSL, LSR and
##       ASR and set by ASL when the sign changes, and the reason is the word
##       "arithmetic" in section 3.2.1.5: "V - overflow condition code bit:
##       Set if an ARITHMETIC overflow occurs implying that the result cannot
##       be represented in the operand size; otherwise cleared". LSL and LSR
##       are logical shifts, so no arithmetic overflow occurs and V is
##       cleared; ASR is arithmetic but a right shift moves every bit toward
##       the LSB and cannot leave the operand size; ASL is arithmetic and can,
##       and it is the one that sets V. LSL's V stays clear because LSL is not
##       an arithmetic operation, not because nothing overflows: `lsl.l #1` of
##       `0x87654321` carries a one out of bit 31 and the 32-bit result does
##       not hold the value.
##
## The shift is performed one bit at a time, on purpose. A count is at most 63
## and the loop costs nothing, and it makes two rules that are easy to get
## wrong in closed form come out by construction: the carry is the last bit
## that left the word rather than a bit of the result, and ASL's overflow is
## "the sign changed at any point during the shift" rather than "the sign of
## the result differs from the sign of the operand". Those two readings of the
## overflow rule agree at a count of one and can differ above it, so the
## conformance corpus asserts V only where every candidate reading agrees on
## its value: every case at a count of one, and a case at a larger count whose
## operand cannot change sign.
##
## A shift count of zero is reachable through the register form alone, because
## the immediate form spends its zero slot on the value eight. It shifts
## nothing. X is left alone: section 3.2.1.5 gives X the value of C "for
## arithmetic operations; otherwise not affected", and a shift that moved no
## bit produced no carry to copy. N, Z, V and C are written anyway - N and Z
## from the unmoved operand, V and C cleared - and that is this module's
## choice and not a rule any document on this machine states.
##
## Cycles are nominal: the per-instruction budget needs the clock work of open
## question 6 in AGENTS.md and no exact cost is asserted anywhere.
##
## What this module does not know. The implementation picks a behaviour and
## nothing asserts it. The document that would settle 1, 2, 4, 5 and 6 is the
## ColdFire Family Programmer's Reference Manual, whose per-instruction pages
## give the operand table and the flag rules directly; it is not on this
## machine.
##
##   1. ASL's overflow reading. "The sign changed at any point" against "the
##      sign of the result differs from the sign of the operand". No case pins
##      a count at which the two readings disagree.
##
##   2. The status word of a shift by zero.
##
##   3. The exact cycle count of every instruction in this group.
##      `tests/t_logic.nim`'s `cycles` field is not a counter-case though its
##      name reads like one. That field is the return of
##      `mcf5307_exec(ctx, 1)`, and `mcf5307_exec` saturates at its budget: a
##      cost of 2 for the fetch plus anything this module returns already
##      exceeds a budget of one, so the value is 1 for an instruction that ran
##      and 0 for one that trapped, and it cannot see a count at all.
##
##   4. Whether a dynamic BTST may read an immediate operand. User's Manual
##      Table 3-13, page 3-28, dashes the `#xxx` column of the `btst Dy,<ea>`
##      row, and `m68k-elf-as -mcpu=5307` assembles `btst %d1,#5` anyway. The
##      mask follows the manual and traps it; the full evidence, including why
##      the assembler's acceptance is the 68000's rule rather than this part's,
##      is on `eaBitDynamic` in `decode_types.nim`.
##
##      Two tables of the one manual disagree. Table 3-5 on page 3-21,
##      "Effective Addressing Modes and Categories", marks Immediate `#<xxx>`
##      with an `x` in the DATA column. A dynamic BTST reads its operand, so
##      the DATA class is its class, and that column restores the immediate
##      the timing table dashes. Cutting the other way, Table 3-7 on page 3-23
##      gives BTST's operand syntax as `Dy,<ea>x`, and the `x` suffix is the
##      manual's destination mark - `CLR <ea>x` is "0 -> Destination" and
##      `CMP <ea>y,Dx` is "Destination - Source" - which an immediate cannot
##      be.
##
##      A reader who reverses this must change both assertions in
##      `tests/t_logic.nim`: the `btst %d1,#5` trap case, and the
##      `checkMask(eaIsLegalFor(opBtst, decodeEa(0x3C)), false, ...)` row. It
##      is the one entry on this list that a future reader may have to reverse
##      rather than merely fill in.
##
##   5. The bit number's modulus. `execBitOp` reduces the number modulo the
##      operand width - 32 for a data register, 8 for memory. Table 3-7 gives
##      the two widths ("8,32") and states no modulus anywhere, and no other
##      passage does either. Figure 3-8 on page 3-18 is the closest thing and
##      it does not carry the weight: its `BIT` row reads "BIT (0 <= MODULO
##      (OFFSET) < 31, OFFSET OF 0 = MSB)", which numbers from the MSB where
##      every bit operation here numbers from the LSB, stops at 31 rather than
##      including it, and uses the word OFFSET, which belongs to the bit-field
##      instructions section 3.9 lists among the removed ones.
##
##      The memory half is pinned by the corpus and the register half is not.
##      `bchg_b_memory_dynamic_bit_number` in
##      `conformance/corpus/logic_00.json` is `bchg %d1,(%a0)` with d1 = 9
##      against a byte memory operand - 9 is outside the range a byte holds -
##      and its expected result is the modulo-8 answer and nothing else: the
##      byte at 0x2000 goes 0x02 to 0x00, which is bit 1 cleared, and sr goes
##      0x271f to 0x271b, which is Z cleared because bit 1 was found set.
##      Modulo 32 selects bit 9 of a byte that has no bit 9, so Z comes out set
##      and the byte keeps 0x02; no reduction at all selects bit 9 too, which
##      is the same computation at this bit number. A clamp to 7 selects bit 7,
##      so Z comes out set and the byte becomes 0x82. Only the modulo-8 reading
##      gives 0x00 with Z clear.
##
##      What remains unpinned is the 32-bit modulus. No case in the corpus or
##      in `tests/t_logic.nim` uses a bit number outside the width its operand
##      holds, except the 9 above, so nothing separates modulo 32 from a wider
##      reduction or from no reduction at all for a register operand.
##
##   6. The register shift count's modulus. `execShift` takes it modulo 64.
##      Table 3-7 gives the shift operations as `X/C <- (Dy << Dx) <- 0` and
##      states no modulus, and no other passage does. No case in the corpus or
##      in `tests/t_logic.nim` uses a count above 31, so nothing distinguishes
##      modulo 64 from modulo 256 or from no reduction at all.

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
  ## `src op dst`. The order of the two operands does not matter for any of
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
  ## is true. The two directions carry different operand masks: the first
  ## reads any data-addressing mode, the immediate and the PC-relative pair
  ## included, and the second writes a memory-alterable one. A single mask
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
  # The destination is resolved once. `(An)+` and `-(An)` adjust the address
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
  ## `Dn ^ <ea> -> <ea>`. EOR has one direction on this part and the
  ## destination is always the effective address: `m68k-elf-as -mcpu=5307`
  ## rejects `eor.l (%a0),%d1`, so `eor.l %d0,%d1` puts the source in bits
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
  ## The size and the operand are checked before the immediate is fetched. A
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
  ## NOT.L Dn. The memory forms of the 68000 are gone, and the manual is what
  ## says so. MCF5307 User's Manual Table 3-12, "One Operand Instruction
  ## Execution Times", page 3-27: the `not.l` row carries `Dx` in the `<EA>`
  ## column, `1(0/0)` under `Rn`, and a dash under every one of `(An)`,
  ## `(An)+`, `-(An)`, `(d16,An)`, `(d8,An,Xi*SF)`, `xxx.wl` and `#xxx`. The
  ## `clr.l` row above it and the `tst.l` row below it carry times in those
  ## same columns, so the dashes are this row's and not the table's.
  ## `m68k-elf-as -mcpu=5307` agrees: it rejects `not.l (%a0)`. So the operand
  ## mask is `{Dn}` and every other addressing mode traps.
  ##
  ## Do not cite objdump here. `m68k-elf-objdump -m m68k:5307` decodes `4690`
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
  ## The operand width decides the width of the access. A data register
  ## operand is 32 bits and every memory operand is 8 bits, and the access is
  ## one byte - the "8,32" of Table 3-7's OPERAND SIZE column, which carries
  ## that pair for all four bit operations and for no other instruction in
  ## this group. A core that read or wrote a longword in memory here would
  ## answer a different question and would also disturb the three bytes beside
  ## the operand; the conformance corpus seeds those three bytes with distinct
  ## values and asserts them.
  ##
  ## The modulus below is a choice and not a citation. Taking the bit number
  ## modulo the operand width - 32 for a register, 8 for memory - is what this
  ## core does with a number that does not fit, and no passage in the User's
  ## Manual states it. It is uncertainty 5 in this module's header, which says
  ## why Figure 3-8's `MODULO (OFFSET)` annotation does not settle it. The
  ## memory half is asserted by `bchg_b_memory_dynamic_bit_number` in
  ## `conformance/corpus/logic_00.json`; the 32-bit half is not.
  ##
  ## The static form is narrower than the dynamic one. `eaBitStatic` is its
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
  # BTST reads and the other three read and write, and that decides which
  # operand evaluator each one uses.
  #
  # `eaResolve` returns a reference a later write can reach, so it refuses
  # every operand that cannot be written: the PC-relative pair, the immediate
  # and the reserved mode-7 encodings. That is correct for BSET, BCLR and BCHG
  # and wrong for BTST, whose mask is `eaBitDynamic` and which admits the two
  # PC-relative sub-variants. Measured: `btst %d1,(4,%pc)` (`033a 0004`) and
  # `btst %d1,(4,%pc,%d2)` (`033b 2804`) both assemble on `-mcpu=5307`, and
  # both halted with `fault` while this procedure resolved every operand
  # through `eaResolve`.
  #
  # The immediate is not one of them. `eaBitDynamic` excludes it, so the mask
  # check above refuses `btst %d1,#5` before either evaluator is reached. See
  # that constant in `decode_types.nim` for the manual rows behind it, and
  # uncertainty 4 in this module's header for what would overturn it.
  #
  # The fix belongs here and not in `eaResolve`. Widening that procedure would
  # let a write reach a PC-relative or an immediate operand, and the three bit
  # operations that write are not the only callers it has. BTST never writes,
  # so it reads through `eaRead`, which serves every mode its mask admits.
  var value: uint32
  if d.op == opBtst:
    value = eaRead(ctx, d.ea, d.size)
    if ctx.halted: return 0'u32
  else:
    # The destination is resolved once, for the reason `execAndOr` gives:
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
  # Z alone, and it is the complement of the bit as it was found. N, V, C and
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
  ## The operand is checked before the size, so that a memory shift reports
  ## the reason it is refused - the operand - rather than the word size the
  ## memory encoding happens to carry.
  if not eaIsLegalFor(d.op, d.ea):
    return trap(ctx)
  if d.size != 4'u8:
    return trap(ctx)
  # An immediate count is 1 to 8, which the encoding itself fixes. A register
  # count is taken modulo 64, and that number is a choice, not a citation.
  # Table 3-7 gives the four shifts as `X/C <- (Dy << Dx) <- 0` and the two
  # right-hand forms and states no modulus, and no other passage of the
  # User's Manual does either. It is uncertainty 6 in this module's header.
  #
  # The modulus is treated as a property of the shift unit rather than of the
  # operand width, so a count of 40 shifts a 32-bit register 40 times and
  # leaves zero rather than shifting it 8. Nothing asserts it: no case in the
  # corpus or in `tests/t_logic.nim` uses a count above eight, so modulo 64,
  # modulo 256 and no reduction at all are indistinguishable here.
  let count = if d.regOperand: regD(ctx, d.destReg) and 63'u32
              else: uint32(d.imm)
  let toLeft = d.op == opAsl or d.op == opLsl
  let arithmetic = d.op == opAsl or d.op == opAsr
  var value = regD(ctx, d.ea.reg)
  var carry = false
  var overflow = false
  for _ in 0 ..< int(count):
    let before = value
    if toLeft:
      carry = (before and 0x80000000'u32) != 0'u32
      value = before shl 1
      # ASL's overflow is a property of the whole shift and not of its last
      # step: it is set if the sign changed at any point, so it is latched
      # here and never cleared inside the loop.
      if arithmetic and ((before xor value) and 0x80000000'u32) != 0'u32:
        overflow = true
    else:
      carry = (before and 1'u32) != 0'u32
      value = before shr 1
      # An arithmetic right shift replicates the sign. `shr` on the unsigned
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
  if overflow: sr = sr or ccrV
  if carry: sr = sr or ccrC
  # X takes C, and a count of zero leaves X alone. A shift that moved no bit
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
