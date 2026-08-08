## `decode` - the instruction decoder for ColdFire ISA_A, and the part of the
## core lifecycle that the CPU-6 task owns. Task CPU-6 creates this file.
## Design section 6.1.
##
## THIS FILE OWNS TWO THINGS. (1) The instruction decoder: it turns a
## 16-bit instruction word into an `Operation` plus its effective address,
## and it supplies each opcode's effective-address legality mask. (2) The
## part of the `mcf5307_*` ABI that makes `mcf5307_exec` able to execute an
## instruction: the context, `mcf5307_create`, `mcf5307_destroy`,
## `mcf5307_reset` and `mcf5307_exec` itself. CPU-6 is the first task whose
## `Files:` line implements an instruction `mcf5307_exec` can execute (the
## plan's check text states this exactly); the instruction-group semantics
## are built by CPU-7 to CPU-10, which extend this dispatch.
##
## THE ONE A7. There is no supervisor and user stack split on ISA_A, so the
## context holds a single address register 7. `sp` is that one register.
##
## MIT licensed and clean-room with respect to GPL and LGPL code. Opcode
## encoding, the addressing-mode placement and the exception layout are facts
## about Motorola silicon; they are taken from the ColdFire Family
## Programmer's Reference Manual and the MCF5307 User's Manual (AGENTS.md
## section 11) and from this project's own measurements.

import mcf5307/ea

# ---------------------------------------------------------------------------
# The bus-status values and the board callbacks, matching `include/mcf5307.h`
# exactly. `Mcf5307BusStatus` has the width of a C `int` so that the
# out-parameter the board writes has the ABI the header declares.

type
  Mcf5307BusStatus* {.size: sizeof(cint), pure.} = enum
    busOk          = 0  ## the access completed
    busUnmapped    = 1  ## no device answers at this address
    busSizeIllegal = 2  ## the width is not one the device accepts
    busFault       = 3  ## the device answers and reports a fault of its own

  Mcf5307ReadFn* = proc(user: pointer; address: uint32; size: cint;
                        status: ptr Mcf5307BusStatus): uint32 {.cdecl.}
  Mcf5307WriteFn* = proc(user: pointer; address: uint32; size: cint;
                         value: uint32; status: ptr Mcf5307BusStatus) {.cdecl.}
  Mcf5307IackFn* = proc(user: pointer; level: cint; vector: uint8) {.cdecl.}

# ---------------------------------------------------------------------------
# The context. It is opaque to every caller: C sees `mcf5307_ctx` and never
# its layout. It is a Nim `ref` because `mcf5307_create` allocates it and the
# design (design section 5.6, CPU-19) requires that allocation happen ONLY
# inside `mcf5307_create`, never inside `mcf5307_exec`.

type
  MCF5307Ctx* = ref object
    user*: pointer
    readFn*: Mcf5307ReadFn
    writeFn*: Mcf5307WriteFn
    iackFn*: Mcf5307IackFn
    pc*: uint32     ## the program counter
    sp*: uint32     ## the single A7 - no supervisor/user split
    sr*: uint32     ## the status register (kept 32-bit, low 16 meaningful)
    halted*: bool   ## set when execution must stop this cycle budget
    fault*: bool    ## set on a firmware fault / illegal instruction

# ---------------------------------------------------------------------------
# The decoder.
#
# CPU-6 recognizes the instruction families that carry the effective-address
# legality demonstration, together with the two instructions that have no
# effective address. The full opcode table with per-group semantics is the
# work of CPU-7 to CPU-12; the decoder is structured so those tasks extend
# the `case` below and the legality table rather than rewrite it.

type
  Operation* = enum
    opIllegal     ## not a recognized ISA_A encoding (including line-A)
    opNop
    opMove        ## MOVE.<sz> <ea>,<ea>
    opAddq        ## ADDQ #imm,<ea>
    opSubq        ## SUBQ #imm,<ea>
    opLea         ## LEA <ea>,An
    opMoveq       ## MOVEQ #imm,Dn

  Decoded* = object
    op*: Operation
    ea*: EA

proc decodeWord*(word: uint16): Decoded =
  ## Decode one 16-bit instruction word into its operation and effective
  ## address. Every EA-bearing family recognized here places its effective
  ## address in the low six bits, which is the canonical placement.
  if word == 0x4E71'u16:
    return Decoded(op: opNop)
  elif (word and 0xC000'u16) == 0x0000'u16:
    # `00` prefix: MOVE, source EA in the low six bits.
    return Decoded(op: opMove, ea: decodeEa(word))
  elif (word and 0xF100'u16) == 0x5000'u16:
    return Decoded(op: opAddq, ea: decodeEa(word))
  elif (word and 0xF100'u16) == 0x5100'u16:
    return Decoded(op: opSubq, ea: decodeEa(word))
  elif (word and 0xFFC0'u16) == 0x41C0'u16:
    # LEA, destination An in bits 11..9, EA in the low six bits.
    return Decoded(op: opLea, ea: decodeEa(word))
  elif (word and 0xF100'u16) == 0x7000'u16:
    return Decoded(op: opMoveq)
  else:
    return Decoded(op: opIllegal)

proc eaLegalityFor*(op: Operation): EaLegality =
  ## The legality mask the opcode carries. Illegal for an opcode with no
  ## effective address is meaningless (the empty mask).
  case op
  of opMove, opAddq, opSubq:
    # These take data addressing, which admits every mode including the
    # mode-7 sub-variants. The reserved and invalid mode-7 encodings stay
    # out of the mask, so they trap.
    EaLegality(modes: eaDataModes, ea7: eaData7)
  of opLea:
    # LEA takes control addressing only. A data register direct (mode 0),
    # an immediate (mode 7, sub 4) and so on are illegal and must trap.
    EaLegality(modes: eaControlModes, ea7: eaControl7)
  else:
    EaLegality(modes: {}, ea7: {})

proc eaIsLegalFor*(op: Operation; ea: EA): bool =
  ## True when `ea` is inside the opcode's legality mask. An opcode with no
  ## effective address has no mask and therefore no illegal mode.
  result = (op in {opMove, opAddq, opSubq, opLea}) and
    isEaLegal(eaLegalityFor(op), ea)

# ---------------------------------------------------------------------------
# The instruction-cycle costs.
#
# THESE ARE NOMINAL. The per-instruction cycle budget on serial MCF5307
# silicon needs the clock work of open question 6 in AGENTS.md; until it is
# settled no exact cost is asserted anywhere. The only property the CPU-6
# check asserts is that `mcf5307_exec` returns a non-zero count. A later
# task replaces the constants when the clock is settled.

const
  fetchCycles = 2'u32   ## one 16-bit instruction fetch
  nopCycles = 2'u32     ## NOP on the execution pipe

# ---------------------------------------------------------------------------
# Core lifecycle.

proc mcf5307_create*(user: pointer; rd: Mcf5307ReadFn; wr: Mcf5307WriteFn;
                     iack: Mcf5307IackFn): MCF5307Ctx
    {.exportc: "mcf5307_create", cdecl, dynlib.} =
  ## Allocate the context and store the board callbacks. This is the one
  ## place the core allocates (design section 5.6, CPU-19).
  new(result)
  result.user = user
  result.readFn = rd
  result.writeFn = wr
  result.iackFn = iack

proc mcf5307_destroy*(ctx: MCF5307Ctx)
    {.exportc: "mcf5307_destroy", cdecl, dynlib.} =
  ## Tear the context down. Under `--mm:arc` the object is reclaimed when the
  ## owning reference is dropped; this marks it dead so a later use faults
  ## instead of reading a live object.
  if not ctx.isNil:
    ctx.halted = true
    ctx.fault = true
    ctx.readFn = nil
    ctx.writeFn = nil
    ctx.iackFn = nil

proc mcf5307_reset*(ctx: MCF5307Ctx; initialSp: uint32; initialPc: uint32)
    {.exportc: "mcf5307_reset", cdecl, dynlib.} =
  ## Reset the machine to a known state: the single A7 to `initial_sp`, the
  ## program counter to `initial_pc`, and the status register to the reset
  ## value. The reset vector longword 1 of the G2 (`0x16`) is
  ## `move.w #$2700,%sr`; `0x2700` is the correct supervisor, full-mask
  ## reset value on this part.
  ctx.sp = initialSp
  ctx.pc = initialPc
  ctx.sr = 0x2700'u32
  ctx.halted = false
  ctx.fault = false

proc step(ctx: MCF5307Ctx): uint32 =
  ## Execute one instruction: fetch, decode, and either execute it or halt.
  ## Returns the cycles spent. Halts with `fault` set on a bus fault or an
  ## illegal instruction; halts without `fault` on a recognized opcode whose
  ## semantics a later instruction-group task owns.
  if ctx.readFn.isNil:
    ctx.fault = true
    ctx.halted = true
    return 0
  var status = Mcf5307BusStatus.busOk
  let word = ctx.readFn(ctx.user, ctx.pc, 2, addr status)
  if status != Mcf5307BusStatus.busOk:
    ctx.fault = true
    ctx.halted = true
    return 0
  let decoded = decodeWord(uint16(word and 0xFFFF'u32))
  ctx.pc = ctx.pc + fetchCycles
  case decoded.op
  of opNop:
    result = fetchCycles + nopCycles
  of opMove, opAddq, opSubq, opLea, opMoveq:
    # Recognized at the decoder level. Their execution semantics arrive with
    # the instruction-group tasks (CPU-7 to CPU-10), which extend the
    # dispatch. Until then exec halts rather than pretend to have executed
    # them. The legality of their effective address is asserted directly by
    # the CPU-6 test through `eaIsLegalFor`.
    ctx.halted = true
    result = 0
  of opIllegal:
    ctx.fault = true
    ctx.halted = true
    result = 0

proc mcf5307_exec*(ctx: MCF5307Ctx; maxCycles: uint32): uint32
    {.exportc: "mcf5307_exec", cdecl, dynlib.} =
  ## Run at most `max_cycles` cycles and return the cycles actually spent.
  ## The loop stops when the budget is exhausted, or earlier when the machine
  ## halts (a fault, an illegal instruction, or an opcode this task has
  ## recognized but not yet executed).
  if ctx.isNil or ctx.halted:
    return 0
  var spent = 0'u32
  while spent < maxCycles and not ctx.halted:
    let cost = step(ctx)
    if ctx.halted:
      break
    if cost == 0'u32:
      break
    if spent + cost > maxCycles:
      spent = maxCycles
      break
    spent = spent + cost
  result = spent
