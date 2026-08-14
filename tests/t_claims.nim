## `t_claims` - the OBSERVER half of the check that turns an unobservability
## claim into something a run can refute. Task CPU-28. Design section 5.2.2.
##
## WHAT A CLAIM OF UNOBSERVABILITY IS, AND WHY PROSE CANNOT CARRY ONE. A test
## file may record that some change to the core "changes no reachable state",
## that "no case here separates it", or that a mutant is equivalent. A FALSE
## claim of that shape READS EXACTLY LIKE A TRUE ONE: both are a sentence, and
## no run disagrees with either. `tests/t_irq.nim` carried such a sentence
## about moving the level-7 latch clear to just after `takeException`, and a
## review refuted it BY CONSTRUCTION - by writing the board the sentence had
## not considered.
##
## SO THE CLAIM NAMES A MUTATION AND THIS PROGRAM IS THE WITNESS. The registry
## in `tests/t_claims.cmake` defines each mutation as text; the driver applies
## it to a COPY of `src/`, compiles this program against the copy and against
## the pristine tree, and requires the two runs to print THE SAME TRACE. One
## differing scenario is a refutation, and the driver prints both traces and
## the scenario that separated them.
##
## WHAT THIS PROGRAM ASSERTS: NOTHING. It has no expected values and no cases.
## It presents a bounded, deterministic space of scenarios to the interrupt
## interface and prints what it observed. The comparison is between two RUNS of
## it, so an expectation written here would be a third thing to keep true.
##
## THE SCENARIO SPACE IS THE PRODUCT OF FIVE AXES, AND THE LAST TWO ARE THE
## ONES THAT ARE NOT OBVIOUS: every entry mask, every pre-take presentation
## sequence, every cycle budget, every RE-ENTRY SCRIPT, and every PRESENTATION
## PROFILE - the vector and the autovector flag each call carries.
##
## The re-entry script is the axis a hand-written case does not think
## of: `takeException` stacks the frame THROUGH THE BOARD'S WRITE CALLBACK, so
## a board may call `mcf5307_set_irq` from inside a take, between the latch
## clear and the acknowledge. That is the only way this interface can change
## the interrupt state in the middle of an exception, and it is exactly where
## the order of two statements inside `takeInterrupt` becomes visible.
##
## THE FOURTH AXIS IS THE PRESENTATION PROFILE, AND IT EXISTS BECAUSE ITS
## ABSENCE MANUFACTURED A FALSE UPHELD. Until 2026-08-13 every
## `mcf5307_set_irq` call in this file - in the pre-take sequence and in the
## re-entry script alike - passed `userVector` and an `autovector` argument of
## 1, so all 225 scenarios presented an AUTOVECTORED interrupt carrying ONE
## vector value. `irq.nim`'s `vectorFor` returns the autovector WITHOUT READING
## the stored vector whenever the flag is set, so `ctx.irq7Vector` and
## `ctx.irqVector` were written by every scenario and read by none.
##
## WHAT THAT COST, MEASURED 2026-08-13 AND NOT ARGUED. The level-7 edge's vector
## store moved OUT of its guard - a real semantic break, after which every later
## presentation overwrites the edge's vector - was registered against this
## observer as an `equivalent` claim, and the driver reported UPHELD over all
## 225 scenarios with the reachability probe reporting both edits REACHED. A
## mutation that changes only what an unread field holds cannot move a trace,
## and the verdict that follows says nothing about the core.
##
## SO `pVectored` HANDS EVERY PRESENTATION A DISTINCT VECTOR AND CLEARS THE
## FLAG. Two values on the flag alone would not have been enough: with one
## vector value in play, moving the store still leaves the same number in the
## field. It is the SECOND vector value that separates the edge's stored vector
## from the vector a later presentation carries, so the axis varies both
## together and `pAutovectored` keeps the space this file had.
##
## MEASURED 2026-08-13 AFTER THE WIDENING: 450 scenarios, and the same mutation
## is REFUTED - `pre @[7, 7]` presents a level-7 edge carrying one vector and
## then a second level 7 carrying another, which is the arrangement no
## autovectored scenario can express.
##
## THE SCENARIO COUNT IS NOT WHAT THIS COSTS. MEASURED 2026-08-13, this program
## runs its 450 scenarios in single-digit milliseconds, while `t_claims` runs
## for tens of seconds and spends essentially all of that in the Nim COMPILES
## the driver makes.
##
## WHAT THE SPACE STILL DOES NOT VARY, STATED SO THAT ITS SILENCE IS NOT READ AS
## COVERAGE. MEASURED 2026-08-13, and each of these is a field or an argument no
## scenario here moves: the RESET state, which every scenario takes from one
## `mcf5307_reset(ctx, startSp, execBase)`; the MEMORY the core executes, which
## is NOPs from `execBase` to `codeEnd` in every scenario; the T and S and M bits
## of the entry status register, which `srWithIpm` fixes; a level OUTSIDE 0 to 7,
## which `irq.nim` stores and never takes and which no `preSequences` or
## `writeScripts` entry carries; and the WRITE the re-entry script fires on,
## which is always the FIRST bus write of the run. A claim that turns on any of
## those is a claim this observer declines to refute for want of a scenario, and
## not one it has measured.
##
## WHAT IT CANNOT DO, STATED SO A PASS IS NOT READ AS A PROOF. It can REFUTE an
## unobservability claim and it can never ESTABLISH one. A claim it does not
## refute is a claim no scenario in this bounded space separates, which is a
## weaker statement than "changes no reachable state" and must not be recorded
## as that one.
##
## MIT licensed and clean-room with respect to GPL and LGPL code.

import std/strutils

import mcf5307/cpu
import mcf5307/decode_types
import mcf5307/exception
import mcf5307/irq
import mcf5307/machine

const
  memSize = 0x1000
  execBase = 0x400'u32
  startSp = 0x800'u32
  opNopWord = 0x4E71'u16
  handlerBase = 0x500'u32   ## every handler is 16 bytes apart from here
  codeEnd = 0x700'u32       ## the end of the NOP region, below the stack
  userVector = 0x42'u8
  vectoredBase = 0x50'u8    ## the first of the distinct vectors `pVectored` hands out
  vectoredCount = 8         ## more than any scenario here presents

type
  TestBoard = object
    bytes: array[memSize, uint8]

  PresentationProfile = enum
    ## HOW A PRESENTATION SPELLS ITS VECTOR AND ITS AUTOVECTOR FLAG. The two
    ## arguments move TOGETHER and not on two axes of their own: a cleared flag
    ## with one vector value in play reads the stored vector and cannot tell
    ## which presentation put it there.
    pAutovectored   ## `userVector` and `autovector` 1 - the space this file had
    pVectored       ## a DISTINCT vector per presentation, `autovector` 0

var board: TestBoard
var vectorReads: seq[uint32]
var acks: seq[string]
var ctxRef: MCF5307Ctx

# THE RE-ENTRY SCRIPT AND THE WRITE IT FIRES ON. `writeScript` is a sequence of
# levels the board presents from inside the FIRST bus write of the run, which
# is the first longword of the exception frame. `writesSeen` is what makes it
# fire once: a script that fired on every write would re-enter from the second
# frame longword as well and the trace would stop being about one boundary.
var writeScript: seq[int]
var writesSeen = 0

# THE PROFILE AND THE PRESENTATION COUNTER. The counter is what makes
# `pVectored`'s vectors DISTINCT rather than merely non-autovectored, and
# `freshBoard` resets it, so the vector a presentation carries is a function of
# its position in the scenario and of nothing outside it.
var presentationProfile: PresentationProfile
var presentationsMade = 0

proc present(ctx: MCF5307Ctx; level: int) =
  ## ONE PRESENTATION, AND THE ONE PLACE IN THIS FILE THAT NAMES A VECTOR OR A
  ## FLAG. Both call sites - the pre-take sequence and the re-entry script - go
  ## through here, so a scenario cannot present under one profile and re-enter
  ## under another.
  case presentationProfile
  of pAutovectored:
    mcf5307_set_irq(ctx, cint(level), userVector, 1)
  of pVectored:
    mcf5307_set_irq(ctx, cint(level),
                    vectoredBase + uint8(presentationsMade mod vectoredCount), 0)
  inc presentationsMade

proc boardWrite(b: var TestBoard; address: uint32; size: int; value: uint32) =
  for i in 0 ..< size:
    b.bytes[int(address) + i] =
      uint8((value shr ((size - 1 - i) * 8)) and 0xFF'u32)

proc boardReadValue(b: TestBoard; address: uint32; size: int): uint32 =
  for i in 0 ..< size:
    result = (result shl 8) or uint32(b.bytes[int(address) + i])

proc bRead(user: pointer; address: uint32; size: cint;
           status: ptr Mcf5307BusStatus): uint32 {.cdecl.} =
  let b = cast[ptr TestBoard](user)
  if int(address) + int(size) > memSize:
    status[] = Mcf5307BusStatus.busUnmapped
    return 0'u32
  status[] = Mcf5307BusStatus.busOk
  if address < vectorTableBytes:
    vectorReads.add(address)
  boardReadValue(b[], address, int(size))

proc bWrite(user: pointer; address: uint32; size: cint; value: uint32;
            status: ptr Mcf5307BusStatus) {.cdecl.} =
  let b = cast[ptr TestBoard](user)
  if int(address) + int(size) > memSize:
    status[] = Mcf5307BusStatus.busUnmapped
    return
  status[] = Mcf5307BusStatus.busOk
  boardWrite(b[], address, int(size), value)
  # THE RE-ENTRY. It happens AFTER the write has been performed, so the frame
  # the core is stacking is not disturbed by it, and only on the first write of
  # the run.
  if writesSeen == 0:
    writesSeen = 1
    for level in writeScript:
      present(ctxRef, level)
  else:
    inc writesSeen

proc bIack(user: pointer; level: cint; vector: uint8) {.cdecl.} =
  ## EVERY ACKNOWLEDGE CARRIES WHERE IT HAPPENED, for the reason
  ## `tests/t_irq.nim` gives at its own `Ack` type: a level and a vector alone
  ## do not separate an acknowledge made at the wrong point in the sequence
  ## from one made at the right point.
  acks.add("(level " & $int(level) & " vector " & $int(vector) &
           " sp 0x" & toHex(mcf5307_get_reg(ctxRef, 15)) &
           " pc 0x" & toHex(mcf5307_get_reg(ctxRef, 17)) &
           " reads " & $vectorReads.len &
           " sr 0x" & toHex(mcf5307_get_reg(ctxRef, 16)) & ")")

proc freshBoard() =
  for i in 0 ..< memSize:
    board.bytes[i] = 0'u8
  vectorReads = @[]
  acks = @[]
  writesSeen = 0
  presentationsMade = 0
  # THE WHOLE CODE REGION IS NOPs, AND THAT IS NOT LAZINESS. `tests/t_irq.nim`
  # records what a short NOP run costs: a run that passes its last NOP decodes
  # the ZERO word beyond it, the core halts, and every scenario that reached
  # that point reports `halted true` for a reason that has nothing to do with
  # interrupts. The scenarios here run to a CYCLE budget rather than to an
  # instruction count, so the position the run stops at is not known when the
  # board is written. Filling the region removes the question.
  for word in 0 ..< int((codeEnd - execBase) div 2'u32):
    boardWrite(board, execBase + uint32(word) * 2'u32, 2, uint32(opNopWord))
  for level in 1 .. 7:
    boardWrite(board, vectorAddress(0'u32, autovectorFor(level)), 4,
               handlerBase + uint32(level) * 0x10'u32)
  boardWrite(board, vectorAddress(0'u32, userVector), 4, handlerBase)
  # EVERY VECTOR `pVectored` CAN HAND OUT GETS ITS OWN HANDLER ADDRESS, so a
  # trace separates two vectored presentations by where the core went and not
  # by the acknowledge alone. The addresses sit inside the NOP region, above
  # the autovector handlers, which is why the region is filled rather than
  # spot-written.
  for index in 0 ..< vectoredCount:
    boardWrite(board, vectorAddress(0'u32, vectoredBase + uint8(index)), 4,
               handlerBase + 0x80'u32 + uint32(index) * 0x10'u32)

proc mem32(address: uint32): uint32 =
  if int(address) + 4 > memSize:
    return 0'u32
  boardReadValue(board, address, 4)

proc srWithIpm(ipm: uint32): uint32 =
  0x2000'u32 or (ipm shl 8)

proc scenario(ipm: uint32; pre: seq[int]; script: seq[int];
              budget: uint32; profile: PresentationProfile): string =
  ## One scenario, run and printed. THE WHOLE OBSERVABLE OUTCOME IS PRINTED and
  ## no field is left out, because the field a claim turns on is not known when
  ## this is written: a difference the trace does not carry is a difference the
  ## driver cannot see, and the driver is what decides.
  freshBoard()
  presentationProfile = profile
  writeScript = script
  let ctx = mcf5307_create(addr board, bRead, bWrite, bIack)
  ctxRef = ctx
  mcf5307_reset(ctx, startSp, execBase)
  discard mcf5307_set_reg(ctx, 16, srWithIpm(ipm))
  for level in pre:
    present(ctx, level)
  discard mcf5307_exec(ctx, budget)
  let sp = mcf5307_get_reg(ctx, 15)
  result = "sp 0x" & toHex(sp) &
    " pc 0x" & toHex(mcf5307_get_reg(ctx, 17)) &
    " sr 0x" & toHex(mcf5307_get_reg(ctx, 16)) &
    " halted " & $(mcf5307_halted(ctx) != 0) &
    " frame 0x" & toHex(mem32(sp)) &
    " framePc 0x" & toHex(mem32(sp + 4'u32)) &
    " acks " & $acks &
    " reads " & $vectorReads
  mcf5307_destroy(ctx)

const
  masks = [0'u32, 3'u32, 7'u32]
  preSequences = [
    @[3], @[7], @[3, 7], @[7, 7], @[7, 3, 7],
  ]
  writeScripts = [
    newSeq[int](), @[7], @[3, 7], @[7, 3, 7], @[0],
  ]
  budgets = [1'u32, 8'u32, 64'u32]
  profiles = [pAutovectored, pVectored]

# THE SCENARIO IDENTIFIER IS THE INPUT SPELLED OUT and never an index, so that
# a scenario added to the space does not renumber the ones already in it and a
# difference the driver reports names the run that produced it.
for mask in masks:
  for pre in preSequences:
    for script in writeScripts:
      for budget in budgets:
        for profile in profiles:
          echo "SCENARIO mask ", mask, " pre ", pre, " script ", script,
               " budget ", budget, " profile ", profile, " => ",
               scenario(mask, pre, script, budget, profile)
echo "t_claims: observer complete"
