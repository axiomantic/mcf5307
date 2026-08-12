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
# the parent-variable shadow of `MCF5307_ABI_GATE` was found in. MEASURED
# 2026-08-12: 17 names top-level, 1 from a scratch parent.
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
if(NOT ea_run_out MATCHES "t_ea_masks: [0-9]+ cases passed")
    message(FATAL_ERROR
        "t_ea_masks: the run exited 0 but did not report a full pass.\n"
        "  stdout : ${ea_run_out}\n  stderr : ${ea_run_err}")
endif()
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
if(NOT sign_run_out MATCHES "t_sign_extend: [0-9]+ cases passed")
    message(FATAL_ERROR
        "t_sign_extend: the run exited 0 but did not report a full pass.\n"
        "  stdout : ${sign_run_out}\n  stderr : ${sign_run_err}")
endif()
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
if(NOT alu_run_out MATCHES "t_alu: [0-9]+ cases passed")
    message(FATAL_ERROR
        "t_alu: the run exited 0 but did not report a full pass.\n"
        "  stdout : ${alu_run_out}\n  stderr : ${alu_run_err}")
endif()
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
if(NOT move_run_out MATCHES "t_move: [0-9]+ cases passed")
    message(FATAL_ERROR
        "t_move: the run exited 0 but did not report a full pass.\n"
        "  stdout : ${move_run_out}\n  stderr : ${move_run_err}")
endif()
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
#
# THE FOUR OTHER BLOCKS IN THIS FILE CARRY THE SAME SENTENCE AND THE SAME
# `[0-9]+`. They belong to their own tasks - section 7.4.2 makes CPU-26 the
# owner of this file and admits a later cpu task only as a second writer of
# ITS OWN registration - so they are not repaired here and they are filed.
if(NOT logic_run_out MATCHES "t_logic: [1-9][0-9]* cases passed")
    message(FATAL_ERROR
        "t_logic: the run exited 0 but did not report a full pass.\n"
        "  stdout : ${logic_run_out}\n  stderr : ${logic_run_err}")
endif()
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
#
# THE FOUR OLDEST BLOCKS IN THIS FILE STILL USE `[0-9]+`. They belong to their
# own tasks - section 7.4.2 makes CPU-26 the owner of this file and admits a
# later cpu task only as a second writer of ITS OWN registration - so they are
# not repaired here and they are filed.
if(NOT control_run_out MATCHES "t_control: [1-9][0-9]* cases passed")
    message(FATAL_ERROR
        "t_control: the run exited 0 but did not report a full pass.\n"
        "  stdout : ${control_run_out}\n  stderr : ${control_run_err}")
endif()
]==])

string(CONFIGURE "${MCF5307_CONTROL_DRIVER_TEMPLATE}"
    MCF5307_CONTROL_DRIVER @ONLY)
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/t_control_driver.cmake"
    "${MCF5307_CONTROL_DRIVER}")

add_test(NAME t_control
    COMMAND "${CMAKE_COMMAND}"
        -P "${CMAKE_CURRENT_BINARY_DIR}/t_control_driver.cmake")

# -------------------------------------------------------------------- CPU-14
# `t_exception` - the exception model.
#
# ONE REGISTERED NAME, AND NO CORPUS BESIDE IT. Every other executor block in
# this file registers a unit test beside a conformance corpus of the same
# group. This task has none: the corpus runner executes ASSEMBLED encodings,
# and neither an access error nor an address error can be assembled. The whole
# of the evidence for this task is the registered name below.
#
# IT COMPILES A MODULE THE LIBRARY DOES NOT YET CARRY. `src/mcf5307.nim` imports
# each submodule so that the compiler compiles it into the library, and it does
# not name `exception.nim`: that file is CPU-1's and this task declares no write
# to it. The module exports no C symbol, so its absence from the archive changes
# nothing a caller can see - but it also means THIS TEST IS THE ONLY THING IN
# THE TREE THAT COMPILES `src/mcf5307/exception.nim` at all, and it compiles it
# with the library's own flag set for that reason. CPU-15 is the first consumer
# and the task that puts the module into the library.
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
]==])

string(CONFIGURE "${MCF5307_EXCEPTION_DRIVER_TEMPLATE}"
    MCF5307_EXCEPTION_DRIVER @ONLY)
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/t_exception_driver.cmake"
    "${MCF5307_EXCEPTION_DRIVER}")

add_test(NAME t_exception
    COMMAND "${CMAKE_COMMAND}"
        -P "${CMAKE_CURRENT_BINARY_DIR}/t_exception_driver.cmake")

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
target_include_directories(abi_smoke PRIVATE
    "${PROJECT_SOURCE_DIR}/include"
    "${NIMCACHE_DIR}"
    "${NIM_INCLUDE_DIR}"
)
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
