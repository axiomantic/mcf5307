## `t_runtime_latch` - the one-time runtime latch, and what a stalled one
## answers.
##
## `mcf5307_runtime_init` reports a stall to its caller, and a report nobody
## is obliged to read is worth nothing unless the rest of the library refuses
## to run behind it. Both halves are asserted here: the report, and the
## refusal.
##
## Every case drives the real mechanism. The stall is produced by a second
## thread that claims the latch through `runtimeInitOnce` itself and stays
## inside its initializer, which is the exact shape `src/mcf5307/latch.nim`
## documents: module initialization waits for a thread, and that thread calls
## the initializer again. Nothing here writes a latch state by hand.
##
## The positive control is in this run and not in another test. Case 1 drives a
## healthy latch through the same procedure and reads `true` out of it. Without
## it a `false` from the stalled latch would not be separable from a procedure
## that answers `false` to everything.
##
## Why the latch is a value and not a module global. A single global latch can
## be driven to its terminal state exactly once per process, so a suite built
## on one could hold either the healthy case or the stalled case and never
## both. `RuntimeLatch` is an object, the published ABI owns one instance of
## it, and this suite makes as many as it needs.


import std/atomics
import std/os

import mcf5307/latch
import mcf5307/cpu
import isp1181/stub

import ./case_sites

var failures: seq[string]
var passCount = 0

proc checkImpl(site: int; ok: bool; label: string; got: string; want: string) =
  if ok:
    echo "PASSED  ", label
    inc passCount
    executedSites.add(site)
  else:
    echo "FAILED  ", label
    echo "          got  ", got
    echo "          want ", want
    failures.add(label)
    executedSites.add(site)

template check(ok: bool; label: string; got: string; want: string) =
  const site = instantiationInfo(-1).line
  static: declaredSites.add(site)
  checkImpl(site, ok, label, got, want)

# ---------------------------------------------------------------------------
# The initializers this suite hands to `runtimeInitOnce`.
#
# They are `cdecl` because the published path's initializer is. The one the
# library passes is the runtime entry point the Nim code generator emits, and
# the parameter type is what makes that call legal; a suite that passed a
# `nimcall` procedure would be exercising a signature the library cannot use.

var initializerRuns: Atomic[int]

proc countingInitializer() {.cdecl.} =
  discard initializerRuns.fetchAdd(1, moAcquireRelease)

proc inertInitializer() {.cdecl.} =
  discard

# The holder's initializer. It announces that it is inside - which is when the
# latch is claimed and the waiter's wait is guaranteed to be a real one - and
# then stays there until the waiter says it is finished. A fixed sleep would
# make the whole suite a race against a duration.
var holderInside: Atomic[bool]
var waiterFinished: Atomic[bool]
var holderResult: Atomic[bool]
var holderLatch: ptr RuntimeLatch

proc holdingInitializer() {.cdecl.} =
  holderInside.store(true, moRelease)
  while not waiterFinished.load(moAcquire):
    sleep(1)

proc holderBody(ignored: int) {.thread.} =
  holderResult.store(runtimeInitOnce(holderLatch[], holdingInitializer),
                     moRelease)

proc stall(target: var RuntimeLatch; waitMillis: int64): bool =
  ## Claim `target` on a second thread, wait for it from this one, and answer
  ## what the wait returned. The holder is joined before this returns, so the
  ## latch is settled by the time a caller reads it.
  holderInside.store(false, moRelease)
  waiterFinished.store(false, moRelease)
  holderResult.store(false, moRelease)
  holderLatch = addr target

  var holder: Thread[int]
  createThread(holder, holderBody, 0)
  while not holderInside.load(moAcquire):
    sleep(1)

  result = runtimeInitOnce(target, inertInitializer, waitMillis)
  waiterFinished.store(true, moRelease)
  joinThread(holder)

# ---------------------------------------------------------------------------
# Case 1 and 2. The positive control, on a latch nothing interferes with.

var healthy: RuntimeLatch

let firstCall = runtimeInitOnce(healthy, countingInitializer)
check(firstCall and initializerRuns.load(moAcquire) == 1,
      "a healthy latch runs the initializer once and answers true",
      $firstCall & " runs=" & $initializerRuns.load(moAcquire),
      "true runs=1")

let secondCall = runtimeInitOnce(healthy, countingInitializer)
check(secondCall and initializerRuns.load(moAcquire) == 1,
      "a second call answers true and does not run the initializer again",
      $secondCall & " runs=" & $initializerRuns.load(moAcquire),
      "true runs=1")

check(not runtimeAbandoned(healthy),
      "a healthy latch does not report itself abandoned",
      $runtimeAbandoned(healthy), "false")

# ---------------------------------------------------------------------------
# Case 4 to 7. The stall, driven by a real holder against a short deadline.

var stalled: RuntimeLatch
let stalledAnswer = stall(stalled, 50'i64)

check(not stalledAnswer,
      "a wait that reaches its deadline answers false instead of ending the " &
        "process",
      $stalledAnswer, "false")

check(runtimeAbandoned(stalled),
      "the abandoned state SURVIVES the holder finishing its initializer",
      $runtimeAbandoned(stalled), "true")

check(not holderResult.load(moAcquire),
      "the holder that completed its initializer under an abandoned latch " &
        "answers false too - the verdict belongs to the latch and not to the " &
        "thread",
      $holderResult.load(moAcquire), "false")

let repeatAnswer = runtimeInitOnce(stalled, inertInitializer)
check(not repeatAnswer,
      "a later call on an abandoned latch answers false and does not wait",
      $repeatAnswer, "false")

# ---------------------------------------------------------------------------
# Case 8. The default deadline is the one the library uses, and it is asserted
# by measuring a wait rather than by reading the constant back. A suite that
# compared `latchWaitMillis` against a literal would agree with itself whatever
# the wait loop did with it.

var defaulted: RuntimeLatch
let beforeDefault = monotonicMillis()
let defaultAnswer = stall(defaulted, latchWaitMillis)
let defaultElapsed = monotonicMillis() - beforeDefault

check(not defaultAnswer and defaultElapsed >= latchWaitMillis - 100,
      "the default deadline is the one the wait loop honours",
      $defaultAnswer & " elapsed=" & $defaultElapsed,
      "false elapsed>=" & $(latchWaitMillis - 100))

# ---------------------------------------------------------------------------
# Case 9 and 10. The refusal. A caller that dropped the status of
# `mcf5307_runtime_init` reaches a library that will not hand it a context.
#
# This is the half that does not depend on the caller. The status return is
# advice, and C lets a caller ignore advice; these two cases are what makes an
# ignored status harmless instead of silent.

let abandonedGlobalAnswer = stall(runtimeLatch, 50'i64)
check(not abandonedGlobalAnswer,
      "the ABI's own latch reaches the same abandoned state",
      $abandonedGlobalAnswer, "false")

let refusedCore = mcf5307_create(nil, nil, nil, nil)
check(refusedCore.isNil,
      "mcf5307_create refuses to allocate a core behind an abandoned runtime",
      (if refusedCore.isNil: "nil" else: "a context"), "nil")

let refusedDevice = isp1181_create(nil, nil, nil)
check(refusedDevice.isNil,
      "isp1181_create refuses to allocate a device behind an abandoned runtime",
      (if refusedDevice.isNil: "nil" else: "a context"), "nil")

# ---------------------------------------------------------------------------
# The registry lines. They are data and not a verdict.
const declaredCaseSites = declaredSites
const declaredOffGreenPathSites = offGreenPathSites
echo caseSiteLine("declared", "t_runtime_latch", declaredCaseSites)
echo caseSiteLine("executed", "t_runtime_latch", executedSites)
echo caseSiteLine("off-green-path", "t_runtime_latch", declaredOffGreenPathSites)

if failures.len > 0:
  echo ""
  echo "t_runtime_latch: ", failures.len, " of ", failures.len + passCount,
      " cases failed"
  quit(1)
else:
  echo ""
  echo "t_runtime_latch: ", passCount, " cases passed"
