## `machine` - the machine substrate every instruction group executes against.
##
## Given a context, this module reads and writes the machine's state. The
## register file, the condition-code bits, the board accesses, the
## instruction-stream extension words and the effective-address evaluation are
## all "how the machine is touched". What each opcode means is the job of the
## instruction-group modules, and none of that is here.
##
## `alu.nim` importing `move.nim` for the shared helpers would put an executor
## under another executor, which is the same shape as the decoder-under-executor
## cycle. The helpers are pure functions over the shared types, so they live
## beside those types and not beside one caller.
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

import mcf5307/bus
import mcf5307/decode_types
import mcf5307/ea
import mcf5307/exception

# ---------------------------------------------------------------------------
# The register file.
#
# d0..d7 live in `ctx.dRegs`, a0..a6 in `ctx.aRegs`, and a7 is `ctx.sp`.
# `regFileGet`/`regFileSet` are the single-index view the ABI accessors and
# the MOVEM mask use: 0..7 = d0..d7, 8..15 = a0..a7, 16 = sr, 17 = pc, and
# 18 upwards the control registers - 18 = vbr, 19 = cacr, 20 = acr0,
# 21 = acr1, 22 = rambar0, 23 = rambar1, 24 = mbar.
#
# The control registers are not part of the register file. They are here
# because this index space is the only channel a host has: `MOVEC` reaches
# nothing outside a running program. The MOVEM mask never names an index above
# 15, so widening this view does not widen that instruction.
#
# 17 stays read-only through `regFileSet` and the control registers do not. The
# program counter is written by `mcf5307_reset`, which is the entry point that
# owns it.

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
  elif index == 18:
    ctx.vbr
  elif index == 19:
    ctx.cacr
  elif index == 20:
    ctx.acr0
  elif index == 21:
    ctx.acr1
  elif index == 22:
    ctx.rambar0
  elif index == 23:
    ctx.rambar1
  elif index == 24:
    ctx.mbar
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
  elif index == 18:
    ctx.vbr = v
    true
  elif index == 19:
    ctx.cacr = v
    true
  elif index == 20:
    ctx.acr0 = v
    true
  elif index == 21:
    ctx.acr1 = v
    true
  elif index == 22:
    ctx.rambar0 = v
    true
  elif index == 23:
    ctx.rambar1 = v
    true
  elif index == 24:
    ctx.mbar = v
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
  ## it.
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

# An absent callback is a refused access and not an abort. `mcf5307_create`
# (`include/mcf5307.h`) forbids no argument, so a context whose board callbacks
# are all nil is one a caller may build, and nothing here may abort the host
# process.
#
# The guard is here and not only at the head of `step` because this is where
# the call happens. `step`'s guard answers for the paths that run through
# `step`; `takeException` runs at the instruction boundary, ahead of the first
# fetch, and reaches these two procedures without passing it. A guard at each
# caller would be one guard per path and would be missing from the next path
# added.
#
# A nil callback reports the same fault a board's refusal reports, which is the
# behaviour the callers are already written for: every caller of these two
# checks `ctx.halted` and unwinds. Inventing a second failure mode would give
# each of them a second thing to check.
#
# `fetchExt` below calls `ctx.readFn` without such a guard, and it is not
# reached with a nil one. Its call sites are the effective-address evaluator in
# this module and the executor modules, and each of those runs only from
# `step`, whose first statement faults on a nil `readFn`.

proc boardRead(ctx: MCF5307Ctx; address: uint32; size: uint8;
               st: var Mcf5307BusStatus): uint32 =
  ## One board read, reporting what the board reported and deciding nothing.
  ## The callers below are the decision and they differ.
  st = Mcf5307BusStatus.busOk
  if ctx.readFn.isNil:
    ctx.fault = true
    ctx.halted = true
    return 0'u32
  ctx.readFn(ctx.user, address, cint(size), addr st)

proc boardWrite(ctx: MCF5307Ctx; address: uint32; size: uint8; value: uint32;
                st: var Mcf5307BusStatus) =
  st = Mcf5307BusStatus.busOk
  if ctx.writeFn.isNil:
    ctx.fault = true
    ctx.halted = true
    return
  ctx.writeFn(ctx.user, address, cint(size), value and sizeMask(size), addr st)

# The two layers differ in what a non-ok status means and in nothing else. On
# an executor's path it is an access fault and takes a vector; inside an
# exception entry the same status is a double fault and halts, and it must not
# recurse.
#
# The bound on the recursion is the call graph and not a flag on the context.
# `takeException` reaches the board only through `stackingRead` and
# `stackingWrite`, neither of which can re-enter it, so there is no state to
# set, to clear, or to leave set on a path that returned early.

proc stackingRead(ctx: MCF5307Ctx; address: uint32; size: uint8): uint32 =
  var st = Mcf5307BusStatus.busOk
  result = boardRead(ctx, address, size, st)
  if st != Mcf5307BusStatus.busOk:
    ctx.fault = true
    ctx.halted = true

proc stackingWrite(ctx: MCF5307Ctx; address: uint32; size: uint8;
                   value: uint32) =
  var st = Mcf5307BusStatus.busOk
  boardWrite(ctx, address, size, value, st)
  if st != Mcf5307BusStatus.busOk:
    ctx.fault = true
    ctx.halted = true

# The read path halts and does not take a vector, and an unwind blocks it
# rather than a preference. A fault must be taken before it commits any
# register or memory side effect of the faulting instruction, and `ctx.halted`
# is the only signal that unwinds a part-completed instruction: every executor
# checks it after each step. An access fault must not halt - the handler has to
# run - so a read that took a vector here would return to an executor that
# carried on with a zero operand and committed it. Measured: `move.l
# 0x1000,%d1` against a board that reports `busUnmapped` left `d1` zeroed over
# its previous value.
#
# Taking it at the instruction boundary is the fix and it is not writable from
# this module: it needs either a pending-fault field on `MCF5307Ctx`, which
# `decode_types.nim` holds, or a check after the executor returns, which
# `cpu.nim`'s `step` holds.
#
# THE WRITE PATH NEEDS NO UNWIND, WHICH IS WHY IT IS WIRED AND THE READ IS NOT.
# The rule's one named exception is the operand write, and the reason is that
# "all programming model updates associated with the write instruction are
# completed". An executor that carries on after a write fault is doing what the
# reference requires. That the only access error this part
# raises is a store to write-protected space puts the real case on this side too.

proc readMem*(ctx: MCF5307Ctx; address: uint32; size: uint8): uint32 =
  stackingRead(ctx, address, size)

proc writeMem*(ctx: MCF5307Ctx; address: uint32; size: uint8; value: uint32) =
  var st = Mcf5307BusStatus.busOk
  boardWrite(ctx, address, size, value, st)
  if st != Mcf5307BusStatus.busOk and not ctx.pendingWriteFault:
    # The first faulted store of an instruction is the one reported, and the
    # manual settles neither this nor its alternative. Section 3.5.1 says the
    # reporting is imprecise and names the NOP instruction as the way to
    # collect a write error; it says nothing about a second faulted store
    # before that collection. `movem.l` writing a register list into refused
    # space is the one instruction in this core that can raise the question.
    # The first is kept because it is the one whose captured program counter
    # and status register are nearest the fault.
    ctx.pendingWriteFault = true
    ctx.pendingFaultStatus = faultStatusFor(st, operandWrite)
    ctx.pendingStackedSr = ctx.sr and 0xFFFF'u32
    ctx.pendingStackedPc = ctx.pc

proc fetchExt*(ctx: MCF5307Ctx): uint16 =
  ## Read one extension word from the instruction stream and advance the pc
  ## past it.
  ##
  ## This procedure does not define the PC-relative base. That base is the
  ## address *of* the displacement word, which is the pc before this call, so
  ## `eaAddr` reads `ctx.pc` into a local before it calls this procedure; the
  ## citation is on the two PC arms there.
  var st = Mcf5307BusStatus.busOk
  let v = ctx.readFn(ctx.user, ctx.pc, 2, addr st)
  if st != Mcf5307BusStatus.busOk:
    ctx.fault = true
    ctx.halted = true
    return 0'u16
  ctx.pc = ctx.pc + insWordBytes
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
  ## Dn(0) or An(1), bits 14..12 the index register, bit 11 word(0) or long(1)
  ## index, bits 10..9 the scale (1, 2, 4, 8), bit 8 the brief-format marker,
  ## bits 7..0 the signed d8. Bit 8 is zero in every word the assembler emits,
  ## so a word/long select read there answers word for every legal encoding.
  ##
  ## The manual does not print the extension word's layout. There is no
  ## brief-format figure anywhere in the MCF5307 User's Manual, so the pinned
  ## assembler is the authority for the bit position: `btst %d1,(4,%pc,%d2)`
  ## assembles to `033b 2804`, whose `2804` has bit 11 set and bit 8 clear, and
  ## `m68k-elf-objdump -m m68k:5307` prints `%pc@(0x6,%d2:l)` - `:l`, a long
  ## index. Scaling corroborates the neighbouring fields: `(4,%pc,%d2*4)` is
  ## `2c04`, which moves bits 10..9 alone.
  ##
  ## The word form does not exist here.
  ## Section 3.5.2, "Address Error Exception", page 3-15: "Any attempted use of
  ## a word-sized index register (Xi.w) or a scale factor of 8 on an indexed
  ## effective addressing mode generates an address error". `m68k-elf-as
  ## -mcpu=5307` agrees and rejects `btst %d1,(4,%pc,%d2.w)`, so bit 11 is set
  ## in every encoding this core can legally be given and the narrowing branch
  ## below is unreachable from assembled code.
  ##
  ## That address error is not raised here. This procedure narrows a word
  ## index rather than faulting on one, and it applies a scale of 8 rather than
  ## faulting on that. See the uncertainty note in `eaAddr` below.
  let isAn = (ext and 0x8000'u16) != 0'u16
  let n = (ext shr 12) and 0x7'u16
  let scale = (ext shr 9) and 0x3'u16
  let longIndex = (ext and 0x0800'u16) != 0'u16
  var v = if isAn: regA(ctx, uint8(n)) else: regD(ctx, uint8(n))
  if not longIndex:
    v = uint32(s16(uint16(v and 0xFFFF'u32)))
  v shl scale

proc eaAddr*(ctx: MCF5307Ctx; ea: EA; size: uint8): uint32 =
  ## The effective address of a memory-addressing mode. Register and
  ## immediate modes have no address; a caller that asks for one gets 0.
  ##
  ## What this procedure does not know. Two things; the implementation picks a
  ## behaviour and nothing asserts it.
  ##
  ##   1. The address error of an illegal index. MCF5307 User's Manual section
  ##      3.5.2, page 3-15, says a word-sized index register or a scale factor
  ##      of 8 "generates an address error". `indexOperand` raises no such
  ##      error: it narrows the word index and it applies the scale of 8. No
  ##      case reaches either, because `m68k-elf-as -mcpu=5307` refuses to
  ##      assemble `(4,%pc,%d2.w)` and `(4,%pc,%d2*8)`, so the corpus - which
  ##      is generated through that assembler - cannot express one, and a
  ##      hand-written word would be asserting a trap this core does not have.
  ##      Raising it belongs to whoever owns the exception model.
  ##
  ##   2. THE SIGN EXTENSION OF `(xxx).W`. `ea7AbsW` sign-extends its one
  ##      extension word, so `0x8000.w` addresses `0xFFFF8000`.
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
      # THE FIRST EXTENSION WORD IS THE HIGH HALF OF THE ADDRESS. "The address
      # N of a longword data item corresponds to the address of the high order
      # word. The lower order word is located at address N + 2." The extension
      # pair is a longword in the instruction
      # stream, so the word at the lower address is the high half.
      # `m68k-elf-as -mcpu=5307` agrees: `btst %d1,0x00030004` assembles to
      # `0339 0003 0004`.
      let hi = fetchExt(ctx)
      let lo = fetchExt(ctx)
      result = (uint32(hi) shl 16) or uint32(lo)
    of ea7PCDisp:
      # The PC-relative base is the address *of* the extension word, so it is
      # taken before `fetchExt` advances the program counter past it. The
      # indexed PC mode below takes its base the same way.
      #
      # The manual does not settle this. The MCF5307 User's Manual names
      # `(d16,PC)` and `(d8,PC,Xi)` in Table 3-5 (page 3-21) and prints no
      # effective-address equation for any mode, so the authority here is the
      # pinned assembler. Measured: `btst %d1,(target,%pc)` with the opcode at
      # 0 assembles to `033a 0004` and `target` is placed at 6, and
      # `m68k-elf-objdump -m m68k:5307` prints `btst %d1,%pc@(6 <target>)`.
      # Base + 4 = 6, so the base is 2 - the address of the displacement word
      # and not the address after it.
      let base = ctx.pc
      result = base + uint32(s16(fetchExt(ctx)))
    of ea7PCIndex:
      # The base is the address of the extension word, exactly as for
      # `ea7PCDisp` above; the citation and the measurement are there.
      let base = ctx.pc
      let ext = fetchExt(ctx)
      result = base + uint32(s8(ext)) + indexOperand(ctx, ext)
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
# The exception stack frame. It is here and not in `control.nim` because the
# exception model, the bus-fault channel, interrupts and `control.nim`'s own
# format-error path all need the same frame, and `exception.nim` is a sibling
# of `control.nim`.
#
# There is no vector table object, no fault-status computation and no
# double-fault handling; this procedure is what those extend.

# `srMaster` sits with the bits `takeException` writes because a status-register
# bit position is a fact about the register and not about the exception that
# happens to clear it.
const
  srSupervisor* = 0x2000'u32   ## S, status register bit 13
  srTrace* = 0x8000'u32        ## T, status register bit 15
  srMaster* = 0x1000'u32       ## M, status register bit 12

proc exceptionFrameBase*(sp: uint32): uint32 =
  ## Where the two-longword frame goes, and it is not simply `sp - 8`.
  ##
  ## "The exception stack frame is created at a 0-modulo-4 address on the top
  ## of the current system stack". The format field encoding gives the cases: an
  ## A7 whose low two bits are 00, 01, 10 or 11 leaves the handler with A7-8,
  ## A7-9, A7-10 or A7-11, and each of those results is 0-modulo-4. That is
  ## this expression.
  (sp - 8'u32) and not 3'u32

proc exceptionFormat*(sp: uint32): uint32 =
  ## The format field of the frame the stack pointer `sp` produces: 4, 5, 6 or
  ## 7, the four rows of Table 3-2 in order. It records the misalignment the
  ## frame base removed, so that `RTE` can put it back.
  4'u32 + (sp and 3'u32)

proc takeExceptionCopiedSr*(ctx: MCF5307Ctx; vector: uint8; stackedPc: uint32;
                            fs: uint32; stackedSr: uint32) =
  ## Stack a two-longword exception frame, then load the program counter from
  ## the vector table.
  ##
  ## The status register is copied before it is changed: "the processor makes
  ## an internal copy of the SR and then enters supervisor mode by setting the
  ## S-bit and disabling trace mode by clearing the T-bit". The COPY is what
  ## reaches the frame; the modified word is what the handler runs under. The
  ## M-bit and the interrupt priority mask are changed only by an INTERRUPT
  ## exception, so nothing here touches them.
  ##
  ## The frame is two longword writes and not six bytewise pushes. It is drawn
  ## as two longwords - the format/vector word above the status register, then
  ## the program counter - and `trap #imm` costs `18(1/2)`: ONE read, the
  ## vector, and TWO writes. The instruction summary spells the same thing as
  ## `SP-4;PC`, `SP-2;SR`, `SP-2;Format`, which agrees whenever A7 was already
  ## longword aligned and does not show the self-alignment at all.
  ##
  ## The vector table is based at zero, and that is a limitation. Section 3.3,
  ## page 3-12: the handler address is "obtained by fetching a value from the
  ## table located at the address defined in the vector base register", indexed
  ## by `4 x vector_number`. This core has no VBR: the context holds no such
  ## field, and `MOVEC` - the only way to write one - is not implemented.
  ##
  ## The read below is the only reader of `ctx.vbr`. A core that stored the
  ## value and dispatched from zero would answer every read-back correctly and
  ## take every exception to the wrong handler, so the suite adjudicates on the
  ## handler address it lands on and never on the value it reads back.
  ##
  ## A fault inside this procedure is a double fault. Each access is checked
  ## and the procedure returns early, leaving the context halted with `fault`;
  ## it does not recurse. The status register has already been modified at that
  ## point, which is a state a double-fault handler will have to define.
  ctx.sr = (ctx.sr or srSupervisor) and not srTrace
  let format = exceptionFormat(ctx.sp)
  let base = exceptionFrameBase(ctx.sp)
  stackingWrite(ctx, base, 4,
                frameFirstLongword(format, fs, vector, stackedSr))
  if ctx.halted:
    return
  stackingWrite(ctx, base + 4'u32, 4, stackedPc)
  if ctx.halted:
    return
  ctx.sp = base
  let handler = stackingRead(ctx, vectorAddress(ctx.vbr, vector), 4)
  if ctx.halted:
    return
  ctx.pc = handler
  # The handler's first instruction has not run, and that is a fact about the
  # machine that outlives this call. MCF5307 User's Manual Table 3-1, closing
  # paragraph, folio 3-13: "ColdFire processors inhibit sampling for interrupts
  # during the first instruction of all exception handlers." `mcf5307_exec`
  # reads this field at its sample and clears it.
  #
  # It is written here, after the program counter: every exception this core
  # takes ends on this line, so no exception path can acquire the rule and none
  # can be forgotten by it. A flag set by `execTrap` instead would be a rule
  # about TRAP.
  #
  # A take that faulted does not set it, because each early return above is
  # ahead of this line and a machine that never reached a handler is not at
  # one.
  ctx.atHandlerEntry = true

# The `FS` argument is defaulted, and the default is the manual's answer rather
# than this module's convenience. User's Manual section 3.4, folio 3-14, of the
# fault status field: "This field is defined for access and address errors only
# and written as zeros for all other types of exceptions." The two callers
# outside this module - `control.nim`'s `TRAP` and `irq.nim`'s interrupt - are
# both "other types", so `0000` is what the manual writes for each of them, and
# a required parameter would make each of them state a value the manual already
# fixes. `frameFirstLongword` keeps its own `fs` parameter undefaulted, so the
# layout is still closed by the compiler one layer down.

proc takeException*(ctx: MCF5307Ctx; vector: uint8; stackedPc: uint32;
                    fs: uint32 = fsNotAnAccessError) =
  ## An exception whose processing begins where the fault was detected, so
  ## section 3.3's copy of the status register is the live word.
  takeExceptionCopiedSr(ctx, vector, stackedPc, fs, ctx.sr and 0xFFFF'u32)

proc takePendingWriteFault*(ctx: MCF5307Ctx) =
  ## Take the access error a faulted store recorded, at the instruction
  ## boundary. `cpu.nim`'s `step` is the one caller, and `writeMem` above
  ## carries the manual reading that puts the take here.
  ##
  ## The capture fields are cleared whether or not the vector is taken, and a
  ## snapshot is why. `state.nim` encodes every context field, so a machine
  ## that left a spent capture behind would save a block that differs from the
  ## block of a machine in the same architectural state reached another way.
  ##
  ## A halted core takes nothing. The executor stopped for a reason of its own -
  ## an illegal encoding, an illegal effective address, a nil callback - and a
  ## machine that is not going to run its next instruction is not going to run
  ## a handler's first one either.
  if not ctx.pendingWriteFault:
    return
  let stackedPc = ctx.pendingStackedPc
  let stackedSr = ctx.pendingStackedSr
  let fs = ctx.pendingFaultStatus
  ctx.pendingWriteFault = false
  ctx.pendingStackedPc = 0'u32
  ctx.pendingStackedSr = 0'u32
  ctx.pendingFaultStatus = 0'u32
  if ctx.halted:
    return
  takeExceptionCopiedSr(ctx, vecAccessError, stackedPc, fs, stackedSr)

proc transferControl*(ctx: MCF5307Ctx; target: uint32; faultPc: uint32) =
  ## Write `target` into the program counter, or take the address error when
  ## it is odd. `faultPc` is the address of the instruction doing the
  ## transferring.
  ##
  ## "Any attempted execution transferring control to an odd instruction
  ## address (i.e., if bit 0 of the target address is set) results in an
  ## address error exception" - MCF5307 User's Manual, section 3.5.2. The
  ## Programmer's Reference Manual, Rev. 3 assigns the vector and stops there:
  ## its section 11.1.3 names a table of processor exceptions that the revision
  ## does not carry, so nothing in it says what raises this one.
  ##
  ## It is a funnel and not a check per executor: a test beside each
  ## `ctx.pc = target` is silent for whichever executor is added next.
  ##
  ## The stacked program counter is the transferring instruction's, not the odd
  ## address and not the instruction after it: vector 3 is marked `Fault` in
  ## the vector assignments, and "fault refers to the PC of the instruction
  ## that caused the exception".
  ##
  ## `fsInstructionFetch` is the fault status. The field is defined for access
  ## and address errors, and `0100` - "error on instruction fetch" - is the one
  ## defined code naming the access this exception exists to refuse.
  ##
  ## The program counter loaded by `takeException` itself is not checked here,
  ## and a vector table entry with bit 0 set therefore still enters a handler
  ## at an odd address. The manual puts that case in the fault-on-fault halted
  ## state, which this core has no representation for yet; routing the handler
  ## address through this procedure would recurse instead.
  if (target and 1'u32) != 0'u32:
    takeException(ctx, vecAddressError, faultPc, fsInstructionFetch)
  else:
    ctx.pc = target

# ---------------------------------------------------------------------------
# The register access the conformance harness needs. The C ABI in
# `include/mcf5307.h` declares these. `index` 0..7 is d0..d7, 8..14 is a0..a6,
# 15 is a7 (the single stack pointer), 16 is the status register, and 17 is
# the program counter (read-only through this call).

proc mcf5307_set_reg*(ctx: MCF5307Ctx; index: cint; value: uint32): cint
    {.exportc: "mcf5307_set_reg", cdecl, dynlib.} =
  if ctx.isNil or index < 0 or index > 24:
    return cast[cint](0)
  if regFileSet(ctx, int(index), value):
    return cast[cint](1)
  cast[cint](0)

proc mcf5307_get_reg*(ctx: MCF5307Ctx; index: cint): uint32
    {.exportc: "mcf5307_get_reg", cdecl, dynlib.} =
  if ctx.isNil or index < 0 or index > 24:
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
