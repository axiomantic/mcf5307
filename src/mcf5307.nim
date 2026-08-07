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
# `cmake/Nim.cmake` step 4a BUILDS A SHARED OBJECT AT CONFIGURE TIME AND READS
# ITS SYMBOL TABLE. A published symbol the object defines and does not export
# fails the configure step. The check reads the linker's answer and it reads no
# Nim macro, so this comment is enforceable rather than advisory, and a Nim
# release that renames `N_LIB_EXPORT` changes nothing about it.
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
# THE DEADLINE USES A MONOTONIC CLOCK AND NOT THE WALL CLOCK. `time` was here
# before and it was wrong for two separate reasons.
#
#   Its resolution is one second, and the deadline is `time() + 5`. The start
#   is truncated to a whole second and the comparison is truncated again, so
#   the true wait is anything between four and five seconds. Measured over six
#   runs of a harness in which one thread claims the latch and never releases
#   it: 4.53, 4.99, 4.99, 4.99, 4.99 and 4.99 seconds. Not one run waited the
#   five seconds the constant names.
#
#   `time` reads the SETTABLE wall clock. An operator, NTP or a container start
#   can step it backwards at any moment. A backward step moves the deadline
#   away from the waiter, and the loop then spins with no end. That is the
#   unbounded spin this whole deadline exists to close, re-opened by a clock
#   adjustment.
#
# `clock_gettime(CLOCK_MONOTONIC)` counts from an arbitrary origin, no caller
# can set it, and its resolution is nanoseconds. `GetTickCount64` is the
# Windows equivalent and it counts milliseconds since boot. The file already
# carries a `when defined(windows)` branch for the yield, so a second branch
# costs nothing new.
#
# `sched_yield`, or `SwitchToThread` on Windows, hands the core to another
# thread. The wait loop below calls it. The loop it replaces called `cpuRelax`
# alone and yielded to nothing. THE WINDOWS BRANCH OF BOTH IS UNMEASURED. This
# host is macOS and it builds the other branch.

when defined(windows):
  proc mcf5307TickCount(): uint64 {.
      importc: "GetTickCount64", header: "<windows.h>", stdcall.}

  proc mcf5307MonotonicMillis(): int64 =
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

  proc mcf5307MonotonicMillis(): int64 =
    ## The monotonic clock in milliseconds.
    ##
    ## A failure of `clock_gettime` is not handled here, and it cannot be:
    ## this procedure runs before the Nim runtime exists and the contract
    ## carries no failure channel. `CLOCK_MONOTONIC` is mandatory in POSIX
    ## 2008 and the call fails only for an invalid clock identifier.
    var now: MCF5307TimeSpec
    discard mcf5307ClockGetTime(mcf5307ClockMonotonic, addr now)
    int64(now.tv_sec) * 1000'i64 + int64(now.tv_nsec) div 1_000_000'i64

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

# How long a caller waits for another thread to finish the initializer.
#
# THE BOUND IS A TRADE AND THE MARGIN IS MEASURED. `mcf5307_runtime_init` was
# timed with `clock_gettime(CLOCK_MONOTONIC)` around the call, one measurement
# per process because the latch is one-time, over 20 processes on this host
# (macOS 26.5.1, arm64, Nim 2.2.10, clang -O2):
#
#   8000 5000 5000 5000 6000 6000 3000 6000 6000 7000
#   5000 7000 4000 6000 7000 5000 5000 6000 5000 5000    nanoseconds
#
#   minimum 3.0 us, maximum 8.0 us, mean 5.6 us over 20 runs.
#
# The bound is therefore about 625000 times the slowest run measured. A
# runtime initializer that needs five seconds is already broken. A wait with no
# bound cannot report a stall at all, and that outcome is worse.
#
# The unit is milliseconds because the clock below reports milliseconds.
const latchWaitMillis = 5000'i64

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
  ## ENDING THE PROCESS IS THE WRONG ANSWER AND IT IS THE ONLY ONE AVAILABLE.
  ## THE REAL DEFECT IS IN THE CONTRACT, AND CPU-0 OWNS IT. A library has no
  ## business killing its host. A JUCE plugin that aborts takes the whole
  ## digital audio workstation with it, and the user loses unsaved work that
  ## has nothing to do with this core. The correct behaviour is to report the
  ## failure to the caller and let the host decide.
  ##
  ## `include/mcf5307.h` declares `void mcf5307_runtime_init(void)`. THAT
  ## SIGNATURE CARRIES NO FAILURE CHANNEL: no return value, no out-parameter
  ## and no status call. There is no way for this procedure to say `I failed`
  ## and return. `c_abort` is what is left.
  ##
  ## CPU-1 CANNOT REPAIR THIS FROM THIS FILE, AND THE REPAIR TO THE GATE IS
  ## WHAT MAKES THAT MECHANICAL. `cmake/Nim.cmake` step 4a now fails the
  ## configure step over ANY symbol the shared object exports that the contract
  ## does not declare. Adding an `mcf5307_runtime_status` here would therefore
  ## stop the configure step. The contract header belongs to CPU-0, and the
  ## channel has to be added there first.
  ##
  ## What CPU-0 would have to add is one of:
  ##   `int mcf5307_runtime_init(void);`         a non-zero result on failure
  ##   `void mcf5307_runtime_init(int* status);` a status out-parameter
  ##   `int mcf5307_runtime_ready(void);`        a separate query
  ##
  ## `src/mcf5307.nim` then returns instead of aborting, and this procedure
  ## goes away. Until then the abort stands, and this comment is the record of
  ## why it stands rather than a defence of it.
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
  let deadline = mcf5307MonotonicMillis() + latchWaitMillis
  while true:
    let waitedState = latch.load(moAcquire)
    if waitedState == latchDone:
      return
    if waitedState == latchAbandoned:
      mcf5307LatchStalled()
    if mcf5307MonotonicMillis() >= deadline:
      # THE RESULT OF THE EXCHANGE IS READ AND IT IS NOT DISCARDED. There is a
      # race between the load above and this line. The initializing thread can
      # store `latchDone` in that window. The exchange then fails, `running`
      # comes back holding `latchDone`, and the runtime IS initialized. A
      # discarded result aborted a process whose runtime had just come up.
      #
      # A failure that reports any other value is a real stall. `latchRunning`
      # means the initializing thread is still inside and out of time.
      # `latchAbandoned` means another waiter reached its own deadline first.
      var running = latchRunning
      if not latch.compareExchange(
          running, latchAbandoned, moAcquireRelease, moAcquire):
        if running == latchDone:
          return
      mcf5307LatchStalled()
    mcf5307Yield()
