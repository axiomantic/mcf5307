# CMake drives Nim. Task CPU-1 creates this file.
#
# The repository ships NIM SOURCE PLUS BUILD INTEGRATION and never a prebuilt
# `.a`. Design section 20.1 gives six integration steps and this file runs them
# in that order, at configure time, reporting each one by number.
#
#   1  Read `.nim-version`, run `nim --version`, fail the configure step on a
#      mismatch and print both versions.
#   2  Run the Nim compiler in compile-only mode with the C backend.
#   3  Read the compile-unit list out of Nim's own JSON build file.
#   4  Add the listed `.c` files to an OBJECT library `mcf5307_nim_objs`.
#   5  Add a STATIC library `mcf5307` that carries those objects and the
#      hand-written public header.
#   6  Export `mcf5307::mcf5307` for consumers.
#
# THE STEPS RUN AT CONFIGURE TIME AND NOT AT BUILD TIME, because steps 4 and 5
# need the unit list to declare their targets, and a CMake target's source list
# is fixed when the target is declared.
#
# `.nim-version` is READ here and owned by CPU-25. The root `CMakeLists.txt` is
# owned by CPU-26 and carries one `include()` of this file.
#
# MIT licensed and clean-room with respect to GPL and LGPL code.

# ---------------------------------------------------------------------------
# Step 1. The version pin.
#
# Design section 5.7 rule 2. Both known audio-Nim precedents broke at a major
# version, so the pin is exact and the mismatch is a configure failure rather
# than a warning.

find_program(MCF5307_NIM_EXECUTABLE nim REQUIRED
    DOC "The Nim compiler that builds the mcf5307 core")

set(MCF5307_NIM_VERSION_FILE "${PROJECT_SOURCE_DIR}/.nim-version")
if(NOT EXISTS "${MCF5307_NIM_VERSION_FILE}")
    message(FATAL_ERROR
        "mcf5307: step 1 failed: ${MCF5307_NIM_VERSION_FILE} does not exist. "
        "The pin is the file, and a build without one is not a pinned build.")
endif()

file(READ "${MCF5307_NIM_VERSION_FILE}" MCF5307_NIM_PIN_RAW)
string(STRIP "${MCF5307_NIM_PIN_RAW}" MCF5307_NIM_PIN)

execute_process(
    COMMAND "${MCF5307_NIM_EXECUTABLE}" --version
    OUTPUT_VARIABLE MCF5307_NIM_VERSION_OUTPUT
    ERROR_VARIABLE MCF5307_NIM_VERSION_ERROR
    RESULT_VARIABLE MCF5307_NIM_VERSION_RESULT)

if(NOT MCF5307_NIM_VERSION_RESULT EQUAL 0)
    message(FATAL_ERROR
        "mcf5307: step 1 failed: `${MCF5307_NIM_EXECUTABLE} --version` exited "
        "${MCF5307_NIM_VERSION_RESULT}.\n${MCF5307_NIM_VERSION_ERROR}")
endif()

# The first line reads `Nim Compiler Version 2.2.10 [MacOSX: arm64]`.
if(NOT MCF5307_NIM_VERSION_OUTPUT MATCHES "Version[ \t]+([0-9]+\\.[0-9]+\\.[0-9]+)")
    message(FATAL_ERROR
        "mcf5307: step 1 failed: no version number was found in the output of "
        "`${MCF5307_NIM_EXECUTABLE} --version`.\n${MCF5307_NIM_VERSION_OUTPUT}")
endif()
set(MCF5307_NIM_INSTALLED "${CMAKE_MATCH_1}")

# BOTH VERSIONS ARE PRINTED, and the message names the file that holds the pin
# and the compiler that answered, so that a mismatch is actionable without a
# second command.
if(NOT MCF5307_NIM_INSTALLED STREQUAL MCF5307_NIM_PIN)
    message(FATAL_ERROR
        "mcf5307: step 1 failed: the Nim version does not match the pin.\n"
        "  pinned    : ${MCF5307_NIM_PIN}  (from ${MCF5307_NIM_VERSION_FILE})\n"
        "  installed : ${MCF5307_NIM_INSTALLED}  (from ${MCF5307_NIM_EXECUTABLE})\n"
        "A major-version migration is scheduled work with its own branch and "
        "its own full conformance run. A minor bump is allowed after the "
        "conformance corpus passes. See docs/nim-version.md.")
endif()

message(STATUS
    "mcf5307: step 1 the Nim version matches the pin: ${MCF5307_NIM_PIN}")

# ---------------------------------------------------------------------------
# Step 2. The compile-only run of the C backend.
#
# THE FLAG SET IS MANDATED AND THERE IS NO `--checks:off` AND NO `-d:danger`.
# With `-d:release` alone the run-time checks stay compiled in. Removing them
# converts a defect that ends the process into a defect that returns a wrong
# value and exits 0, and a wrong answer with exit status 0 inside a CPU core is
# the one outcome this design refuses. Design sections 5.6 and 20.1.

set(MCF5307_NIM_ENTRY "${PROJECT_SOURCE_DIR}/src/mcf5307.nim")
set(MCF5307_NIMCACHE "${PROJECT_BINARY_DIR}/nimcache")
set(MCF5307_NIM_HEADER "mcf5307_nim.h")

# The flags that govern the generated code. They are held apart from the
# command for two reasons. A second Nim project repeats them unchanged, and a
# Nim TEST program must be compiled with the same set: a test compiled with a
# different set proves nothing about the library the set governs.
set(MCF5307_NIM_FLAGS --mm:arc --panics:on -d:release)

# THE NIM ENTRY MODULES OF THIS PROJECT. Design section 5.5 keeps the
# one-project convention and the list holds one name today. A second Nim
# library appends its name here and writes its own command below, with its own
# `--nimMainPrefix:` value. Step 2a reads this list.
set(MCF5307_NIM_ENTRIES mcf5307)

# EACH ENTRY MODULE'S COMMAND IS WRITTEN OUT AND IS NEVER DERIVED FROM THE
# ENTRY NAME. A derived prefix cannot collide, so a derived prefix would make
# the duplicate half of step 2a unable to fail, and a check that cannot fail is
# worse than no check.
set(MCF5307_NIM_COMMAND_mcf5307
    "${MCF5307_NIM_EXECUTABLE}" c
    --compileOnly
    --noMain
    "--nimcache:${MCF5307_NIMCACHE}"
    ${MCF5307_NIM_FLAGS}
    --nimMainPrefix:mcf5307_
    "--header:${MCF5307_NIM_HEADER}"
    "${MCF5307_NIM_ENTRY}")

# ---------------------------------------------------------------------------
# Step 2a. The prefix check. Task CPU-2 adds this block.
#
# `--nimMainPrefix:` renames the Nim runtime entry point of one Nim project.
# Two Nim projects in one binary that keep the default names collide on
# `NimMain`, `NimMainInner` and `NimMainModule` at link. THE FLAG IS WHAT
# PREVENTS THAT COLLISION AND NOTHING IN THIS FILE ENFORCED IT.
#
# WHY THE FAULT MUST BE CAUGHT HERE. With the flag deleted the configure step
# succeeds, the build succeeds and the archive is written, all without one
# diagnostic: a static archive tolerates an undefined symbol, so
# `libmcf5307.a` then carries an undefined `mcf5307_NimMain` beside an
# unprefixed `NimMain`, and nothing fails until a consumer's final link, in a
# different repository, at a later time. The configure step is the last place
# at which the fault is still local to this project.
#
# The check has three steps and only the second one is fatal.
#
#   1  count the entry modules
#   2  assert that every entry module's command carries a `--nimMainPrefix:`
#      and that no two prefixes are equal - FAILS THE CONFIGURE STEP
#   3  when the count is above one, print one line that names the departure
#      from the one-project convention and the build integration it costs -
#      DOES NOT FAIL THE CONFIGURE STEP
#
# IT READS THE COMMANDS AND NOT A SEPARATE DECLARATION OF INTENT. The command
# above is the text that runs, so a check that read anything else could pass
# over a command that had lost the flag.

# Check step 1. The count.
list(LENGTH MCF5307_NIM_ENTRIES MCF5307_NIM_ENTRY_COUNT)
if(MCF5307_NIM_ENTRY_COUNT EQUAL 0)
    message(FATAL_ERROR
        "mcf5307: step 2a failed: MCF5307_NIM_ENTRIES is empty. A build with "
        "no entry module compiles no Nim code at all.")
endif()

# Check step 2. The flag, and the uniqueness of its value.
set(MCF5307_NIM_SEEN_PREFIXES "")
foreach(entry IN LISTS MCF5307_NIM_ENTRIES)
    if(NOT DEFINED MCF5307_NIM_COMMAND_${entry})
        message(FATAL_ERROR
            "mcf5307: step 2a failed: the entry module `${entry}` is listed in "
            "MCF5307_NIM_ENTRIES and MCF5307_NIM_COMMAND_${entry} is not set. "
            "An entry module without a command compiles nothing.")
    endif()
    string(REPLACE ";" " " MCF5307_NIM_ENTRY_COMMAND_TEXT
        "${MCF5307_NIM_COMMAND_${entry}}")
    if(NOT MCF5307_NIM_ENTRY_COMMAND_TEXT MATCHES "--nimMainPrefix:([^ ]+)")
        message(FATAL_ERROR
            "mcf5307: step 2a failed: the compile command of the entry module "
            "`${entry}` carries no --nimMainPrefix: flag.\n"
            "  command : ${MCF5307_NIM_ENTRY_COMMAND_TEXT}\n"
            "Without the flag the Nim runtime keeps its default entry-point "
            "names, the archive still builds, and the fault surfaces at a "
            "consumer's final link. That is why it is refused here.")
    endif()
    set(MCF5307_NIM_ENTRY_PREFIX "${CMAKE_MATCH_1}")
    if(MCF5307_NIM_ENTRY_PREFIX IN_LIST MCF5307_NIM_SEEN_PREFIXES)
        message(FATAL_ERROR
            "mcf5307: step 2a failed: the entry module `${entry}` repeats the "
            "--nimMainPrefix: value `${MCF5307_NIM_ENTRY_PREFIX}`, which an "
            "earlier entry module in MCF5307_NIM_ENTRIES already uses. Two "
            "equal prefixes rename the two runtimes to the SAME names, and "
            "they then collide exactly as the default names do.")
    endif()
    list(APPEND MCF5307_NIM_SEEN_PREFIXES "${MCF5307_NIM_ENTRY_PREFIX}")
    message(STATUS
        "mcf5307: step 2a the entry module ${entry} carries "
        "--nimMainPrefix:${MCF5307_NIM_ENTRY_PREFIX}")
endforeach()

# Check step 3. The one-project convention. IT IS A NOTE AND NOT A FAILURE.
if(MCF5307_NIM_ENTRY_COUNT GREATER 1)
    message(STATUS
        "mcf5307: step 2a NOTE: this build declares ${MCF5307_NIM_ENTRY_COUNT} "
        "Nim entry modules and design section 5.5 keeps one. Each entry module "
        "beyond the first costs its own nimcache directory, its own "
        "compile-unit list, its own object library and its own "
        "`<component>_runtime_init` export. Steps 2 to 6 below build the first "
        "entry module alone.")
endif()

# ---------------------------------------------------------------------------
# Steps 2 to 6 build THE ONE LIBRARY of the one-project convention. The note of
# check step 3 names the integration a second entry module would need.
set(MCF5307_NIM_COMMAND ${MCF5307_NIM_COMMAND_mcf5307})

# The command is printed in full, BEFORE it runs, so that a failing run leaves
# the exact invocation in the log. The prefix and the two absent flags are then
# a property of the configure log rather than a claim about this file.
#
# The line does NOT carry a step number. Each step reports itself exactly once,
# and a reader who counts the step lines gets the six steps and their order.
string(REPLACE ";" " " MCF5307_NIM_COMMAND_TEXT "${MCF5307_NIM_COMMAND}")
message(STATUS "mcf5307: nim invocation: ${MCF5307_NIM_COMMAND_TEXT}")

# Editing a Nim source must re-run the configure step, because the unit list is
# read at configure time and a new module adds a unit to it.
file(GLOB_RECURSE MCF5307_NIM_SOURCES CONFIGURE_DEPENDS
    "${PROJECT_SOURCE_DIR}/src/*.nim")
set_property(DIRECTORY "${PROJECT_SOURCE_DIR}"
    APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
    ${MCF5307_NIM_SOURCES} "${MCF5307_NIM_VERSION_FILE}")

execute_process(
    COMMAND ${MCF5307_NIM_COMMAND}
    WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}"
    OUTPUT_VARIABLE MCF5307_NIM_OUTPUT
    ERROR_VARIABLE MCF5307_NIM_ERROR
    RESULT_VARIABLE MCF5307_NIM_RESULT)

if(NOT MCF5307_NIM_RESULT EQUAL 0)
    message(FATAL_ERROR
        "mcf5307: step 2 failed: the Nim compiler exited "
        "${MCF5307_NIM_RESULT}.\n${MCF5307_NIM_OUTPUT}\n${MCF5307_NIM_ERROR}")
endif()

message(STATUS "mcf5307: step 2 the Nim compile-only run succeeded")

# ---------------------------------------------------------------------------
# Step 3. The compile-unit list.
#
# NIM'S OWN JSON BUILD FILE IS THE LIST AND A GLOB OF THE CACHE IS NOT. A glob
# picks up a stale `.c` left by an earlier build with a different module set,
# and a stale unit that still defines its module's symbols produces a duplicate
# symbol at link. The JSON names exactly the units of THIS run.

get_filename_component(MCF5307_NIM_PROJECT_NAME "${MCF5307_NIM_ENTRY}" NAME_WE)
set(MCF5307_NIM_JSON "${MCF5307_NIMCACHE}/${MCF5307_NIM_PROJECT_NAME}.json")

if(NOT EXISTS "${MCF5307_NIM_JSON}")
    message(FATAL_ERROR
        "mcf5307: step 3 failed: the Nim build file ${MCF5307_NIM_JSON} does "
        "not exist. The unit list is read from that file and is never globbed "
        "out of the cache directory.")
endif()

file(READ "${MCF5307_NIM_JSON}" MCF5307_NIM_JSON_TEXT)
string(JSON MCF5307_NIM_UNIT_COUNT LENGTH "${MCF5307_NIM_JSON_TEXT}" compile)

if(MCF5307_NIM_UNIT_COUNT EQUAL 0)
    message(FATAL_ERROR
        "mcf5307: step 3 failed: ${MCF5307_NIM_JSON} lists no compile unit. An "
        "empty object library would link and would carry no Nim code at all.")
endif()

# Each entry of `compile` is a pair: the generated `.c` file, then the command
# Nim would have used to compile it. Element 0 is taken and element 1 is
# discarded, because the consumer's own toolchain and flags compile these
# sources. That is the whole point of shipping source plus integration.
set(MCF5307_NIM_C_SOURCES "")
math(EXPR MCF5307_NIM_LAST_UNIT "${MCF5307_NIM_UNIT_COUNT} - 1")
foreach(index RANGE ${MCF5307_NIM_LAST_UNIT})
    string(JSON MCF5307_NIM_UNIT GET
        "${MCF5307_NIM_JSON_TEXT}" compile ${index} 0)
    if(NOT EXISTS "${MCF5307_NIM_UNIT}")
        message(FATAL_ERROR
            "mcf5307: step 3 failed: ${MCF5307_NIM_JSON} lists the compile "
            "unit ${MCF5307_NIM_UNIT} and that file does not exist.")
    endif()
    list(APPEND MCF5307_NIM_C_SOURCES "${MCF5307_NIM_UNIT}")
endforeach()

message(STATUS
    "mcf5307: step 3 read ${MCF5307_NIM_UNIT_COUNT} compile units from "
    "${MCF5307_NIM_JSON}")

# ---------------------------------------------------------------------------
# Step 4. The object library.
#
# The generated C includes `nimbase.h` from the Nim installation and the
# generated `mcf5307_nim.h` from the cache. The Nim library directory is
# derived from the compiler's own location, which is how Nim itself finds it,
# and the derivation is CHECKED rather than assumed.

get_filename_component(MCF5307_NIM_BIN_DIR "${MCF5307_NIM_EXECUTABLE}" DIRECTORY)
get_filename_component(MCF5307_NIM_PREFIX "${MCF5307_NIM_BIN_DIR}" DIRECTORY)
set(MCF5307_NIM_LIB_DIR "${MCF5307_NIM_PREFIX}/lib")

if(NOT EXISTS "${MCF5307_NIM_LIB_DIR}/nimbase.h")
    message(FATAL_ERROR
        "mcf5307: step 4 failed: nimbase.h was not found in "
        "${MCF5307_NIM_LIB_DIR}. Every generated C unit includes that header, "
        "so the directory is derived from ${MCF5307_NIM_EXECUTABLE} and then "
        "checked, and this is the check.")
endif()

add_library(mcf5307_nim_objs OBJECT ${MCF5307_NIM_C_SOURCES})

# The generated C is a build product and is not this project's own source. It
# is not held to this project's warning policy, and a Nim release changing its
# output must not turn into a build failure here.
target_include_directories(mcf5307_nim_objs PRIVATE
    "${MCF5307_NIM_LIB_DIR}"
    "${MCF5307_NIMCACHE}"
    "${PROJECT_SOURCE_DIR}/src")
set_target_properties(mcf5307_nim_objs PROPERTIES
    C_STANDARD 11
    POSITION_INDEPENDENT_CODE ON)

# Nim 2.2 builds with `threads:on` by default and the generated runtime names
# pthread symbols.
set(THREADS_PREFER_PTHREAD_FLAG ON)
find_package(Threads REQUIRED)
target_link_libraries(mcf5307_nim_objs PUBLIC Threads::Threads)

message(STATUS "mcf5307: step 4 the object library mcf5307_nim_objs is defined")

# ---------------------------------------------------------------------------
# Step 5. The static library.
#
# It carries the objects of step 4 and the HAND-WRITTEN public header. The
# generated `mcf5307_nim.h` is not the contract and is not published: the
# contract is `include/mcf5307.h`, which is reviewed as one file.

add_library(mcf5307 STATIC $<TARGET_OBJECTS:mcf5307_nim_objs>)

target_include_directories(mcf5307 PUBLIC
    "$<BUILD_INTERFACE:${PROJECT_SOURCE_DIR}/include>"
    "$<INSTALL_INTERFACE:include>")
target_link_libraries(mcf5307 PUBLIC Threads::Threads)
set_target_properties(mcf5307 PROPERTIES
    LINKER_LANGUAGE C
    PUBLIC_HEADER "${PROJECT_SOURCE_DIR}/include/mcf5307.h")

message(STATUS "mcf5307: step 5 the static library mcf5307 is defined")

# ---------------------------------------------------------------------------
# Step 6. The consumer-facing name.
#
# A consumer writes `mcf5307::mcf5307` whether it brings this project in with
# `FetchContent` or finds an installed one, and the double-colon name is also
# what makes a misspelling a CMake error instead of a `-lmcf5307` passed to the
# linker unchanged.

add_library(mcf5307::mcf5307 ALIAS mcf5307)

message(STATUS "mcf5307: step 6 the target mcf5307::mcf5307 is exported")
