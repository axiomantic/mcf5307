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
# fault. The fault appears only when the archive goes into a shared object,
# which is the delivery form: the plugin then exports nothing, and the host
# cannot reach the core.
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
# The one-time latch.
#
# It holds three states in one atomic word. Measured on Nim 2.2.10, the C
# translation is a file-scope `_Atomic NI64` with no initializer. Its value is
# therefore zero before any Nim code runs, and the generated module initializer
# holds no write to it. The latch needs no initializing call of its own.
# That property is required and not incidental: this procedure runs before the
# Nim runtime exists, so anything it touches must be correct at zero.
const
  latchUntouched = 0
  latchRunning = 1
  latchDone = 2

var latch: Atomic[int]

# True while this thread is inside `mcf5307_NimMain`. It translates to a
# zero-initialized `NIM_THREADVAR`, so it needs no initializing call either. It
# is what separates a re-entrant call on the initializing thread from a
# concurrent first call on some other thread. The two look alike at the latch
# and need opposite answers.
var initializing {.threadvar.}: bool

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
  ## A caller that loses the exchange waits. Returning early would hand back a
  ## runtime that does not exist yet, which is the same defect the latch is
  ## here to prevent.
  if latch.load(moAcquire) == latchDone:
    return

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
  else:
    # Another thread claimed the latch. Wait for it to finish.
    while latch.load(moAcquire) != latchDone:
      cpuRelax()
