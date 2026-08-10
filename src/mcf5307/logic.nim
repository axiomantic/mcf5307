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
## EVERY SHIFT IS REGISTER-ONLY AND A MEMORY SHIFT TRAPS. The 68000's
## `1110 0tt d 11 <ea>` memory shifts are not instructions on this part -
## `m68k-elf-objdump -m m68k:5307` decodes neither `e0c0` nor `e2d0` - and the
## `{Dn}` mask in `decode_types` refuses their operand. THE ROTATES ARE GONE
## TOO: manual section 3.9 lists "logical rotate" among the removed
## instructions, and `decode.nim` never produces an operation for them.
## CPU-13 owns both negative cases; this module and that mask are the
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
##       forms). N and Z come from the result. V is cleared by LSL, LSR and
##       ASR, none of which can produce a value the operand size cannot hold,
##       and ASL sets it when the sign changes.
##
## THE SHIFT IS PERFORMED ONE BIT AT A TIME, ON PURPOSE. A count is at most 63
## and the loop costs nothing, and it makes two rules that are easy to get
## wrong in closed form come out by construction: the carry is THE LAST BIT
## THAT LEFT THE WORD rather than a bit of the result, and ASL's overflow is
## "the sign changed AT ANY POINT during the shift" rather than "the sign of
## the result differs from the sign of the operand". Those two readings of the
## overflow rule agree at a count of one and can differ above it, so THE
## CONFORMANCE CORPUS ASSERTS V ONLY WHERE EVERY CANDIDATE READING AGREES ON
## ITS VALUE. That is two kinds of case and not one: every case at a count of
## ONE, and a case at a LARGER count whose operand CANNOT CHANGE SIGN.
## `asl_l_count_register_d1` is the second kind - it shifts `0x12345678` by
## two, the sign after k shifts is bit 31-k of the operand, and bits 31, 30
## and 29 are all zero, so no step of that shift changes the sign and both
## readings give V clear. NO CASE PINS A COUNT AT WHICH THE TWO READINGS
## DISAGREE, because the ColdFire Family Programmer's Reference Manual is the
## document that separates them (AGENTS.md section 11) and it is not on this
## machine.
##
## A SHIFT COUNT OF ZERO IS REACHABLE THROUGH THE REGISTER FORM ALONE, because
## the immediate form spends its zero slot on the value eight. It shifts
## nothing, clears C, and LEAVES X ALONE - a shift that moved no bit produced
## no carry to copy into X. The corpus asserts the destination of that case
## and not its status word, for the reason the paragraph above gives.
##
## CYCLES ARE NOMINAL, for the reason `move.nim`, `alu.nim` and `cpu.nim` all
## give: the per-instruction budget needs the clock work of open question 6 in
## AGENTS.md and no exact cost is asserted anywhere.
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
  ## NOT.L Dn. THE MEMORY FORMS OF THE 68000 ARE GONE: `not.l (%a0)` is
  ## rejected by `m68k-elf-as -mcpu=5307` and `4690` is not an instruction
  ## `m68k-elf-objdump -m m68k:5307` decodes, so the operand mask is `{Dn}`
  ## and every other addressing mode traps.
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
  ## THE OPERAND WIDTH DECIDES THE BIT NUMBER'S MODULUS AND THE WIDTH OF THE
  ## ACCESS, AND IT IS ONE DECISION. A data register operand is 32 bits and
  ## the bit number is taken modulo 32; every memory operand is 8 bits and the
  ## number is taken modulo 8 AND THE ACCESS IS ONE BYTE. A core that read or
  ## wrote a longword in memory here would answer a different question and
  ## would also disturb the three bytes beside the operand; the conformance
  ## corpus seeds those three bytes with distinct values and asserts them.
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
  let dest = eaResolve(ctx, d.ea, d.size)
  if ctx.halted: return 0'u32
  let value = eaRefRead(ctx, dest, d.size)
  if ctx.halted: return 0'u32
  let wasSet = (value and selector) != 0'u32
  if d.op != opBtst:
    let written = case d.op
      of opBset: value or selector
      of opBclr: value and not selector
      else: value xor selector
    eaRefWrite(ctx, dest, d.size, written)
    if ctx.halted: return 0'u32
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
  # A REGISTER COUNT IS TAKEN MODULO 64 and an immediate one is 1 to 8. The
  # modulus is a property of the silicon's shift unit and not of the operand
  # width, so a count of 40 shifts a 32-bit register 40 times and leaves zero
  # rather than shifting it 8.
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
      # ASL'S OVERFLOW IS A PROPERTY OF THE WHOLE SHIFT AND NOT OF ITS LAST
      # STEP: it is set if the sign changed at ANY point, so it is latched
      # here and never cleared inside the loop.
      if arithmetic and ((before xor value) and 0x80000000'u32) != 0'u32:
        overflow = true
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
  if overflow: sr = sr or ccrV
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
