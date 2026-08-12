# The root of the `mcf5307` CMake project.
#
# Each test is registered in the list that governs its own directory:
# `tests/tests_cpu.cmake` or `conformance/conformance_cpu.cmake`.
#
# 3.20 is the floor because `--no-tests=error` is a CTest flag that the earlier
# releases do not carry, and without that flag every `-R` check in this project
# passes against no code at all. The requirement is on the installed CTest;
# `.github/workflows/ci.yml` checks the installed version in every job.

cmake_minimum_required(VERSION 3.20)

project(mcf5307
    VERSION 0.1.0
    DESCRIPTION "An MCF5307 ColdFire core and an ISP1181 USB device model"
    LANGUAGES C CXX)

# `enable_testing()` is what makes the test tree reachable. Without it CTest
# reports no test project at all, which is a DIFFERENT shape from a project
# that registers no test: the first is a broken build tree and the second is a
# tree with an empty registration list.
#
# IT IS NOT GUARDED BY `PROJECT_IS_TOP_LEVEL` AND THE SUITE BELOW IT IS. A
# guarded one writes no `CTestTestfile.cmake` for this directory in a consumer's
# tree, and the ABI-gate assertion `tests/tests_cpu.cmake` registers there would
# then not register at all.
enable_testing()

# The relaxation that keeps a consumer's compiler flags from failing this
# project's own test targets.
#
# `tests/tests_cpu.cmake` and `conformance/conformance_cpu.cmake` compile their
# executables with `-Wall -Wextra -pedantic -Werror`, and that `-Werror` is
# correct: a warning in code this project wrote must stop the build.
#
# A consumer that adds this project with `FetchContent` also gives it the
# consumer's own `CMAKE_C_FLAGS_RELEASE` and `CMAKE_CXX_FLAGS_RELEASE`.
# Measured: `gearmulator` appends `-Ofast`, and a current Apple clang answers
# `-Ofast` with `argument '-Ofast' is deprecated; use '-O3 -ffast-math'
# [-Wdeprecated-ofast]`. That diagnostic is about the command line the consumer
# built and not about one line of this project's source, so `-Werror` promotes
# it to an error and the registered tests become Not Run. The same warning is
# printed elsewhere in that build and is harmless there, because only these
# targets carry `-Werror`.
#
# The demotion names one diagnostic and not all of them. `-Wno-error` (the flag
# `cmake/Nim.cmake` uses for Nim-generated C, which this project does not write)
# would disarm every warning in code this project does write, and `-w` would
# hide them. `-Wno-error=deprecated-ofast` leaves every other warning fatal:
# only the one diagnostic a consumer's flag can produce becomes a warning
# again, and it is still printed.
#
# The flag is probed and never assumed. `deprecated-ofast` is a clang
# diagnostic name. GCC rejects `-Wno-error=` for a warning it does not have,
# and MSVC has no such spelling at all, so an unconditional append would break
# the Linux and Windows builds this project also targets.
# `check_cxx_compiler_flag` answers for the compiler actually in use, and the
# variable stays empty when the answer is no.
#
# Standalone this appends nothing observable: no flag in this project's own
# configure emits `-Wdeprecated-ofast`, so the relaxation has nothing to demote
# and the standalone results do not move.
include(CheckCXXCompilerFlag)

set(MCF5307_TEST_WARNING_RELAXATIONS "")
if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
    check_cxx_compiler_flag("-Wno-error=deprecated-ofast"
        MCF5307_HAVE_WNO_ERROR_DEPRECATED_OFAST)
    if(MCF5307_HAVE_WNO_ERROR_DEPRECATED_OFAST)
        list(APPEND MCF5307_TEST_WARNING_RELAXATIONS
            "-Wno-error=deprecated-ofast")
    endif()
endif()

# The T0 test aggregate. A test executable attaches itself with
# `add_dependencies(mcf5307_tests <its target>)`.
#
# It is a custom target and not an ALL target: the test executables are
# ordinary `add_executable` targets and are in ALL already, so
# `--target mcf5307_tests` is a way to build the test set alone rather than a
# second path to the same build.
add_custom_target(mcf5307_tests
    COMMENT "Building the mcf5307 T0 test set")

# CMake drives Nim. Six integration steps run there, at configure time, and
# they leave `mcf5307_nim_objs`, `mcf5307` and `mcf5307::mcf5307` defined. The
# include comes before the test directories because a test that links the core
# needs the target to exist when its own list is read.
include(cmake/Nim.cmake)

# `tests/` IS ENTERED IN EVERY TREE AND `conformance/` ONLY AT TOP LEVEL.
# `tests/tests_cpu.cmake` registers the ABI-gate assertion and then returns
# unless this project is top-level, so a consumer inherits that one test, no
# other, and no test executable. Nothing in `conformance/` has a reason to
# outlive the top-level tree, so its guard is the whole directory.
add_subdirectory(tests)
if(PROJECT_IS_TOP_LEVEL)
    add_subdirectory(conformance)
endif()
