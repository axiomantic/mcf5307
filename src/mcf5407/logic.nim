## `logic` - the logic, bit-operation and shift instruction group of the
## ColdFire ISA_A core.
##
## This module executes AND, ANDI, OR, ORI, EOR, EORI, NOT, BTST, BSET, BCLR,
## BCHG, LSL, LSR, ASL and ASR, and nothing else. The register file, the board
## accesses and the effective-address evaluation are `mcf5407/machine`'s.
##
## Its whole import list is `{decode_types, ea, machine}`, and it imports no
## sibling executor. An executor that reaches into another executor for a
## helper rebuilds the decoder-under-executor cycle one layer down.
##
## The size is long, with one exception. Every operation in this group
## is 32-bit on this part, which the MCF5407 User's Manual Table 2-8,
## "User-Level Instruction Set Summary", folios 2-20 and 2-22, states for
## each of them in its Operand Size column, and `m68k-elf-as -mcpu=5307`
## confirms by rejecting
## `and.b %d0,%d1`, `not.w %d0`, `andi.b #5,%d1` and `lsl.w #1,%d0`. The one
## exception is the bit operations, whose operand is 32 bits when it is a data
## register and 8 bits otherwise - the ".B,.L" of that same column on folio
## 2-20. Every byte
## and word form of everything else traps here.
##
## Every shift is register-only and a memory shift traps. MCF5407 User's
## Manual Table 2-15, "Two-Operand Instruction Execution Times": `asl.l` and
## `asr.l` on folio 2-27 and
## `lsl.l` and `lsr.l` on folio 2-28 all read `<ea>,Dx` and carry a time under
## `Rn` and under `#<xxx>` alone - `1(0/0)` in each - with a dash under `(An)`,
## `(An)+`, `-(An)`, `(d16,An)`, `(d8,An,Xi*SF)` and `(xxx).wl`. A shift on this
## part reaches a data register and an immediate count and no memory operand at
## all, and the `{Dn}` mask in `decode_types` refuses that operand.
##
## The witness is `e2d0`: `1110 001 0 11 010 000`, a memory shift whose
## operand is `(%a0)`, which decodes as `lsrw %a0@` on
## `m68k-elf-objdump -m m68k:68000` and as `.short 0xe2d0` on `-m m68k:5307`.
## `e0c0` demonstrates nothing: it decodes on neither architecture, because
## its low six bits are mode 000 - a data register - which is not a memory
## operand on the 68000 either, so its refusal is not ColdFire's doing.
##
## The rotates are gone too: manual section 2.6, "Instruction Set Summary",
## folio 2-15, lists "logical rotate" among
## the removed instructions, and `decode.nim` never produces an operation for
## them.
##
## The condition codes, and where each rule comes from.
##
##   AND, ANDI, OR, ORI, EOR, EORI, NOT
##       N and Z from the result, V and C cleared, X untouched. Manual section
##       2.2.1.5, Table 2-1 "CCR Field Descriptions", folio 2-10, defines V as
##       an arithmetic overflow, C as a carry out of an
##       addition or a borrow in a subtraction, and X as "Assigned the value of
##       the carry bit for arithmetic operations; otherwise not affected or set
##       to a specified result". A logical operation
##       is none of those things. That is `setNzClearVc`, which `machine.nim`
##       already holds for the same rule under MOVE.
##
##   BTST, BSET, BCLR, BCHG
##       Z alone, and Z is the complement of the bit tested. Manual Table 2-8,
##       folio 2-20,
##       gives the operation as `~(<bit number> of destination) -> Z` and
##       names no other bit, so N, V, C and X are left exactly as they were.
##
##   LSL, LSR, ASL, ASR
##       X and C both take the last bit shifted out, which Table 2-8 states
##       for all four (`X/C <- (Dx << Dy) <- 0` and the two right-shift
##       forms, folios 2-20 and 2-21). N and Z come from the result. V is
##       cleared by all four, ASL
##       included. CFPRM folio 4-12 gives V a flat "Always cleared" in the
##       condition-code table and adds "Note that CCR[V] is always cleared by
##       ASL and ASR, unlike on the 68K family processors"; folio 4-11 says
##       "The overflow bit is always zero". This part computes no shift
##       overflow at all.
##
## The shift is performed one bit at a time. A count is at most 63
## and the loop costs nothing, and it makes the carry rule that is easy to get
## wrong in closed form come out by construction: the carry is the last bit
## that left the word rather than a bit of the result.
##
## A shift count of zero is reachable through the register form alone, because
## the immediate form spends its zero slot on the value eight. It shifts
## nothing.
##
## The status word of a shift by zero: N, Z, V and C are written anyway - N and
## Z from the unmoved operand, V and C cleared - and that is this module's
## choice and not a rule any document on this machine states.
##
## Cycles. See the block above the constants in `cpu.nim`. Every instruction
## here has a timing row - all of them in Table 2-15 (folios 2-27, 2-28 and
## 2-29)
## except NOT, which is in Table 2-14 (2-27) - and none of the returns here was
## derived from one. Many of those rows carry `1(0/0)` in every cell they carry
## at all - `not.l Dx`, the `#imm,Dx` immediate rows, and the shifts, which are
## timed under `Rn` and `#<xxx>` and dashed everywhere else - against the 4 and
## 6
## returned.
##
## What this module does not know. The implementation picks a behaviour.
##
## The ColdFire Family Programmer's Reference Manual, Rev. 3, carries the flag
## rules directly on its per-instruction pages. The entries below are
## per-instruction questions of exactly the kind the CFPRM answers.
##
##      Whether a dynamic BTST may read an immediate operand. User's Manual
##      Table 2-15, folio 2-28, dashes the `#<xxx>` column of the
##      `btst Dy,<ea>`
##      row, and `m68k-elf-as -mcpu=5307` assembles `btst %d1,#5` anyway. The
##      mask follows the manual and traps it; the full evidence, including why
##      the assembler's acceptance is the 68000's rule rather than this part's,
##      is on `eaBitDynamic` in `decode_types.nim`.
##
##      Two tables of the one manual disagree. Table 2-5 on folio 2-15,
##      "ColdFire Effective Addressing Modes", marks Immediate `#<xxx>`
##      with an `X` in the Data column. A dynamic BTST reads its operand, so
##      the Data class is its class, and that column restores the immediate the
##      timing table dashes. Cutting the other way, Table 2-8 on folio 2-20
##      gives BTST's operand syntax as `Dy,<ea>x`, and the `x` suffix is the
##      manual's destination mark - `CLR <ea>y,Dx` is "0 -> destination" and
##      `CMP <ea>y,Ax` is "Destination - source" - which an immediate cannot
##      be.
##
##      This is the one entry on this list that a future reader may have to
##      reverse rather than merely fill in.
##
##      The bit number's modulus. `execBitOp` reduces the number modulo the
##      operand width - 32 for a data register, 8 for memory. Table 2-8 gives
##      the widths (".B,.L") and states no modulus anywhere, and no other
##      passage does either. Figure 2-7, "Organization of Integer Data Formats
##      in Data Registers", folio 2-13, is the closest thing and it still does
##      not carry the weight: its bit row reads "Bit (0 <= bit number <= 31)",
##      which is a statement of the register's numbering and not a rule for
##      reducing an out-of-range operand.
##
##      THE MCF5407 FIGURE IS NOT THE MCF5307'S. The MCF5307's Figure 3-8 read
##      "BIT (0 <= MODULO (OFFSET) < 31, OFFSET OF 0 = MSB)" - MSB-numbered,
##      exclusive of 31, and phrased in the OFFSET language of the removed
##      bit-field instructions. Three separate objections to reading it as a
##      modulus rule. The MCF5407 wording removes all three: it numbers from
##      the LSB, as every bit operation here does, and it includes 31. What it
##      does not do is state a modulus, so the conclusion is unchanged and only
##      the reasoning behind it is.
##
##      The register shift count's modulus. `execShift` takes it modulo 64.
##      Table 2-8 gives the shift operations as `X/C <- (Dx << Dy) <- 0` and
##      states no modulus, and no other passage does. Nothing here distinguishes
##      modulo 64 from modulo 256 or from no reduction at all.

import mcf5407/decode_types
import mcf5407/ea
import mcf5407/machine

# ---------------------------------------------------------------------------
# Trapping.

proc trap(ctx: MCF5407Ctx): uint32 =
  ## Halt the context with `fault`. Every illegal size and illegal operand
  ## mode in this module ends here, so that "the core refused" is one
  ## observable and not several.
  ctx.fault = true
  ctx.halted = true
  0'u32

# ---------------------------------------------------------------------------
# The bitwise combinations, named once.

proc combine(op: Operation; src, dst: uint32): uint32 =
  ## `src op dst`. The order of the two operands does not matter for any of
  ## them, which is why one procedure serves both directions of AND and OR and
  ## the single direction of EOR.
  case op
  of opAnd, opAndi: src and dst
  of opOr, opOri: src or dst
  else: src xor dst

# ---------------------------------------------------------------------------
# AND and OR, both directions.

proc execAndOr(ctx: MCF5407Ctx; d: Decoded): uint32 =
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
  # MCF5407 User's Manual Table 2-15, folio 2-27, `and.l`/`or.l`/`eor.l`: 1(0/0)
  # under `Rn` and `#xxx`, 1(1/0) or 1(1/1) under the four memory modes and
  # `xxx.wl` according to direction, and 2 under `(d8,An,Xi*SF)`. Was 6, which
  # was near the MCF5307's cells and is nowhere near these.
  1'u32

proc execEor(ctx: MCF5407Ctx; d: Decoded): uint32 =
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

proc execImmediate(ctx: MCF5407Ctx; d: Decoded): uint32 =
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
  # MCF5407 User's Manual Table 2-15, folio 2-27, `andi.l`/`ori.l`/`eori.l #imm,Dx`:
  # the single cell 1(0/0). Was 6. (Table 2-15 spells the OR immediate
  # `or.l | #imm,Dx` rather than `ori.l`.)
  1'u32

proc execNot(ctx: MCF5407Ctx; d: Decoded): uint32 =
  ## NOT.L Dn. The memory forms of the 68000 are gone, and the manual is what
  ## says so. MCF5407 User's Manual Table 2-14, "One-Operand Instruction
  ## Execution Times", folio 2-27: the `not.l` row carries `Dx` in the `<ea>`
  ## column, `1(0/0)` under `Rn`, and a dash under every one of `(An)`, `(An)+`,
  ## `-(An)`, `(d16,An)`, `(d8,An,Xi*SF)`, `(xxx).wl` and `#xxx`. The `clr.l`
  ## and
  ## `tst.l` rows of the same table carry times in those same columns, so the
  ## dashes are this row's and not the table's. `m68k-elf-as -mcpu=5307`
  ## agrees: it rejects `not.l (%a0)`. So the operand mask is `{Dn}` and every
  ## other addressing mode traps.
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
  # MCF5407 User's Manual Table 2-14, folio 2-27, `not.l Dx`: the single cell 1(0/0).
  # Was 4.
  1'u32

# ---------------------------------------------------------------------------
# BTST, BSET, BCLR and BCHG.

proc execBitOp(ctx: MCF5407Ctx; d: Decoded): uint32 =
  ## One bit operation, in either of its two forms.
  ##
  ## The operand width decides the width of the access. A data register operand
  ## is 32 bits and every memory operand is 8 bits, and the access is one byte -
  ## the ".B,.L" of Table 2-8's Operand Size column on folio 2-20, which is
  ## carried by the bit
  ## operations and by no other instruction in this group. A core that read or
  ## wrote a longword in memory here would answer a different question and
  ## would also disturb the three bytes beside the operand.
  ##
  ## The modulus below is a choice and not a citation. Taking the bit number
  ## modulo the operand width - 32 for a register, 8 for memory - is what this
  ## core does with a number that does not fit, and no passage in the User's
  ## Manual states it. The header says why Figure 2-7's bit-numbering
  ## annotation does not settle it.
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
    # before the effective address's own extension words - the order the
    # assembler emits them in, measured: `btst #3,4(%a0)` is `0828 0003 0004`.
    bitNumber = uint32(fetchExt(ctx))
    if ctx.halted: return 0'u32
  let bit = bitNumber and (8'u32 * uint32(d.size) - 1'u32)
  let selector = 1'u32 shl bit
  # BTST reads and the others read and write, and that decides which operand
  # evaluator each one uses.
  #
  # `eaResolve` returns a reference a later write can reach, so it refuses
  # every operand that cannot be written: the PC-relative pair, the immediate
  # and the reserved mode-7 encodings. That is correct for BSET, BCLR and BCHG
  # and wrong for BTST, whose mask is `eaBitDynamic` and which admits the two
  # PC-relative sub-variants. Measured: `btst %d1,(4,%pc)` (`033a 0004`) and
  # `btst %d1,(4,%pc,%d2)` (`033b 2804`) both assemble on `-mcpu=5307`.
  #
  # The immediate is not one of them. `eaBitDynamic` excludes it, so the mask
  # check above refuses `btst %d1,#5` before either evaluator is reached. See
  # that constant in `decode_types.nim` for the manual rows behind it. The
  # STATIC form is the one whose `#<xxx>` cell the MCF5407 does time; the
  # dynamic row dashes it, and `eaBitDynamic` records the difference.
  #
  # The fix belongs here and not in `eaResolve`. Widening that procedure would
  # let a write reach a PC-relative or an immediate operand, and the bit
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

proc execShift(ctx: MCF5407Ctx; d: Decoded): uint32 =
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
  # count is taken modulo 64, and that number is a choice, not a citation:
  # Table 2-8, folios 2-20 and 2-21, gives the shifts as
  # `X/C <- (Dx << Dy) <- 0` and the two
  # right-hand forms and STATES NO MODULUS, and no other passage of the
  # User's Manual does either.
  #
  # The modulus is treated as a property of the shift unit rather than of the
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
      # No overflow is computed for ASL. CFPRM folio 4-12 gives V a flat
      # "Always cleared" and adds "Note that CCR[V] is always cleared by ASL
      # and ASR, unlike on the 68K family processors"; folio 4-11 says "The
      # overflow bit is always zero". The clearing at the foot of this proc is
      # the whole rule.
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
  if carry: sr = sr or ccrC
  # X takes C, and a count of zero leaves X alone. A shift that moved no bit
  # produced no carry to copy, and X is the bit a multi-precision sequence is
  # holding across instructions.
  if count != 0'u32:
    sr = sr and not ccrX
    if carry: sr = sr or ccrX
  ctx.sr = sr
  # MCF5407 User's Manual Table 2-15, folio 2-27, `asl.l`, `asr.l`, `lsl.l` and `lsr.l`,
  # all `<ea>,Dx`: 1(0/0) under `Rn` and under `#xxx`, every other column
  # dashed. This core is register-and-immediate only, so that is the whole
  # reachable row. Was 4.
  1'u32

# ---------------------------------------------------------------------------
# The dispatch entry `step` calls.

proc logicFamily*(ctx: MCF5407Ctx; word: uint16; d: Decoded): uint32 =
  ## Execute one logic, bit-operation or shift instruction. Called from `step`
  ## in `mcf5407/cpu` with the opcode word and the decoded operation. Returns a
  ## placeholder cycle count excluding the fetch - see the cycle block in
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
