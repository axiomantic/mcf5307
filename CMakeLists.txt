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
enable_testing()

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

add_subdirectory(tests)
add_subdirectory(conformance)
