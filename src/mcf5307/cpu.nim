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
# The cycle counts, and why nothing checks them. Stated once here; the four
# executor modules point at this block instead of repeating it.
#
# `mcf5307_exec` saturates at its budget, and that is the whole mechanism. The
# conformance runner passes 1 (`kBudget`, `conformance/runner.cpp`) and so do
# `t_alu`, `t_move`, `t_logic` and `t_control`, so the return is 1 for an
# instruction that ran and 0 for one that trapped and carries no count at all.
# Where a `cycles` field is filled at all, flattened to 0-or-1 it reads like a
# counter and is not one. The assertions that read an unflattened return -
# `t_ea_masks` (3), (4) and (5) - assert its direction and never its value: a
# legal operand costs something and a trapped one costs nothing. No cycle count
# is asserted anywhere.
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
