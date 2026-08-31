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
# `machine` is imported for one procedure, `takePendingWriteFault`, and adds no
# import cycle: `machine` is below every executor and imports none of them.
# `machine.nim`'s `writeMem` states why the take belongs at the instruction
# boundary, which is here.
import mcf5307/machine
import mcf5307/move
import mcf5307/alu
import mcf5307/logic
import mcf5307/control
import mcf5307/irq

# ---------------------------------------------------------------------------
# The cycle counts, and why nothing checks them. Stated once here; the four
# executor modules point at this block instead of repeating it.
#
# `mcf5307_exec` saturates at its budget, and that is the whole mechanism. The
# conformance runner passes 1 (`kBudget`, `conformance/runner.cpp`) and so do
# the executor suites, so the return is 1 for an instruction that ran and 0 for
# one that trapped and carries no count at all. Flattened to 0-or-1 it reads
# like a counter and is not one.
#
# How to read any number here or in an executor. None was derived from the
# manual, and the split into a fetch cost plus an executor return is this
# core's own: Tables 3-9 to 3-16, folios 3-26 to 3-30, time whole instructions
# and decompose nothing. Where a return happens to equal a cell of those tables
# the site names the cell; where the manual carries no row for the instruction
# the site says so. A return with no comment makes no claim about the tables.
#
# Cycle accuracy, if it is ever wanted, needs a new return type rather than
# better constants: a saturating `uint32` cannot report a count the caller
# bounded.

const
  fetchCycles = 2'u32   ## one 16-bit instruction fetch
  nopCycles = 2'u32     ## NOP on the execution pipe. The pair sums to 4 where
                        ## Table 3-14, folio 3-29, times `nop` at 3(0/0) whole.

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
  ##
  ## This is a C ABI entry point (`include/mcf5307.h`), so the argument is
  ## whatever the caller passed and not something the type system has vouched
  ## for. An entry point that faults on nil while its neighbour returns is a
  ## contract the header cannot state.
  if ctx.isNil:
    return
  ctx.sp = initialSp
  ctx.pc = initialPc
  ctx.sr = 0x2700'u32
  ctx.halted = false
  ctx.fault = false
  # A reset discards a store's recorded access error rather than carrying it
  # into the reset handler. The capture names a program counter and a status
  # register of the program this call has just ended; taking it after the reset
  # would stack a frame describing a machine that no longer exists.
  ctx.pendingWriteFault = false
  ctx.pendingFaultStatus = 0'u32
  ctx.pendingStackedSr = 0'u32
  ctx.pendingStackedPc = 0'u32
  # The reset exception is an exception, so its first instruction is inhibited
  # like every other handler's. Table 3-1's closing paragraph, folio 3-13:
  # "ColdFire processors inhibit sampling for interrupts during the first
  # instruction of all exception handlers." Section 3.5.11, folio 3-17, is the
  # reset exception's own entry, so the instruction at `initialPc` is the first
  # instruction of an exception handler and that sentence governs it.
  #
  # The write has to be here because this call does not route through
  # `takeException`, which is where every other exception in this core acquires
  # the field.
  #
  # `true` and not `false`: the reset acquires its own inhibition, and the
  # instruction that spends it is the one this call has just installed. With
  # `false` the core could take an interrupt at the reset program counter
  # before retiring a single instruction, which is the state the sentence above
  # forbids.
  ctx.atHandlerEntry = true
  # The level-7 edge latch is cleared and the pin is then re-observed;
  # `resetInterruptEdge` in `mcf5307/irq.nim` carries the argument. The board's
  # presentation survives - it is the board's state and this call has no newer
  # answer for it. What does not survive is the core's own edge history, which
  # is why a level 7 still asserted across this call is armed again and one
  # whose pin has been released is not.
  resetInterruptEdge(ctx)

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
  ctx.pc = ctx.pc + insWordBytes
  case decoded.op
  of opNop:
    result = fetchCycles + nopCycles
  of opMove, opMovea, opMoveq, opMovem, opLea, opPea, opLink, opUnlk,
     opSwap:
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
    # The control-flow and comparison group. `controlFamily` executes
    # the instruction and halts the context with `fault` on an illegal size, an
    # illegal effective address, a 32-bit branch displacement - which is ISA_B
    # and not on this part - or an exception frame whose format field is not
    # one of the four the part writes.
    result = fetchCycles + controlFamily(ctx, opWord, decoded)
  of opExg, opTas, opNbcd:
    # `halted` is set and `fault` is not, because the encoding is valid and
    # only the semantics are absent.
    #
    # No arm of `decodeWord` produces any of these three, and the arm is kept
    # rather than deleted because the enum members are reachable through
    # `eaLegalityFor` and a `case` over `Operation` must be exhaustive.
    #
    # `opExg`, `opTas`, `opNbcd` are not on this part. Table 3-7, pages 3-23
    # to 3-25, carries no EXG, TAS or NBCD row, Table 3-12, page 3-27, none
    # either, and `m68k-elf-as -mcpu=5307` rejects `exg %d0,%d1`, `tas %d0`
    # and `nbcd %d0`. Section 3.9, page 3-21, names BCD among the removed
    # groups, which is NBCD; it does not name EXG or TAS, whose absence is
    # the tables' and the assembler's.
    #
    # SWAP is not in this arm, though it looks like it belongs: Table 3-7,
    # page 3-25, carries `SWAP | Dn | 16 | MSW of Dn <-> LSW of Dn`, Table
    # 3-12, page 3-27, times `swap Dx` at 1(0/0), and section 3.9's removed
    # list does not name it. It is dispatched with the data-movement group
    # above. `decode.nim` must test `0xFFF8`/`0x4840` ahead of its PEA arm,
    # whose `0xFFC0` mask spans `4840`-`487f` and would otherwise swallow all
    # eight SWAP encodings; `tests/t_move.nim` fails if the decoder stops
    # producing `opSwap`.
    ctx.halted = true
    result = 0
  of opIllegal:
    ctx.fault = true
    ctx.halted = true
    result = 0
  # The instruction boundary. A store that faulted recorded the access error
  # and let the instruction finish; this is where the vector is taken. It sits
  # after every arm and not inside the arms that write memory, so the rule is a
  # property of the boundary rather than a list of executors that remembered
  # it. `machine.nim`'s `writeMem` carries the manual reading.
  takePendingWriteFault(ctx)

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
    # The interrupt is sampled at an instruction boundary and at no other
    # point. User's Manual section 7.6, folio 7-23: "The MCF5307 device takes
    # an interrupt exception for a pending interrupt within one instruction
    # boundary after processing any other pending exception with a higher
    # priority. Thus, the MCF5307 device executes at least one instruction in
    # an interrupt exception handler before recognizing another interrupt
    # request." Table 3-1's closing paragraph, folio 3-13, states the same
    # rule for every exception handler: "ColdFire processors inhibit sampling
    # for interrupts during the first instruction of all exception handlers."
    #
    # `atHandlerEntry` is what implements both sentences, and the shape of this
    # loop is not. `takeException` sets that field on every exception it
    # completes and the clear below spends it, which buys one instruction of
    # inhibition per exception and no more. The loop cannot supply it: an
    # exception taken inside `step` returns here with the machine at a
    # handler's entry and `halted` false, so the sample at the top of the next
    # iteration would land on an instruction that has not run.
    #
    # The clear sits between the sample and the `step`, and each of its two
    # neighbours is a reason for that position. Ahead of `step` it cannot wipe
    # the field an exception taken in this iteration is about to set, so the
    # inhibition reaches the iteration that owns it. Behind the sample it also
    # spends the field that this iteration's own take set - which is correct,
    # because that take's handler runs its first instruction in the `step`
    # below, in this same iteration, and inhibiting the next sample as well
    # would cost the handler a second instruction the manual does not give it.
    # The reset's own inhibition is spent by this same clear and does not add a
    # second: the reset installs the instruction that spends it.
    #
    # The take costs no cycles: no cycle count in this core came from the
    # manual's timing tables, so an invented entry cost would be a number with
    # no source. `takeInterrupt` is bounded by construction: it raises the mask
    # to the level it took and clears the level-7 latch, so the next sample of
    # the same presentation returns false.
    if not ctx.atHandlerEntry:
      if takeInterrupt(ctx):
        if ctx.halted:
          break
    ctx.atHandlerEntry = false
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
