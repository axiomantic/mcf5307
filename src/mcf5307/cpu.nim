## `cpu` - the core lifecycle and the instruction dispatch of the ColdFire
## ISA_A core.
##
## THIS MODULE IS THE TOP OF THE CORE. It owns the part of the `mcf5307_*`
## ABI that runs the machine: the lifecycle calls `mcf5307_create`,
## `mcf5307_destroy` and `mcf5307_reset`, the private `step` procedure, and
## `mcf5307_exec` itself.
##
## THE LAYERING. `step` decodes one word and then calls the executor of the
## instruction group that the word belongs to. It is therefore the one place
## that must know both the decoder and every executor:
##
##     decode_types            the shared types and the EA legality table
##        ^          ^
##     decode      move (and later alu, logic, control)
##        ^          ^
##            cpu               this module
##
## `decode` and `move` are level-2 siblings. Neither imports the other.
## Keeping `step` here rather than in `decode` is what stops the decoder
## depending on an executor: that inversion would add one import to the
## decoder for each new instruction group.
##
## TO ADD AN INSTRUCTION GROUP: write the new executor module beside
## `move.nim` and `alu.nim`, add one `import` line here, and add one arm to
## the `case decoded.op` below. A shared helper a second executor needs goes
## DOWN into `mcf5307/machine`, not sideways into another executor.
##
## THE ONE A7. There is no supervisor and user stack split on ISA_A, so the
## context holds a single address register 7. `sp` is that one register.
## The context type lives in `decode_types` with the other shared types.
##
## MIT licensed and clean-room with respect to GPL and LGPL code. The
## exception layout and the reset values are facts about Motorola silicon;
## they are taken from the ColdFire Family Programmer's Reference Manual and
## the MCF5307 User's Manual and from this project's own measurements.

import mcf5307/decode_types
import mcf5307/decode
import mcf5307/move
import mcf5307/alu
import mcf5307/logic
import mcf5307/control
import mcf5307/movec
import mcf5307/irq

# ---------------------------------------------------------------------------
# THE CYCLE COUNTS, AND WHY NOTHING CHECKS THEM. Stated once here; the executor
# modules point at this block instead of repeating it.
#
# `mcf5307_exec` REPORTS THE COST OF EVERYTHING THAT RAN, AND MAY THEREFORE
# RETURN MORE THAN THE BUDGET IT WAS GIVEN. The loop tests the budget only
# BEFORE a step, so the last instruction of a call has already retired when the
# budget is found to be spent; there is nothing left to decline. A caller that
# passes a budget of 1 gets the whole cost of the one instruction that ran -
# `nopCycles + fetchCycles` for a NOP - and 0 for one that trapped.
#
# THE OVERRUN IS BOUNDED BY ONE INSTRUCTION AND BY NOTHING ELSE. The return is
# at most `maxCycles` plus the cost of the single instruction that crossed the
# budget, so a caller carrying the difference forward carries a bounded
# quantity. `tests/t_exec_budget.nim` pins the exact return for every budget in
# a sweep, and pins it against a cost it MEASURES rather than transcribes.
#
# WHY IT IS NOT CLAMPED, WHICH IT WAS. A clamp made the return no greater than
# the budget for every call, so a consumer computing `spent - want` got a
# floor-of-zero difference that could never be anything but zero, and an
# overrun the machine really took was invisible to it. The clamped return also
# flattened to 0-or-1 at a budget of 1, which reads like a counter and is not
# one. What is returned now is not a cycle-ACCURATE count either - the numbers
# below and in the executors are this core's own, and the paragraph after next
# says where they did not come from - but it is at least the sum of them.
#
# `fetchCycles` PRICES THE FETCH AND DOES NOT ADVANCE THE PROGRAM COUNTER. The
# pc advances by `insWordBytes`, a width in bytes that shares the value 2 with
# `fetchCycles` by arithmetic accident. `insWordBytes` is declared in
# `decode_types.nim`, not here, because it is not a cycle count.
#
# THE TWO PC SITES ARE ONE CONSTANT, AND THAT COUPLING CAN HIDE AN ERROR. Both
# `step` below and `fetchExt` in `machine.nim` advance the pc by that constant,
# so a wrong value moves the opcode word and every extension word TOGETHER and
# the two errors can cancel.
#
# HOW TO READ ANY NUMBER HERE OR IN AN EXECUTOR. None was derived from the
# manual, and the split into a fetch cost plus an executor return is this
# core's own: the manual's timing tables time WHOLE instructions and decompose
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
# layout. It is a Nim `ref` because allocation must happen ONLY inside
# `mcf5307_create`, never inside `mcf5307_exec`.

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
  ## value. `0x2700` is the supervisor, full-mask reset value on this part.
  ##
  ## THE NIL GUARD IS HERE FOR THE REASON `mcf5307_set_irq` HAS ONE: this is a
  ## C ABI entry point, so the argument is whatever the caller passed and NOT
  ## something the type system has vouched for. An entry point that faults on
  ## nil while its neighbour returns is a contract the header cannot state.
  if ctx.isNil:
    return
  ctx.sp = initialSp
  ctx.pc = initialPc
  ctx.sr = 0x2700'u32
  ctx.halted = false
  ctx.fault = false
  # THE CONTROL REGISTERS, TO THE VALUES THE MANUAL GIVES THEM AT RESET.
  #
  # TWO OF THE SEVEN ARE STATED OUTRIGHT AND FIVE ARE NOT, AND THE DIFFERENCE
  # IS WHY THIS COMMENT EXISTS. The MCF5307 User's Manual gives the vector base
  # register `$00000000` at reset (section 3.7's reset exception) and says a
  # hardware reset CLEARS the CACR (section 5.5). The ACRs, the RAMBARs and the
  # MBAR are weaker: the manual guarantees only that the enable or valid bit is
  # forced to zero and calls the remaining bits unaffected or uninitialised, so
  # no full reset value is documented for them. Section 5.6 states the stronger
  # reading for the ACRs - reset "places 0's in all CACR and ACR bits" - and
  # the manual therefore disagrees with itself about those two.
  #
  # ZERO IS CHOSEN FOR ALL FIVE, AND THE ALTERNATIVE IS WHAT DECIDES IT. Zero
  # satisfies every documented constraint, including the weak ones: the enable
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
  # THE RESET EXCEPTION IS AN EXCEPTION, SO ITS FIRST INSTRUCTION IS INHIBITED
  # LIKE EVERY OTHER HANDLER'S. The instruction at `initialPc` is the first
  # instruction of an exception handler, and interrupt sampling is inhibited
  # during the first instruction of every exception handler.
  #
  # THE WRITE HAS TO BE HERE BECAUSE THIS CALL DOES NOT ROUTE THROUGH
  # `takeException`, which is where every other exception in this core acquires
  # the field.
  #
  # `true` AND NOT `false`, AND THE DISTINCTION IS BETWEEN A CARRIED INHIBITION
  # AND AN ACQUIRED ONE. A STALE inhibition - one skipping a sample on behalf of
  # a handler this call has already left - would be wrong. This is not one: the
  # reset acquires its OWN, and the instruction that spends it is the one this
  # call has just installed. With `false` the core could take an interrupt at
  # the reset program counter before retiring a single instruction, which is the
  # state the sentence above forbids. `tests/t_claims.cmake` registers this
  # line's mutation as `reset_inhibit_suite_t_irq` and refutes when it moves.
  ctx.atHandlerEntry = true
  # THE LEVEL-7 EDGE LATCH IS CLEARED AND THE PIN IS THEN RE-OBSERVED.
  # `resetInterruptEdge` in `mcf5307/irq.nim` carries the whole argument.
  # THE BOARD'S PRESENTATION SURVIVES: it is the board's
  # state and this call has no newer answer for it. What does not survive is the
  # core's own edge history, which is why a level 7 still asserted across this
  # call is armed again and one whose pin has been released is not.
  resetInterruptEdge(ctx)

# ---------------------------------------------------------------------------
# The instruction dispatch.

proc step(ctx: MCF5307Ctx): uint32 =
  ## Execute one instruction: fetch, decode, and either execute it or halt.
  ## Returns the cycles spent. Halts with `fault` set on a bus fault or an
  ## illegal instruction; halts without `fault` on a recognized opcode with no
  ## implemented semantics.
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
    # The data-movement group. `moveFamily` executes the instruction
    # and halts the context with `fault` on an illegal encoding or an
    # illegal effective address.
    result = fetchCycles + moveFamily(ctx, opWord, decoded)
  of opAddq, opSubq,
     opAdd, opSub, opAdda, opSuba,
     opAddi, opSubi, opAddx, opSubx,
     opClr, opExt, opExtb, opNeg, opNegx,
     opMulu, opMuls, opDivu, opDivs:
    # The integer-arithmetic group. `aluFamily` executes the
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
    # `MOVEC`. `movecFamily` fetches the extension word, takes the
    # privilege violation in user state, and halts the context WITHOUT `fault`
    # on a control-register number this part does not carry.
    result = fetchCycles + movecFamily(ctx, opWord, decoded)
  of opMoveFromSr, opMoveFromCcr, opMoveToCcr, opMoveToSr:
    result = fetchCycles + systemControlFamily(ctx, opWord, decoded)
  of opExg, opTas, opNbcd:
    # EXG, TAS AND NBCD ARE NOT ON THIS PART, so nothing decodes them. The arm
    # is kept rather than deleted because the enum members are reachable
    # through `eaLegalityFor` and a `case` over `Operation` must be exhaustive.
    # `halted` is set and `fault` is not, because an encoding that never
    # arrives here is not an illegal one.
    #
    # AN UNREACHABLE-OPCODE NOTE IS THE SHAPE THAT MAKES A LIVE DEFECT LOOK
    # LIKE A PROPERTY OF THE SILICON, so a sweep confirming that no arm
    # produces an opcode is not evidence that the part lacks it.
    ctx.halted = true
    result = 0
  of opIllegal:
    ctx.fault = true
    ctx.halted = true
    result = 0

proc mcf5307_exec*(ctx: MCF5307Ctx; maxCycles: uint32): uint32
    {.exportc: "mcf5307_exec", cdecl, dynlib.} =
  ## Run until at least `max_cycles` cycles have been spent and return the
  ## cycles actually spent, WHICH MAY EXCEED `max_cycles` by up to the cost of
  ## one instruction: no instruction is abandoned once it has started. The loop
  ## stops when the budget is reached, or earlier when the machine halts (a
  ## fault, an illegal instruction, or a recognized opcode with no implemented
  ## semantics). The block at the head of this module is the contract.
  if ctx.isNil or ctx.halted:
    return 0
  var spent = 0'u32
  while spent < maxCycles and not ctx.halted:
    # THE INTERRUPT IS SAMPLED AT AN INSTRUCTION BOUNDARY AND AT NO OTHER
    # POINT. The part takes a pending interrupt within one instruction
    # boundary after any higher-priority exception, so it executes at least
    # one instruction of an interrupt handler before recognizing another
    # request; and sampling is inhibited during the first instruction of every
    # exception handler.
    #
    # `atHandlerEntry` IS WHAT IMPLEMENTS BOTH SENTENCES, AND THE SHAPE OF THIS
    # LOOP IS NOT. `takeException` sets that field on every exception it
    # completes and the clear below spends it, which buys one instruction of
    # inhibition per exception and no more. The second sentence needs exactly
    # that and the loop cannot supply it: an exception taken INSIDE `step`
    # returns here with the machine at a handler's entry and `halted` false,
    # so the sample at the top of the NEXT iteration would land
    # on an instruction that has not run.
    #
    # THE SAMPLE AND THE `step` BELOW ARE ONE ITERATION. Making the take
    # `continue` instead is an equivalent loop rather than a defect: the take's
    # own `atHandlerEntry` inhibits the sample the extra iteration would make.
    # What the one iteration still buys is stated at the clear below.
    #
    # THE CLEAR SITS BETWEEN THE SAMPLE AND THE `step`, AND EACH OF ITS TWO
    # NEIGHBOURS IS A REASON FOR THAT POSITION. Ahead of `step` it cannot wipe
    # the field an exception taken in this iteration is about to set, so the
    # inhibition reaches the iteration that owns it. Behind the sample it also
    # spends the field that THIS iteration's own take set - which is correct
    # and not an oversight, because that take's handler runs its first
    # instruction in the `step` below, IN THIS SAME ITERATION, and inhibiting
    # the next sample as well would cost the handler a second instruction the
    # manual does not give it. That is the one thing the single iteration is
    # still load-bearing for. THE RESET'S OWN INHIBITION IS SPENT BY THIS SAME
    # CLEAR and does not add a second: the reset installs the instruction that
    # spends it, so the clear is reached with no take of this iteration's own
    # to keep.
    #
    # IT COSTS NO CYCLES, AND THAT IS A REFUSAL TO CLAIM RATHER THAN A
    # MEASUREMENT. No cycle count in this core came from the manual's timing
    # tables, so an invented entry cost would be a
    # number with no source. `takeInterrupt` is bounded by construction: it
    # raises the mask to the level it took and clears the level-7 latch, so
    # the next sample of the same presentation returns false.
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
    # THE INSTRUCTION HAS ALREADY RETIRED, SO ITS WHOLE COST IS SPENT. The
    # `while` above is the only place the budget is tested, and it is tested
    # BEFORE a step and never after one: nothing here can un-run the step that
    # has just happened, so a clamp at `maxCycles` would report less than the
    # machine did. See the block at the head of this module for what that costs
    # a caller.
    spent = spent + cost
  result = spent
