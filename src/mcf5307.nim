## The Nim entry module of the `mcf5307` project.
##
## THIS MODULE IS THE ONLY NIM ENTRY MODULE, and the build passes
## `--nimMainPrefix:mcf5307_` for it. Design section 5.5 keeps the one-project
## rule as a convention: a second Nim library passes its own prefix and exports
## its own `<component>_runtime_init`, and nothing else changes.
##
## Task CPU-1 creates this file and gives it the runtime entry point alone. The
## core and the ISP1181 model are the work of the later cpu tasks, and they add
## their `{.exportc.}` procedures to this project.
##
## MIT licensed and clean-room with respect to GPL and LGPL code.

# `mcf5307_NimMain` is the runtime initialiser that `--nimMainPrefix:mcf5307_`
# renames. The prefix is what lets a second Nim library live in the same
# binary, because the collision is on the DEFAULT names alone.
proc mcf5307_NimMain() {.importc: "mcf5307_NimMain", cdecl.}

# The idempotence latch. It is a plain boolean, so the C translation is a
# zero-initialised static and its value is false before any Nim code runs.
var runtimeReady = false

proc mcf5307RuntimeInit() {.exportc: "mcf5307_runtime_init", cdecl, dynlib.} =
  ## Runs the Nim runtime's initialiser once.
  ##
  ## C++ NEVER NAMES `mcf5307_NimMain`. It calls this procedure, which is what
  ## design section 5.4 rule 2 requires, and this procedure is the only caller
  ## of the runtime entry point in the project.
  ##
  ## The latch is set AFTER the call and not before it. Module initialisation
  ## runs inside `mcf5307_NimMain`, so a latch set before the call could be
  ## written back to its initial value by that initialisation and every later
  ## call would then run the initialiser again.
  if not runtimeReady:
    mcf5307_NimMain()
    runtimeReady = true
