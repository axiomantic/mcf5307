## `machine` - the machine substrate every instruction group executes against.
##
## THIS MODULE HAS ONE JOB: given a context, read and write the machine's
## state. The register file, the condition-code bits, the board accesses, the
## instruction-stream extension words and the effective-address evaluation are
## all "how the machine is touched". What each opcode MEANS is the job of the
## instruction-group modules (`move.nim`, `alu.nim`, and later `logic.nim` and
## `control.nim`), and none of that is here.
##
## WHY IT EXISTS. Every executor needs the same register file, the same board
## accesses and the same effective-address evaluation. `alu.nim` importing
## `move.nim` for them would put an executor under another executor, which is
## the SAME SHAPE as the decoder-under-executor cycle. The helpers are pure
## functions over the shared types, so they live beside those types and not
## beside one caller.
##
## THE LAYERING. This module sits at the `decode_types` level. It reads the
## shared types and it names no executor and no decoder:
##
##     ea
##      ^
##     decode_types            the shared types and the EA legality table
##      ^        ^
##     machine   |             THIS MODULE: the state, and how to touch it
##      ^  ^     |
##      |  |   decode          the instruction word -> Operation + EA
##      |  |     ^
##     move alu  |             the instruction semantics, one module per group
##      ^   ^    ^
##          cpu               `step`, the dispatch, and the lifecycle ABI
##
## `decode` DOES NOT IMPORT THIS MODULE and must not: a decoder that reaches
## machine state is that inversion.
##
## THE CASTS IN `s16`/`s8` ARE CORRECT AND A CONVERSION IS NOT. See the note
## above them.
##
## MIT licensed and clean-room with respect to GPL and LGPL code. Register
## numbering, the condition-code bit positions and addressing-mode behaviour
## are facts about Motorola silicon; they are taken from the ColdFire Family
## Programmer's Reference Manual and the MCF5307 User's Manual and from this
## project's own measurements.

import mcf5307/bus
import mcf5307/decode_types
import mcf5307/ea
import mcf5307/exception

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
  ## A SIZED WRITE TO A REGISTER REPLACES THE LOW size BYTES AND NOTHING ELSE.
  ## `MOVE.B` and `MOVE.W` into `Dn` leave the rest of `Dn` untouched, and so do
  ## `CLR.B`, `CLR.W` and the low half of `EXT.W`. A size of 4 masks to all ones
  ## and this reduces to the value, which is why the long forms need no case of
  ## their own.
  ##
  ## THERE IS ONE COPY OF THIS RULE AND EVERY SIZED REGISTER WRITE GOES THROUGH
  ## IT.
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

# AN ABSENT CALLBACK IS A REFUSED ACCESS AND NOT AN ABORT. `mcf5307_create`
# (`include/mcf5307.h`) forbids no argument, so a context whose board callbacks
# are all nil is a context a caller may build, and `step` in `cpu.nim` opens by
# faulting on a nil `readFn` rather than calling it - the core's own statement
# that such a context is a state it survives. The requirement behind that
# statement is that nothing aborts the process: an abort inside a plugin
# destroys the host's session.
#
# THE GUARD IS HERE AND NOT ONLY AT THE HEAD OF `step` BECAUSE THIS IS WHERE THE
# CALL HAPPENS. `step`'s guard answers for the paths that run THROUGH `step`;
# `takeException` runs at the instruction boundary, ahead of the first fetch,
# and reaches these two procedures without passing it. A guard at each caller
# would be one guard per path and would be missing from the next path added.
#
# A NIL CALLBACK REPORTS THE SAME FAULT A BOARD'S REFUSAL REPORTS, which is the
# behaviour the callers are already written for: every caller of these two
# checks `ctx.halted` and unwinds. Inventing a second failure mode would give
# each of them a second thing to check.
#
# `fetchExt` BELOW CALLS `ctx.readFn` WITHOUT SUCH A GUARD, AND IT IS NOT
# REACHED WITH A NIL ONE. Its call sites are the effective-address evaluator in
# this module and the executor modules, and each of those runs only from
# `step`, whose first statement faults on a nil `readFn`.

# THE `FS` ARGUMENT IS DEFAULTED, AND THE DEFAULT IS THE REFERENCE'S ANSWER
# RATHER THAN THIS MODULE'S CONVENIENCE. The fault status field "is defined for
# access and address errors only and written as zeros for all other types of
# exceptions". The callers outside this module - `control.nim`'s `TRAP` and
# `irq.nim`'s interrupt - are both "other types", so `0000` is the documented
# value for each of them, and a required parameter would make each of them
# state a value that is already fixed. `frameFirstLongword` keeps its own `fs`
# parameter undefaulted, so the layout is still closed by the compiler one
# layer down.
proc takeException*(ctx: MCF5307Ctx; vector: uint8; stackedPc: uint32;
                    fs: uint32 = fsNotAnAccessError)

proc boardRead(ctx: MCF5307Ctx; address: uint32; size: uint8;
               st: var Mcf5307BusStatus): uint32 =
  ## One board read, reporting what the board reported and deciding nothing.
  ## The two callers below are the decision and they differ.
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

# THE TWO LAYERS DIFFER IN WHAT A NON-OK STATUS MEANS AND IN NOTHING ELSE. On
# an executor's path it is an ACCESS FAULT and takes a vector; inside an
# exception ENTRY the same status is a DOUBLE FAULT and halts. The design
# requires the second and requires that it not recurse.
#
# THE BOUND ON THE RECURSION IS THE CALL GRAPH AND NOT A FLAG ON THE CONTEXT.
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

# THE READ PATH HALTS AND DOES NOT TAKE A VECTOR, AND AN UNWIND BLOCKS IT
# RATHER THAN A PREFERENCE. The design requires that a fault be taken "before
# it commits any register or memory side effect of the faulting instruction",
# and `ctx.halted` is the ONLY signal that unwinds a part-completed
# instruction: every executor checks it after each step. An access fault must
# NOT halt - the handler has to run - so a read that took a vector here would
# return to an executor that carried on with a zero operand and committed it.
# `move.l 0x1000,%d1` against a board that reports `busUnmapped` leaves `d1`
# zeroed over its previous value.
#
# TAKING IT AT THE INSTRUCTION BOUNDARY IS THE FIX AND IT IS NOT WRITABLE FROM
# THIS MODULE: it needs either a pending-fault field on `MCF5307Ctx`, which
# `decode_types.nim` holds, or a check after the executor returns, which
# `cpu.nim`'s `step` holds. `tests/t_bus_fault.nim` pins the present behaviour
# so that wiring the read path is a deliberate change and not a silent one.
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
  if st != Mcf5307BusStatus.busOk:
    takeException(ctx, vecAccessError, ctx.pc, faultStatusFor(st, operandWrite))

proc fetchExt*(ctx: MCF5307Ctx): uint16 =
  ## Read one extension word from the instruction stream and advance the pc
  ## past it.
  ##
  ## THIS PROCEDURE DOES NOT DEFINE THE PC-RELATIVE BASE. The base is the
  ## address OF the displacement word, which is the pc BEFORE this call.
  ## `eaAddr` reads `ctx.pc` into a local before it calls this procedure for
  ## exactly that reason; the citation is on the PC arms there.
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
# THE CASTS ARE CORRECT AND A CONVERSION IS NOT. Sign extension REINTERPRETS
# the bits of an unsigned value as a two's-complement signed value of the same
# width. It does not narrow the value, so there is no range to check. A
# conversion `int16(x)` is a CHECKED narrowing conversion: the library is
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
  ## Dn(0) or An(1), bits 14..12 the index register, BIT 11 word(0) or long(1)
  ## index, bits 10..9 the scale (1, 2, 4, 8), bit 8 the brief-format marker,
  ## bits 7..0 the signed d8.
  ##
  ## THE WORD/LONG SELECT IS BIT 11. Bit 8 is the brief-format marker and is
  ## zero in every word the assembler emits.
  ##
  ## THE REFERENCE DOES NOT PRINT THE EXTENSION WORD'S LAYOUT. There is no
  ## brief-format figure anywhere in it, so the pinned
  ## assembler is the authority for the bit position: `btst %d1,(4,%pc,%d2)`
  ## assembles to `033b 2804`, whose `2804` has bit 11 SET and bit 8 CLEAR, and
  ## `m68k-elf-objdump -m m68k:5307` prints `%pc@(0x6,%d2:l)` - `:l`, a LONG
  ## index. Scaling corroborates the neighbouring fields: `(4,%pc,%d2*4)` is
  ## `2c04`, which moves bits 10..9 alone.
  ##
  ## WHAT THE REFERENCE DOES SAY IS THAT THE WORD FORM DOES NOT EXIST HERE:
  ## "Any attempted use of a word-sized index register (Xi.w) or a scale factor
  ## of 8 on an indexed effective addressing mode generates an address error".
  ## `m68k-elf-as
  ## -mcpu=5307` agrees and REJECTS `btst %d1,(4,%pc,%d2.w)`, so bit 11 is set
  ## in every encoding this core can legally be given and the narrowing branch
  ## below is unreachable from assembled code.
  ##
  ## THAT ADDRESS ERROR IS NOT RAISED HERE. This procedure narrows a word
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
  ## WHAT THIS PROCEDURE DOES NOT KNOW, and the rule for each is the one
  ## `logic.nim`'s header uses: THE IMPLEMENTATION PICKS A BEHAVIOUR.
  ##
  ##   1. THE ADDRESS ERROR OF AN ILLEGAL INDEX. A word-sized index register or
  ##      a scale factor of 8 "generates an address error". `indexOperand`
  ##      raises no such
  ##      error: it narrows the word index and it applies the scale of 8.
  ##      `m68k-elf-as -mcpu=5307` REFUSES to assemble `(4,%pc,%d2.w)` and
  ##      `(4,%pc,%d2*8)`, so a hand-written word would be asserting a trap
  ##      this core does not have. Raising it is a change of behaviour and
  ##      belongs to whoever owns the exception model, not to a repair of the
  ##      address arithmetic.
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
      # THE PC-RELATIVE BASE IS THE ADDRESS *OF* THE EXTENSION WORD, so it is
      # taken BEFORE `fetchExt` advances the program counter past it. The
      # indexed PC mode below takes its base the same way and for the same
      # reason.
      #
      # THE REFERENCE DOES NOT SETTLE THIS. It names `(d16,PC)` and
      # `(d8,PC,Xi)` and prints no effective-address equation for any mode, so
      # the authority here is the pinned assembler: `btst %d1,(target,%pc)`
      # with the opcode at 0 assembles to `033a 0004` and `target` is placed
      # at 6, and
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
  ## Write the operand of an alterable effective address. A Dn write REPLACES
  ## THE LOW size BYTES AND KEEPS THE REST of the register; memory modes write
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
# A destination resolved ONCE.
#
# `eaRead` followed by `eaWrite` on the same operand evaluates the effective
# address TWICE. For (An)+ and -(An) that applies the adjustment twice and
# writes to the wrong address, and for (d16,An) and the absolute modes it
# consumes the extension words twice and desynchronises the program counter
# from the instruction stream. Every read-modify-write instruction - which is
# most of the arithmetic group - therefore resolves the destination once and
# reads and writes THROUGH THE RESOLVED REFERENCE.
#
# `move.nim` needs none of this: MOVE writes its destination and never reads
# it.

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
# THE EXCEPTION STACK FRAME. `TRAP` needs it, because a TRAP that did not take
# its vector would be a NOP with extra steps.
#
# IT IS HERE AND NOT IN `control.nim` FOR THE REASON THIS MODULE EXISTS. The
# exception model, the bus-fault channel, interrupts and `control.nim`'s own
# format-error path all need the same frame, and `exception.nim` is a SIBLING
# of `control.nim`, so it could not reach a copy that lived there without
# putting one executor under another. That is the decoder-under-executor
# inversion one layer down.
#
# IT IS THE MINIMUM `TRAP` NEEDS AND NOT THE EXCEPTION MODEL. There is no
# vector table object, no fault-status computation and no double-fault
# handling; this procedure is what those extend.

# THE BITS NAMED HERE ARE THE ONES THIS MODULE'S OWN `takeException` WRITES OR
# PRESERVES, and `srMaster` sits with them because a status-register
# bit position is a fact about the register and not about the exception that
# happens to clear it.
const
  srSupervisor* = 0x2000'u32   ## S, status register bit 13
  srTrace* = 0x8000'u32        ## T, status register bit 15
  srMaster* = 0x1000'u32       ## M, status register bit 12

proc exceptionFrameBase*(sp: uint32): uint32 =
  ## Where the two-longword frame goes, and it is NOT simply `sp - 8`.
  ##
  ## "The exception stack frame is created at a 0-modulo-4 address on the top
  ## of the current system stack". The format field encoding gives the cases: an
  ## A7 whose low two bits are 00, 01, 10 or 11 leaves the handler with A7-8,
  ## A7-9, A7-10 or A7-11, and each of those results is 0-modulo-4. That is
  ## this expression.
  (sp - 8'u32) and not 3'u32

proc exceptionFormat*(sp: uint32): uint32 =
  ## The FORMAT field of the frame the stack pointer `sp` produces: 4, 5, 6 or
  ## 7, the rows of the format field encoding in order. It RECORDS the
  ## misalignment the frame base removed, so that `RTE` can put it back.
  4'u32 + (sp and 3'u32)

proc takeException*(ctx: MCF5307Ctx; vector: uint8; stackedPc: uint32;
                    fs: uint32) =
  ## Stack a two-longword exception frame, then load the program counter from
  ## the vector table.
  ##
  ## THE STATUS REGISTER IS COPIED BEFORE IT IS CHANGED: "the processor makes
  ## an internal copy of the SR and then enters supervisor mode by setting the
  ## S-bit and disabling trace mode by clearing the T-bit". The COPY is what
  ## reaches the frame; the modified word is what the handler runs under. The
  ## M-bit and the interrupt priority mask are changed only by an INTERRUPT
  ## exception, so nothing here touches them.
  ##
  ## THE FRAME IS TWO LONGWORD WRITES AND NOT SIX BYTEWISE PUSHES. It is drawn
  ## as two longwords - the format/vector word above the status register, then
  ## the program counter - and `trap #imm` costs `18(1/2)`: ONE read, the
  ## vector, and TWO writes. The instruction summary spells the same thing as
  ## `SP-4;PC`, `SP-2;SR`, `SP-2;Format`, which agrees whenever A7 was already
  ## longword aligned and does not show the self-alignment at all.
  ##
  ## THE VECTOR TABLE IS BASED AT ZERO, AND THAT IS A LIMITATION AND NOT A
  ## CHOICE. The handler address is "obtained by fetching a value from the
  ## table located at the address defined in the vector base register", indexed
  ## by `4 x vector_number`. THIS CORE HAS NO VBR: the context holds no such
  ## field, and `MOVEC` is the only way to write one.
  ##
  ## THE RESET VALUE IS ZERO AND THE REFERENCE PRINTS IT: VBR has a width of
  ## 32, a RESET VALUE of `$00000000` and an ACCESS of `W`. So this expression
  ## is correct for a machine that has not written VBR and wrong for one that
  ## has, and the one line that would change is the `readMem` below.
  ##
  ## A FAULT INSIDE THIS PROCEDURE IS A DOUBLE FAULT. Each access is checked
  ## and the procedure returns early, leaving the context halted with `fault`;
  ## it does not recurse, which is the design's requirement. The status
  ## register has already been modified at that point, which is a state a
  ## double-fault handler will have to define.
  let stackedSr = ctx.sr and 0xFFFF'u32
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
  let handler = stackingRead(ctx, vectorAddress(0'u32, vector), 4)
  if ctx.halted:
    return
  ctx.pc = handler
  # THE HANDLER'S FIRST INSTRUCTION HAS NOT RUN, AND THAT IS A FACT ABOUT THE
  # MACHINE THAT OUTLIVES THIS CALL. "ColdFire processors inhibit sampling for
  # interrupts during the first instruction of all exception handlers."
  # `mcf5307_exec` reads this field at its sample and clears it;
  # `decode_types.nim` states why it is a field of the context.
  #
  # IT IS WRITTEN HERE, AFTER THE PROGRAM COUNTER, AND THAT POSITION IS THE
  # WHOLE OF THE RULE'S REACH. Every exception this core takes ends on this
  # line, so no exception path can acquire the rule and none can be forgotten
  # by it. A flag set by `execTrap` instead would be a rule about TRAP.
  #
  # RE-MEASURED AGAINST THIS TREE - the one where `mcf5307_reset`
  # SETS `atHandlerEntry` for the reset exception's own first instruction and
  # GUARDS a nil context, and where `t_irq` carries 37 cases: moving this line
  # out of here and into `execTrap` leaves every one of those cases GREEN,
  # because TRAP is still the only exception an INSTRUCTION of this tree can
  # take and the two spellings agree on every path that exists. THE RESET IS
  # NOT A COUNTEREXAMPLE: it does
  # not run through this procedure at all, it writes the field itself, and
  # `cpu.nim` says why. The funnel is a reason and not a measurement until a
  # SECOND path into this procedure from inside `step` exists; the bus-fault
  # exception is that path.
  #
  # A TAKE THAT FAULTED DOES NOT SET IT, because each early return above is
  # ahead of this line and a machine that never reached a handler is not at
  # one.
  ctx.atHandlerEntry = true

# ---------------------------------------------------------------------------
# The register access the conformance harness needs. The C ABI in
# `include/mcf5307.h` declares these; the runner's register bridge is the only
# caller today. `index` 0..7 is d0..d7, 8..14 is a0..a6,
# 15 is a7 (the single stack pointer), 16 is the status register, and 17 is
# the program counter (read-only through this call).
#
# THEY LIVE BESIDE THE REGISTER FILE.

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
# The run state the conformance harness needs. `include/mcf5307.h` declares
# these two beside the register accessors, and for the same reason: the harness
# goes through the C ABI and the ABI published no way to see them.
#
# THEY ARE TWO CALLS AND NOT ONE, BECAUSE `halted` AND `fault` ARE TWO BITS.
# `cpu.nim`'s `step` sets `halted` alone for a valid opcode whose semantics are
# not yet written, and it sets BOTH for a bus error, an illegal instruction
# word, an illegal effective address, an illegal size or a divide by zero.
# Folding them into one call would make "this instruction trapped" and "this
# instruction is not written yet" the same answer, and the conformance runner
# has to separate exactly those two.
#
# THEY REPORT AND THEY DO NOT CLEAR. `mcf5307_reset` is what clears both bits,
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
