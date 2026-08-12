## `machine` - the machine substrate every instruction group executes against.
## Task CPU-8 creates this file by LIFTING the shared helpers out of
## `move.nim`. Design section 6.1.
##
## THIS MODULE HAS ONE JOB: given a context, read and write the machine's
## state. The register file, the condition-code bits, the board accesses, the
## instruction-stream extension words and the effective-address evaluation are
## all "how the machine is touched". What each opcode MEANS is the job of the
## instruction-group modules (`move.nim`, `alu.nim`, and later `logic.nim` and
## `control.nim`), and none of that is here.
##
## WHY IT EXISTS. CPU-7 wrote these helpers inside `move.nim` because `move`
## was the only executor. CPU-8 adds a second executor that needs the same
## register file, the same board accesses and the same effective-address
## evaluation. `alu.nim` importing `move.nim` for them would put an executor
## under another executor, which is the SAME SHAPE as the decoder-under-
## executor cycle that CPU-7 spent three commits unwinding, and it is bad at
## two siblings and worse at four. The helpers are pure functions over the
## shared types, so `~/Desktop/avoiding-cycles.md` puts them beside those
## types, not beside one caller.
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
## machine state is the inversion CPU-7 removed.
##
## THE CASTS IN `s16`/`s8` ARE CORRECT AND A CONVERSION IS NOT. See the note
## above them; `tests/t_sign_extend.nim` pins their boundaries and follows them
## here from `move.nim`.
##
## MIT licensed and clean-room with respect to GPL and LGPL code. Register
## numbering, the condition-code bit positions and addressing-mode behaviour
## are facts about Motorola silicon; they are taken from the ColdFire Family
## Programmer's Reference Manual and the MCF5307 User's Manual (AGENTS.md
## section 11) and from this project's own measurements.

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
  ## A SIZED WRITE TO A REGISTER REPLACES THE LOW size BYTES AND NOTHING ELSE.
  ## `MOVE.B` and `MOVE.W` into `Dn` leave the rest of `Dn` untouched, and so do
  ## `CLR.B`, `CLR.W` and the low half of `EXT.W`. A size of 4 masks to all ones
  ## and this reduces to the value, which is why the long forms need no case of
  ## their own.
  ##
  ## THERE IS ONE COPY OF THIS RULE AND EVERY SIZED REGISTER WRITE GOES THROUGH
  ## IT. `eaWrite` and `eaRefWrite` each carried their own copy, they disagreed,
  ## and the disagreement was a live defect: `eaWrite` REPLACED the whole
  ## register, so `move.b %d0,%d1` with d1 = 0x12345678 and d0 = 0xAA gave
  ## 0x000000AA where the part gives 0x123456AA. `tests/t_move.nim` asserts it.
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
  ## past it.
  ##
  ## THIS PROCEDURE DOES NOT DEFINE THE PC-RELATIVE BASE, AND AN EARLIER
  ## REVISION OF THIS COMMENT ASSERTED THAT IT DID. It read "the pc-relative
  ## base of a PC mode is the pc AFTER its last extension word, which is
  ## exactly where the next instruction begins", and that is false: the base is
  ## the address OF the displacement word, which is the pc BEFORE this call.
  ## `eaAddr` reads `ctx.pc` into a local before it calls this procedure for
  ## exactly that reason; the citation is on the two PC arms there.
  ##
  ## The wrong sentence was not idle. `eaAddr` was written to agree with it and
  ## every PC-relative operand in the core was two bytes high.
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
  ## THE WORD/LONG SELECT IS BIT 11 AND THIS READ IT AT BIT 8. Bit 8 is the
  ## brief-format marker and is zero in every word the assembler emits, so the
  ## old reading answered WORD for every legal encoding and sign-extended an
  ## index that must not be narrowed at all.
  ##
  ## THE MANUAL DOES NOT PRINT THE EXTENSION WORD'S LAYOUT. There is no
  ## brief-format figure anywhere in the MCF5307 User's Manual, so the pinned
  ## assembler is the authority for the bit position: `btst %d1,(4,%pc,%d2)`
  ## assembles to `033b 2804`, whose `2804` has bit 11 SET and bit 8 CLEAR, and
  ## `m68k-elf-objdump -m m68k:5307` prints `%pc@(0x6,%d2:l)` - `:l`, a LONG
  ## index. Scaling corroborates the neighbouring fields: `(4,%pc,%d2*4)` is
  ## `2c04`, which moves bits 10..9 alone.
  ##
  ## WHAT THE MANUAL DOES SAY IS THAT THE WORD FORM DOES NOT EXIST HERE.
  ## Section 3.5.2, "Address Error Exception", page 3-15: "Any attempted use of
  ## a word-sized index register (Xi.w) or a scale factor of 8 on an indexed
  ## effective addressing mode generates an address error". `m68k-elf-as
  ## -mcpu=5307` agrees and REJECTS `btst %d1,(4,%pc,%d2.w)`, so bit 11 is set
  ## in every encoding this core can legally be given and the narrowing branch
  ## below is unreachable from assembled code.
  ##
  ## THAT ADDRESS ERROR IS NOT RAISED HERE, and nothing asserts it. This
  ## procedure narrows a word index rather than faulting on one, and it applies
  ## a scale of 8 rather than faulting on that. Both are outside the defect
  ## this comment repairs; see the uncertainty note in `eaAddr` below.
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
  ## WHAT THIS PROCEDURE DOES NOT KNOW. Two things, and the rule for both is
  ## the one `logic.nim`'s header uses: THE IMPLEMENTATION PICKS A BEHAVIOUR
  ## AND NOTHING ASSERTS IT.
  ##
  ##   1. THE ADDRESS ERROR OF AN ILLEGAL INDEX. MCF5307 User's Manual section
  ##      3.5.2, page 3-15, says a word-sized index register or a scale factor
  ##      of 8 "generates an address error". `indexOperand` raises no such
  ##      error: it narrows the word index and it applies the scale of 8. No
  ##      case reaches either, because `m68k-elf-as -mcpu=5307` REFUSES to
  ##      assemble `(4,%pc,%d2.w)` and `(4,%pc,%d2*8)`, so the corpus - which
  ##      is generated through that assembler - cannot express one, and a
  ##      hand-written word would be asserting a trap this core does not have.
  ##      Raising it is a change of behaviour and belongs to whoever owns the
  ##      exception model, not to a repair of the address arithmetic.
  ##
  ##   2. THE SIGN EXTENSION OF `(xxx).W`. `ea7AbsW` sign-extends its one
  ##      extension word, so `0x8000.w` addresses `0xFFFF8000`. NOTHING PINS
  ##      IT: the conformance runner's board is 1 MiB, an access above it
  ##      reports `busUnmapped`, and a case whose operand access faults fails
  ##      on the run state rather than on the address. Every `(xxx).W` case in
  ##      the corpus therefore uses a positive short address, at which
  ##      sign-extending and zero-extending are the same answer.
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
      # THE FIRST EXTENSION WORD IS THE HIGH HALF OF THE ADDRESS. MCF5307
      # User's Manual section 3.7.2, "Organization of Integer Data Formats in
      # Memory", page 3-19: "The address N of a longword data item corresponds
      # to the address of the high order word. The lower order word is located
      # at address N + 2." The extension pair is a longword in the instruction
      # stream, so the word at the lower address is the high half.
      # `m68k-elf-as -mcpu=5307` agrees: `btst %d1,0x00030004` assembles to
      # `0339 0003 0004`.
      #
      # THIS READ THE TWO HALVES THE OTHER WAY ROUND, and nothing saw it: no
      # case in any group used an absolute-long operand at all. Measured on a
      # dynamic BTST against `$00030004`, the core reached `$00040003`. The two
      # other readers of a longword in the instruction stream - `ea7Imm` below
      # and `execImmediate` in `logic.nim` - already took the high half first,
      # so the tree disagreed with itself.
      let hi = fetchExt(ctx)
      let lo = fetchExt(ctx)
      result = (uint32(hi) shl 16) or uint32(lo)
    of ea7PCDisp:
      # THE PC-RELATIVE BASE IS THE ADDRESS *OF* THE EXTENSION WORD, so it is
      # taken BEFORE `fetchExt` advances the program counter past it. The
      # indexed PC mode below takes its base the same way and for the same
      # reason.
      #
      # THE MANUAL DOES NOT SETTLE THIS. The MCF5307 User's Manual names
      # `(d16,PC)` and `(d8,PC,Xi)` in Table 3-5 (page 3-21) and prints no
      # effective-address equation for any mode, so the authority here is the
      # pinned assembler. Measured: `btst %d1,(target,%pc)` with the opcode at
      # 0 assembles to `033a 0004` and `target` is placed at 6, and
      # `m68k-elf-objdump -m m68k:5307` prints `btst %d1,%pc@(6 <target>)`.
      # Base + 4 = 6, so the base is 2 - the address of the displacement word
      # and not the address after it.
      #
      # THIS TOOK THE BASE AFTER THE WORD and every PC-relative operand in the
      # core - MOVE's, the arithmetic group's and BTST's alike - was two bytes
      # high. Nothing saw it: no conformance case in any group used a
      # PC-relative operand, and `tests/t_logic.nim` seeded both candidate
      # addresses with the same byte on purpose so that it would not pin the
      # base.
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
# it. The pair below arrived with CPU-8 for that reason.

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
# THE EXCEPTION STACK FRAME. CPU-10 adds it, because `TRAP` is in its group and
# a TRAP that did not take its vector would be a NOP with extra steps.
#
# IT IS HERE AND NOT IN `control.nim` FOR THE REASON THIS MODULE EXISTS. Four
# later tasks need the same frame - CPU-14 owns the exception model itself,
# CPU-15 the bus-fault channel, CPU-17 interrupts, and `control.nim`'s own
# format-error path - and `exception.nim` will be a SIBLING of `control.nim`,
# so it could not reach a copy that lived there without putting one executor
# under another. That is the decoder-under-executor inversion one layer down;
# `~/Desktop/avoiding-cycles.md` is the rule and CPU-8 followed it when it
# lifted the register file out of `move.nim`.
#
# IT IS THE MINIMUM `TRAP` NEEDS AND NOT THE EXCEPTION MODEL. There is no
# vector table object, no fault-status computation and no double-fault
# handling; CPU-14 and CPU-15 own those and this procedure is what they will
# extend.

const
  srSupervisor* = 0x2000'u32   ## S, status register bit 13
  srTrace* = 0x8000'u32        ## T, status register bit 15

proc exceptionFrameBase*(sp: uint32): uint32 =
  ## Where the two-longword frame goes, and it is NOT simply `sp - 8`.
  ##
  ## MCF5307 User's Manual section 3.3, page 3-11: "the exception stack frame
  ## is created at a 0-modulo-4 address on the top of the current system
  ## stack". Table 3-2, "Format Field Encoding", page 3-14, gives the four
  ## cases: an A7 whose low two bits are 00, 01, 10 or 11 leaves the handler
  ## with A7-8, A7-9, A7-10 or A7-11, and each of those four results is
  ## 0-modulo-4. That is this expression.
  (sp - 8'u32) and not 3'u32

proc exceptionFormat*(sp: uint32): uint32 =
  ## The FORMAT field of the frame the stack pointer `sp` produces: 4, 5, 6 or
  ## 7, the four rows of Table 3-2 in order. It RECORDS the misalignment the
  ## frame base removed, so that `RTE` can put it back.
  4'u32 + (sp and 3'u32)

proc takeException*(ctx: MCF5307Ctx; vector: uint8; stackedPc: uint32) =
  ## Stack a two-longword exception frame, then load the program counter from
  ## the vector table.
  ##
  ## THE STATUS REGISTER IS COPIED BEFORE IT IS CHANGED. Section 3.3, page
  ## 3-11: "the processor makes an internal copy of the SR and then enters
  ## supervisor mode by setting the S-bit and disabling trace mode by clearing
  ## the T-bit". The COPY is what reaches the frame; the modified word is what
  ## the handler runs under. The M-bit and the interrupt priority mask are
  ## changed only by an INTERRUPT exception, which is CPU-17's, so nothing
  ## here touches them.
  ##
  ## THE FRAME IS TWO LONGWORD WRITES AND NOT SIX BYTEWISE PUSHES. Figure 3-7,
  ## page 3-13, draws it as two longwords - the format/vector word above the
  ## status register, then the program counter - and Table 3-14, page 3-29,
  ## gives `trap #imm` a cost of `18(1/2)`: ONE read, the vector, and TWO
  ## writes. Table 3-7's `TRAP` row on page 3-25 spells the same thing as
  ## `SP-4;PC`, `SP-2;SR`, `SP-2;Format`, which agrees whenever A7 was already
  ## longword aligned and does not show the self-alignment at all.
  ##
  ## THE VECTOR TABLE IS BASED AT ZERO, AND THAT IS A LIMITATION AND NOT A
  ## CHOICE. Section 3.3, page 3-12: the handler address is "obtained by
  ## fetching a value from the table located at the address defined in the
  ## vector base register", indexed by `4 x vector_number`. THIS CORE HAS NO
  ## VBR: the context holds no such field, and CPU-11 is the task that adds
  ## `MOVEC` and therefore the only way to write one.
  ##
  ## THE RESET VALUE IS ZERO AND THE MANUAL PRINTS IT. Table B-2, "Summary
  ## Chart of MCF5307 Internal CPU Memory Map", Appendix page B-5, gives
  ## `CPU @ $801` the name VBR, a width of 32, a RESET VALUE of `$00000000`
  ## and an ACCESS of `W`. So this expression is correct for a machine that
  ## has not written VBR and wrong for one that has, and the one line that
  ## changes when CPU-11 lands is the `readMem` below.
  ##
  ## A FAULT INSIDE THIS PROCEDURE IS A DOUBLE FAULT AND CPU-15 OWNS IT. Each
  ## access is checked and the procedure returns early, leaving the context
  ## halted with `fault`; it does not recurse, which is design section 5.2.1's
  ## requirement. The status register has already been modified at that point,
  ## which is a state a double-fault handler will have to define.
  let stackedSr = ctx.sr and 0xFFFF'u32
  ctx.sr = (ctx.sr or srSupervisor) and not srTrace
  let format = exceptionFormat(ctx.sp)
  let base = exceptionFrameBase(ctx.sp)
  writeMem(ctx, base, 4,
           (format shl 28) or (uint32(vector) shl 18) or stackedSr)
  if ctx.halted:
    return
  writeMem(ctx, base + 4'u32, 4, stackedPc)
  if ctx.halted:
    return
  ctx.sp = base
  let handler = readMem(ctx, 4'u32 * uint32(vector), 4)
  if ctx.halted:
    return
  ctx.pc = handler

# ---------------------------------------------------------------------------
# The register access the conformance harness needs. The C ABI in
# `include/mcf5307.h` (CPU-0) declares these; the runner's register bridge
# (CPU-5) is the only caller today. `index` 0..7 is d0..d7, 8..14 is a0..a6,
# 15 is a7 (the single stack pointer), 16 is the status register, and 17 is
# the program counter (read-only through this call).
#
# THEY LIVE BESIDE THE REGISTER FILE. CPU-7 put them in `move.nim` because the
# register file was there; CPU-8 moved the file here and they came with it.
# The two names, the two signatures and the pragma set are unchanged, which is
# what the step 4a ABI gate measures.

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
# The run state the conformance harness needs. `include/mcf5307.h` (CPU-0)
# declares these two beside the register accessors, and for the same reason:
# the harness goes through the C ABI and the ABI published no way to see them.
#
# THEY ARE TWO CALLS AND NOT ONE, BECAUSE `halted` AND `fault` ARE TWO BITS.
# `cpu.nim`'s `step` sets `halted` alone for a valid opcode whose semantics a
# later task owns, and it sets BOTH for a bus error, an illegal instruction
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
