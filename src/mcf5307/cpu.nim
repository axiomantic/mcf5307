## `cpu` - the core lifecycle and the instruction dispatch of the ColdFire
## ISA_A core.
##
## This module is the top of the core. It owns the part of the `mcf5307_*`
## ABI that runs the machine: the lifecycle calls `mcf5307_create`,
## `mcf5307_destroy` and `mcf5307_reset`, the private `step` procedure, and
## `mcf5307_exec` itself.
##
## `step` decodes one word and then calls the executor of the
## instruction group that the word belongs to. It is therefore the one place
## that must know both the decoder and every executor:
##
##     decode_types            the shared types and the EA legality table
##        ^          ^
##     decode      move, alu
##        ^          ^
##            cpu               this module
##
## `decode` and the executors are level-2 siblings. Neither imports the other.
##
## To add an instruction group: write the new executor module beside
## `move.nim` and `alu.nim`, add one `import` line here, and add one arm to
## the `case decoded.op` below. `decode.nim` gets the new opcodes in its own
## `case` when the group is decoded, but it does not get a new dependency.
## Shared helpers that a second executor needs go down into
## `mcf5307/machine`, not sideways into `move.nim`.
##
## There is no supervisor and user stack split on ISA_A, so the context holds
## a single address register 7. `sp` is that one register. The context type
## lives in `decode_types` with the other shared types.
##
## The exception layout and the reset values are taken from the ColdFire
## Family Programmer's Reference Manual and the MCF5307 User's Manual, and
## from this project's own measurements.

import mcf5307/decode_types
import mcf5307/decode
import mcf5307/move
import mcf5307/alu
import mcf5307/logic
import mcf5307/control

# ---------------------------------------------------------------------------
# The instruction-cycle costs.
#
# These are nominal. The per-instruction cycle budget on serial MCF5307
# silicon is not settled, so no exact cost is asserted anywhere. The only
# property asserted is that `mcf5307_exec` returns a non-zero count.

const
  fetchCycles = 2'u32   ## one 16-bit instruction fetch
  nopCycles = 2'u32     ## NOP on the execution pipe

# ---------------------------------------------------------------------------
# Core lifecycle.
#
# The context is opaque to every caller: C sees `mcf5307_ctx` and never its
# layout. It is a Nim `ref` because `mcf5307_create` allocates it, and
# allocation happens only inside `mcf5307_create`, never inside
# `mcf5307_exec`.

proc mcf5307_create*(user: pointer; rd: Mcf5307ReadFn; wr: Mcf5307WriteFn;
                     iack: Mcf5307IackFn): MCF5307Ctx
    {.exportc: "mcf5307_create", cdecl, dynlib.} =
  ## Allocate the context and store the board callbacks. This is the one
  ## place the core allocates.
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

# ---------------------------------------------------------------------------
# The instruction dispatch.

proc step(ctx: MCF5307Ctx): uint32 =
  ## Execute one instruction: fetch, decode, and either execute it or halt.
  ## Returns the cycles spent. Halts with `fault` set on a bus fault or an
  ## illegal instruction; halts without `fault` on a recognized opcode whose
  ## semantics are not yet implemented.
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
  # The board returns the fetch in the low 16 bits. The opcode word is that
  # narrowed value, and the executors take it at its own width.
  let opWord = uint16(word and 0xFFFF'u32)
  let decoded = decodeWord(opWord)
  ctx.pc = ctx.pc + fetchCycles
  case decoded.op
  of opNop:
    result = fetchCycles + nopCycles
  of opMove, opMovea, opMoveq, opMovem, opLea, opPea, opLink, opUnlk:
    # `moveFamily` executes the instruction
    # and halts the context with `fault` on an illegal encoding or an
    # illegal effective address.
    result = fetchCycles + moveFamily(ctx, opWord, decoded)
  of opAddq, opSubq,
     opAdd, opSub, opAdda, opSuba,
     opAddi, opSubi, opAddx, opSubx,
     opClr, opExt, opExtb, opNeg, opNegx,
     opMulu, opMuls, opDivu, opDivs:
    # `aluFamily` executes the
    # instruction and halts the context with `fault` on an illegal size, an
    # illegal effective address or a divide by zero.
    result = fetchCycles + aluFamily(ctx, opWord, decoded)
  of opAnd, opOr, opEor,
     opAndi, opOri, opEori,
     opNot,
     opBtst, opBchg, opBclr, opBset,
     opAsl, opAsr, opLsl, opLsr:
    # The logic, bit-operation and shift group. `logicFamily` executes
    # the instruction and halts the context with `fault` on an illegal size or
    # an illegal effective address - a memory shift, a byte or word form of
    # anything in the group, and a bit operation whose static form names an
    # operand only the dynamic form may reach.
    result = fetchCycles + logicFamily(ctx, opWord, decoded)
  of opBcc, opBra, opBsr,
     opScc, opTst,
     opCmp, opCmpa, opCmpi,
     opJmp, opJsr, opRts, opRte, opTrap:
    # The control-flow and comparison group (CPU-10). `controlFamily` executes
    # the instruction and halts the context with `fault` on an illegal size, an
    # illegal effective address, a 32-bit branch displacement - which is ISA_B
    # and not on this part - or an exception frame whose format field is not
    # one of the four the part writes.
    result = fetchCycles + controlFamily(ctx, opWord, decoded)
  of opExg, opSwap, opTas, opNbcd:
    # The `Operation` enum names every opcode the later instruction-group
    # tasks decode. Their execution semantics arrive with those tasks. Until
    # then exec halts rather than pretend to have executed them. `halted` is
    # set and `fault` is not, because the encoding is valid and only the
    # semantics are absent.
    #
    # NO ARM OF `decodeWord` PRODUCES ANY OF THESE FOUR TODAY, and the arm is
    # kept rather than deleted because the enum members are reachable through
    # `eaLegalityFor` and a `case` over `Operation` must be exhaustive.
    #
    # THE REASON IS NOT THE SAME FOR ALL FOUR, AND ONE OF THEM IS A DEFECT.
    #
    #   `opExg`, `opTas`, `opNbcd` - NOT ON THIS PART. Table 3-7, pages 3-23
    #   to 3-25, carries no EXG, TAS or NBCD row, Table 3-12, page 3-27, none
    #   either, and `m68k-elf-as -mcpu=5307` REJECTS `exg %d0,%d1`, `tas %d0`
    #   and `nbcd %d0`. Section 3.9, page 3-21, names BCD among the removed
    #   groups, which is NBCD; it does not name EXG or TAS, whose absence is
    #   the tables' and the assembler's. Nothing decodes them because there is
    #   nothing to decode. This is a property of the part.
    #
    #   `opSwap` - ON THIS PART, AND UNREACHABLE BECAUSE THIS CODE EATS IT.
    #   SWAP IS NOT REMOVED: Table 3-7, page 3-25, carries the row
    #   `SWAP | Dn | 16 | MSW of Dn <-> LSW of Dn`, Table 3-12, page 3-27,
    #   carries a `swap Dx` row at 1(0/0), and `m68k-elf-as -mcpu=5307`
    #   assembles `swap %d0` to `4840` and `swap %d7` to `4847`.
    #   `decode.nim`'s PEA arm matches `word and 0xFFC0 == 0x4840`, which spans
    #   `4840`-`487f` and so SWALLOWS ALL EIGHT SWAP ENCODINGS. Measured
    #   against the decoder: `4840`, `4841` and `4847` all come back
    #   `op=opPea, ea.mode=eaDn`, and `eaLegalityFor(opPea)` is control
    #   addressing, which excludes `Dn` - so every `swap` on this core faults
    #   as an illegal PEA operand instead of executing.
    #
    #   THAT IS A LIVE DEFECT, NOT A GAP AWAITING A LATER TASK. It is CPU-7's
    #   code, pre-existing at commit a124077, and it is filed and repaired as
    #   its own task - NOT here, and NOT by this arm. Until it is fixed,
    #   "`opSwap` is not produced" must be read as "the decoder is wrong",
    #   because the alternative reading - that the part has no SWAP - is
    #   contradicted by both tables and by the assembler.
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
  ## halts (a fault, an illegal instruction, or a recognized opcode that has
  ## no executor yet).
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
