## `cpu` - the core lifecycle and the instruction dispatch of the ColdFire
## ISA_A core. Design section 6.1.
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
## Before this module existed, `decode` held `step` and therefore imported
## `move`, which made the decoder depend on an executor. That inversion adds
## one import to the decoder for each new instruction group.
##
## TO ADD AN INSTRUCTION GROUP (tasks CPU-9 and CPU-10): write the new
## executor module beside `move.nim` and `alu.nim`, add one `import` line
## here, and add one arm to the `case decoded.op` below. `decode.nim` gets the
## new opcodes in its own `case` when the group is decoded, but it does not
## get a new dependency. CPU-8 IS THE PROOF THAT THE SHAPE HOLDS: adding the
## integer-arithmetic group cost exactly one module, one import here and one
## arm below, and `decode.nim`'s import list is still `{decode_types, ea}`.
## The shared helpers that a second executor needed went DOWN into
## `mcf5307/machine`, not sideways into `move.nim`.
##
## THE ONE A7. There is no supervisor and user stack split on ISA_A, so the
## context holds a single address register 7. `sp` is that one register.
## The context type lives in `decode_types` with the other shared types.
##
## MIT licensed and clean-room with respect to GPL and LGPL code. The
## exception layout and the reset values are facts about Motorola silicon;
## they are taken from the ColdFire Family Programmer's Reference Manual and
## the MCF5307 User's Manual (AGENTS.md section 11) and from this project's
## own measurements.

import mcf5307/decode_types
import mcf5307/decode
import mcf5307/move
import mcf5307/alu
import mcf5307/logic
import mcf5307/control
import mcf5307/irq

# ---------------------------------------------------------------------------
# THE CYCLE COUNTS, AND WHY NOTHING CHECKS THEM. Stated once here; the four
# executor modules point at this block instead of repeating it.
#
# `mcf5307_exec` SATURATES AT ITS BUDGET, and that is the whole mechanism. The
# conformance runner passes 1 (`kBudget`, `conformance/runner.cpp`) and so do
# `t_alu`, `t_move`, `t_logic` and `t_control`, so the return is 1 for an
# instruction that ran and 0 for one that trapped and carries no count at all.
# The `cycles` field of those four drivers is that return, and MOST OF THEIR
# TUPLES LEAVE IT OUT. Measured 2026-08-12 over the `let`-bound named-field
# tuple literals of the four, 24 of 86 carry a `cycles` member: `t_logic` 14 of
# 18, `t_alu` 8 of 28, `t_control` 2 of 22, and `t_move` 0 of 18, which fills
# the field and reads it in no assertion at all. `expectPc` in `t_alu` is one
# of the omitting sites. Where a tuple does carry it, flattened to 0-or-1 it
# reads like a counter and is not one. THREE assertions read a return not
# flattened to 0-or-1, and every one of them asserts its DIRECTION and never
# its value. `t_ea_masks` assertion (5) is `check(cycles > 0'u32, ...)` in
# `tests/t_ea_masks.nim`, over the `mcf5307_exec(ctx, 64'u32)` beside it and
# its budget of 64: EVERY non-zero return passes it, so it cannot tell 64
# from 1. It saturates as well - its board answers NOP to every fetch, and
# measured 2026-08-12 against this tree, with that assertion temporarily
# strengthened to `cycles == 64'u32`, the 4-cycle NOP fills the budget exactly
# and returns 64 while `nopCycles` at 1044 makes the 1046-cycle NOP take the
# saturation clause and return 64 AGAIN.
# Assertions (3) and (4) of the same file read a return that never entered
# `mcf5307_exec` at all - `runFamily` calls the family procs directly - and
# assert only that a legal operand costs something and a trapped one costs
# nothing. No cycle count is asserted anywhere.
#
# MEASURED 2026-08-12 AGAINST THIS TREE - the one where `step` advances the pc
# by `insWordBytes` and `fetchCycles` prices the fetch alone. EVERY non-zero
# cycle expression in `src/mcf5307` given a distinct wrong value in one build -
# 45 of them over 40 sites, 41..49 in `move`, 51..65 in `alu`, 71..79 in
# `logic`, 81..90 in `control` and 91 and 92 here. The census counts each ARM
# of an `if` expression and each COEFFICIENT of a sum separately, which is what
# makes `move` 9 over 8 sites and `logic` 9 over 7. Reach: 44 of the 45 appear
# as their own literal in the generated C of a fresh configure, the Nim
# transpile being a configure-time step; the forty-fifth is `nopCycles`, which
# is constant-folded and reaches the C only as the sum `fetchCycles +
# nopCycles` - `((NU32)183)` present, `((NU32)4)` absent. EVERY SUITE HELD ITS
# BASELINE: t_alu 165, t_ea_masks <caseTotalMustMatchTranscripts>, t_move 34,
# t_logic 74, t_control 168, t_sign_extend 10, conformance 23/32/48/82/185,
# ctest exit 8 with `abi_smoke` - which fails to LINK against the ABI symbols
# nothing implements yet - the one failure.
#
# THAT COUNT USED TO BE SPELLED HERE AS A NUMBER AND THE NUMBER WENT STALE.
# It read 13, and CPU-17 is the change that moved it: `mcf5307_set_irq` was the
# thirteenth and this task implements it. MEASURED 2026-08-13 against this
# tree, the link reports 12 - `isp1181_create`, `isp1181_destroy`,
# `isp1181_read`, `isp1181_rx`, `isp1181_state_load`, `isp1181_state_save`,
# `isp1181_state_size`, `isp1181_tick`, `isp1181_write`, `mcf5307_state_load`,
# `mcf5307_state_save` and `mcf5307_state_size` - and every one of the twelve
# belongs to CPU-18 or to chain B, so the figure moves again when they land.
# THE LESSON IS THE ONE THIS FILE ALREADY RECORDS 200 LINES BELOW: a stale
# sentence turns a repaired defect back into a documented invariant. What is
# written above is the SHAPE of the failure, which is what the surrounding
# measurement needs; the count is here, dated, and named as a thing that moves.
#
# THE `t_ea_masks` COLUMN NAMES A CONSTANT AND THE OTHERS SPELL A NUMBER, AND
# THAT ASYMMETRY IS DELIBERATE. `t_ea_masks` is the one suite whose total is
# GUARDED - `caseTotalMustMatchTranscripts`, declared once in
# `tests/t_ea_masks.nim` and held against the live count by block (18) of that
# file - and it is also the one that moves when a block is added there. A bare
# literal in this line went stale on exactly that event and no run could see it,
# because the copy sits in PRODUCTION SOURCE, which that guard does not count
# and cannot reach. Naming the constant is the only spelling here that cannot go
# silently wrong. The `opMovem` arm of `decode_types.nim` names it the same way
# and records the limit both share: this is TEXT IN A COMMENT, nothing links it
# to the symbol, and `src/` cannot import `tests/` to close that.
#
# A DATE IS NOT A TREE STATE, and this result is a property of the tree above
# rather than of the calendar. The SAME 45-value mutation applied to the tree
# at HEAD c374e8c, where `step` still advanced the pc by `fetchCycles`, reds 63
# unit cases - t_alu 27, t_move 7, t_logic 6, t_control 23 - and 120 corpus
# cases - 14, 13, 17 and 76 - measured 2026-08-12 by reconstructing that tree
# and rerunning. Any measurement recorded here names the tree it ran against
# and not only the day it ran.
#
# `fetchCycles` IS IN THAT POPULATION AND IS NOT SPECIAL. It used to advance
# the program counter as well as price the fetch, and a wrong value then red
# unit and corpus cases through the pc. The pc now advances by `insWordBytes`,
# a width in bytes sharing the value 2 by arithmetic accident, and measured
# 2026-08-12 `fetchCycles` alone at 1091 reds NOTHING - 0 unit cases, 0 corpus
# cases, every suite at its baseline.
#
# `insWordBytes` IS WHAT THE SUITE ACTUALLY GUARDS, and it is declared in
# `decode_types.nim`, not here, because it is not a cycle count. Its red count
# MOVES WITH THE WRONG VALUE, so a count quoted without its value does not
# reproduce. Measured 2026-08-12: 63 unit cases at 99, 63 at 3, 64 at 8 and 65
# at 4 - `t_logic` supplies the movement at 6, 6, 7 and 8 - against 120 corpus
# cases at all four.
#
# THE TWO PC SITES ARE NOW ONE CONSTANT, AND COUPLING THEM COST ONE CASE. Both
# `step` below and `fetchExt` in `machine.nim` advance the pc by that constant,
# so a wrong value moves the opcode word and every extension word TOGETHER and
# the two errors can cancel. Measured 2026-08-12 against the same tree with the
# two sites separate: the opcode site alone at 3 reds 64 unit cases where the
# shared constant reds 63, and the case that recovers is `t_logic`'s
# `andi.l #5,%d0 = 0 and sets Z`, whose displaced immediate still ANDs to zero.
# The extension site was never unguarded - separate and wrong alone at 6 it
# reds 8 unit cases and 36 corpus cases - so this change bought one name for
# one concept and not new coverage.
#
# HOW TO READ ANY NUMBER HERE OR IN AN EXECUTOR. None was derived from the
# manual, and the split into a fetch cost plus an executor return is this
# core's own: Tables 3-9 to 3-16, folios 3-26 to 3-30, time WHOLE instructions
# and decompose nothing. Where a return happens to EQUAL a cell of those tables
# the site names the cell; where the manual carries no row for the instruction
# the site says so. A RETURN WITH NO COMMENT MAKES NO CLAIM ABOUT THE TABLES.
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
# layout. It is a Nim `ref` because `mcf5307_create` allocates it and the
# design (design section 5.6, CPU-19) requires that allocation happen ONLY
# inside `mcf5307_create`, never inside `mcf5307_exec`.

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
  ##
  ## THE NIL GUARD IS HERE FOR THE REASON `mcf5307_set_irq` HAS ONE: this is a
  ## C ABI entry point (`include/mcf5307.h`), so the argument is whatever the
  ## caller passed and NOT something the type system has vouched for. The
  ## asymmetry between the two was not deliberate - `mcf5307_set_irq` acquired
  ## its guard when a case reached for one and this procedure was never asked -
  ## and an entry point that faults on nil while its neighbour returns is a
  ## contract the header cannot state.
  if ctx.isNil:
    return
  ctx.sp = initialSp
  ctx.pc = initialPc
  ctx.sr = 0x2700'u32
  ctx.halted = false
  ctx.fault = false
  # THE RESET EXCEPTION IS AN EXCEPTION, SO ITS FIRST INSTRUCTION IS INHIBITED
  # LIKE EVERY OTHER HANDLER'S. THIS IS A CITATION AND NOT AN INFERENCE. Table
  # 3-1's closing paragraph, folio 3-13 (PDF page 70): "ColdFire processors
  # inhibit sampling for interrupts during the first instruction of all
  # exception handlers." ALL exception handlers - and section 3.5.11, folio 3-17
  # (PDF page 74), is the RESET EXCEPTION's own entry, so the instruction at
  # `initialPc` is the first instruction of an exception handler and that
  # sentence governs it.
  #
  # THE WRITE HAS TO BE HERE BECAUSE THIS CALL DOES NOT ROUTE THROUGH
  # `takeException`, which is where every other exception in this core acquires
  # the field (`machine.nim` states why the write sits on that procedure's last
  # line).
  #
  # AN EARLIER REVISION WROTE `false` HERE AND ARGUED FOR IT, and the argument
  # was right about a different question. It read that the field "says the
  # program counter is at an exception handler's entry, and the line above has
  # just made the program counter something else", so carrying it over "would
  # skip one sample on behalf of a handler this call has already left". A STALE
  # inhibition would indeed be wrong. This is not one: the reset does not carry
  # a previous handler's inhibition over, it acquires its OWN, and the
  # instruction that spends it is the one this call has just installed. With
  # `false` the core could take an interrupt at the reset program counter before
  # retiring a single instruction, which is the state the sentence above forbids.
  # `tests/t_irq.nim` block 22 pins it in both directions, and it is not the
  # only block that does. `tests/t_claims.cmake` registers this line's mutation
  # as `reset_inhibit_suite_t_irq`, which carries the count and refutes when it
  # moves, so the coverage this comment names is held by that entry rather than
  # by this sentence. THE NUMBER IS DELIBERATELY NOT REPEATED HERE: a second
  # copy of it in `src/` is one nothing reads and nothing fails on, which is
  # the shape of second source this file guards against everywhere else.
  ctx.atHandlerEntry = true
  # THE LEVEL-7 EDGE LATCH IS CLEARED AND THE PIN IS THEN RE-OBSERVED, AND THAT
  # IS AN INFERENCE RATHER THAN A CITATION. `resetInterruptEdge` in
  # `mcf5307/irq.nim` carries the whole argument, including what the manuals do
  # and do not say about it. THE BOARD'S PRESENTATION SURVIVES: it is the board's
  # state and this call has no newer answer for it. What does not survive is the
  # core's own edge history, which is why a level 7 still asserted across this
  # call is armed again and one whose pin has been released is not.
  resetInterruptEdge(ctx)

# ---------------------------------------------------------------------------
# The instruction dispatch.

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
    # The data-movement group (CPU-7). `moveFamily` executes the instruction
    # and halts the context with `fault` on an illegal encoding or an
    # illegal effective address.
    result = fetchCycles + moveFamily(ctx, opWord, decoded)
  of opAddq, opSubq,
     opAdd, opSub, opAdda, opSuba,
     opAddi, opSubi, opAddx, opSubx,
     opClr, opExt, opExtb, opNeg, opNegx,
     opMulu, opMuls, opDivu, opDivs:
    # The integer-arithmetic group (CPU-8). `aluFamily` executes the
    # instruction and halts the context with `fault` on an illegal size, an
    # illegal effective address or a divide by zero.
    result = fetchCycles + aluFamily(ctx, opWord, decoded)
  of opAnd, opOr, opEor,
     opAndi, opOri, opEori,
     opNot,
     opBtst, opBchg, opBclr, opBset,
     opAsl, opAsr, opLsl, opLsr:
    # The logic, bit-operation and shift group (CPU-9). `logicFamily` executes
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
  of opExg, opTas, opNbcd:
    # The `Operation` enum names every opcode the later instruction-group
    # tasks decode. Their execution semantics arrive with those tasks. Until
    # then exec halts rather than pretend to have executed them. `halted` is
    # set and `fault` is not, because the encoding is valid and only the
    # semantics are absent.
    #
    # NO ARM OF `decodeWord` PRODUCES ANY OF THESE THREE, and the arm is
    # kept rather than deleted because the enum members are reachable through
    # `eaLegalityFor` and a `case` over `Operation` must be exhaustive.
    #
    # `opExg`, `opTas`, `opNbcd` - NOT ON THIS PART. Table 3-7, pages 3-23
    # to 3-25, carries no EXG, TAS or NBCD row, Table 3-12, page 3-27, none
    # either, and `m68k-elf-as -mcpu=5307` REJECTS `exg %d0,%d1`, `tas %d0`
    # and `nbcd %d0`. Section 3.9, page 3-21, names BCD among the removed
    # groups, which is NBCD; it does not name EXG or TAS, whose absence is
    # the tables' and the assembler's. Nothing decodes them because there is
    # nothing to decode. This is a property of the part.
    #
    # `opSwap` WAS THE FOURTH MEMBER OF THIS ARM AND IT HAS MOVED, BECAUSE
    # ITS PRESENCE HERE WAS A DEFECT WEARING THE COSTUME OF A PROPERTY.
    # SWAP is on this part - Table 3-7, page 3-25, carries `SWAP | Dn | 16 |
    # MSW of Dn <-> LSW of Dn`, Table 3-12, page 3-27, times `swap Dx` at
    # 1(0/0), section 3.9's removed list does not name it, and the shipped
    # G2 operating system executes it 339 times. It reached this arm only
    # because `decode.nim`'s PEA mask `word and 0xFFC0 == 0x4840` spans
    # `4840`-`487f` and swallowed all eight SWAP encodings before any
    # `opSwap` arm could be reached. `decode.nim` now tests `0xFFF8`/`0x4840`
    # AHEAD of the PEA arm, `move.nim` executes it, and it is dispatched
    # with the data-movement group above, which is the group Table 3-7 puts
    # it in.
    #
    # THE LESSON IS WORTH MORE THAN THE REPAIR. Gate 4.4's 65,536-word sweep
    # CONFIRMED the sentence that used to stand here - "no arm produces
    # `opSwap`" - and the sentence was true, for the wrong reason. A
    # measurement that verifies the LETTER of a claim can miss its MEANING,
    # and an unreachable-opcode note is exactly the shape that makes a live
    # defect look like a property of the silicon. What now keeps this
    # honest is not a comment: `tests/t_move.nim` fails if the decoder
    # stops producing `opSwap`.
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
    # THE INTERRUPT IS SAMPLED AT AN INSTRUCTION BOUNDARY AND AT NO OTHER
    # POINT. User's Manual section 7.6, folio 7-23: "The MCF5307 device takes
    # an interrupt exception for a pending interrupt within one instruction
    # boundary after processing any other pending exception with a higher
    # priority. Thus, the MCF5307 device executes at least one instruction in
    # an interrupt exception handler before recognizing another interrupt
    # request." Table 3-1's closing paragraph, folio 3-13, states the same
    # rule for every exception handler: "ColdFire processors inhibit sampling
    # for interrupts during the first instruction of all exception handlers."
    #
    # `atHandlerEntry` IS WHAT IMPLEMENTS BOTH SENTENCES, AND THE SHAPE OF THIS
    # LOOP IS NOT. `takeException` sets that field on every exception it
    # completes and the clear below spends it, which buys one instruction of
    # inhibition per exception and no more. The second sentence needs exactly
    # that and the loop cannot supply it: an exception taken INSIDE `step`
    # returns here with the machine at a handler's entry and `halted` false -
    # `execTrap` in `control.nim` is that path today and CPU-15's bus fault is
    # the next one - so the sample at the top of the NEXT iteration would land
    # on an instruction that has not run.
    #
    # THE SAMPLE AND THE `step` BELOW ARE ONE ITERATION, AND AN EARLIER
    # REVISION OF THIS BLOCK CLAIMED THAT SHAPE WAS WHAT IMPLEMENTED THE FIRST
    # SENTENCE: "making the take `continue` instead would sample again before
    # the handler had executed anything". THAT SENTENCE IS DELETED RATHER THAN
    # KEPT, because the field above made it false and a false sentence left
    # standing is how a repaired defect becomes a documented invariant.
    # MEASURED 2026-08-13 against this tree: adding that `continue` reds NO
    # case of `tests/t_irq.nim`, where against the tree before the field it
    # redded two. The take's own `atHandlerEntry` inhibits the sample the extra
    # iteration would make, so the edit is now an equivalent loop and not a
    # defect. What the one iteration still buys is stated at the clear below.
    # RE-MEASURED 2026-08-13 against the tree `mcf5307_reset` NOW leaves - the
    # one where the reset acquires its own inhibition, re-observes the level-7
    # pin and guards a nil context, and where `t_irq` carries 37 cases: still
    # 0 red. A measurement names the tree it ran against, and the reset change
    # moved the tree under both of the two in this block.
    #
    # THE SUITE IS NAMED ON THE SAME LINE AS THE FIGURE ON PURPOSE. This
    # sentence read "that suite carries 34 cases" until 2026-08-13, and the
    # second-source scan in `tests/tests_cpu.cmake` reads a suite name and a
    # count out of ONE LINE of `src/` - so a figure whose suite is named by an
    # ANAPHOR six lines up was invisible to it. That is not a wrapping the scan
    # can be widened to reach: no textual scan resolves "that suite". The
    # repair is to write the name where the number is, and the scan then holds
    # this figure against the generated driver.
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
    # still load-bearing for. MEASURED 2026-08-13, and RE-MEASURED the same day
    # against the tree `mcf5307_reset` now leaves: moving this line ahead of
    # the sample, so that a take keeps its own inhibition, reds the two cases
    # of `tests/t_irq.nim` that present a SECOND interrupt across a handler's
    # first instruction - blocks 15 and 17 - and no other. THE RESET'S OWN
    # INHIBITION IS SPENT BY THIS SAME CLEAR and does not add a third: the
    # reset installs the instruction that spends it, so the clear is reached
    # with no take of this iteration's own to keep.
    #
    # IT COSTS NO CYCLES, AND THAT IS A REFUSAL TO CLAIM RATHER THAN A
    # MEASUREMENT. The block at the head of this file records that no cycle
    # count in this core came from the manual's timing tables and that no
    # assertion in the tree reads one; an invented entry cost would be a
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
    if spent + cost > maxCycles:
      spent = maxCycles
      break
    spent = spent + cost
  result = spent
