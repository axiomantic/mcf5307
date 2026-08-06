# The root of the `mcf5307` CMake project. Task CPU-26 creates this file and
# every registration list under it, and it is the only task that creates one.
#
# CPU-26 REGISTERS NO TEST OF ITS OWN. `tests/tests_cpu.cmake` and
# `conformance/conformance_cpu.cmake` are created EMPTY on purpose, and each
# later cpu task adds its own `add_test(NAME <name> ...)` line to the list that
# governs its own directory. A skeleton that registered a test would make the
# emptiness of those lists unobservable.
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
# that registers no test: the first is a broken build tree and the second is
# this skeleton. CPU-26's negative case deletes this line and asserts the two
# shapes are distinguishable.
enable_testing()

# The T0 test aggregate. It is created here, empty of dependencies, because
# milestone M1's check builds this target and a task that registers tests
# cannot sit downstream of the tasks whose tests it registers. Each later cpu
# task attaches its own executable with
# `add_dependencies(mcf5307_tests <its target>)`.
#
# It is a custom target and not an ALL target: the test executables that later
# tasks add are ordinary `add_executable` targets and are in ALL already, so
# `--target mcf5307_tests` is a way to build the test set alone rather than a
# second path to the same build.
add_custom_target(mcf5307_tests
    COMMENT "Building the mcf5307 T0 test set")

# CMake drives Nim. Task CPU-1 adds this line and owns the file it includes.
# The six integration steps of design section 20.1 run there, at configure
# time, and they leave `mcf5307_nim_objs`, `mcf5307` and `mcf5307::mcf5307`
# defined. THE INCLUDE COMES BEFORE THE TEST DIRECTORIES because a test that
# links the core needs the target to exist when its own list is read.
include(cmake/Nim.cmake)

add_subdirectory(tests)
add_subdirectory(conformance)
