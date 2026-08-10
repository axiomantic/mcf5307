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
# `--path:src` puts the package root on the Nim search path so that the
# entry module's `import mcf5307/<sub>` resolves to `src/mcf5307/<sub>.nim`.
# The submodules of the core (CPU-6 and later) live under `src/mcf5307/`, and
# without the path an entry module at `src/mcf5307.nim` cannot import them.
set(MCF5307_NIM_PATH "${PROJECT_SOURCE_DIR}/src")
set(MCF5307_NIM_COMMAND_mcf5307
    "${MCF5307_NIM_EXECUTABLE}" c
    --compileOnly
    --noMain
    "--nimcache:${MCF5307_NIMCACHE}"
    "--path:${MCF5307_NIM_PATH}"
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

# The contract header. It is CPU-0's file, it is read here and it is never
# written here. The name is set at this point because the line below has to
# name it, and step 4a reads the same variable.
set(MCF5307_ABI_CONTRACT_FILE "${PROJECT_SOURCE_DIR}/include/mcf5307.h")

# The smoke test's symbol list. It is CPU-3's file, it is read here and it is
# never written here. Step 4a compares it against the published set of the
# contract header above. It is named at this point for the same reason the
# contract header is: the dependency list below has to carry it.
set(MCF5307_ABI_SMOKE_LIST_FILE
    "${PROJECT_SOURCE_DIR}/tests/abi_smoke_symbols.inc")

# Editing a configure-time INPUT must re-run the configure step. Four files
# are inputs, and all four are listed.
#
#   `src/*.nim`        the unit list is read at configure time, and a new
#                      module adds a unit to it.
#   `.nim-version`     step 1 compares it against the compiler.
#   `include/mcf5307.h` step 4a reads the published set out of it.
#   `tests/abi_smoke_symbols.inc`
#                      step 4a reads the smoke test's list out of it and
#                      compares the two. A list edited without a re-run would
#                      leave the comparison speaking about a version of the
#                      list that no longer exists - the exact failure the
#                      paragraph below records for the contract header.
#
# THE CONTRACT HEADER WAS MISSING FROM THIS LIST. Measured before the repair:
# an edit to `include/mcf5307.h` did not re-run the configure step, so step 4a
# kept its verdict about a version of the contract that no longer existed, the
# build exited 0, and no diagnostic named the stale read. An edit to
# `src/mcf5307.nim` did re-run it, which is what made the gap hard to see.
file(GLOB_RECURSE MCF5307_NIM_SOURCES CONFIGURE_DEPENDS
    "${PROJECT_SOURCE_DIR}/src/*.nim")
set_property(DIRECTORY "${PROJECT_SOURCE_DIR}"
    APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
    ${MCF5307_NIM_SOURCES} "${MCF5307_NIM_VERSION_FILE}"
    "${MCF5307_ABI_CONTRACT_FILE}" "${MCF5307_ABI_SMOKE_LIST_FILE}")

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
# Step 4a. The visibility gate.
#
# WHAT THE GATE PROTECTS. The delivery form is a JUCE plugin, and a plugin is a
# shared object. Every symbol `include/mcf5307.h` publishes must leave that
# shared object with default visibility. Nim decides that in the pragma set of
# the declaration. Measured on Nim 2.2.10, `{.exportc, cdecl.}` alone gives a
# hidden symbol, and `dynlib` added to the set gives a visible one.
#
# `nm` over the static archive reports a hidden symbol exactly as it reports a
# visible one, and the smoke test of CPU-3 links statically. The shared object
# is the first artifact that tells the two apart, so this step builds one.
#
# HOW THE GATE MEASURES IT. It asks two tools, and it parses no C of its own.
#
#   THE PUBLISHED SET COMES FROM A C COMPILER. A generated translation unit
#   includes the contract header. `-Xclang -ast-dump=json` prints the syntax
#   tree of that unit, and this file reads the function and object declarations
#   out of the tree. A C parser decides what the C means.
#
#   THE EXPORTED SET COMES FROM THE LINKER. This file builds a shared object
#   from the generated C units and reads its symbol table with `nm`. That is
#   the delivery-form property itself and not an opinion about it.
#
# The verdict is a comparison of sets. A published name that the shared object
# defines and does not export is a fault. A published name that the shared
# object does not define at all is NOT a fault, and the report keeps the two
# apart. A later cpu task writes those definitions.
#
# THE GATE KNOWS NOTHING ABOUT `N_LIB_EXPORT`, `N_LIB_EXPORT_VAR` OR
# `N_LIB_PRIVATE`. Those macros are one Nim release's way to write a visibility
# attribute. The linker reports the result of the attribute, so the gate reads
# the result and never the macro. A Nim release that renames the macros changes
# nothing here.
#
# WHY THE READER THIS BLOCK REPLACES HAD TO GO. It parsed C with regular
# expressions. Measured, seven ordinary shapes defeated it:
#
#   struct mcf5307_ctx* mcf5307_peek(void);          dropped in silence
#   struct isp1181_ctx *isp1181_peek(void);          dropped in silence
#   enum mcf5307_bus_status mcf5307_last_status(void);   dropped in silence
#   union mcf5307_word mcf5307_peek_word(void);      dropped in silence
#   __attribute__((visibility("default"))) void mcf5307_boom(void);
#                                                    published `__attribute__`
#   uint32_t (*mcf5307_get_reader(int idx))(void*, uint32_t);
#                                                    published `uint32_t`
#   extern uint32_t mcf5307_lo, mcf5307_hi;          lost `mcf5307_lo`
#
# It was wrong in both directions, and its own guard caught only a statement it
# could not classify. It never caught one it classified WRONGLY. A compiler
# handles all seven by construction, and the calibration below proves that on
# every configure run rather than in a review comment.
#
# `include/mcf5307.h` belongs to CPU-0. It is read here and never written here.

# ---------------------------------------------------------------------------
# The escape hatch, and why it is loud.
#
# The gate needs a Clang-compatible C parser and an `nm`. A host without both
# cannot run it. The gate then FAILS the configure step and names the tool it
# did not find, because a check that quietly does not run is the fault this
# whole block exists to end.
#
# `-DMCF5307_ABI_GATE=OFF` configures such a host. It prints a WARNING on every
# configure run. The build is then a build whose published symbols nobody
# measured, and the warning says so in those words.
set(MCF5307_ABI_GATE ON CACHE BOOL
    "Measure the visibility of every published symbol at configure time")

if(NOT MCF5307_ABI_GATE)
    message(WARNING
        "mcf5307: step 4a IS TURNED OFF. MCF5307_ABI_GATE is OFF, so nothing "
        "in this configure run measured the visibility of the published "
        "symbols of ${MCF5307_ABI_CONTRACT_FILE}. A published "
        "symbol that reaches the shared object hidden makes a plugin that "
        "exports nothing, and this build would not report it. Turn the gate "
        "back on with -DMCF5307_ABI_GATE=ON.")
else()

# ---------------------------------------------------------------------------
# The two tools.
#
# The parser must accept `-Xclang -ast-dump=json`. The project's own C compiler
# is used when it is Clang, because that keeps the parse and the build on one
# toolchain. Otherwise a Clang is looked up separately. GCC has no equivalent
# dump for C.
#
# The shared object is built with the PROJECT'S C compiler and not with the
# parser. The exported set is a property of the toolchain that ships the
# library, so the toolchain that ships it is the one that must answer.

if(CMAKE_C_COMPILER_ID MATCHES "^(Clang|AppleClang)$")
    set(MCF5307_ABI_PARSER "${CMAKE_C_COMPILER}")
    set(MCF5307_ABI_PARSER_SOURCE "the project's own C compiler")
else()
    find_program(MCF5307_ABI_CLANG NAMES clang clang-cl
        DOC "A Clang that prints a JSON syntax tree for step 4a")
    if(MCF5307_ABI_CLANG)
        set(MCF5307_ABI_PARSER "${MCF5307_ABI_CLANG}")
        set(MCF5307_ABI_PARSER_SOURCE "a separate Clang found on this host")
    else()
        message(FATAL_ERROR
            "mcf5307: step 4a failed: no Clang was found.\n"
            "  project C compiler : ${CMAKE_C_COMPILER} "
            "(${CMAKE_C_COMPILER_ID})\n"
            "The published set of ${PROJECT_SOURCE_DIR}/include/mcf5307.h is "
            "read from a C syntax tree, which Clang prints with "
            "`-Xclang -ast-dump=json`. A regular expression over the header "
            "text is what this step replaced, and it was wrong in both "
            "directions. Install Clang, or configure with "
            "-DMCF5307_ABI_GATE=OFF and accept a build whose published "
            "symbols nobody measured.")
    endif()
endif()

if(CMAKE_NM)
    set(MCF5307_ABI_NM "${CMAKE_NM}")
else()
    find_program(MCF5307_ABI_NM_PROGRAM NAMES nm llvm-nm
        DOC "The symbol lister that reads the measurement shared object")
    set(MCF5307_ABI_NM "${MCF5307_ABI_NM_PROGRAM}")
endif()
if(NOT MCF5307_ABI_NM)
    message(FATAL_ERROR
        "mcf5307: step 4a failed: no `nm` was found.\n"
        "The exported set is read from the symbol table of a shared object. "
        "Nothing else reports whether a published symbol left that object. "
        "Install binutils or LLVM, or configure with -DMCF5307_ABI_GATE=OFF "
        "and accept a build whose published symbols nobody measured.")
endif()

set(MCF5307_ABI_DIR "${PROJECT_BINARY_DIR}/mcf5307_abi")
file(MAKE_DIRECTORY "${MCF5307_ABI_DIR}")

# ---------------------------------------------------------------------------
# The reader of a published set.
#
# It writes a translation unit that includes one header, asks the parser for
# the syntax tree of that unit, and folds the tree.
#
# THE UNIT CARRIES TWO SENTINEL DECLARATIONS, one before the include and one
# after it. They are the per-read control of the file attribution below. The
# caller asserts that the fold attributed exactly those two to the unit itself.
# A fold that lost the attribution and gave everything to the header would put
# the sentinels in the published set. A fold that gave nothing to the header
# would still show them. Neither failure can pass this pair.
#
# HOW THE ATTRIBUTION WORKS. Clang prints `loc.file` on a node only when the
# file differs from the previous node's file. The fold therefore carries the
# last file it saw forward, exactly as the printer expects. A declaration that
# no file covers goes into the unattributed list, and the caller stops over it.
#
# It keeps a `FunctionDecl` and a `VarDecl`, and it keeps nothing else. A
# `typedef`, a `struct`, a `union` and an `enum` name a type and publish no
# symbol. A `static` declaration publishes no symbol either.
function(mcf5307_abi_read_published
        mcf5307_read_names mcf5307_read_sentinels mcf5307_read_unattributed
        mcf5307_read_label mcf5307_read_header)
    set(mcf5307_read_unit "${MCF5307_ABI_DIR}/${mcf5307_read_label}_probe.c")
    set(mcf5307_read_tree "${MCF5307_ABI_DIR}/${mcf5307_read_label}_ast.json")
    file(WRITE "${mcf5307_read_unit}"
        "/* GENERATED by cmake/Nim.cmake step 4a. Do not edit this copy. */\n"
        "extern int mcf5307_abi_sentinel_alpha(void);\n"
        "#include \"${mcf5307_read_header}\"\n"
        "extern int mcf5307_abi_sentinel_omega(void);\n")

    execute_process(
        COMMAND "${MCF5307_ABI_PARSER}" -std=c11 -fsyntax-only
                "-I${PROJECT_SOURCE_DIR}/include"
                -Xclang -ast-dump=json "${mcf5307_read_unit}"
        OUTPUT_FILE "${mcf5307_read_tree}"
        ERROR_VARIABLE mcf5307_read_error
        RESULT_VARIABLE mcf5307_read_result)
    if(NOT mcf5307_read_result EQUAL 0)
        mcf5307_clip(mcf5307_read_error_head "${mcf5307_read_error}" 2000)
        message(FATAL_ERROR
            "mcf5307: step 4a failed: the parser did not read "
            "${mcf5307_read_header}.\n"
            "  parser : ${MCF5307_ABI_PARSER}\n"
            "  unit   : ${mcf5307_read_unit}\n"
            "  exit   : ${mcf5307_read_result}\n"
            "  stderr : ${mcf5307_read_error_head}\n"
            "A header the C compiler refuses is a header no consumer can "
            "include, and this step reports nothing about a file it could not "
            "parse.")
    endif()

    file(READ "${mcf5307_read_tree}" mcf5307_read_text)
    string(JSON mcf5307_read_count
        ERROR_VARIABLE mcf5307_read_json_error
        LENGTH "${mcf5307_read_text}" inner)
    if(NOT mcf5307_read_json_error STREQUAL "NOTFOUND")
        message(FATAL_ERROR
            "mcf5307: step 4a failed: ${mcf5307_read_tree} carries no readable "
            "`inner` array.\n"
            "  error : ${mcf5307_read_json_error}\n"
            "That member holds the declarations of the translation unit. A "
            "Clang release that renames it needs this step read the new name.")
    endif()

    set(mcf5307_read_result_names "")
    set(mcf5307_read_result_sentinels "")
    set(mcf5307_read_result_lost "")
    set(mcf5307_read_file "")
    math(EXPR mcf5307_read_last "${mcf5307_read_count} - 1")
    foreach(mcf5307_read_index RANGE ${mcf5307_read_last})
        string(JSON mcf5307_read_node
            GET "${mcf5307_read_text}" inner ${mcf5307_read_index})

        # The file is sticky. It is updated whenever the node carries one, and
        # it is carried forward whenever the node does not.
        string(JSON mcf5307_read_node_file
            ERROR_VARIABLE mcf5307_read_file_error
            GET "${mcf5307_read_node}" loc file)
        if(mcf5307_read_file_error STREQUAL "NOTFOUND")
            set(mcf5307_read_file "${mcf5307_read_node_file}")
        endif()

        string(JSON mcf5307_read_kind
            ERROR_VARIABLE mcf5307_read_kind_error
            GET "${mcf5307_read_node}" kind)
        if(NOT mcf5307_read_kind_error STREQUAL "NOTFOUND")
            continue()
        endif()
        if(NOT mcf5307_read_kind STREQUAL "FunctionDecl"
                AND NOT mcf5307_read_kind STREQUAL "VarDecl")
            continue()
        endif()

        # A compiler-supplied declaration is not part of any header's contract.
        string(JSON mcf5307_read_implicit
            ERROR_VARIABLE mcf5307_read_implicit_error
            GET "${mcf5307_read_node}" isImplicit)
        if(mcf5307_read_implicit_error STREQUAL "NOTFOUND"
                AND mcf5307_read_implicit)
            continue()
        endif()

        # `static` gives the name internal linkage. No consumer can reach it,
        # so it publishes nothing and the gate says nothing about it.
        string(JSON mcf5307_read_storage
            ERROR_VARIABLE mcf5307_read_storage_error
            GET "${mcf5307_read_node}" storageClass)
        if(mcf5307_read_storage_error STREQUAL "NOTFOUND"
                AND mcf5307_read_storage STREQUAL "static")
            continue()
        endif()

        string(JSON mcf5307_read_name
            ERROR_VARIABLE mcf5307_read_name_error
            GET "${mcf5307_read_node}" name)
        if(NOT mcf5307_read_name_error STREQUAL "NOTFOUND")
            continue()
        endif()

        if(mcf5307_read_file STREQUAL "")
            list(APPEND mcf5307_read_result_lost "${mcf5307_read_name}")
        elseif(mcf5307_read_file STREQUAL "${mcf5307_read_header}")
            list(APPEND mcf5307_read_result_names "${mcf5307_read_name}")
        elseif(mcf5307_read_file STREQUAL "${mcf5307_read_unit}")
            list(APPEND mcf5307_read_result_sentinels "${mcf5307_read_name}")
        endif()
    endforeach()

    list(REMOVE_DUPLICATES mcf5307_read_result_names)
    set(${mcf5307_read_names} "${mcf5307_read_result_names}" PARENT_SCOPE)
    set(${mcf5307_read_sentinels} "${mcf5307_read_result_sentinels}"
        PARENT_SCOPE)
    set(${mcf5307_read_unattributed} "${mcf5307_read_result_lost}"
        PARENT_SCOPE)
endfunction()

# ---------------------------------------------------------------------------
# The per-read control of the reader above.
#
# It runs on the calibration read AND on the contract read, so the fold is
# calibrated on the very read whose answer is used. The expected answer is
# written out here, so a blind fold cannot produce it.
function(mcf5307_abi_check_sentinels mcf5307_check_label mcf5307_check_seen
        mcf5307_check_lost)
    set(mcf5307_check_want
        "mcf5307_abi_sentinel_alpha;mcf5307_abi_sentinel_omega")
    if(NOT mcf5307_check_lost STREQUAL "")
        message(FATAL_ERROR
            "mcf5307: step 4a failed: control A (${mcf5307_check_label}): a "
            "declaration was read and no file covers it.\n"
            "  unattributed : ${mcf5307_check_lost}\n"
            "The fold carries the last file Clang printed forward. A "
            "declaration before the first printed file means the fold no "
            "longer follows the printer, and every name it sorted afterwards "
            "is in doubt.")
    endif()
    if(NOT "${mcf5307_check_seen}" STREQUAL "${mcf5307_check_want}")
        message(FATAL_ERROR
            "mcf5307: step 4a failed: control A (${mcf5307_check_label}): the "
            "sentinels of the generated translation unit were not read back.\n"
            "  expected : ${mcf5307_check_want}\n"
            "  read     : ${mcf5307_check_seen}\n"
            "The unit declares one sentinel before the include and one after "
            "it. A fold that gave the whole unit to the header would report "
            "neither here and both in the published set. A fold that read "
            "nothing would report neither anywhere. This pair separates those "
            "two failures from a correct read.")
    endif()
endfunction()

# ---------------------------------------------------------------------------
# The reader of a shared object's symbols.
#
# It reads the object TWICE and returns two sets.
#
#   `defined`  every symbol the object defines, whatever its visibility.
#   `exported` every symbol the object defines AND makes external.
#
# The two sets are what separate `hidden` from `not implemented yet`. A hidden
# symbol is defined and not exported. A symbol nothing implements is in
# neither set. The reader before this one could not tell those apart, and it
# reported both as `not defined in this compilation`.
#
# `nm` prints `<address> <type> <name>`, and it prints `U`, `u`, `w` or `v` in
# the type column for a symbol the object does not define. Those four are
# dropped and every other type is a definition.
function(mcf5307_abi_read_symbols mcf5307_symbols_out_defined
        mcf5307_symbols_out_exported mcf5307_symbols_object)
    foreach(mcf5307_symbols_pass all external)
        if(mcf5307_symbols_pass STREQUAL "external")
            set(mcf5307_symbols_flags -g)
        else()
            set(mcf5307_symbols_flags "")
        endif()
        execute_process(
            COMMAND "${MCF5307_ABI_NM}" ${mcf5307_symbols_flags}
                    "${mcf5307_symbols_object}"
            OUTPUT_VARIABLE mcf5307_symbols_output
            ERROR_VARIABLE mcf5307_symbols_error
            RESULT_VARIABLE mcf5307_symbols_result)
        if(NOT mcf5307_symbols_result EQUAL 0)
            mcf5307_clip(mcf5307_symbols_error_head
                "${mcf5307_symbols_error}" 2000)
            message(FATAL_ERROR
                "mcf5307: step 4a failed: `${MCF5307_ABI_NM}` exited "
                "${mcf5307_symbols_result} over "
                "${mcf5307_symbols_object}.\n"
                "  stderr : ${mcf5307_symbols_error_head}")
        endif()
        string(REPLACE "\r" "" mcf5307_symbols_output
            "${mcf5307_symbols_output}")
        string(REPLACE "\n" ";" mcf5307_symbols_lines
            "${mcf5307_symbols_output}")
        set(mcf5307_symbols_set_${mcf5307_symbols_pass} "")
        foreach(mcf5307_symbols_line IN LISTS mcf5307_symbols_lines)
            if(NOT mcf5307_symbols_line MATCHES
                    "^[0-9a-fA-F]*[ \t]+([A-Za-z])[ \t]+([^ \t]+)[ \t]*$")
                continue()
            endif()
            # THE TWO CAPTURES ARE COPIED OUT BEFORE THE NEXT `MATCHES` RUNS.
            # A second `MATCHES` overwrites `CMAKE_MATCH_1` and `CMAKE_MATCH_2`
            # on a hit AND clears them on a miss. Reading them afterwards gave
            # every defined symbol the empty name.
            set(mcf5307_symbols_type "${CMAKE_MATCH_1}")
            set(mcf5307_symbols_name "${CMAKE_MATCH_2}")
            if(mcf5307_symbols_type MATCHES "^[Uuwv]$")
                continue()
            endif()
            list(APPEND mcf5307_symbols_set_${mcf5307_symbols_pass}
                "${mcf5307_symbols_name}")
        endforeach()
        list(REMOVE_DUPLICATES mcf5307_symbols_set_${mcf5307_symbols_pass})
    endforeach()
    set(${mcf5307_symbols_out_defined} "${mcf5307_symbols_set_all}"
        PARENT_SCOPE)
    set(${mcf5307_symbols_out_exported} "${mcf5307_symbols_set_external}"
        PARENT_SCOPE)
endfunction()

# ---------------------------------------------------------------------------
# Calibration 1. The published-set reader reads seven ordinary C shapes.
#
# THIS IS THE MECHANISED FORM OF THE DEFECT THAT ENDED THE READER BEFORE THIS
# ONE. The calibration header below carries every shape that defeated it, plus
# four shapes that publish nothing and one declaration behind `#if 0`. The
# expected answer is WRITTEN OUT. A reader that lost a shape, that reported a
# type keyword, or that reported a type name cannot produce it.
#
# The check runs on every configure run and not in a review.

set(MCF5307_ABI_CALIBRATION "${MCF5307_ABI_DIR}/calibration.h")
file(WRITE "${MCF5307_ABI_CALIBRATION}" [==[
/* GENERATED by cmake/Nim.cmake step 4a. Do not edit this copy in the build
 * tree. It is the calibration input of the published-set reader.
 *
 * The first group holds the seven shapes that defeated the regular-expression
 * reader this step replaced. Every one of them publishes a symbol.
 * The second group publishes nothing at all. */

#include <stddef.h>
#include <stdint.h>

struct mcf5307_cal_ctx* mcf5307_cal_struct_return(void);
struct mcf5307_cal_ctx *mcf5307_cal_pointer_spacing(void);
enum mcf5307_cal_status mcf5307_cal_enum_return(void);
union mcf5307_cal_word mcf5307_cal_union_return(void);
__attribute__((visibility("default"))) void mcf5307_cal_attribute(void);
uint32_t (*mcf5307_cal_function_pointer(int idx))(void*, uint32_t);
extern uint32_t mcf5307_cal_first_object, mcf5307_cal_second_object;

typedef struct mcf5307_cal_ctx mcf5307_cal_context;
typedef enum { MCF5307_CAL_ZERO = 0 } mcf5307_cal_enumeration;
typedef void (*mcf5307_cal_callback)(void* user, uint32_t address);
static inline int mcf5307_cal_internal(void) { return 0; }

/* A declaration behind a false conditional. A reader with no preprocessor
 * publishes it, and it is not published. */
#if 0
void mcf5307_cal_dead_branch(void);
#endif
]==])

# The expected answer. It is sorted, because the comparison below sorts the
# measurement too. The order of the declarations is a property of Clang's
# printer and it is not the property under test.
set(MCF5307_ABI_CALIBRATION_EXPECTED
    mcf5307_cal_attribute
    mcf5307_cal_enum_return
    mcf5307_cal_first_object
    mcf5307_cal_function_pointer
    mcf5307_cal_pointer_spacing
    mcf5307_cal_second_object
    mcf5307_cal_struct_return
    mcf5307_cal_union_return)

mcf5307_abi_read_published(MCF5307_ABI_CALIBRATION_READ
    MCF5307_ABI_CALIBRATION_SENTINELS MCF5307_ABI_CALIBRATION_LOST
    calibration "${MCF5307_ABI_CALIBRATION}")
mcf5307_abi_check_sentinels("the calibration header"
    "${MCF5307_ABI_CALIBRATION_SENTINELS}" "${MCF5307_ABI_CALIBRATION_LOST}")

set(MCF5307_ABI_CALIBRATION_SORTED ${MCF5307_ABI_CALIBRATION_READ})
list(SORT MCF5307_ABI_CALIBRATION_SORTED)
if(NOT "${MCF5307_ABI_CALIBRATION_SORTED}" STREQUAL
        "${MCF5307_ABI_CALIBRATION_EXPECTED}")
    message(FATAL_ERROR
        "mcf5307: step 4a failed: control B: the published-set reader did not "
        "read the calibration header correctly.\n"
        "  header   : ${MCF5307_ABI_CALIBRATION}\n"
        "  expected : ${MCF5307_ABI_CALIBRATION_EXPECTED}\n"
        "  read     : ${MCF5307_ABI_CALIBRATION_SORTED}\n"
        "That header carries a `struct`, a `union` and an `enum` return type, "
        "a pointer return written both ways, a GNU attribute in front of a "
        "declaration, a function that returns a function pointer, two "
        "declarators in one statement, four shapes that publish nothing, and "
        "one declaration behind `#if 0`. A reader that cannot answer this "
        "cannot be trusted with the contract, and the answer it gives for the "
        "contract would look exactly like a correct one.")
endif()

message(STATUS
    "mcf5307: step 4a control B the published-set reader answered the "
    "calibration header exactly (8 of 8 shapes, 5 negatives)")

# ---------------------------------------------------------------------------
# The published set. It comes from the contract header, through the same
# reader and the same per-read control. `MCF5307_ABI_CONTRACT_FILE` is set
# beside the configure-time dependency list above, so the file this step reads
# and the file that re-runs this step are one name.

if(NOT EXISTS "${MCF5307_ABI_CONTRACT_FILE}")
    message(FATAL_ERROR
        "mcf5307: step 4a failed: ${MCF5307_ABI_CONTRACT_FILE} does not exist. "
        "That header is the published set of this library, and the gate reads "
        "its names from there.")
endif()

mcf5307_abi_read_published(MCF5307_ABI_PUBLISHED MCF5307_ABI_SENTINELS
    MCF5307_ABI_LOST contract "${MCF5307_ABI_CONTRACT_FILE}")
mcf5307_abi_check_sentinels("the contract header"
    "${MCF5307_ABI_SENTINELS}" "${MCF5307_ABI_LOST}")

if(MCF5307_ABI_PUBLISHED STREQUAL "")
    message(FATAL_ERROR
        "mcf5307: step 4a failed: control C: ${MCF5307_ABI_CONTRACT_FILE} "
        "publishes no symbol at all.\n"
        "This project publishes at least `mcf5307_runtime_init`. An empty "
        "published set makes every verdict below it vacuous, and silence is "
        "not a pass.")
endif()

# ---------------------------------------------------------------------------
# The measurement shared object.
#
# It carries the generated C units of step 3 and one generated probe unit. The
# static archive of step 5 is not built yet at configure time, and it would
# add nothing: the archive holds these same objects, and a shared object made
# from the archive with a force-load flag holds them all as well. This route
# needs no archive semantics and no platform force-load flag.
#
# THE CONSUMER'S `CMAKE_C_FLAGS` ARE NOT PASSED HERE. This object is a
# measuring instrument and it is never shipped. A consumer's `-Werror` would
# stop the measurement over a warning in code this project does not author.
#
# The probe unit is what calibrates the symbol reader. It is compiled into
# THIS object and not into a separate one, so the calibration is a statement
# about the artifact the verdict is read from.

set(MCF5307_ABI_PROBE_SOURCE "${MCF5307_ABI_DIR}/visibility_probe.c")
file(WRITE "${MCF5307_ABI_PROBE_SOURCE}" [==[
/* GENERATED by cmake/Nim.cmake step 4a. Do not edit this copy in the build
 * tree. It calibrates the symbol reader on the object the verdict is read
 * from.
 *
 * `mcf5307_abi_probe_visible` must be defined AND exported.
 * `mcf5307_abi_probe_hidden`  must be defined AND NOT exported.
 * `mcf5307_abi_probe_absent`  is defined nowhere and must be in neither set.
 *
 * The three answers together prove that the reader separates the three
 * outcomes the verdict below depends on. */
__attribute__((visibility("default"))) void mcf5307_abi_probe_visible(void) {}
__attribute__((visibility("hidden"))) void mcf5307_abi_probe_hidden(void) {}
]==])

set(MCF5307_ABI_OBJECT
    "${MCF5307_ABI_DIR}/libmcf5307_abi_measure${CMAKE_SHARED_LIBRARY_SUFFIX}")

# Both variables hold a command fragment as ONE string with spaces in it, and
# not a CMake list. `${VAR}` inside a COMMAND would pass the whole fragment as
# a single argument. `separate_arguments` splits it the way a shell would.
separate_arguments(MCF5307_ABI_SHARED_FLAGS NATIVE_COMMAND
    "${CMAKE_SHARED_LIBRARY_CREATE_C_FLAGS}")
separate_arguments(MCF5307_ABI_PIC_FLAGS NATIVE_COMMAND
    "${CMAKE_C_COMPILE_OPTIONS_PIC}")

execute_process(
    COMMAND "${CMAKE_C_COMPILER}"
            ${MCF5307_ABI_SHARED_FLAGS}
            ${MCF5307_ABI_PIC_FLAGS}
            -std=c11
            "-isystem" "${MCF5307_NIM_LIB_DIR}"
            -o "${MCF5307_ABI_OBJECT}"
            ${MCF5307_NIM_C_SOURCES}
            "${MCF5307_ABI_PROBE_SOURCE}"
    OUTPUT_VARIABLE MCF5307_ABI_LINK_OUTPUT
    ERROR_VARIABLE MCF5307_ABI_LINK_ERROR
    RESULT_VARIABLE MCF5307_ABI_LINK_RESULT)

if(NOT MCF5307_ABI_LINK_RESULT EQUAL 0)
    mcf5307_clip(MCF5307_ABI_LINK_OUTPUT_HEAD "${MCF5307_ABI_LINK_OUTPUT}" 2000)
    mcf5307_clip(MCF5307_ABI_LINK_ERROR_HEAD "${MCF5307_ABI_LINK_ERROR}" 2000)
    message(FATAL_ERROR
        "mcf5307: step 4a failed: the measurement shared object did not "
        "build.\n"
        "  compiler : ${CMAKE_C_COMPILER}\n"
        "  object   : ${MCF5307_ABI_OBJECT}\n"
        "  exit     : ${MCF5307_ABI_LINK_RESULT}\n"
        "  stdout   : ${MCF5307_ABI_LINK_OUTPUT_HEAD}\n"
        "  stderr   : ${MCF5307_ABI_LINK_ERROR_HEAD}\n"
        "The delivery form is a shared object, so the gate builds one and "
        "reads its symbol table. Without it nothing here measures visibility.")
endif()

mcf5307_abi_read_symbols(MCF5307_ABI_DEFINED_RAW MCF5307_ABI_EXPORTED_RAW
    "${MCF5307_ABI_OBJECT}")

# ---------------------------------------------------------------------------
# Control D. The symbol reader, calibrated on the object it just read.
#
# The visible probe also MEASURES the platform's symbol prefix. Mach-O puts one
# underscore in front of every C name and ELF puts none. The prefix is read off
# a name this file wrote, and it is never assumed.
set(MCF5307_ABI_PREFIX "")
set(MCF5307_ABI_PREFIX_FOUND FALSE)
foreach(name IN LISTS MCF5307_ABI_EXPORTED_RAW)
    if(name MATCHES "^(_*)mcf5307_abi_probe_visible$")
        set(MCF5307_ABI_PREFIX "${CMAKE_MATCH_1}")
        set(MCF5307_ABI_PREFIX_FOUND TRUE)
    endif()
endforeach()
if(NOT MCF5307_ABI_PREFIX_FOUND)
    message(FATAL_ERROR
        "mcf5307: step 4a failed: control D: the probe symbol "
        "`mcf5307_abi_probe_visible` is not among the exported symbols of "
        "${MCF5307_ABI_OBJECT}.\n"
        "  exported : ${MCF5307_ABI_EXPORTED_RAW}\n"
        "That probe carries `visibility(\"default\")` and this file compiled "
        "it into that object. A reader that cannot find it read the wrong "
        "file, read nothing, or cannot see an exported symbol at all. Every "
        "`hidden` verdict below would then be false, and every `visible` "
        "verdict would be unearned.")
endif()

function(mcf5307_abi_strip mcf5307_strip_output)
    set(mcf5307_strip_result "")
    foreach(mcf5307_strip_name IN LISTS ARGN)
        if(NOT MCF5307_ABI_PREFIX STREQUAL "")
            string(REGEX REPLACE "^${MCF5307_ABI_PREFIX}" ""
                mcf5307_strip_name "${mcf5307_strip_name}")
        endif()
        list(APPEND mcf5307_strip_result "${mcf5307_strip_name}")
    endforeach()
    set(${mcf5307_strip_output} "${mcf5307_strip_result}" PARENT_SCOPE)
endfunction()

mcf5307_abi_strip(MCF5307_ABI_DEFINED ${MCF5307_ABI_DEFINED_RAW})
mcf5307_abi_strip(MCF5307_ABI_EXPORTED ${MCF5307_ABI_EXPORTED_RAW})

if(NOT "mcf5307_abi_probe_hidden" IN_LIST MCF5307_ABI_DEFINED)
    message(FATAL_ERROR
        "mcf5307: step 4a failed: control D: the probe symbol "
        "`mcf5307_abi_probe_hidden` is not among the DEFINED symbols of "
        "${MCF5307_ABI_OBJECT}.\n"
        "  defined : ${MCF5307_ABI_DEFINED}\n"
        "This file compiled a definition of it into that object. A reader "
        "that cannot see a hidden definition cannot separate `hidden` from "
        "`not implemented yet`, and it would report every hidden symbol as an "
        "unwritten one. That is the report the gate must never give.")
endif()

if("mcf5307_abi_probe_hidden" IN_LIST MCF5307_ABI_EXPORTED)
    message(FATAL_ERROR
        "mcf5307: step 4a failed: control D: the probe symbol "
        "`mcf5307_abi_probe_hidden` is among the EXPORTED symbols of "
        "${MCF5307_ABI_OBJECT}.\n"
        "  exported : ${MCF5307_ABI_EXPORTED}\n"
        "It carries `visibility(\"hidden\")`. A reader that calls it exported "
        "calls every hidden symbol exported, and the whole gate then passes "
        "whatever it is given.")
endif()

if("mcf5307_abi_probe_absent" IN_LIST MCF5307_ABI_DEFINED
        OR "mcf5307_abi_probe_absent" IN_LIST MCF5307_ABI_EXPORTED)
    message(FATAL_ERROR
        "mcf5307: step 4a failed: control D: the name "
        "`mcf5307_abi_probe_absent` was read out of ${MCF5307_ABI_OBJECT}.\n"
        "Nothing defines it anywhere in this project. A reader that reports it "
        "reports names the object does not hold, and its `visible` verdicts "
        "are then worth nothing.")
endif()

message(STATUS
    "mcf5307: step 4a control D the symbol reader separated visible, hidden "
    "and absent on ${MCF5307_ABI_OBJECT} (symbol prefix: "
    "`${MCF5307_ABI_PREFIX}`)")

# ---------------------------------------------------------------------------
# The Nim runtime scaffolding.
#
# Those names belong to the Nim runtime under `--nimMainPrefix:`. The contract
# does not declare them, and the undeclared-export check below would otherwise
# stop over them. They are reported instead.
set(MCF5307_ABI_SCAFFOLDING "")
foreach(suffix
        NimMain NimMainInner NimMainModule
        PreMain PreMainInner NimDestroyGlobals)
    list(APPEND MCF5307_ABI_SCAFFOLDING "${MCF5307_NIM_BUILT_PREFIX}${suffix}")
endforeach()

# The two probe names are this file's own instrument. They are in the
# measurement object and they are in no shipped artifact.
set(MCF5307_ABI_INSTRUMENT
    mcf5307_abi_probe_visible mcf5307_abi_probe_hidden)

# ---------------------------------------------------------------------------
# The verdict. Three categories, and each name lands in exactly one.
#
#   VISIBLE            published, defined, exported.        Pass.
#   HIDDEN             published, defined, NOT exported.    FAILS THE CONFIGURE
#                                                           STEP.
#   NOT IMPLEMENTED    published and NOT defined.           Reported, not a
#                                                           fault.
#
# THE THIRD CATEGORY IS A SEPARATE LINE AND A SEPARATE WORD. The reader before
# this one reported `not defined in this compilation` for both `a later cpu
# task writes this` and `the reader could not see it`. Those two must never
# share a line. The `defined` set is what separates them, and control D is what
# proves the `defined` set works.

set(MCF5307_ABI_VISIBLE "")
set(MCF5307_ABI_HIDDEN "")
set(MCF5307_ABI_UNIMPLEMENTED "")
foreach(name IN LISTS MCF5307_ABI_PUBLISHED)
    if(NOT name IN_LIST MCF5307_ABI_DEFINED)
        list(APPEND MCF5307_ABI_UNIMPLEMENTED "${name}")
    elseif(name IN_LIST MCF5307_ABI_EXPORTED)
        list(APPEND MCF5307_ABI_VISIBLE "${name}")
    else()
        list(APPEND MCF5307_ABI_HIDDEN "${name}")
    endif()
endforeach()

if(NOT MCF5307_ABI_HIDDEN STREQUAL "")
    message(FATAL_ERROR
        "mcf5307: step 4a failed: ${MCF5307_ABI_CONTRACT_FILE} publishes a "
        "symbol that the shared object DEFINES AND DOES NOT EXPORT.\n"
        "  hidden          : ${MCF5307_ABI_HIDDEN}\n"
        "  visible         : ${MCF5307_ABI_VISIBLE}\n"
        "  measured object : ${MCF5307_ABI_OBJECT}\n"
        "  symbol lister   : ${MCF5307_ABI_NM}\n"
        "A consumer of the plugin cannot reach a name that is not exported. "
        "The static archive still builds and `nm` over the archive still "
        "reports the name, so this step is the only one that reports the "
        "fault.\n"
        "THE USUAL CAUSE IS A PRAGMA SET WITHOUT `dynlib`. `src/mcf5307.nim` "
        "defines `mcf5307Abi` as `cdecl, dynlib` together for exactly this "
        "reason. A procedure declared `{.exportc: \"<c name>\", cdecl.}` "
        "alone is hidden. Write `{.exportc: \"<c name>\", mcf5307Abi.}` "
        "instead. An exported VARIABLE needs `{.exportc: \"<c name>\", "
        "dynlib.}`.")
endif()

# ---------------------------------------------------------------------------
# The other direction. An exported name the contract does not declare.
#
# A consumer cannot call a symbol it cannot declare. This check is also a
# CONSTRAINT ON THIS PROJECT, and `src/mcf5307.nim` records it: CPU-1 cannot
# add an exported status symbol of its own, because the contract belongs to
# CPU-0 and this step refuses an export the contract does not carry.
set(MCF5307_ABI_UNDECLARED "")
foreach(name IN LISTS MCF5307_ABI_EXPORTED)
    if(name IN_LIST MCF5307_ABI_PUBLISHED
            OR name IN_LIST MCF5307_ABI_SCAFFOLDING
            OR name IN_LIST MCF5307_ABI_INSTRUMENT)
        continue()
    endif()
    list(APPEND MCF5307_ABI_UNDECLARED "${name}")
endforeach()
if(NOT MCF5307_ABI_UNDECLARED STREQUAL "")
    message(FATAL_ERROR
        "mcf5307: step 4a failed: the shared object exports a name that "
        "${MCF5307_ABI_CONTRACT_FILE} does not declare.\n"
        "  undeclared : ${MCF5307_ABI_UNDECLARED}\n"
        "Either the contract lost the declaration, or this project exported "
        "something the contract never promised. A symbol a consumer cannot "
        "declare is a symbol a consumer cannot call.")
endif()

# ---------------------------------------------------------------------------
# The report.

list(LENGTH MCF5307_ABI_PUBLISHED MCF5307_ABI_PUBLISHED_COUNT)
list(LENGTH MCF5307_ABI_VISIBLE MCF5307_ABI_VISIBLE_COUNT)
list(LENGTH MCF5307_ABI_UNIMPLEMENTED MCF5307_ABI_UNIMPLEMENTED_COUNT)

message(STATUS
    "mcf5307: step 4a ${MCF5307_ABI_CONTRACT_FILE} publishes "
    "${MCF5307_ABI_PUBLISHED_COUNT} symbol(s), read by ${MCF5307_ABI_PARSER} "
    "(${MCF5307_ABI_PARSER_SOURCE})")
message(STATUS
    "mcf5307: step 4a ${MCF5307_ABI_VISIBLE_COUNT} of them are DEFINED AND "
    "EXPORTED by the measurement shared object: ${MCF5307_ABI_VISIBLE}")
message(STATUS
    "mcf5307: step 4a ${MCF5307_ABI_UNIMPLEMENTED_COUNT} of them are NOT YET "
    "IMPLEMENTED. No compilation unit defines them, and a later cpu task "
    "writes them: ${MCF5307_ABI_UNIMPLEMENTED}")

# The scaffolding report. Design section 5.4 rule 2 asks C++ never to call the
# runtime entry point directly. `include/mcf5307.h` does not declare it, and
# that is the whole barrier. This line prints what the shared object actually
# exports, so the fact sits in the configure log rather than nowhere. A
# mechanism would be a linker export list, and that belongs to the build that
# makes the shipped shared object.
set(MCF5307_ABI_REACHABLE "")
foreach(name IN LISTS MCF5307_ABI_SCAFFOLDING)
    if(name IN_LIST MCF5307_ABI_EXPORTED)
        list(APPEND MCF5307_ABI_REACHABLE "${name}")
    endif()
endforeach()
if(NOT MCF5307_ABI_REACHABLE STREQUAL "")
    message(STATUS
        "mcf5307: step 4a NOTE: the runtime scaffolding a consumer can reach: "
        "${MCF5307_ABI_REACHABLE}. Design section 5.4 rule 2 asks C++ not to "
        "call it, the contract header does not declare it, and no mechanism "
        "here enforces that. This line is a report and not a check.")
endif()

# ---------------------------------------------------------------------------
# Step 4a, part two. THE SMOKE-TEST LIST GATE.
#
# WHAT IT PROTECTS. `tests/abi_smoke.cpp` states its own invariant as taking
# the address of every function the contract header declares. That sentence
# was FALSE for two symbols: `mcf5307_set_reg` and `mcf5307_get_reg` reached
# the contract with CPU-7 and never reached the test, so a rename of either
# one was not a link error in the one test whose stated job is the ABI
# surface. Nothing measured the gap, which is exactly why it opened.
#
# WHY THE CHECK LIVES HERE AND NOT IN THE TEST. The published set is what the
# list must equal, and the published set is parsed HERE, by a C compiler,
# above. A count asserted inside the test would be a third hand-maintained
# number beside the list and the header, and it would fall behind them the
# same way. This block compares two SETS and asserts no number at all.
#
# IT FAILS IN BOTH DIRECTIONS.
#
#   A name the contract declares and the list omits. That is the defect this
#   block was written for, and the message names the symbol.
#
#   A name the list carries and the contract does not declare. The C++ side
#   also refuses that one - `&name` needs a declaration - but it refuses it
#   with a compiler diagnostic about a test file, at build time, and this
#   block refuses it at configure time and says which of the two files is
#   wrong.
#
# THE LIST IS READ AND THE TEST'S C++ IS NOT. `tests/abi_smoke_symbols.inc`
# holds nothing but blank lines, comment lines and the entry macro, so the
# reader below needs no C parser and no preprocessor. That is the whole reason
# the list is a separate file. THE GRAMMAR IS TOTAL: every line lands in
# exactly one of those three shapes or FAILS THE CONFIGURE STEP with its line
# number. A line that carries `MCF5307_ABI_FN` in a shape the C++ side would
# expand but this reader would not - a leading space, a trailing comment, a
# semicolon - is a failure and never a skip.
#
# A COMMENTED-OUT ENTRY NEEDS NO SPECIAL RULE, and the reader deliberately has
# none. Both readers skip a comment, so both stop seeing the name, and the
# comparison against the CONTRACT is what fails: the header still declares the
# symbol and the list no longer names it. This block compares two sets and
# never a count, so a name it cannot see is a name it reports as missing. That
# is why the comment shape is tested BEFORE the macro shape below, and why
# this file's own prose may name the macro.
#
# WHEN THE GATE IS OFF THIS CHECK DOES NOT RUN, because there is no published
# set to compare against. The warning that `-DMCF5307_ABI_GATE=OFF` prints
# already says the configure run measured nothing.

if(NOT EXISTS "${MCF5307_ABI_SMOKE_LIST_FILE}")
    message(FATAL_ERROR
        "mcf5307: step 4a failed: ${MCF5307_ABI_SMOKE_LIST_FILE} does not "
        "exist. That file is the symbol list of `tests/abi_smoke.cpp`, the "
        "test includes it twice, and this step compares it against the "
        "published set of ${MCF5307_ABI_CONTRACT_FILE}.")
endif()

file(READ "${MCF5307_ABI_SMOKE_LIST_FILE}" MCF5307_ABI_SMOKE_TEXT)
string(REPLACE "\r" "" MCF5307_ABI_SMOKE_TEXT "${MCF5307_ABI_SMOKE_TEXT}")
# A semicolon in the text would split one line into two list elements and the
# line numbers below would drift. Escaping it keeps every line one element.
string(REPLACE ";" "\\;" MCF5307_ABI_SMOKE_TEXT "${MCF5307_ABI_SMOKE_TEXT}")
string(REPLACE "\n" ";" MCF5307_ABI_SMOKE_LINES "${MCF5307_ABI_SMOKE_TEXT}")

set(MCF5307_ABI_SMOKE_NAMES "")
set(MCF5307_ABI_SMOKE_LINE_NUMBER 0)
foreach(MCF5307_ABI_SMOKE_LINE IN LISTS MCF5307_ABI_SMOKE_LINES)
    math(EXPR MCF5307_ABI_SMOKE_LINE_NUMBER
        "${MCF5307_ABI_SMOKE_LINE_NUMBER} + 1")

    if(MCF5307_ABI_SMOKE_LINE MATCHES "^[ \t]*$")
        continue()
    endif()

    # A comment line. The file's own header block is written this way, and it
    # names the entry macro in its prose. The paragraph above says why a
    # comment may be skipped without opening a hole: a name this reader cannot
    # see is a name it reports as missing from the contract's published set.
    if(MCF5307_ABI_SMOKE_LINE MATCHES "^[ \t]*(/\\*|\\*)")
        continue()
    endif()

    # The entry form, anchored at both ends. THE CAPTURE IS COPIED OUT BEFORE
    # THE NEXT `MATCHES` RUNS, for the reason the symbol reader above records.
    if(MCF5307_ABI_SMOKE_LINE MATCHES
            "^MCF5307_ABI_FN\\(([A-Za-z_][A-Za-z0-9_]*)\\)$")
        set(MCF5307_ABI_SMOKE_NAME "${CMAKE_MATCH_1}")
        if(MCF5307_ABI_SMOKE_NAME IN_LIST MCF5307_ABI_SMOKE_NAMES)
            message(FATAL_ERROR
                "mcf5307: step 4a failed: ${MCF5307_ABI_SMOKE_LIST_FILE} line "
                "${MCF5307_ABI_SMOKE_LINE_NUMBER} repeats the entry "
                "`${MCF5307_ABI_SMOKE_NAME}`, which an earlier line already "
                "carries. The test declares one pointer per entry, so a "
                "repeat is a redefinition there. The list is a set and this "
                "step compares it as one.")
        endif()
        list(APPEND MCF5307_ABI_SMOKE_NAMES "${MCF5307_ABI_SMOKE_NAME}")
        continue()
    endif()

    # A line that is not a comment, that mentions the macro, and that is not
    # an entry. An entry with a leading space, a trailing comment or a
    # semicolon lands here. THE C++ SIDE WOULD EXPAND IT AND THIS READER WOULD
    # NOT, and that disagreement is the one shape this comparison cannot
    # survive, because it makes the test take an address of a name this step
    # never saw. It is refused rather than guessed at.
    if(MCF5307_ABI_SMOKE_LINE MATCHES "MCF5307_ABI_FN")
        message(FATAL_ERROR
            "mcf5307: step 4a failed: ${MCF5307_ABI_SMOKE_LIST_FILE} line "
            "${MCF5307_ABI_SMOKE_LINE_NUMBER} carries `MCF5307_ABI_FN` and is "
            "neither an entry nor a comment.\n"
            "  line : ${MCF5307_ABI_SMOKE_LINE}\n"
            "An entry is exactly `MCF5307_ABI_FN(<identifier>)` with no "
            "leading space, no trailing text and no semicolon. The C++ side "
            "would expand this line and this step would not have counted it, "
            "so the two would disagree about what the list holds.")
    endif()

    message(FATAL_ERROR
        "mcf5307: step 4a failed: ${MCF5307_ABI_SMOKE_LIST_FILE} line "
        "${MCF5307_ABI_SMOKE_LINE_NUMBER} is neither blank, nor a comment, "
        "nor an entry.\n"
        "  line : ${MCF5307_ABI_SMOKE_LINE}\n"
        "That file is data and not C. `tests/abi_smoke.cpp` includes it twice "
        "with two different definitions of `MCF5307_ABI_FN`, and anything "
        "else in it would expand into both of them.")
endforeach()

if(MCF5307_ABI_SMOKE_NAMES STREQUAL "")
    message(FATAL_ERROR
        "mcf5307: step 4a failed: ${MCF5307_ABI_SMOKE_LIST_FILE} holds no "
        "entry at all. An empty list makes the smoke test take no address, "
        "and the comparison below would then report every published symbol as "
        "missing. Silence is not a pass.")
endif()

# The comparison. Two directions, two messages, and each one names the
# symbols rather than a count.
set(MCF5307_ABI_SMOKE_MISSING "")
foreach(name IN LISTS MCF5307_ABI_PUBLISHED)
    if(NOT name IN_LIST MCF5307_ABI_SMOKE_NAMES)
        list(APPEND MCF5307_ABI_SMOKE_MISSING "${name}")
    endif()
endforeach()

set(MCF5307_ABI_SMOKE_EXTRA "")
foreach(name IN LISTS MCF5307_ABI_SMOKE_NAMES)
    if(NOT name IN_LIST MCF5307_ABI_PUBLISHED)
        list(APPEND MCF5307_ABI_SMOKE_EXTRA "${name}")
    endif()
endforeach()

if(NOT MCF5307_ABI_SMOKE_MISSING STREQUAL "")
    message(FATAL_ERROR
        "mcf5307: step 4a failed: ${MCF5307_ABI_CONTRACT_FILE} publishes a "
        "symbol that ${MCF5307_ABI_SMOKE_LIST_FILE} does not name.\n"
        "  missing from the test : ${MCF5307_ABI_SMOKE_MISSING}\n"
        "  published             : ${MCF5307_ABI_PUBLISHED}\n"
        "  named by the test     : ${MCF5307_ABI_SMOKE_NAMES}\n"
        "`tests/abi_smoke.cpp` states its invariant as taking the address of "
        "EVERY function the contract declares, and a symbol it does not name "
        "is a symbol whose rename that test cannot catch. Add one "
        "`MCF5307_ABI_FN(<name>)` line to the list file for each name above. "
        "The test's array grows with the list and carries no written length.")
endif()

if(NOT MCF5307_ABI_SMOKE_EXTRA STREQUAL "")
    message(FATAL_ERROR
        "mcf5307: step 4a failed: ${MCF5307_ABI_SMOKE_LIST_FILE} names a "
        "symbol that ${MCF5307_ABI_CONTRACT_FILE} does not declare.\n"
        "  named by the test and not published : ${MCF5307_ABI_SMOKE_EXTRA}\n"
        "  published                           : ${MCF5307_ABI_PUBLISHED}\n"
        "  named by the test                   : ${MCF5307_ABI_SMOKE_NAMES}\n"
        "Either the contract lost the declaration, or the list names "
        "something that was never in the contract. The C++ compiler refuses "
        "the second one too, at build time, and this message says which of "
        "the two files to change.")
endif()

list(LENGTH MCF5307_ABI_SMOKE_NAMES MCF5307_ABI_SMOKE_COUNT)
message(STATUS
    "mcf5307: step 4a ${MCF5307_ABI_SMOKE_LIST_FILE} names exactly the "
    "${MCF5307_ABI_SMOKE_COUNT} published symbol(s), so `tests/abi_smoke.cpp` "
    "takes the address of every one of them")

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
