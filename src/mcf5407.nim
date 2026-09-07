## The Nim entry module of the `mcf5407` project.
##
## The build passes `--nimMainPrefix:mcf5407_` for this module. A second Nim
## library passes its own prefix and exports its own
## `<component>_runtime_init`, and nothing else changes.

# The core submodules. The entry module imports them so that the compiler
# compiles them into this library; it never names their symbols itself. The
# `UnusedImport` warning is therefore expected and is masked. The exported
# `mcf5407_*` state functions the submodules carry are reached from C by name
# (see `include/mcf5407.h` and `tests/abi_smoke.cpp`).
{.push warning[UnusedImport]: off.}
import mcf5407/alu
import mcf5407/cpu
import mcf5407/decode
import mcf5407/decode_types
import mcf5407/ea
import mcf5407/logic
import mcf5407/machine
import mcf5407/move
import mcf5407/state
# The ISP1181 device model. It is a sibling of the core rather than a part of
# it, and it is named here for the same reason the core submodules are: the
# compiler builds a module this entry module reaches and no other.
import isp1181/state
import isp1181/stub
{.pop.}

# The latch. It is imported outside the pushed warning mask because this
# module names its symbols below.
import mcf5407/latch

# ---------------------------------------------------------------------------
# The pragma set of every symbol this project publishes.
#
# Each exported procedure carries `{.exportc: "<c name>", mcf5407Abi.}` and
# nothing less. `mcf5407Abi` holds `cdecl` and `dynlib` together, so that the
# set is written once and no later edit can supply half of it.
#
# `dynlib` is load-bearing. Measured on Nim 2.2.10, a procedure declared
# `{.exportc, cdecl.}` alone translates to `N_LIB_PRIVATE`, and `nimbase.h`
# defines that as `__attribute__((visibility("hidden")))` for gcc and clang.
# The same procedure with `dynlib` translates to `N_LIB_EXPORT`, which is
# `__attribute__((visibility("default")))`.
#
# A hidden symbol still reports as `T` in `nm` output over the static archive,
# so `nm libmcf5407.a` cannot find this fault. The fault appears only when the
# archive goes into a shared object, which is the delivery form. The plugin
# then exports nothing, and the host cannot reach the core.
#
# `cmake/Nim.cmake` step 4a builds a shared object at configure time and reads
# its symbol table. A published symbol the object defines and does not export
# fails the configure step. The check reads the linker's answer and no Nim
# macro, so a Nim release that renames `N_LIB_EXPORT` changes nothing about it.
#
# `include/mcf5407.h` describes the set as `{.exportc, cdecl.}`, without
# `dynlib`. This file is the one the compiler reads.
{.pragma: mcf5407Abi, cdecl, dynlib.}

# ---------------------------------------------------------------------------
# `mcf5407_NimMain` is the runtime initializer that `--nimMainPrefix:mcf5407_`
# renames. The prefix is what lets a second Nim library live in the same
# binary, because the collision is on the default names alone.
proc mcf5407_NimMain() {.importc: "mcf5407_NimMain", cdecl, gcsafe,
                         raises: [].}

# ---------------------------------------------------------------------------
# `mcf5407_runtime_init` - the published entry point.
#
# The mechanism is in `mcf5407/latch` and not here. Two other modules ask the
# same latch whether the runtime was abandoned before they allocate, and a
# suite drives it directly; that module states why neither can reach it
# through this one.

proc mcf5407RuntimeInit(): cint {.exportc: "mcf5407_runtime_init",
                                  mcf5407Abi.} =
  ## Runs the Nim runtime's initializer once and reports whether it succeeded.
  ##
  ## C++ never names `mcf5407_NimMain`. It calls this procedure instead.
  ##
  ## The return is 1 for usable and 0 for not, which is the convention every
  ## other `int` in `include/mcf5407.h` already uses. It is not a POSIX-style
  ## error code, and mixing the two conventions inside one contract is the
  ## footgun that decided it.
  ##
  ## Why the status alone is not the guarantee. A caller must not proceed with
  ## a runtime that does not exist. C lets a caller drop
  ## a return value, so the status alone would not have kept that guarantee.
  ## `mcf5407_create` and `isp1181_create` read the latch themselves and hand
  ## back no context once it is abandoned, and every other call in the contract
  ## already answers a documented benign value for a nil context. A caller that
  ## ignores this status therefore gets a library that does nothing, and never
  ## one that answers from an uninitialized runtime.
  if runtimeInitOnce(runtimeLatch, mcf5407_NimMain):
    cint(1)
  else:
    cint(0)
