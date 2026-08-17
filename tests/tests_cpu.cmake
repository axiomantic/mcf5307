# The cpu track's registration list for `tests/`.
#
# CPU-26 CREATES THIS FILE EMPTY AND REGISTERS NOTHING IN IT. That is the
# correct state for the skeleton, and CPU-26's own check asserts it by reading
# `Total Tests: 0` out of the CTest listing.
#
# Each later cpu task adds its own `add_test(NAME <name> ...)` line here, with
# whatever target the name needs, and attaches that target to the `mcf5307_tests`
# aggregate that the root list creates, AFTER the `PROJECT_IS_TOP_LEVEL` guard
# below unless it has the same reason to outlive it the block above the guard has.

# --------------------------------------------------------------------- CPU-3
# `t0_abi_gate_on` - step 4a is switched ON in the tree this suite is running
# against.
#
# THE BANNER READ CPU-26 AND THAT WAS WRONG. Section 7.4.2's owner row, CPU-26's
# own block and the root list all three say CPU-26 registers no test of its own,
# and the section defines no third role for a registration that belongs to
# nobody. CPU-3 is the later task the second role names: it owns `cmake/Nim.cmake`
# as a declared second write, and the gate this test reads is its work.
#
# WHAT IT PROTECTS. What the OFF branch of step 4a does is `message(WARNING)`,
# and a warning fails neither `cmake`, nor `cmake --build`, nor `ctest`. The
# switch is a `CACHE BOOL`, so a directory configured OFF once stays OFF with
# nobody naming it again. The whole OFF state was therefore reportable only as
# one line of scrollback on a run that ends in exit 0 - the shape of a check
# that quietly does not run, which is the shape step 4a was written to end.
#
# THIS TEST IS THE ONLY THING IN THE REPOSITORY THAT FAILS WHEN THE GATE IS
# OFF. Measured 2026-08-12: `git grep -n MCF5307_ABI_GATE` answers with
# `cmake/Nim.cmake` and this file and nothing else. No CI step, no lint and no
# other test reads the switch. The command is `git grep` because a literal
# `grep -rn` also walks `.claude/worktrees/`, where an untracked checkout of
# this same repository carries its own `cmake/Nim.cmake`; measured the same
# day, that answered with a THIRD file.
#
# THE CACHE ENTRY IS NOT THE GATE. It is the SWITCH. A run can read `ON` out of
# `CMakeCache.txt` and still not have run step 4a: delete the branch and keep
# the `set(... CACHE BOOL)`, or let a parent list file shadow the entry with a
# NORMAL variable, which the docstring in `cmake/Nim.cmake` records. Both were
# MEASURED 2026-08-12 against the cache-only form this block replaces, and a
# cache-only assertion PASSED on each.
#
# SO THE ASSERTION IS ON AN ARTIFACT STEP 4a PRODUCED, AND THE CACHE CHECKS ARE
# KEPT BESIDE IT. `cmake/Nim.cmake` writes `mcf5307_abi_gate_ran.token` at the
# END of step 4a's own branch, carrying the counts the three parts measured and
# the number of sites that ran. This file MOVES that token - removes any
# previous stamp, then renames - into the binary directory ctest starts the
# driver in. The token is CONSUMED, so a stamp can be here only if step 4a
# wrote a token in the same run that moved it.
#
# WHAT THE MOVE DOES NOT CLOSE is a configure that ABORTS before this directory
# is read: nothing here runs to remove the previous stamp. MEASURED 2026-08-12:
# an honest tree passed, a fault injected inside step 4a made the reconfigure
# exit 1 without generating, and the test PASSED against the surviving stamp.
# So a stamp proves the branch ran through IN THE MOST RECENT CONFIGURE THAT
# REACHED `tests/`, which is what the pass line says. It is bounded: `cmake
# --build` on that tree re-runs cmake and exits 2, so CI never reaches ctest.
#
# THE MOVE IS WHY THERE IS NO MTIME COMPARISON. An existence-only stamp needs
# one, and `CMakeCache.txt` is the file it would have to name. MEASURED
# 2026-08-12 on a two-line probe project, both directions defeat it. Within one
# configure the cache is written AFTER every list file has run, so a stamp
# written by step 4a is ALWAYS older than the cache of its own run and the
# honest ON case would red. And a second configure that changed no entry left
# `CMakeCache.txt` at the mtime of the first while the probe's own list-file
# write moved forward, so the cache is not rewritten on every configure either
# - which makes a STALE stamp read NEWER than the cache. Consumption answers
# the question the mtime was reaching for without depending on either ordering.
#
# THE TWO OFFSETS ARE ANCHORED DIFFERENTLY ON PURPOSE. The token lands in THIS
# PROJECT's binary directory, `PROJECT_BINARY_DIR`; `CMakeCache.txt` is written
# once per BUILD TREE, `CMAKE_BINARY_DIR`. The two are the same directory ONLY
# when mcf5307 is top-level. MEASURED 2026-08-12 with the cache offset taken
# from `PROJECT_BINARY_DIR`: configured through `add_subdirectory()` it named
# `<build>/mcf5307_build`, which holds no cache, and the test was red on every
# run WITH THE GATE ON - closed rather than open, but broken in the
# configuration step 6 exists to serve.
#
# THE CACHE CHECKS ARE KEPT AND NOT REPLACED. They read the persisted entry,
# which is the thing that survives into the next configure, and they name a
# different fault: a tree whose switch is off, or whose switch is no longer
# declared, is a different report from a tree whose branch did not run.
#
# THE TWO FILES IT READS ARE RESOLVED AT RUN TIME AND NOT BAKED AT CONFIGURE
# TIME. What `add_test` records for each is a RELATIVE offset, resolved against
# the directory ctest starts the driver in, in whatever tree ctest was invoked
# in. An absolute path
# computed at configure time names THAT tree forever, and a build tree is a
# directory anyone can copy. MEASURED 2026-08-12 against the absolute form this
# replaces: configure a tree with `-DMCF5307_ABI_GATE=OFF`, copy it,
# reconfigure the ORIGINAL to ON, run ctest in the COPY - PASSED, exit 0,
# printing the ORIGINAL tree's path in its own pass line.
#
# THE ASSERTION IS ON CMAKE'S OWN BOOLEAN READING OF THE LITERAL, not on the
# spelling `ON`. `-DMCF5307_ABI_GATE=TRUE` and `-DMCF5307_ABI_GATE=1` are gates
# that ARE on, and a test that demanded the three letters would red on a tree
# whose gate runs. The literal is reported verbatim in both the pass line and
# the failure message, so the evidence is the value itself either way.
#
# THE COUNT CHECK IS NOT DECORATION. Zero entries means `cmake/Nim.cmake` no
# longer declares the switch at all, which is a way to lose step 4a that an
# ON/OFF assertion alone reads as a missing variable and CMake reads as false.
# The two are separated so the failure names which one happened.
#
# IT REGISTERS NO CHECK TARGET, AND `docs/check-targets.txt` IS LEFT EMPTY AND
# UNMODIFIED. VERIFIED 2026-08-12 in the tool: the check-target condition
# compares that file against a set harvested from the PLAN DOCUMENT and opens
# NO SOURCE FILE, so an `add_test()` written here puts a name into neither set.
# The file's own prose - it declares the targets of tasks declared COMPLETE -
# is no filter in that comparison, so the empty file is correct because no name
# reaches either set and NOT because a filter holds incomplete tasks back. The
# prose is not inert: a SECOND half of the same tool reads the same file, by a
# different rule, as a completion signal. Neither reading reaches this block.
#
# The `t0_` prefix is what puts this name in front of CI instead -
# `.github/workflows/ci.yml` runs `-R '^t0_'` in two jobs, and this name joins
# that pattern with no edit to the workflow.

# The consume step. It runs on EVERY configure, because this file is what
# registers the test: a configure that does not reach this line registers no
# `t0_abi_gate_on` at all, which `--no-tests=error` and the suite's own count
# report as a missing test rather than as a pass. The removal comes first so
# that a configure which finds no token leaves no stamp behind.
#
# THE TOKEN IS HELD AGAINST THE VARIABLE `cmake/Nim.cmake` LEFT BESIDE IT.
# WHAT THAT REJECTS is a token on disk that step 4a's branch did not write in
# this run. Measured 2026-08-12 without the comparison: a token planted in the
# build tree, with step 4a's whole branch then deleted from `cmake/Nim.cmake`,
# was moved here and the test PASSED. A rejected token is removed rather than
# left, so the next configure starts from the same place a clean one does.
#
# WHAT IT DOES NOT REJECT IS `-D`. The variable is NOT set by this run or not
# at all: `cmake -DMCF5307_ABI_GATE_RECORD=<text>` creates a cache entry, the
# same persistence `MCF5307_ABI_GATE` has and this test exists to catch.
# MEASURED 2026-08-12 against a branch-deleted source with a token planted by
# hand, one configure naming `-D` PASSED and the entry landed as
# `MCF5307_ABI_GATE_RECORD:UNINITIALIZED=`. It is bounded twice, and neither
# bound makes the old claim safe to restate. The record is multi-line and CMake
# truncates a cached value at the first newline, so a later configure that does
# not name `-D` reds - measured the same run. And naming it is hand-writing the
# record with an extra step, which belongs with forging the stamp.
#
# DELETING THIS STEP IS NOT A QUIET WAY TO DISARM THE TEST. The offset computed
# below names `MCF5307_GATE_STAMP`, so a tree without this step reaches
# `file(RELATIVE_PATH)` with an empty argument. MEASURED 2026-08-12: `CMake
# Error ... file RELATIVE_PATH must be passed a full path to the file`, and the
# configure ends non-zero with no test registered at all.
set(MCF5307_GATE_TOKEN "${PROJECT_BINARY_DIR}/mcf5307_abi_gate_ran.token")
set(MCF5307_GATE_STAMP "${CMAKE_CURRENT_BINARY_DIR}/t0_abi_gate_ran.stamp")
file(REMOVE "${MCF5307_GATE_STAMP}")
if(EXISTS "${MCF5307_GATE_TOKEN}")
    file(READ "${MCF5307_GATE_TOKEN}" MCF5307_GATE_TOKEN_TEXT)
    if(MCF5307_ABI_GATE_RECORD AND
       "${MCF5307_GATE_TOKEN_TEXT}" STREQUAL "${MCF5307_ABI_GATE_RECORD}")
        file(RENAME "${MCF5307_GATE_TOKEN}" "${MCF5307_GATE_STAMP}")
    else()
        file(REMOVE "${MCF5307_GATE_TOKEN}")
    endif()
endif()

file(RELATIVE_PATH MCF5307_GATE_CACHE_OFFSET
    "${CMAKE_CURRENT_BINARY_DIR}" "${CMAKE_BINARY_DIR}/CMakeCache.txt")
file(RELATIVE_PATH MCF5307_GATE_STAMP_OFFSET
    "${CMAKE_CURRENT_BINARY_DIR}" "${MCF5307_GATE_STAMP}")

# THE DRIVER IS A SOURCE FILE AND THE OFFSETS STILL RESOLVE AGAINST THE BUILD
# TREE. `cmake -P` sets `CMAKE_CURRENT_BINARY_DIR` to the WORKING DIRECTORY and
# never to the script's own directory. MEASURED 2026-08-12 on CMake 4.3.4, with
# a decoy `CMakeCache.txt` reading OFF planted where a script-anchored
# resolution would have landed: the driver read the build tree's cache.
add_test(NAME t0_abi_gate_on
    COMMAND "${CMAKE_COMMAND}"
        "-DGATE_CACHE_OFFSET=${MCF5307_GATE_CACHE_OFFSET}"
        "-DGATE_STAMP_OFFSET=${MCF5307_GATE_STAMP_OFFSET}"
        -P "${CMAKE_CURRENT_LIST_DIR}/t0_abi_gate_on.cmake")

# THE BLOCK ABOVE REGISTERS IN EVERY TREE AND EVERYTHING BELOW ONLY AT TOP
# LEVEL. A test that runs in a tree no task owns is a test whose failure has no
# owner. THE GATE ASSERTION IS THE EXCEPTION ON PURPOSE: `add_subdirectory()` is
# where a hidden published symbol breaks a plugin, and it is the configuration
# the parent-variable shadow of `MCF5307_ABI_GATE` was found in.
if(NOT PROJECT_IS_TOP_LEVEL)
    return()
endif()

# --------------------------------------------------------------------- CPU-0
# `t0_abi_header` - the application binary interface contract.
#
# ONE REGISTERED NAME, FOUR CASES, AND EACH ONE CAN FAIL:
#
#   1  `include/mcf5307.h` compiles as C11, warning-clean. IT NEVER LINKS.
#   2  the same header compiles as C++17, warning-clean. IT NEVER LINKS.
#   3  `t0_abi_header.c`   COMPILES AND LINKS against `abi_stub.c`, and runs.
#   4  `t0_abi_header.cpp` COMPILES AND LINKS against `abi_stub.c`, and runs.
#
# `-fsyntax-only` stops before the link, so cases 1 and 2 catch a header that
# does not compile and can catch NO rename at all. Cases 3 and 4 link, which
# is what turns a renamed declaration into an error rather than into nothing,
# and the stub is what makes them linkable at this task's completion: the real
# implementation is written by a later task that depends on this contract.
#
# THE COMPILE AND THE LINK OF CASES 3 AND 4 HAPPEN INSIDE THE TEST, NOT IN THE
# BUILD. If the build produced the two executables and the test only ran them,
# then a `ctest` run over a tree whose build had failed would run the STALE
# executables from the previous build and pass. The check is one `ctest`
# command, so the command has to be sufficient on its own.
#
# The four cases run from a driver script that this file WRITES INTO THE BUILD
# TREE. The driver is a build artifact and not a source file, because this
# task owns four files and a fifth committed file would be a file with no
# owner. It runs all four cases, reports each one by name, and fails if any
# one of them failed.

file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/t0_abi_header_driver.cmake" [==[
# GENERATED BY tests/tests_cpu.cmake. Do not edit this copy in the build tree.
#
# The driver of the registered test `t0_abi_header`. It runs FOUR CASES and
# reports every one of them, so that a run names each failure rather than
# stopping at the first.

set(abi_failures "")
set(abi_flags -Wall -Wextra -pedantic -Werror)

# A case is one label and one or more STEPS. The first step that fails ends
# the case: the later steps are skipped, because compiling an executable that
# did not link and running an executable that did not build report a second
# failure that says nothing the first did not already say. Skipping the run
# after a failed compile is also what stops a STALE executable from an earlier
# run being executed and reported as a pass.
macro(abi_begin_case abi_label)
    set(abi_current "${abi_label}")
    set(abi_rc "0")
    set(abi_out "")
    set(abi_err "")
endmacro()

macro(abi_step)
    if(abi_rc STREQUAL "0")
        execute_process(COMMAND ${ARGN}
                        RESULT_VARIABLE abi_rc
                        OUTPUT_VARIABLE abi_out
                        ERROR_VARIABLE abi_err)
    endif()
endmacro()

macro(abi_end_case)
    if(abi_rc STREQUAL "0")
        message("PASSED  ${abi_current}")
    else()
        message("FAILED  ${abi_current}  (result: ${abi_rc})")
        if(NOT abi_out STREQUAL "")
            message("${abi_out}")
        endif()
        if(NOT abi_err STREQUAL "")
            message("${abi_err}")
        endif()
        list(APPEND abi_failures "${abi_current}")
    endif()
endmacro()

# Cases 1 and 2 carry `-fsyntax-only` and name no output file, so they stop
# after the parse. NOTHING LINKS HERE AND NOTHING RUNS HERE.
abi_begin_case("case 1: include/mcf5307.h compiles as C11")
abi_step("${ABI_C_COMPILER}" -std=c11 -fsyntax-only ${abi_flags}
         -x c "${ABI_HEADER}")
abi_end_case()

abi_begin_case("case 2: include/mcf5307.h compiles as C++17")
abi_step("${ABI_CXX_COMPILER}" -std=c++17 -fsyntax-only ${abi_flags}
         -x c++ "${ABI_HEADER}")
abi_end_case()

# Case 3. The stub is compiled as C, linked with the C assertions, and run.
# Each case compiles its OWN copy of the stub, so that neither case can fail
# because of a step the other one owns.
abi_begin_case("case 3: the C surface links against the stub and runs")
abi_step("${ABI_C_COMPILER}" -std=c11 ${abi_flags} "-I${ABI_INCLUDE_DIR}"
         -c -o "${ABI_WORK_DIR}/abi_stub_for_c.o" "${ABI_SRC_DIR}/abi_stub.c")
abi_step("${ABI_C_COMPILER}" -std=c11 ${abi_flags} "-I${ABI_INCLUDE_DIR}"
         -o "${ABI_WORK_DIR}/t0_abi_header_c"
         "${ABI_SRC_DIR}/t0_abi_header.c" "${ABI_WORK_DIR}/abi_stub_for_c.o")
abi_step("${ABI_WORK_DIR}/t0_abi_header_c")
abi_end_case()

# Case 4. THE STUB IS STILL COMPILED AS C, because that is what it is, and the
# C++ assertions link against it. The header's `extern "C"` block is what makes
# that link resolve, so a header that lost it fails here on a mangled name.
# The two compilers are invoked separately because one command cannot carry
# both `-std=c11` and `-std=c++17`.
abi_begin_case("case 4: the C++ surface links against the stub and runs")
abi_step("${ABI_C_COMPILER}" -std=c11 ${abi_flags} "-I${ABI_INCLUDE_DIR}"
         -c -o "${ABI_WORK_DIR}/abi_stub_for_cpp.o" "${ABI_SRC_DIR}/abi_stub.c")
abi_step("${ABI_CXX_COMPILER}" -std=c++17 ${abi_flags} "-I${ABI_INCLUDE_DIR}"
         -o "${ABI_WORK_DIR}/t0_abi_header_cpp"
         "${ABI_SRC_DIR}/t0_abi_header.cpp"
         "${ABI_WORK_DIR}/abi_stub_for_cpp.o")
abi_step("${ABI_WORK_DIR}/t0_abi_header_cpp")
abi_end_case()

if(NOT abi_failures STREQUAL "")
    list(LENGTH abi_failures abi_failure_count)
    message(FATAL_ERROR
        "t0_abi_header: ${abi_failure_count} of 4 cases failed: ${abi_failures}")
endif()

message("t0_abi_header: 4 of 4 cases passed")
]==])

add_test(NAME t0_abi_header
    COMMAND "${CMAKE_COMMAND}"
        "-DABI_C_COMPILER=${CMAKE_C_COMPILER}"
        "-DABI_CXX_COMPILER=${CMAKE_CXX_COMPILER}"
        "-DABI_HEADER=${PROJECT_SOURCE_DIR}/include/mcf5307.h"
        "-DABI_INCLUDE_DIR=${PROJECT_SOURCE_DIR}/include"
        "-DABI_SRC_DIR=${CMAKE_CURRENT_LIST_DIR}"
        "-DABI_WORK_DIR=${CMAKE_CURRENT_BINARY_DIR}"
        -P "${CMAKE_CURRENT_BINARY_DIR}/t0_abi_header_driver.cmake")

# -------------------------------------------------------------------- CPU-20
# `t_checks_on` - the run-time checks stay compiled in.
#
# ONE REGISTERED NAME, TWO CASES, AND EACH ONE CAN FAIL:
#
#   1  an IN-RANGE index prints the element and exits 0. THIS IS THE POSITIVE
#      CONTROL. Without it a run in which the program exited 1 for a reason of
#      its own would report case 2 as a pass, and "the check fired" would not
#      be separable from "the program cannot run at all".
#   2  an OUT-OF-RANGE index ends the process. The case asserts the exit
#      status 1 AND the whole defect line, because `--checks:off` turns the
#      same run into a wrong value with exit status 0 and, on another host,
#      into a signal - and an exit status on its own does not separate those
#      three outcomes.
#
# THE FLAG SET IS TAKEN FROM THE LIBRARY'S OWN COMPILE COMMAND AND IS NEVER
# WRITTEN OUT AGAIN HERE. That is the whole point of the test: it asserts a
# property of the flags `cmake/Nim.cmake` passes, so a flag added there - a
# `--checks:off` among them - reaches this program too. A test that carried
# its own copy of the flag set would assert a property of a flag set nothing
# else uses, and the library could lose its checks with this test still green.
#
# THE COMPILE HAPPENS INSIDE THE TEST AND NOT IN THE BUILD, for the reason
# `t0_abi_header` gives above: a `ctest` run over a tree whose build had
# failed would otherwise run the STALE binary of an earlier build and pass.

if(NOT DEFINED MCF5307_NIM_COMMAND)
    message(FATAL_ERROR
        "tests: t_checks_on cannot be registered: MCF5307_NIM_COMMAND is not "
        "set. The test takes its flag set from the library's own compile "
        "command, and a test registered against an empty command would "
        "compile with no flags at all and assert nothing.")
endif()

# The arguments below belong to the OBJECT-LIBRARY build alone. A test program
# is linked and run, so it needs its own main and its own output binary, and
# it carries neither the generated header nor the runtime prefix. Everything
# else - `--mm:arc`, `--panics:on`, `-d:release`, and anything a later task
# adds - is kept.
set(MCF5307_CHECKS_ON_COMMAND "")
foreach(argument IN LISTS MCF5307_NIM_COMMAND)
    if(argument STREQUAL "--compileOnly"
            OR argument STREQUAL "--noMain"
            OR argument MATCHES "^--nimcache:"
            OR argument MATCHES "^--header:"
            OR argument MATCHES "^--nimMainPrefix:"
            OR argument MATCHES "\\.nim$")
        continue()
    endif()
    list(APPEND MCF5307_CHECKS_ON_COMMAND "${argument}")
endforeach()

set(NIM_COMMAND_LITERAL "")
foreach(argument IN LISTS MCF5307_CHECKS_ON_COMMAND)
    string(APPEND NIM_COMMAND_LITERAL "    \"${argument}\"\n")
endforeach()

set(SOURCE "${CMAKE_CURRENT_LIST_DIR}/t_checks_on.nim")
set(BINARY "${CMAKE_CURRENT_BINARY_DIR}/t_checks_on_program")
set(NIMCACHE "${CMAKE_CURRENT_BINARY_DIR}/t_checks_on_nimcache")

set(MCF5307_CHECKS_ON_DRIVER_TEMPLATE [==[
# GENERATED BY tests/tests_cpu.cmake. Do not edit this copy in the build tree.
#
# The driver of the registered test `t_checks_on`. It compiles the Nim test
# program with THE LIBRARY'S OWN FLAG SET, runs it twice, and reports both
# cases, so that a run names each failure rather than stopping at the first.

set(nim_command
@NIM_COMMAND_LITERAL@)
set(source "@SOURCE@")
set(binary "@BINARY@")
set(nimcache "@NIMCACHE@")

set(checks_failures "")

# The binary of an earlier run is REMOVED BEFORE THE COMPILE. Without this a
# compile that failed would leave the earlier binary in place, and both cases
# would then run code this run never produced.
file(REMOVE "${binary}")

execute_process(
    COMMAND ${nim_command} "--nimcache:${nimcache}" "-o:${binary}" "${source}"
    RESULT_VARIABLE checks_compile_rc
    OUTPUT_VARIABLE checks_compile_out
    ERROR_VARIABLE checks_compile_err)

if(NOT checks_compile_rc EQUAL 0)
    message(FATAL_ERROR
        "t_checks_on: the Nim test program did not compile "
        "(result: ${checks_compile_rc})\n"
        "${checks_compile_out}\n${checks_compile_err}")
endif()

# Case 1. THE POSITIVE CONTROL. The whole standard output is compared, and not
# a part of it, so that a program which printed the right number among wrong
# text would fail here.
execute_process(
    COMMAND "${binary}" "3"
    RESULT_VARIABLE checks_rc_1
    OUTPUT_VARIABLE checks_out_1
    ERROR_VARIABLE checks_err_1)
string(STRIP "${checks_out_1}" checks_out_1_text)

if(checks_rc_1 EQUAL 0 AND checks_out_1_text STREQUAL "scratch[3] = 40")
    message("PASSED  case 1: an in-range index prints `scratch[3] = 40` and exits 0")
else()
    message("FAILED  case 1: an in-range index prints `scratch[3] = 40` and exits 0")
    message("  result : ${checks_rc_1}")
    message("  stdout : ${checks_out_1_text}")
    message("  stderr : ${checks_err_1}")
    list(APPEND checks_failures "case 1")
endif()

# Case 2. The out-of-range index. THE WHOLE DEFECT LINE IS MATCHED, anchored
# at both ends of the line, and not a bare fragment of it: the index, the
# range and the defect name all have to be right. The traceback that follows
# the line is not matched, because its frames are a property of the Nim
# release rather than of the flag set this case asserts.
execute_process(
    COMMAND "${binary}" "4"
    RESULT_VARIABLE checks_rc_2
    OUTPUT_VARIABLE checks_out_2
    ERROR_VARIABLE checks_err_2)
set(checks_combined_2 "${checks_out_2}${checks_err_2}")

if(checks_rc_2 EQUAL 1 AND checks_combined_2 MATCHES
        "(^|\n)Error: unhandled exception: index 4 not in 0 \\.\\. 3 \\[IndexDefect\\](\r?\n|$)")
    message("PASSED  case 2: an out-of-range index reports IndexDefect and exits 1")
else()
    message("FAILED  case 2: an out-of-range index reports IndexDefect and exits 1")
    message("  result : ${checks_rc_2}")
    message("  stdout : ${checks_out_2}")
    message("  stderr : ${checks_err_2}")
    list(APPEND checks_failures "case 2")
endif()

if(NOT checks_failures STREQUAL "")
    list(LENGTH checks_failures checks_failure_count)
    message(FATAL_ERROR
        "t_checks_on: ${checks_failure_count} of 2 cases failed: ${checks_failures}")
endif()

message("t_checks_on: 2 of 2 cases passed")
]==])

string(CONFIGURE "${MCF5307_CHECKS_ON_DRIVER_TEMPLATE}"
    MCF5307_CHECKS_ON_DRIVER @ONLY)
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/t_checks_on_driver.cmake"
    "${MCF5307_CHECKS_ON_DRIVER}")

add_test(NAME t_checks_on
    COMMAND "${CMAKE_COMMAND}"
        -P "${CMAKE_CURRENT_BINARY_DIR}/t_checks_on_driver.cmake")
# --------------------------------------------------------------------- CPU-6
# `t_ea_masks` - the decoder and effective-address legality masks.
#
# ONE REGISTERED NAME, AND EVERY CASE CAN FAIL.
#
# THE CASE COUNT AND THE OPCODE ROSTER ARE DELIBERATELY NOT WRITTEN DOWN HERE.
# This block used to name FIFTEEN cases over a hand-maintained list of four
# opcodes, and that hand-maintained list is precisely the defect
# `tests/t_ea_masks.nim` was rewritten to abolish: an opcode that gained a
# legality mask went SILENTLY UNCOVERED instead of LOUDLY MISSING, and the
# stated count went stale without anything turning red. A count restated here
# would decay the same silent way. The program prints its own count and its own
# attribution figure on the summary line the driver below matches, and THAT
# LINE IS THE LIVE FIGURE. In case order:
#
#   FIRST  `exec` runs a NOP fetch and returns a non-zero cycle count - the
#      assertion that moved here from CPU-3 (W3-7). Drives
#      `mcf5307_create`/`mcf5307_reset`/`mcf5307_exec`/`mcf5307_destroy`
#      through the real ABI against a board that answers `MCF5307_BUS_OK`.
#   THEN  EA legality, ENUMERATED OVER `Operation` AND NOT OVER A ROSTER OF
#      OPCODE NAMES. Every operation whose `eaLegalityFor` mask is NON-EMPTY
#      carries FOUR assertions: the mask REJECTS an illegal mode cited from the
#      MCF5307 User's Manual and never derived from the mask itself, the mask
#      ACCEPTS a legal mode, the executor RUNS the legal operand, and the
#      executor TRAPS the illegal one. Every operation whose mask is EMPTY
#      carries ONE assertion instead - that no stale coverage entry names it.
#      Both directions are therefore red-on-drift: an operation that gains a
#      mask with no coverage entry fails in the wave that adds it, and an entry
#      whose mask has gone empty fails as a stale entry.
#   LAST  the decoder recognizes each of a handful of implemented opcodes from
#      a representative word, so the legality assertions are attached to the
#      code that runs and not to a table the decoder never reads.
#
# THE TRAP IS NOT EQUALLY ATTRIBUTABLE FOR EVERY OPERATION, AND THE SUMMARY
# LINE SAYS SO RATHER THAN LETTING A BARE COUNT IMPLY OTHERWISE. A minority of
# operations carry a mask WHOSE COMPLEMENT THE MACHINE LAYER ALREADY REFUSES -
# the reserved mode-7 encodings, which `machine.nim`'s `eaAddr` and `eaRead`
# fault on independently of any mask, and the `(d16,PC)` destination of ADDQ
# and SUBQ, whose `eaResolve` accepts exactly the two mode-7 encodings the mask
# admits and faults on every other. For those the trap is real but cannot be
# attributed to the guard: deleting the guard leaves a MACHINE-LAYER FALLBACK
# to fault in its place, so the case stays GREEN; `tests/t_ea_masks.nim` marks
# each such entry `discriminating: false`, and the first assertion is what
# covers a widened mask for them. The program prints `<N> of <M> operations
# attribute the refusal to their own guard` beside the case count. Read that
# figure from the run and not from this comment.
#
# THE COMPILE HAPPENS INSIDE THE TEST AND NOT IN THE BUILD, for the reason
# `t0_abi_header` and `t_checks_on` give: a `ctest` run over a tree whose
# build had failed would otherwise run a STALE binary of an earlier build.
# The test takes the library's own flag set (`-d:release --mm:arc
# --panics:on`), so a `--checks:off` added to the library reaches this
# program too, and `--path:src` is what makes the `mcf5307/...` imports
# resolve against the source tree.
#
# The driver also FAILS ON A NON-ZERO EXIT. The program itself prints a named
# PASSED/FAILED line per case and exits 1 when any case fails, so a silent
# pass is a failure of the driver, not a green result.

if(NOT DEFINED MCF5307_NIM_COMMAND)
    message(FATAL_ERROR
        "tests: t_ea_masks cannot be registered: MCF5307_NIM_COMMAND is not "
        "set. The test takes its flag set from the library's own compile "
        "command, and a test registered against an empty command would "
        "compile with no flags at all and assert nothing.")
endif()

# The command is the LIBRARY's command with the runtime-only and output
# arguments removed, exactly as `t_checks_on` does, plus `--path:src` so the
# package imports resolve. Everything else - `--mm:arc`, `--panics:on`,
# `-d:release`, and anything a later task adds - is kept.
set(MCF5307_EA_COMMAND "")
foreach(argument IN LISTS MCF5307_NIM_COMMAND)
    if(argument STREQUAL "--compileOnly"
            OR argument STREQUAL "--noMain"
            OR argument MATCHES "^--nimcache:"
            OR argument MATCHES "^--header:"
            OR argument MATCHES "^--nimMainPrefix:"
            OR argument MATCHES "^--path:"
            OR argument MATCHES "\\.nim$")
        continue()
    endif()
    list(APPEND MCF5307_EA_COMMAND "${argument}")
endforeach()
list(APPEND MCF5307_EA_COMMAND "--path:${PROJECT_SOURCE_DIR}/src")

set(NIM_EA_COMMAND_LITERAL "")
foreach(argument IN LISTS MCF5307_EA_COMMAND)
    string(APPEND NIM_EA_COMMAND_LITERAL "    \"${argument}\"\n")
endforeach()

# THE VANISHED-CASE CHECK EVERY `t_*` DRIVER BELOW INCLUDES.
#
# Each driver anchors its pass on `<suite>: <N> cases passed`, and MEASURED
# 2026-08-13 that anchor accepts a suite that has stopped running its cases:
# `t_irq` with `if passCount >= 1: return` at the head of its `check` printed
# `t_irq: 1 cases passed`, exited 0, and `ctest -R ^t_irq$` reported `Passed`
# with twenty-two of twenty-three cases gone.
#
# `case_sites.cmake` states the rules that replace the range with a
# comparison, and `tests/case_sites.nim` states the run-time half.
set(MCF5307_CASE_SITES_MODULE "${CMAKE_CURRENT_LIST_DIR}/case_sites.cmake")


set(MCF5307_EA_SOURCE "${CMAKE_CURRENT_LIST_DIR}/t_ea_masks.nim")
set(MCF5307_EA_BINARY "${CMAKE_CURRENT_BINARY_DIR}/t_ea_masks_program")
set(MCF5307_EA_NIMCACHE "${CMAKE_CURRENT_BINARY_DIR}/t_ea_masks_nimcache")

set(MCF5307_EA_DRIVER_TEMPLATE [==[
# GENERATED BY tests/tests_cpu.cmake. Do not edit this copy in the build tree.
#
# The driver of the registered test `t_ea_masks`. It compiles the Nim test
# program with THE LIBRARY'S OWN FLAG SET, runs it, and fails when the run
# exits non-zero or does not report a full pass.

set(nim_command
@NIM_EA_COMMAND_LITERAL@)
set(source "@MCF5307_EA_SOURCE@")
set(binary "@MCF5307_EA_BINARY@")
set(nimcache "@MCF5307_EA_NIMCACHE@")

# The binary of an earlier run is REMOVED BEFORE THE COMPILE. Without this a
# compile that failed would leave the earlier binary in place, and the run
# would then execute code this run never produced.
file(REMOVE "${binary}")

execute_process(
    COMMAND ${nim_command} "--nimcache:${nimcache}" "-o:${binary}" "${source}"
    RESULT_VARIABLE ea_compile_rc
    OUTPUT_VARIABLE ea_compile_out
    ERROR_VARIABLE ea_compile_err)

if(NOT ea_compile_rc EQUAL 0)
    message(FATAL_ERROR
        "t_ea_masks: the Nim test program did not compile "
        "(result: ${ea_compile_rc})\n"
        "${ea_compile_out}\n${ea_compile_err}")
endif()

execute_process(
    COMMAND "${binary}"
    RESULT_VARIABLE ea_run_rc
    OUTPUT_VARIABLE ea_run_out
    ERROR_VARIABLE ea_run_err)
message("${ea_run_out}")

if(NOT ea_run_rc EQUAL 0)
    message(FATAL_ERROR
        "t_ea_masks: the run exited ${ea_run_rc}\n${ea_run_err}")
endif()

# The program prints `t_ea_masks: <N> cases passed`; failing cases make it
# exit non-zero, which the check above already rejects. Anchoring the tail
# here keeps a run that printed the banner but skipped the cases from passing.
# THE `[1-9]` IS WHAT REJECTS A RUN OF ZERO CASES.
if(NOT ea_run_out MATCHES "t_ea_masks: [1-9][0-9]* cases passed")
    message(FATAL_ERROR
        "t_ea_masks: the run exited 0 but did not report a full pass.\n"
        "  stdout : ${ea_run_out}\n  stderr : ${ea_run_err}")
endif()

# THE VANISHED-CASE CHECK. The anchor above stays beside it rather than being
# replaced by it: the two fail on differently-shaped defects, and the anchor is
# the cheaper of the two. `tests/case_sites.cmake` states the rules.
include("@MCF5307_CASE_SITES_MODULE@")
mcf5307_check_case_sites("t_ea_masks" "@MCF5307_EA_SOURCE@" "${ea_run_out}"
    1)

# THE CASE TOTAL. The rules the call above applies catch a case that stops
# RUNNING; they cannot see a TABLE THAT GOT SHORTER, because a site inside a
# loop is one site however many rows the loop carries. `tests/case_sites.cmake`
# states at `mcf5307_check_case_total` why a TYPED figure is accepted here and
# what it still does not reach. MOVE IT ONLY WITH A DELIBERATE CHANGE IN THE
# CASE COUNT.
mcf5307_check_case_total("t_ea_masks" "${ea_run_out}" 449)

]==])

string(CONFIGURE "${MCF5307_EA_DRIVER_TEMPLATE}"
    MCF5307_EA_DRIVER @ONLY)
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/t_ea_masks_driver.cmake"
    "${MCF5307_EA_DRIVER}")

add_test(NAME t_ea_masks
    COMMAND "${CMAKE_COMMAND}"
        -P "${CMAKE_CURRENT_BINARY_DIR}/t_ea_masks_driver.cmake")

# --------------------------------------------------------------------- CPU-7
# `t_sign_extend` - the sign-extension helpers of `mcf5307/machine`.
#
# ONE REGISTERED NAME, TEN CASES, AND EACH ONE CAN FAIL. `s16` and `s8` turn a
# displacement or an immediate value into the signed 32-bit value the address
# arithmetic adds. The four boundary values of each helper are asserted with
# their exact results, and `s8` is asserted twice more with a high byte it
# must ignore. The file `tests/t_sign_extend.nim` gives the case list.
#
# THE FLAG SET IS WHAT MAKES THIS TEST BITE, and it is taken from the
# library's own compile command exactly as `t_checks_on` and `t_ea_masks` take
# it. A checked narrowing conversion in either helper rejects EVERY NEGATIVE
# displacement; under the library's `--panics:on -d:release` that ends the
# process with a `RangeDefect` instead of raising a catchable error. A test
# compiled with a flag set of its own could report that as something other
# than a dead program.
#
# THE COMPILE HAPPENS INSIDE THE TEST AND NOT IN THE BUILD, for the reason the
# tests above give: a `ctest` run over a tree whose build had failed would
# otherwise run a STALE binary of an earlier build and pass.
#
# The driver FAILS ON A NON-ZERO EXIT and also on a run that exited 0 without
# reporting a full pass. The first is what catches the process the defect
# kills; the second is what stops a program that printed nothing from passing.

if(NOT DEFINED MCF5307_NIM_COMMAND)
    message(FATAL_ERROR
        "tests: t_sign_extend cannot be registered: MCF5307_NIM_COMMAND is "
        "not set. The test takes its flag set from the library's own compile "
        "command, and a test registered against an empty command would "
        "compile with no flags at all and assert nothing.")
endif()

# The command is the LIBRARY's command with the runtime-only and output
# arguments removed, exactly as `t_ea_masks` does, plus `--path:src` so the
# `include` of `mcf5307/machine` resolves against the source tree.
set(MCF5307_SIGN_COMMAND "")
foreach(argument IN LISTS MCF5307_NIM_COMMAND)
    if(argument STREQUAL "--compileOnly"
            OR argument STREQUAL "--noMain"
            OR argument MATCHES "^--nimcache:"
            OR argument MATCHES "^--header:"
            OR argument MATCHES "^--nimMainPrefix:"
            OR argument MATCHES "^--path:"
            OR argument MATCHES "\\.nim$")
        continue()
    endif()
    list(APPEND MCF5307_SIGN_COMMAND "${argument}")
endforeach()
list(APPEND MCF5307_SIGN_COMMAND "--path:${PROJECT_SOURCE_DIR}/src")

set(NIM_SIGN_COMMAND_LITERAL "")
foreach(argument IN LISTS MCF5307_SIGN_COMMAND)
    string(APPEND NIM_SIGN_COMMAND_LITERAL "    \"${argument}\"\n")
endforeach()

set(MCF5307_SIGN_SOURCE "${CMAKE_CURRENT_LIST_DIR}/t_sign_extend.nim")
set(MCF5307_SIGN_BINARY "${CMAKE_CURRENT_BINARY_DIR}/t_sign_extend_program")
set(MCF5307_SIGN_NIMCACHE "${CMAKE_CURRENT_BINARY_DIR}/t_sign_extend_nimcache")

set(MCF5307_SIGN_DRIVER_TEMPLATE [==[
# GENERATED BY tests/tests_cpu.cmake. Do not edit this copy in the build tree.
#
# The driver of the registered test `t_sign_extend`. It compiles the Nim test
# program with THE LIBRARY'S OWN FLAG SET, runs it, and fails when the run
# exits non-zero or does not report a full pass.

set(nim_command
@NIM_SIGN_COMMAND_LITERAL@)
set(source "@MCF5307_SIGN_SOURCE@")
set(binary "@MCF5307_SIGN_BINARY@")
set(nimcache "@MCF5307_SIGN_NIMCACHE@")

# The binary of an earlier run is REMOVED BEFORE THE COMPILE. Without this a
# compile that failed would leave the earlier binary in place, and the run
# would then execute code this run never produced.
file(REMOVE "${binary}")

execute_process(
    COMMAND ${nim_command} "--nimcache:${nimcache}" "-o:${binary}" "${source}"
    RESULT_VARIABLE sign_compile_rc
    OUTPUT_VARIABLE sign_compile_out
    ERROR_VARIABLE sign_compile_err)

if(NOT sign_compile_rc EQUAL 0)
    message(FATAL_ERROR
        "t_sign_extend: the Nim test program did not compile "
        "(result: ${sign_compile_rc})\n"
        "${sign_compile_out}\n${sign_compile_err}")
endif()

execute_process(
    COMMAND "${binary}"
    RESULT_VARIABLE sign_run_rc
    OUTPUT_VARIABLE sign_run_out
    ERROR_VARIABLE sign_run_err)
message("${sign_run_out}")

if(NOT sign_run_rc EQUAL 0)
    message(FATAL_ERROR
        "t_sign_extend: the run exited ${sign_run_rc}\n${sign_run_err}")
endif()

# The program prints `t_sign_extend: <N> cases passed`; failing cases make it
# exit non-zero, which the check above already rejects. Anchoring the tail
# here keeps a run that printed the banner but skipped the cases from passing.
# THE `[1-9]` IS WHAT REJECTS A RUN OF ZERO CASES.
if(NOT sign_run_out MATCHES "t_sign_extend: [1-9][0-9]* cases passed")
    message(FATAL_ERROR
        "t_sign_extend: the run exited 0 but did not report a full pass.\n"
        "  stdout : ${sign_run_out}\n  stderr : ${sign_run_err}")
endif()

# THE VANISHED-CASE CHECK. The anchor above stays beside it rather than being
# replaced by it: the two fail on differently-shaped defects, and the anchor is
# the cheaper of the two. `tests/case_sites.cmake` states the rules.
include("@MCF5307_CASE_SITES_MODULE@")
mcf5307_check_case_sites("t_sign_extend" "@MCF5307_SIGN_SOURCE@" "${sign_run_out}"
    0)

# THE CASE TOTAL. The rules the call above applies catch a case that stops
# RUNNING; they cannot see a TABLE THAT GOT SHORTER, because a site inside a
# loop is one site however many rows the loop carries. `tests/case_sites.cmake`
# states at `mcf5307_check_case_total` why a TYPED figure is accepted here and
# what it still does not reach. MOVE IT ONLY WITH A DELIBERATE CHANGE IN THE
# CASE COUNT.
mcf5307_check_case_total("t_sign_extend" "${sign_run_out}" 10)

]==])

string(CONFIGURE "${MCF5307_SIGN_DRIVER_TEMPLATE}"
    MCF5307_SIGN_DRIVER @ONLY)
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/t_sign_extend_driver.cmake"
    "${MCF5307_SIGN_DRIVER}")

add_test(NAME t_sign_extend
    COMMAND "${CMAKE_COMMAND}"
        -P "${CMAKE_CURRENT_BINARY_DIR}/t_sign_extend_driver.cmake")

# --------------------------------------------------------------------- CPU-8
# `t_alu` - the integer-arithmetic instruction group.
#
# ONE REGISTERED NAME, AND EVERY CASE CAN FAIL. The CPU-8 Check: line is
# `mcf5307_conformance_alu`, and this test is registered BESIDE it rather than
# instead of it, because the two measure different things and neither covers
# the other.
#
# THE CORPUS CANNOT SEE A CONDITION CODE. Measured on the committed corpus:
# not one case in any of the four groups names `sr` in its `expected` state,
# and `conformance/runner.cpp` asserts only the registers a case names. A core
# that computed every arithmetic result correctly and set no flag at all
# reports `9 cases, 0 failed`. Half of this instruction group is the flags:
# ADDX, SUBX and NEGX READ X, their sticky-Z rule is a rule about Z alone, and
# the overflow of a 32-bit multiply is observable in V and nowhere else.
# `tests/t_alu.nim` asserts those, through the same C entry points the corpus
# runner uses.
#
# THE CORPUS ALSO CARRIES NO NEGATIVE CASE YET. CPU-13 owns the negative
# corpus and it is downstream of this task, so the encodings this part does
# NOT have - byte and word arithmetic, an ADDI to memory, a NEG to memory, a
# PC-relative ADDQ destination, a 64-bit MULU.L, the memory form of ADDX -
# are asserted to trap here in the meantime. Each one was offered to
# `m68k-elf-as -mcpu=5307` and rejected, which is the ground truth for what
# the silicon has.
#
# THE FLAG SET, THE COMPILE INSIDE THE TEST and the two-part failure check are
# taken from `t_ea_masks` and `t_sign_extend` above, for the reasons those
# blocks give.

if(NOT DEFINED MCF5307_NIM_COMMAND)
    message(FATAL_ERROR
        "tests: t_alu cannot be registered: MCF5307_NIM_COMMAND is not set. "
        "The test takes its flag set from the library's own compile command, "
        "and a test registered against an empty command would compile with no "
        "flags at all and assert nothing.")
endif()

set(MCF5307_ALU_COMMAND "")
foreach(argument IN LISTS MCF5307_NIM_COMMAND)
    if(argument STREQUAL "--compileOnly"
            OR argument STREQUAL "--noMain"
            OR argument MATCHES "^--nimcache:"
            OR argument MATCHES "^--header:"
            OR argument MATCHES "^--nimMainPrefix:"
            OR argument MATCHES "^--path:"
            OR argument MATCHES "\\.nim$")
        continue()
    endif()
    list(APPEND MCF5307_ALU_COMMAND "${argument}")
endforeach()
list(APPEND MCF5307_ALU_COMMAND "--path:${PROJECT_SOURCE_DIR}/src")

set(NIM_ALU_COMMAND_LITERAL "")
foreach(argument IN LISTS MCF5307_ALU_COMMAND)
    string(APPEND NIM_ALU_COMMAND_LITERAL "    \"${argument}\"\n")
endforeach()

set(MCF5307_ALU_SOURCE "${CMAKE_CURRENT_LIST_DIR}/t_alu.nim")
set(MCF5307_ALU_BINARY "${CMAKE_CURRENT_BINARY_DIR}/t_alu_program")
set(MCF5307_ALU_NIMCACHE "${CMAKE_CURRENT_BINARY_DIR}/t_alu_nimcache")

set(MCF5307_ALU_DRIVER_TEMPLATE [==[
# GENERATED BY tests/tests_cpu.cmake. Do not edit this copy in the build tree.
#
# The driver of the registered test `t_alu`. It compiles the Nim test program
# with THE LIBRARY'S OWN FLAG SET, runs it, and fails when the run exits
# non-zero or does not report a full pass.

set(nim_command
@NIM_ALU_COMMAND_LITERAL@)
set(source "@MCF5307_ALU_SOURCE@")
set(binary "@MCF5307_ALU_BINARY@")
set(nimcache "@MCF5307_ALU_NIMCACHE@")

# The binary of an earlier run is REMOVED BEFORE THE COMPILE. Without this a
# compile that failed would leave the earlier binary in place, and the run
# would then execute code this run never produced.
file(REMOVE "${binary}")

execute_process(
    COMMAND ${nim_command} "--nimcache:${nimcache}" "-o:${binary}" "${source}"
    RESULT_VARIABLE alu_compile_rc
    OUTPUT_VARIABLE alu_compile_out
    ERROR_VARIABLE alu_compile_err)

if(NOT alu_compile_rc EQUAL 0)
    message(FATAL_ERROR
        "t_alu: the Nim test program did not compile "
        "(result: ${alu_compile_rc})\n"
        "${alu_compile_out}\n${alu_compile_err}")
endif()

execute_process(
    COMMAND "${binary}"
    RESULT_VARIABLE alu_run_rc
    OUTPUT_VARIABLE alu_run_out
    ERROR_VARIABLE alu_run_err)
message("${alu_run_out}")

if(NOT alu_run_rc EQUAL 0)
    message(FATAL_ERROR
        "t_alu: the run exited ${alu_run_rc}\n${alu_run_err}")
endif()

# The program prints `t_alu: <N> cases passed`; failing cases make it exit
# non-zero, which the check above already rejects. Anchoring the tail here
# keeps a run that printed the banner but skipped the cases from passing.
# THE `[1-9]` IS WHAT REJECTS A RUN OF ZERO CASES.
if(NOT alu_run_out MATCHES "t_alu: [1-9][0-9]* cases passed")
    message(FATAL_ERROR
        "t_alu: the run exited 0 but did not report a full pass.\n"
        "  stdout : ${alu_run_out}\n  stderr : ${alu_run_err}")
endif()

# THE VANISHED-CASE CHECK. The anchor above stays beside it rather than being
# replaced by it: the two fail on differently-shaped defects, and the anchor is
# the cheaper of the two. `tests/case_sites.cmake` states the rules.
include("@MCF5307_CASE_SITES_MODULE@")
mcf5307_check_case_sites("t_alu" "@MCF5307_ALU_SOURCE@" "${alu_run_out}"
    0)

# THE CASE TOTAL. The rules the call above applies catch a case that stops
# RUNNING; they cannot see a TABLE THAT GOT SHORTER, because a site inside a
# loop is one site however many rows the loop carries. `tests/case_sites.cmake`
# states at `mcf5307_check_case_total` why a TYPED figure is accepted here and
# what it still does not reach. MOVE IT ONLY WITH A DELIBERATE CHANGE IN THE
# CASE COUNT.
mcf5307_check_case_total("t_alu" "${alu_run_out}" 165)

]==])

string(CONFIGURE "${MCF5307_ALU_DRIVER_TEMPLATE}"
    MCF5307_ALU_DRIVER @ONLY)
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/t_alu_driver.cmake"
    "${MCF5307_ALU_DRIVER}")

add_test(NAME t_alu
    COMMAND "${CMAKE_COMMAND}"
        -P "${CMAKE_CURRENT_BINARY_DIR}/t_alu_driver.cmake")

# --------------------------------------------------------------------- CPU-7
# `t_move` - the sized write to a data register in the data-movement group.
#
# ONE REGISTERED NAME, SEVEN CASES, AND EVERY ONE CAN FAIL. This test is
# registered BESIDE `mcf5307_conformance_move` rather than instead of it,
# because that corpus CANNOT SEE THE RULE THIS TEST ASSERTS.
#
# THE CORPUS IS DEGENERATE ON THE SIZED WRITE. It is 18 of 18, and it holds
# exactly two sized cases - `move_w_d0_to_d1` and `move_b_d0_to_d1` - and BOTH
# START THE DESTINATION REGISTER AT ZERO. A `MOVE.B` into `Dn` writes the low
# byte and leaves the upper three alone; a core that zeroes them produces the
# same register as a correct core from a zero destination, so the corpus
# reports 18 of 18 either way. Every case in `tests/t_move.nim` starts the
# destination at 0x12345678, which is what separates the two.
#
# THE CORPUS ALSO CANNOT SEE A CONDITION CODE, for the reason the CPU-8 block
# above records: no case in any of the four corpus files names `sr`, and
# `conformance/runner.cpp` asserts only the registers a case names. Each case
# here asserts the register, the whole status register and `fault` as ONE
# TUPLE.
#
# THE FLAG SET, THE COMPILE INSIDE THE TEST and the two-part failure check are
# taken from `t_ea_masks`, `t_sign_extend` and `t_alu` above, for the reasons
# those blocks give.

if(NOT DEFINED MCF5307_NIM_COMMAND)
    message(FATAL_ERROR
        "tests: t_move cannot be registered: MCF5307_NIM_COMMAND is not set. "
        "The test takes its flag set from the library's own compile command, "
        "and a test registered against an empty command would compile with no "
        "flags at all and assert nothing.")
endif()

set(MCF5307_MOVE_COMMAND "")
foreach(argument IN LISTS MCF5307_NIM_COMMAND)
    if(argument STREQUAL "--compileOnly"
            OR argument STREQUAL "--noMain"
            OR argument MATCHES "^--nimcache:"
            OR argument MATCHES "^--header:"
            OR argument MATCHES "^--nimMainPrefix:"
            OR argument MATCHES "^--path:"
            OR argument MATCHES "\\.nim$")
        continue()
    endif()
    list(APPEND MCF5307_MOVE_COMMAND "${argument}")
endforeach()
list(APPEND MCF5307_MOVE_COMMAND "--path:${PROJECT_SOURCE_DIR}/src")

set(NIM_MOVE_COMMAND_LITERAL "")
foreach(argument IN LISTS MCF5307_MOVE_COMMAND)
    string(APPEND NIM_MOVE_COMMAND_LITERAL "    \"${argument}\"\n")
endforeach()

set(MCF5307_MOVE_SOURCE "${CMAKE_CURRENT_LIST_DIR}/t_move.nim")
set(MCF5307_MOVE_BINARY "${CMAKE_CURRENT_BINARY_DIR}/t_move_program")
set(MCF5307_MOVE_NIMCACHE "${CMAKE_CURRENT_BINARY_DIR}/t_move_nimcache")

set(MCF5307_MOVE_DRIVER_TEMPLATE [==[
# GENERATED BY tests/tests_cpu.cmake. Do not edit this copy in the build tree.
#
# The driver of the registered test `t_move`. It compiles the Nim test program
# with THE LIBRARY'S OWN FLAG SET, runs it, and fails when the run exits
# non-zero or does not report a full pass.

set(nim_command
@NIM_MOVE_COMMAND_LITERAL@)
set(source "@MCF5307_MOVE_SOURCE@")
set(binary "@MCF5307_MOVE_BINARY@")
set(nimcache "@MCF5307_MOVE_NIMCACHE@")

# The binary of an earlier run is REMOVED BEFORE THE COMPILE. Without this a
# compile that failed would leave the earlier binary in place, and the run
# would then execute code this run never produced.
file(REMOVE "${binary}")

execute_process(
    COMMAND ${nim_command} "--nimcache:${nimcache}" "-o:${binary}" "${source}"
    RESULT_VARIABLE move_compile_rc
    OUTPUT_VARIABLE move_compile_out
    ERROR_VARIABLE move_compile_err)

if(NOT move_compile_rc EQUAL 0)
    message(FATAL_ERROR
        "t_move: the Nim test program did not compile "
        "(result: ${move_compile_rc})\n"
        "${move_compile_out}\n${move_compile_err}")
endif()

execute_process(
    COMMAND "${binary}"
    RESULT_VARIABLE move_run_rc
    OUTPUT_VARIABLE move_run_out
    ERROR_VARIABLE move_run_err)
message("${move_run_out}")

if(NOT move_run_rc EQUAL 0)
    message(FATAL_ERROR
        "t_move: the run exited ${move_run_rc}\n${move_run_err}")
endif()

# The program prints `t_move: <N> cases passed`; failing cases make it exit
# non-zero, which the check above already rejects. Anchoring the tail here
# keeps a run that printed the banner but skipped the cases from passing.
# THE `[1-9]` IS WHAT REJECTS A RUN OF ZERO CASES.
if(NOT move_run_out MATCHES "t_move: [1-9][0-9]* cases passed")
    message(FATAL_ERROR
        "t_move: the run exited 0 but did not report a full pass.\n"
        "  stdout : ${move_run_out}\n  stderr : ${move_run_err}")
endif()

# THE VANISHED-CASE CHECK. The anchor above stays beside it rather than being
# replaced by it: the two fail on differently-shaped defects, and the anchor is
# the cheaper of the two. `tests/case_sites.cmake` states the rules.
include("@MCF5307_CASE_SITES_MODULE@")
mcf5307_check_case_sites("t_move" "@MCF5307_MOVE_SOURCE@" "${move_run_out}"
    0)

# THE CASE TOTAL. The rules the call above applies catch a case that stops
# RUNNING; they cannot see a TABLE THAT GOT SHORTER, because a site inside a
# loop is one site however many rows the loop carries. `tests/case_sites.cmake`
# states at `mcf5307_check_case_total` why a TYPED figure is accepted here and
# what it still does not reach. MOVE IT ONLY WITH A DELIBERATE CHANGE IN THE
# CASE COUNT.
mcf5307_check_case_total("t_move" "${move_run_out}" 34)

]==])

string(CONFIGURE "${MCF5307_MOVE_DRIVER_TEMPLATE}"
    MCF5307_MOVE_DRIVER @ONLY)
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/t_move_driver.cmake"
    "${MCF5307_MOVE_DRIVER}")

add_test(NAME t_move
    COMMAND "${CMAKE_COMMAND}"
        -P "${CMAKE_CURRENT_BINARY_DIR}/t_move_driver.cmake")

# --------------------------------------------------------------------- CPU-9
# `t_logic` - the logic, bit-operation and shift instruction group.
#
# ONE REGISTERED NAME, AND EVERY CASE CAN FAIL. The CPU-9 Check: line is
# `mcf5307_conformance_logic`, and this test is registered BESIDE it rather
# than instead of it, because that corpus STRUCTURALLY CANNOT SEE the two
# defects this file was written to catch.
#
# A POSITIVE CORPUS CANNOT SEE A WRONGLY-CLAIMED ENCODING. The 41 committed
# logic cases are all encodings this part HAS. `decode.nim` claimed line 1011
# opmode 111 - CMPA.L, which CPU-10 owns - as an EOR, and the wrong claim
# presented as a well-formed long EOR: measured, `cmpa.l %d0,%a1` (`b3c0`) left
# d0 = d0 xor d1 and the corpus stayed 41 of 41. Adding green cases never
# catches that. Only a case that asserts what must NOT decode can.
#
# NOR CAN IT SEE AN OPERAND IT NEVER OFFERS. The corpus holds no dynamic BTST
# against a PC-relative or an immediate operand, so the disagreement between
# the declared mask - which admits both - and the executor - which refused both
# - was invisible. Measured, `btst %d1,(4,%pc)` and `btst %d1,#5` each halted
# with `fault`, though `m68k-elf-as -mcpu=5307` assembles both.
#
# AND NO REGISTERED TEST ENTERED `logic.nim` AT ALL BEFORE THIS ONE.
# `t_ea_masks` HAS SINCE BEEN REWRITTEN TO ENUMERATE OVER `Operation`, so it
# now enters `logicFamily` for every logic operation carrying a legality mask -
# BUT IT ENTERS THROUGH THE EFFECTIVE-ADDRESS DOOR ALONE. It asserts that a
# legal operand runs and that an illegal one traps whole, and it asserts
# NOTHING about the COMPUTED RESULT of a legal run and NOTHING about the
# ENCODING of any logic word - it hand-builds its `Decoded` objects, and the
# six words it does put through `decodeWord` are NOP, MOVE, ADDQ, SUBQ, LEA and
# MOVEQ, not one logic opcode among them. Its `opBtst` entry offers `Dn` and
# `An` and no other mode, so the PC-relative and immediate operands named above
# are never presented to it. That leaves both defects above out of its reach
# and leaves this file's reason to exist unchanged. (It does assert a cycle
# count and the status register, but only as part of `traps whole`: a non-zero
# count for the legal run and zero cycles with an unchanged SR for the trap.)
# `t_move` and `t_alu` cover their own groups.
# `tests/t_logic.nim` gives the case list and the measurement behind every
# encoding it names.
#
# THE FLAG SET, THE COMPILE INSIDE THE TEST and the two-part failure check are
# taken from `t_ea_masks`, `t_sign_extend`, `t_alu` and `t_move` above, for the
# reasons those blocks give.

if(NOT DEFINED MCF5307_NIM_COMMAND)
    message(FATAL_ERROR
        "tests: t_logic cannot be registered: MCF5307_NIM_COMMAND is not set. "
        "The test takes its flag set from the library's own compile command, "
        "and a test registered against an empty command would compile with no "
        "flags at all and assert nothing.")
endif()

set(MCF5307_LOGIC_COMMAND "")
foreach(argument IN LISTS MCF5307_NIM_COMMAND)
    if(argument STREQUAL "--compileOnly"
            OR argument STREQUAL "--noMain"
            OR argument MATCHES "^--nimcache:"
            OR argument MATCHES "^--header:"
            OR argument MATCHES "^--nimMainPrefix:"
            OR argument MATCHES "^--path:"
            OR argument MATCHES "\\.nim$")
        continue()
    endif()
    list(APPEND MCF5307_LOGIC_COMMAND "${argument}")
endforeach()
list(APPEND MCF5307_LOGIC_COMMAND "--path:${PROJECT_SOURCE_DIR}/src")

set(NIM_LOGIC_COMMAND_LITERAL "")
foreach(argument IN LISTS MCF5307_LOGIC_COMMAND)
    string(APPEND NIM_LOGIC_COMMAND_LITERAL "    \"${argument}\"\n")
endforeach()

set(MCF5307_LOGIC_SOURCE "${CMAKE_CURRENT_LIST_DIR}/t_logic.nim")
set(MCF5307_LOGIC_BINARY "${CMAKE_CURRENT_BINARY_DIR}/t_logic_program")
set(MCF5307_LOGIC_NIMCACHE "${CMAKE_CURRENT_BINARY_DIR}/t_logic_nimcache")

set(MCF5307_LOGIC_DRIVER_TEMPLATE [==[
# GENERATED BY tests/tests_cpu.cmake. Do not edit this copy in the build tree.
#
# The driver of the registered test `t_logic`. It compiles the Nim test program
# with THE LIBRARY'S OWN FLAG SET, runs it, and fails when the run exits
# non-zero or does not report a full pass.

set(nim_command
@NIM_LOGIC_COMMAND_LITERAL@)
set(source "@MCF5307_LOGIC_SOURCE@")
set(binary "@MCF5307_LOGIC_BINARY@")
set(nimcache "@MCF5307_LOGIC_NIMCACHE@")

# The binary of an earlier run is REMOVED BEFORE THE COMPILE. Without this a
# compile that failed would leave the earlier binary in place, and the run
# would then execute code this run never produced.
file(REMOVE "${binary}")

execute_process(
    COMMAND ${nim_command} "--nimcache:${nimcache}" "-o:${binary}" "${source}"
    RESULT_VARIABLE logic_compile_rc
    OUTPUT_VARIABLE logic_compile_out
    ERROR_VARIABLE logic_compile_err)

if(NOT logic_compile_rc EQUAL 0)
    message(FATAL_ERROR
        "t_logic: the Nim test program did not compile "
        "(result: ${logic_compile_rc})\n"
        "${logic_compile_out}\n${logic_compile_err}")
endif()

execute_process(
    COMMAND "${binary}"
    RESULT_VARIABLE logic_run_rc
    OUTPUT_VARIABLE logic_run_out
    ERROR_VARIABLE logic_run_err)
message("${logic_run_out}")

if(NOT logic_run_rc EQUAL 0)
    message(FATAL_ERROR
        "t_logic: the run exited ${logic_run_rc}\n${logic_run_err}")
endif()

# The program prints `t_logic: <N> cases passed`; failing cases make it exit
# non-zero, which the check above already rejects. Anchoring the tail here
# keeps a run that printed the banner but skipped the cases from passing.
#
# THE COUNT IS `[1-9][0-9]*` AND NOT `[0-9]+`, AND THE DIFFERENCE IS THE WHOLE
# CHECK. `[0-9]+` matches `0`, so a `t_logic.nim` reduced to nothing but
# `echo "t_logic: ", 0, " cases passed"` exits 0, prints the banner, runs no
# case and PASSES this test - which is the one outcome the paragraph above
# says this anchor exists to reject. Measured: with `[0-9]+`, that reduced
# program passes; with the pattern below it fails.
if(NOT logic_run_out MATCHES "t_logic: [1-9][0-9]* cases passed")
    message(FATAL_ERROR
        "t_logic: the run exited 0 but did not report a full pass.\n"
        "  stdout : ${logic_run_out}\n  stderr : ${logic_run_err}")
endif()

# THE VANISHED-CASE CHECK. The anchor above stays beside it rather than being
# replaced by it: the two fail on differently-shaped defects, and the anchor is
# the cheaper of the two. `tests/case_sites.cmake` states the rules.
include("@MCF5307_CASE_SITES_MODULE@")
mcf5307_check_case_sites("t_logic" "@MCF5307_LOGIC_SOURCE@" "${logic_run_out}"
    0)

# THE CASE TOTAL. The rules the call above applies catch a case that stops
# RUNNING; they cannot see a TABLE THAT GOT SHORTER, because a site inside a
# loop is one site however many rows the loop carries. `tests/case_sites.cmake`
# states at `mcf5307_check_case_total` why a TYPED figure is accepted here and
# what it still does not reach. MOVE IT ONLY WITH A DELIBERATE CHANGE IN THE
# CASE COUNT.
mcf5307_check_case_total("t_logic" "${logic_run_out}" 74)

]==])

string(CONFIGURE "${MCF5307_LOGIC_DRIVER_TEMPLATE}"
    MCF5307_LOGIC_DRIVER @ONLY)
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/t_logic_driver.cmake"
    "${MCF5307_LOGIC_DRIVER}")

add_test(NAME t_logic
    COMMAND "${CMAKE_COMMAND}"
        -P "${CMAKE_CURRENT_BINARY_DIR}/t_logic_driver.cmake")

# -------------------------------------------------------------------- CPU-10
# `t_control` - control flow and comparison.
#
# ONE REGISTERED NAME, AND EVERY CASE CAN FAIL. The CPU-10 Check: line is
# `mcf5307_conformance_control`, and this test is registered BESIDE it rather
# than instead of it, for the reason the `t_logic` block above gives: a POSITIVE
# corpus STRUCTURALLY CANNOT SEE a wrongly-claimed encoding, because a stolen
# encoding produces a PASSING EXECUTION OF A DIFFERENT INSTRUCTION.
#
# THIS GROUP ARRIVED WITH ONE. Measured on a sweep of all 65536 words against
# the decoder of commit a124077: `decode.nim`'s ADDQ and SUBQ arms matched on
# `word and 0xF100` alone and claimed all 1024 `0101 cccc 11 <ea>` words, 512 as
# `opAddq` and 512 as `opSubq`, none unclaimed. Every one of them then trapped
# on the illegal size field, which is indistinguishable from "the opcode is not
# written yet". `tests/t_control.nim` asserts `decodeWord(0x50c0).op == opScc`
# and the three ADDQ/SUBQ controls beside it.
#
# THOSE 1024 WORDS ARE NOT "THE Scc AND DBcc SPACE", which is what this block
# used to call them. The split is measured, not assumed:
#
#     128 are `Scc Dn` - EA field `000 rrr`, eight registers times sixteen
#         conditions. All 128 assemble under `m68k-elf-as -mcpu=5307` (`st %d0`
#         is `50c0`, `sf %d0` is `51c0`, `shi %d0` is `52c0`) and `st (%a0)` is
#         REFUSED. Table 3-7, page 3-25, gives Scc an OPERAND SYNTAX of `Dx`,
#         and Table 3-12, page 3-27, one `scc Dx` row and no memory column.
#
#       0 are DBcc. THE INSTRUCTION IS NOT ON THIS PART. Section 3.9, page
#         3-21, lists "decrement and branch" among the removed instructions,
#         no table carries a row, and the pinned assembler rejects `dbf`,
#         `dbra`, `dbt` and `dbne` under `-mcpu=5307`. The 128 words
#         `0101 cccc 11 001 rrr` are a 68000 DBcc slot and nothing here.
#
#       3 are TRAPF - `51fa`, `51fb` and `51fc`, measured from `trapf.w #1`,
#         `trapf.l #1` and `trapf`. `trapt`, `trapeq`, `trapne` and `traphi`
#         are all REJECTED, so it is three words and not a condition family.
#         TRAPF is NOT in this task's opcode list; `t_control` asserts all
#         three as `opIllegal` so they stay unclaimed for whichever task owns
#         them, and keeps `51c0`, `51f9` and `51fd` as Scc controls beside
#         them.
#
#     893 are none of the three - no instruction on this part.
#
# IT ALSO CARRIES THE ONE ASSERTION THE PLAN ROW WRITES IN BOLD: a `Bcc` whose
# 8-bit displacement is `0xff` means a 32-bit displacement, which is ISA_B, and
# must trap. No corpus case can hold it - `m68k-elf-as -mcpu=5307` refuses to
# assemble `bra.l` at all - so the word is built by hand there.
#
# THE FLAG SET, THE COMPILE INSIDE THE TEST and the two-part failure check are
# taken from `t_ea_masks`, `t_sign_extend`, `t_alu`, `t_move` and `t_logic`
# above, for the reasons those blocks give.

if(NOT DEFINED MCF5307_NIM_COMMAND)
    message(FATAL_ERROR
        "tests: t_control cannot be registered: MCF5307_NIM_COMMAND is not "
        "set. The test takes its flag set from the library's own compile "
        "command, and a test registered against an empty command would compile "
        "with no flags at all and assert nothing.")
endif()

set(MCF5307_CONTROL_COMMAND "")
foreach(argument IN LISTS MCF5307_NIM_COMMAND)
    if(argument STREQUAL "--compileOnly"
            OR argument STREQUAL "--noMain"
            OR argument MATCHES "^--nimcache:"
            OR argument MATCHES "^--header:"
            OR argument MATCHES "^--nimMainPrefix:"
            OR argument MATCHES "^--path:"
            OR argument MATCHES "\\.nim$")
        continue()
    endif()
    list(APPEND MCF5307_CONTROL_COMMAND "${argument}")
endforeach()
list(APPEND MCF5307_CONTROL_COMMAND "--path:${PROJECT_SOURCE_DIR}/src")

set(NIM_CONTROL_COMMAND_LITERAL "")
foreach(argument IN LISTS MCF5307_CONTROL_COMMAND)
    string(APPEND NIM_CONTROL_COMMAND_LITERAL "    \"${argument}\"\n")
endforeach()

set(MCF5307_CONTROL_SOURCE "${CMAKE_CURRENT_LIST_DIR}/t_control.nim")
set(MCF5307_CONTROL_BINARY "${CMAKE_CURRENT_BINARY_DIR}/t_control_program")
set(MCF5307_CONTROL_NIMCACHE "${CMAKE_CURRENT_BINARY_DIR}/t_control_nimcache")

set(MCF5307_CONTROL_DRIVER_TEMPLATE [==[
# GENERATED BY tests/tests_cpu.cmake. Do not edit this copy in the build tree.
#
# The driver of the registered test `t_control`. It compiles the Nim test
# program with THE LIBRARY'S OWN FLAG SET, runs it, and fails when the run exits
# non-zero or does not report a full pass.

set(nim_command
@NIM_CONTROL_COMMAND_LITERAL@)
set(source "@MCF5307_CONTROL_SOURCE@")
set(binary "@MCF5307_CONTROL_BINARY@")
set(nimcache "@MCF5307_CONTROL_NIMCACHE@")

# The binary of an earlier run is REMOVED BEFORE THE COMPILE. Without this a
# compile that failed would leave the earlier binary in place, and the run
# would then execute code this run never produced.
file(REMOVE "${binary}")

execute_process(
    COMMAND ${nim_command} "--nimcache:${nimcache}" "-o:${binary}" "${source}"
    RESULT_VARIABLE control_compile_rc
    OUTPUT_VARIABLE control_compile_out
    ERROR_VARIABLE control_compile_err)

if(NOT control_compile_rc EQUAL 0)
    message(FATAL_ERROR
        "t_control: the Nim test program did not compile "
        "(result: ${control_compile_rc})\n"
        "${control_compile_out}\n${control_compile_err}")
endif()

execute_process(
    COMMAND "${binary}"
    RESULT_VARIABLE control_run_rc
    OUTPUT_VARIABLE control_run_out
    ERROR_VARIABLE control_run_err)
message("${control_run_out}")

if(NOT control_run_rc EQUAL 0)
    message(FATAL_ERROR
        "t_control: the run exited ${control_run_rc}\n${control_run_err}")
endif()

# The program prints `t_control: <N> cases passed`; failing cases make it exit
# non-zero, which the check above already rejects. Anchoring the tail here
# keeps a run that printed the banner but skipped the cases from passing.
#
# THE COUNT IS `[1-9][0-9]*` AND NOT `[0-9]+`, AND THE DIFFERENCE IS THE WHOLE
# CHECK. `[0-9]+` matches `0`, so a `t_control.nim` reduced to nothing but
# `echo "t_control: ", 0, " cases passed"` exits 0, prints the banner, runs no
# case and PASSES this test - which is the one outcome the paragraph above says
# this anchor exists to reject. The `t_logic` block above measured exactly that
# and this block uses its tightened form.
if(NOT control_run_out MATCHES "t_control: [1-9][0-9]* cases passed")
    message(FATAL_ERROR
        "t_control: the run exited 0 but did not report a full pass.\n"
        "  stdout : ${control_run_out}\n  stderr : ${control_run_err}")
endif()

# THE VANISHED-CASE CHECK. The anchor above stays beside it rather than being
# replaced by it: the two fail on differently-shaped defects, and the anchor is
# the cheaper of the two. `tests/case_sites.cmake` states the rules.
include("@MCF5307_CASE_SITES_MODULE@")
mcf5307_check_case_sites("t_control" "@MCF5307_CONTROL_SOURCE@" "${control_run_out}"
    0)

# THE CASE TOTAL. The rules the call above applies catch a case that stops
# RUNNING; they cannot see a TABLE THAT GOT SHORTER, because a site inside a
# loop is one site however many rows the loop carries. `tests/case_sites.cmake`
# states at `mcf5307_check_case_total` why a TYPED figure is accepted here and
# what it still does not reach. MOVE IT ONLY WITH A DELIBERATE CHANGE IN THE
# CASE COUNT.
mcf5307_check_case_total("t_control" "${control_run_out}" 168)

]==])

string(CONFIGURE "${MCF5307_CONTROL_DRIVER_TEMPLATE}"
    MCF5307_CONTROL_DRIVER @ONLY)
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/t_control_driver.cmake"
    "${MCF5307_CONTROL_DRIVER}")

add_test(NAME t_control
    COMMAND "${CMAKE_COMMAND}"
        -P "${CMAKE_CURRENT_BINARY_DIR}/t_control_driver.cmake")

# -------------------------------------------------------------------- CPU-11
# `t_movec` - the `MOVEC` encoding and the control-register map.
#
# ONE REGISTERED NAME, AND NO CORPUS BESIDE IT. The blocks above register a
# unit test beside a conformance corpus of the same group. This task has none,
# and the reason is the same one CPU-14's block gives one step further on: a
# positive corpus executes an encoding and compares the machine state after
# it, and `MOVEC` writes a control register this core does not keep. There is
# no state for a corpus case to read back, so a corpus case would assert that
# the instruction decoded and nothing about which register it named - which is
# the one thing this task exists to pin.
#
# THE HAZARD IS SILENT IN BOTH DIRECTIONS AND THAT IS WHY THE MAP IS TESTED
# NUMBER BY NUMBER. Design section 6.1 calls the 68k collision the number one
# hazard: `0x004` and `0x005` are ACR0 and ACR1 here and ITT0 and ITT1 on the
# 68040, and `0x800` is USP on the 68040 and names no register of this part. A
# decoder carrying the wrong map writes a real register with a real value and
# reports nothing, so no exit status anywhere can catch it.
#
# THE FLAG SET IS THE LIBRARY'S OWN, taken exactly as `t_ea_masks` and
# `t_sign_extend` above take it, and for the reason those blocks give.
#
# THE COMPILE HAPPENS INSIDE THE TEST AND NOT IN THE BUILD, for the reason the
# blocks above give: a `ctest` run over a tree whose build had failed would
# otherwise run a STALE binary of an earlier build and pass.

if(NOT DEFINED MCF5307_NIM_COMMAND)
    message(FATAL_ERROR
        "tests: t_movec cannot be registered: MCF5307_NIM_COMMAND is not set. "
        "The test takes its flag set from the library's own compile command, "
        "and a test registered against an empty command would compile with no "
        "flags at all and assert nothing.")
endif()

set(MCF5307_MOVEC_COMMAND "")
foreach(argument IN LISTS MCF5307_NIM_COMMAND)
    if(argument STREQUAL "--compileOnly"
            OR argument STREQUAL "--noMain"
            OR argument MATCHES "^--nimcache:"
            OR argument MATCHES "^--header:"
            OR argument MATCHES "^--nimMainPrefix:"
            OR argument MATCHES "^--path:"
            OR argument MATCHES "\\.nim$")
        continue()
    endif()
    list(APPEND MCF5307_MOVEC_COMMAND "${argument}")
endforeach()
list(APPEND MCF5307_MOVEC_COMMAND "--path:${PROJECT_SOURCE_DIR}/src")

set(NIM_MOVEC_COMMAND_LITERAL "")
foreach(argument IN LISTS MCF5307_MOVEC_COMMAND)
    string(APPEND NIM_MOVEC_COMMAND_LITERAL "    \"${argument}\"\n")
endforeach()

set(MCF5307_MOVEC_SOURCE "${CMAKE_CURRENT_LIST_DIR}/t_movec.nim")
set(MCF5307_MOVEC_BINARY "${CMAKE_CURRENT_BINARY_DIR}/t_movec_program")
set(MCF5307_MOVEC_NIMCACHE "${CMAKE_CURRENT_BINARY_DIR}/t_movec_nimcache")

set(MCF5307_MOVEC_DRIVER_TEMPLATE [==[
# GENERATED BY tests/tests_cpu.cmake. Do not edit this copy in the build tree.
#
# The driver of the registered test `t_movec`. It compiles the Nim test
# program with THE LIBRARY'S OWN FLAG SET, runs it, and fails when the run
# exits non-zero or does not report a full pass.

set(nim_command
@NIM_MOVEC_COMMAND_LITERAL@)
set(source "@MCF5307_MOVEC_SOURCE@")
set(binary "@MCF5307_MOVEC_BINARY@")
set(nimcache "@MCF5307_MOVEC_NIMCACHE@")

# The binary of an earlier run is REMOVED BEFORE THE COMPILE. Without this a
# compile that failed would leave the earlier binary in place, and the run
# would then execute code this run never produced.
file(REMOVE "${binary}")

execute_process(
    COMMAND ${nim_command} "--nimcache:${nimcache}" "-o:${binary}" "${source}"
    RESULT_VARIABLE movec_compile_rc
    OUTPUT_VARIABLE movec_compile_out
    ERROR_VARIABLE movec_compile_err)

if(NOT movec_compile_rc EQUAL 0)
    message(FATAL_ERROR
        "t_movec: the Nim test program did not compile "
        "(result: ${movec_compile_rc})\n"
        "${movec_compile_out}\n${movec_compile_err}")
endif()

execute_process(
    COMMAND "${binary}"
    RESULT_VARIABLE movec_run_rc
    OUTPUT_VARIABLE movec_run_out
    ERROR_VARIABLE movec_run_err)
message("${movec_run_out}")

if(NOT movec_run_rc EQUAL 0)
    message(FATAL_ERROR
        "t_movec: the run exited ${movec_run_rc}\n${movec_run_err}")
endif()

# The program prints `t_movec: <N> cases passed`; failing cases make it exit
# non-zero, which the check above already rejects. Anchoring the tail here
# keeps a run that printed the banner but skipped the cases from passing.
# THE `[1-9]` IS WHAT REJECTS A RUN OF ZERO CASES.
if(NOT movec_run_out MATCHES "t_movec: [1-9][0-9]* cases passed")
    message(FATAL_ERROR
        "t_movec: the run exited 0 but did not report a full pass.\n"
        "  stdout : ${movec_run_out}\n  stderr : ${movec_run_err}")
endif()

# THE VANISHED-CASE CHECK. The anchor above stays beside it rather than being
# replaced by it: the two fail on differently-shaped defects, and the anchor is
# the cheaper of the two. `tests/case_sites.cmake` states the rules.
include("@MCF5307_CASE_SITES_MODULE@")
mcf5307_check_case_sites("t_movec" "@MCF5307_MOVEC_SOURCE@" "${movec_run_out}"
    0)

# THE CASE TOTAL. The rules the call above applies catch a case that stops
# RUNNING; they cannot see a TABLE THAT GOT SHORTER, because a site inside a
# loop is one site however many rows the loop carries. `tests/case_sites.cmake`
# states at `mcf5307_check_case_total` why a TYPED figure is accepted here and
# what it still does not reach. MOVE IT ONLY WITH A DELIBERATE CHANGE IN THE
# CASE COUNT.
mcf5307_check_case_total("t_movec" "${movec_run_out}" 35)

]==])

string(CONFIGURE "${MCF5307_MOVEC_DRIVER_TEMPLATE}"
    MCF5307_MOVEC_DRIVER @ONLY)
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/t_movec_driver.cmake"
    "${MCF5307_MOVEC_DRIVER}")

add_test(NAME t_movec
    COMMAND "${CMAKE_COMMAND}"
        -P "${CMAKE_CURRENT_BINARY_DIR}/t_movec_driver.cmake")

# -------------------------------------------------------------------- CPU-30
# `t_system_control` - the SR and CCR transfers.
#
# ONE REGISTERED NAME, AND NO CORPUS BESIDE IT, for the reason the CPU-11 block
# above gives at greater length. A positive corpus executes an encoding and
# compares the machine state after it; the state these four instructions move
# is the STATUS REGISTER, which is what the corpus runner would have to seed to
# make a case mean anything, and the privilege half of the group cannot be
# expressed as a state comparison at all - it is an EXCEPTION, and the suite
# below reads the stacked frame to assert it.
#
# THE SUITE ASSERTS PRIVILEGE IN BOTH DIRECTIONS AND THAT IS THE POINT OF THE
# TASK. `MOVE from SR` and `MOVE to SR` are supervisor-only on this part and
# `MOVE from CCR` and `MOVE to CCR` are not, so the suite runs the CCR pair
# with S CLEAR and requires no exception. A suite that ran all four in
# supervisor state would pass against a correct core AND against one that
# privileged the CCR pair, which is the silent direction.
#
# THE PRIVILEGE PREDICATE HAS ONE HOME AND THE SUITE IS HALF OF THE PROOF.
# `movecPrivilegeViolation` in `src/mcf5307/movec.nim` is the only test of the
# S bit in the core, and the executor of this group is in that same file so
# that it reads the same predicate rather than a second copy. `t_claims.cmake`
# is the other half: a mutation of that one predicate must turn the `MOVEC`
# cases AND these cases red IN ONE RUN, and a run where only one of the two
# goes red is the two-copies defect.
#
# THE FLAG SET IS THE LIBRARY'S OWN, taken exactly as the blocks above take it,
# and for the reason those blocks give.
#
# THE COMPILE HAPPENS INSIDE THE TEST AND NOT IN THE BUILD, for the reason the
# blocks above give: a `ctest` run over a tree whose build had failed would
# otherwise run a STALE binary of an earlier build and pass.

if(NOT DEFINED MCF5307_NIM_COMMAND)
    message(FATAL_ERROR
        "tests: t_system_control cannot be registered: MCF5307_NIM_COMMAND is "
        "not set. The test takes its flag set from the library's own compile "
        "command, and a test registered against an empty command would compile "
        "with no flags at all and assert nothing.")
endif()

set(MCF5307_SYSCTL_COMMAND "")
foreach(argument IN LISTS MCF5307_NIM_COMMAND)
    if(argument STREQUAL "--compileOnly"
            OR argument STREQUAL "--noMain"
            OR argument MATCHES "^--nimcache:"
            OR argument MATCHES "^--header:"
            OR argument MATCHES "^--nimMainPrefix:"
            OR argument MATCHES "^--path:"
            OR argument MATCHES "\\.nim$")
        continue()
    endif()
    list(APPEND MCF5307_SYSCTL_COMMAND "${argument}")
endforeach()
list(APPEND MCF5307_SYSCTL_COMMAND "--path:${PROJECT_SOURCE_DIR}/src")

set(NIM_SYSCTL_COMMAND_LITERAL "")
foreach(argument IN LISTS MCF5307_SYSCTL_COMMAND)
    string(APPEND NIM_SYSCTL_COMMAND_LITERAL "    \"${argument}\"\n")
endforeach()

set(MCF5307_SYSCTL_SOURCE "${CMAKE_CURRENT_LIST_DIR}/t_system_control.nim")
set(MCF5307_SYSCTL_BINARY
    "${CMAKE_CURRENT_BINARY_DIR}/t_system_control_program")
set(MCF5307_SYSCTL_NIMCACHE
    "${CMAKE_CURRENT_BINARY_DIR}/t_system_control_nimcache")

set(MCF5307_SYSCTL_DRIVER_TEMPLATE [==[
# GENERATED BY tests/tests_cpu.cmake. Do not edit this copy in the build tree.
#
# The driver of the registered test `t_system_control`. It compiles the Nim
# test program with THE LIBRARY'S OWN FLAG SET, runs it, and fails when the run
# exits non-zero or does not report a full pass.

set(nim_command
@NIM_SYSCTL_COMMAND_LITERAL@)
set(source "@MCF5307_SYSCTL_SOURCE@")
set(binary "@MCF5307_SYSCTL_BINARY@")
set(nimcache "@MCF5307_SYSCTL_NIMCACHE@")

# The binary of an earlier run is REMOVED BEFORE THE COMPILE. Without this a
# compile that failed would leave the earlier binary in place, and the run
# would then execute code this run never produced.
file(REMOVE "${binary}")

execute_process(
    COMMAND ${nim_command} "--nimcache:${nimcache}" "-o:${binary}" "${source}"
    RESULT_VARIABLE sysctl_compile_rc
    OUTPUT_VARIABLE sysctl_compile_out
    ERROR_VARIABLE sysctl_compile_err)

if(NOT sysctl_compile_rc EQUAL 0)
    message(FATAL_ERROR
        "t_system_control: the Nim test program did not compile "
        "(result: ${sysctl_compile_rc})\n"
        "${sysctl_compile_out}\n${sysctl_compile_err}")
endif()

execute_process(
    COMMAND "${binary}"
    RESULT_VARIABLE sysctl_run_rc
    OUTPUT_VARIABLE sysctl_run_out
    ERROR_VARIABLE sysctl_run_err)
message("${sysctl_run_out}")

if(NOT sysctl_run_rc EQUAL 0)
    message(FATAL_ERROR
        "t_system_control: the run exited ${sysctl_run_rc}\n${sysctl_run_err}")
endif()

# The program prints `t_system_control: <N> cases passed`; failing cases make
# it exit non-zero, which the check above already rejects. Anchoring the tail
# here keeps a run that printed the banner but skipped the cases from passing.
# THE `[1-9]` IS WHAT REJECTS A RUN OF ZERO CASES.
if(NOT sysctl_run_out MATCHES "t_system_control: [1-9][0-9]* cases passed")
    message(FATAL_ERROR
        "t_system_control: the run exited 0 but did not report a full pass.\n"
        "  stdout : ${sysctl_run_out}\n  stderr : ${sysctl_run_err}")
endif()

# THE VANISHED-CASE CHECK. The anchor above stays beside it rather than being
# replaced by it: the two fail on differently-shaped defects, and the anchor is
# the cheaper of the two. `tests/case_sites.cmake` states the rules.
include("@MCF5307_CASE_SITES_MODULE@")
mcf5307_check_case_sites("t_system_control" "@MCF5307_SYSCTL_SOURCE@"
    "${sysctl_run_out}" 0)

# THE CASE TOTAL. The rules the call above applies catch a case that stops
# RUNNING; they cannot see a TABLE THAT GOT SHORTER, because a site inside a
# loop is one site however many rows the loop carries. `tests/case_sites.cmake`
# states at `mcf5307_check_case_total` why a TYPED figure is accepted here and
# what it still does not reach. MOVE IT ONLY WITH A DELIBERATE CHANGE IN THE
# CASE COUNT.
mcf5307_check_case_total("t_system_control" "${sysctl_run_out}" 37)

]==])

string(CONFIGURE "${MCF5307_SYSCTL_DRIVER_TEMPLATE}"
    MCF5307_SYSCTL_DRIVER @ONLY)
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/t_system_control_driver.cmake"
    "${MCF5307_SYSCTL_DRIVER}")

add_test(NAME t_system_control
    COMMAND "${CMAKE_COMMAND}"
        -P "${CMAKE_CURRENT_BINARY_DIR}/t_system_control_driver.cmake")

# -------------------------------------------------------------------- CPU-12
# `t_lines` - the line-A and line-F opcode spaces.
#
# ONE REGISTERED NAME, AND NO CORPUS BESIDE IT. A positive corpus executes an
# encoding and compares the machine state after it, and the whole subject of
# this task is encodings that MUST NOT execute. The negative corpus is CPU-13's
# and it names the removed 68000 instructions; the two line spaces are not
# removed instructions but opcode space this core declines to claim, and the
# refusal has to be asserted over the WHOLE of each space rather than at
# sampled encodings a corpus could carry.
#
# THE SWEEP IS EXHAUSTIVE AND NOT SAMPLED, AND THAT IS WHAT THIS SUITE ADDS.
# The two spaces reach no operation because no arm of `decodeWord` matches
# them, which is a property of an ABSENCE. An absence is the one thing a
# sampled case cannot pin: it holds for every word of the space or it does not
# hold at all, so the assertion is written over every word of it.
#
# THE FLAG SET IS THE LIBRARY'S OWN, taken exactly as the blocks above take it,
# and for the reason those blocks give.
#
# THE COMPILE HAPPENS INSIDE THE TEST AND NOT IN THE BUILD, for the reason the
# blocks above give: a `ctest` run over a tree whose build had failed would
# otherwise run a STALE binary of an earlier build and pass.

if(NOT DEFINED MCF5307_NIM_COMMAND)
    message(FATAL_ERROR
        "tests: t_lines cannot be registered: MCF5307_NIM_COMMAND is not set. "
        "The test takes its flag set from the library's own compile command, "
        "and a test registered against an empty command would compile with no "
        "flags at all and assert nothing.")
endif()

set(MCF5307_LINES_COMMAND "")
foreach(argument IN LISTS MCF5307_NIM_COMMAND)
    if(argument STREQUAL "--compileOnly"
            OR argument STREQUAL "--noMain"
            OR argument MATCHES "^--nimcache:"
            OR argument MATCHES "^--header:"
            OR argument MATCHES "^--nimMainPrefix:"
            OR argument MATCHES "^--path:"
            OR argument MATCHES "\\.nim$")
        continue()
    endif()
    list(APPEND MCF5307_LINES_COMMAND "${argument}")
endforeach()
list(APPEND MCF5307_LINES_COMMAND "--path:${PROJECT_SOURCE_DIR}/src")

set(NIM_LINES_COMMAND_LITERAL "")
foreach(argument IN LISTS MCF5307_LINES_COMMAND)
    string(APPEND NIM_LINES_COMMAND_LITERAL "    \"${argument}\"\n")
endforeach()

set(MCF5307_LINES_SOURCE "${CMAKE_CURRENT_LIST_DIR}/t_lines.nim")
set(MCF5307_LINES_BINARY "${CMAKE_CURRENT_BINARY_DIR}/t_lines_program")
set(MCF5307_LINES_NIMCACHE "${CMAKE_CURRENT_BINARY_DIR}/t_lines_nimcache")

set(MCF5307_LINES_DRIVER_TEMPLATE [==[
# GENERATED BY tests/tests_cpu.cmake. Do not edit this copy in the build tree.
#
# The driver of the registered test `t_lines`. It compiles the Nim test
# program with THE LIBRARY'S OWN FLAG SET, runs it, and fails when the run
# exits non-zero or does not report a full pass.

set(nim_command
@NIM_LINES_COMMAND_LITERAL@)
set(source "@MCF5307_LINES_SOURCE@")
set(binary "@MCF5307_LINES_BINARY@")
set(nimcache "@MCF5307_LINES_NIMCACHE@")

# The binary of an earlier run is REMOVED BEFORE THE COMPILE. Without this a
# compile that failed would leave the earlier binary in place, and the run
# would then execute code this run never produced.
file(REMOVE "${binary}")

execute_process(
    COMMAND ${nim_command} "--nimcache:${nimcache}" "-o:${binary}" "${source}"
    RESULT_VARIABLE lines_compile_rc
    OUTPUT_VARIABLE lines_compile_out
    ERROR_VARIABLE lines_compile_err)

if(NOT lines_compile_rc EQUAL 0)
    message(FATAL_ERROR
        "t_lines: the Nim test program did not compile "
        "(result: ${lines_compile_rc})\n"
        "${lines_compile_out}\n${lines_compile_err}")
endif()

execute_process(
    COMMAND "${binary}"
    RESULT_VARIABLE lines_run_rc
    OUTPUT_VARIABLE lines_run_out
    ERROR_VARIABLE lines_run_err)
message("${lines_run_out}")

if(NOT lines_run_rc EQUAL 0)
    message(FATAL_ERROR
        "t_lines: the run exited ${lines_run_rc}\n${lines_run_err}")
endif()

# The program prints `t_lines: <N> cases passed`; failing cases make it exit
# non-zero, which the check above already rejects. Anchoring the tail here
# keeps a run that printed the banner but skipped the cases from passing.
# THE `[1-9]` IS WHAT REJECTS A RUN OF ZERO CASES.
if(NOT lines_run_out MATCHES "t_lines: [1-9][0-9]* cases passed")
    message(FATAL_ERROR
        "t_lines: the run exited 0 but did not report a full pass.\n"
        "  stdout : ${lines_run_out}\n  stderr : ${lines_run_err}")
endif()

# THE VANISHED-CASE CHECK. The anchor above stays beside it rather than being
# replaced by it: the two fail on differently-shaped defects, and the anchor is
# the cheaper of the two. `tests/case_sites.cmake` states the rules.
include("@MCF5307_CASE_SITES_MODULE@")
mcf5307_check_case_sites("t_lines" "@MCF5307_LINES_SOURCE@" "${lines_run_out}"
    0)

# THE CASE TOTAL. The rules the call above applies catch a case that stops
# RUNNING; they cannot see a TABLE THAT GOT SHORTER, because a site inside a
# loop is one site however many rows the loop carries. THIS SUITE'S SWEEP IS
# EXACTLY SUCH A SITE. `tests/case_sites.cmake` states at
# `mcf5307_check_case_total` why a TYPED figure is accepted here and what it
# still does not reach. MOVE IT ONLY WITH A DELIBERATE CHANGE IN THE CASE
# COUNT.
mcf5307_check_case_total("t_lines" "${lines_run_out}" 20)

]==])

string(CONFIGURE "${MCF5307_LINES_DRIVER_TEMPLATE}"
    MCF5307_LINES_DRIVER @ONLY)
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/t_lines_driver.cmake"
    "${MCF5307_LINES_DRIVER}")

add_test(NAME t_lines
    COMMAND "${CMAKE_COMMAND}"
        -P "${CMAKE_CURRENT_BINARY_DIR}/t_lines_driver.cmake")

# -------------------------------------------------------------------- CPU-13
# `t_negative` - the negative corpus.
#
# ONE REGISTERED NAME, AND THE CORPUS IS BOUND INTO THE PROGRAM RATHER THAN
# PASSED TO IT. `tests/t_negative.nim` reads
# `conformance/corpus/negative_00.json` with `staticRead`, so the corpus
# arrives at COMPILE time and this block forwards no corpus path. A path
# forwarded at run time that pointed nowhere would leave the suite
# adjudicating an empty table and reporting a pass, and an empty negative
# corpus passes against any core at all.
#
# IT IS NOT REGISTERED IN `conformance/conformance_cpu.cmake` BESIDE THE FOUR
# POSITIVE GROUPS, AND THE REASON IS THE RUNNER RATHER THAN THE FILE. That
# runner takes a `<group>_00.json` and compares a machine state after the
# encoding EXECUTES; these cases are encodings that must not execute, and the
# comparison it makes has nothing to read. `conformance/parse_check.cpp` names
# its four required groups explicitly, so this file is invisible to it too and
# `t0_corpus_parses` is unaffected either way.
#
# THE GROUND IT DIVIDES WITH `t_lines` IS CPU-12's OWN SPLIT, stated in that
# block above: the line-A and line-F spaces are opcode space this core
# declines to claim and are swept exhaustively there, and this suite is the
# REMOVED 68000 INSTRUCTIONS, which live in lines the core does claim and
# decode. No encoding in the corpus is in either of those two lines.
#
# THE FLAG SET IS THE LIBRARY'S OWN, taken exactly as the blocks above take
# it, and for the reason those blocks give.
#
# THE COMPILE HAPPENS INSIDE THE TEST AND NOT IN THE BUILD, for the reason the
# blocks above give: a `ctest` run over a tree whose build had failed would
# otherwise run a STALE binary of an earlier build and pass. It carries a
# second weight here, because the corpus is a compile-time input: a corpus
# edited without a recompile would be tested in its previous state.

if(NOT DEFINED MCF5307_NIM_COMMAND)
    message(FATAL_ERROR
        "tests: t_negative cannot be registered: MCF5307_NIM_COMMAND is not "
        "set. The test takes its flag set from the library's own compile "
        "command, and a test registered against an empty command would "
        "compile with no flags at all and assert nothing.")
endif()

set(MCF5307_NEGATIVE_COMMAND "")
foreach(argument IN LISTS MCF5307_NIM_COMMAND)
    if(argument STREQUAL "--compileOnly"
            OR argument STREQUAL "--noMain"
            OR argument MATCHES "^--nimcache:"
            OR argument MATCHES "^--header:"
            OR argument MATCHES "^--nimMainPrefix:"
            OR argument MATCHES "^--path:"
            OR argument MATCHES "\\.nim$")
        continue()
    endif()
    list(APPEND MCF5307_NEGATIVE_COMMAND "${argument}")
endforeach()
list(APPEND MCF5307_NEGATIVE_COMMAND "--path:${PROJECT_SOURCE_DIR}/src")

set(NIM_NEGATIVE_COMMAND_LITERAL "")
foreach(argument IN LISTS MCF5307_NEGATIVE_COMMAND)
    string(APPEND NIM_NEGATIVE_COMMAND_LITERAL "    \"${argument}\"\n")
endforeach()

set(MCF5307_NEGATIVE_SOURCE "${CMAKE_CURRENT_LIST_DIR}/t_negative.nim")
set(MCF5307_NEGATIVE_BINARY "${CMAKE_CURRENT_BINARY_DIR}/t_negative_program")
set(MCF5307_NEGATIVE_NIMCACHE
    "${CMAKE_CURRENT_BINARY_DIR}/t_negative_nimcache")

set(MCF5307_NEGATIVE_DRIVER_TEMPLATE [==[
# GENERATED BY tests/tests_cpu.cmake. Do not edit this copy in the build tree.
#
# The driver of the registered test `t_negative`. It compiles the Nim test
# program with THE LIBRARY'S OWN FLAG SET, runs it, and fails when the run
# exits non-zero or does not report a full pass.

set(nim_command
@NIM_NEGATIVE_COMMAND_LITERAL@)
set(source "@MCF5307_NEGATIVE_SOURCE@")
set(binary "@MCF5307_NEGATIVE_BINARY@")
set(nimcache "@MCF5307_NEGATIVE_NIMCACHE@")

# The binary of an earlier run is REMOVED BEFORE THE COMPILE. Without this a
# compile that failed would leave the earlier binary in place, and the run
# would then execute code this run never produced.
file(REMOVE "${binary}")

execute_process(
    COMMAND ${nim_command} "--nimcache:${nimcache}" "-o:${binary}" "${source}"
    RESULT_VARIABLE negative_compile_rc
    OUTPUT_VARIABLE negative_compile_out
    ERROR_VARIABLE negative_compile_err)

if(NOT negative_compile_rc EQUAL 0)
    message(FATAL_ERROR
        "t_negative: the Nim test program did not compile "
        "(result: ${negative_compile_rc})\n"
        "${negative_compile_out}\n${negative_compile_err}")
endif()

execute_process(
    COMMAND "${binary}"
    RESULT_VARIABLE negative_run_rc
    OUTPUT_VARIABLE negative_run_out
    ERROR_VARIABLE negative_run_err)
message("${negative_run_out}")

if(NOT negative_run_rc EQUAL 0)
    message(FATAL_ERROR
        "t_negative: the run exited ${negative_run_rc}\n${negative_run_err}")
endif()

# The program prints `t_negative: <N> cases passed`; failing cases make it
# exit non-zero, which the check above already rejects. Anchoring the tail
# here keeps a run that printed the banner but skipped the cases from passing.
# THE `[1-9]` IS WHAT REJECTS A RUN OF ZERO CASES.
if(NOT negative_run_out MATCHES "t_negative: [1-9][0-9]* cases passed")
    message(FATAL_ERROR
        "t_negative: the run exited 0 but did not report a full pass.\n"
        "  stdout : ${negative_run_out}\n  stderr : ${negative_run_err}")
endif()

# THE VANISHED-CASE CHECK. The anchor above stays beside it rather than being
# replaced by it: the two fail on differently-shaped defects, and the anchor
# is the cheaper of the two. `tests/case_sites.cmake` states the rules.
include("@MCF5307_CASE_SITES_MODULE@")
mcf5307_check_case_sites("t_negative" "@MCF5307_NEGATIVE_SOURCE@"
    "${negative_run_out}" 0)

# THE CASE TOTAL. The rules the call above applies catch a case that stops
# RUNNING; they cannot see a TABLE THAT GOT SHORTER, because a site inside a
# loop is one site however many rows the loop carries. EVERY PER-CASE SITE IN
# THIS SUITE IS SUCH A SITE - the suite iterates the corpus - so a case
# deleted from `conformance/corpus/negative_00.json` is invisible to
# everything except this figure. `tests/case_sites.cmake` states at
# `mcf5307_check_case_total` why a TYPED figure is accepted here and what it
# still does not reach. MOVE IT ONLY WITH A DELIBERATE CHANGE IN THE CASE
# COUNT.
mcf5307_check_case_total("t_negative" "${negative_run_out}" 33)

]==])

string(CONFIGURE "${MCF5307_NEGATIVE_DRIVER_TEMPLATE}"
    MCF5307_NEGATIVE_DRIVER @ONLY)
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/t_negative_driver.cmake"
    "${MCF5307_NEGATIVE_DRIVER}")

add_test(NAME t_negative
    COMMAND "${CMAKE_COMMAND}"
        -P "${CMAKE_CURRENT_BINARY_DIR}/t_negative_driver.cmake")

# -------------------------------------------------------------------- CPU-14
# `t_exception` - the exception model.
#
# ONE REGISTERED NAME, AND NO CORPUS BESIDE IT. Every other executor block in
# this file registers a unit test beside a conformance corpus of the same
# group. This task has none: the corpus runner executes ASSEMBLED encodings,
# and neither an access error nor an address error can be assembled. The whole
# of the evidence for this task is the registered name below.
#
# IT COMPILES `src/mcf5307/exception.nim` FOR ITS OWN RUN, with the library's
# own flag set, so that the module this test asserts about is built the way the
# library builds it.
#
# THE FLAG SET, THE COMPILE INSIDE THE TEST and the two-part failure check are
# taken from the `t_control` block above, for the reasons that block gives. The
# tail anchor is `[1-9][0-9]*`, which rejects a run of zero cases.

if(NOT DEFINED MCF5307_NIM_COMMAND)
    message(FATAL_ERROR
        "tests: t_exception cannot be registered: MCF5307_NIM_COMMAND is not "
        "set. The test takes its flag set from the library's own compile "
        "command, and a test registered against an empty command would compile "
        "with no flags at all and assert nothing.")
endif()

set(MCF5307_EXCEPTION_COMMAND "")
foreach(argument IN LISTS MCF5307_NIM_COMMAND)
    if(argument STREQUAL "--compileOnly"
            OR argument STREQUAL "--noMain"
            OR argument MATCHES "^--nimcache:"
            OR argument MATCHES "^--header:"
            OR argument MATCHES "^--nimMainPrefix:"
            OR argument MATCHES "^--path:"
            OR argument MATCHES "\\.nim$")
        continue()
    endif()
    list(APPEND MCF5307_EXCEPTION_COMMAND "${argument}")
endforeach()
list(APPEND MCF5307_EXCEPTION_COMMAND "--path:${PROJECT_SOURCE_DIR}/src")

set(NIM_EXCEPTION_COMMAND_LITERAL "")
foreach(argument IN LISTS MCF5307_EXCEPTION_COMMAND)
    string(APPEND NIM_EXCEPTION_COMMAND_LITERAL "    \"${argument}\"\n")
endforeach()

set(MCF5307_EXCEPTION_SOURCE "${CMAKE_CURRENT_LIST_DIR}/t_exception.nim")
set(MCF5307_EXCEPTION_BINARY "${CMAKE_CURRENT_BINARY_DIR}/t_exception_program")
set(MCF5307_EXCEPTION_NIMCACHE
    "${CMAKE_CURRENT_BINARY_DIR}/t_exception_nimcache")

set(MCF5307_EXCEPTION_DRIVER_TEMPLATE [==[
# GENERATED BY tests/tests_cpu.cmake. Do not edit this copy in the build tree.
#
# The driver of the registered test `t_exception`. It compiles the Nim test
# program with THE LIBRARY'S OWN FLAG SET, runs it, and fails when the run exits
# non-zero or does not report a full pass.

set(nim_command
@NIM_EXCEPTION_COMMAND_LITERAL@)
set(source "@MCF5307_EXCEPTION_SOURCE@")
set(binary "@MCF5307_EXCEPTION_BINARY@")
set(nimcache "@MCF5307_EXCEPTION_NIMCACHE@")

# The binary of an earlier run is REMOVED BEFORE THE COMPILE. Without this a
# compile that failed would leave the earlier binary in place, and the run
# would then execute code this run never produced.
file(REMOVE "${binary}")

execute_process(
    COMMAND ${nim_command} "--nimcache:${nimcache}" "-o:${binary}" "${source}"
    RESULT_VARIABLE exception_compile_rc
    OUTPUT_VARIABLE exception_compile_out
    ERROR_VARIABLE exception_compile_err)

if(NOT exception_compile_rc EQUAL 0)
    message(FATAL_ERROR
        "t_exception: the Nim test program did not compile "
        "(result: ${exception_compile_rc})\n"
        "${exception_compile_out}\n${exception_compile_err}")
endif()

execute_process(
    COMMAND "${binary}"
    RESULT_VARIABLE exception_run_rc
    OUTPUT_VARIABLE exception_run_out
    ERROR_VARIABLE exception_run_err)
message("${exception_run_out}")

if(NOT exception_run_rc EQUAL 0)
    message(FATAL_ERROR
        "t_exception: the run exited ${exception_run_rc}\n${exception_run_err}")
endif()

# The program prints `t_exception: <N> cases passed`; failing cases make it
# exit non-zero, which the check above already rejects. THE COUNT IS
# `[1-9][0-9]*` AND NOT `[0-9]+`: `[0-9]+` matches `0`, so a test program
# reduced to its banner alone would exit 0, run no case and PASS.
if(NOT exception_run_out MATCHES "t_exception: [1-9][0-9]* cases passed")
    message(FATAL_ERROR
        "t_exception: the run exited 0 but did not report a full pass.\n"
        "  stdout : ${exception_run_out}\n  stderr : ${exception_run_err}")
endif()

# THE VANISHED-CASE CHECK. The anchor above stays beside it rather than being
# replaced by it: the two fail on differently-shaped defects, and the anchor is
# the cheaper of the two. `tests/case_sites.cmake` states the rules.
include("@MCF5307_CASE_SITES_MODULE@")
mcf5307_check_case_sites("t_exception" "@MCF5307_EXCEPTION_SOURCE@" "${exception_run_out}"
    0)

# THE CASE TOTAL. The rules the call above applies catch a case that stops
# RUNNING; they cannot see a TABLE THAT GOT SHORTER, because a site inside a
# loop is one site however many rows the loop carries. `tests/case_sites.cmake`
# states at `mcf5307_check_case_total` why a TYPED figure is accepted here and
# what it still does not reach. MOVE IT ONLY WITH A DELIBERATE CHANGE IN THE
# CASE COUNT.
mcf5307_check_case_total("t_exception" "${exception_run_out}" 39)

]==])

string(CONFIGURE "${MCF5307_EXCEPTION_DRIVER_TEMPLATE}"
    MCF5307_EXCEPTION_DRIVER @ONLY)
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/t_exception_driver.cmake"
    "${MCF5307_EXCEPTION_DRIVER}")

add_test(NAME t_exception
    COMMAND "${CMAKE_COMMAND}"
        -P "${CMAKE_CURRENT_BINARY_DIR}/t_exception_driver.cmake")

# -------------------------------------------------------------------- CPU-15
# `t_bus_fault` - the bus-fault channel.
#
# ONE REGISTERED NAME, AND NO CORPUS BESIDE IT. The corpus runner executes
# ASSEMBLED encodings, and a bus fault is raised by a board rather than by an
# instruction, so there is no encoding to assemble. The whole of the evidence
# for this task is the registered name below.
#
# THE FLAG SET IS THE LIBRARY'S OWN, taken from the compile command this
# configure built for the library itself, so that the modules this test asserts
# about are built the way the library builds them. The tail anchor is
# `[1-9][0-9]*`, which rejects a run of zero cases.

if(NOT DEFINED MCF5307_NIM_COMMAND)
    message(FATAL_ERROR
        "tests: t_bus_fault cannot be registered: MCF5307_NIM_COMMAND is not "
        "set. The test takes its flag set from the library's own compile "
        "command, and a test registered against an empty command would compile "
        "with no flags at all and assert nothing.")
endif()

set(MCF5307_BUS_FAULT_COMMAND "")
foreach(argument IN LISTS MCF5307_NIM_COMMAND)
    if(argument STREQUAL "--compileOnly"
            OR argument STREQUAL "--noMain"
            OR argument MATCHES "^--nimcache:"
            OR argument MATCHES "^--header:"
            OR argument MATCHES "^--nimMainPrefix:"
            OR argument MATCHES "^--path:"
            OR argument MATCHES "\\.nim$")
        continue()
    endif()
    list(APPEND MCF5307_BUS_FAULT_COMMAND "${argument}")
endforeach()
list(APPEND MCF5307_BUS_FAULT_COMMAND "--path:${PROJECT_SOURCE_DIR}/src")

set(NIM_BUS_FAULT_COMMAND_LITERAL "")
foreach(argument IN LISTS MCF5307_BUS_FAULT_COMMAND)
    string(APPEND NIM_BUS_FAULT_COMMAND_LITERAL "    \"${argument}\"\n")
endforeach()

set(MCF5307_BUS_FAULT_SOURCE "${CMAKE_CURRENT_LIST_DIR}/t_bus_fault.nim")
set(MCF5307_BUS_FAULT_BINARY "${CMAKE_CURRENT_BINARY_DIR}/t_bus_fault_program")
set(MCF5307_BUS_FAULT_NIMCACHE
    "${CMAKE_CURRENT_BINARY_DIR}/t_bus_fault_nimcache")

set(MCF5307_BUS_FAULT_DRIVER_TEMPLATE [==[
# GENERATED BY tests/tests_cpu.cmake. Do not edit this copy in the build tree.
#
# The driver of the registered test `t_bus_fault`. It compiles the Nim test
# program with THE LIBRARY'S OWN FLAG SET, runs it, and fails when the run exits
# non-zero or does not report a full pass.

set(nim_command
@NIM_BUS_FAULT_COMMAND_LITERAL@)
set(source "@MCF5307_BUS_FAULT_SOURCE@")
set(binary "@MCF5307_BUS_FAULT_BINARY@")
set(nimcache "@MCF5307_BUS_FAULT_NIMCACHE@")

# The binary of an earlier run is REMOVED BEFORE THE COMPILE. Without this a
# compile that failed would leave the earlier binary in place, and the run
# would then execute code this run never produced.
file(REMOVE "${binary}")

execute_process(
    COMMAND ${nim_command} "--nimcache:${nimcache}" "-o:${binary}" "${source}"
    RESULT_VARIABLE bus_fault_compile_rc
    OUTPUT_VARIABLE bus_fault_compile_out
    ERROR_VARIABLE bus_fault_compile_err)

if(NOT bus_fault_compile_rc EQUAL 0)
    message(FATAL_ERROR
        "t_bus_fault: the Nim test program did not compile "
        "(result: ${bus_fault_compile_rc})\n"
        "${bus_fault_compile_out}\n${bus_fault_compile_err}")
endif()

execute_process(
    COMMAND "${binary}"
    RESULT_VARIABLE bus_fault_run_rc
    OUTPUT_VARIABLE bus_fault_run_out
    ERROR_VARIABLE bus_fault_run_err)
message("${bus_fault_run_out}")

if(NOT bus_fault_run_rc EQUAL 0)
    message(FATAL_ERROR
        "t_bus_fault: the run exited ${bus_fault_run_rc}\n${bus_fault_run_err}")
endif()

# The program prints `t_bus_fault: <N> cases passed`; failing cases make it
# exit non-zero, which the check above already rejects. THE COUNT IS
# `[1-9][0-9]*` AND NOT `[0-9]+`: `[0-9]+` matches `0`, so a test program
# reduced to its banner alone would exit 0, run no case and PASS.
if(NOT bus_fault_run_out MATCHES "t_bus_fault: [1-9][0-9]* cases passed")
    message(FATAL_ERROR
        "t_bus_fault: the run exited 0 but did not report a full pass.\n"
        "  stdout : ${bus_fault_run_out}\n  stderr : ${bus_fault_run_err}")
endif()

# THE VANISHED-CASE CHECK. The anchor above stays beside it rather than being
# replaced by it: the two fail on differently-shaped defects, and the anchor is
# the cheaper of the two. `tests/case_sites.cmake` states the rules.
include("@MCF5307_CASE_SITES_MODULE@")
mcf5307_check_case_sites("t_bus_fault" "@MCF5307_BUS_FAULT_SOURCE@" "${bus_fault_run_out}"
    0)

# THE CASE TOTAL. The rules the call above applies catch a case that stops
# RUNNING; they cannot see a TABLE THAT GOT SHORTER, because a site inside a
# loop is one site however many rows the loop carries. `tests/case_sites.cmake`
# states at `mcf5307_check_case_total` why a TYPED figure is accepted here and
# what it still does not reach. MOVE IT ONLY WITH A DELIBERATE CHANGE IN THE
# CASE COUNT.
mcf5307_check_case_total("t_bus_fault" "${bus_fault_run_out}" 24)

]==])

string(CONFIGURE "${MCF5307_BUS_FAULT_DRIVER_TEMPLATE}"
    MCF5307_BUS_FAULT_DRIVER @ONLY)
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/t_bus_fault_driver.cmake"
    "${MCF5307_BUS_FAULT_DRIVER}")

add_test(NAME t_bus_fault
    COMMAND "${CMAKE_COMMAND}"
        -P "${CMAKE_CURRENT_BINARY_DIR}/t_bus_fault_driver.cmake")

# -------------------------------------------------------------------- CPU-16
# `t_bus_fault_write` - the IMPRECISE stacked program counter of an operand
# write fault.
#
# ONE REGISTERED NAME, AND NO CORPUS BESIDE IT, for the reason the CPU-15 block
# above gives: the corpus runner executes ASSEMBLED encodings, and a bus fault
# is raised by a board rather than by an instruction, so there is no encoding to
# assemble. The whole of the evidence for this task is the registered name
# below.
#
# THE FLAG SET IS THE LIBRARY'S OWN, taken from the compile command this
# configure built for the library itself, so that the modules this test asserts
# about are built the way the library builds them. The tail anchor is
# `[1-9][0-9]*`, which rejects a run of zero cases.

if(NOT DEFINED MCF5307_NIM_COMMAND)
    message(FATAL_ERROR
        "tests: t_bus_fault_write cannot be registered: MCF5307_NIM_COMMAND is "
        "not set. The test takes its flag set from the library's own compile "
        "command, and a test registered against an empty command would compile "
        "with no flags at all and assert nothing.")
endif()

set(MCF5307_BUS_FAULT_WRITE_COMMAND "")
foreach(argument IN LISTS MCF5307_NIM_COMMAND)
    if(argument STREQUAL "--compileOnly"
            OR argument STREQUAL "--noMain"
            OR argument MATCHES "^--nimcache:"
            OR argument MATCHES "^--header:"
            OR argument MATCHES "^--nimMainPrefix:"
            OR argument MATCHES "^--path:"
            OR argument MATCHES "\\.nim$")
        continue()
    endif()
    list(APPEND MCF5307_BUS_FAULT_WRITE_COMMAND "${argument}")
endforeach()
list(APPEND MCF5307_BUS_FAULT_WRITE_COMMAND "--path:${PROJECT_SOURCE_DIR}/src")

set(NIM_BUS_FAULT_WRITE_COMMAND_LITERAL "")
foreach(argument IN LISTS MCF5307_BUS_FAULT_WRITE_COMMAND)
    string(APPEND NIM_BUS_FAULT_WRITE_COMMAND_LITERAL "    \"${argument}\"\n")
endforeach()

set(MCF5307_BUS_FAULT_WRITE_SOURCE
    "${CMAKE_CURRENT_LIST_DIR}/t_bus_fault_write.nim")
set(MCF5307_BUS_FAULT_WRITE_BINARY
    "${CMAKE_CURRENT_BINARY_DIR}/t_bus_fault_write_program")
set(MCF5307_BUS_FAULT_WRITE_NIMCACHE
    "${CMAKE_CURRENT_BINARY_DIR}/t_bus_fault_write_nimcache")

set(MCF5307_BUS_FAULT_WRITE_DRIVER_TEMPLATE [==[
# GENERATED BY tests/tests_cpu.cmake. Do not edit this copy in the build tree.
#
# The driver of the registered test `t_bus_fault_write`. It compiles the Nim
# test program with THE LIBRARY'S OWN FLAG SET, runs it, and fails when the run
# exits non-zero or does not report a full pass.

set(nim_command
@NIM_BUS_FAULT_WRITE_COMMAND_LITERAL@)
set(source "@MCF5307_BUS_FAULT_WRITE_SOURCE@")
set(binary "@MCF5307_BUS_FAULT_WRITE_BINARY@")
set(nimcache "@MCF5307_BUS_FAULT_WRITE_NIMCACHE@")

# The binary of an earlier run is REMOVED BEFORE THE COMPILE. Without this a
# compile that failed would leave the earlier binary in place, and the run
# would then execute code this run never produced.
file(REMOVE "${binary}")

execute_process(
    COMMAND ${nim_command} "--nimcache:${nimcache}" "-o:${binary}" "${source}"
    RESULT_VARIABLE bus_fault_write_compile_rc
    OUTPUT_VARIABLE bus_fault_write_compile_out
    ERROR_VARIABLE bus_fault_write_compile_err)

if(NOT bus_fault_write_compile_rc EQUAL 0)
    message(FATAL_ERROR
        "t_bus_fault_write: the Nim test program did not compile "
        "(result: ${bus_fault_write_compile_rc})\n"
        "${bus_fault_write_compile_out}\n${bus_fault_write_compile_err}")
endif()

execute_process(
    COMMAND "${binary}"
    RESULT_VARIABLE bus_fault_write_run_rc
    OUTPUT_VARIABLE bus_fault_write_run_out
    ERROR_VARIABLE bus_fault_write_run_err)
message("${bus_fault_write_run_out}")

if(NOT bus_fault_write_run_rc EQUAL 0)
    message(FATAL_ERROR
        "t_bus_fault_write: the run exited ${bus_fault_write_run_rc}\n"
        "${bus_fault_write_run_err}")
endif()

# The program prints `t_bus_fault_write: <N> cases passed`; failing cases make
# it exit non-zero, which the check above already rejects. THE COUNT IS
# `[1-9][0-9]*` AND NOT `[0-9]+`: `[0-9]+` matches `0`, so a test program
# reduced to its banner alone would exit 0, run no case and PASS.
if(NOT bus_fault_write_run_out MATCHES
        "t_bus_fault_write: [1-9][0-9]* cases passed")
    message(FATAL_ERROR
        "t_bus_fault_write: the run exited 0 but did not report a full pass.\n"
        "  stdout : ${bus_fault_write_run_out}\n"
        "  stderr : ${bus_fault_write_run_err}")
endif()

# THE VANISHED-CASE CHECK. The anchor above stays beside it rather than being
# replaced by it: the two fail on differently-shaped defects, and the anchor is
# the cheaper of the two. `tests/case_sites.cmake` states the rules.
include("@MCF5307_CASE_SITES_MODULE@")
mcf5307_check_case_sites("t_bus_fault_write"
    "@MCF5307_BUS_FAULT_WRITE_SOURCE@" "${bus_fault_write_run_out}" 0)

# THE CASE TOTAL. The rules the call above applies catch a case that stops
# RUNNING; they cannot see a TABLE THAT GOT SHORTER, because a site inside a
# loop is one site however many rows the loop carries. `tests/case_sites.cmake`
# states at `mcf5307_check_case_total` why a TYPED figure is accepted here and
# what it still does not reach. MOVE IT ONLY WITH A DELIBERATE CHANGE IN THE
# CASE COUNT.
mcf5307_check_case_total("t_bus_fault_write" "${bus_fault_write_run_out}" 5)

]==])

string(CONFIGURE "${MCF5307_BUS_FAULT_WRITE_DRIVER_TEMPLATE}"
    MCF5307_BUS_FAULT_WRITE_DRIVER @ONLY)
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/t_bus_fault_write_driver.cmake"
    "${MCF5307_BUS_FAULT_WRITE_DRIVER}")

add_test(NAME t_bus_fault_write
    COMMAND "${CMAKE_COMMAND}"
        -P "${CMAKE_CURRENT_BINARY_DIR}/t_bus_fault_write_driver.cmake")

# -------------------------------------------------------------------- CPU-17
# `t_irq` - the interrupt model.
#
# ONE REGISTERED NAME, AND NO CORPUS BESIDE IT, for the reason the CPU-14
# block above gives: the corpus runner executes ASSEMBLED encodings, and an
# interrupt has no encoding. The whole of the evidence for this task is the
# registered name below.
#
# IT EXERCISES A MODULE THE LIBRARY DOES CARRY. `src/mcf5307/cpu.nim` imports
# `mcf5307/irq`, so the entry module reaches it transitively and its
# `mcf5307_set_irq` is in the archive; the test reaches the same module by
# source. That import also carries `src/mcf5307/exception.nim` into the library,
# because `irq.nim` imports it for `autovectorFor`.
#
# THE FLAG SET, THE COMPILE INSIDE THE TEST and the two-part failure check are
# taken from the `t_exception` block above, for the reasons that block gives.
# The tail anchor is `[1-9][0-9]*`, which rejects a run of zero cases.

if(NOT DEFINED MCF5307_NIM_COMMAND)
    message(FATAL_ERROR
        "tests: t_irq cannot be registered: MCF5307_NIM_COMMAND is not set. "
        "The test takes its flag set from the library's own compile command, "
        "and a test registered against an empty command would compile with no "
        "flags at all and assert nothing.")
endif()

set(MCF5307_IRQ_COMMAND "")
foreach(argument IN LISTS MCF5307_NIM_COMMAND)
    if(argument STREQUAL "--compileOnly"
            OR argument STREQUAL "--noMain"
            OR argument MATCHES "^--nimcache:"
            OR argument MATCHES "^--header:"
            OR argument MATCHES "^--nimMainPrefix:"
            OR argument MATCHES "^--path:"
            OR argument MATCHES "\\.nim$")
        continue()
    endif()
    list(APPEND MCF5307_IRQ_COMMAND "${argument}")
endforeach()
list(APPEND MCF5307_IRQ_COMMAND "--path:${PROJECT_SOURCE_DIR}/src")

set(NIM_IRQ_COMMAND_LITERAL "")
foreach(argument IN LISTS MCF5307_IRQ_COMMAND)
    string(APPEND NIM_IRQ_COMMAND_LITERAL "    \"${argument}\"\n")
endforeach()

set(MCF5307_IRQ_SOURCE "${CMAKE_CURRENT_LIST_DIR}/t_irq.nim")
set(MCF5307_IRQ_BINARY "${CMAKE_CURRENT_BINARY_DIR}/t_irq_program")
set(MCF5307_IRQ_NIMCACHE "${CMAKE_CURRENT_BINARY_DIR}/t_irq_nimcache")

set(MCF5307_IRQ_DRIVER_TEMPLATE [==[
# GENERATED BY tests/tests_cpu.cmake. Do not edit this copy in the build tree.
#
# The driver of the registered test `t_irq`. It compiles the Nim test program
# with THE LIBRARY'S OWN FLAG SET, runs it, and fails when the run exits
# non-zero or does not report a full pass.

set(nim_command
@NIM_IRQ_COMMAND_LITERAL@)
set(source "@MCF5307_IRQ_SOURCE@")
set(binary "@MCF5307_IRQ_BINARY@")
set(nimcache "@MCF5307_IRQ_NIMCACHE@")

# The binary of an earlier run is REMOVED BEFORE THE COMPILE. Without this a
# compile that failed would leave the earlier binary in place, and the run
# would then execute code this run never produced.
file(REMOVE "${binary}")

execute_process(
    COMMAND ${nim_command} "--nimcache:${nimcache}" "-o:${binary}" "${source}"
    RESULT_VARIABLE irq_compile_rc
    OUTPUT_VARIABLE irq_compile_out
    ERROR_VARIABLE irq_compile_err)

if(NOT irq_compile_rc EQUAL 0)
    message(FATAL_ERROR
        "t_irq: the Nim test program did not compile "
        "(result: ${irq_compile_rc})\n"
        "${irq_compile_out}\n${irq_compile_err}")
endif()

execute_process(
    COMMAND "${binary}"
    RESULT_VARIABLE irq_run_rc
    OUTPUT_VARIABLE irq_run_out
    ERROR_VARIABLE irq_run_err)
message("${irq_run_out}")

if(NOT irq_run_rc EQUAL 0)
    message(FATAL_ERROR
        "t_irq: the run exited ${irq_run_rc}\n${irq_run_err}")
endif()

# The program prints `t_irq: <N> cases passed`; failing cases make it exit
# non-zero, which the check above already rejects. THE COUNT IS `[1-9][0-9]*`
# AND NOT `[0-9]+`: `[0-9]+` matches `0`, so a test program reduced to its
# banner alone would exit 0, run no case and PASS.
if(NOT irq_run_out MATCHES "t_irq: [1-9][0-9]* cases passed")
    message(FATAL_ERROR
        "t_irq: the run exited 0 but did not report a full pass.\n"
        "  stdout : ${irq_run_out}\n  stderr : ${irq_run_err}")
endif()

# THE VANISHED-CASE CHECK. The anchor above stays beside it rather than being
# replaced by it: the two fail on differently-shaped defects, and the anchor is
# the cheaper of the two. `tests/case_sites.cmake` states the rules.
include("@MCF5307_CASE_SITES_MODULE@")
mcf5307_check_case_sites("t_irq" "@MCF5307_IRQ_SOURCE@" "${irq_run_out}"
    0)

# THE CASE TOTAL. The rules the call above applies catch a case that stops
# RUNNING; they cannot see a TABLE THAT GOT SHORTER, because a site inside a
# loop is one site however many rows the loop carries. `tests/case_sites.cmake`
# states at `mcf5307_check_case_total` why a TYPED figure is accepted here and
# what it still does not reach. MOVE IT ONLY WITH A DELIBERATE CHANGE IN THE
# CASE COUNT.
mcf5307_check_case_total("t_irq" "${irq_run_out}" 37)

]==])

string(CONFIGURE "${MCF5307_IRQ_DRIVER_TEMPLATE}" MCF5307_IRQ_DRIVER @ONLY)
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/t_irq_driver.cmake"
    "${MCF5307_IRQ_DRIVER}")

add_test(NAME t_irq
    COMMAND "${CMAKE_COMMAND}"
        -P "${CMAKE_CURRENT_BINARY_DIR}/t_irq_driver.cmake")

# -------------------------------------------------------------------- CPU-18
# `t_state` - the state block, its layout and its refusal of a damaged block.
#
# ONE REGISTERED NAME, AND NO CORPUS BESIDE IT, for the reason the CPU-14 and
# CPU-17 blocks give: the corpus runner executes ASSEMBLED encodings, and a
# snapshot has no encoding.
#
# WHETHER THE LIBRARY CARRIES THE MODULE THIS SUITE EXERCISES IS NOT ASSERTED
# HERE, AND THE READER IS POINTED AT WHAT DOES SAY. `cmake/Nim.cmake` step 3
# lists the compile units Nim's own JSON names, so a module NO import chain
# from `src/mcf5307.nim` reaches is never compiled and its `{.exportc.}` names
# never become symbols; step 4a then reports those names as NOT YET
# IMPLEMENTED, on every configure, by measuring the object rather than by
# describing it. Read that report and not this comment.
#
# THIS SUITE IS INDIFFERENT TO THE ANSWER, AND THAT IS WHY IT IS WRITTEN THIS
# WAY. It compiles `src/mcf5307/state.nim` FROM SOURCE through `--path:src`,
# exactly as every suite above it compiles the modules it measures, so it
# measures the module whether or not the archive holds it. What no suite here
# can measure is the LINK; `abi_smoke` is the test that does.
#
# THE FLAG SET, THE COMPILE INSIDE THE TEST and the two-part failure check are
# taken from the `t_irq` block above, for the reasons that block gives.

if(NOT DEFINED MCF5307_NIM_COMMAND)
    message(FATAL_ERROR
        "tests: t_state cannot be registered: MCF5307_NIM_COMMAND is not set. "
        "The test takes its flag set from the library's own compile command, "
        "and a test registered against an empty command would compile with no "
        "flags at all and assert nothing.")
endif()

set(MCF5307_STATE_COMMAND "")
foreach(argument IN LISTS MCF5307_NIM_COMMAND)
    if(argument STREQUAL "--compileOnly"
            OR argument STREQUAL "--noMain"
            OR argument MATCHES "^--nimcache:"
            OR argument MATCHES "^--header:"
            OR argument MATCHES "^--nimMainPrefix:"
            OR argument MATCHES "^--path:"
            OR argument MATCHES "\\.nim$")
        continue()
    endif()
    list(APPEND MCF5307_STATE_COMMAND "${argument}")
endforeach()
list(APPEND MCF5307_STATE_COMMAND "--path:${PROJECT_SOURCE_DIR}/src")

set(NIM_STATE_COMMAND_LITERAL "")
foreach(argument IN LISTS MCF5307_STATE_COMMAND)
    string(APPEND NIM_STATE_COMMAND_LITERAL "    \"${argument}\"\n")
endforeach()

set(MCF5307_STATE_SOURCE "${CMAKE_CURRENT_LIST_DIR}/t_state.nim")
set(MCF5307_STATE_BINARY "${CMAKE_CURRENT_BINARY_DIR}/t_state_program")
set(MCF5307_STATE_NIMCACHE "${CMAKE_CURRENT_BINARY_DIR}/t_state_nimcache")

set(MCF5307_STATE_DRIVER_TEMPLATE [==[
# GENERATED BY tests/tests_cpu.cmake. Do not edit this copy in the build tree.
#
# The driver of the registered test `t_state`. It compiles the Nim test program
# with THE LIBRARY'S OWN FLAG SET, runs it, and fails when the run exits
# non-zero or does not report a full pass.

set(nim_command
@NIM_STATE_COMMAND_LITERAL@)
set(source "@MCF5307_STATE_SOURCE@")
set(binary "@MCF5307_STATE_BINARY@")
set(nimcache "@MCF5307_STATE_NIMCACHE@")

# The binary of an earlier run is REMOVED BEFORE THE COMPILE. Without this a
# compile that failed would leave the earlier binary in place, and the run
# would then execute code this run never produced.
file(REMOVE "${binary}")

execute_process(
    COMMAND ${nim_command} "--nimcache:${nimcache}" "-o:${binary}" "${source}"
    RESULT_VARIABLE state_compile_rc
    OUTPUT_VARIABLE state_compile_out
    ERROR_VARIABLE state_compile_err)

if(NOT state_compile_rc EQUAL 0)
    message(FATAL_ERROR
        "t_state: the Nim test program did not compile "
        "(result: ${state_compile_rc})\n"
        "${state_compile_out}\n${state_compile_err}")
endif()

execute_process(
    COMMAND "${binary}"
    RESULT_VARIABLE state_run_rc
    OUTPUT_VARIABLE state_run_out
    ERROR_VARIABLE state_run_err)
message("${state_run_out}")

if(NOT state_run_rc EQUAL 0)
    message(FATAL_ERROR
        "t_state: the run exited ${state_run_rc}\n${state_run_err}")
endif()

# The program prints `t_state: <N> cases passed`; failing cases make it exit
# non-zero, which the check above already rejects. THE COUNT IS `[1-9][0-9]*`
# AND NOT `[0-9]+`: `[0-9]+` matches `0`, so a test program reduced to its
# banner alone would exit 0, run no case and PASS.
if(NOT state_run_out MATCHES "t_state: [1-9][0-9]* cases passed")
    message(FATAL_ERROR
        "t_state: the run exited 0 but did not report a full pass.\n"
        "  stdout : ${state_run_out}\n  stderr : ${state_run_err}")
endif()

# THE VANISHED-CASE CHECK. The anchor above stays beside it rather than being
# replaced by it: the two fail on differently-shaped defects, and the anchor is
# the cheaper of the two. `tests/case_sites.cmake` states the rules.
include("@MCF5307_CASE_SITES_MODULE@")
mcf5307_check_case_sites("t_state" "@MCF5307_STATE_SOURCE@" "${state_run_out}"
    0)

# THE CASE TOTAL. The rules the call above applies catch a case that stops
# RUNNING; they cannot see a TABLE THAT GOT SHORTER, because a site inside a
# loop is one site however many rows the loop carries. `tests/case_sites.cmake`
# states at `mcf5307_check_case_total` why a TYPED figure is accepted here and
# what it still does not reach. MOVE IT ONLY WITH A DELIBERATE CHANGE IN THE
# CASE COUNT.
#
# THIS SUITE'S TOTAL MOVES WITH THE NUMBER OF SERIALISED CONTEXT FIELDS, which
# is a property the other suites' totals do not have. Its per-field round-trip
# and per-byte-position blocks iterate the state block itself, so a field added
# to `MCF5307Ctx` moves this figure. That coupling is the point: a field that
# enters the snapshot without anyone deciding it should is what this figure
# refuses to let pass quietly.
mcf5307_check_case_total("t_state" "${state_run_out}" 33)

]==])

string(CONFIGURE "${MCF5307_STATE_DRIVER_TEMPLATE}" MCF5307_STATE_DRIVER @ONLY)
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/t_state_driver.cmake"
    "${MCF5307_STATE_DRIVER}")

add_test(NAME t_state
    COMMAND "${CMAKE_COMMAND}"
        -P "${CMAKE_CURRENT_BINARY_DIR}/t_state_driver.cmake")


# -------------------------------------------------------------------- CPU-21
# `t_isp1181_stub` - the CS3 stub of the ISP1181 USB device controller.
#
# ONE REGISTERED NAME, AND NO CORPUS BESIDE IT. The corpus runner executes
# ASSEMBLED encodings, and a device model answers a bus access rather than an
# instruction, so there is no encoding to assemble.
#
# THE FLAG SET IS THE LIBRARY'S OWN, taken from the compile command this
# configure built for the library itself, so that the module this test asserts
# about is built the way the library builds it. The tail anchor is
# `[1-9][0-9]*`, which rejects a run of zero cases.

if(NOT DEFINED MCF5307_NIM_COMMAND)
    message(FATAL_ERROR
        "tests: t_isp1181_stub cannot be registered: MCF5307_NIM_COMMAND is "
        "not set. The test takes its flag set from the library's own compile "
        "command, and a test registered against an empty command would compile "
        "with no flags at all and assert nothing.")
endif()

set(MCF5307_ISP1181_STUB_COMMAND "")
foreach(argument IN LISTS MCF5307_NIM_COMMAND)
    if(argument STREQUAL "--compileOnly"
            OR argument STREQUAL "--noMain"
            OR argument MATCHES "^--nimcache:"
            OR argument MATCHES "^--header:"
            OR argument MATCHES "^--nimMainPrefix:"
            OR argument MATCHES "^--path:"
            OR argument MATCHES "\\.nim$")
        continue()
    endif()
    list(APPEND MCF5307_ISP1181_STUB_COMMAND "${argument}")
endforeach()
list(APPEND MCF5307_ISP1181_STUB_COMMAND "--path:${PROJECT_SOURCE_DIR}/src")

set(NIM_ISP1181_STUB_COMMAND_LITERAL "")
foreach(argument IN LISTS MCF5307_ISP1181_STUB_COMMAND)
    string(APPEND NIM_ISP1181_STUB_COMMAND_LITERAL "    \"${argument}\"\n")
endforeach()

set(MCF5307_ISP1181_STUB_SOURCE
    "${CMAKE_CURRENT_LIST_DIR}/t_isp1181_stub.nim")
set(MCF5307_ISP1181_STUB_BINARY
    "${CMAKE_CURRENT_BINARY_DIR}/t_isp1181_stub_program")
set(MCF5307_ISP1181_STUB_NIMCACHE
    "${CMAKE_CURRENT_BINARY_DIR}/t_isp1181_stub_nimcache")

set(MCF5307_ISP1181_STUB_DRIVER_TEMPLATE [==[
# GENERATED BY tests/tests_cpu.cmake. Do not edit this copy in the build tree.
#
# The driver of the registered test `t_isp1181_stub`. It compiles the Nim test
# program with THE LIBRARY'S OWN FLAG SET, runs it, and fails when the run exits
# non-zero or does not report a full pass.

set(nim_command
@NIM_ISP1181_STUB_COMMAND_LITERAL@)
set(source "@MCF5307_ISP1181_STUB_SOURCE@")
set(binary "@MCF5307_ISP1181_STUB_BINARY@")
set(nimcache "@MCF5307_ISP1181_STUB_NIMCACHE@")

# The binary of an earlier run is REMOVED BEFORE THE COMPILE. Without this a
# compile that failed would leave the earlier binary in place, and the run
# would then execute code this run never produced.
file(REMOVE "${binary}")

execute_process(
    COMMAND ${nim_command} "--nimcache:${nimcache}" "-o:${binary}" "${source}"
    RESULT_VARIABLE isp_stub_compile_rc
    OUTPUT_VARIABLE isp_stub_compile_out
    ERROR_VARIABLE isp_stub_compile_err)

if(NOT isp_stub_compile_rc EQUAL 0)
    message(FATAL_ERROR
        "t_isp1181_stub: the Nim test program did not compile "
        "(result: ${isp_stub_compile_rc})\n"
        "${isp_stub_compile_out}\n${isp_stub_compile_err}")
endif()

execute_process(
    COMMAND "${binary}"
    RESULT_VARIABLE isp_stub_run_rc
    OUTPUT_VARIABLE isp_stub_run_out
    ERROR_VARIABLE isp_stub_run_err)
message("${isp_stub_run_out}")

# A NIL DEREFERENCE INSIDE THE MODEL ARRIVES HERE AND NOT AS A FAILED CASE.
# The suite drives the entry points with a nil handle, which design section 5.6
# forbids the model to abort on, and a model that aborts kills the program
# before it can report anything at all.
if(NOT isp_stub_run_rc EQUAL 0)
    message(FATAL_ERROR
        "t_isp1181_stub: the run exited ${isp_stub_run_rc}\n"
        "${isp_stub_run_err}")
endif()

# The program prints `t_isp1181_stub: <N> cases passed`; failing cases make it
# exit non-zero, which the check above already rejects. THE COUNT IS
# `[1-9][0-9]*` AND NOT `[0-9]+`: `[0-9]+` matches `0`, so a test program
# reduced to its banner alone would exit 0, run no case and PASS.
if(NOT isp_stub_run_out MATCHES "t_isp1181_stub: [1-9][0-9]* cases passed")
    message(FATAL_ERROR
        "t_isp1181_stub: the run exited 0 but did not report a full pass.\n"
        "  stdout : ${isp_stub_run_out}\n  stderr : ${isp_stub_run_err}")
endif()

# THE VANISHED-CASE CHECK. The anchor above stays beside it rather than being
# replaced by it: the two fail on differently-shaped defects, and the anchor is
# the cheaper of the two. `tests/case_sites.cmake` states the rules.
include("@MCF5307_CASE_SITES_MODULE@")
mcf5307_check_case_sites("t_isp1181_stub" "@MCF5307_ISP1181_STUB_SOURCE@"
    "${isp_stub_run_out}" 0)

# THE CASE TOTAL. The rules the call above applies catch a case that stops
# RUNNING; they cannot see a TABLE THAT GOT SHORTER, because a site inside a
# loop is one site however many rows the loop carries. `tests/case_sites.cmake`
# states at `mcf5307_check_case_total` why a TYPED figure is accepted here and
# what it still does not reach. MOVE IT ONLY WITH A DELIBERATE CHANGE IN THE
# CASE COUNT.
#
# EVERY SWEEP IN THIS SUITE AGGREGATES INTO ONE CASE rather than asserting per
# iteration, so this figure counts properties and not addresses. A sweep that
# stopped iterating is caught by the iteration count inside the case's own
# expected value, which is why the two guards do not overlap here.
mcf5307_check_case_total("t_isp1181_stub" "${isp_stub_run_out}" 23)

]==])

string(CONFIGURE "${MCF5307_ISP1181_STUB_DRIVER_TEMPLATE}"
    MCF5307_ISP1181_STUB_DRIVER @ONLY)
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/t_isp1181_stub_driver.cmake"
    "${MCF5307_ISP1181_STUB_DRIVER}")

add_test(NAME t_isp1181_stub
    COMMAND "${CMAKE_COMMAND}"
        -P "${CMAKE_CURRENT_BINARY_DIR}/t_isp1181_stub_driver.cmake")


# -------------------------------------------------------------------- CPU-22
# `t_isp1181_command_set` - the command set of the full ISP1181 model.
#
# ONE REGISTERED NAME, AND NO CORPUS BESIDE IT, for the reason CPU-21's block
# above gives: the corpus runner executes assembled encodings and a device
# model answers a bus access rather than an instruction.
#
# THE FLAG SET IS THE LIBRARY'S OWN, taken from the compile command this
# configure built for the library itself, so that the modules this test asserts
# about are built the way the library builds them.

if(NOT DEFINED MCF5307_NIM_COMMAND)
    message(FATAL_ERROR
        "tests: t_isp1181_command_set cannot be registered: "
        "MCF5307_NIM_COMMAND is not set. The test takes its flag set from the "
        "library's own compile command, and a test registered against an empty "
        "command would compile with no flags at all and assert nothing.")
endif()

set(MCF5307_ISP1181_CMD_COMMAND "")
foreach(argument IN LISTS MCF5307_NIM_COMMAND)
    if(argument STREQUAL "--compileOnly"
            OR argument STREQUAL "--noMain"
            OR argument MATCHES "^--nimcache:"
            OR argument MATCHES "^--header:"
            OR argument MATCHES "^--nimMainPrefix:"
            OR argument MATCHES "^--path:"
            OR argument MATCHES "\\.nim$")
        continue()
    endif()
    list(APPEND MCF5307_ISP1181_CMD_COMMAND "${argument}")
endforeach()
list(APPEND MCF5307_ISP1181_CMD_COMMAND "--path:${PROJECT_SOURCE_DIR}/src")

set(NIM_ISP1181_CMD_COMMAND_LITERAL "")
foreach(argument IN LISTS MCF5307_ISP1181_CMD_COMMAND)
    string(APPEND NIM_ISP1181_CMD_COMMAND_LITERAL "    \"${argument}\"\n")
endforeach()

set(MCF5307_ISP1181_CMD_SOURCE
    "${CMAKE_CURRENT_LIST_DIR}/t_isp1181_command_set.nim")
set(MCF5307_ISP1181_CMD_BINARY
    "${CMAKE_CURRENT_BINARY_DIR}/t_isp1181_command_set_program")
set(MCF5307_ISP1181_CMD_NIMCACHE
    "${CMAKE_CURRENT_BINARY_DIR}/t_isp1181_command_set_nimcache")

set(MCF5307_ISP1181_CMD_DRIVER_TEMPLATE [==[
# GENERATED BY tests/tests_cpu.cmake. Do not edit this copy in the build tree.
#
# The driver of the registered test `t_isp1181_command_set`. It compiles the
# Nim test program with THE LIBRARY'S OWN FLAG SET, runs it, and fails when the
# run exits non-zero or does not report a full pass.

set(nim_command
@NIM_ISP1181_CMD_COMMAND_LITERAL@)
set(source "@MCF5307_ISP1181_CMD_SOURCE@")
set(binary "@MCF5307_ISP1181_CMD_BINARY@")
set(nimcache "@MCF5307_ISP1181_CMD_NIMCACHE@")

# The binary of an earlier run is REMOVED BEFORE THE COMPILE, so that a failed
# compile cannot leave the earlier binary in place for the run to execute. A
# run of a binary this run did not produce reports a pass about code that no
# longer exists.
file(REMOVE "${binary}")

execute_process(
    COMMAND ${nim_command} "--nimcache:${nimcache}" "-o:${binary}" "${source}"
    RESULT_VARIABLE isp_cmd_compile_rc
    OUTPUT_VARIABLE isp_cmd_compile_out
    ERROR_VARIABLE isp_cmd_compile_err)

if(NOT isp_cmd_compile_rc EQUAL 0)
    message(FATAL_ERROR
        "t_isp1181_command_set: the Nim test program did not compile "
        "(result: ${isp_cmd_compile_rc})\n"
        "${isp_cmd_compile_out}\n${isp_cmd_compile_err}")
endif()

execute_process(
    COMMAND "${binary}"
    RESULT_VARIABLE isp_cmd_run_rc
    OUTPUT_VARIABLE isp_cmd_run_out
    ERROR_VARIABLE isp_cmd_run_err)
message("${isp_cmd_run_out}")

if(NOT isp_cmd_run_rc EQUAL 0)
    message(FATAL_ERROR
        "t_isp1181_command_set: the run exited ${isp_cmd_run_rc}\n"
        "${isp_cmd_run_err}")
endif()

# THE COUNT IS `[1-9][0-9]*` AND NOT `[0-9]+`, for the reason CPU-21's driver
# states: `[0-9]+` matches `0`, so a program reduced to its banner alone would
# exit 0, run no case and PASS.
if(NOT isp_cmd_run_out MATCHES "t_isp1181_command_set: [1-9][0-9]* cases passed")
    message(FATAL_ERROR
        "t_isp1181_command_set: the run exited 0 but did not report a full "
        "pass.\n"
        "  stdout : ${isp_cmd_run_out}\n  stderr : ${isp_cmd_run_err}")
endif()

include("@MCF5307_CASE_SITES_MODULE@")
mcf5307_check_case_sites("t_isp1181_command_set"
    "@MCF5307_ISP1181_CMD_SOURCE@" "${isp_cmd_run_out}" 0)

# THE CASE TOTAL. `tests/case_sites.cmake` states at `mcf5307_check_case_total`
# why a TYPED figure is accepted here and what it still does not reach. MOVE IT
# ONLY WITH A DELIBERATE CHANGE IN THE CASE COUNT.
#
# THE THREE OPCODE SWEEPS AGGREGATE INTO ONE CASE EACH and carry their own
# driven-count inside the expected value, so a sweep that stopped iterating
# fails on that count rather than on this figure. What this figure catches is
# a whole case removed.
mcf5307_check_case_total("t_isp1181_command_set" "${isp_cmd_run_out}" 24)

]==])

string(CONFIGURE "${MCF5307_ISP1181_CMD_DRIVER_TEMPLATE}"
    MCF5307_ISP1181_CMD_DRIVER @ONLY)
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/t_isp1181_command_set_driver.cmake"
    "${MCF5307_ISP1181_CMD_DRIVER}")

add_test(NAME t_isp1181_command_set
    COMMAND "${CMAKE_COMMAND}"
        -P "${CMAKE_CURRENT_BINARY_DIR}/t_isp1181_command_set_driver.cmake")


# -------------------------------------------------------------------- CPU-23
# `t_isp1181` - the ISP1181 model driven by synthetic transactions.
#
# ONE REGISTERED NAME, AND NO CORPUS BESIDE IT, for the reason CPU-21's block
# above gives: the corpus runner executes assembled encodings and a device
# model answers a bus access rather than an instruction.
#
# THE FLAG SET IS THE LIBRARY'S OWN, taken from the compile command this
# configure built for the library itself, so that the modules this test asserts
# about are built the way the library builds them.

if(NOT DEFINED MCF5307_NIM_COMMAND)
    message(FATAL_ERROR
        "tests: t_isp1181 cannot be registered: MCF5307_NIM_COMMAND is not "
        "set. The test takes its flag set from the library's own compile "
        "command, and a test registered against an empty command would "
        "compile with no flags at all and assert nothing.")
endif()

set(MCF5307_ISP1181_MODEL_COMMAND "")
foreach(argument IN LISTS MCF5307_NIM_COMMAND)
    if(argument STREQUAL "--compileOnly"
            OR argument STREQUAL "--noMain"
            OR argument MATCHES "^--nimcache:"
            OR argument MATCHES "^--header:"
            OR argument MATCHES "^--nimMainPrefix:"
            OR argument MATCHES "^--path:"
            OR argument MATCHES "\\.nim$")
        continue()
    endif()
    list(APPEND MCF5307_ISP1181_MODEL_COMMAND "${argument}")
endforeach()
list(APPEND MCF5307_ISP1181_MODEL_COMMAND "--path:${PROJECT_SOURCE_DIR}/src")

set(NIM_ISP1181_MODEL_COMMAND_LITERAL "")
foreach(argument IN LISTS MCF5307_ISP1181_MODEL_COMMAND)
    string(APPEND NIM_ISP1181_MODEL_COMMAND_LITERAL "    \"${argument}\"\n")
endforeach()

set(MCF5307_ISP1181_MODEL_SOURCE
    "${CMAKE_CURRENT_LIST_DIR}/t_isp1181.nim")
set(MCF5307_ISP1181_MODEL_BINARY
    "${CMAKE_CURRENT_BINARY_DIR}/t_isp1181_program")
set(MCF5307_ISP1181_MODEL_NIMCACHE
    "${CMAKE_CURRENT_BINARY_DIR}/t_isp1181_nimcache")

set(MCF5307_ISP1181_MODEL_DRIVER_TEMPLATE [==[
# GENERATED BY tests/tests_cpu.cmake. Do not edit this copy in the build tree.
#
# The driver of the registered test `t_isp1181`. It compiles the Nim test
# program with THE LIBRARY'S OWN FLAG SET, runs it, and fails when the run
# exits non-zero or does not report a full pass.

set(nim_command
@NIM_ISP1181_MODEL_COMMAND_LITERAL@)
set(source "@MCF5307_ISP1181_MODEL_SOURCE@")
set(binary "@MCF5307_ISP1181_MODEL_BINARY@")
set(nimcache "@MCF5307_ISP1181_MODEL_NIMCACHE@")

# The binary of an earlier run is REMOVED BEFORE THE COMPILE, so that a failed
# compile cannot leave the earlier binary in place for the run to execute. A
# run of a binary this run did not produce reports a pass about code that no
# longer exists.
file(REMOVE "${binary}")

execute_process(
    COMMAND ${nim_command} "--nimcache:${nimcache}" "-o:${binary}" "${source}"
    RESULT_VARIABLE isp_model_compile_rc
    OUTPUT_VARIABLE isp_model_compile_out
    ERROR_VARIABLE isp_model_compile_err)

if(NOT isp_model_compile_rc EQUAL 0)
    message(FATAL_ERROR
        "t_isp1181: the Nim test program did not compile "
        "(result: ${isp_model_compile_rc})\n"
        "${isp_model_compile_out}\n${isp_model_compile_err}")
endif()

execute_process(
    COMMAND "${binary}"
    RESULT_VARIABLE isp_model_run_rc
    OUTPUT_VARIABLE isp_model_run_out
    ERROR_VARIABLE isp_model_run_err)
message("${isp_model_run_out}")

if(NOT isp_model_run_rc EQUAL 0)
    message(FATAL_ERROR
        "t_isp1181: the run exited ${isp_model_run_rc}\n"
        "${isp_model_run_err}")
endif()

# THE COUNT IS `[1-9][0-9]*` AND NOT `[0-9]+`, for the reason CPU-21's driver
# states: `[0-9]+` matches `0`, so a program reduced to its banner alone would
# exit 0, run no case and PASS.
if(NOT isp_model_run_out MATCHES "t_isp1181: [1-9][0-9]* cases passed")
    message(FATAL_ERROR
        "t_isp1181: the run exited 0 but did not report a full pass.\n"
        "  stdout : ${isp_model_run_out}\n  stderr : ${isp_model_run_err}")
endif()

include("@MCF5307_CASE_SITES_MODULE@")
mcf5307_check_case_sites("t_isp1181"
    "@MCF5307_ISP1181_MODEL_SOURCE@" "${isp_model_run_out}" 0)

# THE CASE TOTAL. `tests/case_sites.cmake` states at `mcf5307_check_case_total`
# why a TYPED figure is accepted here and what it still does not reach. MOVE IT
# ONLY WITH A DELIBERATE CHANGE IN THE CASE COUNT.
#
# THE SWEEP OVER THE COMMAND BYTE AGGREGATES INTO ONE CASE and carries its own
# driven-count inside the expected value, so a sweep that stopped iterating
# fails on that count rather than on this figure. What this figure catches is
# a whole case removed.
mcf5307_check_case_total("t_isp1181" "${isp_model_run_out}" 16)

]==])

string(CONFIGURE "${MCF5307_ISP1181_MODEL_DRIVER_TEMPLATE}"
    MCF5307_ISP1181_MODEL_DRIVER @ONLY)
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/t_isp1181_driver.cmake"
    "${MCF5307_ISP1181_MODEL_DRIVER}")

add_test(NAME t_isp1181
    COMMAND "${CMAKE_COMMAND}"
        -P "${CMAKE_CURRENT_BINARY_DIR}/t_isp1181_driver.cmake")


# -------------------------------------------------------------------- CPU-24
# `t_isp1181_state` - the SOF tick and the ISP1181 state block.
#
# ONE REGISTERED NAME, AND NO CORPUS BESIDE IT, for the reason CPU-21's block
# above gives: a device model answers a bus access rather than an instruction,
# so there is no encoding to assemble.
#
# THE FLAG SET IS THE LIBRARY'S OWN, taken from the compile command this
# configure built for the library itself.

if(NOT DEFINED MCF5307_NIM_COMMAND)
    message(FATAL_ERROR
        "tests: t_isp1181_state cannot be registered: MCF5307_NIM_COMMAND is "
        "not set. The test takes its flag set from the library's own compile "
        "command, and a test registered against an empty command would compile "
        "with no flags at all and assert nothing.")
endif()

set(MCF5307_ISP1181_STATE_COMMAND "")
foreach(argument IN LISTS MCF5307_NIM_COMMAND)
    if(argument STREQUAL "--compileOnly"
            OR argument STREQUAL "--noMain"
            OR argument MATCHES "^--nimcache:"
            OR argument MATCHES "^--header:"
            OR argument MATCHES "^--nimMainPrefix:"
            OR argument MATCHES "^--path:"
            OR argument MATCHES "\\.nim$")
        continue()
    endif()
    list(APPEND MCF5307_ISP1181_STATE_COMMAND "${argument}")
endforeach()
list(APPEND MCF5307_ISP1181_STATE_COMMAND "--path:${PROJECT_SOURCE_DIR}/src")

set(NIM_ISP1181_STATE_COMMAND_LITERAL "")
foreach(argument IN LISTS MCF5307_ISP1181_STATE_COMMAND)
    string(APPEND NIM_ISP1181_STATE_COMMAND_LITERAL "    \"${argument}\"\n")
endforeach()

set(MCF5307_ISP1181_STATE_SOURCE
    "${CMAKE_CURRENT_LIST_DIR}/t_isp1181_state.nim")
set(MCF5307_ISP1181_STATE_BINARY
    "${CMAKE_CURRENT_BINARY_DIR}/t_isp1181_state_program")
set(MCF5307_ISP1181_STATE_NIMCACHE
    "${CMAKE_CURRENT_BINARY_DIR}/t_isp1181_state_nimcache")

set(MCF5307_ISP1181_STATE_DRIVER_TEMPLATE [==[
# GENERATED BY tests/tests_cpu.cmake. Do not edit this copy in the build tree.
#
# The driver of the registered test `t_isp1181_state`. It compiles the Nim test
# program with THE LIBRARY'S OWN FLAG SET, runs it, and fails when the run exits
# non-zero or does not report a full pass.

set(nim_command
@NIM_ISP1181_STATE_COMMAND_LITERAL@)
set(source "@MCF5307_ISP1181_STATE_SOURCE@")
set(binary "@MCF5307_ISP1181_STATE_BINARY@")
set(nimcache "@MCF5307_ISP1181_STATE_NIMCACHE@")

# The binary of an earlier run is REMOVED BEFORE THE COMPILE. Without this a
# compile that failed would leave the earlier binary in place, and the run would
# then execute code this run never produced.
file(REMOVE "${binary}")

execute_process(
    COMMAND ${nim_command} "--nimcache:${nimcache}" "-o:${binary}" "${source}"
    RESULT_VARIABLE isp_state_compile_rc
    OUTPUT_VARIABLE isp_state_compile_out
    ERROR_VARIABLE isp_state_compile_err)

if(NOT isp_state_compile_rc EQUAL 0)
    message(FATAL_ERROR
        "t_isp1181_state: the Nim test program did not compile "
        "(result: ${isp_state_compile_rc})\n"
        "${isp_state_compile_out}\n${isp_state_compile_err}")
endif()

execute_process(
    COMMAND "${binary}"
    RESULT_VARIABLE isp_state_run_rc
    OUTPUT_VARIABLE isp_state_run_out
    ERROR_VARIABLE isp_state_run_err)
message("${isp_state_run_out}")

# A NIL DEREFERENCE INSIDE THE MODEL ARRIVES HERE AND NOT AS A FAILED CASE. The
# suite drives the entry points with a nil handle, which design section 5.6
# forbids the model to abort on, and a model that aborts kills the program
# before it can report anything at all.
if(NOT isp_state_run_rc EQUAL 0)
    message(FATAL_ERROR
        "t_isp1181_state: the run exited ${isp_state_run_rc}\n"
        "${isp_state_run_err}")
endif()

# THE COUNT IS `[1-9][0-9]*` AND NOT `[0-9]+`: `[0-9]+` matches `0`, so a test
# program reduced to its banner alone would exit 0, run no case and PASS.
if(NOT isp_state_run_out MATCHES "t_isp1181_state: [1-9][0-9]* cases passed")
    message(FATAL_ERROR
        "t_isp1181_state: the run exited 0 but did not report a full pass.\n"
        "  stdout : ${isp_state_run_out}\n  stderr : ${isp_state_run_err}")
endif()

# THE VANISHED-CASE CHECK. `tests/case_sites.cmake` states the rules.
include("@MCF5307_CASE_SITES_MODULE@")
mcf5307_check_case_sites("t_isp1181_state" "@MCF5307_ISP1181_STATE_SOURCE@"
    "${isp_state_run_out}" 0)

# THE CASE TOTAL. The rules the call above applies catch a case that stops
# RUNNING; they cannot see a TABLE THAT GOT SHORTER, because a site inside a
# loop is one site however many rows the loop carries. MOVE IT ONLY WITH A
# DELIBERATE CHANGE IN THE CASE COUNT.
#
# EVERY SWEEP IN THIS SUITE AGGREGATES INTO ONE CASE and carries its own
# iteration count inside its expected value, so a sweep that stopped iterating
# fails on that count rather than on this figure.
mcf5307_check_case_total("t_isp1181_state" "${isp_state_run_out}" 15)

]==])

string(CONFIGURE "${MCF5307_ISP1181_STATE_DRIVER_TEMPLATE}"
    MCF5307_ISP1181_STATE_DRIVER @ONLY)
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/t_isp1181_state_driver.cmake"
    "${MCF5307_ISP1181_STATE_DRIVER}")

add_test(NAME t_isp1181_state
    COMMAND "${CMAKE_COMMAND}"
        -P "${CMAKE_CURRENT_BINARY_DIR}/t_isp1181_state_driver.cmake")


# -------------------------------------------------------------------- CPU-19
# `t_no_alloc` - the core allocates only inside `mcf5307_create`.
#
# THIS IS THE ONE SUITE IN THIS FILE WHOSE FLAG SET IS NOT THE LIBRARY'S ALONE,
# and the addition is stated here rather than left to the reader of the list
# below. `-d:nimAllocStats` is appended after the library's own arguments.
# `system/memalloc.nim` compiles the allocator's two counters only under that
# define; without it `getAllocStats()` compiles, returns an `AllocStats`, and
# returns a DEFAULT one. A suite asserting zero against that build reports a
# pass it never measured.
#
# THE DEFINE ADDS A COUNTER AND CHANGES NOTHING THAT ALLOCATES. It is an
# `atomicInc` inside the allocator's own entry points, so a call that reaches
# the allocator under this define reaches it without one. What the departure
# does cost is that this suite measures a compile the shipped library does not
# make, and that is why the property is stated against a counter rather than
# against a byte figure.
#
# NOTHING HERE SUPPRESSES A RUN-TIME CHECK. The two defines AGENTS.md forbids -
# `--checks:off` and `-d:danger` - are neither added nor implied by this one,
# and the strip loop below removes no check-bearing argument.
#
# THE SUITE'S OWN `mcf5307_create` CASE IS WHAT ENFORCES THIS BLOCK. Drop the
# define and that case reads zero where it requires one, so the departure
# cannot be undone quietly - which is the only reason a departure was
# acceptable at all.
#
# THE COMPILE HAPPENS INSIDE THE TEST AND NOT IN THE BUILD, for the reason the
# blocks above give: a `ctest` run over a tree whose build had failed would
# otherwise run a STALE binary of an earlier build and pass.

if(NOT DEFINED MCF5307_NIM_COMMAND)
    message(FATAL_ERROR
        "tests: t_no_alloc cannot be registered: MCF5307_NIM_COMMAND is not "
        "set. The test takes its flag set from the library's own compile "
        "command, and a test registered against an empty command would compile "
        "with no flags at all and assert nothing.")
endif()

set(MCF5307_NO_ALLOC_COMMAND "")
foreach(argument IN LISTS MCF5307_NIM_COMMAND)
    if(argument STREQUAL "--compileOnly"
            OR argument STREQUAL "--noMain"
            OR argument MATCHES "^--nimcache:"
            OR argument MATCHES "^--header:"
            OR argument MATCHES "^--nimMainPrefix:"
            OR argument MATCHES "^--path:"
            OR argument MATCHES "\\.nim$")
        continue()
    endif()
    list(APPEND MCF5307_NO_ALLOC_COMMAND "${argument}")
endforeach()
list(APPEND MCF5307_NO_ALLOC_COMMAND "--path:${PROJECT_SOURCE_DIR}/src")
list(APPEND MCF5307_NO_ALLOC_COMMAND "-d:nimAllocStats")

set(NIM_NO_ALLOC_COMMAND_LITERAL "")
foreach(argument IN LISTS MCF5307_NO_ALLOC_COMMAND)
    string(APPEND NIM_NO_ALLOC_COMMAND_LITERAL "    \"${argument}\"\n")
endforeach()

set(MCF5307_NO_ALLOC_SOURCE "${CMAKE_CURRENT_LIST_DIR}/t_no_alloc.nim")
set(MCF5307_NO_ALLOC_BINARY "${CMAKE_CURRENT_BINARY_DIR}/t_no_alloc_program")
set(MCF5307_NO_ALLOC_NIMCACHE
    "${CMAKE_CURRENT_BINARY_DIR}/t_no_alloc_nimcache")

set(MCF5307_NO_ALLOC_DRIVER_TEMPLATE [==[
# GENERATED BY tests/tests_cpu.cmake. Do not edit this copy in the build tree.
#
# The driver of the registered test `t_no_alloc`. It compiles the Nim test
# program with the library's flag set plus `-d:nimAllocStats`, runs it, and
# fails when the run exits non-zero or does not report a full pass.

set(nim_command
@NIM_NO_ALLOC_COMMAND_LITERAL@)
set(source "@MCF5307_NO_ALLOC_SOURCE@")
set(binary "@MCF5307_NO_ALLOC_BINARY@")
set(nimcache "@MCF5307_NO_ALLOC_NIMCACHE@")

# The binary of an earlier run is REMOVED BEFORE THE COMPILE. Without this a
# compile that failed would leave the earlier binary in place, and the run
# would then execute code this run never produced.
file(REMOVE "${binary}")

execute_process(
    COMMAND ${nim_command} "--nimcache:${nimcache}" "-o:${binary}" "${source}"
    RESULT_VARIABLE no_alloc_compile_rc
    OUTPUT_VARIABLE no_alloc_compile_out
    ERROR_VARIABLE no_alloc_compile_err)

if(NOT no_alloc_compile_rc EQUAL 0)
    message(FATAL_ERROR
        "t_no_alloc: the Nim test program did not compile "
        "(result: ${no_alloc_compile_rc})\n"
        "${no_alloc_compile_out}\n${no_alloc_compile_err}")
endif()

execute_process(
    COMMAND "${binary}"
    RESULT_VARIABLE no_alloc_run_rc
    OUTPUT_VARIABLE no_alloc_run_out
    ERROR_VARIABLE no_alloc_run_err)
message("${no_alloc_run_out}")

if(NOT no_alloc_run_rc EQUAL 0)
    message(FATAL_ERROR
        "t_no_alloc: the run exited ${no_alloc_run_rc}\n${no_alloc_run_err}")
endif()

# The program prints `t_no_alloc: <N> cases passed`; failing cases make it
# exit non-zero, which the check above already rejects. Anchoring the tail
# here keeps a run that printed the banner but skipped the cases from passing.
# THE `[1-9]` IS WHAT REJECTS A RUN OF ZERO CASES.
if(NOT no_alloc_run_out MATCHES "t_no_alloc: [1-9][0-9]* cases passed")
    message(FATAL_ERROR
        "t_no_alloc: the run exited 0 but did not report a full pass.\n"
        "  stdout : ${no_alloc_run_out}\n  stderr : ${no_alloc_run_err}")
endif()

# THE VANISHED-CASE CHECK. The anchor above stays beside it rather than being
# replaced by it: the two fail on differently-shaped defects, and the anchor is
# the cheaper of the two. `tests/case_sites.cmake` states the rules.
include("@MCF5307_CASE_SITES_MODULE@")
mcf5307_check_case_sites("t_no_alloc" "@MCF5307_NO_ALLOC_SOURCE@"
    "${no_alloc_run_out}" 0)

# THE CASE TOTAL. The rules the call above applies catch a case that stops
# RUNNING; they cannot see a case DELETED from the file, because a deleted call
# site leaves the compiler's registry as well as the text.
# `tests/case_sites.cmake` states at `mcf5307_check_case_total` why a TYPED
# figure is accepted here and what it still does not reach. MOVE IT ONLY WITH A
# DELIBERATE CHANGE IN THE CASE COUNT.
mcf5307_check_case_total("t_no_alloc" "${no_alloc_run_out}" 9)

]==])

string(CONFIGURE "${MCF5307_NO_ALLOC_DRIVER_TEMPLATE}"
    MCF5307_NO_ALLOC_DRIVER @ONLY)
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/t_no_alloc_driver.cmake"
    "${MCF5307_NO_ALLOC_DRIVER}")

add_test(NAME t_no_alloc
    COMMAND "${CMAKE_COMMAND}"
        -P "${CMAKE_CURRENT_BINARY_DIR}/t_no_alloc_driver.cmake")


# `t_bus_size_unit` - the UNIT of the `size` argument of the two board
# callbacks, pinned as a behaviour of the core rather than as a sentence in the
# header.
#
# WHAT IT EXISTS TO CATCH. `include/mcf5307.h` states that `size` is a COUNT OF
# BYTES. A header sentence cannot fail, so this suite is the mechanism that
# can: it installs recording callbacks through the PUBLISHED entry points and
# asserts the values the core actually hands a board.
#
# THE DEFECT IT IS A RESPONSE TO. The unit was never stated, and the core and
# its first real consumer read it differently - the core as a byte count, the
# consumer as a width in bits. Every access was refused and the firmware
# executed no instruction. Both sides were internally consistent and both
# suites were green, because no test had ever let the core drive a real board:
# every board-side test supplied the width by hand.
#
# IT DRIVES THE CALLBACKS A CONSUMER INSTALLS, AND THAT IS THE WHOLE POINT. The
# path is `mcf5307_create`, `mcf5307_reset`, `mcf5307_exec` - the same three
# calls a board makes - so the values asserted are the values that cross the
# ABI. A suite that reached `readMem` directly would assert the core's internal
# spelling and would have stayed green through exactly the defect above.
#
# THE SWEEP IS WHAT MAKES THE SET CLAIM A MEASUREMENT. The named MOVE programs
# show a byte, a word and a longword reaching a board on the read path and on
# the write path; the sweep then runs every one of the 65536 opcode words and
# collects every width any of them presents, so the claim that nothing else
# reaches a board is measured over the whole opcode space and not over the
# encodings someone thought to write. `sizeField` in `src/mcf5307/decode.nim`
# reports the `11` size encoding as 0, so a value that is not a legal width
# exists inside the decoder and the sweep is what establishes that no such
# value reaches a board.
#
# A VACUOUS PASS IS REFUSED. Each sweep set is asserted EQUAL to the byte
# widths, so a run that observed nothing at all reports an empty set and is red.

if(NOT DEFINED MCF5307_NIM_COMMAND)
    message(FATAL_ERROR
        "tests: t_bus_size_unit cannot be registered: MCF5307_NIM_COMMAND is "
        "not set. The test takes its flag set from the library's own compile "
        "command, and a test registered against an empty command would "
        "compile with no flags at all and assert nothing.")
endif()

# The command is the LIBRARY's command with the runtime-only and output
# arguments removed, exactly as `t_sign_extend` does, plus `--path:src` so the
# imports of `mcf5307/*` resolve against the source tree.
set(MCF5307_SIZE_UNIT_COMMAND "")
foreach(argument IN LISTS MCF5307_NIM_COMMAND)
    if(argument STREQUAL "--compileOnly"
            OR argument STREQUAL "--noMain"
            OR argument MATCHES "^--nimcache:"
            OR argument MATCHES "^--header:"
            OR argument MATCHES "^--nimMainPrefix:"
            OR argument MATCHES "^--path:"
            OR argument MATCHES "\\.nim$")
        continue()
    endif()
    list(APPEND MCF5307_SIZE_UNIT_COMMAND "${argument}")
endforeach()
list(APPEND MCF5307_SIZE_UNIT_COMMAND "--path:${PROJECT_SOURCE_DIR}/src")

set(NIM_SIZE_UNIT_COMMAND_LITERAL "")
foreach(argument IN LISTS MCF5307_SIZE_UNIT_COMMAND)
    string(APPEND NIM_SIZE_UNIT_COMMAND_LITERAL "    \"${argument}\"\n")
endforeach()

set(MCF5307_SIZE_UNIT_SOURCE "${CMAKE_CURRENT_LIST_DIR}/t_bus_size_unit.nim")
set(MCF5307_SIZE_UNIT_BINARY
    "${CMAKE_CURRENT_BINARY_DIR}/t_bus_size_unit_program")
set(MCF5307_SIZE_UNIT_NIMCACHE
    "${CMAKE_CURRENT_BINARY_DIR}/t_bus_size_unit_nimcache")

set(MCF5307_SIZE_UNIT_DRIVER_TEMPLATE [==[
# GENERATED BY tests/tests_cpu.cmake. Do not edit this copy in the build tree.
#
# The driver of the registered test `t_bus_size_unit`. It compiles the Nim test
# program with THE LIBRARY'S OWN FLAG SET, runs it, and fails when the run
# exits non-zero or does not report a full pass.

set(nim_command
@NIM_SIZE_UNIT_COMMAND_LITERAL@)
set(source "@MCF5307_SIZE_UNIT_SOURCE@")
set(binary "@MCF5307_SIZE_UNIT_BINARY@")
set(nimcache "@MCF5307_SIZE_UNIT_NIMCACHE@")

# The binary of an earlier run is REMOVED BEFORE THE COMPILE. Without this a
# compile that failed would leave the earlier binary in place, and the run
# would then execute code this run never produced.
file(REMOVE "${binary}")

execute_process(
    COMMAND ${nim_command} "--nimcache:${nimcache}" "-o:${binary}" "${source}"
    RESULT_VARIABLE size_unit_compile_rc
    OUTPUT_VARIABLE size_unit_compile_out
    ERROR_VARIABLE size_unit_compile_err)

if(NOT size_unit_compile_rc EQUAL 0)
    message(FATAL_ERROR
        "t_bus_size_unit: the Nim test program did not compile "
        "(result: ${size_unit_compile_rc})\n"
        "${size_unit_compile_out}\n${size_unit_compile_err}")
endif()

execute_process(
    COMMAND "${binary}"
    RESULT_VARIABLE size_unit_run_rc
    OUTPUT_VARIABLE size_unit_run_out
    ERROR_VARIABLE size_unit_run_err)
message("${size_unit_run_out}")

if(NOT size_unit_run_rc EQUAL 0)
    message(FATAL_ERROR
        "t_bus_size_unit: the run exited ${size_unit_run_rc}\n"
        "${size_unit_run_err}")
endif()

# The program prints `t_bus_size_unit: <N> cases passed`; failing cases make it
# exit non-zero, which the check above already rejects. Anchoring the tail here
# keeps a run that printed the banner but skipped the cases from passing.
# THE `[1-9]` IS WHAT REJECTS A RUN OF ZERO CASES.
if(NOT size_unit_run_out MATCHES "t_bus_size_unit: [1-9][0-9]* cases passed")
    message(FATAL_ERROR
        "t_bus_size_unit: the run exited 0 but did not report a full pass.\n"
        "  stdout : ${size_unit_run_out}\n  stderr : ${size_unit_run_err}")
endif()

# THE VANISHED-CASE CHECK. The anchor above stays beside it rather than being
# replaced by it: the two fail on differently-shaped defects, and the anchor is
# the cheaper of the two. `tests/case_sites.cmake` states the rules.
include("@MCF5307_CASE_SITES_MODULE@")
mcf5307_check_case_sites("t_bus_size_unit" "@MCF5307_SIZE_UNIT_SOURCE@"
    "${size_unit_run_out}" 0)

# THE CASE TOTAL. The rules the call above applies catch a case that stops
# RUNNING; they cannot see a TABLE THAT GOT SHORTER, because a site inside a
# loop is one site however many rows the loop carries - and the sweep in this
# suite is exactly such a loop. `tests/case_sites.cmake` states at
# `mcf5307_check_case_total` why a TYPED figure is accepted here and what it
# still does not reach. MOVE IT ONLY WITH A DELIBERATE CHANGE IN THE CASE
# COUNT.
mcf5307_check_case_total("t_bus_size_unit" "${size_unit_run_out}" 8)

]==])

string(CONFIGURE "${MCF5307_SIZE_UNIT_DRIVER_TEMPLATE}"
    MCF5307_SIZE_UNIT_DRIVER @ONLY)
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/t_bus_size_unit_driver.cmake"
    "${MCF5307_SIZE_UNIT_DRIVER}")

add_test(NAME t_bus_size_unit
    COMMAND "${CMAKE_COMMAND}"
        -P "${CMAKE_CURRENT_BINARY_DIR}/t_bus_size_unit_driver.cmake")


# ------------------------------------------- THE CHECK ON THE VANISHED-CASE
# CHECK ITSELF. Nothing above pins HOW MANY drivers carry
# `mcf5307_check_case_sites`, so the mechanism that refuses to let a case
# vanish in silence could itself vanish in silence.
#
# MEASURED 2026-08-13 by the gate-4.4 judge: deleting the
# `mcf5307_check_case_sites("t_irq" ...)` line from the `t_irq` driver template
# above left `cmake` configuring cleanly and `ctest -R ^t_irq$` reporting
# `Passed`, WITH NO COMPLAINT ANYWHERE. The rule that a count must be derived
# rather than typed was applied to every suite's cases and to none of the
# suites' checks.
#
# SO THE SET IS DERIVED FROM BOTH ENDS AND THE TWO ENDS ARE COMPARED, which is
# the discipline `case_sites.cmake` rule 2 already applies to call sites:
#
#   A. THE SUITES THAT CARRY THE RUN-TIME HALF. A suite participates by
#      importing `tests/case_sites.nim`; the import is what gives it
#      `declaredSites`, `executedSites` and `caseSiteLine`, and a suite that
#      drops the import does not compile, because it uses all three.
#   B. THE SUITES THE GENERATED DRIVERS ACTUALLY CHECK, read out of the driver
#      files THIS CONFIGURE JUST WROTE - the artifact that runs, not the
#      template it was written from.
#
# NEITHER SIDE SPELLS A NUMBER, so a suite added to this file updates both at
# once and there is nothing to maintain.
#
# IT RUNS AT CONFIGURE TIME AND IS NOT A REGISTERED TEST, deliberately. A check
# on whether the tests are wired up must not be a test that a selection filter
# can leave out - which is the defect REPO-6 recorded when CI selected three of
# eleven T0 tests and could not see a suite vanish. A configure that fails here
# builds nothing at all.
#
# WHAT IT DOES NOT REACH, STATED SO ITS SILENCE IS NOT READ AS COVERAGE. Both
# sides fall together under ONE change: deleting a suite's `import
# ./case_sites` AND its driver's check line in the same edit removes the suite
# from side A and from side B, and this comparison stays green. That is the
# same shape as `case_sites.cmake` rule 2's own residual - a call site deleted
# from the text is deleted from the compiler's registry too - and it is not
# closeable by comparing these two sides harder. What it does catch is either
# half deleted on its own, which is what was measured.
#
# A STALE BUILD TREE REPORTS HERE. Side B globs the generated drivers, so a
# driver left behind by a deleted suite is an extra name and is red. The repair
# is a clean configure and never a relaxation of this check.
# THIS BLOCK READS THE SUITE FILES AT CONFIGURE TIME, SO THE CONFIGURE HAS TO
# RE-RUN WHEN THEY MOVE. Until 2026-08-17 it did not, and the check above was
# the one thing a suite edit could not reach: a configure hard-fails on an
# unregistered suite, and the trigger for that failure is the `import
# ./case_sites` line this loop reads - so the ONE mechanism that catches an
# unregistered suite was exactly the mechanism a suite edit failed to re-run.
# MEASURED 2026-08-17 against `CMakeFiles/Makefile.cmake`: CMake recorded 30
# source-tree configure dependencies and `t_*.nim` matched none of them, so
# adding a suite and building reported success while this comparison spoke
# about the previous configure's set of files.
#
# IT TAKES BOTH LINES, AND THE SECOND IS NOT REDUNDANT. They answer two
# different edits and neither answers the other:
#
#   `CONFIGURE_DEPENDS` re-globs at build time and re-runs the configure when
#   the SET OF MATCHED FILES changes - a suite added, deleted or renamed.
#   MEASURED: with this word alone, adding an unregistered `t_*.nim` turned an
#   ordinary `cmake --build` red.
#
#   The directory property registers each matched file INDIVIDUALLY, which is
#   what answers an edit INSIDE a file that already matched. Side A's
#   membership turns on one line of text, so a suite can join or leave it with
#   the glob's result set unchanged. MEASURED, with `CONFIGURE_DEPENDS` alone
#   and no property: appending `import ./case_sites` to an existing suite that
#   did not carry it left `cmake --build` at exit 0, while a forced configure
#   on the same tree failed. THE GLOB WORD DOES NOT WATCH CONTENT.
#
# This is the pairing `cmake/Nim.cmake` already applies to `src/*.nim` for the
# same reason, and the shape is the general one: a value read at configure time
# is stale unless the file it was read from is a configure dependency.
file(GLOB MCF5307_SUITE_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_LIST_DIR}/t_*.nim")
set_property(DIRECTORY "${PROJECT_SOURCE_DIR}"
    APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${MCF5307_SUITE_SOURCES})
set(MCF5307_SUITES_WITH_RUNTIME_HALF "")
foreach(mcf5307_suite_source IN LISTS MCF5307_SUITE_SOURCES)
    file(READ "${mcf5307_suite_source}" mcf5307_suite_text)
    # THE IMPORT IS ANCHORED AT THE START OF A LINE so that the many `##`
    # comments naming `tests/case_sites.nim` are not read as imports.
    if(mcf5307_suite_text MATCHES "(^|\n)import[ \t]+\\./case_sites")
        get_filename_component(mcf5307_suite_name "${mcf5307_suite_source}"
            NAME_WE)
        list(APPEND MCF5307_SUITES_WITH_RUNTIME_HALF "${mcf5307_suite_name}")
    endif()
endforeach()

file(GLOB MCF5307_GENERATED_DRIVERS
    "${CMAKE_CURRENT_BINARY_DIR}/t_*_driver.cmake")
#
# BOTH DRIVER-SIDE CHECKS ARE REQUIRED OF EVERY DRIVER, not just the older one.
# `mcf5307_check_case_total` is exactly as deletable as
# `mcf5307_check_case_sites` was, and exempting it here would rebuild the hole
# this block exists to close one function further along. A driver missing
# EITHER call leaves its suite out of the set below.
set(MCF5307_SUITES_CHECKED_BY_A_DRIVER "")
foreach(mcf5307_driver IN LISTS MCF5307_GENERATED_DRIVERS)
    get_filename_component(mcf5307_driver_name "${mcf5307_driver}" NAME)
    string(REGEX REPLACE "_driver\\.cmake$" "" mcf5307_driver_suite
        "${mcf5307_driver_name}")
    file(READ "${mcf5307_driver}" mcf5307_driver_text)
    set(mcf5307_driver_checked "")
    foreach(mcf5307_required_call IN ITEMS mcf5307_check_case_sites
            mcf5307_check_case_total)
        string(REGEX MATCHALL "${mcf5307_required_call}\\(\"[A-Za-z0-9_]+\""
            mcf5307_driver_hits "${mcf5307_driver_text}")
        set(mcf5307_call_names "")
        foreach(mcf5307_hit IN LISTS mcf5307_driver_hits)
            string(REGEX REPLACE "^.*\\(\"([A-Za-z0-9_]+)\"$" "\\1"
                mcf5307_hit_suite "${mcf5307_hit}")
            # A DRIVER MAY ONLY CHECK ITS OWN SUITE. Without this a single
            # driver naming every suite would satisfy the comparison
            # below while seven runs went unexamined.
            if(NOT mcf5307_hit_suite STREQUAL mcf5307_driver_suite)
                message(FATAL_ERROR
                    "tests: the generated driver ${mcf5307_driver_name} calls "
                    "${mcf5307_required_call} for `${mcf5307_hit_suite}`, "
                    "which is not the suite it runs. A driver checks the "
                    "output of its OWN run and has no other run to check.")
            endif()
            list(APPEND mcf5307_call_names "${mcf5307_hit_suite}")
        endforeach()
        if(NOT mcf5307_call_names STREQUAL "")
            list(APPEND mcf5307_driver_checked "${mcf5307_required_call}")
        endif()
    endforeach()
    # THE CASE TOTAL THE DRIVER RECORDS, read out of the GENERATED file rather
    # than out of the template it was written from, for the reason side B above
    # gives: the artifact that runs is the one whose figure the second-source
    # comparison below has to be about.
    if(mcf5307_driver_text MATCHES
            "mcf5307_check_case_total\\(\"${mcf5307_driver_suite}\"[^\n]*[^0-9]([0-9]+)\\)")
        set(MCF5307_CASE_TOTAL_${mcf5307_driver_suite} "${CMAKE_MATCH_1}")
    endif()
    list(LENGTH mcf5307_driver_checked mcf5307_driver_checked_count)
    if(mcf5307_driver_checked_count EQUAL 2)
        list(APPEND MCF5307_SUITES_CHECKED_BY_A_DRIVER
            "${mcf5307_driver_suite}")
    elseif(mcf5307_driver_checked_count EQUAL 1)
        string(REPLACE ";" " " mcf5307_driver_checked_text
            "${mcf5307_driver_checked}")
        message(FATAL_ERROR
            "tests: the generated driver ${mcf5307_driver_name} calls "
            "${mcf5307_driver_checked_text} and not the other of the two "
            "driver-side checks. `mcf5307_check_case_sites` fails on a case "
            "that stopped running and `mcf5307_check_case_total` fails on a "
            "table that got shorter; they are not two strengths of one check "
            "and a suite carrying one of them is unguarded against the other "
            "shape.")
    endif()
endforeach()

list(REMOVE_DUPLICATES MCF5307_SUITES_WITH_RUNTIME_HALF)
list(REMOVE_DUPLICATES MCF5307_SUITES_CHECKED_BY_A_DRIVER)
list(SORT MCF5307_SUITES_WITH_RUNTIME_HALF)
list(SORT MCF5307_SUITES_CHECKED_BY_A_DRIVER)
list(LENGTH MCF5307_SUITES_WITH_RUNTIME_HALF MCF5307_RUNTIME_HALF_COUNT)
list(LENGTH MCF5307_SUITES_CHECKED_BY_A_DRIVER MCF5307_DRIVER_CHECK_COUNT)

if(NOT MCF5307_SUITES_WITH_RUNTIME_HALF STREQUAL
        MCF5307_SUITES_CHECKED_BY_A_DRIVER)
    string(REPLACE ";" " " MCF5307_RUNTIME_HALF_TEXT
        "${MCF5307_SUITES_WITH_RUNTIME_HALF}")
    string(REPLACE ";" " " MCF5307_DRIVER_CHECK_TEXT
        "${MCF5307_SUITES_CHECKED_BY_A_DRIVER}")
    message(FATAL_ERROR
        "tests: ${MCF5307_RUNTIME_HALF_COUNT} suite(s) import "
        "`tests/case_sites.nim` and carry the run-time half of the "
        "vanished-case check:\n  ${MCF5307_RUNTIME_HALF_TEXT}\n"
        "but ${MCF5307_DRIVER_CHECK_COUNT} generated driver(s) call "
        "`mcf5307_check_case_sites`:\n  ${MCF5307_DRIVER_CHECK_TEXT}\n"
        "A SUITE WHOSE DRIVER DOES NOT CALL IT REPORTS ITS OWN REGISTRIES AND "
        "NOBODY READS THEM: it passes with its cases gone, which is exactly "
        "the silence `tests/case_sites.cmake` exists to end. The two sides "
        "here are derived - one from the suites' own imports, one from the "
        "driver files this configure just wrote - and NEITHER may be brought "
        "into agreement by deleting the import.")
endif()
message(STATUS
    "mcf5307: the vanished-case check is wired into all "
    "${MCF5307_DRIVER_CHECK_COUNT} suite(s) that carry its run-time half")


# ----------------------------------- THE SECOND SOURCE FOR A TYPED CASE TOTAL.
# `tests/case_sites.cmake` accepts ONE TYPED figure per suite because a table
# that gets shorter fails no derived check. The round-2 audit of gate 4.4 then
# asked what stops an author who meets that red from editing the figure instead
# of restoring the cases, and until this block the answer was NOTHING.
#
# THE ARGUMENT THAT NO SECOND SOURCE EXISTED WAS WRONG, AND THE FILE THAT MADE
# IT NAMED THE SOURCE ELSEWHERE IN ITSELF. `src/` carries dated transcripts of
# runs of these suites, quoted inside the comments that record cycle-mutation
# and mask-mutation measurements, and a transcript naming a suite and a case
# count is a figure the driver's number can be held against. It is not derived
# from the RUN - both sides are written down - but they are written down in
# different files, by different tasks, for different reasons, and one of them is
# production source that a test may not edit. An author moving one to silence a
# red has to move the other in the same change, and the other is not a test.
#
# BOTH ENDS ARE DERIVED, as they are for the wiring check above. Side A is every
# transcript found by READING `src/`; side B is the figure read out of the
# GENERATED driver. No suite is named here and no count is typed here, so a
# transcript added to or removed from `src/` moves this check with it.
#
# THIS BLOCK PRINTED A COVERAGE FIGURE UNTIL 2026-08-13 - `<N> of the 8 typed
# case totals are corroborated by a transcript in src/`, with the suites named -
# AND THAT LINE IS DELETED RATHER THAN REPAIRED. It was a present-tense claim
# about the state of the tree with nothing keeping it true, which is the shape of
# sentence this whole mechanism exists to make unsayable. The gate-4.4 judge
# moved it in BOTH directions at rc 0, MEASURED 2026-08-13:
#
#   DOWNWARD, SILENTLY. Rewording a real transcript - `held its 168 cases` to
#   `held its 168 unit cases` - dropped the figure from 3 to 2, and so did
#   line-wrapping the same sentence so that the suite name and the number fell on
#   different lines. Nothing failed. A STALE FIGURE THEN SURVIVES IN `src/` with
#   the printed line reporting a smaller coverage that no reader is watching.
#
#   UPWARD. Prose naming a suite and a number, in a paragraph whose own words
#   were "nothing here was measured from a run", raised the figure to 4 and
#   printed that suite as corroborated.
#
# A NUMBER THAT MOVES IN BOTH DIRECTIONS WITHOUT FAILING MEASURES THE WORDING OF
# COMMENTS AND NOT THE COVERAGE IT NAMES. The AGREEMENT GATE below stays, because
# it is the half that fails: a transcript this scan DOES find and that DISAGREES
# with the driver's figure stops the configure. What is gone is the half that
# reported how much was found, because "found" was never a count of anything an
# author could rely on.
#
# THE SCAN HAS MISSED A REAL TRANSCRIPT, and the miss is recorded because the
# repair it drove is the loop below. `src/mcf5307/logic.nim`'s "All 74
# `t_logic` cases stayed GREEN" went unread, because the number precedes the
# suite name there and the scan read only a number that FOLLOWED it. THAT ONE
# IS CLOSED: the loop below now reads both orders, and the comment at the two
# branches records what the second may and may not match.
#
# HOW MANY TRANSCRIPTS THE SCAN READS IS DELIBERATELY NOT WRITTEN DOWN HERE.
# Every figure this block has carried went stale inside a single round: the
# last one enumerated the suites it had found, and the scan was already reading
# one the enumeration did not name by the time it was committed. Nothing in the
# tree reads such a figure, so nothing makes it fail. What DOES fail is the
# AGREEMENT GATE below - a transcript that disagrees with the driver's own
# figure stops the configure and names the file, the suite and both numbers.
#
# A DIFFERENT MISS OF THE SAME FAMILY IS NOT CLOSED AND IS NOT CLOSEABLE HERE.
# A figure whose suite is named by an ANAPHOR - `src/mcf5307/cpu.nim` carried
# "that suite carries 34 cases", with `t_irq` six lines above - is outside what
# any per-line regex can resolve, and widening this scan until it guessed would
# make it match prose. That is still the reason no figure derived from this scan
# is printed as coverage: what it does not find, it cannot report on.
#
# WHAT IT DOES NOT REACH, STATED SO ITS SILENCE IS NOT READ AS COVERAGE. A suite
# no transcript names is not covered and this check says nothing whatever about
# it: the typed figure is still the only guard there. Neither is a suite whose
# transcript is written in a shape this scan does not read, and the paragraph
# above names one. Nor does it make the transcripts a specification - they are
# dated records of past runs, so a DELIBERATE change in a suite's case count
# makes them red. The repair for that is the one this project already uses where
# a transcript would otherwise quote a total that moves: MEASURED 2026-08-13,
# `src/mcf5307/decode_types.nim` quotes `t_ea_masks` as
# `5 of <caseTotalMustMatchTranscripts> cases failed`, a named reference in place
# of a number, which stays true at every date and leaves this scan nothing to
# compare. Retyping the driver's figure to agree with a stale transcript is not a
# repair, and neither is deleting this block.
file(GLOB_RECURSE MCF5307_CORE_SOURCES "${PROJECT_SOURCE_DIR}/src/*.nim")
foreach(mcf5307_core_source IN LISTS MCF5307_CORE_SOURCES)
    # SPLIT BY HAND for the reason `tests/case_sites.cmake` gives at its own
    # source-side rule: a `;` in the text would split one line into two list
    # elements and take the front off both halves.
    file(READ "${mcf5307_core_source}" mcf5307_core_text)
    string(REPLACE ";" "\\;" mcf5307_core_text "${mcf5307_core_text}")
    string(REPLACE "\n" ";" mcf5307_core_text "${mcf5307_core_text}")
    foreach(mcf5307_core_line IN LISTS mcf5307_core_text)
        if(NOT mcf5307_core_line MATCHES " cases")
            continue()
        endif()
        foreach(mcf5307_suite IN LISTS MCF5307_SUITES_WITH_RUNTIME_HALF)
            # THE SUITE NAME IS BOUNDED ON BOTH SIDES so that one suite's name
            # inside a longer one does not answer for it, and the count must be
            # DIGITS immediately before ` cases` so that the named-reference
            # spelling above is not read as a figure.
            #
            # THE LEFT BOUND WAS MISSING UNTIL 2026-08-13 and only the right one
            # was written. MEASURED that day: a line reading
            # "`helper_t_alu` held its 999 cases" was read as `t_alu` quoting
            # 999 and stopped the configure, naming a suite the line does not
            # mention. A bound on one side of a name is not a bound.
            #
            # BOTH ORDERS ARE READ, AND ONLY ONE WAS UNTIL 2026-08-13. The
            # paragraph above this loop recorded the miss and left it open:
            # `src/mcf5307/logic.nim`'s "All 74 `t_logic` cases stayed GREEN"
            # puts the number BEFORE the name, and a scan that reads only a
            # number FOLLOWING the name never saw it. That is a real transcript
            # quoting a real total, and a stale one would have survived in
            # `src/` with nothing to say so. The second branch below reads it.
            #
            # WHAT THE SECOND BRANCH IS NOT ALLOWED TO DO is match a line the
            # first branch would have rejected as prose. It is bounded on both
            # sides of the name exactly as the first is, and it requires the
            # word `cases` to FOLLOW the name, so a sentence that merely holds
            # a number and a suite name in the same clause is not a figure.
            # MEASURED 2026-08-13 over every line of `src/`: the second branch
            # matches exactly ONE line that the first does not, and it is the
            # `logic.nim` transcript named above.
            #
            # THE SECOND BRANCH DOES MATCH ORDINARY PROSE, AND IT IS KEPT
            # ANYWAY. MEASURED 2026-08-13 by planting
            # "Blocks 24, 25 `t_irq` cases are new" in `cpu.nim`: the configure
            # stopped, reporting that the line quotes 25 cases. It is a real
            # false positive and the shape is one this codebase writes often -
            # block numbers, then a backticked suite name, then `cases`.
            #
            # WHAT WOULD BE TRADED FOR SILENCING IT IS THE REASON IT STAYS. The
            # only feature separating that line from `logic.nim`'s real
            # transcript is which noun the number counts, and no per-line
            # regex reads nouns. Every narrowing available here - bounding the
            # gap between the number and the name, refusing a number that
            # follows a comma - also rejects transcripts an author may
            # legitimately write, and a transcript this scan does not reach is
            # a STALE FIGURE SURVIVING IN `src/` WITH NOTHING TO SAY SO. This
            # branch exists because exactly that had already happened once.
            # A false positive costs one rewording and prints the line it
            # matched; a false negative costs nothing and says nothing.
            #
            # NEITHER BRANCH REACHES A FIGURE WHOSE SUITE IS AN ANAPHOR, and
            # that limit is stated because it cannot be closed here.
            # `src/mcf5307/cpu.nim` carried "that suite carries 34 cases" with
            # the name `t_irq` six lines above it; no widening of a per-line
            # regex resolves "that suite", and a window over adjacent lines
            # does not reach six. The repair for that shape is in the SOURCE -
            # write the suite's name where the number is - and `cpu.nim` now
            # says so at the line this scan reads.
            set(mcf5307_quoted "")
            if(mcf5307_core_line MATCHES
                    "(^|[^A-Za-z0-9_])${mcf5307_suite}[^A-Za-z0-9_].*[^0-9]([0-9]+) cases")
                set(mcf5307_quoted "${CMAKE_MATCH_2}")
            elseif(mcf5307_core_line MATCHES
                    "([0-9]+)[^A-Za-z0-9_]+${mcf5307_suite}[^A-Za-z0-9_]+cases")
                set(mcf5307_quoted "${CMAKE_MATCH_1}")
            endif()
            if(mcf5307_quoted STREQUAL "")
                continue()
            endif()
            if(NOT DEFINED MCF5307_CASE_TOTAL_${mcf5307_suite})
                message(FATAL_ERROR
                    "tests: ${mcf5307_core_source}\n  quotes a case total for "
                    "`${mcf5307_suite}` and no generated driver records one, "
                    "so there is nothing to compare it against.")
            endif()
            if(NOT mcf5307_quoted EQUAL MCF5307_CASE_TOTAL_${mcf5307_suite})
                string(STRIP "${mcf5307_core_line}" mcf5307_core_stripped)
                message(FATAL_ERROR
                    "tests: ${mcf5307_core_source}\n  quotes "
                    "${mcf5307_quoted} cases for `${mcf5307_suite}` and the "
                    "generated driver records "
                    "${MCF5307_CASE_TOTAL_${mcf5307_suite}}:\n    "
                    "${mcf5307_core_stripped}\n"
                    "  THE TYPED FIGURE HAS A SECOND SOURCE AND THE TWO "
                    "DISAGREE, AND THERE ARE THREE REPAIRS BECAUSE THERE ARE "
                    "THREE WAYS TO GET HERE.\n"
                    "  If the count fell without anyone meaning it to, the "
                    "cases are missing and the figure is the symptom.\n"
                    "  If it moved deliberately, the line above is a DATED "
                    "RECORD of a run against a suite that no longer exists in "
                    "that shape: re-measure it, or quote the live figure by "
                    "name as `src/mcf5307/decode_types.nim` does for "
                    "`t_ea_masks`.\n"
                    "  IF THE LINE ABOVE IS NOT A TRANSCRIPT AT ALL - prose "
                    "that happens to name this suite and a number - then there "
                    "is nothing to re-measure and re-measuring it is the wrong "
                    "advice. MEASURED 2026-08-13: this scan reads any line of "
                    "`src/` carrying a suite name followed by digits and the "
                    "word `cases`, including a sentence whose own words were "
                    "\"nothing here was measured from a run\". Reword the line "
                    "so it does not read as a figure for this suite - the "
                    "named-reference spelling above does exactly that.\n"
                    "  RETYPING THE DRIVER'S FIGURE TO AGREE WITH THIS LINE IS "
                    "NOT ONE OF THE THREE.")
            endif()
        endforeach()
    endforeach()
endforeach()


# -------------------------------------------------------------------- CPU-28
# `t_claims` - the claims this repository's tests make about MUTATIONS, made
# executable.
#
# THE MECHANISM IS ITS OWN TASK AND NOT PART OF CPU-17. This block, both
# `t_claims` files and both `case_sites` files carried a CPU-17 label until
# 2026-08-13, which read as though the interrupt task had written its own
# grader. CPU-17 owns the core and the suite this driver MEASURES; what
# measures a suite's claims is separable from the suite, and a grader labelled
# with the task it grades is the arrangement CPU-28 exists to refuse.
#
# WHAT IT ADDS THAT NO OTHER REGISTERED NAME CARRIES. Every other test here
# asserts what the core does. This one asserts what a TEST FILE SAYS about the
# core: that a named mutation is unobservable, or that a named suite does not
# separate it. Such a sentence cannot be reviewed by reading - a false one
# reads exactly like a true one - and it cannot be repaired by rewording.
# `tests/t_claims.cmake` holds the registry and the driver, and
# `tests/t_claims.nim` is the observer the absolute claims are measured with.
#
# IT WRITES NOTHING INTO THE SOURCE TREE. Every mutation is applied to a COPY
# of `src/` under this test's own working directory in the build tree.
#
# THE FLAG SET IS THE LIBRARY'S OWN, AS `t_irq`'s IS, AND WITH NO `--path`.
# The driver passes the path of the tree under measurement itself, and a second
# `--path` naming the pristine tree would leave which module the compiler reads
# up to a search order this project does not control.
if(NOT DEFINED MCF5307_NIM_COMMAND)
    message(FATAL_ERROR
        "tests: t_claims cannot be registered: MCF5307_NIM_COMMAND is not set.")
endif()

set(MCF5307_CLAIMS_COMMAND "")
foreach(argument IN LISTS MCF5307_NIM_COMMAND)
    if(argument STREQUAL "--compileOnly"
            OR argument STREQUAL "--noMain"
            OR argument MATCHES "^--nimcache:"
            OR argument MATCHES "^--header:"
            OR argument MATCHES "^--nimMainPrefix:"
            OR argument MATCHES "^--path:"
            OR argument MATCHES "\\.nim$")
        continue()
    endif()
    list(APPEND MCF5307_CLAIMS_COMMAND "${argument}")
endforeach()

add_test(NAME t_claims
    COMMAND "${CMAKE_COMMAND}"
        "-DCLAIMS_SOURCE_DIR=${PROJECT_SOURCE_DIR}"
        "-DCLAIMS_WORK_DIR=${CMAKE_CURRENT_BINARY_DIR}/t_claims_work"
        "-DCLAIMS_NIM_COMMAND=${MCF5307_CLAIMS_COMMAND}"
        -P "${CMAKE_CURRENT_LIST_DIR}/t_claims.cmake")

# --------------------------------------------------------------------- CPU-3
# The application binary interface SMOKE test `abi_smoke`.
#
# This is the test the CPU-3 task CHECK names. It tests the ABI surface the
# task's closure produces, and it asserts NO CORE BEHAVIOUR. The test takes
# the address of every function `include/mcf5307.h` declares, which is the
# assertion that a renamed or dropped declaration is a link error. It calls
# `mcf5307_runtime_init()` twice and asserts both calls return. C++ never
# names `NimMain`; it calls `mcf5307_runtime_init()`, which is idempotent.
add_executable(abi_smoke ${CMAKE_CURRENT_LIST_DIR}/abi_smoke.cpp)
# `include/` IS THE WHOLE INCLUDE PATH, and leaving the nimcache and the Nim
# library directory off it is the point. The consumer this test stands in for -
# `gearmulator`'s `g2Lib` - has neither on its own include path. Either one
# added here would let `include/mcf5307.h` acquire a dependency on a generated
# header or on `nimbase.h` and still compile under this test, which is the
# regression the test exists to catch. `abi_smoke_symbols.inc` needs no `-I`:
# a quoted include resolves beside `abi_smoke.cpp`.
target_include_directories(abi_smoke PRIVATE "${PROJECT_SOURCE_DIR}/include")
target_link_libraries(abi_smoke PRIVATE mcf5307)
target_compile_features(abi_smoke PRIVATE cxx_std_17)
if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
    # `MCF5307_TEST_WARNING_RELAXATIONS` is the root list's probe result. It is
    # empty for a standalone configure and for every compiler that does not
    # know the diagnostic; it demotes ONLY a diagnostic a consumer's own flags
    # produce, and never a warning in this project's source. See the root
    # `CMakeLists.txt` for the measurement.
    target_compile_options(abi_smoke PRIVATE -Wall -Wextra -pedantic -Werror
        ${MCF5307_TEST_WARNING_RELAXATIONS})
endif()
add_dependencies(mcf5307_tests abi_smoke)
add_test(NAME abi_smoke COMMAND abi_smoke)
