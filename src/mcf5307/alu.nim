## `alu` - the integer-arithmetic instruction group of the ColdFire ISA_A core.
##
## This module executes ADD, ADDA, ADDI, ADDQ, ADDX, SUB, SUBA, SUBI, SUBQ,
## SUBX, NEG, NEGX, CLR, EXT, EXTB, MULU, MULS, DIVU and DIVS in BOTH their
## word and their long forms, and the REMx.L forms, AND NOTHING ELSE. The
## register file, the board accesses and the effective-address evaluation are
## `mcf5307/machine`'s. The word forms are `execMulWord` and `execDivWord`.
##
## This module does not reach into another executor for a helper; that would
## invert the layering one level down.
##
## Arithmetic on this part is 32-bit. `ADD.B`, `ADD.W`, `ADDA.W`, `ADDI.B`,
## `ADDQ.W`, `NEG.W`, `ADDX.W` and the rest of the byte and word forms are
## 68000 encodings that ISA_A dropped, and each one traps here. `CLR` is the
## exception: it keeps all three sizes, which `m68k-elf-as -mcpu=5407`
## confirms by accepting `clr.b` and `clr.w`, and which MCF5407 User's Manual
## Table 2-8, folio 2-20, prints as an operand size of `.B,.W,.L` for CLR.
##
## THE BYTE AND WORD COMPARES LEFT THAT DROPPED LIST ON THIS PART. Rev. B
## restores `CMP.B`, `CMP.W`, `CMPI.B` and `CMPI.W` - MCF5407 User's Manual
## Table 2-7, "ColdFire ISA_B Extension Summary", folio 2-19 - and
## `control.nim` records what this core does about them. The byte and word
## forms of ADD, ADDA, ADDQ, NEG and ADDX named above are not in Rev. B and
## stay dropped.
##
## The ColdFire divide is not the 68020 divide. `DIVU.L`/`DIVS.L` reuse the
## 68020 two-word encoding, and the second word names a quotient register Dq
## and a remainder register Dr. On the 68020 an unequal pair is `DIVUL`, which
## writes both. On ColdFire an unequal pair is `REMU.L`/`REMS.L`, which writes
## the remainder only and leaves Dq alone.
##
## A divide by zero is a trap vector on silicon; this core halts the context
## with `fault` instead, the same channel every other illegal operand uses.
##
## CYCLES. See the block above the constants in `cpu.nim`. `adda.l` and
## `suba.l` have no timing row in MCF5407 User's Manual Table 2-15 (folios 2-27
## to 2-29) or Table 2-14 (folio 2-27) at all, established by reading those
## pages whole rather than by looking at neighbours: the opcode column is not
## alphabetical, so a gap between neighbours proves nothing - `msac.w` and
## `msac.l` print before `muls.w` on folio 2-28. `control.nim` records the same
## absence for CMPA.
##
## THE REMx FORMS ARE PRICED ON THIS PART AND WERE NOT ON THE MCF5307. That is
## a difference in the silicon's documentation and not a renumbering. Table
## 2-15's final page, folio 2-29, carries a `rems.l <ea>,Dx` row and a
## `remu.l <ea>,Dx` row, each reading `35(0/0)` under `Rn` and `35(1/0)` under
## `(An)`, `(An)+`, `-(An)` and `(d16,An)`, and dashing `(d8,An,Xi*SF)`,
## `xxx.wl` and `#<xxx>`. The MCF5307's Table 3-13 had neither row, and this
## module's note used to say a reader who priced REMS.L or REMU.L off the
## divide row would be quoting a cell the table never offered. On the MCF5407
## the table offers it directly, and it is the same 35 the `divs.l`/`divu.l`
## row carries, so `execDiv`'s single return is right for all four opcodes
## rather than right for two and invented for the other two.
##
## That row was read off the RENDERED folio and not off a text extraction.
## `pdftotext` is lossy inside these tables, so the absence of `adda.l` and
## `suba.l` above rests on the printed page with its neighbours either side,
## which is evidence a failed grep would not be.
##
## This module still models the REMx forms as behaviour of their own inside
## `execDiv` - an unequal register pair writes the remainder and leaves Dq
## alone - because the timing row prices them without saying what they compute.
##
## The word MUL and DIV returns equal a cell of their own row and say so at the
## site; nothing else here was derived from a table.
##
## Instruction semantics, the condition-code rules and the encodings are taken
## from the ColdFire Family Programmer's Reference Manual and the MCF5407
## User's Manual, and from this project's own measurements with the pinned
## cross assembler.

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
# X and C take the same bit value for these instructions and they live in two
# places: C is read by the conditional branches and X is read by ADDX, SUBX
# and NEGX. N and Z come from the result. V is the signed overflow, which is
# a different question from the carry and is why both bits exist.
#
# The extended forms (ADDX, SUBX, NEGX) differ in Z alone: they clear Z on a
# non-zero result and leave it alone otherwise, so that a multi-precision
# sequence ends with Z set exactly when every word of the result was zero. An
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
  ## is true. The two directions carry different operand masks: the first
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
  # The destination is resolved once. `(An)+` and `-(An)` adjust the address
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
  # MCF5407 User's Manual Table 2-15, folio 2-27, `add.l`/`sub.l`: 1(0/0)
  # under `Rn` and `#xxx`, 1(1/0) under the four memory modes and `xxx.wl` in
  # the to-register direction, 1(1/1) in the to-memory direction, and 2 under
  # `(d8,An,Xi*SF)` in both. Every cell but the indexed one is 1.
  #
  # This return was 6 while the target was an MCF5307, where the same cells
  # read 3 and 4. The V4 pipeline is why it is 1 now.
  1'u32

proc execAddSubA(ctx: MCF5307Ctx; d: Decoded; isSub: bool): uint32 =
  ## ADDA.L and SUBA.L. They touch no condition code: an address computation
  ## must not disturb the flags a following conditional branch reads.
  if d.size != 4'u8:
    return trap(ctx)
  if not eaIsLegalFor(d.op, d.ea):
    return trap(ctx)
  let src = eaRead(ctx, d.ea, 4)
  if ctx.halted: return 0'u32
  let dst = regA(ctx, d.destReg)
  setRegA(ctx, d.destReg, if isSub: dst - src else: dst + src)
  # `adda.l`/`suba.l` HAVE NO ROW - see the header - so this number is this
  # core's own and no cell backs it. It was 4; it is 1 because every
  # arithmetic row Table 2-15 does carry reads 1 for the register and memory
  # forms, and an ADDA that cost four times an ADD would be an outlier the
  # manual gives no reason for. Still a choice, not a measurement.
  1'u32

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
  # MCF5407 User's Manual Table 2-15, folio 2-27, `addi.l`/`subi.l #imm,Dx`: the single
  # cell 1(0/0). Was 6.
  1'u32

proc execAddSubQ(ctx: MCF5307Ctx; d: Decoded; isSub: bool): uint32 =
  ## ADDQ.L and SUBQ.L. An address register destination sets no condition
  ## code, exactly as ADDA does; every other destination sets them all.
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
  # MCF5407 User's Manual Table 2-15, folio 2-27, `addq.l`/`subq.l #imm,<ea>`: 1(0/0)
  # under `Rn`, 1(1/1) under the memory modes and `xxx.wl`, 2(1/1) under
  # `(d8,An,Xi*SF)`. Was 4.
  1'u32

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
  # MCF5407 User's Manual Table 2-15, folio 2-27, `addx.l`/`subx.l Dy,Dx`: the single
  # cell 1(0/0). Was 4.
  1'u32

# ---------------------------------------------------------------------------
# NEG, NEGX and CLR.

proc execNeg(ctx: MCF5307Ctx; d: Decoded; extended: bool): uint32 =
  ## NEG.L and NEGX.L: `0 - Dn` and `0 - Dn - X`. C is set whenever a borrow
  ## left the word, which for NEG is exactly "the operand was not zero".
  if d.size != 4'u8:
    return trap(ctx)
  if not eaIsLegalFor(d.op, d.ea):
    return trap(ctx)
  let src = regD(ctx, d.ea.reg)
  let x = if extended: xBit(ctx) else: 0'u32
  let (res, borrow) = subWithBorrow(0'u32, src, x)
  setRegD(ctx, d.ea.reg, res)
  setSubCc(ctx, src, 0'u32, res, borrow, extended)
  # MCF5407 User's Manual Table 2-14, folio 2-27, `neg.l Dx` and `negx.l Dx`: the
  # single cell 1(0/0) each. Was 4.
  1'u32

proc execClr(ctx: MCF5307Ctx; d: Decoded): uint32 =
  ## CLR.B/.W/.L. N, V and C take fixed values, Z is always set, and X is
  ## untouched - a clear is not an arithmetic result and must not disturb a
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
  # MCF5407 User's Manual Table 2-14, folio 2-27, `clr.b`/`clr.w`/`clr.l <ea>`: 1(0/0)
  # under `Rn`, 1(0/1) under the memory modes and `xxx.wl`, 2(0/1) under
  # `(d8,An,Xi*SF)`. All three sizes read alike. Was 4.
  1'u32

# ---------------------------------------------------------------------------
# EXT and EXTB.

proc execExt(ctx: MCF5307Ctx; d: Decoded; fromByte: bool): uint32 =
  ## EXT.W (byte into word), EXT.L (word into long) and EXTB.L (byte into
  ## long). EXT.W writes the low word alone and the upper half of the
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
  # MCF5407 User's Manual Table 2-14, folio 2-27, `ext.w`, `ext.l` and `extb.l`, all
  # `Dx`: the single cell 1(0/0) each. Was 4.
  1'u32

# ---------------------------------------------------------------------------
# MULU.L, MULS.L, DIVU.L, DIVS.L and REMx.L.
#
# Both families carry the 68020 two-word encoding. The second word follows the
# opcode word and precedes the effective address's own extension words, so it
# is fetched first.

const
  mulDivSignedBit = 0x0800'u16   ## bit 11: MULS/DIVS rather than MULU/DIVU
  mulDivWideBit = 0x0400'u16     ## bit 10: the 68020 64-bit form

proc execMulWord(ctx: MCF5307Ctx; d: Decoded): uint32 =
  ## MULU.W and MULS.W: `16 x 16 -> 32`, one instruction word, no extension.
  ##
  ## CFPRM folios 4-55 (MULS) and 4-57 (MULU), word form: "the multiplier and
  ## multiplicand are both word operands, and the result is a longword
  ## operand. A register operand is the low-order word; the upper word of the
  ## register is ignored. All 32 bits of the product are saved in the
  ## destination data register."
  let src = eaRead(ctx, d.ea, 2)
  if ctx.halted: return 0'u32
  let dst = regD(ctx, d.destReg)
  # Both operands are narrowed to 16 bits before the multiply. `eaRead`
  # returns the whole register for a `Dn` operand and leaves the narrowing to
  # the caller - `machine.nim` says so at its declaration - and the
  # destination is read with `regD`, which does no narrowing either. Without
  # both masks a data-register source would multiply 32 bits by 16.
  let srcW = uint16(src and 0xFFFF'u32)
  let dstW = uint16(dst and 0xFFFF'u32)
  # The signed bit is observable in this form, unlike the long one below. A
  # 16x16 product is kept whole in 32 bits, so the sign extension of the two
  # word operands reaches the result; the long form keeps only the low 32 bits
  # of a 32x32 product, where it cannot. `0xFFFF * 3` is `0x0002FFFD` unsigned
  # and `0xFFFFFFFD` signed.
  let res =
    if d.op == opMuls:
      cast[uint32](int32(cast[int16](srcW)) * int32(cast[int16](dstW)))
    else:
      uint32(srcW) * uint32(dstW)
  setRegD(ctx, d.destReg, res)
  # V and C are cleared and N and Z come from all 32 bits, which is the same
  # rule the long form uses and for the same reason: folios 4-55 and 4-57
  # print ONE condition-code table each, above the WORD instruction format,
  # and neither continuation page (4-56, 4-58) carries a second. The word
  # table therefore governs both sizes.
  setNzClearVc(ctx, res, 4)
  # MCF5407 User's Manual Table 2-15, "Two Operand Instruction Execution
  # Times", folio 2-27, `muls.w`/`mulu.w <ea>,Dx`: `3(0/0)` under `Rn` and
  # under `#xxx`, `3(1/0)` for the four memory modes and for `xxx.wl`, and
  # `4(1/0)` for `(d8,An,Xi*SF)`. This flat 3 is therefore every cell of the
  # row except the indexed one.
  #
  # It was a worse fit on the MCF5307, whose Table 3-13 read `6(1/0)` for the
  # memory modes and `7(1/0)` indexed - the V4 pipeline is what closed the gap,
  # not a change here. The number did not move; the part underneath it did.
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
  # V is always cleared, and that is the CFPRM's own word rather than an
  # inference. Folio 4-55 for MULS and folio 4-57 for MULU each give V "Always
  # cleared" in the condition-code table and each add the sentence "Note that
  # CCR[V] is always cleared by MULS/MULU, unlike the 68K family processors".
  # Neither folio's longword page (4-56, 4-58) carries a condition-code table
  # of its own, so the word-form table governs this 32-bit form too. C is
  # "Always cleared" on both, N comes from bit 31 of the 32 bits written - for
  # MULU that is bit 31 of the unsigned product, so it is not always zero - and
  # Z from those same 32 bits. `setNzClearVc` is exactly that rule. Setting V
  # when the 32 bits written are not the whole product is the 68K rule, and the
  # CFPRM note above singles it out as not this part's.
  #
  # The signed bit selects nothing in this form, and the multiply is written
  # once because of it. A 32x32 product's low 32 bits are the same under both
  # readings - multiplication modulo 2^32 does not depend on how the operands'
  # sign bits are interpreted - and every flag above comes from those 32 bits.
  # `mulDivSignedBit` is still the decoder's business and still separates the
  # divide forms below, where the quotient genuinely differs.
  let res = uint32((uint64(dst) * uint64(src)) and 0xFFFFFFFF'u64)
  setRegD(ctx, dl, res)
  setNzClearVc(ctx, res, 4)
  # `muls.l`/`mulu.l <ea>,Dx` reads `5(0/0)` under `Rn` and `5(1/0)` under the
  # four memory modes, MCF5407 User's Manual Table 2-15, folio 2-27, and dashes
  # `(d8,An,Xi*SF)`, `xxx.wl` and `#<xxx>`. Every cell the row defines is 5, so
  # 5 is the whole row and not a flattening of it.
  #
  # This return was 10 while the target was an MCF5307, whose Table 3-13 read
  # `5(0/0)` and `8(1/0)` - two different numbers, so no single return matched
  # and 10 matched neither of them. The V4 row is uniform and the return can
  # now be exact.
  5'u32

const divWordCycles = 20'u32
  ## MCF5407 User's Manual Table 2-15, "Two Operand Instruction Execution
  ## Times", folio 2-27, `divs.w`/`divu.w <ea>,Dx`: `20(0/0)` under `Rn` and
  ## under `#xxx`, `20(1/0)` for the four memory modes and for `xxx.wl`, and
  ## `21(1/0)` for `(d8,An,Xi*SF)`. This constant is therefore every cell of
  ## the row except the indexed one.
  ##
  ## The MCF5307's Table 3-13 read `23(1/0)` for the memory modes and `24(1/0)`
  ## indexed, so 20 named one cell there and names six here. The constant did
  ## not move; the part underneath it did.

proc execDivWord(ctx: MCF5307Ctx; d: Decoded): uint32 =
  ## DIVU.W and DIVS.W: a 32-bit dividend in Dx over a 16-bit source, with
  ## both halves of the answer packed into Dx.
  ##
  ## CFPRM folios 4-31 (DIVS) and 4-33 (DIVU): "For a word-sized operation,
  ## the destination operand is a longword and the source is a word; the
  ## 16-bit quotient is in the lower word and the 16-bit remainder is in the
  ## upper word of the destination. Note that the sign of the remainder is the
  ## same as the sign of the dividend."
  let src = eaRead(ctx, d.ea, 2)
  if ctx.halted: return 0'u32
  # The divisor is the low word and the mask is load-bearing. `eaRead` hands
  # back the whole register for a `Dn` source, so without it a source of
  # `0x00010000` would divide by 65536 instead of trapping on a zero divisor.
  let divisor = uint16(src and 0xFFFF'u32)
  if divisor == 0'u16:
    # A divide by zero is exception vector 5 at vector offset 0x014, of class
    # Fault - CFPRM Table 11-1, "Exception Vector Assignments", folio 11-2,
    # whose footnote adds "if the divide unit is not present (5202, 5204,
    # 5206), vector 5 is reserved". Folios 4-31 and 4-33 add that no registers
    # are affected and that the stack frame points at the offending opcode.
    #
    # This halts with `fault` instead - the channel the long form already uses
    # and the one every illegal operand in this module uses. The vector is
    # recorded here so that it need not be re-derived.
    return trap(ctx)
  let dividend = regD(ctx, d.destReg)
  var quotient: uint32
  var remainder: uint32
  var overflowed: bool
  if d.op == opDivs:
    let a = int64(cast[int32](dividend))
    let b = int64(cast[int16](divisor))
    # Nim's `div` truncates toward zero and `mod` takes the sign of the
    # dividend, which is exactly the pair the folios describe: 17 / -3 is -5
    # with remainder +2, and -17 / 3 is -5 with remainder -2. A flooring
    # division gives -6 and +1 for the second and fails both halves.
    let q = a div b
    # The overflow boundary at exactly -32768 is the one inference in this
    # path, and this comparison is what decides it.
    #
    # The folios say "An overflow occurs if the quotient is larger than a
    # 16-bit (.W) or 32-bit (.L) signed integer" and do not define "larger"
    # for the asymmetric end of the range. -32768 is a 16-bit signed integer -
    # it is the smallest one - so under the reading taken here it does not
    # overflow, and the range test below is the plain two-sided one. The other
    # available reading is that "larger" means larger in magnitude than the
    # largest positive value, under which -32768 would overflow.
    #
    # Nothing in the CFPRM settles it and no oracle available here does
    # either: `m68k-elf-as` decides what assembles, not what a quotient does
    # at run time, and Table 2-15 times the instruction without saying what it
    # computes. What would settle it is a run on silicon or on a hardware
    # model - `divs.w` with a dividend of -65536 and a divisor of 2, reading V
    # afterwards - or an erratum or a later revision of the folio that states
    # the boundary. Until then this is a READING and not a measurement.
    if q < -32768'i64 or q > 32767'i64:
      overflowed = true
    else:
      quotient = uint32(cast[uint64](q) and 0xFFFF'u64)
      remainder = uint32(cast[uint64](a mod b) and 0xFFFF'u64)
  else:
    let q = dividend div uint32(divisor)
    # The unsigned boundary is not ambiguous: the folio says "larger than a
    # 16-bit (.W) ... unsigned integer" and 0xFFFF is that integer.
    if q > 0xFFFF'u32:
      overflowed = true
    else:
      quotient = q
      remainder = dividend mod uint32(divisor)
  if overflowed:
    # The destination is unaffected - "If overflow is detected, the
    # destination register is unaffected" - and the status word is fully
    # determined: V set, C cleared ("Always cleared"), N and Z cleared
    # ("Cleared if overflow is detected"), X untouched ("Not affected"). This
    # is the same rule and the same line the long form uses below.
    ctx.sr = (ctx.sr and not (ccrC or ccrN or ccrZ)) or ccrV
    return divWordCycles
  setRegD(ctx, d.destReg, (remainder shl 16) or quotient)
  # N and Z come from the quotient and the size is 2, not from the longword
  # written. The folios read "N ... set if the quotient is negative" and
  # "Z ... set if the quotient is zero", and the quotient is 16 bits wide
  # here, so N is bit 15 of it. A core taking N from bit 31 of the register it
  # just wrote would report the remainder's sign; `-17 / -5` is quotient +3
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
    # A divide by zero is exception vector 5 on silicon. Halting with `fault`
    # is the channel every other illegal operand already uses.
    return trap(ctx)
  let dividend = regD(ctx, dq)
  if signed and dividend == 0x80000000'u32 and src == 0xFFFFFFFF'u32:
    # The one signed division overflow. The most negative value has no
    # positive counterpart, so the quotient does not exist. The operands are
    # unchanged and the status word is fully determined: V set, C cleared, and
    # N and Z cleared. CFPRM folios 4-31 and 4-33 (DIVS, DIVU) and 4-70 and
    # 4-71 (REMS, REMU) all read "N Cleared if overflow is detected;
    # otherwise ..." and "Z Cleared if overflow is detected; otherwise ...",
    # with "V Set if an overflow occurs" and "C Always cleared". X is "Not
    # affected" and is the one bit that survives.
    ctx.sr = (ctx.sr and not (ccrC or ccrN or ccrZ)) or ccrV
    # The same cost as a divide that produced a quotient: the manual gives the
    # row one number and does not time the overflow separately. See the return
    # at the end of this procedure for the cell.
    return 35'u32
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
  # ColdFire's REMx.L produces the remainder only. An unequal register pair
  # is `REMU.L`/`REMS.L` here and `DIVUL`/`DIVSL` on the 68020, and the
  # 68020 instruction also writes the quotient into Dq. Writing Dq here
  # would corrupt the dividend a following instruction still reads.
  setRegD(ctx, (if dr == dq: dq else: dr), written)
  # N and Z come from the quotient even when the remainder is what was
  # written. CFPRM folios 4-70 and 4-71 give REMS and REMU "N ... set if the
  # quotient is negative, cleared if positive" and "Z ... set if the quotient
  # is zero, cleared if nonzero", though the operation line of each is
  # "Destination/Source -> Remainder". So the flags and the destination come
  # from DIFFERENT NUMBERS, and `quotient` is computed above for the REMx
  # forms purely to feed this line.
  setNzClearVc(ctx, quotient, 4)
  # `divs.l`/`divu.l <ea>,Dx` reads `35(0/0)` under `Rn` and `35(1/0)` under
  # the four memory modes, MCF5407 User's Manual Table 2-15, folio 2-27, and
  # dashes the rest. Every cell the row defines is 35, so 35 is the whole row.
  # The overflow path above returns it too.
  35'u32

# ---------------------------------------------------------------------------
# The dispatch entry `step` calls.

proc aluFamily*(ctx: MCF5307Ctx; word: uint16; d: Decoded): uint32 =
  ## Execute one integer-arithmetic instruction. Called from `step` in
  ## `mcf5307/cpu` with the opcode word and the decoded operation. Returns a
  ## placeholder cycle count excluding the fetch - see the cycle block in
  ## `cpu.nim` - and halts the context with `fault` set on an illegal size, an
  ## illegal effective address or a divide by zero.
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
