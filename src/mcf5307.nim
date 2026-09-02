## The Nim entry module of the `mcf5307` project.
##
## This module is the only Nim entry module. The build passes
## `--nimMainPrefix:mcf5307_` for it. A second Nim library passes its own
## prefix and exports its own `<component>_runtime_init`, and nothing else
## changes.

# The core submodules. The entry module imports them so that the compiler
# compiles them into this library; it never names their symbols itself. The
# `UnusedImport` warning is therefore expected and is masked. The exported
# `mcf5307_*` state functions the submodules carry are reached from C by name
# (see `include/mcf5307.h` and `tests/abi_smoke.cpp`).
{.push warning[UnusedImport]: off.}
import mcf5307/alu
import mcf5307/cpu
import mcf5307/decode
import mcf5307/decode_types
import mcf5307/ea
import mcf5307/logic
import mcf5307/machine
import mcf5307/move
import mcf5307/state
# The ISP1181 device model. It is a sibling of the core rather than a part of
# it, and it is named here for the same reason the core submodules are: the
# compiler builds a module this entry module reaches and no other.
import isp1181/state
import isp1181/stub
{.pop.}

# The latch. It is imported outside the pushed warning mask because this
# module names its symbols below.
import mcf5307/latch

# ---------------------------------------------------------------------------
# The pragma set of every symbol this project publishes.
#
# Each exported procedure carries `{.exportc: "<c name>", mcf5307Abi.}` and
# nothing less. `mcf5307Abi` holds `cdecl` and `dynlib` together, so that the
# set is written once and no later edit can supply half of it.
#
# `dynlib` is load-bearing. Measured on Nim 2.2.10, a procedure declared
# `{.exportc, cdecl.}` alone translates to `N_LIB_PRIVATE`, and `nimbase.h`
# defines that as `__attribute__((visibility("hidden")))` for gcc and clang.
# The same procedure with `dynlib` translates to `N_LIB_EXPORT`, which is
# `__attribute__((visibility("default")))`.
#
# A hidden symbol still reports as `T` in `nm` output over the static archive,
# so `nm libmcf5307.a` cannot find this fault. The fault appears only when the
# archive goes into a shared object, which is the delivery form. The plugin
# then exports nothing, and the host cannot reach the core.
#
# `cmake/Nim.cmake` step 4a builds a shared object at configure time and reads
# its symbol table. A published symbol the object defines and does not export
# fails the configure step. The check reads the linker's answer and no Nim
# macro, so a Nim release that renames `N_LIB_EXPORT` changes nothing about it.
#
# `include/mcf5307.h` describes the set as `{.exportc, cdecl.}`, without
# `dynlib`. This file is the one the compiler reads.
{.pragma: mcf5307Abi, cdecl, dynlib.}

# ---------------------------------------------------------------------------
# `mcf5307_NimMain` is the runtime initializer that `--nimMainPrefix:mcf5307_`
# renames. The prefix is what lets a second Nim library live in the same
# binary, because the collision is on the default names alone.
proc mcf5307_NimMain() {.importc: "mcf5307_NimMain", cdecl, gcsafe,
                         raises: [].}

# ---------------------------------------------------------------------------
# `mcf5307_runtime_init` - the published entry point, and the only caller of
# the runtime entry point in this project.
#
# The mechanism is in `mcf5307/latch` and not here. Two other modules ask the
# same latch whether the runtime was abandoned before they allocate, and a
# suite drives it directly; that module states why neither can reach it
# through this one.

proc mcf5307RuntimeInit(): cint {.exportc: "mcf5307_runtime_init",
                                  mcf5307Abi.} =
  ## Runs the Nim runtime's initializer once and reports whether it succeeded.
  ##
  ## C++ never names `mcf5307_NimMain`. It calls this procedure instead.
  ##
  ## The return is 1 for usable and 0 for not, which is the convention every
  ## other `int` in `include/mcf5307.h` already uses. It is not a POSIX-style
  ## error code, and mixing the two conventions inside one contract is the
  ## footgun that decided it.
  ##
  ## What replaces the abort's guarantee. The abort existed so that a caller
  ## could not proceed with a runtime that does not exist. C lets a caller drop
  ## a return value, so the status alone would not have kept that guarantee.
  ## `mcf5307_create` and `isp1181_create` read the latch themselves and hand
  ## back no context once it is abandoned, and every other call in the contract
  ## already answers a documented benign value for a nil context. A caller that
  ## ignores this status therefore gets a library that does nothing, and never
  ## one that answers from an uninitialized runtime.
  if runtimeInitOnce(runtimeLatch, mcf5307_NimMain):
    cint(1)
  else:
    cint(0)
