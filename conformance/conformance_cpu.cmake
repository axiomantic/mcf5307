# The cpu track's registration list for `conformance/`.
#
# CPU-26 CREATES THIS FILE EMPTY AND REGISTERS NOTHING IN IT, for the same
# reason `tests/tests_cpu.cmake` is empty.
#
# The conformance corpus parse check and the corpus runner add their own
# `add_test(NAME <name> ...)` lines here.

# --------------------------------------------------------------------- CPU-4
# `t0_corpus_parses` - the conformance corpus parse check.
#
# The CPU-4 Check: line is split by platform. Where there is no m68k cross
# assembler (macOS arm64, Windows x86-64) this is the check: it loads the
# committed corpus and asserts it parses and is complete - every group CPU-7
# to CPU-10 names is present, and every case carries an instruction, an
# initial state and an expected final state.
#
# The program is pure C++, links nothing but the runtimes, and so needs no
# Nim and no cross assembler. The corpus directory is passed as an argument;
# the program finds the four `<group>_00.json` files inside it.
#
# The build compiles this executable ONCE inside the build, and the test then
# RUNS it, unlike the t0_abi_header and t_checks_on tests which compile inside
# the test. That difference is deliberate: those two assert properties of the
# compile flags, which only a compile at test time can exercise. This test
# asserts a property of the committed DATA (the corpus), whose bytes do not
# change when the build changes, so the ordinary build-and-run shape is the
# right one.
add_executable(t0_corpus_parses ${PROJECT_SOURCE_DIR}/conformance/parse_check.cpp)
target_compile_features(t0_corpus_parses PRIVATE cxx_std_17)
if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
    # `MCF5307_TEST_WARNING_RELAXATIONS` is the root list's probe result. It is
    # empty for a standalone configure and for every compiler that does not
    # know the diagnostic; it demotes ONLY a diagnostic a consumer's own flags
    # produce, and never a warning in this project's source. See the root
    # `CMakeLists.txt` for the measurement.
    target_compile_options(t0_corpus_parses PRIVATE
        -Wall -Wextra -pedantic -Werror
        ${MCF5307_TEST_WARNING_RELAXATIONS})
endif()
add_test(NAME t0_corpus_parses
    COMMAND t0_corpus_parses "${PROJECT_SOURCE_DIR}/conformance/corpus")

# --------------------------------------------------------------------- CPU-5
# The conformance runner and its five registered tests.
#
# CPU-5 creates `conformance/runner.cpp`, one executable, and registers FIVE
# tests off it: one per group and the whole-corpus aggregate. The group is
# selected by the registered test NAME and never by a forwarded argument that a
# CTest invocation appends -- CPU-5's own note gives the measured reason (CTest
# does not forward arguments after `--`), so each registration carries its
# `--group <name>` in its own COMMAND.
#
# The whole-corpus test is named `mcf5307_conformance_all` and NOT
# `mcf5307_conformance`. The shorter name is a PREFIX of all four group names,
# so `-R ^mcf5307_conformance$` would match nothing (anchored) and an
# unanchored `-R mcf5307_conformance` would run all five twice. The rename
# removes the trap.
#
# The runner links the `mcf5307` static library through the C ABI
# (`include/mcf5307.h`). The executable is built ONCE in the build; the five
# tests then run it. Unlike `t0_corpus_parses`, this asserts a property of the
# CORE against committed DATA, so the ordinary build-and-run shape is the right
# one.
#
# THE CORPUS DIRECTORY IS PASSED AS AN ORDINARY COMMAND ARGUMENT. The runner
# takes `<corpus-dir>` from argv, so the test command names it exactly as it
# exists in the source tree, and the build needs no generated path.

add_executable(mcf5307_conformance
    "${PROJECT_SOURCE_DIR}/conformance/runner.cpp")
target_include_directories(mcf5307_conformance PRIVATE
    "${PROJECT_SOURCE_DIR}/include")
target_link_libraries(mcf5307_conformance PRIVATE mcf5307)
target_compile_features(mcf5307_conformance PRIVATE cxx_std_17)
if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
    # See `t0_corpus_parses` above and the root `CMakeLists.txt`.
    target_compile_options(mcf5307_conformance PRIVATE
        -Wall -Wextra -pedantic -Werror
        ${MCF5307_TEST_WARNING_RELAXATIONS})
endif()

set(MCF5307_CONFORMANCE_CORPUS "${PROJECT_SOURCE_DIR}/conformance/corpus")

add_test(NAME mcf5307_conformance_move
    COMMAND mcf5307_conformance --group move "${MCF5307_CONFORMANCE_CORPUS}")
add_test(NAME mcf5307_conformance_alu
    COMMAND mcf5307_conformance --group alu "${MCF5307_CONFORMANCE_CORPUS}")
add_test(NAME mcf5307_conformance_logic
    COMMAND mcf5307_conformance --group logic "${MCF5307_CONFORMANCE_CORPUS}")
add_test(NAME mcf5307_conformance_control
    COMMAND mcf5307_conformance --group control "${MCF5307_CONFORMANCE_CORPUS}")
add_test(NAME mcf5307_conformance_all
    COMMAND mcf5307_conformance "${MCF5307_CONFORMANCE_CORPUS}")
