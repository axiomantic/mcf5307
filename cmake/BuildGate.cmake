# The build gate: the registration of `t0_build_is_current`, and the one call
# a registration list makes to put its own tests behind it.
#
# Why this is not in a `*_cpu.cmake` registration list. It is a property of the
# whole build tree, it is registered once, and it must sit ahead of every test
# in every directory. Registering it in `tests/` would also put it in a
# consumer's tree, where it would try to build the consumer's project from
# inside the consumer's ctest run. It is registered here, at top level only.
#
# What it repairs. `ctest` grades the executables it finds. When a build fails,
# the executables from the last successful build are still on disk, and ctest
# runs those and reports Passed. Measured in this tree: a `full` run reported
# `100% tests passed, 0 tests failed out of 37` while `cmake --build --preset
# full` had exited 2, and a `t0` run reported `t0_abi_smoke ... Passed` while
# `cmake --build --preset t0` had exited 2. Nothing in either run named the
# build. Correctness rested entirely on the caller remembering to read
# `BUILD_EXIT` before believing the summary -- a discipline, not a mechanism.
#
# The shape, and why this one.
#
#   It must fail loudly rather than by omission. A missing executable makes
#   ctest report `Not Run` for the one test that names it while the other tests
#   still report Passed; the reader is left to notice one line. So the gate is
#   a test that fails, with a banner that names the build.
#
#   It must not depend on the caller. So it is a registered `add_test`, inside
#   the run whose summary the caller reads, and not a wrapper script or a
#   documented step that a caller can skip.
#
#   It must distinguish `the build failed` from `these tests fail`. So the gate
#   is a CTest fixture. When it fails, the dependent tests are not run at all
#   and ctest says they failed to satisfy a fixture dependency; the only test
#   reported as FAILED is the one named `t0_build_is_current`, whose output is
#   the banner. When the build is good and a test is genuinely wrong, the gate
#   passes and only the wrong test fails -- the ordinary reading.
#
# What it also fixes. `cmake --build --preset t0` builds only the
# `mcf5307_tests` target, which does not reach `conformance/`'s
# `t0_corpus_parses` executable, while `ctest --preset t0` DOES select that
# test by name; a clean tree therefore reported `t0_corpus_parses (Not Run)`.
# The gate builds the default target of the tree it runs in, so the executable
# now exists by the time any test runs. That trap and this defect are the same
# defect: in both, ctest grades whatever happens to be on disk and the build is
# not on the path to the verdict.
#
# It builds the tree and not a list of targets. Naming the targets the run
# needs -- `mcf5307_tests` plus `t0_corpus_parses` -- would be a roster, and a
# roster amended once per case is the very thing that produced the `Not Run`
# above: the t0 BUILD preset's target list stopped matching the set of tests
# the t0 TEST preset selects, and nothing was there to notice. The default
# target of the tree is not a roster, so it cannot drift out of date.
#
# The consequence is that T0 is now wider than its build preset.
# `cmake --build --preset t0` still narrows
# the build to `mcf5307_tests`; what has changed is that `ctest --preset t0`
# no longer grades a tree it has not built. Measured: a syntax error in
# `conformance/runner.cpp`, which the t0 build preset never compiles, now
# turns `ctest --preset t0` red. T0's narrowing was always of the run; the
# tree it runs in is the whole project.
#
# The cost. The gate runs an incremental build. On an already-built tree that
# is a no-op walk of the dependency graph; on a t0 tree it additionally builds
# the conformance targets that the t0 BUILD preset skips, once. Measured on
# an already-built t0 tree: 40.3s before the gate, 41.5s after.

set(MCF5307_BUILD_GATE_FIXTURE "MCF5307_BUILD_IS_CURRENT")

# `t0_` so that the T0 name filter -- `^t0_|^t_`, carried by the test presets
# and by `T0_PATTERN` in `.github/workflows/ci.yml` -- selects it. A gate that
# the narrow run filters out is a gate for the full run only.
if(PROJECT_IS_TOP_LEVEL)
    add_test(NAME t0_build_is_current
        COMMAND "${CMAKE_COMMAND}"
            "-DMCF5307_BUILD_DIR=${CMAKE_BINARY_DIR}"
            -P "${CMAKE_CURRENT_LIST_DIR}/run_build_gate.cmake")

    # RUN_SERIAL because the gate writes the executables the other tests
    # execute. FIXTURES_SETUP already keeps the dependents behind it, and
    # every registered test is a dependent, but a serial gate is the property
    # that says why rather than relying on that remaining true.
    set_tests_properties(t0_build_is_current PROPERTIES
        FIXTURES_SETUP "${MCF5307_BUILD_GATE_FIXTURE}"
        RUN_SERIAL TRUE)

    set(MCF5307_BUILD_GATE_ARMED TRUE)
else()
    # A consumer's tree has no gate, so nothing there may require one: a
    # fixture requirement naming a fixture no test sets up makes every
    # requiring test unrunnable.
    set(MCF5307_BUILD_GATE_ARMED FALSE)
endif()

# Put every test registered in the CALLING directory behind the gate.
#
# It is a call and not an automatic sweep from the root because CMake's
# `set_tests_properties` reaches only the tests of the directory it is called
# in -- measured: a call at root scope naming a test added in `tests/` is a
# configure error, not a no-op. So each registration list makes this call at
# its own end, which is also the one place where every test it registers is
# already known.
function(mcf5307_require_current_build)
    if(NOT MCF5307_BUILD_GATE_ARMED)
        return()
    endif()

    get_property(dir_tests DIRECTORY PROPERTY TESTS)
    list(REMOVE_ITEM dir_tests t0_build_is_current)
    if(dir_tests STREQUAL "")
        return()
    endif()

    set_tests_properties(${dir_tests} PROPERTIES
        FIXTURES_REQUIRED "${MCF5307_BUILD_GATE_FIXTURE}")

    list(LENGTH dir_tests dir_test_count)
    message(STATUS
        "mcf5307: the build gate covers ${dir_test_count} test(s) registered in "
        "${CMAKE_CURRENT_SOURCE_DIR}")
endfunction()
