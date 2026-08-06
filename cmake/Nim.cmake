# CMake drives Nim. Task CPU-1 creates this file.
#
# The repository ships Nim source plus build integration, and never a prebuilt
# `.a`. Design section 20.1 gives six integration steps. This file runs them in
# that order, at configure time, and reports each one by number.
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
# The steps run at configure time and not at build time. Steps 4 and 5 need the
# unit list to declare their targets, and a CMake target's source list is fixed
# when the target is declared.
#
# `.nim-version` is read here and owned by CPU-25. The root `CMakeLists.txt` is
# owned by CPU-26 and carries one `include()` of this file.
#
# MIT licensed and clean-room with respect to GPL and LGPL code.

# ---------------------------------------------------------------------------
# A shell-safe rendering of a command list.
#
# `string(REPLACE ";" " ")` joins the arguments and drops their quoting. A path
# that holds a space then prints as two arguments, and the printed line cannot
# be run. This function quotes an argument that holds white space, a quotation
# mark or nothing at all, so that the printed line stays runnable.
function(mcf5307_render_command mcf5307_render_output)
    set(mcf5307_render_text "")
    foreach(mcf5307_render_argument IN LISTS ARGN)
        if(mcf5307_render_argument STREQUAL ""
                OR mcf5307_render_argument MATCHES "[ \t\r\n\"\\\\]")
            string(REPLACE "\\" "\\\\"
                mcf5307_render_argument "${mcf5307_render_argument}")
            string(REPLACE "\"" "\\\""
                mcf5307_render_argument "${mcf5307_render_argument}")
            set(mcf5307_render_argument "\"${mcf5307_render_argument}\"")
        endif()
        if(mcf5307_render_text STREQUAL "")
            set(mcf5307_render_text "${mcf5307_render_argument}")
        else()
            string(APPEND mcf5307_render_text " ${mcf5307_render_argument}")
        endif()
    endforeach()
    set(${mcf5307_render_output} "${mcf5307_render_text}" PARENT_SCOPE)
endfunction()

# ---------------------------------------------------------------------------
# The head of a captured stream, for a failure message.
#
# A `nim dump` report is a single JSON line of about ten kilobytes, and both
# of its streams go into one failure message. A reader who has just been
# stopped cannot read twenty kilobytes. This function keeps the head and says
# how much it dropped, so that the whole amount stays in the message.
function(mcf5307_clip mcf5307_clip_output mcf5307_clip_text mcf5307_clip_limit)
    string(LENGTH "${mcf5307_clip_text}" mcf5307_clip_length)
    if(mcf5307_clip_length GREATER mcf5307_clip_limit)
        string(SUBSTRING "${mcf5307_clip_text}" 0 ${mcf5307_clip_limit}
            mcf5307_clip_text)
        string(APPEND mcf5307_clip_text
            " [... ${mcf5307_clip_length} bytes in all,"
            " ${mcf5307_clip_limit} shown]")
    endif()
    set(${mcf5307_clip_output} "${mcf5307_clip_text}" PARENT_SCOPE)
endfunction()

# ---------------------------------------------------------------------------
# Step 1. The version pin.
#
# Design section 5.7 rule 2. Both known audio-Nim precedents broke at a major
# version. The pin is therefore exact, and a mismatch fails the configure step
# instead of raising a warning.

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

# Both streams are printed on every failure path below. A compiler that fails
# to start writes to one of them. A compiler that answers oddly writes to the
# other. This file cannot tell in advance which one holds the evidence.
if(NOT MCF5307_NIM_VERSION_RESULT EQUAL 0)
    message(FATAL_ERROR
        "mcf5307: step 1 failed: `${MCF5307_NIM_EXECUTABLE} --version` exited "
        "${MCF5307_NIM_VERSION_RESULT}.\n"
        "  stdout : ${MCF5307_NIM_VERSION_OUTPUT}\n"
        "  stderr : ${MCF5307_NIM_VERSION_ERROR}")
endif()

# The version is read from the first line alone. That line reads
# `Nim Compiler Version 2.2.10 [MacOSX: arm64]`. A match over the whole output
# would take the first version-shaped number anywhere in it. That includes a
# number in a later line, which this file does not control.
string(REGEX REPLACE "\r?\n.*" "" MCF5307_NIM_VERSION_FIRST_LINE
    "${MCF5307_NIM_VERSION_OUTPUT}")

if(NOT MCF5307_NIM_VERSION_FIRST_LINE MATCHES
        "Version[ \t]+([0-9]+\\.[0-9]+\\.[0-9]+)")
    message(FATAL_ERROR
        "mcf5307: step 1 failed: no version number was found in the first line "
        "of the output of `${MCF5307_NIM_EXECUTABLE} --version`.\n"
        "  first line : ${MCF5307_NIM_VERSION_FIRST_LINE}\n"
        "  stdout     : ${MCF5307_NIM_VERSION_OUTPUT}\n"
        "  stderr     : ${MCF5307_NIM_VERSION_ERROR}")
endif()
set(MCF5307_NIM_INSTALLED "${CMAKE_MATCH_1}")

# Both versions are printed. The message names the file that holds the pin and
# the compiler that answered, so that a mismatch is actionable without a second
# command.
if(NOT MCF5307_NIM_INSTALLED STREQUAL MCF5307_NIM_PIN)
    message(FATAL_ERROR
        "mcf5307: step 1 failed: the Nim version does not match the pin.\n"
        "  pinned    : ${MCF5307_NIM_PIN}  (from ${MCF5307_NIM_VERSION_FILE})\n"
        "  installed : ${MCF5307_NIM_INSTALLED}  (from ${MCF5307_NIM_EXECUTABLE})\n"
        "A major-version migration is scheduled work with its own branch and "
        "its own full conformance run. A minor bump is allowed after the "
        "conformance corpus passes. To move the pin, edit "
        "${MCF5307_NIM_VERSION_FILE} in the change that runs that corpus.")
endif()

message(STATUS
    "mcf5307: step 1 the Nim version matches the pin: ${MCF5307_NIM_PIN}")

# ---------------------------------------------------------------------------
# Step 2. The compile-only run of the C backend.
#
# The flag set is mandated. It holds no `--checks:off` and no `-d:danger`. With
# `-d:release` alone the run-time checks stay compiled in. Removing them turns
# a defect that ends the process into a defect that returns a wrong value and
# exits 0. A wrong answer with exit status 0 inside a CPU core is the one
# outcome this design refuses. Design sections 5.6 and 20.1.

set(MCF5307_NIMCACHE "${PROJECT_BINARY_DIR}/nimcache")
set(MCF5307_NIM_HEADER "mcf5307_nim.h")

# The flags that govern the generated code. They are held apart from the
# command for two reasons. A second Nim project repeats them unchanged, and a
# Nim test program must be compiled with the same set. A test compiled with a
# different set proves nothing about the library the set governs.
set(MCF5307_NIM_FLAGS --mm:arc --panics:on -d:release)

# The Nim entry modules of this project. Design section 5.5 keeps the
# one-project convention and the list holds one name today. A second Nim
# library appends its name here and writes its own command below, with its own
# `--nimMainPrefix:` value. Step 2a reads this list.
set(MCF5307_NIM_ENTRIES mcf5307)

# Each entry module's source file and its command are written out, and neither
# is derived from the entry name. A derived prefix cannot collide. It would
# therefore make the duplicate half of step 2a unable to fail. A check that
# cannot fail is worse than no check.
set(MCF5307_NIM_SOURCE_mcf5307 "${PROJECT_SOURCE_DIR}/src/mcf5307.nim")
set(MCF5307_NIM_COMMAND_mcf5307
    "${MCF5307_NIM_EXECUTABLE}" c
    --compileOnly
    --noMain
    "--nimcache:${MCF5307_NIMCACHE}"
    ${MCF5307_NIM_FLAGS}
    --nimMainPrefix:mcf5307_
    "--header:${MCF5307_NIM_HEADER}"
    "${MCF5307_NIM_SOURCE_mcf5307}")

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
    if(NOT DEFINED MCF5307_NIM_SOURCE_${entry})
        message(FATAL_ERROR
            "mcf5307: step 2a failed: the entry module `${entry}` is listed in "
            "MCF5307_NIM_ENTRIES and MCF5307_NIM_SOURCE_${entry} is not set. "
            "Steps 3 and 4 read that path. Step 3 takes the name of Nim's own "
            "build file from it, and step 4 asks the compiler about it.")
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
    # The value is stored under the entry module's own name. A single loop
    # variable would hold the LAST entry module's prefix after the loop. Any
    # later reader of it would then read the wrong entry module's value.
    set(MCF5307_NIM_PREFIX_${entry} "${CMAKE_MATCH_1}")
    if(MCF5307_NIM_PREFIX_${entry} IN_LIST MCF5307_NIM_SEEN_PREFIXES)
        message(FATAL_ERROR
            "mcf5307: step 2a failed: the entry module `${entry}` repeats the "
            "--nimMainPrefix: value `${MCF5307_NIM_PREFIX_${entry}}`, which an "
            "earlier entry module in MCF5307_NIM_ENTRIES already uses. Two "
            "equal prefixes rename the two runtimes to the SAME names, and "
            "they then collide exactly as the default names do.")
    endif()
    list(APPEND MCF5307_NIM_SEEN_PREFIXES "${MCF5307_NIM_PREFIX_${entry}}")
    message(STATUS
        "mcf5307: step 2a the entry module ${entry} carries "
        "--nimMainPrefix:${MCF5307_NIM_PREFIX_${entry}}")
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
# Steps 2 to 6 build the one library of the one-project convention. The note of
# check step 3 names the integration a second entry module would need.
#
# THE ENTRY MODULE THEY BUILD IS THE FIRST ONE IN MCF5307_NIM_ENTRIES, and the
# note above says exactly that. A name written out here instead would make the
# note false as soon as the list held a second name. The pass or the failure of
# this file would then depend on the order of that list alone.
list(GET MCF5307_NIM_ENTRIES 0 MCF5307_NIM_BUILT_ENTRY)
set(MCF5307_NIM_COMMAND ${MCF5307_NIM_COMMAND_${MCF5307_NIM_BUILT_ENTRY}})
set(MCF5307_NIM_ENTRY "${MCF5307_NIM_SOURCE_${MCF5307_NIM_BUILT_ENTRY}}")
set(MCF5307_NIM_BUILT_PREFIX "${MCF5307_NIM_PREFIX_${MCF5307_NIM_BUILT_ENTRY}}")

# The command is printed in full, before it runs, so that a failing run leaves
# the exact invocation in the log. The prefix and the two absent flags are then
# a property of the configure log rather than a claim about this file.
#
# The line carries no step number. Each step reports itself exactly once, and a
# reader who counts the step lines gets the six steps and their order.
mcf5307_render_command(MCF5307_NIM_COMMAND_TEXT ${MCF5307_NIM_COMMAND})
message(STATUS "mcf5307: nim invocation: ${MCF5307_NIM_COMMAND_TEXT}")

# Editing a Nim source must re-run the configure step. The unit list is read at
# configure time, and a new module adds a unit to it.
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
# Nim's own JSON build file is the list, and a glob of the cache is not. A glob
# picks up a stale `.c` left by an earlier build with a different module set. A
# stale unit that still defines its module's symbols produces a duplicate
# symbol at link. The JSON names exactly the units of the run that just ran.

get_filename_component(MCF5307_NIM_PROJECT_NAME "${MCF5307_NIM_ENTRY}" NAME_WE)
set(MCF5307_NIM_JSON "${MCF5307_NIMCACHE}/${MCF5307_NIM_PROJECT_NAME}.json")

if(NOT EXISTS "${MCF5307_NIM_JSON}")
    message(FATAL_ERROR
        "mcf5307: step 3 failed: the Nim build file ${MCF5307_NIM_JSON} does "
        "not exist. The unit list is read from that file and is never globbed "
        "out of the cache directory.")
endif()

file(READ "${MCF5307_NIM_JSON}" MCF5307_NIM_JSON_TEXT)

# The schema of the build file belongs to the Nim release and not to this
# project. `ERROR_VARIABLE` is what turns a schema change into a diagnostic
# that names the step and the member. Without it CMake raises its own error,
# the configure log holds no step number, and the reader has to find the step.
string(JSON MCF5307_NIM_UNIT_COUNT
    ERROR_VARIABLE MCF5307_NIM_JSON_ERROR
    LENGTH "${MCF5307_NIM_JSON_TEXT}" compile)
if(NOT MCF5307_NIM_JSON_ERROR STREQUAL "NOTFOUND")
    message(FATAL_ERROR
        "mcf5307: step 3 failed: ${MCF5307_NIM_JSON} carries no readable "
        "`compile` array.\n"
        "  error : ${MCF5307_NIM_JSON_ERROR}\n"
        "The member is the unit list of the run that just ran. A Nim release "
        "that renames it needs this step read the new name.")
endif()

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
    string(JSON MCF5307_NIM_UNIT
        ERROR_VARIABLE MCF5307_NIM_JSON_ERROR
        GET "${MCF5307_NIM_JSON_TEXT}" compile ${index} 0)
    if(NOT MCF5307_NIM_JSON_ERROR STREQUAL "NOTFOUND")
        message(FATAL_ERROR
            "mcf5307: step 3 failed: entry ${index} of the `compile` array of "
            "${MCF5307_NIM_JSON} does not hold a file name at element 0.\n"
            "  error : ${MCF5307_NIM_JSON_ERROR}")
    endif()
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
# The generated C includes `nimbase.h` from the Nim installation. Measured on
# Nim 2.2.10, that is the only header of the toolchain the units name, and
# every other header they name is a system header. One unit compiled with the
# Nim library directory as its sole `-I` confirms it. The cache directory is
# therefore not on the search path here. The units live in that directory, and
# a quoted include resolves against the including file's own directory first.
#
# The compiler reports its own library directory. `nim dump --dump.format:json`
# prints a JSON object whose `libpath` member is the directory Nim uses. Asking
# the compiler is the only route that holds for every installation.
#
# A path walk from the executable is the fallback and not the first choice.
# `get_filename_component` does not resolve a symlink, so the walk is wrong for
# choosenim, which `.github/workflows/ci.yml` installs on ubuntu-latest and
# whose `~/.nimble/bin/nim` is a symlink. It is wrong for a mise shim, for
# Homebrew and for `update-alternatives`. It is wrong for a Debian or Ubuntu
# package, where `nim` is `/usr/bin/nim` and the library is `/usr/lib/nim`,
# which no walk from `bin` reaches. The fallback resolves the symlink first and
# then covers the layout that keeps `lib` beside `bin`.

execute_process(
    COMMAND "${MCF5307_NIM_EXECUTABLE}" dump --dump.format:json
            "${MCF5307_NIM_ENTRY}"
    OUTPUT_VARIABLE MCF5307_NIM_DUMP_OUTPUT
    ERROR_VARIABLE MCF5307_NIM_DUMP_ERROR
    RESULT_VARIABLE MCF5307_NIM_DUMP_RESULT)

set(MCF5307_NIM_LIB_DIR "")
set(MCF5307_NIM_LIB_DIR_SOURCE "")
if(MCF5307_NIM_DUMP_RESULT EQUAL 0)
    string(JSON MCF5307_NIM_DUMP_LIBPATH
        ERROR_VARIABLE MCF5307_NIM_DUMP_JSON_ERROR
        GET "${MCF5307_NIM_DUMP_OUTPUT}" libpath)
    if(MCF5307_NIM_DUMP_JSON_ERROR STREQUAL "NOTFOUND"
            AND NOT MCF5307_NIM_DUMP_LIBPATH STREQUAL "")
        set(MCF5307_NIM_LIB_DIR "${MCF5307_NIM_DUMP_LIBPATH}")
        set(MCF5307_NIM_LIB_DIR_SOURCE
            "`${MCF5307_NIM_EXECUTABLE} dump --dump.format:json`")
    endif()
endif()

# The fallback. It runs when the compiler gave no usable answer, and also when
# the answer it gave holds no `nimbase.h`.
if(MCF5307_NIM_LIB_DIR STREQUAL ""
        OR NOT EXISTS "${MCF5307_NIM_LIB_DIR}/nimbase.h")
    get_filename_component(MCF5307_NIM_REAL_EXECUTABLE
        "${MCF5307_NIM_EXECUTABLE}" REALPATH)
    get_filename_component(MCF5307_NIM_BIN_DIR
        "${MCF5307_NIM_REAL_EXECUTABLE}" DIRECTORY)
    get_filename_component(MCF5307_NIM_PREFIX
        "${MCF5307_NIM_BIN_DIR}" DIRECTORY)
    if(EXISTS "${MCF5307_NIM_PREFIX}/lib/nimbase.h")
        set(MCF5307_NIM_LIB_DIR "${MCF5307_NIM_PREFIX}/lib")
        set(MCF5307_NIM_LIB_DIR_SOURCE
            "a path walk from ${MCF5307_NIM_REAL_EXECUTABLE}")
    endif()
endif()

# The result is checked and never assumed, whichever route produced it.
if(MCF5307_NIM_LIB_DIR STREQUAL ""
        OR NOT EXISTS "${MCF5307_NIM_LIB_DIR}/nimbase.h")
    mcf5307_clip(MCF5307_NIM_DUMP_OUTPUT_HEAD
        "${MCF5307_NIM_DUMP_OUTPUT}" 400)
    mcf5307_clip(MCF5307_NIM_DUMP_ERROR_HEAD "${MCF5307_NIM_DUMP_ERROR}" 400)
    message(FATAL_ERROR
        "mcf5307: step 4 failed: nimbase.h was not found. Every generated C "
        "unit includes that header.\n"
        "  compiler       : ${MCF5307_NIM_EXECUTABLE}\n"
        "  dump exit      : ${MCF5307_NIM_DUMP_RESULT}\n"
        "  dump stdout    : ${MCF5307_NIM_DUMP_OUTPUT_HEAD}\n"
        "  dump stderr    : ${MCF5307_NIM_DUMP_ERROR_HEAD}\n"
        "  directory tried: ${MCF5307_NIM_LIB_DIR}\n"
        "The directory comes from the compiler's own `dump` report, and a path "
        "walk from the resolved executable is the fallback. Both streams are "
        "cut to their head. The full report is one JSON line of about ten "
        "kilobytes, and it names the same directory this message already "
        "names.")
endif()

message(STATUS
    "mcf5307: step 4 the Nim library directory is ${MCF5307_NIM_LIB_DIR} "
    "(from ${MCF5307_NIM_LIB_DIR_SOURCE})")

add_library(mcf5307_nim_objs OBJECT ${MCF5307_NIM_C_SOURCES})

# The generated C is a build product and is not this project's own source. Two
# mechanisms hold it apart from this project's warning policy. This text
# replaces a comment that claimed the separation and supplied neither.
#
#   `SYSTEM` marks the Nim library directory as a system include directory, so
#   a warning raised inside `nimbase.h` is suppressed.
#
#   `-Wno-error`, or `/WX-` for MSVC, disarms a `-Werror` a consumer set in
#   `CMAKE_C_FLAGS`. It is appended after those flags, so it wins. Measured:
#   without it, a configure with `-Wall -Wextra -Werror` builds until Nim's own
#   `digitsutils.nim.c` raises `variable 'T1_' set but not used`, and the build
#   fails.
#
# THE FLAG IS `-Wno-error` AND NOT `-w`. The requirement is to stop a
# consumer's `-Werror` from failing a build over code this project compiles
# and does not author. `-w` would also delete the diagnostics themselves.
# Measured with `-Wall -Wextra -Werror`: both flags build clean, `-Wno-error`
# leaves the warnings in the build log and `-w` leaves none there. A count is
# not written here, because an edit to `src/mcf5307.nim` changes it. A silent
# warning channel over the one body of code nobody here reviews is the worse
# trade.
#
# The collision is scheduled and not hypothetical. `tests/tests_cpu.cmake`
# already compiles with `-Wall -Wextra -pedantic -Werror`.
target_include_directories(mcf5307_nim_objs SYSTEM PRIVATE
    "${MCF5307_NIM_LIB_DIR}")
target_compile_options(mcf5307_nim_objs PRIVATE
    "$<IF:$<C_COMPILER_ID:MSVC>,/WX-,-Wno-error>")
set_target_properties(mcf5307_nim_objs PROPERTIES
    C_STANDARD 11
    POSITION_INDEPENDENT_CODE ON)

# Nim 2.2 builds with threads on. Measured on Nim 2.2.10, the unit list holds
# `std/typedthreads`, which is what that setting puts there.
#
# The generated runtime names no thread function of its own. `nm` over the
# archive reports zero matches for `pthread`. The positive control of that zero
# is another symbol of the same run, and it is not a count of that symbol: the
# same `nm` command reports matches for `__tlv_bootstrap`, so the command did
# read the archive. A count is not written here. An edit to `src/mcf5307.nim`
# changes it, and the `{.threadvar.}` in that file already put
# `__tlv_bootstrap` into a further object.
#
# Nim's own link command in the JSON build file carries `-ldl` and no
# `-lpthread`. The thread-local storage the runtime uses goes through the
# platform's own mechanism.
#
# The dependency is kept and is not required. A host that holds the thread
# functions in a separate library needs the flag once a later cpu task creates
# a thread. A host without a thread library configures today, because nothing
# in the current object set calls into one.
set(THREADS_PREFER_PTHREAD_FLAG ON)
find_package(Threads)
if(TARGET Threads::Threads)
    target_link_libraries(mcf5307_nim_objs PUBLIC Threads::Threads)
endif()

message(STATUS "mcf5307: step 4 the object library mcf5307_nim_objs is defined")

# ---------------------------------------------------------------------------
# Step 4a. The visibility check.
#
# A published symbol has to reach a consumer through a shared object, because
# the delivery form is a JUCE plugin. Nim decides that in the pragma set of the
# declaration. Measured on Nim 2.2.10:
#
#   procedure  {.exportc, cdecl.}           ->  N_LIB_PRIVATE
#   procedure  {.exportc, cdecl, dynlib.}   ->  N_LIB_EXPORT
#   variable   {.exportc.}                  ->  N_LIB_PRIVATE
#   variable   {.exportc, dynlib.}          ->  N_LIB_EXPORT_VAR
#
# `nimbase.h` defines `N_LIB_PRIVATE` as `visibility("hidden")` for gcc and
# clang. It defines both export forms as `visibility("default")`.
#
# No check that exists could see that fault. `nm` over the static archive
# reports a hidden symbol as `T`, and the smoke test of CPU-3 links statically.
# A shared object built from the archive is the first thing that reports it,
# and nothing in this project builds one. This check reads the generated C
# instead, where the decision is plain text.
#
# THE PUBLISHED SET COMES FROM `include/mcf5307.h` AND NOT FROM A PREFIX. That
# header is the contract, and it publishes two families of names: nine that
# start `mcf5307_` and nine that start `isp1181_`. A check scoped to one
# prefix reports nothing at all about the other nine. A positive control
# scoped to that same prefix cannot report the gap either, because it shares
# the assumption it is there to guard. That pair is the fault this block ends.
#
# `include/mcf5307.h` belongs to CPU-0. It is read here and never written here.
#
# The storage class comes from the generated `.c` units, where `N_LIB_EXPORT`,
# `N_LIB_EXPORT_VAR` and `N_LIB_PRIVATE` are the visibility attribute itself.

# ---------------------------------------------------------------------------
# The scanner for one generated C file.
#
# It returns one `<storage>|<name>` token for every file-scope declaration or
# definition it reads. `<storage>` is the visibility macro that opens the line,
# or `none` when the line opens with no such macro. Neither field can hold a
# `;`, so the result is a list CMake can carry without damage.
#
# IT STRIPS C COMMENTS AND IT CARRIES THE BLOCK-COMMENT STATE FROM LINE TO
# LINE. Without that state a declaration inside a comment that spans lines
# reads as a declaration, and it is not one.
#
# It does not evaluate `#if`, `#ifdef` or any other conditional. A declaration
# inside `#if 0` is read as a live declaration. That limit is written down
# here, and it is not repaired here: a real answer needs a real preprocessor.
function(mcf5307_abi_scan mcf5307_scan_output mcf5307_scan_file)
    set(mcf5307_scan_result "")
    set(mcf5307_scan_open FALSE)
    file(STRINGS "${mcf5307_scan_file}" mcf5307_scan_lines)
    foreach(mcf5307_scan_line IN LISTS mcf5307_scan_lines)
        if(mcf5307_scan_open)
            if(mcf5307_scan_line MATCHES "\\*/(.*)$")
                set(mcf5307_scan_line "${CMAKE_MATCH_1}")
                set(mcf5307_scan_open FALSE)
            else()
                continue()
            endif()
        endif()
        string(REGEX REPLACE "/\\*[^*]*\\*+([^/*][^*]*\\*+)*/" ""
            mcf5307_scan_line "${mcf5307_scan_line}")
        if(mcf5307_scan_line MATCHES "^(.*)/\\*")
            set(mcf5307_scan_line "${CMAKE_MATCH_1}")
            set(mcf5307_scan_open TRUE)
        endif()
        string(REGEX REPLACE "//.*$" "" mcf5307_scan_line
            "${mcf5307_scan_line}")

        # A procedure: an optional visibility macro, then Nim's own calling
        # convention macro, then the name, then the parameter list.
        if(mcf5307_scan_line MATCHES
"^(N_LIB_EXPORT|N_LIB_EXPORT_VAR|N_LIB_PRIVATE|N_LIB_IMPORT)?[ \t]*N_[A-Z_]+\\(.*,[ \t]*([A-Za-z_][A-Za-z0-9_]*)\\)\\(")
            set(mcf5307_scan_storage "${CMAKE_MATCH_1}")
            set(mcf5307_scan_name "${CMAKE_MATCH_2}")
        # An object. The visibility macro is REQUIRED here and not optional.
        # Every `exportc` variable carries one, measured above, and a line with
        # no macro at all is any C declaration whatever.
        elseif(mcf5307_scan_line MATCHES
"^(N_LIB_EXPORT_VAR|N_LIB_PRIVATE|N_LIB_IMPORT)[ \t]+[^;]*[ \t*]([A-Za-z_][A-Za-z0-9_]*)[ \t]*(\\[[^]]*\\])?[ \t]*;")
            set(mcf5307_scan_storage "${CMAKE_MATCH_1}")
            set(mcf5307_scan_name "${CMAKE_MATCH_2}")
        else()
            continue()
        endif()
        if(mcf5307_scan_storage STREQUAL "")
            set(mcf5307_scan_storage "none")
        endif()
        list(APPEND mcf5307_scan_result
            "${mcf5307_scan_storage}|${mcf5307_scan_name}")
    endforeach()
    list(REMOVE_DUPLICATES mcf5307_scan_result)
    set(${mcf5307_scan_output} "${mcf5307_scan_result}" PARENT_SCOPE)
endfunction()

# ---------------------------------------------------------------------------
# The reader for the contract header.
#
# A C declaration spans as many lines as it likes, so this reader works on
# statements and not on lines. It strips the comments first, drops the lines a
# statement must not absorb, and then splits on the semicolon. A CMake string
# that holds semicolons IS a list, so the split needs no further work.
#
# It skips `typedef`, `struct`, `union` and `enum`. Those name a type and they
# publish no symbol. What is left is a function declaration or an `extern`
# object declaration, and both are read.
#
# IT ACCOUNTS FOR EVERY STATEMENT AND IT DROPS NONE IN SILENCE. A statement it
# can neither skip nor read goes into the second output, and control 1 stops
# the configure step over it. A reader that finds most names and loses the rest
# is the fault this step repairs. It is the same fault, one level up.
function(mcf5307_abi_contract mcf5307_contract_output mcf5307_contract_unread
        mcf5307_contract_file)
    set(mcf5307_contract_text "")
    set(mcf5307_contract_open FALSE)
    file(STRINGS "${mcf5307_contract_file}" mcf5307_contract_lines)
    foreach(mcf5307_contract_line IN LISTS mcf5307_contract_lines)
        if(mcf5307_contract_open)
            if(mcf5307_contract_line MATCHES "\\*/(.*)$")
                set(mcf5307_contract_line "${CMAKE_MATCH_1}")
                set(mcf5307_contract_open FALSE)
            else()
                continue()
            endif()
        endif()
        string(REGEX REPLACE "/\\*[^*]*\\*+([^/*][^*]*\\*+)*/" ""
            mcf5307_contract_line "${mcf5307_contract_line}")
        if(mcf5307_contract_line MATCHES "^(.*)/\\*")
            set(mcf5307_contract_line "${CMAKE_MATCH_1}")
            set(mcf5307_contract_open TRUE)
        endif()
        string(REGEX REPLACE "//.*$" "" mcf5307_contract_line
            "${mcf5307_contract_line}")

        # A preprocessor line, the `extern "C"` opener and a lone closing brace
        # all carry no semicolon. Each would otherwise join the statement that
        # follows it and change what that statement looks like.
        if(mcf5307_contract_line MATCHES "^[ \t]*#")
            continue()
        endif()
        if(mcf5307_contract_line MATCHES "^[ \t]*extern[ \t]+\"C\"")
            continue()
        endif()
        if(mcf5307_contract_line MATCHES "^[ \t]*\\}[ \t]*$")
            continue()
        endif()
        string(APPEND mcf5307_contract_text "${mcf5307_contract_line}\n")
    endforeach()

    set(mcf5307_contract_result "")
    set(mcf5307_contract_lost "")
    foreach(mcf5307_contract_statement IN LISTS mcf5307_contract_text)
        string(REGEX REPLACE "[ \t\r\n]+" " " mcf5307_contract_statement
            "${mcf5307_contract_statement}")
        string(STRIP "${mcf5307_contract_statement}"
            mcf5307_contract_statement)
        if(mcf5307_contract_statement STREQUAL "")
            continue()
        endif()
        if(mcf5307_contract_statement MATCHES "^(typedef|struct|union|enum)[ ]")
            continue()
        endif()
        if(mcf5307_contract_statement MATCHES
                "([A-Za-z_][A-Za-z0-9_]*)[ ]*\\(.*\\)$")
            list(APPEND mcf5307_contract_result "${CMAKE_MATCH_1}")
        elseif(mcf5307_contract_statement MATCHES
                "^extern[ ].*[ *]([A-Za-z_][A-Za-z0-9_]*)(\\[[^]]*\\])?$")
            list(APPEND mcf5307_contract_result "${CMAKE_MATCH_1}")
        else()
            string(APPEND mcf5307_contract_lost
                "\n        ${mcf5307_contract_statement}")
        endif()
    endforeach()
    list(REMOVE_DUPLICATES mcf5307_contract_result)
    set(${mcf5307_contract_output} "${mcf5307_contract_result}" PARENT_SCOPE)
    set(${mcf5307_contract_unread} "${mcf5307_contract_lost}" PARENT_SCOPE)
endfunction()

# ---------------------------------------------------------------------------
# The three inputs. Each one comes from a different file and a different
# reader, and the controls below use that separation.

set(MCF5307_ABI_CONTRACT_FILE "${PROJECT_SOURCE_DIR}/include/mcf5307.h")
if(NOT EXISTS "${MCF5307_ABI_CONTRACT_FILE}")
    message(FATAL_ERROR
        "mcf5307: step 4a failed: ${MCF5307_ABI_CONTRACT_FILE} does not exist. "
        "That header is the published set of this library, and the check reads "
        "its names from there.")
endif()
mcf5307_abi_contract(MCF5307_ABI_PUBLISHED MCF5307_ABI_CONTRACT_UNREAD
    "${MCF5307_ABI_CONTRACT_FILE}")

set(MCF5307_ABI_HEADER_FILE "${MCF5307_NIMCACHE}/${MCF5307_NIM_HEADER}")
if(NOT EXISTS "${MCF5307_ABI_HEADER_FILE}")
    message(FATAL_ERROR
        "mcf5307: step 4a failed: ${MCF5307_ABI_HEADER_FILE} does not exist. "
        "Step 2 passes `--header:${MCF5307_NIM_HEADER}`, and control 1 below "
        "reads the compiler's own view of the published set from that file.")
endif()

# What NIM says it publishes. Measured on Nim 2.2.10, in this header alone:
# a procedure with `dynlib` reaches it as `N_LIB_IMPORT`. A procedure without
# `dynlib` reaches it as `N_LIB_PRIVATE`. A published VARIABLE reaches it as a
# plain `extern`, with no macro at all. This set therefore holds the published
# procedures alone, and control 1 is what it is for.
mcf5307_abi_scan(MCF5307_ABI_NIM_TOKENS "${MCF5307_ABI_HEADER_FILE}")
set(MCF5307_ABI_NIM_PUBLISHED "")
foreach(token IN LISTS MCF5307_ABI_NIM_TOKENS)
    if(token MATCHES "^N_LIB_IMPORT\\|(.+)$")
        list(APPEND MCF5307_ABI_NIM_PUBLISHED "${CMAKE_MATCH_1}")
    endif()
endforeach()

# The names Nim's own runtime scaffolding takes under `--nimMainPrefix:`. The
# prefix is the one of the entry module steps 2 to 6 build, and it is read
# back under that module's own name. They are not part of the published set,
# and step 4a REPORTS them instead of skipping them. See the note below.
set(MCF5307_ABI_SCAFFOLDING "")
foreach(suffix
        NimMain NimMainInner NimMainModule
        PreMain PreMainInner NimDestroyGlobals)
    list(APPEND MCF5307_ABI_SCAFFOLDING "${MCF5307_NIM_BUILT_PREFIX}${suffix}")
endforeach()

# ---------------------------------------------------------------------------
# The measurement. Every site of every interesting name is kept, with the unit
# it was read in. The report below then states what was read, and not a guess
# about the cause.

foreach(name IN LISTS MCF5307_ABI_PUBLISHED MCF5307_ABI_SCAFFOLDING)
    unset(MCF5307_ABI_SITES_${name})
endforeach()

set(MCF5307_ABI_SEEN "")
set(MCF5307_ABI_CLASSES "")
foreach(unit IN LISTS MCF5307_NIM_C_SOURCES)
    get_filename_component(MCF5307_ABI_UNIT_NAME "${unit}" NAME)
    mcf5307_abi_scan(MCF5307_ABI_UNIT_TOKENS "${unit}")
    foreach(token IN LISTS MCF5307_ABI_UNIT_TOKENS)
        if(NOT token MATCHES "^([^|]*)\\|(.*)$")
            continue()
        endif()
        set(MCF5307_ABI_STORAGE "${CMAKE_MATCH_1}")
        set(MCF5307_ABI_SYMBOL "${CMAKE_MATCH_2}")
        list(APPEND MCF5307_ABI_CLASSES "${MCF5307_ABI_STORAGE}")
        if(MCF5307_ABI_SYMBOL IN_LIST MCF5307_ABI_PUBLISHED)
            list(APPEND MCF5307_ABI_SEEN "${MCF5307_ABI_SYMBOL}")
        elseif(NOT MCF5307_ABI_SYMBOL IN_LIST MCF5307_ABI_SCAFFOLDING)
            continue()
        endif()
        list(APPEND MCF5307_ABI_SITES_${MCF5307_ABI_SYMBOL}
            "${MCF5307_ABI_STORAGE} in ${MCF5307_ABI_UNIT_NAME}")
    endforeach()
endforeach()
list(REMOVE_DUPLICATES MCF5307_ABI_SEEN)
list(REMOVE_DUPLICATES MCF5307_ABI_CLASSES)

# ---------------------------------------------------------------------------
# Control 1. The two headers hold each other up.
#
# The check above reads `include/mcf5307.h` with one reader. This control
# reads the compiler's own header with a DIFFERENT reader, and asserts that
# what Nim publishes is non-empty and is declared in the contract. Blind the
# contract reader and the subset test fails. Blind the Nim-header reader and
# the non-empty test fails. NEITHER READER CAN GO BLIND ON ITS OWN.
#
# The first part is narrower and it comes first. The two tests below both need
# the contract reader to have read the WHOLE contract. A reader that returned
# most of the names would pass both. The names it lost would then be published
# symbols this step says nothing about.
if(NOT MCF5307_ABI_CONTRACT_UNREAD STREQUAL "")
    message(FATAL_ERROR
        "mcf5307: step 4a failed: control 1: a statement of "
        "${MCF5307_ABI_CONTRACT_FILE} was neither skipped nor read.\n"
        "    unread statements:${MCF5307_ABI_CONTRACT_UNREAD}\n"
        "The reader skips a `typedef`, a `struct`, a `union` and an `enum`, "
        "and it reads a function declaration and an `extern` object "
        "declaration. A statement outside those five shapes is a symbol this "
        "step would report nothing about, and silence is not a pass.")
endif()

if(MCF5307_ABI_NIM_PUBLISHED STREQUAL "")
    message(FATAL_ERROR
        "mcf5307: step 4a failed: control 1: ${MCF5307_ABI_HEADER_FILE} names "
        "no published procedure at all.\n"
        "This project publishes at least `mcf5307_runtime_init`, and a "
        "procedure that carries `dynlib` reaches that header as "
        "`N_LIB_IMPORT`. An empty set means this step no longer reads what it "
        "was written to read, and every verdict below it would be vacuous.")
endif()

set(MCF5307_ABI_UNDECLARED "")
foreach(name IN LISTS MCF5307_ABI_NIM_PUBLISHED)
    if(NOT name IN_LIST MCF5307_ABI_PUBLISHED)
        list(APPEND MCF5307_ABI_UNDECLARED "${name}")
    endif()
endforeach()
if(NOT MCF5307_ABI_UNDECLARED STREQUAL "")
    message(FATAL_ERROR
        "mcf5307: step 4a failed: control 1: the Nim compilation publishes a "
        "name that the contract does not declare.\n"
        "  undeclared : ${MCF5307_ABI_UNDECLARED}\n"
        "  contract   : ${MCF5307_ABI_CONTRACT_FILE}\n"
        "Either the contract header lost the declaration, or this step no "
        "longer reads that header. Both readings are faults and this step "
        "cannot tell them apart. A symbol a consumer cannot declare is a "
        "symbol a consumer cannot call.")
endif()

# Control 2. The unit reader found at least one published symbol.
#
# Every `not defined here` verdict below rests on the unit reader working. If
# it read nothing at all, every published name would be reported as `not
# defined here`, and that report reads exactly like a young project.
if(MCF5307_ABI_SEEN STREQUAL "")
    message(FATAL_ERROR
        "mcf5307: step 4a failed: control 2: no published symbol was found in "
        "any generated C unit.\n"
        "  units : ${MCF5307_NIM_C_SOURCES}\n"
        "This project defines at least `mcf5307_runtime_init`. An empty result "
        "means the unit reader read nothing, and silence is not a pass.")
endif()

# Control 3. The unit reader can tell the two storage classes apart.
#
# The verdict is a comparison between the visible macros and the hidden one. A
# reader that never saw the hidden macro anywhere cannot make that comparison,
# and it would report every symbol as visible. Nim's own units carry many
# `N_LIB_PRIVATE` declarations, so the two classes are both present in any
# build this step can run against.
if(NOT "N_LIB_EXPORT" IN_LIST MCF5307_ABI_CLASSES
        OR NOT "N_LIB_PRIVATE" IN_LIST MCF5307_ABI_CLASSES)
    message(FATAL_ERROR
        "mcf5307: step 4a failed: control 3: the unit reader did not see both "
        "storage classes.\n"
        "  classes read : ${MCF5307_ABI_CLASSES}\n"
        "It has to read `N_LIB_EXPORT` and `N_LIB_PRIVATE` somewhere in the "
        "units before its verdict means anything. A reader blind to the hidden "
        "macro calls every symbol visible.")
endif()

# ---------------------------------------------------------------------------
# The verdict. A published symbol passes when EVERY site of it carries a
# visible macro. One site that does not is enough to fail the name.

set(MCF5307_ABI_VISIBLE "")
set(MCF5307_ABI_FAULTY "")
foreach(name IN LISTS MCF5307_ABI_SEEN)
    set(MCF5307_ABI_NAME_OK TRUE)
    foreach(site IN LISTS MCF5307_ABI_SITES_${name})
        if(NOT site MATCHES "^(N_LIB_EXPORT|N_LIB_EXPORT_VAR) ")
            set(MCF5307_ABI_NAME_OK FALSE)
        endif()
    endforeach()
    if(MCF5307_ABI_NAME_OK)
        list(APPEND MCF5307_ABI_VISIBLE "${name}")
    else()
        list(APPEND MCF5307_ABI_FAULTY "${name}")
    endif()
endforeach()

if(NOT MCF5307_ABI_FAULTY STREQUAL "")
    set(MCF5307_ABI_REPORT "")
    foreach(name IN LISTS MCF5307_ABI_FAULTY)
        string(APPEND MCF5307_ABI_REPORT "\n    ${name}")
        set(MCF5307_ABI_NAME_SITES "${MCF5307_ABI_SITES_${name}}")
        list(REMOVE_DUPLICATES MCF5307_ABI_NAME_SITES)
        foreach(site IN LISTS MCF5307_ABI_NAME_SITES)
            string(APPEND MCF5307_ABI_REPORT "\n        ${site}")
        endforeach()
    endforeach()
    message(FATAL_ERROR
        "mcf5307: step 4a failed: ${MCF5307_ABI_CONTRACT_FILE} publishes a "
        "symbol that the generated C does not emit visible.\n"
        "Every site of every name below is listed, with the storage class "
        "this step read at that site:${MCF5307_ABI_REPORT}\n"
        "  visible : ${MCF5307_ABI_VISIBLE}\n"
        "`N_LIB_PRIVATE` is `__attribute__((visibility(\"hidden\")))`. THIS "
        "STEP READ A STORAGE CLASS AND IT DID NOT MEASURE A CAUSE. Two causes "
        "fit: the Nim declaration carries a pragma set without `dynlib`, or "
        "the name has more than one declaration and they disagree. A name "
        "listed with sites of two classes is the second one. `mcf5307Abi` in "
        "`src/mcf5307.nim` holds `cdecl` and `dynlib` together, and `dynlib` "
        "is what asks for the visible form.\n"
        "The archive still builds and `nm` over the archive still reports the "
        "symbol, so this is the only step that reports the fault.")
endif()

# ---------------------------------------------------------------------------
# The report. It names what passed, and it names what this compilation does
# not define yet, so that neither reads as the other.

set(MCF5307_ABI_UNDEFINED "")
foreach(name IN LISTS MCF5307_ABI_PUBLISHED)
    if(NOT name IN_LIST MCF5307_ABI_SEEN)
        list(APPEND MCF5307_ABI_UNDEFINED "${name}")
    endif()
endforeach()

list(LENGTH MCF5307_ABI_PUBLISHED MCF5307_ABI_PUBLISHED_COUNT)
list(LENGTH MCF5307_ABI_VISIBLE MCF5307_ABI_VISIBLE_COUNT)
list(LENGTH MCF5307_ABI_UNDEFINED MCF5307_ABI_UNDEFINED_COUNT)

message(STATUS
    "mcf5307: step 4a ${MCF5307_ABI_CONTRACT_FILE} publishes "
    "${MCF5307_ABI_PUBLISHED_COUNT} symbol(s)")
message(STATUS
    "mcf5307: step 4a ${MCF5307_ABI_VISIBLE_COUNT} of them are emitted "
    "visible: ${MCF5307_ABI_VISIBLE}")
message(STATUS
    "mcf5307: step 4a ${MCF5307_ABI_UNDEFINED_COUNT} of them are not defined "
    "in this compilation: ${MCF5307_ABI_UNDEFINED}")

# ---------------------------------------------------------------------------
# The runtime scaffolding. Design section 5.4 rule 2 says C++ never calls the
# runtime entry point directly, and THAT RULE HAS NO MECHANISM BEHIND IT.
#
# `include/mcf5307.h` does not declare `<prefix>NimMain`, so a C++ caller has
# to write its own declaration to reach it. That is the whole barrier. The
# symbol itself carries no visibility macro at all in the generated C. That is
# C default visibility, so it does reach a consumer of the shared object.
#
# This step cannot enforce the rule and it does not pretend to. It prints what
# it read, so that the fact sits in the configure log rather than nowhere. A
# mechanism would be a linker export list, and that belongs to the build that
# makes the shared object.
set(MCF5307_ABI_REACHABLE "")
foreach(name IN LISTS MCF5307_ABI_SCAFFOLDING)
    if(NOT DEFINED MCF5307_ABI_SITES_${name})
        continue()
    endif()
    foreach(site IN LISTS MCF5307_ABI_SITES_${name})
        if(NOT site MATCHES "^N_LIB_PRIVATE ")
            list(APPEND MCF5307_ABI_REACHABLE "${name}")
        endif()
    endforeach()
endforeach()
list(REMOVE_DUPLICATES MCF5307_ABI_REACHABLE)
if(NOT MCF5307_ABI_REACHABLE STREQUAL "")
    message(STATUS
        "mcf5307: step 4a NOTE: the runtime scaffolding a consumer can reach: "
        "${MCF5307_ABI_REACHABLE}. Design section 5.4 rule 2 asks C++ not to "
        "call it, the contract header does not declare it, and no mechanism "
        "here enforces that. This line is a report and not a check.")
endif()

# ---------------------------------------------------------------------------
# Step 5. The static library.
#
# It carries the objects of step 4 and nothing else. The contract header
# reaches a consumer through the include directory below, and it is in no
# source list of this target. The generated `mcf5307_nim.h` is not the contract
# and is not published. The contract is `include/mcf5307.h`, which is reviewed
# as one file.
#
# There is no `INSTALL_INTERFACE` expression and no `PUBLIC_HEADER` property
# here. Nothing in this project installs this target, so both would be inert
# text that no run can check. The task that adds an `install(TARGETS ...)` rule
# adds them back in the same change, where they take effect.
#
# `include/mcf5307.h` is in no target's source list, and no build step compiles
# it. The compile check for the contract header is the registered test
# `t0_abi_header`, whose cases 1 and 2 parse it as C11 and as C++17.

add_library(mcf5307 STATIC $<TARGET_OBJECTS:mcf5307_nim_objs>)

target_include_directories(mcf5307 PUBLIC
    "$<BUILD_INTERFACE:${PROJECT_SOURCE_DIR}/include>")
if(TARGET Threads::Threads)
    target_link_libraries(mcf5307 PUBLIC Threads::Threads)
endif()
set_target_properties(mcf5307 PROPERTIES
    LINKER_LANGUAGE C)

message(STATUS "mcf5307: step 5 the static library mcf5307 is defined")

# ---------------------------------------------------------------------------
# Step 6. The consumer-facing name.
#
# A consumer writes `mcf5307::mcf5307`, whether it brings this project in with
# `FetchContent` or finds an installed one. The double-colon name is also what
# makes a misspelling a CMake error. Without it a misspelled name reaches the
# linker unchanged as `-lmcf5307`.

add_library(mcf5307::mcf5307 ALIAS mcf5307)

message(STATUS "mcf5307: step 6 the target mcf5307::mcf5307 is exported")
