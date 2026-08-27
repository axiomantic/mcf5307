# The body of the `t0_build_is_current` test. `cmake/BuildGate.cmake`
# registers the test that runs this file with `cmake -P`.
#
# IT BUILDS THE TREE IT IS RUN IN AND FAILS WHEN THE BUILD FAILS. That is the
# whole mechanism. A ctest run whose executables were left over from an earlier
# successful build reports Passed about source that no longer compiles, and
# nothing in the run says so; measured twice in this repository on one day,
# once as `37/37 green` with the build exiting 2, and once as `t0_abi_smoke
# Passed` with the build exiting 2. Making the build a REGISTERED TEST puts the
# build's exit status on the same path as every other verdict, so a caller who
# reads only ctest's summary still sees it.
#
# THE COMMAND IS THE ONE `.github/workflows/ci.yml` ALREADY RUNS in its
# `Configure and build` step -- `cmake --build <dir> --parallel`, no
# keep-going. That is deliberate and not a coincidence: this gate can then
# never be redder than CI's own build step, so it introduces no new way for the
# tree to fail. Keep-going belongs in the BUILD presets, whose job is to build
# as much as they can so a failure is reported per target; it does not belong
# here, whose job is to answer one question with one bit.
#
# `RESULT_VARIABLE` reads the child's own exit status. There is no pipe in this
# file for the same reason the defect exists at all: `$?` after a pipe reports
# the LAST command's status, and a build failure read through a pipe reads
# exactly like a success.

if(NOT DEFINED MCF5307_BUILD_DIR)
    message(FATAL_ERROR
        "run_build_gate.cmake: MCF5307_BUILD_DIR was not passed. "
        "This file is not meant to be run by hand; "
        "cmake/BuildGate.cmake registers the test that runs it.")
endif()

if(NOT IS_DIRECTORY "${MCF5307_BUILD_DIR}")
    message(FATAL_ERROR
        "run_build_gate.cmake: MCF5307_BUILD_DIR=${MCF5307_BUILD_DIR} "
        "is not a directory.")
endif()

# The output is NOT captured. It streams to ctest, so the compiler diagnostics
# appear above the banner below and the reader sees which file failed. Both
# test presets carry `--output-on-failure`, so a failing gate prints them.
execute_process(
    COMMAND "${CMAKE_COMMAND}" --build "${MCF5307_BUILD_DIR}" --parallel
    RESULT_VARIABLE mcf5307_build_rc)

if(NOT mcf5307_build_rc STREQUAL "0")
    # The banner is printed in NOTICE mode and the abort carries one line.
    # `message(FATAL_ERROR)` REFLOWS and re-indents its text, which turns a
    # banner into ragged prose; NOTICE mode prints what is written.
    message([[
================================================================
mcf5307: THE BUILD FAILED.

THIS IS A BUILD FAILURE, NOT A TEST FAILURE. No test verdict in
this run describes the current source. Every other test in this
tree was left unrun rather than run against an executable that
is stale or missing.

Fix the compile or link errors printed above this banner, then
run the suite again.
================================================================]])
    message("build tree:  ${MCF5307_BUILD_DIR}")
    message("build exited with status ${mcf5307_build_rc}")
    message(FATAL_ERROR
        "t0_build_is_current: FAIL: the build failed; nothing below is graded.")
endif()

message("t0_build_is_current: PASS: "
    "${MCF5307_BUILD_DIR} built clean; "
    "the verdicts below are about source that compiles.")
