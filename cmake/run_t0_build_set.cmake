# The body of `t0_test_set_builds_what_it_runs`.
#
# THE RULE. A test whose name the T0 pattern selects, and whose `COMMAND` names
# a CMake executable target, is run by `ctest --preset t0` and must therefore be
# BUILT by `cmake --build --preset t0`. That build preset carries
# `--target mcf5307_tests` and nothing else, so the only way a target reaches it
# is an `add_dependencies(mcf5307_tests <target>)` line. The root `CMakeLists.txt`
# states that convention where it creates the aggregate; this check is what makes
# a list file that forgets it fail.
#
# WHY THE FAILURE NEEDED A CHECK OF ITS OWN. A target that is registered but not
# built leaves its test `***Not Run`, which is a failure ctest reports only when
# the executable is genuinely absent at run time. That failure was hidden in
# this tree from more than one direction:
#
#   - `--no-tests=error` catches a `-R` pattern that selects NOTHING. It says
#     nothing about a selected test whose binary is missing, and `AGENTS.md`
#     records that scope.
#   - `t0_build_is_current` builds the tree's DEFAULT target, which contains
#     every `add_executable`. It therefore produced the missing binary before any
#     test ran -- it MASKED the omission rather than reporting it.
#   - `.github/workflows/ci.yml` builds with `cmake --build build --parallel`,
#     the default target again.
#
# So the omission was invisible from every angle while `ctest --preset t0` was
# quietly wider than the build preset that is supposed to feed it. This check
# reads the registration lists as TEXT, which is the one view that does not
# depend on the default target having already built everything.
#
# WHY TEXT AND NOT THE BUILD SYSTEM. CMake has no readable `COMMAND` property on
# a test -- `get_property(TEST <name> PROPERTY COMMAND)` answers `NOTFOUND` --
# and directory-scoped test properties need CMake 3.28, above this project's 3.20
# floor. The list files are the source of truth for what is registered, and
# `ci.yml` already derives its own roster from them by grepping for `add_test(NAME`.
#
# THE INPUT SET IS GLOBBED, NOT LISTED. A written list of registration files is a
# roster: the day a fourth file registers a test, a roster silently stops covering
# it and this check reports a clean tree. So the check sweeps every `*.cmake` and
# `CMakeLists.txt` under the source directory instead, and it does NOT anchor
# `add_test(NAME` to column zero -- `cmake/BuildGate.cmake` registers
# `t0_build_is_current` indented inside an `if()`, and an anchored sweep would
# pass straight over it. A leading `#` is what separates a registration from the
# several comments in this tree that spell `add_test(NAME <name> ...)` in prose.
cmake_minimum_required(VERSION 3.20)

foreach(required IN ITEMS T0_PATTERN T0_SOURCE_DIR T0_AGGREGATE)
    if(NOT DEFINED ${required})
        message(FATAL_ERROR
            "t0_test_set_builds_what_it_runs: ${required} was not passed to this "
            "script. The registration in tests/tests_cpu.cmake passes all three.")
    endif()
endforeach()

# The build trees `.gitignore` reserves inside the source tree (`build/`,
# `build-asan/`) hold generated list files and CMake's own modules, and a driver
# generated from a template would otherwise be read as a second registration of
# the test it drives. The preset trees are outside the source tree already.
file(GLOB_RECURSE t0_candidates LIST_DIRECTORIES false
    "${T0_SOURCE_DIR}/*.cmake"
    "${T0_SOURCE_DIR}/CMakeLists.txt"
    "${T0_SOURCE_DIR}/*/CMakeLists.txt")
set(t0_lists "")
foreach(candidate IN LISTS t0_candidates)
    file(RELATIVE_PATH relative "${T0_SOURCE_DIR}" "${candidate}")
    if(relative MATCHES "(^|/)build[^/]*/" OR relative MATCHES "(^|/)CMakeFiles/")
        continue()
    endif()
    list(APPEND t0_lists "${candidate}")
endforeach()
list(LENGTH t0_lists t0_list_count)
if(t0_list_count EQUAL 0)
    message(FATAL_ERROR
        "t0_test_set_builds_what_it_runs: the sweep of ${T0_SOURCE_DIR} found no "
        "CMake list file at all. This check cannot read the tree it is checking.")
endif()

# -----------------------------------------------------------------------------
# Pass 1 -- every target the aggregate has been told to build.
set(t0_attached "")
foreach(list_file IN LISTS t0_lists)
    file(STRINGS "${list_file}" list_lines)
    foreach(line IN LISTS list_lines)
        if(line MATCHES "^[ \t]*add_dependencies\\(${T0_AGGREGATE}[ \t]+([A-Za-z0-9_]+)[ \t]*\\)")
            list(APPEND t0_attached "${CMAKE_MATCH_1}")
        endif()
    endforeach()
endforeach()

# -----------------------------------------------------------------------------
# Pass 2 -- every T0-selected registration, and what its COMMAND runs.
set(t0_failures "")
set(t0_failure_count 0)
set(t0_registrations 0)
set(t0_selected 0)
set(t0_target_backed 0)

foreach(list_file IN LISTS t0_lists)
    file(STRINGS "${list_file}" list_lines)
    list(LENGTH list_lines line_count)
    if(line_count EQUAL 0)
        continue()
    endif()
    math(EXPR last_line "${line_count} - 1")

    foreach(index RANGE ${last_line})
        list(GET list_lines ${index} line)
        if(NOT line MATCHES "^[ \t]*add_test\\(NAME[ \t]+([A-Za-z0-9_]+)")
            continue()
        endif()
        set(test_name "${CMAKE_MATCH_1}")
        math(EXPR t0_registrations "${t0_registrations} + 1")

        # A name the T0 pattern does not select is not run by the t0 test preset,
        # so the t0 build preset owes it nothing. `ci.yml` keeps the written
        # roster of which names those are and why; this check does not duplicate
        # that roster, it just applies the same pattern.
        if(NOT test_name MATCHES "${T0_PATTERN}")
            continue()
        endif()
        math(EXPR t0_selected "${t0_selected} + 1")

        # The first COMMAND argument sits either on the registration line or on
        # the line below it. Both shapes are in use in this tree.
        set(command_token "")
        if(line MATCHES "COMMAND[ \t]+([^ \t]+)")
            set(command_token "${CMAKE_MATCH_1}")
        else()
            math(EXPR next_index "${index} + 1")
            if(NOT next_index GREATER last_line)
                list(GET list_lines ${next_index} following)
                if(following MATCHES "^[ \t]*COMMAND[ \t]+([^ \t]+)")
                    set(command_token "${CMAKE_MATCH_1}")
                endif()
            endif()
        endif()
        string(REGEX REPLACE "\\)+$" "" command_token "${command_token}")

        if(command_token STREQUAL "")
            math(EXPR t0_failure_count "${t0_failure_count} + 1")
            string(APPEND t0_failures "\n  - "
                "${test_name} (${list_file}): no COMMAND argument was found on the "
                "registration line or the line below it. The registration shape has "
                "moved out from under this check -- repair the parser here, do not "
                "reshape the registration to suit it.")
            continue()
        endif()

        # A `cmake -P` script test compiles and runs its own subject at test time
        # and needs nothing from the build.
        if(command_token STREQUAL "\"\${CMAKE_COMMAND}\"")
            continue()
        endif()

        if(NOT command_token MATCHES "^[A-Za-z_][A-Za-z0-9_]*$")
            math(EXPR t0_failure_count "${t0_failure_count} + 1")
            string(APPEND t0_failures "\n  - "
                "${test_name} (${list_file}): its COMMAND begins with "
                "`${command_token}`, which is neither \"\${CMAKE_COMMAND}\" nor a bare "
                "target name. This check knows those two shapes and refuses to guess "
                "at a third: decide here whether the new shape needs a build.")
            continue()
        endif()

        math(EXPR t0_target_backed "${t0_target_backed} + 1")
        if(NOT command_token IN_LIST t0_attached)
            math(EXPR t0_failure_count "${t0_failure_count} + 1")
            string(APPEND t0_failures "\n  - "
                "${test_name} (${list_file}): runs the executable target "
                "`${command_token}`, and no `add_dependencies(${T0_AGGREGATE} "
                "${command_token})` line attaches that target to the aggregate the t0 "
                "build preset builds. `cmake --build --preset t0` will not produce it, "
                "and `ctest --preset t0` would report the test ***Not Run in any tree "
                "where the build gate had not already built the default target.")
        endif()
    endforeach()
endforeach()

# The sweep saw the tree. A zero here is this check having gone blind -- a
# changed registration spelling, or a glob that matched nothing -- and it reads
# exactly like a tree with no tests in it.
if(t0_registrations EQUAL 0)
    message(FATAL_ERROR
        "t0_test_set_builds_what_it_runs: ${t0_list_count} CMake list file(s) were "
        "swept and not one `add_test(NAME ...` was found. That is not a clean "
        "result; it is this check no longer recognising a registration.")
endif()

# The known positive. Every shape this check can report needs at least one
# target-backed T0 test to exist for the check to have looked at anything; a zero
# here means the classification above put every registration in the
# `${CMAKE_COMMAND}` bucket and the check passed without exercising its subject.
if(t0_target_backed EQUAL 0)
    message(FATAL_ERROR
        "t0_test_set_builds_what_it_runs: not one of the ${t0_selected} T0-selected "
        "registrations was classified as running a build target. That is the shape "
        "this check exists to inspect, so a zero is the check failing to see rather "
        "than a tree with nothing to see.")
endif()

if(t0_failure_count GREATER 0)
    message(FATAL_ERROR
        "t0_test_set_builds_what_it_runs: ${t0_failure_count} T0-selected test(s) "
        "are registered but are not in the t0 build preset's target set:"
        "${t0_failures}")
endif()

message(STATUS
    "t0_test_set_builds_what_it_runs: ${t0_list_count} list file(s) swept, "
    "${t0_registrations} registration(s) found, ${t0_selected} T0-selected, "
    "${t0_target_backed} of those run a build target, and every one of those is "
    "attached to ${T0_AGGREGATE}.")
