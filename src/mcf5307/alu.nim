## `alu` - the integer-arithmetic instruction group of the ColdFire ISA_A
## core. Task CPU-8 creates this file. Design section 6.1.
##
## This module executes ADD, ADDA, ADDI, ADDQ, ADDX, SUB, SUBA, SUBI, SUBQ,
## SUBX, NEG, NEGX, CLR, EXT, EXTB, MULU.L, MULS.L, DIVU.L, DIVS.L and the two
## REMx.L forms, AND NOTHING ELSE. The register file, the board accesses and
## the effective-address evaluation are `mcf5307/machine`'s.
##
## THIS MODULE IS A SIBLING OF `move.nim` AND OF `decode.nim`. It imports
## neither, and neither imports it. Adding this group cost one new module, one
## `import` line in `cpu.nim` and one arm of the `case` there; `decode.nim`
## gained the opcodes and NO import. The rule and the reason are in
## `~/Desktop/avoiding-cycles.md`: an executor that reaches into another
## executor for a helper is the decoder-under-executor cycle one layer down,
## and it is bad at two siblings and worse at four.
##
## THE SIZE IS LONG AND THE EXCEPTIONS ARE NAMED. Arithmetic on this part is
## 32-bit. `ADD.B`, `ADD.W`, `ADDA.W`, `ADDI.B`, `ADDQ.W`, `NEG.W`, `ADDX.W`
## and the rest of the byte and word forms are 68000 encodings that ISA_A
## dropped, and each one TRAPS here; CPU-13 carries them as negative cases.
## `CLR` is the exception: it keeps all three sizes, which
## `m68k-elf-as -mcpu=5307` confirms by accepting `clr.b` and `clr.w`.
##
## THE COLDFIRE DIVIDE IS NOT THE 68020 DIVIDE. `DIVU.L`/`DIVS.L` reuse the
## 68020 two-word encoding, and the second word names a quotient register Dq
## and a remainder register Dr. On the 68020 an unequal pair is `DIVUL`, which
## writes BOTH. On ColdFire an unequal pair is `REMU.L`/`REMS.L`, WHICH WRITES
## THE REMAINDER ONLY and leaves Dq alone.
##
## THERE IS NO EXCEPTION MODEL YET. A divide by zero is a trap vector on
## silicon and CPU-14 owns the vector table. Until then it halts the context
## with `fault`, which is the same channel every other illegal operand uses.
##
## CYCLES ARE NOMINAL, for the reason `move.nim` and `cpu.nim` both give: the
## per-instruction budget needs the clock work of open question 6 in AGENTS.md
## and no exact cost is asserted anywhere.
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
  ## Halt the context with `fault`. Every illegal size, illegal operand mode
  ## and divide by zero in this module ends here, so that "the core refused"
  ## is one observable and not several.
  ctx.fault = true
  ctx.halted = true
  0'u32

# ---------------------------------------------------------------------------
# The condition codes of addition and subtraction.
#
# X and C are the SAME BIT VALUE for these instructions and they live in two
# places: C is read by the conditional branches and X is read by ADDX, SUBX
# and NEGX. N and Z come from the result. V is the SIGNED overflow, which is
# a different question from the carry and is why both bits exist.
#
# The extended forms (ADDX, SUBX, NEGX) differ in Z alone: THEY CLEAR Z ON A
# NON-ZERO RESULT AND LEAVE IT ALONE OTHERWISE, so that a multi-precision
# sequence ends with Z set exactly when EVERY word of the result was zero. An
# ordinary ADD would set Z from its own word and lose the earlier words.

proc setAddCc(ctx: MCF5307Ctx; src, dst, res: uint32; carry: bool;
              sticky: bool) =
  let overflow = ((src xor res) and (dst xor res) and 0x80000000'u32) != 0'u32
  var sr = ctx.sr and not (ccrN or ccrV or ccrC or ccrX)
  if (res and 0x80000000'u32) != 0'u32: sr = sr or ccrN
  if res == 0'u32:
    if not sticky: sr = sr or ccrZ
  else:
    sr = sr and not ccrZ
  if overflow: sr = sr or ccrV
  if carry: sr = sr or (ccrC or ccrX)
  ctx.sr = sr

proc setSubCc(ctx: MCF5307Ctx; src, dst, res: uint32; borrow: bool;
              sticky: bool) =
  let overflow = ((src xor dst) and (dst xor res) and 0x80000000'u32) != 0'u32
  var sr = ctx.sr and not (ccrN or ccrV or ccrC or ccrX)
  if (res and 0x80000000'u32) != 0'u32: sr = sr or ccrN
  if res == 0'u32:
    if not sticky: sr = sr or ccrZ
  else:
    sr = sr and not ccrZ
  if overflow: sr = sr or ccrV
  if borrow: sr = sr or (ccrC or ccrX)
  ctx.sr = sr

proc addWithCarry(dst, src: uint32; carryIn: uint32):
    tuple[res: uint32, carryOut: bool] =
  let wide = uint64(dst) + uint64(src) + uint64(carryIn)
  (uint32(wide and 0xFFFFFFFF'u64), wide > 0xFFFFFFFF'u64)

proc subWithBorrow(dst, src: uint32; borrowIn: uint32):
    tuple[res: uint32, carryOut: bool] =
  let subtrahend = uint64(src) + uint64(borrowIn)
  (uint32((uint64(dst) - subtrahend) and 0xFFFFFFFF'u64),
   uint64(dst) < subtrahend)

proc xBit(ctx: MCF5307Ctx): uint32 =
  if (ctx.sr and ccrX) != 0'u32: 1'u32 else: 0'u32

# ---------------------------------------------------------------------------
# ADD and SUB, both directions.

proc execAddSub(ctx: MCF5307Ctx; d: Decoded; isSub: bool): uint32 =
  ## `<ea> op Dn -> Dn` when `dirToEa` is false, `Dn op <ea> -> <ea>` when it
  ## is true. The two directions carry DIFFERENT operand masks: the first
  ## reads any data-addressing mode, and the second writes a memory-alterable
  ## one. A single mask would let `add.l %d1,(4,%pc)` through.
  if d.size != 4'u8:
    return trap(ctx)
  if not d.dirToEa:
    if not eaIsLegalFor(d.op, d.ea):
      return trap(ctx)
    let src = eaRead(ctx, d.ea, 4)
    if ctx.halted: return 0'u32
    let dst = regD(ctx, d.destReg)
    let (res, c) = if isSub: subWithBorrow(dst, src, 0'u32)
                   else: addWithCarry(dst, src, 0'u32)
    setRegD(ctx, d.destReg, res)
    if isSub: setSubCc(ctx, src, dst, res, c, false)
    else: setAddCc(ctx, src, dst, res, c, false)
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
  let src = regD(ctx, d.destReg)
  let (res, c) = if isSub: subWithBorrow(dst, src, 0'u32)
                 else: addWithCarry(dst, src, 0'u32)
  eaRefWrite(ctx, dest, 4, res)
  if ctx.halted: return 0'u32
  if isSub: setSubCc(ctx, src, dst, res, c, false)
  else: setAddCc(ctx, src, dst, res, c, false)
  6'u32

proc execAddSubA(ctx: MCF5307Ctx; d: Decoded; isSub: bool): uint32 =
  ## ADDA.L and SUBA.L. THEY TOUCH NO CONDITION CODE: an address computation
  ## must not disturb the flags a following conditional branch reads.
  if d.size != 4'u8:
    return trap(ctx)
  if not eaIsLegalFor(d.op, d.ea):
    return trap(ctx)
  let src = eaRead(ctx, d.ea, 4)
  if ctx.halted: return 0'u32
  let dst = regA(ctx, d.destReg)
  setRegA(ctx, d.destReg, if isSub: dst - src else: dst + src)
  4'u32

proc execAddSubI(ctx: MCF5307Ctx; d: Decoded; isSub: bool): uint32 =
  ## ADDI.L and SUBI.L. The long immediate is the two words after the opcode.
  if d.size != 4'u8:
    return trap(ctx)
  if not eaIsLegalFor(d.op, d.ea):
    return trap(ctx)
  let hi = fetchExt(ctx)
  let lo = fetchExt(ctx)
  if ctx.halted: return 0'u32
  let src = (uint32(hi) shl 16) or uint32(lo)
  let dst = regD(ctx, d.ea.reg)
  let (res, c) = if isSub: subWithBorrow(dst, src, 0'u32)
                 else: addWithCarry(dst, src, 0'u32)
  setRegD(ctx, d.ea.reg, res)
  if isSub: setSubCc(ctx, src, dst, res, c, false)
  else: setAddCc(ctx, src, dst, res, c, false)
  6'u32

proc execAddSubQ(ctx: MCF5307Ctx; d: Decoded; isSub: bool): uint32 =
  ## ADDQ.L and SUBQ.L. An ADDRESS REGISTER DESTINATION SETS NO CONDITION
  ## CODE, exactly as ADDA does; every other destination sets them all.
  if d.size != 4'u8:
    return trap(ctx)
  if not eaIsLegalFor(d.op, d.ea):
    return trap(ctx)
  let src = uint32(d.imm)
  if d.ea.mode == eaAn:
    let dst = regA(ctx, d.ea.reg)
    setRegA(ctx, d.ea.reg, if isSub: dst - src else: dst + src)
    return 4'u32
  let dest = eaResolve(ctx, d.ea, 4)
  if ctx.halted: return 0'u32
  let dst = eaRefRead(ctx, dest, 4)
  if ctx.halted: return 0'u32
  let (res, c) = if isSub: subWithBorrow(dst, src, 0'u32)
                 else: addWithCarry(dst, src, 0'u32)
  eaRefWrite(ctx, dest, 4, res)
  if ctx.halted: return 0'u32
  if isSub: setSubCc(ctx, src, dst, res, c, false)
  else: setAddCc(ctx, src, dst, res, c, false)
  4'u32

proc execAddSubX(ctx: MCF5307Ctx; d: Decoded; isSub: bool): uint32 =
  ## ADDX.L Dy,Dx and SUBX.L Dy,Dx. The register form is the only one this
  ## part has; the `-(Ay),-(Ax)` form of the 68000 arrives here with an
  ## address-register operand and the legality mask rejects it.
  if d.size != 4'u8:
    return trap(ctx)
  if not eaIsLegalFor(d.op, d.ea):
    return trap(ctx)
  let src = regD(ctx, d.ea.reg)
  let dst = regD(ctx, d.destReg)
  let x = xBit(ctx)
  let (res, c) = if isSub: subWithBorrow(dst, src, x)
                 else: addWithCarry(dst, src, x)
  setRegD(ctx, d.destReg, res)
  if isSub: setSubCc(ctx, src, dst, res, c, true)
  else: setAddCc(ctx, src, dst, res, c, true)
  4'u32

# ---------------------------------------------------------------------------
# NEG, NEGX and CLR.

proc execNeg(ctx: MCF5307Ctx; d: Decoded; extended: bool): uint32 =
  ## NEG.L and NEGX.L: `0 - Dn` and `0 - Dn - X`. C IS SET WHENEVER A BORROW
  ## LEFT THE WORD, which for NEG is exactly "the operand was not zero".
  if d.size != 4'u8:
    return trap(ctx)
  if not eaIsLegalFor(d.op, d.ea):
    return trap(ctx)
  let src = regD(ctx, d.ea.reg)
  let x = if extended: xBit(ctx) else: 0'u32
  let (res, borrow) = subWithBorrow(0'u32, src, x)
  setRegD(ctx, d.ea.reg, res)
  setSubCc(ctx, src, 0'u32, res, borrow, extended)
  4'u32

proc execClr(ctx: MCF5307Ctx; d: Decoded): uint32 =
  ## CLR.B/.W/.L. N, V and C take fixed values, Z is always set, AND X IS
  ## UNTOUCHED - a clear is not an arithmetic result and must not disturb a
  ## multi-precision sequence in progress.
  if d.size == 0'u8:
    return trap(ctx)
  if not eaIsLegalFor(opClr, d.ea):
    return trap(ctx)
  let dest = eaResolve(ctx, d.ea, d.size)
  if ctx.halted: return 0'u32
  eaRefWrite(ctx, dest, d.size, 0'u32)
  if ctx.halted: return 0'u32
  ctx.sr = (ctx.sr and not (ccrN or ccrV or ccrC)) or ccrZ
  4'u32

# ---------------------------------------------------------------------------
# EXT and EXTB.

proc execExt(ctx: MCF5307Ctx; d: Decoded; fromByte: bool): uint32 =
  ## EXT.W (byte into word), EXT.L (word into long) and EXTB.L (byte into
  ## long). EXT.W WRITES THE LOW WORD ALONE and the upper half of the
  ## register is untouched, so N comes from bit 15 of a word result and from
  ## bit 31 of a long one.
  if not eaIsLegalFor(d.op, d.ea):
    return trap(ctx)
  let src = regD(ctx, d.ea.reg)
  let widened =
    if fromByte or d.size == 2'u8: uint32(s8(uint16(src and 0xFF'u32)))
    else: uint32(s16(uint16(src and 0xFFFF'u32)))
  if d.size == 2'u8:
    setRegD(ctx, d.ea.reg, mergeSized(src, widened, 2))
  else:
    setRegD(ctx, d.ea.reg, widened)
  setNzClearVc(ctx, widened, d.size)
  4'u32

# ---------------------------------------------------------------------------
# MULU.L, MULS.L, DIVU.L, DIVS.L and REMx.L.
#
# Both families carry the 68020 two-word encoding. The second word follows the
# opcode word and PRECEDES the effective address's own extension words, so it
# is fetched first.

const
  mulDivSignedBit = 0x0800'u16   ## bit 11: MULS/DIVS rather than MULU/DIVU
  mulDivWideBit = 0x0400'u16     ## bit 10: the 68020 64-bit form

proc execMulWord(ctx: MCF5307Ctx; d: Decoded): uint32 =
  ## MULU.W and MULS.W: `16 x 16 -> 32`, one instruction word, no extension.
  ##
  ## CFPRM folios 4-55 (MULS) and 4-57 (MULU), word form: "the multiplier and
  ## multiplicand are both word operands, and the result is a longword
  ## operand. A REGISTER OPERAND IS THE LOW-ORDER WORD; THE UPPER WORD OF THE
  ## REGISTER IS IGNORED. ALL 32 BITS OF THE PRODUCT ARE SAVED in the
  ## destination data register."
  let src = eaRead(ctx, d.ea, 2)
  if ctx.halted: return 0'u32
  let dst = regD(ctx, d.destReg)
  # BOTH OPERANDS ARE NARROWED TO 16 BITS BEFORE THE MULTIPLY. `eaRead`
  # returns the WHOLE register for a `Dn` operand and leaves the narrowing to
  # the caller - `machine.nim` says so at its declaration - and the
  # destination is read with `regD`, which does no narrowing either. Without
  # both masks a data-register source would multiply 32 bits by 16.
  let srcW = uint16(src and 0xFFFF'u32)
  let dstW = uint16(dst and 0xFFFF'u32)
  # THE SIGNED BIT IS OBSERVABLE IN THIS FORM, UNLIKE THE LONG ONE BELOW. A
  # 16x16 product is kept WHOLE in 32 bits, so the sign extension of the two
  # word operands reaches the result; the long form keeps only the low 32 bits
  # of a 32x32 product, where it cannot. `0xFFFF * 3` is `0x0002FFFD` unsigned
  # and `0xFFFFFFFD` signed.
  let res =
    if d.op == opMuls:
      cast[uint32](int32(cast[int16](srcW)) * int32(cast[int16](dstW)))
    else:
      uint32(srcW) * uint32(dstW)
  setRegD(ctx, d.destReg, res)
  # V AND C ARE CLEARED AND N AND Z COME FROM ALL 32 BITS, which is the same
  # rule the long form uses and for the same reason: folios 4-55 and 4-57
  # print ONE condition-code table each, above the WORD instruction format,
  # and neither continuation page (4-56, 4-58) carries a second. The word
  # table therefore governs both sizes.
  setNzClearVc(ctx, res, 4)
  # MCF5307 User's Manual Table 3-13 p.3-28, `muls.w`/`mulu.w <ea>,Dx`, the
  # `Rn` column: `3(0/0)`. THIS CORE RETURNS ONE NOMINAL FIGURE PER FORM AND
  # DOES NOT MODEL THE PER-OPERAND COLUMNS - the row also carries `6(1/0)` for
  # the four memory modes, `7(1/0)` for `(d8,An,Xi*SF)`, `6(1/0)` for `xxx.wl`
  # and `3(0/0)` for `#xxx`, and none of those is returned here.
  3'u32

proc execMul(ctx: MCF5307Ctx; d: Decoded): uint32 =
  if not eaIsLegalFor(d.op, d.ea, d.size):
    return trap(ctx)
  if d.size == 2'u8:
    return execMulWord(ctx, d)
  let ext = fetchExt(ctx)
  if ctx.halted: return 0'u32
  if (ext and mulDivWideBit) != 0'u16:
    # The 64-bit product form is a 68020 instruction. This part has the
    # 32-bit form alone and the wide one must not silently produce half a
    # result.
    return trap(ctx)
  let dl = uint8((ext shr 12) and 0x7'u16)
  let src = eaRead(ctx, d.ea, 4)
  if ctx.halted: return 0'u32
  let dst = regD(ctx, dl)
  # V IS ALWAYS CLEARED, AND THAT IS THE CFPRM'S OWN WORD RATHER THAN AN
  # INFERENCE. Folio 4-55 for MULS and folio 4-57 for MULU each give V "Always
  # cleared" in the condition-code table and each add the sentence "Note that
  # CCR[V] is always cleared by MULS/MULU, unlike the 68K family processors".
  # Neither folio's longword page (4-56, 4-58) carries a condition-code table
  # of its own, so the word-form table governs this 32-bit form too. C is
  # "Always cleared" on both, N comes from bit 31 of the 32 bits written - for
  # MULU that is bit 31 of the UNSIGNED product, so it is not always zero - and
  # Z from those same 32 bits. `setNzClearVc` is exactly that rule.
  #
  # AN EARLIER REVISION SET V WHEN THE 32 BITS WRITTEN WERE NOT THE WHOLE
  # PRODUCT, so that a product whose low half is zero could be told from a
  # multiply by zero. That is the 68K rule and it is the one the CFPRM note
  # singles out as not this part's. The distinction it bought is real and this
  # part simply does not report it.
  #
  # THE SIGNED BIT SELECTS NOTHING IN THIS FORM, and the multiply is written
  # once because of it. A 32x32 product's low 32 bits are the same under both
  # readings - multiplication modulo 2^32 does not depend on how the operands'
  # sign bits are interpreted - and every flag above comes from those 32 bits.
  # So MULS.L and MULU.L differ in NOTHING observable here once V is gone.
  # `mulDivSignedBit` is still the decoder's business and still separates the
  # DIVIDE forms below, where the quotient genuinely differs.
  let res = uint32((uint64(dst) * uint64(src)) and 0xFFFFFFFF'u64)
  setRegD(ctx, dl, res)
  setNzClearVc(ctx, res, 4)
  10'u32

const divWordCycles = 20'u32
  ## MCF5307 User's Manual Table 3-13 p.3-28, `divs.w`/`divu.w <ea>,Dx`, the
  ## `Rn` column: `20(0/0)`. As with the multiply above, this core returns one
  ## nominal figure per form and does not model the per-operand columns.

proc execDivWord(ctx: MCF5307Ctx; d: Decoded): uint32 =
  ## DIVU.W and DIVS.W: a 32-bit dividend in Dx over a 16-bit source, with
  ## BOTH halves of the answer packed into Dx.
  ##
  ## CFPRM folios 4-31 (DIVS) and 4-33 (DIVU): "For a word-sized operation,
  ## the destination operand is a longword and the source is a word; THE
  ## 16-BIT QUOTIENT IS IN THE LOWER WORD AND THE 16-BIT REMAINDER IS IN THE
  ## UPPER WORD of the destination. Note that THE SIGN OF THE REMAINDER IS THE
  ## SAME AS THE SIGN OF THE DIVIDEND."
  let src = eaRead(ctx, d.ea, 2)
  if ctx.halted: return 0'u32
  # THE DIVISOR IS THE LOW WORD AND THE MASK IS LOAD-BEARING. `eaRead` hands
  # back the whole register for a `Dn` source, so without it a source of
  # `0x00010000` would divide by 65536 instead of trapping on a zero divisor.
  let divisor = uint16(src and 0xFFFF'u32)
  if divisor == 0'u16:
    # A DIVIDE BY ZERO IS EXCEPTION VECTOR 5 AT VECTOR OFFSET 0x014, of class
    # Fault - CFPRM Table 11-1, "Exception Vector Assignments", folio 11-2,
    # whose footnote adds "if the divide unit is not present (5202, 5204,
    # 5206), vector 5 is reserved". Folios 4-31 and 4-33 add that NO REGISTERS
    # ARE AFFECTED and that the stack frame points at the offending opcode.
    #
    # THERE IS NO EXCEPTION MODEL YET and CPU-14 owns the vector table, so
    # this halts with `fault` - the channel the LONG form already uses and the
    # one every illegal operand in this module uses. The vector is recorded
    # here so that CPU-14 does not have to re-derive it.
    return trap(ctx)
  let dividend = regD(ctx, d.destReg)
  var quotient: uint32
  var remainder: uint32
  var overflowed: bool
  if d.op == opDivs:
    let a = int64(cast[int32](dividend))
    let b = int64(cast[int16](divisor))
    # Nim's `div` truncates toward zero and `mod` takes the sign of the
    # DIVIDEND, which is exactly the pair the folios describe: 17 / -3 is -5
    # with remainder +2, and -17 / 3 is -5 with remainder -2. A flooring
    # division gives -6 and +1 for the second and fails both halves.
    let q = a div b
    # THE OVERFLOW BOUNDARY AT EXACTLY -32768 IS THE ONE INFERENCE IN THIS
    # PATH, AND IT IS MARKED HERE BECAUSE THIS COMPARISON IS WHAT DECIDES IT.
    #
    # The folios say "An overflow occurs if the quotient is larger than a
    # 16-bit (.W) or 32-bit (.L) signed integer" and do not define "larger"
    # for the asymmetric end of the range. -32768 IS a 16-bit signed integer -
    # it is the smallest one - so under the reading taken here it does NOT
    # overflow, and the range test below is the plain two-sided one. The other
    # available reading is that "larger" means larger in MAGNITUDE than the
    # largest positive value, under which -32768 WOULD overflow.
    #
    # NOTHING IN THE CFPRM SETTLES IT AND NO ORACLE AVAILABLE HERE DOES
    # EITHER: `m68k-elf-as` decides what ASSEMBLES, not what a quotient does
    # at run time, and Table 3-13 times the instruction without saying what it
    # computes. WHAT WOULD SETTLE IT is a run on silicon or on a hardware
    # model - `divs.w` with a dividend of -65536 and a divisor of 2, reading V
    # afterwards - or an erratum or a later revision of the folio that states
    # the boundary. Until then this is a READING and not a measurement.
    #
    # `tests/t_alu.nim` brackets it: the -32768 case is labelled [INFERENCE]
    # and its -32769 neighbour overflows under either reading, so a reversal
    # reds the labelled case and leaves the neighbour green. Measured
    # 2026-08-11 by moving this boundary to the other reading: it reds TWO
    # cases across the suite and not one, because the conformance corpus
    # carries the same boundary as
    # `divs_w_quotient_of_minus_32768_does_not_overflow`. Both name it.
    if q < -32768'i64 or q > 32767'i64:
      overflowed = true
    else:
      quotient = uint32(cast[uint64](q) and 0xFFFF'u64)
      remainder = uint32(cast[uint64](a mod b) and 0xFFFF'u64)
  else:
    let q = dividend div uint32(divisor)
    # THE UNSIGNED BOUNDARY IS NOT AMBIGUOUS: the folio says "larger than a
    # 16-bit (.W) ... unsigned integer" and 0xFFFF is that integer.
    if q > 0xFFFF'u32:
      overflowed = true
    else:
      quotient = q
      remainder = dividend mod uint32(divisor)
  if overflowed:
    # THE DESTINATION IS UNAFFECTED - "If overflow is detected, the
    # destination register is unaffected" - and the status word is fully
    # determined: V set, C cleared ("Always cleared"), N and Z CLEARED
    # ("Cleared if overflow is detected"), X untouched ("Not affected"). This
    # is the same rule and the same line the long form uses above.
    ctx.sr = (ctx.sr and not (ccrC or ccrN or ccrZ)) or ccrV
    return divWordCycles
  setRegD(ctx, d.destReg, (remainder shl 16) or quotient)
  # N AND Z COME FROM THE QUOTIENT AND THE SIZE IS 2, NOT FROM THE LONGWORD
  # WRITTEN. The folios read "N ... set if the QUOTIENT is negative" and
  # "Z ... set if the QUOTIENT is zero", and the quotient is 16 bits wide
  # here, so N is bit 15 of it. A core taking N from bit 31 of the register it
  # just wrote would report the REMAINDER's sign; `-17 / -5` is quotient +3
  # with remainder -2 and separates the two.
  setNzClearVc(ctx, quotient, 2)
  divWordCycles

proc execDiv(ctx: MCF5307Ctx; d: Decoded): uint32 =
  if not eaIsLegalFor(d.op, d.ea, d.size):
    return trap(ctx)
  if d.size == 2'u8:
    return execDivWord(ctx, d)
  let ext = fetchExt(ctx)
  if ctx.halted: return 0'u32
  if (ext and mulDivWideBit) != 0'u16:
    return trap(ctx)
  let dq = uint8((ext shr 12) and 0x7'u16)
  let dr = uint8(ext and 0x7'u16)
  let signed = (ext and mulDivSignedBit) != 0'u16
  let src = eaRead(ctx, d.ea, 4)
  if ctx.halted: return 0'u32
  if src == 0'u32:
    # A divide by zero is exception vector 5 on silicon and CPU-14 owns the
    # vector table. Halting with `fault` is the channel available today, and
    # it is the one every other illegal operand already uses.
    return trap(ctx)
  let dividend = regD(ctx, dq)
  if signed and dividend == 0x80000000'u32 and src == 0xFFFFFFFF'u32:
    # THE ONE SIGNED DIVISION OVERFLOW. The most negative value has no
    # positive counterpart, so the quotient does not exist. THE OPERANDS ARE
    # UNCHANGED and the status word is fully determined: V set, C cleared, AND
    # N AND Z CLEARED. CFPRM folios 4-31 and 4-33 (DIVS, DIVU) and 4-70 and
    # 4-71 (REMS, REMU) all read "N Cleared if overflow is detected;
    # otherwise ..." and "Z Cleared if overflow is detected; otherwise ...",
    # with "V Set if an overflow occurs" and "C Always cleared". X is "Not
    # affected" and is the one bit that survives.
    #
    # AN EARLIER REVISION LEFT N AND Z AS IT FOUND THEM and called them
    # undefined - "the one choice a reader can predict". They are not
    # undefined; the four folios state the rule directly, and the choice was
    # unguarded because the only overflow case entered with N and Z already
    # clear and so could not tell the two behaviours apart.
    ctx.sr = (ctx.sr and not (ccrC or ccrN or ccrZ)) or ccrV
    return 10'u32
  var quotient: uint32
  var written: uint32
  if signed:
    let a = int64(cast[int32](dividend))
    let b = int64(cast[int32](src))
    # Nim's `div` truncates toward zero and `mod` takes the sign of the
    # dividend, which is what the silicon does: 17 / -3 is -5 and not -6,
    # and -17 rem 5 is -2 and not +3.
    quotient = uint32(cast[uint64](a div b) and 0xFFFFFFFF'u64)
    written = if dr == dq: quotient
              else: uint32(cast[uint64](a mod b) and 0xFFFFFFFF'u64)
  else:
    quotient = dividend div src
    written = if dr == dq: quotient else: dividend mod src
  # COLDFIRE'S REMx.L PRODUCES THE REMAINDER ONLY. An unequal register pair
  # is `REMU.L`/`REMS.L` here and `DIVUL`/`DIVSL` on the 68020, and the
  # 68020 instruction also writes the quotient into Dq. Writing Dq here
  # would corrupt the dividend a following instruction still reads.
  setRegD(ctx, (if dr == dq: dq else: dr), written)
  # N AND Z COME FROM THE QUOTIENT EVEN WHEN THE REMAINDER IS WHAT WAS
  # WRITTEN. CFPRM folios 4-70 and 4-71 give REMS and REMU "N ... set if the
  # QUOTIENT is negative, cleared if positive" and "Z ... set if the QUOTIENT
  # is zero, cleared if nonzero", though the operation line of each is
  # "Destination/Source -> Remainder". So the flags and the destination come
  # from DIFFERENT NUMBERS, and `quotient` is computed above for the REMx
  # forms purely to feed this line.
  #
  # FOR DIVU AND DIVS THIS IS THE SAME VALUE it always was - an equal register
  # pair writes the quotient - so only the REMx forms change behaviour here.
  # An earlier revision passed `written`, which took the flags from the
  # remainder; the two REMx cases that covered it happened to have a quotient
  # and a remainder agreeing on both N and Z, so nothing caught it.
  setNzClearVc(ctx, quotient, 4)
  10'u32

# ---------------------------------------------------------------------------
# The dispatch entry `step` calls.

proc aluFamily*(ctx: MCF5307Ctx; word: uint16; d: Decoded): uint32 =
  ## Execute one integer-arithmetic instruction. Called from `step` in
  ## `mcf5307/cpu` with the opcode word and the decoded operation. Returns the
  ## instruction's nominal cycles excluding the fetch; halts the context with
  ## `fault` set on an illegal size, an illegal effective address or a divide
  ## by zero.
  case d.op
  of opAdd: execAddSub(ctx, d, false)
  of opSub: execAddSub(ctx, d, true)
  of opAdda: execAddSubA(ctx, d, false)
  of opSuba: execAddSubA(ctx, d, true)
  of opAddi: execAddSubI(ctx, d, false)
  of opSubi: execAddSubI(ctx, d, true)
  of opAddq: execAddSubQ(ctx, d, false)
  of opSubq: execAddSubQ(ctx, d, true)
  of opAddx: execAddSubX(ctx, d, false)
  of opSubx: execAddSubX(ctx, d, true)
  of opNeg: execNeg(ctx, d, false)
  of opNegx: execNeg(ctx, d, true)
  of opClr: execClr(ctx, d)
  of opExt: execExt(ctx, d, false)
  of opExtb: execExt(ctx, d, true)
  of opMulu, opMuls: execMul(ctx, d)
  of opDivu, opDivs: execDiv(ctx, d)
  else: trap(ctx)
