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
    target_compile_options(t0_corpus_parses PRIVATE
        -Wall -Wextra -pedantic -Werror)
endif()
add_test(NAME t0_corpus_parses
    COMMAND t0_corpus_parses "${PROJECT_SOURCE_DIR}/conformance/corpus")
