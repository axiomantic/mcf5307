## `machine` - the machine substrate every instruction group executes against.
##
## Given a context, this module reads and writes the machine's state. The
## register file, the condition-code bits, the board accesses, the
## instruction-stream extension words and the effective-address evaluation are
## all "how the machine is touched". What each opcode means is the job of the
## instruction-group modules, and none of that is here.
##
## The helpers live here rather than in one executor because a second executor
## needs the same register file, the same board accesses and the same
## effective-address evaluation. `alu.nim` importing `move.nim` for them would
## put an executor under another executor. The helpers are pure functions over
## the shared types, so they belong beside those types, not beside one caller.
##
## This module sits at the `decode_types` level. It reads the shared types and
## it names no executor and no decoder:
##
##     ea
##      ^
##     decode_types            the shared types and the EA legality table
##      ^        ^
##     machine   |             this module: the state, and how to touch it
##      ^  ^     |
##      |  |   decode          the instruction word -> Operation + EA
##      |  |     ^
##     move alu  |             the instruction semantics, one module per group
##      ^   ^    ^
##          cpu               `step`, the dispatch, and the lifecycle ABI
##
## `decode` does not import this module and must not: a decoder that reaches
## machine state inverts the layering.
##
## Register numbering, the condition-code bit positions and addressing-mode
## behaviour are taken from the ColdFire Family Programmer's Reference Manual
## and the MCF5307 User's Manual, and from this project's own measurements.

import mcf5307/decode_types
import mcf5307/ea

# ---------------------------------------------------------------------------
# The register file.
#
# d0..d7 live in `ctx.dRegs`, a0..a6 in `ctx.aRegs`, and a7 is `ctx.sp`.
# `regFileGet`/`regFileSet` are the single-index view the ABI accessors and
# the MOVEM mask use: 0..7 = d0..d7, 8..15 = a0..a7, 16 = sr, 17 = pc.

proc regD*(ctx: MCF5307Ctx; n: uint8): uint32 =
  ctx.dRegs[n and 7]

proc regA*(ctx: MCF5307Ctx; n: uint8): uint32 =
  let k = n and 7
  if k == 7: ctx.sp else: ctx.aRegs[k]

proc setRegD*(ctx: MCF5307Ctx; n: uint8; v: uint32) =
  ctx.dRegs[n and 7] = v

proc setRegA*(ctx: MCF5307Ctx; n: uint8; v: uint32) =
  let k = n and 7
  if k == 7: ctx.sp = v else: ctx.aRegs[k] = v

proc regFileGet*(ctx: MCF5307Ctx; index: int): uint32 =
  if index in 0 .. 7:
    ctx.dRegs[index]
  elif index in 8 .. 14:
    ctx.aRegs[index - 8]
  elif index == 15:
    ctx.sp
  elif index == 16:
    ctx.sr
  elif index == 17:
    ctx.pc
  else:
    0

proc regFileSet*(ctx: MCF5307Ctx; index: int; v: uint32): bool =
  if index in 0 .. 7:
    ctx.dRegs[index] = v
    true
  elif index in 8 .. 14:
    ctx.aRegs[index - 8] = v
    true
  elif index == 15:
    ctx.sp = v
    true
  elif index == 16:
    ctx.sr = v and 0xFFFF'u32
    true
  else:
    false

# ---------------------------------------------------------------------------
# The condition-code bits of the status register. ColdFire keeps the 68k CCR
# in bits 0..4: C at 0, V at 1, Z at 2, N at 3, X at 4.

const
  ccrC* = 0x0001'u32
  ccrV* = 0x0002'u32
  ccrZ* = 0x0004'u32
  ccrN* = 0x0008'u32
  ccrX* = 0x0010'u32

proc sizeMask*(size: uint8): uint32 =
  if size == 4: 0xFFFF_FFFF'u32
  else: (1'u32 shl (8 * size)) - 1'u32

proc mergeSized*(old: uint32; value: uint32; size: uint8): uint32 =
  ## A sized write to a register replaces the low `size` bytes and nothing
  ## else. `MOVE.B` and `MOVE.W` into `Dn` leave the rest of `Dn` untouched,
  ## and so do `CLR.B`, `CLR.W` and the low half of `EXT.W`. A size of 4 masks
  ## to all ones and this reduces to the value, which is why the long forms
  ## need no case of their own.
  ##
  ## There is one copy of this rule and every sized register write goes through
  ## it. `move.b %d0,%d1` with d1 = 0x12345678 and d0 = 0xAA gives 0x123456AA,
  ## not 0x000000AA.
  (old and not sizeMask(size)) or (value and sizeMask(size))

proc setNzClearVc*(ctx: MCF5307Ctx; value: uint32; size: uint8) =
  ## N and Z from the result, V and C cleared, X unchanged. This is the rule
  ## MOVE, MOVEQ, EXT, EXTB and the ColdFire 32-bit multiply share; the
  ## instructions that also compute a carry or an overflow set those bits
  ## themselves in their own group's module.
  ctx.sr = ctx.sr and not (ccrN or ccrZ or ccrV or ccrC)
  let msb = 8 * size - 1
  if ((value shr msb) and 1'u32) != 0'u32:
    ctx.sr = ctx.sr or ccrN
  if (value and sizeMask(size)) == 0'u32:
    ctx.sr = ctx.sr or ccrZ

# ---------------------------------------------------------------------------
# Board access, extension words, and the effective-address evaluators.
#
# A bus fault anywhere in an operand access halts the context with `fault`
# set; the callers check `ctx.halted` after each step and unwind.

proc readMem*(ctx: MCF5307Ctx; address: uint32; size: uint8): uint32 =
  var st = Mcf5307BusStatus.busOk
  result = ctx.readFn(ctx.user, address, cint(size), addr st)
  if st != Mcf5307BusStatus.busOk:
    ctx.fault = true
    ctx.halted = true

proc writeMem*(ctx: MCF5307Ctx; address: uint32; size: uint8; value: uint32) =
  var st = Mcf5307BusStatus.busOk
  ctx.writeFn(ctx.user, address, cint(size), value and sizeMask(size), addr st)
  if st != Mcf5307BusStatus.busOk:
    ctx.fault = true
    ctx.halted = true

proc fetchExt*(ctx: MCF5307Ctx): uint16 =
  ## Read one extension word from the instruction stream and advance the pc
  ## past it. The pc-relative base of a PC mode is the pc AFTER its last
  ## extension word, which is exactly where the next instruction begins.
  var st = Mcf5307BusStatus.busOk
  let v = ctx.readFn(ctx.user, ctx.pc, 2, addr st)
  if st != Mcf5307BusStatus.busOk:
    ctx.fault = true
    ctx.halted = true
    return 0'u16
  ctx.pc = ctx.pc + 2'u32
  uint16(v and 0xFFFF'u32)

# Sign extension of a displacement or an immediate value.
#
# The casts are correct and a conversion is not. Sign extension reinterprets
# the bits of an unsigned value as a two's-complement signed value of the same
# width. It does not narrow the value, so there is no range to check. A
# conversion `int16(x)` is a checked narrowing conversion: the library is
# built with `--panics:on -d:release`, thus every `x` from 0x8000 to 0xFFFF -
# that is, every negative displacement - ends the process with a `RangeDefect`
# that no caller can catch. `cast` keeps the bit pattern and gives the signed
# value the silicon uses. The widening to `int32` that follows is safe: each
# `int32` holds all the values of an `int16` and of an `int8`.

func s16*(x: uint16): int32 =
  int32(cast[int16](x))

func s8*(x: uint16): int32 =
  int32(cast[int8](uint8(x and 0xFF'u16)))

proc indexOperand*(ctx: MCF5307Ctx; ext: uint16): uint32 =
  ## The scaled index operand of an indexed extension word. Bit 15 selects
  ## Dn(0) or An(1), bits 14..12 the index register, bits 10..9 the scale
  ## (1, 2, 4, 8), bit 8 word(0) or long(1) index, bits 7..0 the signed d8.
  let isAn = (ext and 0x8000'u16) != 0'u16
  let n = (ext shr 12) and 0x7'u16
  let scale = (ext shr 9) and 0x3'u16
  let longIndex = (ext and 0x0100'u16) != 0'u16
  var v = if isAn: regA(ctx, uint8(n)) else: regD(ctx, uint8(n))
  if not longIndex:
    v = uint32(s16(uint16(v and 0xFFFF'u32)))
  v shl scale

proc eaAddr*(ctx: MCF5307Ctx; ea: EA; size: uint8): uint32 =
  ## The effective address of a memory-addressing mode. Register and
  ## immediate modes have no address; a caller that asks for one gets 0.
  case ea.mode
  of eaAnInd:
    result = regA(ctx, ea.reg)
  of eaAnPost:
    result = regA(ctx, ea.reg)
    setRegA(ctx, ea.reg, result + uint32(size))
  of eaAnPre:
    result = regA(ctx, ea.reg) - uint32(size)
    setRegA(ctx, ea.reg, result)
  of eaAnDisp:
    result = regA(ctx, ea.reg) + uint32(s16(fetchExt(ctx)))
  of eaAnIndex:
    let ext = fetchExt(ctx)
    result = regA(ctx, ea.reg) + uint32(s8(ext)) + indexOperand(ctx, ext)
  of eaMode7:
    case EA7(ea.reg)
    of ea7AbsW:
      result = uint32(s16(fetchExt(ctx)))
    of ea7AbsL:
      # The first extension word is the high half. ColdFire Family
      # Programmer's Reference Manual, Rev. 3, section 2.2.11 and Figure 2-13:
      # "The first extension word contains the high-order part of the address;
      # the second contains the low-order part." The two `fetchExt` calls are
      # ordered, so naming them the other way round assembles the address
      # word-swapped and every `(xxx).L` operand reads the wrong place.
      let hi = fetchExt(ctx)
      let lo = fetchExt(ctx)
      result = (uint32(hi) shl 16) or uint32(lo)
    of ea7PCDisp:
      let d = s16(fetchExt(ctx))
      result = ctx.pc + uint32(d)
    of ea7PCIndex:
      let ext = fetchExt(ctx)
      result = ctx.pc + uint32(s8(ext)) + indexOperand(ctx, ext)
    else:
      # ea7Unused5 / ea7Invalid / ea7Unused7: reserved, never a legal EA.
      ctx.fault = true
      ctx.halted = true
      result = 0
  else:
    discard

proc eaRead*(ctx: MCF5307Ctx; ea: EA; size: uint8): uint32 =
  ## Read the operand of an effective address. Immediate mode reads its
  ## extension words; register modes read the register (low bits used by the
  ## caller's size); memory modes read through the board.
  case ea.mode
  of eaDn:
    result = regD(ctx, ea.reg)
  of eaAn:
    result = regA(ctx, ea.reg)
  of eaAnInd, eaAnPost, eaAnPre, eaAnDisp, eaAnIndex:
    result = readMem(ctx, eaAddr(ctx, ea, size), size)
  of eaMode7:
    case EA7(ea.reg)
    of ea7AbsW, ea7AbsL, ea7PCDisp, ea7PCIndex:
      result = readMem(ctx, eaAddr(ctx, ea, size), size)
    of ea7Imm:
      if size == 4:
        let hi = fetchExt(ctx)
        let lo = fetchExt(ctx)
        result = (uint32(hi) shl 16) or uint32(lo)
      else:
        result = uint32(fetchExt(ctx))
    else:
      ctx.fault = true
      ctx.halted = true
      result = 0

proc eaWrite*(ctx: MCF5307Ctx; ea: EA; size: uint8; value: uint32) =
  ## Write the operand of an alterable effective address. A Dn write replaces
  ## the low `size` bytes and keeps the rest of the register; memory modes write
  ## through the board; PC-relative and immediate mode-7 sub-variants are not
  ## alterable and trap.
  case ea.mode
  of eaDn:
    setRegD(ctx, ea.reg, mergeSized(regD(ctx, ea.reg), value, size))
  of eaAn:
    setRegA(ctx, ea.reg, value)
  of eaAnInd, eaAnPost, eaAnPre, eaAnDisp, eaAnIndex:
    writeMem(ctx, eaAddr(ctx, ea, size), size, value)
  of eaMode7:
    case EA7(ea.reg)
    of ea7AbsW, ea7AbsL:
      writeMem(ctx, eaAddr(ctx, ea, size), size, value)
    else:
      ctx.fault = true
      ctx.halted = true
  else:
    discard

# ---------------------------------------------------------------------------
# A destination resolved once.
#
# `eaRead` followed by `eaWrite` on the same operand evaluates the effective
# address twice. For (An)+ and -(An) that applies the adjustment twice and
# writes to the wrong address, and for (d16,An) and the absolute modes it
# consumes the extension words twice and desynchronises the program counter
# from the instruction stream. Every read-modify-write instruction therefore
# resolves the destination once and reads and writes through the resolved
# reference.
#
# MOVE writes its destination and never reads it, so `move.nim` needs none of
# this.

type
  EaRefKind* = enum
    erNone   ## not a usable operand; the context is already halted
    erDn     ## a data register
    erAn     ## an address register
    erMem    ## a memory address, already adjusted and with its extension
             ## words already consumed

  EaRef* = object
    kind*: EaRefKind
    reg*: uint8
    address*: uint32

proc eaResolve*(ctx: MCF5307Ctx; ea: EA; size: uint8): EaRef =
  ## Evaluate an effective address exactly once and return a reference that
  ## `eaRefRead` and `eaRefWrite` reuse. An immediate, a PC-relative operand
  ## or a reserved mode-7 encoding cannot be a destination; each halts the
  ## context with `fault`.
  case ea.mode
  of eaDn:
    EaRef(kind: erDn, reg: ea.reg)
  of eaAn:
    EaRef(kind: erAn, reg: ea.reg)
  of eaAnInd, eaAnPost, eaAnPre, eaAnDisp, eaAnIndex:
    EaRef(kind: erMem, address: eaAddr(ctx, ea, size))
  of eaMode7:
    case EA7(ea.reg)
    of ea7AbsW, ea7AbsL:
      EaRef(kind: erMem, address: eaAddr(ctx, ea, size))
    else:
      ctx.fault = true
      ctx.halted = true
      EaRef(kind: erNone)

proc eaRefRead*(ctx: MCF5307Ctx; r: EaRef; size: uint8): uint32 =
  case r.kind
  of erDn: regD(ctx, r.reg)
  of erAn: regA(ctx, r.reg)
  of erMem: readMem(ctx, r.address, size)
  of erNone: 0'u32

proc eaRefWrite*(ctx: MCF5307Ctx; r: EaRef; size: uint8; value: uint32) =
  case r.kind
  of erDn: setRegD(ctx, r.reg, mergeSized(regD(ctx, r.reg), value, size))
  of erAn: setRegA(ctx, r.reg, value)
  of erMem: writeMem(ctx, r.address, size, value)
  of erNone: discard

# ---------------------------------------------------------------------------
# The register access the conformance harness needs. The C ABI in
# `include/mcf5307.h` declares these. `index` 0..7 is d0..d7, 8..14 is a0..a6,
# 15 is a7 (the single stack pointer), 16 is the status register, and 17 is
# the program counter (read-only through this call).

proc mcf5307_set_reg*(ctx: MCF5307Ctx; index: cint; value: uint32): cint
    {.exportc: "mcf5307_set_reg", cdecl, dynlib.} =
  if ctx.isNil or index < 0 or index > 16:
    return cast[cint](0)
  if regFileSet(ctx, int(index), value):
    return cast[cint](1)
  cast[cint](0)

proc mcf5307_get_reg*(ctx: MCF5307Ctx; index: cint): uint32
    {.exportc: "mcf5307_get_reg", cdecl, dynlib.} =
  if ctx.isNil or index < 0 or index > 17:
    return 0'u32
  regFileGet(ctx, int(index))

# ---------------------------------------------------------------------------
# The run state the conformance harness needs.
#
# They are two calls and not one, because `halted` and `fault` are two bits.
# `cpu.nim`'s `step` sets `halted` alone for a valid opcode with no executor
# yet, and it sets both for a bus error, an illegal instruction word, an
# illegal effective address, an illegal size or a divide by zero. Folding them
# into one call would make "this instruction trapped" and "this instruction is
# not written yet" the same answer, and the conformance runner has to separate
# exactly those two.
#
# They report and they do not clear. `mcf5307_reset` is what clears both bits,
# so a reader may ask twice and get the same answer. A nil context answers 0
# to both: a caller with no context has no halted core and no faulted one.

proc mcf5307_halted*(ctx: MCF5307Ctx): cint
    {.exportc: "mcf5307_halted", cdecl, dynlib.} =
  if ctx.isNil or not ctx.halted:
    return cast[cint](0)
  cast[cint](1)

proc mcf5307_faulted*(ctx: MCF5307Ctx): cint
    {.exportc: "mcf5307_faulted", cdecl, dynlib.} =
  if ctx.isNil or not ctx.fault:
    return cast[cint](0)
  cast[cint](1)
