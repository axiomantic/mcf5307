## `latch` - the one-time runtime latch, its deadline, and the terminal state a
## stalled initializer leaves behind.
##
## WHY THIS IS ITS OWN MODULE AND NOT PART OF `src/mcf5307.nim`. Two readers
## need the latch and neither may import the entry module.
##
##   `mcf5307/cpu` and `isp1181/stub` ask whether the runtime was ABANDONED
##   before they allocate anything. The entry module imports both of them, so
##   an import the other way is a cycle.
##
##   `tests/t_runtime_latch` drives the latch directly. The entry module
##   declares `mcf5307_NimMain`, which exists only in a build carrying
##   `--nimMainPrefix:mcf5307_`; every Nim suite strips that flag, so a suite
##   that reached the latch through the entry module would not link.
##
## NOTHING HERE NEEDS THE NIM RUNTIME. `runtimeInitOnce` is what BRINGS the
## runtime up, so every line it reaches has to be correct before the runtime
## exists: no `string`, no `seq`, no allocation, no exception. The clock and
## the yield are C library functions named directly, and the report goes out as
## C string literals one line at a time.
##
## THE LATCH IS AN OBJECT AND NOT A MODULE GLOBAL. The published ABI owns one
## instance, `runtimeLatch` below, and that is the only instance a shipped
## build ever has. A latch reaches its terminal state at most once, so a suite
## built on a single global could assert the healthy half or the stalled half
## and never both in one run; an object lets `tests/t_runtime_latch` make as
## many as it needs and drive each through the real procedure.
##
## MIT licensed. Nothing here is a fact about Motorola silicon.

import std/atomics
import system/ansi_c

# ---------------------------------------------------------------------------
# The wait primitives.
#
# THE DEADLINE USES A MONOTONIC CLOCK AND NOT THE WALL CLOCK. `time` is wrong
# for two separate reasons.
#
#   Its resolution is one second, and the deadline is `time() + 5`. The start
#   is truncated to a whole second and the comparison is truncated again, so
#   the true wait is anything between four and five seconds rather than the
#   five the constant names.
#
#   `time` reads the SETTABLE wall clock. An operator, NTP or a container start
#   can step it backwards at any moment. A backward step moves the deadline
#   away from the waiter, and the loop then spins with no end. That is the
#   unbounded spin this whole deadline exists to close, re-opened by a clock
#   adjustment.
#
# `clock_gettime(CLOCK_MONOTONIC)` counts from an arbitrary origin, no caller
# can set it, and its resolution is nanoseconds. `GetTickCount64` is the
# Windows equivalent and it counts milliseconds since boot.
#
# `sched_yield`, or `SwitchToThread` on Windows, hands the core to another
# thread. The wait loop below calls it. THE WINDOWS BRANCH OF BOTH IS
# UNMEASURED. This host is macOS and it builds the other branch.

when defined(windows):
  proc mcf5307TickCount(): uint64 {.
      importc: "GetTickCount64", header: "<windows.h>", stdcall.}

  proc monotonicMillis*(): int64 =
    int64(mcf5307TickCount())

  proc mcf5307Yield(): cint {.
      importc: "SwitchToThread", header: "<windows.h>",
      stdcall, discardable.}
else:
  # The object is `importc` with a header, so Nim emits no definition of its
  # own and the C compiler supplies the real layout. `clong` is the type of
  # both members on macOS and on 64-bit Linux.
  type
    MCF5307TimeSpec {.importc: "struct timespec", header: "<time.h>".} = object
      tv_sec: clong
      tv_nsec: clong

  let mcf5307ClockMonotonic {.importc: "CLOCK_MONOTONIC",
      header: "<time.h>".}: cint

  proc mcf5307ClockGetTime(clockId: cint; target: ptr MCF5307TimeSpec): cint {.
      importc: "clock_gettime", header: "<time.h>", discardable.}

  proc monotonicMillis*(): int64 =
    ## The monotonic clock in milliseconds.
    ##
    ## A failure of `clock_gettime` is not handled here, and it cannot be:
    ## this procedure runs before the Nim runtime exists and there is no
    ## failure channel to report into. `CLOCK_MONOTONIC` is mandatory in POSIX
    ## 2008 and the call fails only for an invalid clock identifier.
    var now: MCF5307TimeSpec
    discard mcf5307ClockGetTime(mcf5307ClockMonotonic, addr now)
    int64(now.tv_sec) * 1000'i64 + int64(now.tv_nsec) div 1_000_000'i64

  proc mcf5307Yield(): cint {.
      importc: "sched_yield", header: "<sched.h>", discardable.}

# ---------------------------------------------------------------------------
# The states.
#
# `latchAbandoned` is the TERMINAL FAILURE STATE. Without it the word held no
# value that ends a wait, and a waiter could spin until the process was killed.
#
# TERMINAL MEANS TERMINAL, AND THAT IS ENFORCED AT THE COMPLETING END TOO. The
# thread that finishes the initializer moves the latch to `latchDone` with a
# COMPARE-EXCHANGE FROM `latchRunning` and not with a plain store. A plain
# store overwrites an abandonment that a waiter has already reported and
# already acted on, so the same process would hold one caller that was told the
# runtime is unusable and another that is told it is fine.
const
  latchUntouched = 0
  latchRunning = 1
  latchDone = 2
  latchAbandoned = 3

const latchWaitMillis* = 5000'i64
  ## How long a caller waits for another thread to finish the initializer.
  ##
  ## THE BOUND IS A TRADE, AND IT SITS FAR ABOVE ANY INITIALIZER RUN OBSERVED
  ## ON THIS HOST. A runtime initializer that needs five seconds is already
  ## broken. A wait with no bound cannot report a stall at all, and that
  ## outcome is worse.
  ##
  ## The unit is milliseconds because the clock above reports milliseconds.

type
  RuntimeLatch* = object
    ## THE WHOLE OBJECT MUST BE CORRECT AT ZERO. `runtimeInitOnce` runs before
    ## the Nim runtime exists, so a latch that needed an initializing call
    ## would have nothing to run it. Measured on Nim 2.2.10, a global of this
    ## type translates to a file-scope C object with no initializer, and the
    ## generated module initializer holds no write to it. `latchUntouched` and
    ## `reportNotYetMade` are both zero for that reason and not by taste.
    state: Atomic[int]
    reported: Atomic[int]

const reportNotYetMade = 0
const reportMade = 1

var runtimeLatch*: RuntimeLatch
  ## THE ONE INSTANCE THE PUBLISHED ABI USES. `mcf5307_runtime_init` drives
  ## this one, `mcf5307_create` and `isp1181_create` read it, and no shipped
  ## build makes another.

var initializing {.threadvar.}: bool
  ## True while this thread is inside an initializer this module is running.
  ## It translates to a zero-initialized `NIM_THREADVAR`, so it needs no
  ## initializing call either. It separates a RE-ENTRANT call on the
  ## initializing thread from a CONCURRENT first call on some other thread: the
  ## two look alike at the latch and need opposite answers.
  ##
  ## There is a third case and this flag cannot see it. Another thread may call
  ## in while the initializing thread waits for that same thread. The flag is
  ## false on the caller, so the caller waits, and the two threads then wait
  ## for each other. An unbounded loop holds that deadlock spinning, with no
  ## diagnostic and no end. The deadline below ends it.
  ##
  ## THE FLAG IS PER-THREAD AND NOT PER-LATCH, AND THAT IS EXACT ONLY BECAUSE A
  ## SHIPPED BUILD HAS ONE LATCH. A build with two would let an initializer of
  ## latch A return early from a first call on latch B. `tests/t_runtime_latch`
  ## makes several latches and nests none of their initializers, so the
  ## condition holds there too; a second production latch would not be covered
  ## by that and would need this flag moved into the object.

proc runtimeAbandoned*(latch: var RuntimeLatch): bool =
  ## True once a waiter has reported a stall on `latch`.
  ##
  ## THIS IS THE REFUSAL EVERY OTHER ENTRY POINT READS. A C caller may drop the
  ## status `mcf5307_runtime_init` returns - the language allows it and no
  ## attribute can make it impossible - so the library may not depend on the
  ## caller having read it. `mcf5307_create` and `isp1181_create` ask this
  ## question instead and hand back no context when the answer is true.
  latch.state.load(moAcquire) == latchAbandoned

proc reportStall(latch: var RuntimeLatch) =
  ## Write the stall to standard error, ONCE PER LATCH.
  ##
  ## The runtime is not initialized here, so the text goes out one C string
  ## literal at a time: no allocation and no Nim string.
  ##
  ## ONCE, BECAUSE THE PROCEDURE NO LONGER ENDS THE PROCESS. The abort this
  ## replaces printed once because there was no second call; a host that keeps
  ## running and retries would otherwise fill its log with the same five lines.
  var expected = reportNotYetMade
  if not latch.reported.compareExchange(
      expected, reportMade, moAcquireRelease, moAcquire):
    return
  discard c_fputs(
    "mcf5307_runtime_init: the Nim runtime initializer did not finish.\n",
    cstderr)
  discard c_fputs(
    "Another thread claimed the one-time latch and did not release it.\n",
    cstderr)
  discard c_fputs(
    "One known cause: module initialization waits for a thread.\n", cstderr)
  discard c_fputs(
    "That thread then calls mcf5307_runtime_init itself.\n", cstderr)
  discard c_fputs(
    "The runtime is not initialized, so this library will create no context.\n",
    cstderr)
  discard c_fputs(
    "mcf5307_runtime_init reports 0 to this caller and to every later one.\n",
    cstderr)

proc runtimeInitOnce*(latch: var RuntimeLatch;
                      initializer: proc () {.cdecl, gcsafe, raises: [].};
                      waitMillis: int64 = latchWaitMillis): bool
    {.gcsafe, raises: [].} =
  ## Run `initializer` exactly once behind `latch`, and answer whether the
  ## runtime it brings up is usable.
  ##
  ## THE PARAMETER TYPE CARRIES `gcsafe` AND `raises: []`, AND BOTH ARE
  ## LOAD-BEARING. An indirect call through a procedure type without them makes
  ## this procedure itself GC-unsafe and raising, which is wrong twice over: it
  ## runs BEFORE the runtime exists, so it can neither touch a garbage-collected
  ## heap nor unwind an exception through the C ABI. Written this way the
  ## compiler REFUSES an initializer that could do either, on the calling side,
  ## rather than leaving the rule in this comment.
  ##
  ## THE RESULT IS THE LATCH'S VERDICT AND NOT THIS CALL'S HISTORY. A thread
  ## that ran the initializer to completion under a latch some other waiter had
  ## already abandoned answers `false` like everyone else. The alternative -
  ## answering `true` because this particular thread's work went well - puts
  ## two callers in one process on opposite sides of the same question.
  ##
  ## The latch is claimed BEFORE the call and not after it. Two hazards decide
  ## that order.
  ##
  ## The first hazard is re-entrancy. Any code that module initialization
  ## reaches can call this procedure again. A latch claimed after the call
  ## recurses without bound. A latch claimed before it terminates.
  ##
  ## The second hazard is concurrency. Nim 2.2 builds with threads on, and
  ## `include/mcf5307.h` promises an idempotent call with no single-thread
  ## precondition. A plain boolean lets two threads both read false and both
  ## run the initializer. The compare-and-exchange admits exactly one of them.
  ##
  ## A caller that loses the exchange waits, and the wait carries a deadline.
  ## Returning early would hand back a runtime that does not exist yet. Waiting
  ## for ever would hide the third case the `initializing` comment names.
  let entryState = latch.state.load(moAcquire)
  if entryState == latchDone:
    return true
  if entryState == latchAbandoned:
    reportStall(latch)
    return false

  if initializing:
    # A re-entrant call on the thread that is running the initializer. The
    # initializer it would run is the one already on this stack, and that call
    # is the one whose verdict counts.
    return true

  var expected = latchUntouched
  if latch.state.compareExchange(expected, latchRunning, moAcquireRelease,
                                 moAcquire):
    initializing = true
    initializer()
    initializing = false
    # THE COMPLETION IS A COMPARE-EXCHANGE. See the note on `latchAbandoned`
    # above: a plain store would resurrect a latch a waiter has already
    # reported as dead.
    var running = latchRunning
    if latch.state.compareExchange(running, latchDone, moAcquireRelease,
                                   moAcquire):
      return true
    reportStall(latch)
    return false

  # Another thread claimed the latch. Wait for that thread, and stop at the
  # deadline. The waiter that stops writes `latchAbandoned` itself, so every
  # other waiter ends at once instead of serving its own deadline.
  let deadline = monotonicMillis() + waitMillis
  while true:
    let waitedState = latch.state.load(moAcquire)
    if waitedState == latchDone:
      return true
    if waitedState == latchAbandoned:
      reportStall(latch)
      return false
    if monotonicMillis() >= deadline:
      # THE RESULT OF THE EXCHANGE IS READ AND IT IS NOT DISCARDED. There is a
      # race between the load above and this line. The initializing thread can
      # finish in that window. The exchange then fails, `running` comes back
      # holding `latchDone`, and the runtime IS initialized. A discarded result
      # would report a stall on a runtime that has just come up.
      #
      # A failure that reports any other value is a real stall. `latchRunning`
      # means the initializing thread is still inside and out of time.
      # `latchAbandoned` means another waiter reached its own deadline first.
      var running = latchRunning
      if not latch.state.compareExchange(
          running, latchAbandoned, moAcquireRelease, moAcquire):
        if running == latchDone:
          return true
      reportStall(latch)
      return false
    mcf5307Yield()
