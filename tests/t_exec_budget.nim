## `t_exec_budget` - what `mcf5307_exec` RETURNS when the budget runs out in
## the middle of an instruction, asserted as an arithmetic identity rather than
## as a flag.
##
## THE PROPERTY. `mcf5307_exec` never abandons an instruction it has started:
## the loop decides whether to continue AFTER a step, so the last instruction of
## a call has already retired when the budget is found to be spent. The return
## is therefore the cost of everything that RAN, and it may EXCEED the budget -
## by at most the cost of that one last instruction.
##
## WHY IT IS ASSERTED HERE AND NOT LEFT TO THE SUITES THAT CALL `exec(ctx, 1)`.
## Those suites read the return as a ran-or-trapped flag and compare it against
## a small literal. A return that under-reports and a return that reports the
## truth are INDISTINGUISHABLE to such a comparison whenever the budget is one,
## so nothing in them can move when this contract changes. The identity below
## can: it holds the total of many calls against a cost this file DERIVES.
##
## NO CYCLE COUNT IS WRITTEN DOWN IN THIS FILE. `costOf` measures an
## instruction's cost through the shipped entry point, using a budget so large
## that the loop stops on the halt that follows the instruction and not on the
## budget. That path cannot saturate, so it reads the same number before and
## after the contract this suite pins - which is what makes it a REFERENCE for
## the budgeted path rather than a second copy of it. A literal here would be
## the defect this project keeps finding: a cost transcribed beside the code
## that computes it, and then left behind when the code moves.

import mcf5307/cpu
import mcf5307/decode_types
import mcf5307/machine

var failures: seq[string]
import ./case_sites

var passCount = 0

proc checkImpl[T](site: int; got: T; want: T; label: string) =
  if got == want:
    echo "PASSED  ", label, " = ", want
    inc passCount
    executedSites.add(site)
  else:
    echo "FAILED  ", label, ": expected ", want, ", got ", got
    failures.add(label)
    executedSites.add(site)

template check(got: untyped; want: untyped; label: string) =
  ## THE CALL SITE IS RECORDED TWICE - once at COMPILE TIME into
  ## `declaredSites` by the `static` below, and once at RUN TIME into
  ## `executedSites`, by the implementation and only when it reaches a verdict.
  ## `tests/case_sites.nim` states what the pair is for and
  ## `tests/case_sites.cmake` states the rules the driver applies.
  const site = instantiationInfo(-1).line
  static: declaredSites.add(site)
  checkImpl(site, got, want, label)

# ---------------------------------------------------------------------------
# The board. It is `tests/t_lines.nim`'s, for the reason that file gives: a pass
# here has to be a pass of the SHIPPED path and not of an internal helper
# reached around the back.

const memSize = 0x1000

type TestBoard = object
  bytes: array[memSize, uint8]

var board: TestBoard

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
  boardReadValue(b[], address, int(size))

proc bWrite(user: pointer; address: uint32; size: cint; value: uint32;
            status: ptr Mcf5307BusStatus) {.cdecl.} =
  let b = cast[ptr TestBoard](user)
  if int(address) + int(size) > memSize:
    status[] = Mcf5307BusStatus.busUnmapped
    return
  status[] = Mcf5307BusStatus.busOk
  boardWrite(b[], address, int(size), value)

proc bIack(user: pointer; level: cint; vector: uint8) {.cdecl.} =
  discard

const
  execBase = 0x100'u32
  stackBase = 0x800'u32
  srBase = 0x2700'u32       ## the reset status register, condition codes clear
  insWords = 64             ## how many copies of the word the memory carries
  nopWord = 0x4E71'u16      ## `nop`, m68k-elf-as -mcpu=5307
  addqWord = 0x5281'u16     ## `addq.l #1,%d1`, m68k-elf-as -mcpu=5307
  refusedWord = 0xA000'u16
    ## A LINE-A WORD, WHICH THIS CORE REFUSES. `tests/t_lines.nim` asserts the
    ## refusal over the whole line-A space: the word halts the core with
    ## `fault` and returns no cycles. `costOf` below needs exactly that - a
    ## STOP the budget did not cause - and an encoding the core executes would
    ## not supply one.

proc freshCore(word: uint16; copies: int; tail: uint16): MCF5307Ctx =
  ## A core whose memory holds `copies` of `word` at `execBase`, followed by
  ## `tail`. Every field the runs below read is set through the published
  ## entry points.
  for index in 0 ..< memSize:
    board.bytes[index] = 0'u8
  for index in 0 ..< copies:
    boardWrite(board, execBase + uint32(index * 2), 2, uint32(word))
  boardWrite(board, execBase + uint32(copies * 2), 2, uint32(tail))

  result = mcf5307_create(addr board, bRead, bWrite, bIack)
  mcf5307_reset(result, stackBase, execBase)
  # The status register is set LAST: `mcf5307_reset` writes it, so an earlier
  # write would be overwritten.
  discard mcf5307_set_reg(result, 16, srBase)

proc costOf(word: uint16): uint32 =
  ## ONE INSTRUCTION'S COST, MEASURED AND NOT TRANSCRIBED. The memory holds one
  ## copy of `word` and then a word the core refuses, and the budget is far
  ## larger than any instruction on this part. The loop therefore stops on the
  ## halt and never on the budget, so the return is the instruction's whole
  ## cost by a path on which no saturation can occur.
  let ctx = freshCore(word, 1, refusedWord)
  result = mcf5307_exec(ctx, uint32(memSize))
  mcf5307_destroy(ctx)

let nopCost = costOf(nopWord)
let addqCost = costOf(addqWord)

# ---------------------------------------------------------------------------
# BLOCK 1. THE TWO COSTS ARE DISCRIMINATING, and this is what makes every case
# below able to fail.
#
# A core that saturated its return at the budget would answer 1 to
# `exec(ctx, 1)` for BOTH words. The cases in blocks 2 and 3 multiply a derived
# cost by a call count, so they separate that core from this one only while the
# derived cost is not 1 - and they separate the two words from each other only
# while the two costs differ. Neither is asserted as a number here: what is
# asserted is the relation each case depends on.

check((nopAboveOne: nopCost > 1'u32, addqAboveOne: addqCost > 1'u32,
       costsDiffer: nopCost != addqCost),
      (nopAboveOne: true, addqAboveOne: true, costsDiffer: true),
      "the two measured costs are above one and are not the same number")

# ---------------------------------------------------------------------------
# BLOCK 2. THE IDENTITY. `insWords` calls, each with a budget of one, retire
# `insWords` instructions and return their whole cost.
#
# THE PROGRAM COUNTER IS ASSERTED BESIDE THE TOTAL AND IS NOT DECORATION. A
# core that returned the right total by running the wrong number of
# instructions would pass a total-only case; the pc is what says the retired
# count is the call count. `insWordBytes` is the core's own opcode-word width,
# imported rather than spelled as a 2 here.

proc totalOverSingleCycleBudgets(word: uint16): (uint32, uint32) =
  ## The sum of `insWords` returns, and the program counter afterwards.
  let ctx = freshCore(word, insWords, refusedWord)
  var total = 0'u32
  for _ in 0 ..< insWords:
    total = total + mcf5307_exec(ctx, 1'u32)
  result = (total, mcf5307_get_reg(ctx, 17))
  mcf5307_destroy(ctx)

let nopRun = totalOverSingleCycleBudgets(nopWord)
check(nopRun,
      (nopCost * uint32(insWords),
       execBase + uint32(insWords) * insWordBytes),
      "NOP: the sum of the single-cycle-budget returns is the retired cost")

let addqRun = totalOverSingleCycleBudgets(addqWord)
check(addqRun,
      (addqCost * uint32(insWords),
       execBase + uint32(insWords) * insWordBytes),
      "ADDQ: the sum of the single-cycle-budget returns is the retired cost")

# ---------------------------------------------------------------------------
# BLOCK 3. THE OVERRUN IS BOUNDED BY ONE INSTRUCTION, stated as the exact
# return for every budget from one to three whole NOPs rather than as an
# inequality. The loop continues while the spend is below the budget, so a call
# retires the smallest whole number of instructions whose cost reaches it: the
# return is the cost rounded UP to a multiple of itself.
#
# AN INEQUALITY WOULD NOT SEPARATE THE TWO CONTRACTS at every budget it covers.
# `spent <= budget` is what the saturating core satisfied, and a case written
# `spent >= budget` passes for a core that overruns by any amount at all.

# THE SWEEP'S LENGTH IS A CONSTANT AND NOT A MULTIPLE OF THE MEASURED COST.
# `mcf5307_check_case_total` in this suite's driver is a TYPED figure, and a
# sweep whose length moved with the cost would move that figure whenever a
# cycle count in the core changed - a red with nothing wrong in it, and the
# shape that teaches an author to retype the figure.
const budgetSweep = 12'u32

for budget in 1'u32 .. budgetSweep:
  let ctx = freshCore(nopWord, insWords, refusedWord)
  let spent = mcf5307_exec(ctx, budget)
  mcf5307_destroy(ctx)
  let wholeInstructions = (budget + nopCost - 1'u32) div nopCost
  check(spent, nopCost * wholeInstructions,
        "a budget of " & $budget & " returns the cost of the instructions it ran")

# THE REGISTRY LINES. They are DATA AND NOT A VERDICT: this program reports
# what its text declares and what its run adjudicated, and the registered
# test's driver is what compares them - and what compares the declared count
# against the call sites in this file. A verdict printed here would be a
# self-assessment, and a run that stopped early would simply not print one.
const declaredCaseSites = declaredSites
const declaredOffGreenPathSites = offGreenPathSites
echo caseSiteLine("declared", "t_exec_budget", declaredCaseSites)
echo caseSiteLine("executed", "t_exec_budget", executedSites)
echo caseSiteLine("off-green-path", "t_exec_budget", declaredOffGreenPathSites)

if failures.len > 0:
  echo ""
  echo "t_exec_budget: ", failures.len, " of ", failures.len + passCount,
      " cases failed"
  quit(1)
else:
  echo ""
  echo "t_exec_budget: ", passCount, " cases passed"
