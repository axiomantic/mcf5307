## `t_no_alloc` - the core allocates only inside `mcf5307_create`, and
## `mcf5307_exec` allocates nothing however long it runs.
##
## The delivery form is an audio plugin, so
## `mcf5307_exec` may be entered from a real-time thread, where one call into
## the system allocator is a missed buffer rather than a slow frame. Nothing
## about that failure is visible in an exit status, in a register comparison or
## in a cycle count, so no other suite in this directory can go red on it.
##
## The instrument is `getAllocStats`, and it is silent when it is not enabled.
## `system/memalloc.nim` compiles the counters only under `-d:nimAllocStats`;
## without that define `getAllocStats()` still compiles, still returns an
## `AllocStats`, and returns a default one. A suite that asserted zero against
## that build would report a pass it had not measured - a zero from a counter
## that was never wired reads exactly like a zero from a core that does not
## allocate. The driver in `tests/tests_cpu.cmake` adds the define and states
## why it departs from the library's own flag set; the case below on
## `mcf5307_create` is what makes the departure self-enforcing, because the
## define going missing turns that case red rather than turning this suite into
## a green mirage.
##
## The counter is read through a cast, and the cast is checked. `AllocStats`
## exports its type and not its two fields, so `stats.allocCount` does not
## compile outside `system`. The public reader is `$`. The cast below reads the
## same two words positionally, and the first case holds it against `$` so that
## a layout this cast no longer matches is red rather than silently
## misreported.
##
## The board mirrors one page of NOPs over the whole address space, and that is
## a deliberate choice over a branch back to the top. Under mirroring the
## program counter advances monotonically for the whole run, so the final
## program counter is a witness of how many instructions ran that does not share
## a path with this file's own fetch counter. A branch-back loop would return
## the program counter to the top of the loop and leave the fetch counter as the
## only witness.
##
## Why the execution witnesses are here at all. A core that halted on its first
## instruction satisfies "allocates nothing" perfectly, and so does one whose
## `mcf5307_exec` returns without executing. The fetch counter, the last fetch
## address, the final program counter and the halt and fault flags are asserted
## beside every allocation figure so that a zero means the run happened.
##
## The two call shapes are separate cases because they fail differently. Ten
## million calls each carrying one instruction find an allocation taken once per
## call; one call carrying many instructions finds an allocation taken once per
## instruction inside the loop. Either shape alone passes against the other's
## defect.

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
  ## The call site is recorded at compile time into `declaredSites` and at run
  ## time into `executedSites`. `tests/case_sites.nim` states what the pair is
  ## for and `tests/case_sites.cmake` states the rules the driver applies.
  ## The template exists for `instantiationInfo`: a proc cannot see where it
  ## was called from.
  const site = instantiationInfo(-1).line
  static: declaredSites.add(site)
  checkImpl(site, got, want, label)

# ---------------------------------------------------------------------------
# The instrument.

type AllocCounts = tuple[allocCount: int, deallocCount: int]

proc counts(): AllocCounts =
  ## The allocator's two counters, read positionally out of the object whose
  ## fields `system` does not export.
  cast[AllocCounts](getAllocStats())

proc taken(before: AllocCounts; after: AllocCounts): AllocCounts =
  (allocCount: after.allocCount - before.allocCount,
   deallocCount: after.deallocCount - before.deallocCount)

const noneTaken: AllocCounts = (allocCount: 0, deallocCount: 0)

# ---------------------------------------------------------------------------
# The board. One page of NOP, mirrored, and a counter on each callback.
#
# Every measured value is taken into a `let` before any case runs. `check` is a
# template and `checkImpl` echoes, and an echo allocates; a measurement window
# that contained a case would be measuring this file rather than the core.

const
  pageBytes = 0x1000
  nopWord = 0x4E71'u16
  execBase = 0x100'u32
  stackBase = 0x800'u32
  seedD0 = 0x12345678'u32
  instructions = 10_000_000
  burstInstructions = 1_000
  nopCycles = 4'u32     ## what one NOP costs this core: the fetch plus the
                        ## execution pipe.

var page: array[pageBytes, uint8]
var fetchCount = 0
var lastFetchAddress = 0'u32
var writeCount = 0
var iackCount = 0

proc bRead(user: pointer; address: uint32; size: cint;
           status: ptr Mcf5307BusStatus): uint32 {.cdecl.} =
  status[] = Mcf5307BusStatus.busOk
  inc fetchCount
  lastFetchAddress = address
  let offset = int(address mod uint32(pageBytes))
  for i in 0 ..< int(size):
    result = (result shl 8) or uint32(page[(offset + i) mod pageBytes])

proc bWrite(user: pointer; address: uint32; size: cint; value: uint32;
            status: ptr Mcf5307BusStatus) {.cdecl.} =
  status[] = Mcf5307BusStatus.busOk
  inc writeCount

proc bIack(user: pointer; level: cint; vector: uint8) {.cdecl.} =
  inc iackCount

for index in countup(0, pageBytes - 2, 2):
  page[index] = uint8(nopWord shr 8)
  page[index + 1] = uint8(nopWord and 0xFF'u16)

# ---------------------------------------------------------------------------
# The cast, held against the public reader.

let sampled = getAllocStats()
let sampledText = $sampled
let sampledByCast = cast[AllocCounts](sampled)

# ---------------------------------------------------------------------------
# The lifecycle, one call per window.

let beforeCreate = counts()
let ctx = mcf5307_create(addr page, bRead, bWrite, bIack)
let afterCreate = counts()

let beforeReset = counts()
mcf5307_reset(ctx, stackBase, execBase)
let afterReset = counts()

let beforeRegisters = counts()
discard mcf5307_set_reg(ctx, 0, seedD0)
let readBack = mcf5307_get_reg(ctx, 0)
let afterRegisters = counts()

# ---------------------------------------------------------------------------
# Ten million instructions, one per call.
#
# A budget of one cycle runs exactly one instruction whatever that instruction
# costs, because `mcf5307_exec` saturates after the step rather than declining
# to take it. It is the budget `conformance/runner.cpp` passes.

let beforeExec = counts()
for index in 1 .. instructions:
  discard mcf5307_exec(ctx, 1'u32)
let afterExec = counts()

let executed = (fetches: fetchCount,
                lastFetch: lastFetchAddress,
                pc: mcf5307_get_reg(ctx, 17),
                halted: ctx.halted,
                fault: ctx.fault,
                writes: writeCount,
                iacks: iackCount)

let beforeDestroy = counts()
mcf5307_destroy(ctx)
let afterDestroy = counts()

# ---------------------------------------------------------------------------
# Many instructions inside one call.
#
# The budget is exact and not generous. At `nopCycles` a NOP the budget below
# is spent to the cycle on the last instruction, so the run ends because the
# budget ran out and not because the loop saturated.
#
# The return of `mcf5307_exec` is not asserted. The loop saturates at its
# budget, so a non-halting run returns
# the budget whatever it cost - an assertion on it would compare the budget to
# itself.

let burstContext = mcf5307_create(addr page, bRead, bWrite, bIack)
mcf5307_reset(burstContext, stackBase, execBase)
let fetchesBeforeBurst = fetchCount

let beforeBurst = counts()
discard mcf5307_exec(burstContext, nopCycles * uint32(burstInstructions))
let afterBurst = counts()

let bursted = (fetches: fetchCount - fetchesBeforeBurst,
               lastFetch: lastFetchAddress,
               pc: mcf5307_get_reg(burstContext, 17),
               halted: burstContext.halted,
               fault: burstContext.fault)
mcf5307_destroy(burstContext)

# ---------------------------------------------------------------------------
# The cases.

check(sampledText,
      "(allocCount: " & $sampledByCast.allocCount &
      ", deallocCount: " & $sampledByCast.deallocCount & ")",
      "the cast reads the counter the public `$` prints")

# The positive control, and the whole suite rests on it. Every case below
# asserts a zero, and a zero is what a dead counter reports. `mcf5307_create`
# is the one entry point the design allows to allocate - it takes the context
# out of the heap - so it is the call that proves the counter moves in the same
# run that reports the zeros. The figure is one because the context is one
# `ref` object and nothing else on that path reaches the allocator; a build
# without `-d:nimAllocStats` reports zero here and is red.
check(taken(beforeCreate, afterCreate), (allocCount: 1, deallocCount: 0),
      "mcf5307_create takes the context out of the heap")

check(taken(beforeReset, afterReset), noneTaken,
      "mcf5307_reset allocates nothing")

check((taken: taken(beforeRegisters, afterRegisters), readBack: readBack),
      (taken: noneTaken, readBack: seedD0),
      "mcf5307_set_reg and mcf5307_get_reg allocate nothing")

check(taken(beforeExec, afterExec), noneTaken,
      "mcf5307_exec allocates nothing over ten million instructions")

# The execution witness for the run above. Its fields are what separate a core
# that ran ten million instructions from one that halted on the first and
# reported the same zero. The last fetch address and the program counter are
# derived from the instruction count by multiplication; the core reaches them
# by repeated addition, so the two do not share a path. The write and interrupt
# acknowledge counters are here because a NOP stream must touch neither, and a
# board callback that fired would put the fetch count and the instruction count
# out of step.
check(executed,
      (fetches: instructions,
       lastFetch: execBase + 2'u32 * uint32(instructions - 1),
       pc: execBase + 2'u32 * uint32(instructions),
       halted: false,
       fault: false,
       writes: 0,
       iacks: 0),
      "ten million instructions ran, and only instruction fetches happened")

check(taken(beforeDestroy, afterDestroy), noneTaken,
      "mcf5307_destroy allocates nothing")

check(taken(beforeBurst, afterBurst), noneTaken,
      "one mcf5307_exec call allocates nothing however many instructions it runs")

check(bursted,
      (fetches: burstInstructions,
       lastFetch: execBase + 2'u32 * uint32(burstInstructions - 1),
       pc: execBase + 2'u32 * uint32(burstInstructions),
       halted: false,
       fault: false),
      "the single call ran its whole budget of instructions")

# The registry lines. They are data and not a verdict: this program reports
# what its text declares and what its run adjudicated, and the registered
# test's driver is what compares them. A verdict printed here would be a
# self-assessment, and a run that stopped early would simply not print one.
const declaredCaseSites = declaredSites
const declaredOffGreenPathSites = offGreenPathSites
echo caseSiteLine("declared", "t_no_alloc", declaredCaseSites)
echo caseSiteLine("executed", "t_no_alloc", executedSites)
echo caseSiteLine("off-green-path", "t_no_alloc", declaredOffGreenPathSites)

if failures.len > 0:
  echo ""
  echo "t_no_alloc: ", failures.len, " of ", failures.len + passCount,
      " cases failed"
  quit(1)
else:
  echo ""
  echo "t_no_alloc: ", passCount, " cases passed"
