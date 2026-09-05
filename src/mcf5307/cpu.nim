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
## A shared helper a second executor needs goes down into `mcf5307/machine`,
## not sideways into another executor.
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
import mcf5307/movec
import mcf5307/irq
# The one-time runtime latch. `mcf5307_create` reads it and allocates nothing
# behind an abandoned one; `mcf5307/latch.nim` states why that refusal is the
# mechanism and the status return is only the advice.
import mcf5307/latch

# ---------------------------------------------------------------------------
# The cycle counts, and why nothing checks them. Stated once here; the
# executor modules point at this block instead of repeating it.
#
# `mcf5307_exec` reports the cost of everything that ran, and may therefore
# return more than the budget it was given. The loop tests the budget only
# before a step, so the last instruction of a call has already retired when the
# budget is found to be spent; there is nothing left to decline. A caller that
# passes a budget of 1 gets the whole cost of the one instruction that ran -
# `nopCycles + fetchCycles` for a NOP - and 0 for one that trapped.
#
# The overrun is bounded by one instruction and by nothing else. The return is
# at most `maxCycles` plus the cost of the single instruction that crossed the
# budget, so a caller carrying the difference forward carries a bounded
# quantity.
#
# The return is not clamped to the budget: a clamp gives a consumer computing
# `spent - want` a floor-of-zero difference that can never be anything but
# zero, and hides an overrun the machine really took. It is not a
# cycle-accurate count either - the numbers below and in the executors are this
# core's own - but it is the sum of them.
#
# How to read any number here or in an executor. None was derived from the
# manual, and the split into a fetch cost plus an executor return is this
# core's own: the manual's timing tables time whole instructions and decompose
# nothing.
#
# Cycle accuracy, if it is ever wanted, needs better constants and not a new
# return type. The return now carries the sum the executors produced, so the
# channel is there and it is the numbers going into it that have no source.

const
  fetchCycles = 2'u32   ## one 16-bit instruction fetch
  nopCycles = 2'u32     ## NOP on the execution pipe

# ---------------------------------------------------------------------------
# Core lifecycle.
#
# The context is opaque to every caller: C sees `mcf5307_ctx` and never its
# layout. It is a Nim `ref` because allocation must happen only inside
# `mcf5307_create`, never inside `mcf5307_exec`.

proc mcf5307_create*(user: pointer; rd: Mcf5307ReadFn; wr: Mcf5307WriteFn;
                     iack: Mcf5307IackFn): MCF5307Ctx
    {.exportc: "mcf5307_create", cdecl, dynlib.} =
  ## Allocate the context and store the board callbacks. This is the one
  ## place the core allocates.
  ##
  ## It refuses when the runtime was abandoned, and that refusal is what
  ## replaces an abort. C lets a caller drop a return value, so a status
  ## nobody is obliged to read cannot carry the guarantee the abort carried.
  ## This check does: `new(result)` needs the Nim
  ## allocator, the allocator needs the runtime, and a nil context is a value
  ## every other call in `include/mcf5307.h` already documents an answer for.
  ## A caller that ignored the status gets a library that does nothing.
  if runtimeAbandoned(runtimeLatch):
    return nil
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
  ## value. `0x2700` is the supervisor, full-mask reset value on this part.
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
  # The control registers, to the values the manual gives them at reset.
  #
  # The MCF5307 User's Manual gives the vector base
  # register `$00000000` at reset (section 3.7's reset exception) and says a
  # hardware reset clears the CACR (section 5.5). The ACRs, the RAMBARs and the
  # MBAR are weaker: the manual guarantees only that the enable or valid bit is
  # forced to zero and calls the remaining bits unaffected or uninitialised, so
  # no full reset value is documented for them. Section 5.6 states the stronger
  # reading for the ACRs - reset "places 0's in all CACR and ACR bits" - and
  # the manual therefore disagrees with itself about those two.
  #
  # Zero is chosen for all of them. Zero satisfies every documented
  # constraint, including the weak ones: the enable
  # and valid bits are the low bit or bit 15 of their registers and zero clears
  # them. Leaving the undocumented bits at whatever the previous run wrote
  # would make this core's reset depend on its own history, which is a
  # divergence a host cannot see and cannot reproduce.
  ctx.vbr = 0'u32
  ctx.cacr = 0'u32
  ctx.acr0 = 0'u32
  ctx.acr1 = 0'u32
  ctx.rambar0 = 0'u32
  ctx.rambar1 = 0'u32
  ctx.mbar = 0'u32

  # A reset discards a store's recorded access error rather than carrying it
  # into the reset handler. The capture names a program counter and a status
  # register of the program this call has just ended; taking it after the reset
  # would stack a frame describing a machine that no longer exists.
  ctx.pendingWriteFault = false
  ctx.pendingFaultStatus = 0'u32
  ctx.pendingStackedSr = 0'u32
  ctx.pendingStackedPc = 0'u32
  # The instruction at `initialPc` is the first instruction of an exception
  # handler, and interrupt sampling is inhibited during the first instruction of
  # every exception handler. The write has to be here because this call does not
  # route through `takeException`, which is where every other exception in this
  # core acquires the field.
  #
  # `true` and not `false`: the reset acquires its own inhibition, and the
  # instruction that spends it is the one this call has just installed. With
  # `false` the core could take an interrupt at the reset program counter before
  # retiring a single instruction.
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
    # one the part writes.
    result = fetchCycles + controlFamily(ctx, opWord, decoded)
  of opMovec:
    # `movecFamily` halts the context without setting `fault` on a
    # control-register number this part does not carry.
    result = fetchCycles + movecFamily(ctx, opWord, decoded)
  of opMoveFromSr, opMoveFromCcr, opMoveToCcr, opMoveToSr:
    result = fetchCycles + systemControlFamily(ctx, opWord, decoded)
  of opExg, opTas, opNbcd:
    # EXG, TAS and NBCD are not on this part, so nothing decodes them. The arm
    # is kept rather than deleted because the enum members are reachable
    # through `eaLegalityFor` and a `case` over `Operation` must be exhaustive.
    # `halted` is set and `fault` is not, because an encoding that never
    # arrives here is not an illegal one.
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
  ## Run until at least `max_cycles` cycles have been spent and return the
  ## cycles actually spent, which may exceed `max_cycles` by up to the cost of
  ## one instruction: no instruction is abandoned once it has started. The loop
  ## stops when the budget is reached, or earlier when the machine halts (a
  ## fault, an illegal instruction, or a recognized opcode with no implemented
  ## semantics). The block at the head of this module is the contract.
  if ctx.isNil or ctx.halted:
    return 0
  var spent = 0'u32
  while spent < maxCycles and not ctx.halted:
    # The part takes a pending interrupt within one instruction boundary
    # after any higher-priority exception, so it executes at least
    # one instruction of an interrupt handler before recognizing another
    # request; and sampling is inhibited during the first instruction of every
    # exception handler.
    #
    # `atHandlerEntry` is what implements both sentences, and the shape of this
    # loop is not. `takeException` sets that field on every exception it
    # completes and the clear below spends it, which buys one instruction of
    # inhibition per exception and no more. The loop cannot supply it: an
    # exception taken inside `step` returns here with the machine at a
    # handler's entry and `halted` false, so the sample at the top of the next
    # iteration would land on an instruction that has not run.
    #
    # THE SAMPLE AND THE `step` BELOW ARE ONE ITERATION. Making the take
    # `continue` instead is an equivalent loop rather than a defect: the take's
    # own `atHandlerEntry` inhibits the sample the extra iteration would make.
    # What the one iteration still buys is stated at the clear below.
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
    # The instruction has already retired, so its whole cost is spent. The
    # `while` above is the only place the budget is tested, and it is tested
    # before a step and never after one: nothing here can un-run the step that
    # has just happened, so a clamp at `maxCycles` would report less than the
    # machine did. See the block at the head of this module for what that costs
    # a caller.
    spent = spent + cost
  result = spent
