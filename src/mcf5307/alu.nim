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
    setRegD(ctx, d.ea.reg, (src and 0xFFFF0000'u32) or (widened and 0xFFFF'u32))
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

proc execMul(ctx: MCF5307Ctx; d: Decoded): uint32 =
  if not eaIsLegalFor(opMulu, d.ea):
    return trap(ctx)
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
  var res: uint32
  var overflow: bool
  if (ext and mulDivSignedBit) != 0'u16:
    let product = int64(cast[int32](dst)) * int64(cast[int32](src))
    res = uint32(cast[uint64](product) and 0xFFFFFFFF'u64)
    overflow = product < int64(low(int32)) or product > int64(high(int32))
  else:
    let product = uint64(dst) * uint64(src)
    res = uint32(product and 0xFFFFFFFF'u64)
    overflow = product > 0xFFFFFFFF'u64
  setRegD(ctx, dl, res)
  setNzClearVc(ctx, res, 4)
  # V REPORTS THAT THE 32 BITS WRITTEN ARE NOT THE WHOLE PRODUCT. Without it
  # a product whose low half is zero is indistinguishable from a multiply by
  # zero.
  if overflow:
    ctx.sr = ctx.sr or ccrV
  10'u32

proc execDiv(ctx: MCF5307Ctx; d: Decoded): uint32 =
  if not eaIsLegalFor(opDivu, d.ea):
    return trap(ctx)
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
    # positive counterpart, so the quotient does not exist. V is set, C is
    # cleared and THE OPERANDS ARE UNCHANGED. The manual leaves N and Z
    # undefined here; this core leaves them as it found them, which is the
    # one choice a reader can predict.
    ctx.sr = (ctx.sr and not ccrC) or ccrV
    return 10'u32
  var written: uint32
  if signed:
    let a = int64(cast[int32](dividend))
    let b = int64(cast[int32](src))
    # Nim's `div` truncates toward zero and `mod` takes the sign of the
    # dividend, which is what the silicon does: 17 / -3 is -5 and not -6,
    # and -17 rem 5 is -2 and not +3.
    written = if dr == dq: uint32(cast[uint64](a div b) and 0xFFFFFFFF'u64)
              else: uint32(cast[uint64](a mod b) and 0xFFFFFFFF'u64)
  else:
    written = if dr == dq: dividend div src else: dividend mod src
  # COLDFIRE'S REMx.L PRODUCES THE REMAINDER ONLY. An unequal register pair
  # is `REMU.L`/`REMS.L` here and `DIVUL`/`DIVSL` on the 68020, and the
  # 68020 instruction also writes the quotient into Dq. Writing Dq here
  # would corrupt the dividend a following instruction still reads.
  setRegD(ctx, (if dr == dq: dq else: dr), written)
  setNzClearVc(ctx, written, 4)
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
