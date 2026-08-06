## The Nim entry module of the `mcf5307` project.
##
## This module is the only Nim entry module. The build passes
## `--nimMainPrefix:mcf5307_` for it. Design section 5.5 keeps the one-project
## rule as a convention. A second Nim library passes its own prefix and exports
## its own `<component>_runtime_init`, and nothing else changes.
##
## Task CPU-1 creates this file and gives it the runtime entry point alone. The
## core and the ISP1181 model are the work of the later cpu tasks. Those tasks
## add their exported procedures to this project.
##
## MIT licensed and clean-room with respect to GPL and LGPL code.

import std/atomics
import system/ansi_c

# ---------------------------------------------------------------------------
# The pragma set of every symbol this project publishes.
#
# Each exported procedure carries `{.exportc: "<c name>", mcf5307Abi.}` and
# nothing less. `mcf5307Abi` holds `cdecl` and `dynlib` together, so that the
# set is written once and a later task cannot supply half of it.
#
# `dynlib` is load-bearing. Measured on Nim 2.2.10, a procedure declared
# `{.exportc, cdecl.}` alone translates to `N_LIB_PRIVATE`, and `nimbase.h`
# defines that as `__attribute__((visibility("hidden")))` for gcc and clang.
# The same procedure with `dynlib` translates to `N_LIB_EXPORT`, which is
# `__attribute__((visibility("default")))`.
#
# A hidden symbol is invisible to the usual check. It still reports as `T` in
# `nm` output over the static archive, so `nm libmcf5307.a` cannot find this
# fault. The fault appears only when the archive goes into a shared object.
# That shared object is the delivery form. The plugin then exports nothing,
# and the host cannot reach the core.
#
# `cmake/Nim.cmake` step 4a reads the generated C and fails the configure step
# when a published symbol lost the pragma. That check is what makes this
# comment enforceable rather than advisory.
#
# `include/mcf5307.h` and design section 5.4 both describe the set as
# `{.exportc, cdecl.}`, without `dynlib`. Those two are the property of other
# tasks. This file is the one the compiler reads.
{.pragma: mcf5307Abi, cdecl, dynlib.}

# ---------------------------------------------------------------------------
# `mcf5307_NimMain` is the runtime initializer that `--nimMainPrefix:mcf5307_`
# renames. The prefix is what lets a second Nim library live in the same
# binary, because the collision is on the default names alone.
proc mcf5307_NimMain() {.importc: "mcf5307_NimMain", cdecl.}

# ---------------------------------------------------------------------------
# The wait primitives.
#
# `mcf5307_runtime_init` runs before the Nim runtime exists. Anything it calls
# must therefore work without that runtime. These declarations name C library
# functions directly, and they add no Nim module to the unit list. Measured on
# Nim 2.2.10: the unit count is six with them and six without them.
#
# `time` supplies the deadline. Its resolution is one second. That is the right
# order for a stall bound, and it needs no platform-specific clock.
#
# `sched_yield`, or `SwitchToThread` on Windows, hands the core to another
# thread. The wait loop below calls it. The loop it replaces called `cpuRelax`
# alone and yielded to nothing. The Windows branch is not measured here. This
# host is macOS and it builds the other branch.

type
  MCF5307Time {.importc: "time_t", header: "<time.h>".} = distinct int64

proc mcf5307WallClock(destination: pointer): MCF5307Time {.
    importc: "time", header: "<time.h>".}

when defined(windows):
  proc mcf5307Yield(): cint {.
      importc: "SwitchToThread", header: "<windows.h>",
      stdcall, discardable.}
else:
  proc mcf5307Yield(): cint {.
      importc: "sched_yield", header: "<sched.h>", discardable.}

# ---------------------------------------------------------------------------
# The one-time latch.
#
# It holds four states in one atomic word. Measured on Nim 2.2.10, the C
# translation is a file-scope `_Atomic NI64` with no initializer. Its value is
# therefore zero before any Nim code runs, and the generated module initializer
# holds no write to it. The latch needs no initializing call of its own.
# That property is required and not incidental: this procedure runs before the
# Nim runtime exists, so anything it touches must be correct at zero.
#
# `latchAbandoned` is the terminal failure state. Without it the word held no
# value that ends a wait. A waiter could then spin until the process was
# killed, and that is the fault this state exists to end.
const
  latchUntouched = 0
  latchRunning = 1
  latchDone = 2
  latchAbandoned = 3

# How long a caller waits for another thread to finish the initializer. The
# bound is a trade and it is not a measurement of the initializer. A runtime
# initializer that needs more than five seconds is already broken. A wait
# without any bound cannot report a stall at all, and that outcome is worse.
const latchWaitSeconds = 5'i64

var latch: Atomic[int]

# True while this thread is inside `mcf5307_NimMain`. It translates to a
# zero-initialized `NIM_THREADVAR`, so it needs no initializing call either. It
# separates a re-entrant call on the initializing thread from a concurrent
# first call on some other thread. The two look alike at the latch and need
# opposite answers.
#
# There is a third case and this flag cannot see it. Another thread may call
# this procedure while the initializing thread waits for that same thread. The
# flag is false on the caller, so the caller waits, and the two threads then
# wait for each other. Measured: the unbounded loop held that deadlock at 98.8%
# of a core, with no diagnostic and no end. The deadline below ends it.
var initializing {.threadvar.}: bool

proc mcf5307LatchStalled() {.noreturn.} =
  ## Reports an abandoned latch and ends the process.
  ##
  ## The runtime is not initialized here, so every later call into this library
  ## would run without it. Design section 5.6 refuses a wrong answer with exit
  ## status 0, and a plain return to the caller would produce one.
  ##
  ## The text goes out one line at a time. Each line is a C string literal, so
  ## the report needs no allocation and no Nim string.
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
    "The runtime is not initialized, so this process stops here.\n", cstderr)
  c_abort()

proc mcf5307RuntimeInit() {.exportc: "mcf5307_runtime_init", mcf5307Abi.} =
  ## Runs the Nim runtime's initializer once.
  ##
  ## C++ never names `mcf5307_NimMain`. It calls this procedure, which is what
  ## design section 5.4 rule 2 requires. This procedure is the only caller of
  ## the runtime entry point in the project.
  ##
  ## The latch is claimed before the call and not after it. Two hazards decide
  ## that order.
  ##
  ## The first hazard is re-entrancy. Any code that module initialization
  ## reaches can call this procedure again. A latch claimed after the call
  ## recurses without bound. A latch claimed before it terminates.
  ##
  ## The second hazard is concurrency. Nim 2.2 builds with threads on, and the
  ## header promises an idempotent call with no single-thread precondition. A
  ## plain boolean lets two threads both read false and both run the
  ## initializer. The compare-and-exchange admits exactly one of them.
  ##
  ## A caller that loses the exchange waits, and the wait carries a deadline.
  ## Returning early would hand back a runtime that does not exist yet. Waiting
  ## for ever would hide the third case the `initializing` comment names.
  let entryState = latch.load(moAcquire)
  if entryState == latchDone:
    return
  if entryState == latchAbandoned:
    mcf5307LatchStalled()

  if initializing:
    # A re-entrant call on the thread that is running the initializer. The
    # initializer it would run is the one already on this stack.
    return

  var expected = latchUntouched
  if latch.compareExchange(expected, latchRunning, moAcquireRelease, moAcquire):
    initializing = true
    mcf5307_NimMain()
    initializing = false
    latch.store(latchDone, moRelease)
    return

  # Another thread claimed the latch. Wait for that thread, and stop at the
  # deadline. The waiter that stops writes `latchAbandoned` itself, so every
  # other waiter ends at once instead of serving its own deadline.
  let deadline = int64(mcf5307WallClock(nil)) + latchWaitSeconds
  while true:
    let waitedState = latch.load(moAcquire)
    if waitedState == latchDone:
      return
    if waitedState == latchAbandoned:
      mcf5307LatchStalled()
    if int64(mcf5307WallClock(nil)) >= deadline:
      var running = latchRunning
      discard latch.compareExchange(
        running, latchAbandoned, moAcquireRelease, moAcquire)
      mcf5307LatchStalled()
    mcf5307Yield()
