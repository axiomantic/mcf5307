# CMake drives Nim. The repository ships Nim source plus build integration, and
# never a prebuilt `.a`. Six integration steps run here, in order, and each one
# reports itself by number.
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
# Step 1. The version pin. It is exact, and a mismatch fails the configure step
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
# The flag set holds no `--checks:off` and no `-d:danger`. With `-d:release`
# alone the run-time checks stay compiled in. Removing them turns a defect that
# ends the process into a defect that returns a wrong value and exits 0.

set(MCF5307_NIMCACHE "${PROJECT_BINARY_DIR}/nimcache")
set(MCF5307_NIM_HEADER "mcf5307_nim.h")

# The flags that govern the generated code. They are held apart from the
# command for two reasons. A second Nim project repeats them unchanged, and a
# Nim test program must be compiled with the same set. A test compiled with a
# different set proves nothing about the library the set governs.
set(MCF5307_NIM_FLAGS --mm:arc --panics:on -d:release)

# The Nim entry modules of this project. A second Nim library appends its name
# here and writes its own command below, with its own `--nimMainPrefix:` value.
# Step 2a reads this list.
set(MCF5307_NIM_ENTRIES mcf5307)

# Each entry module's source file and its command are written out, and neither
# is derived from the entry name. A derived prefix cannot collide. It would
# therefore make the duplicate half of step 2a unable to fail. A check that
# cannot fail is worse than no check.
set(MCF5307_NIM_SOURCE_mcf5307 "${PROJECT_SOURCE_DIR}/src/mcf5307.nim")
# `--path:src` puts the package root on the Nim search path so that the
# entry module's `import mcf5307/<sub>` resolves to `src/mcf5307/<sub>.nim`.
# The submodules of the core live under `src/mcf5307/`, and
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
# Step 2a. The prefix check.
#
# `--nimMainPrefix:` renames the Nim runtime entry point of one Nim project.
# Two Nim projects in one binary that keep the default names collide on
# `NimMain`, `NimMainInner` and `NimMainModule` at link.
#
# With the flag deleted the configure step succeeds, the build succeeds and the
# archive is written, all without one diagnostic: a static archive tolerates an
# undefined symbol, so `libmcf5307.a` then carries an undefined
# `mcf5307_NimMain` beside an unprefixed `NimMain`, and nothing fails until a
# consumer's final link, in a different repository, at a later time. The
# configure step is the last place at which the fault is still local to this
# project.
#
# The check has three steps and only the second one is fatal.
#
#   1  count the entry modules
#   2  assert that every entry module's command carries a `--nimMainPrefix:`
#      and that no two prefixes are equal - fails the configure step
#   3  when the count is above one, print one line that names the build
#      integration a second entry module costs - does not fail
#
# It reads the commands and not a separate declaration of intent. The command
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

# Check step 3. A note and not a failure.
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
# Steps 2 to 6 build the FIRST entry module in MCF5307_NIM_ENTRIES, and the
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

# The contract header. It is read here and never written here. The name is set
# at this point because the line below has to name it, and step 4a reads the
# same variable.
set(MCF5307_ABI_CONTRACT_FILE "${PROJECT_SOURCE_DIR}/include/mcf5307.h")

# The smoke test's expected symbol list. It is read here and never written
# here. Step 4a compares it against the set it measures as defined and
# exported by the library, in both directions. It is
# named at this point for the same reason the contract header is: the
# dependency list below has to carry it.
set(MCF5307_ABI_SMOKE_LIST_FILE
    "${PROJECT_SOURCE_DIR}/tests/abi_smoke_symbols.inc")

# The link-partner stub of `t0_abi_header` cases 3 and 4. It is compiled here
# and never written here. Step 4a, part three reads
# the symbols its object defines and compares them against the same published
# set. It is named at this point for the reason the two files above are: the
# dependency list below has to carry it.
set(MCF5307_ABI_STUB_FILE "${PROJECT_SOURCE_DIR}/tests/abi_stub.c")

# Editing a configure-time input must re-run the configure step. The inputs
# are enumerated here, and the property below lists every one of them.
#
# No count is written. A count is a number beside an enumeration that nothing
# holds to it, and the enumeration is what a reader has to check anyway.
#
#   `src/*.nim`        the unit list is read at configure time, and a new
#                      module adds a unit to it.
#   `.nim-version`     step 1 compares it against the compiler.
#   `include/mcf5307.h` step 4a reads the published set out of it.
#   `tests/abi_smoke_symbols.inc`
#                      step 4a reads the EXPECTED ABI out of it and compares
#                      it against the measured one. A list edited without a
#                      re-run would leave the comparison speaking about a
#                      version of the list that no longer exists - the exact
#                      failure the paragraph below records for the contract
#                      header.
#   `tests/abi_stub.c` step 4a compiles it and reads the symbols the object
#                      defines. A definition added or removed without a re-run
#                      would leave that comparison speaking about an object
#                      this tree can no longer produce.
#
# Drop the contract header from this list and an edit to it does not re-run the
# configure step: step 4a then keeps its verdict about a version of the
# contract that no longer exists, the build exits 0, and no diagnostic names
# the stale read. An edit to `src/mcf5307.nim` does re-run it, which is what
# makes that gap hard to see.
file(GLOB_RECURSE MCF5307_NIM_SOURCES CONFIGURE_DEPENDS
    "${PROJECT_SOURCE_DIR}/src/*.nim")
set_property(DIRECTORY "${PROJECT_SOURCE_DIR}"
    APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
    ${MCF5307_NIM_SOURCES} "${MCF5307_NIM_VERSION_FILE}"
    "${MCF5307_ABI_CONTRACT_FILE}" "${MCF5307_ABI_SMOKE_LIST_FILE}"
    "${MCF5307_ABI_STUB_FILE}")

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
# mechanisms hold it apart from this project's warning policy.
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
# The flag is `-Wno-error` and not `-w`. Measured with `-Wall -Wextra -Werror`:
# both build clean, `-Wno-error` leaves the warnings in the build log and `-w`
# leaves none there. A silent warning channel over the one body of code nobody
# here reviews is the worse trade.
#
# `tests/tests_cpu.cmake` already compiles with `-Wall -Wextra -pedantic
# -Werror`.
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
# archive reports zero matches for `pthread` and matches for
# `__tlv_bootstrap`, so the command did read the archive. Nim's own link
# command in the JSON build file carries `-ldl` and no `-lpthread`. The
# thread-local storage the runtime uses goes through the platform's own
# mechanism.
#
# The dependency is kept and is not required. A host that holds the thread
# functions in a separate library needs the flag once something here creates a
# thread. A host without a thread library configures today, because nothing in
# the current object set calls into one.
set(THREADS_PREFER_PTHREAD_FLAG ON)
find_package(Threads)
if(TARGET Threads::Threads)
    target_link_libraries(mcf5307_nim_objs PUBLIC Threads::Threads)
endif()

message(STATUS "mcf5307: step 4 the object library mcf5307_nim_objs is defined")

# ---------------------------------------------------------------------------
# Step 4a. The visibility gate.
#
# The delivery form is a JUCE plugin, and a plugin is a shared object. Every
# symbol `include/mcf5307.h` publishes must leave that shared object with
# default visibility. Nim decides that in the pragma set of the declaration.
# Measured on Nim 2.2.10, `{.exportc, cdecl.}` alone gives a hidden symbol, and
# `dynlib` added to the set gives a visible one.
#
# `nm` over the static archive reports a hidden symbol exactly as it reports a
# visible one. The shared object is the first artifact that tells the two
# apart, so this step builds one.
#
# The gate asks two tools and parses no C of its own.
#
#   The published set comes from a C compiler. A generated translation unit
#   includes the contract header. `-Xclang -ast-dump=json` prints the syntax
#   tree of that unit, and this file reads the function and object declarations
#   out of the tree.
#
#   The exported set comes from the linker. This file builds a shared object
#   from the generated C units and reads its symbol table with `nm`. That is
#   the delivery-form property itself and not an opinion about it.
#
# The verdict is a comparison of sets. A published name that the shared object
# defines and does not export is a fault. A published name that the shared
# object does not define at all is NOT a fault, and the report keeps the two
# apart.
#
# The gate knows nothing about `N_LIB_EXPORT`, `N_LIB_EXPORT_VAR` or
# `N_LIB_PRIVATE`. Those macros are one Nim release's way to write a visibility
# attribute. The linker reports the result of the attribute, so the gate reads
# the result and never the macro. A Nim release that renames the macros changes
# nothing here.
#
# A regular expression over the header text cannot do this job. Seven ordinary
# shapes defeat one, in both directions:
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
# A compiler handles all seven by construction, and the calibration below
# proves that on every configure run.
#
# `include/mcf5307.h` is read here and never written here.

# ---------------------------------------------------------------------------
# The escape hatch, and why it is loud.
#
# The gate needs a Clang-compatible C parser and an `nm`. A host without both
# cannot run it. The gate then FAILS the configure step and names the tool it
# did not find, because a check that quietly does not run is the fault this
# whole block exists to end.
#
# `-DMCF5307_ABI_GATE=OFF` configures such a host, and prints a warning on
# every configure run.
#
# The gate costs roughly half of this project's configure time, of which the
# controls that exist only to fire the gate's own fatal branches are about an
# eighth. Turning it off buys that back in exchange for a build whose published
# symbols nobody measured. To take a current figure, run `cmake` with
# `--profiling-output=... --profiling-format=google-trace`.
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
# The unit carries two sentinel declarations, one before the include and one
# after it. They are the per-read control of the file attribution below. The
# caller asserts that the fold attributed exactly those two to the unit itself.
# A fold that lost the attribution and gave everything to the header would put
# the sentinels in the published set. A fold that gave nothing to the header
# would still show them. Neither failure can pass this pair.
#
# Clang prints `loc.file` on a node only when the file differs from the
# previous node's file. The fold therefore carries the last file it saw
# forward, exactly as the printer expects. A declaration that no file covers
# goes into the unattributed list, and the caller stops over it.
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
# The per-read control of the reader above. It runs on the calibration read AND
# on the contract read, so the fold is calibrated on the very read whose answer
# is used. The expected answer is written out here, so a blind fold cannot
# produce it.
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
# neither set. One `defined` set alone cannot tell those apart.
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
            # The two captures are copied out before the next `MATCHES` runs.
            # A second `MATCHES` overwrites `CMAKE_MATCH_1` and `CMAKE_MATCH_2`
            # on a hit AND clears them on a miss. Reading them afterwards gives
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
# The calibration header below carries every shape that defeats a regular
# expression, plus four shapes that publish nothing and one declaration behind
# `#if 0`. The expected answer is written out. A reader that lost a shape, that
# reported a type keyword, or that reported a type name cannot produce it.
#
# The check runs on every configure run.

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
# The consumer's `CMAKE_C_FLAGS` are not passed here. This object is a
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
# The visible probe also measures the platform's symbol prefix. Mach-O puts one
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
# The third category gets a separate line and a separate word. `nothing
# implements this yet` and `the reader could not see it` must never share a
# line. The `defined` set is what separates them, and control D is what proves
# the `defined` set works.

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
# A consumer cannot call a symbol it cannot declare. This check also constrains
# this project: no new exported symbol can be added in `src/mcf5307.nim` until
# `include/mcf5307.h` declares it, because this step refuses an export the
# contract does not carry.
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

# The scaffolding report. C++ never calls the runtime entry point directly.
# `include/mcf5307.h` does not declare it, and that is the whole barrier. This
# line prints what the shared object actually exports, so the fact sits in the
# configure log rather than nowhere. A mechanism would be a linker export list,
# and that belongs to the build that makes the shipped shared object.
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
# Step 4a, part two. The smoke-test list gate.
#
# Two mechanisms, wired together, because each one alone fails silently.
#
#   The measured set is the fact. `tests/tests_cpu.cmake` generates the
#   address set of `tests/abi_smoke.cpp` from `MCF5307_ABI_VISIBLE`, the set
#   this step measured as defined and exported by the library. That is what
#   makes the test buildable at all: most of the published surface has no
#   definition yet, and taking the address of an undefined name is an
#   unresolved symbol that takes the whole build down. A measured set also
#   grows on its own, so implementing a published name brings it under this
#   test with no edit anywhere.
#
#   A measured set alone cannot report an ABI addition nobody intended. It
#   simply grows, and the check still passes.
#
#   The committed list is the expectation. `tests/abi_smoke_symbols.inc` names
#   the symbols this project intends the library to define and export. A
#   committed list alone goes stale the moment somebody forgets to update it.
#
#   So the two are compared, and a mismatch in either direction fails here.
#   An unintended addition to the exported ABI then stops the configure step
#   with the symbol named, and shows up as a diff in
#   `tests/abi_smoke_symbols.inc` for a reviewer to read.
#
# The check lives here and not in the test because the measured set is
# measured here, by `nm` over a real shared object, above. This block compares
# two sets and asserts no number at all.
#
# It fails in both directions.
#
#   A name the library defines and exports and the list omits. That is an
#   ABI addition nobody wrote down, and the message names the symbol.
#
#   A name the list carries and the library does not define. That is an ABI
#   symbol that was expected and is gone - a rename, a dropped definition, or
#   an `exportc` name that changed. The link of `abi_smoke` would not catch
#   it, because the generated address set shrank with the measurement, so this
#   direction is the one the committed list exists for.
#
# The whole published set has its own committed two-way roster, and it is not
# this file. `tests/abi_stub.c` must define externally exactly the set
# `include/mcf5307.h` declares, and part three below fails in both directions
# over it.
#
# The list is read and the test's C++ is not. `tests/abi_smoke_symbols.inc`
# holds nothing but blank lines, comment lines and the entry macro, so the
# reader below needs no C parser and no preprocessor. That is the whole reason
# the list is a separate file. The grammar is total: every line lands in
# exactly one of those three shapes or fails the configure step with its line
# number. A line that carries `MCF5307_ABI_FN` in a shape the C++ side would
# expand but this reader would not - a leading space, a trailing comment, a
# semicolon - is a failure and never a skip.
#
# A commented-out entry needs no special rule. This reader skips a comment, so
# it stops seeing the name, and the comparison against the measurement is what
# fails: the library still exports the symbol and the list no longer names it.
# That is why the comment shape is tested before the macro shape below, and
# why this file's own prose may name the macro.
#
# The reader is stricter than it needs to be, on purpose: a line it cannot
# classify is a line whose intent is unclear, and the expectation half of a
# two-way comparison may not be read by guesswork.
#
# When the gate is off this check does not run, because there is no measured
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
    # semicolon lands here. A READER THAT GUESSED AT IT WOULD PUT A NAME INTO
    # THE EXPECTATION THAT NOBODY WROTE, or drop one that somebody did, and
    # either way the comparison below would speak about a list that is not on
    # disk. It is refused rather than guessed at.
    if(MCF5307_ABI_SMOKE_LINE MATCHES "MCF5307_ABI_FN")
        message(FATAL_ERROR
            "mcf5307: step 4a failed: ${MCF5307_ABI_SMOKE_LIST_FILE} line "
            "${MCF5307_ABI_SMOKE_LINE_NUMBER} carries `MCF5307_ABI_FN` and is "
            "neither an entry nor a comment.\n"
            "  line : ${MCF5307_ABI_SMOKE_LINE}\n"
            "An entry is exactly `MCF5307_ABI_FN(<identifier>)` with no "
            "leading space, no trailing text and no semicolon. A line this "
            "step cannot classify is a line it would have to guess at, and "
            "the expectation half of a two-way comparison is not guessed.")
    endif()

    message(FATAL_ERROR
        "mcf5307: step 4a failed: ${MCF5307_ABI_SMOKE_LIST_FILE} line "
        "${MCF5307_ABI_SMOKE_LINE_NUMBER} is neither blank, nor a comment, "
        "nor an entry.\n"
        "  line : ${MCF5307_ABI_SMOKE_LINE}\n"
        "That file is data and not C. It is the committed expectation this "
        "step compares against the measured exported set, and anything else "
        "in it has no meaning to either reader.")
endforeach()

if(MCF5307_ABI_SMOKE_NAMES STREQUAL "")
    message(FATAL_ERROR
        "mcf5307: step 4a failed: ${MCF5307_ABI_SMOKE_LIST_FILE} holds no "
        "entry at all. An empty expectation would report every symbol the "
        "library exports as an unintended addition, and an empty measured set "
        "is refused separately. Silence is not a pass.")
endif()

# The comparison. The measured set is the fact and the list is the
# expectation. Two directions, two messages, and each one names the symbols
# rather than reporting a count or the bare word `differ`, so a reviewer knows
# which symbol to act on and which file to change.
set(MCF5307_ABI_SMOKE_UNEXPECTED "")
foreach(name IN LISTS MCF5307_ABI_VISIBLE)
    if(NOT name IN_LIST MCF5307_ABI_SMOKE_NAMES)
        list(APPEND MCF5307_ABI_SMOKE_UNEXPECTED "${name}")
    endif()
endforeach()

set(MCF5307_ABI_SMOKE_ABSENT "")
foreach(name IN LISTS MCF5307_ABI_SMOKE_NAMES)
    if(NOT name IN_LIST MCF5307_ABI_VISIBLE)
        list(APPEND MCF5307_ABI_SMOKE_ABSENT "${name}")
    endif()
endforeach()

if(NOT MCF5307_ABI_SMOKE_UNEXPECTED STREQUAL "")
    message(FATAL_ERROR
        "mcf5307: step 4a failed: the library DEFINES AND EXPORTS a published "
        "symbol that ${MCF5307_ABI_SMOKE_LIST_FILE} does not name.\n"
        "  added to the ABI and not expected : ${MCF5307_ABI_SMOKE_UNEXPECTED}\n"
        "  measured (defined and exported)   : ${MCF5307_ABI_VISIBLE}\n"
        "  expected by the committed list    : ${MCF5307_ABI_SMOKE_NAMES}\n"
        "The measured set is the FACT and the list is the EXPECTATION. A "
        "measured set on its own would simply grow and this step would still "
        "pass, so an export nobody intended would be adopted in silence. If "
        "the addition is intended, add one `MCF5307_ABI_FN(<name>)` line to "
        "the list file for each name above and the diff is what a reviewer "
        "reads. If it is not intended, the library grew an export it should "
        "not have.")
endif()

if(NOT MCF5307_ABI_SMOKE_ABSENT STREQUAL "")
    message(FATAL_ERROR
        "mcf5307: step 4a failed: ${MCF5307_ABI_SMOKE_LIST_FILE} names a "
        "symbol the library does NOT define and export.\n"
        "  expected and missing from the ABI : ${MCF5307_ABI_SMOKE_ABSENT}\n"
        "  measured (defined and exported)   : ${MCF5307_ABI_VISIBLE}\n"
        "  expected by the committed list    : ${MCF5307_ABI_SMOKE_NAMES}\n"
        "  not yet implemented               : ${MCF5307_ABI_UNIMPLEMENTED}\n"
        "Either a definition was renamed or dropped, or its `exportc` name "
        "changed, or the list names something the library was never going to "
        "define. THE LINK OF `abi_smoke` CANNOT CATCH THIS: its address set is "
        "generated from the measurement, so it shrank along with the ABI and "
        "linked clean. This direction is the whole reason the committed list "
        "exists beside the measurement.")
endif()

list(LENGTH MCF5307_ABI_SMOKE_NAMES MCF5307_ABI_SMOKE_COUNT)
message(STATUS
    "mcf5307: step 4a ${MCF5307_ABI_SMOKE_LIST_FILE} expects exactly the "
    "${MCF5307_ABI_SMOKE_COUNT} symbol(s) the library defines and exports, so "
    "`tests/abi_smoke.cpp` takes the address of every one of them and no ABI "
    "addition or loss can pass unnamed")

# ---------------------------------------------------------------------------
# Step 4a, part three. The link-partner stub gate.
#
# `tests/abi_stub.c` claims one definition, with an empty body, of every
# function the contract declares. This gate is what holds that claim true.
#
# The stub must define the whole published set because it is the link partner
# of cases 3 and 4 of `t0_abi_header`, and those two cases exist to make a
# renamed declaration a link error rather than nothing at all. A reference
# with no definition anywhere is an undefined symbol at that link, so the pair
# can only report a rename for a name the stub defines.
#
# Nothing here reads the stub's source text, and nothing here parses C. The
# smoke-test list above is a separate data file precisely so that its reader
# needs no C parser. That trick does not transfer: a stub is real C with a
# real body and a different signature per function, so no list of names
# generates it. The set is therefore read the way the exported set of the
# measurement shared object is read above - the file is compiled, and `nm`
# reports what the object defines. A regular expression may not be trusted to
# say what C declares, and the shapes in the calibration header above are why.
#
# The measurement is over external definitions. `nm -g` reports what the link
# of `t0_abi_header` can resolve against. A published name defined `static`
# resolves nothing there, so it is a fault with a message of its own. The
# `all` pass is read as well, because it is what separates `defined with
# internal linkage` from `not defined at all` - the same separation the
# visibility verdict above draws between `hidden` and `not implemented yet`,
# and for the same reason: two different faults must never share a line.
#
# It fails in both directions.
#
#   A published name the stub does not define externally. That is the defect
#   this block was written for, and the message names the symbol.
#
#   An external name the stub defines that the contract does not declare. This
#   translation unit is linked into two test executables, and a name of its
#   own there is either a contract that lost a declaration or a stub that grew
#   something outside its job. An internal name is exempt: a `static` helper
#   publishes nothing and can collide with nothing.
#
# The consumer's `CMAKE_C_FLAGS` are not passed here, for the reason the
# measurement shared object gives above: this object is an instrument and it
# is never shipped. The registered test `t0_abi_header` compiles the same file
# with `-Wall -Wextra -pedantic -Werror`, and that is where a warning in it is
# a failure.
#
# `tests/abi_stub.c` is read here and never written here.
#
# Which fatal branches of this part a control enters, and which it does not.
# Controls E through I below drive the branches that depend on a measurement -
# the reader, the three verdict categories, the unpublished-export answer, the
# internal-linkage route and the compile-fault split - because a measurement
# can be wrong while the run stays green, and those are the branches that then
# never fire. These fatal branches have no control and are not claimed to:
#
#   the stub source does not exist;
#   the compiler rejected the stub for a fault of the stub's own;
#   the compiler exited 0 and wrote no object;
#   control H's own precondition - the route name is not in the published set;
#   `nm` exited non-zero, inside `mcf5307_abi_read_symbols` far above.
#
#   Control H's guard is not written as a control and is not one. It fails
#   when `MCF5307_ABI_STUB_ROUTE_NAME` is absent from the published set, and no
#   control plants a contract that has lost `mcf5307_runtime_init`. It exists
#   because control C checks that the published set is non-empty and not that
#   it carries this name, so the membership is tested there or nowhere.
#
#   The reader's own `nm` branch is not written below - it lives in
#   `mcf5307_abi_read_symbols` - but this part reaches it twice: once for the
#   stub object, and once inside control H for each unit that arm compiles.
#
# Why each is uncontrolled:
#
#   The two `EXISTS` branches and the reader's `nm` exit status are each a
#   direct test of a condition this file did not compute, so there is no reading
#   in between for a control to calibrate.
#
#   The compile-fault branch does have a reading in between. Reaching it
#   requires `MCF5307_ABI_STUB_COMPILE_COLLIDED` to be false, that value is
#   computed by the `mcf5307_abi_stub_collided` call below, and control I
#   calibrates it in both directions. Only the exit status itself is
#   uncontrolled.
#
#   Control H's guard reads a set this file did compute, and control B
#   calibrates the reader that produces it. It is uncontrolled in the one sense
#   this heading means: no control makes it fire.
#
# Nothing here claims coverage beyond that.

if(NOT EXISTS "${MCF5307_ABI_STUB_FILE}")
    message(FATAL_ERROR
        "mcf5307: step 4a failed: ${MCF5307_ABI_STUB_FILE} does not exist. "
        "That file is the link partner of cases 3 and 4 of the registered "
        "test `t0_abi_header`, and this step compiles it and compares the "
        "symbols it defines against the published set of "
        "${MCF5307_ABI_CONTRACT_FILE}.")
endif()

set(MCF5307_ABI_STUB_OBJECT
    "${MCF5307_ABI_DIR}/abi_stub_measure${CMAKE_C_OUTPUT_EXTENSION}")

# The probe unit of part three.
#
# It is `-include`d and not compiled beside. That puts it in the same
# translation unit and therefore in the same object the verdict below is read
# from. A sibling object would calibrate a file no verdict reads.
#
# `tests/abi_stub.c` is not touched, and this file only reads it. The
# registered test `t0_abi_header` compiles that same source without this flag,
# so no probe reaches a test executable or any shipped artifact.
set(MCF5307_ABI_STUB_PROBE_SOURCE "${MCF5307_ABI_DIR}/stub_probe.h")
file(WRITE "${MCF5307_ABI_STUB_PROBE_SOURCE}" [==[
/* GENERATED by cmake/Nim.cmake step 4a part three. Do not edit this copy in
 * the build tree. It calibrates the symbol reader AND the verdict on the
 * relocatable object the verdict is read from.
 *
 * `mcf5307_abi_stub_probe_external` is defined with EXTERNAL linkage. It also
 *                                   measures this artifact's symbol prefix.
 * `mcf5307_abi_stub_probe_internal` is defined with INTERNAL linkage.
 * `mcf5307_abi_stub_probe_absent`   is defined nowhere and must be in
 *                                   neither set.
 *
 * `used` IS LOAD-BEARING. An unreferenced `static` function is dropped from
 * the object, and a dropped internal probe would read as `absent`: it would
 * calibrate the wrong category and leave the internal one uncalibrated, which
 * is the exact hole these probes exist to close. */
void mcf5307_abi_stub_probe_external(void) {}
__attribute__((used)) static void mcf5307_abi_stub_probe_internal(void) {}
]==])

# The two probe names are this file's own instrument in that object. The
# unpublished-export check below EXEMPTS them, and an exemption is a hole
# unless something closes it.
#
# What closes it is the compiler, not a control. The probe header above
# defines both names, so a stub that defines either one is
# `error: redefinition` and the compile below exits non-zero. No verdict runs
# on that translation unit at all, so there is no set for the exemption to hide
# a name in. Control I below compiles that collision and asserts it.
set(MCF5307_ABI_STUB_INSTRUMENT
    mcf5307_abi_stub_probe_external mcf5307_abi_stub_probe_internal)

# ---------------------------------------------------------------------------
# Two faults must never share a line. `tests/abi_stub.c` is compiled here with
# `-include` of a header this file generates, so the compile can fail for a
# fault that is not the stub's: a stub name that collides with a probe name.
# Reporting that as `tests/abi_stub.c did not compile` would name the wrong
# file, since the stub compiles clean under the registered test's own
# `-Wall -Wextra -pedantic -Werror`.
#
# The two are separated by the one thing that distinguishes them: whether the
# compiler's own diagnostics name the generated probe header. `string(FIND)` is
# literal, so a path with regex characters in it is still matched as a path.
function(mcf5307_abi_stub_collided mcf5307_col_out mcf5307_col_text)
    string(FIND "${mcf5307_col_text}" "${MCF5307_ABI_STUB_PROBE_SOURCE}"
        mcf5307_col_at)
    if(mcf5307_col_at EQUAL -1)
        set(${mcf5307_col_out} FALSE PARENT_SCOPE)
    else()
        set(${mcf5307_col_out} TRUE PARENT_SCOPE)
    endif()
endfunction()

# ---------------------------------------------------------------------------
# Control I. The compile-fault split, run on every configure run.
#
# It runs before the compile it calibrates, unlike controls E through H, which
# all run after that compile. The branch this one feeds fires the instant the
# real compile fails, so a calibration placed after it would be a calibration
# the failing run never reaches.
#
# It has two arms and needs both. An arm that only proves a collision is
# detected is passed by a predicate that answers TRUE always - and such a
# predicate would report every genuine stub fault as an instrument collision,
# which is the same two-faults defect pointing the other way.
function(mcf5307_abi_stub_compile_probe mcf5307_cp_out_result
        mcf5307_cp_out_collided mcf5307_cp_name mcf5307_cp_text)
    set(mcf5307_cp_src "${MCF5307_ABI_DIR}/${mcf5307_cp_name}.c")
    file(WRITE "${mcf5307_cp_src}" "${mcf5307_cp_text}")
    execute_process(
        COMMAND "${CMAKE_C_COMPILER}"
                -std=c11
                "-I${PROJECT_SOURCE_DIR}/include"
                "-include" "${MCF5307_ABI_STUB_PROBE_SOURCE}"
                -c
                -o "${MCF5307_ABI_DIR}/${mcf5307_cp_name}${CMAKE_C_OUTPUT_EXTENSION}"
                "${mcf5307_cp_src}"
        OUTPUT_VARIABLE mcf5307_cp_stdout
        ERROR_VARIABLE mcf5307_cp_stderr
        RESULT_VARIABLE mcf5307_cp_result)
    mcf5307_abi_stub_collided(mcf5307_cp_collided
        "${mcf5307_cp_stdout}${mcf5307_cp_stderr}")
    set(${mcf5307_cp_out_result} "${mcf5307_cp_result}" PARENT_SCOPE)
    set(${mcf5307_cp_out_collided} "${mcf5307_cp_collided}" PARENT_SCOPE)
endfunction()

# Arm one. A stub that reuses a probe name. This is the shape the exemption
# above would otherwise leave uncovered.
mcf5307_abi_stub_compile_probe(MCF5307_ABI_STUB_COLLIDE_RESULT
    MCF5307_ABI_STUB_COLLIDE_COLLIDED collide_probe
    "#include \"mcf5307.h\"\nvoid mcf5307_abi_stub_probe_external(void) {}\n")

if(MCF5307_ABI_STUB_COLLIDE_RESULT EQUAL 0
        OR NOT MCF5307_ABI_STUB_COLLIDE_COLLIDED)
    message(FATAL_ERROR
        "mcf5307: step 4a failed: control I: a translation unit that redefines "
        "`mcf5307_abi_stub_probe_external` was not reported as an instrument "
        "collision.\n"
        "  exit     : ${MCF5307_ABI_STUB_COLLIDE_RESULT}\n"
        "  collided : ${MCF5307_ABI_STUB_COLLIDE_COLLIDED}\n"
        "  probe    : ${MCF5307_ABI_STUB_PROBE_SOURCE}\n"
        "EXIT 0 means the probe header no longer defines that name, and the "
        "unpublished-export check below then EXEMPTS a name a stub can really "
        "define - the exemption's whole cover is that no such unit compiles. "
        "COLLIDED FALSE means the compile failed and this step would blame "
        "`${MCF5307_ABI_STUB_FILE}` for a fault belonging to a header this "
        "file generated.")
endif()

# Arm two. An ordinary fault in the stub, with no probe name anywhere in it.
mcf5307_abi_stub_compile_probe(MCF5307_ABI_STUB_OWNFAULT_RESULT
    MCF5307_ABI_STUB_OWNFAULT_COLLIDED ownfault_probe
    "#include \"mcf5307.h\"\nvoid mcf5307_abi_stub_own_fault(void) { ? }\n")

if(MCF5307_ABI_STUB_OWNFAULT_RESULT EQUAL 0
        OR MCF5307_ABI_STUB_OWNFAULT_COLLIDED)
    message(FATAL_ERROR
        "mcf5307: step 4a failed: control I: a translation unit whose only "
        "fault is its own was reported as an instrument collision.\n"
        "  exit     : ${MCF5307_ABI_STUB_OWNFAULT_RESULT}\n"
        "  collided : ${MCF5307_ABI_STUB_OWNFAULT_COLLIDED}\n"
        "  probe    : ${MCF5307_ABI_STUB_PROBE_SOURCE}\n"
        "EXIT 0 means a unit this file wrote to be rejected was accepted, so "
        "arm one's failure proves nothing about failing compiles. COLLIDED "
        "TRUE means the split answers `collision` for everything, and a real "
        "syntax error in ${MCF5307_ABI_STUB_FILE} would be reported as this "
        "step's own instrument getting in the way - the same two faults on one "
        "line, pointing the other way.")
endif()

message(STATUS
    "mcf5307: step 4a control I the compile-fault split told an instrument "
    "collision from a fault of the stub's own")

# The object of an earlier configure run is removed before the compile, for
# the reason every driver in `tests/tests_cpu.cmake` records: without it a
# compile that failed would leave the earlier object in place, and the reader
# below would then report a set this run never produced.
file(REMOVE "${MCF5307_ABI_STUB_OBJECT}")

execute_process(
    COMMAND "${CMAKE_C_COMPILER}"
            -std=c11
            "-I${PROJECT_SOURCE_DIR}/include"
            "-include" "${MCF5307_ABI_STUB_PROBE_SOURCE}"
            -c
            -o "${MCF5307_ABI_STUB_OBJECT}"
            "${MCF5307_ABI_STUB_FILE}"
    OUTPUT_VARIABLE MCF5307_ABI_STUB_COMPILE_OUTPUT
    ERROR_VARIABLE MCF5307_ABI_STUB_COMPILE_ERROR
    RESULT_VARIABLE MCF5307_ABI_STUB_COMPILE_RESULT)

if(NOT MCF5307_ABI_STUB_COMPILE_RESULT EQUAL 0)
    mcf5307_clip(MCF5307_ABI_STUB_COMPILE_OUTPUT_HEAD
        "${MCF5307_ABI_STUB_COMPILE_OUTPUT}" 2000)
    mcf5307_clip(MCF5307_ABI_STUB_COMPILE_ERROR_HEAD
        "${MCF5307_ABI_STUB_COMPILE_ERROR}" 2000)
    mcf5307_abi_stub_collided(MCF5307_ABI_STUB_COMPILE_COLLIDED
        "${MCF5307_ABI_STUB_COMPILE_OUTPUT}${MCF5307_ABI_STUB_COMPILE_ERROR}")
endif()

if(NOT MCF5307_ABI_STUB_COMPILE_RESULT EQUAL 0
        AND MCF5307_ABI_STUB_COMPILE_COLLIDED)
    message(FATAL_ERROR
        "mcf5307: step 4a failed: ${MCF5307_ABI_STUB_FILE} collides with a "
        "name THIS STEP injected into it.\n"
        "  compiler : ${CMAKE_C_COMPILER}\n"
        "  injected : ${MCF5307_ABI_STUB_PROBE_SOURCE}\n"
        "  names    : ${MCF5307_ABI_STUB_INSTRUMENT}\n"
        "  exit     : ${MCF5307_ABI_STUB_COMPILE_RESULT}\n"
        "  stdout   : ${MCF5307_ABI_STUB_COMPILE_OUTPUT_HEAD}\n"
        "  stderr   : ${MCF5307_ABI_STUB_COMPILE_ERROR_HEAD}\n"
        "THIS IS NOT A FAULT IN THAT FILE. The compile above carries "
        "`-include` of a header this file generates, and the diagnostics name "
        "it. That same file may compile clean under the registered test "
        "`t0_abi_header`, which uses `-Wall -Wextra -pedantic -Werror` and no "
        "`-include`. This step still cannot measure it, because the "
        "translation unit it would measure does not exist. Rename the stub's "
        "name, or rename the probe: the probe names are this step's own and "
        "the published set has no claim on either of them.")
endif()

if(NOT MCF5307_ABI_STUB_COMPILE_RESULT EQUAL 0)
    message(FATAL_ERROR
        "mcf5307: step 4a failed: ${MCF5307_ABI_STUB_FILE} did not compile.\n"
        "  compiler : ${CMAKE_C_COMPILER}\n"
        "  object   : ${MCF5307_ABI_STUB_OBJECT}\n"
        "  exit     : ${MCF5307_ABI_STUB_COMPILE_RESULT}\n"
        "  stdout   : ${MCF5307_ABI_STUB_COMPILE_OUTPUT_HEAD}\n"
        "  stderr   : ${MCF5307_ABI_STUB_COMPILE_ERROR_HEAD}\n"
        "A stub the C compiler refuses is a stub cases 3 and 4 of "
        "`t0_abi_header` cannot link against, and this step reports nothing "
        "about a file it could not compile.")
endif()

if(NOT EXISTS "${MCF5307_ABI_STUB_OBJECT}")
    message(FATAL_ERROR
        "mcf5307: step 4a failed: the compiler exited 0 and "
        "${MCF5307_ABI_STUB_OBJECT} does not exist. The object of an earlier "
        "run was removed before the compile, so there is nothing here to "
        "read, and a comparison over an empty set would report every "
        "published symbol as missing.")
endif()

mcf5307_abi_read_symbols(MCF5307_ABI_STUB_DEFINED_RAW
    MCF5307_ABI_STUB_EXTERNAL_RAW "${MCF5307_ABI_STUB_OBJECT}")

# ---------------------------------------------------------------------------
# Control E. The symbol reader, calibrated on the relocatable object it just
# read.
#
# Control D calibrates the reader on
# `libmcf5307_abi_measure${CMAKE_SHARED_LIBRARY_SUFFIX}`, with a probe unit
# compiled into that shared object. A relocatable object is a different
# artifact type, and a calibration is a statement about the artifact the
# verdict is read from, so this read gets probes of its own, compiled into
# this object.
#
# Non-emptiness is not enough: any file with one symbol in it passes that, so
# it cannot separate `read the right file` from `read a file`. The three
# probes are named, so a wrong file fails here and says so.
#
#   `mcf5307_abi_stub_probe_external` defined, external linkage.
#   `mcf5307_abi_stub_probe_internal` defined, internal linkage.
#   `mcf5307_abi_stub_probe_absent`   defined nowhere.
#
# The symbol prefix is measured here too, and not inherited. `MCF5307_ABI_
# PREFIX` above is read off the shared object. Applying it to this object
# without measuring it here would be an assumption about an artifact type
# nothing had measured. It is read off a name this file wrote into this
# object, and the two answers must agree.

set(MCF5307_ABI_STUB_PREFIX "")
set(MCF5307_ABI_STUB_PREFIX_FOUND FALSE)
foreach(name IN LISTS MCF5307_ABI_STUB_EXTERNAL_RAW)
    if(name MATCHES "^(_*)mcf5307_abi_stub_probe_external$")
        set(MCF5307_ABI_STUB_PREFIX "${CMAKE_MATCH_1}")
        set(MCF5307_ABI_STUB_PREFIX_FOUND TRUE)
    endif()
endforeach()

if(NOT MCF5307_ABI_STUB_PREFIX_FOUND)
    message(FATAL_ERROR
        "mcf5307: step 4a failed: control E: the probe symbol "
        "`mcf5307_abi_stub_probe_external` is not among the external "
        "definitions of ${MCF5307_ABI_STUB_OBJECT}.\n"
        "  external : ${MCF5307_ABI_STUB_EXTERNAL_RAW}\n"
        "  reader   : ${MCF5307_ABI_NM}\n"
        "This file compiled that probe into that object, with external "
        "linkage, on the compile line above. A reader that cannot find it "
        "read the wrong file, read nothing, or cannot see an external "
        "definition in a relocatable object at all. Every verdict below is "
        "then read from an artifact nothing measured.")
endif()

if(NOT "${MCF5307_ABI_STUB_PREFIX}" STREQUAL "${MCF5307_ABI_PREFIX}")
    message(FATAL_ERROR
        "mcf5307: step 4a failed: control E: the symbol prefix of "
        "${MCF5307_ABI_STUB_OBJECT} is not the prefix of "
        "${MCF5307_ABI_OBJECT}.\n"
        "  relocatable object : `${MCF5307_ABI_STUB_PREFIX}`\n"
        "  shared object      : `${MCF5307_ABI_PREFIX}`\n"
        "Both were measured off a probe name this file wrote, one per "
        "artifact. The verdict below strips the SHARED object's prefix off "
        "the RELOCATABLE object's names, and that is only sound while the two "
        "agree. With the wrong prefix every published name fails to match and "
        "the whole published set is reported missing from a stub that defines "
        "it.")
endif()

mcf5307_abi_strip(MCF5307_ABI_STUB_DEFINED ${MCF5307_ABI_STUB_DEFINED_RAW})
mcf5307_abi_strip(MCF5307_ABI_STUB_EXTERNAL ${MCF5307_ABI_STUB_EXTERNAL_RAW})

if(NOT "mcf5307_abi_stub_probe_internal" IN_LIST MCF5307_ABI_STUB_DEFINED)
    message(FATAL_ERROR
        "mcf5307: step 4a failed: control E: the probe symbol "
        "`mcf5307_abi_stub_probe_internal` is not among the DEFINED symbols "
        "of ${MCF5307_ABI_STUB_OBJECT}.\n"
        "  defined : ${MCF5307_ABI_STUB_DEFINED}\n"
        "This file compiled a `static` definition of it into that object and "
        "marked it `used` so it stays. A reader that cannot see an internal "
        "definition in a relocatable object cannot separate `defined with "
        "internal linkage` from `not defined at all`, and the verdict below "
        "would report every `static` published name as an unwritten one. That "
        "is the report this step must never give.")
endif()

if("mcf5307_abi_stub_probe_internal" IN_LIST MCF5307_ABI_STUB_EXTERNAL)
    message(FATAL_ERROR
        "mcf5307: step 4a failed: control E: the probe symbol "
        "`mcf5307_abi_stub_probe_internal` is among the EXTERNAL definitions "
        "of ${MCF5307_ABI_STUB_OBJECT}.\n"
        "  external : ${MCF5307_ABI_STUB_EXTERNAL}\n"
        "It is `static`. A reader that calls an internal definition external "
        "calls every `static` published name linkable, and the link of "
        "`t0_abi_header` would then fail on a name this step passed.")
endif()

if("mcf5307_abi_stub_probe_absent" IN_LIST MCF5307_ABI_STUB_DEFINED
        OR "mcf5307_abi_stub_probe_absent" IN_LIST MCF5307_ABI_STUB_EXTERNAL)
    message(FATAL_ERROR
        "mcf5307: step 4a failed: control E: the name "
        "`mcf5307_abi_stub_probe_absent` was read out of "
        "${MCF5307_ABI_STUB_OBJECT}.\n"
        "Nothing defines it anywhere in this project. A reader that reports "
        "it reports names the object does not hold, and its `linkable` "
        "verdicts below are then worth nothing.")
endif()

message(STATUS
    "mcf5307: step 4a control E the symbol reader separated external, "
    "internal and absent on ${MCF5307_ABI_STUB_OBJECT} (symbol prefix: "
    "`${MCF5307_ABI_STUB_PREFIX}`, the shared object's)")

# The verdict. Three categories over the published set, and each published
# name lands in exactly one.
#
#   linkable  published and defined with external linkage.  Pass.
#   internal  published and defined with internal linkage.  Fails.
#   absent    published and not defined at all.             Fails.
#
# It is a function so that a probe can run through it. Two of the three
# categories are ones this project's own source is not expected to produce, so
# on an ordinary run the two fatal branches below are never entered, and a
# branch nothing enters is a branch nothing proves works. Control F below
# sorts three probe names through this function and holds the answer against a
# written-out expectation.
#
# It reads the measured sets out of the calling scope on purpose. The control
# and the verdict then sort names out of ONE reading of ONE object. A control
# that carried sets of its own would prove something about its own sets and
# nothing about the object the verdict is read from.
function(mcf5307_abi_stub_classify mcf5307_cls_out_linkable
        mcf5307_cls_out_internal mcf5307_cls_out_absent)
    set(mcf5307_cls_linkable "")
    set(mcf5307_cls_internal "")
    set(mcf5307_cls_absent "")
    foreach(mcf5307_cls_name IN LISTS ARGN)
        if(mcf5307_cls_name IN_LIST MCF5307_ABI_STUB_EXTERNAL)
            list(APPEND mcf5307_cls_linkable "${mcf5307_cls_name}")
        elseif(mcf5307_cls_name IN_LIST MCF5307_ABI_STUB_DEFINED)
            list(APPEND mcf5307_cls_internal "${mcf5307_cls_name}")
        else()
            list(APPEND mcf5307_cls_absent "${mcf5307_cls_name}")
        endif()
    endforeach()
    set(${mcf5307_cls_out_linkable} "${mcf5307_cls_linkable}" PARENT_SCOPE)
    set(${mcf5307_cls_out_internal} "${mcf5307_cls_internal}" PARENT_SCOPE)
    set(${mcf5307_cls_out_absent} "${mcf5307_cls_absent}" PARENT_SCOPE)
endfunction()

# The other direction, also a function and for the same reason. It answers
# every external definition of the object that the allowed set does not carry.
function(mcf5307_abi_stub_unallowed mcf5307_una_out)
    set(mcf5307_una_allowed ${ARGN})
    set(mcf5307_una_result "")
    foreach(mcf5307_una_name IN LISTS MCF5307_ABI_STUB_EXTERNAL)
        if(NOT mcf5307_una_name IN_LIST mcf5307_una_allowed)
            list(APPEND mcf5307_una_result "${mcf5307_una_name}")
        endif()
    endforeach()
    set(${mcf5307_una_out} "${mcf5307_una_result}" PARENT_SCOPE)
endfunction()

# ---------------------------------------------------------------------------
# Control F. Every category of the verdict, entered on every configure run.
#
# Two of the three categories are ones this project's own source is not
# expected to produce, so without this control the two fatal branches below are
# never entered on an ordinary run. The probes go through the same function and
# the same measured sets as the published set, and the expected answer is
# written out here, so a classifier that lost an arm cannot produce it.
#
# This control covers the classifier and not the C. It proves the internal arm
# sorts a name the reader reported as internal-defined. It says nothing about
# what C source makes a compiler produce such a name. Control H below compiles
# one and measures it.
mcf5307_abi_stub_classify(MCF5307_ABI_STUB_PROBE_LINKABLE
    MCF5307_ABI_STUB_PROBE_INTERNAL MCF5307_ABI_STUB_PROBE_ABSENT
    mcf5307_abi_stub_probe_external
    mcf5307_abi_stub_probe_internal
    mcf5307_abi_stub_probe_absent)

if(NOT "${MCF5307_ABI_STUB_PROBE_LINKABLE}" STREQUAL
            "mcf5307_abi_stub_probe_external"
        OR NOT "${MCF5307_ABI_STUB_PROBE_INTERNAL}" STREQUAL
            "mcf5307_abi_stub_probe_internal"
        OR NOT "${MCF5307_ABI_STUB_PROBE_ABSENT}" STREQUAL
            "mcf5307_abi_stub_probe_absent")
    message(FATAL_ERROR
        "mcf5307: step 4a failed: control F: the verdict did not sort the "
        "three probes of ${MCF5307_ABI_STUB_OBJECT} into the three "
        "categories it reports.\n"
        "  expected linkable : mcf5307_abi_stub_probe_external\n"
        "  read     linkable : ${MCF5307_ABI_STUB_PROBE_LINKABLE}\n"
        "  expected internal : mcf5307_abi_stub_probe_internal\n"
        "  read     internal : ${MCF5307_ABI_STUB_PROBE_INTERNAL}\n"
        "  expected absent   : mcf5307_abi_stub_probe_absent\n"
        "  read     absent   : ${MCF5307_ABI_STUB_PROBE_ABSENT}\n"
        "One probe per category, compiled into that object by this file, "
        "sorted by the same function that sorts the published set below. A "
        "category that cannot take its own probe cannot take a published "
        "name either, and the fatal branch that reports it is then a branch "
        "no run can enter. That is the defect this control exists to "
        "prevent.")
endif()

message(STATUS
    "mcf5307: step 4a control F the stub verdict placed one probe in each of "
    "its three categories (linkable, internal, absent) on "
    "${MCF5307_ABI_STUB_OBJECT}")

# ---------------------------------------------------------------------------
# Control G. The other direction, entered on every configure run.
#
# `mcf5307_abi_stub_probe_external` is an external definition of that object,
# planted by this file, and the shape the check below is for is exactly `an
# external definition the allowed set does not carry`. Given an allowed set
# that carries every external name of the object EXCEPT that probe, the answer
# must be that probe and nothing else.
#
# The allowed set is not the published set, and that is deliberate. Written
# against the published set alone, this control's answer grows whenever the
# stub grows a real unpublished export - so a real fault trips the control
# instead of the check, and the operator gets a calibration message where the
# production one names the two files and says which to change. A control must
# never take a production fault's message away from it. Holding the probe
# against everything else the object exports keeps the answer exact whatever
# the stub does, and leaves the real fault to the check below.
set(MCF5307_ABI_STUB_PROBE_ALLOWED "")
foreach(name IN LISTS MCF5307_ABI_STUB_EXTERNAL)
    if(NOT name STREQUAL "mcf5307_abi_stub_probe_external")
        list(APPEND MCF5307_ABI_STUB_PROBE_ALLOWED "${name}")
    endif()
endforeach()

mcf5307_abi_stub_unallowed(MCF5307_ABI_STUB_PROBE_EXTRA
    ${MCF5307_ABI_STUB_PROBE_ALLOWED})

if(NOT "${MCF5307_ABI_STUB_PROBE_EXTRA}" STREQUAL
        "mcf5307_abi_stub_probe_external")
    message(FATAL_ERROR
        "mcf5307: step 4a failed: control G: the unpublished-export check did "
        "not answer with the one probe planted for it in "
        "${MCF5307_ABI_STUB_OBJECT}.\n"
        "  expected : mcf5307_abi_stub_probe_external\n"
        "  read     : ${MCF5307_ABI_STUB_PROBE_EXTRA}\n"
        "  allowed  : ${MCF5307_ABI_STUB_PROBE_ALLOWED}\n"
        "  external : ${MCF5307_ABI_STUB_EXTERNAL}\n"
        "Every external name of that object but that one probe was allowed, "
        "so the one name left over is the whole answer. A check that answers "
        "nothing here answers nothing for a real unpublished export either, "
        "and its fatal branch is then a branch no run can enter. A check that "
        "answers more reports names the allowed set carries, and it would "
        "report the whole published set as unpublished.")
endif()

message(STATUS
    "mcf5307: step 4a control G the unpublished-export check answered with "
    "its probe on ${MCF5307_ABI_STUB_OBJECT}")

# ---------------------------------------------------------------------------
# Control H. The internal branch's two routes, compiled on every configure run.
#
# A sentence about what a compiler does is a measurement and not a fact, so
# each route is compiled here rather than described. A route needs two things:
# internal linkage, and a definition that survives to `nm`, because `nm` is
# what the internal branch reads. Each arm below therefore carries something
# that holds its definition alive - a reference for arm one, `used` for arm
# two - and each asserts the category its own object lands in.
#
# Internal linkage plus something that keeps the definition alive gives
# `t <name>` in the `all` pass, absent from the `-g` pass, and that is what the
# internal branch below reads. Each source is generated here, each object is
# read with the same reader, and the name is sorted by the same function that
# sorts the published set, so a route that stops working fails here rather than
# rotting in a comment.
#
#   Arm one is `static` ahead of the contract, with an anchor that references it.
#   Arm two is the `__asm__` label, on a helper marked `used`.
#
# The two non-routes are compiled here too, for the same reason. `hidden`
# visibility on a published name and `static` after the contract include both
# fail to reach this category, and a sentence saying a mutation does not reach
# a branch rots exactly like a sentence saying it does. Arms three and four
# below run them.
#
# No arm compiles an unanchored shape, so this file says nothing about what one
# produces.
#
# The scope of this measurement is one toolchain. Every answer above was read
# from Apple clang 21.0.0 targeting arm64 Mach-O. A different compiler may emit
# an unreferenced internal definition and reach the branch by the shorter road.
# That would not falsify anything here: these arms compile their shapes and
# assert the outcome, so a toolchain that gets there another way still passes
# arms one and two - and arms three and four would report the change rather than
# hide it.
#
# Arm two's label carries the measured symbol prefix. An `__asm__` label names
# an assembler symbol, so it has to be written the way the assembler writes it -
# `_mcf5307_runtime_init` on this host, `mcf5307_runtime_init` on a target with
# no prefix. `MCF5307_ABI_PREFIX` is the prefix `mcf5307_abi_strip` removes, so
# using it here is what makes the stripped name the reader answers with the
# route name the classifier is asked about. A literal underscore would be an
# assumption about a target, and this file measures that one already.
set(MCF5307_ABI_STUB_ROUTE_NAME "mcf5307_runtime_init")

if(NOT "${MCF5307_ABI_STUB_ROUTE_NAME}" IN_LIST MCF5307_ABI_PUBLISHED)
    message(FATAL_ERROR
        "mcf5307: step 4a failed: control H: `${MCF5307_ABI_STUB_ROUTE_NAME}` "
        "is not in the published set of ${MCF5307_ABI_CONTRACT_FILE}.\n"
        "  published : ${MCF5307_ABI_PUBLISHED}\n"
        "This control drives the INTERNAL branch with a REAL published name, "
        "because that branch only ever reports one. Control C above states "
        "that this project publishes at least this name. Point this control at "
        "a name the contract still declares.")
endif()

# The same classifier, over another object's sets. `mcf5307_abi_stub_classify`
# reads the two measured sets out of its calling scope, which is what lets the
# verdict and control F share one reading of one object. This wrapper names its
# two parameters after those two variables, so inside it they are function-local
# and the nested call sorts the route object instead. It is the production
# classifier that answers here - not a copy of it, and not a restatement of its
# condition in this comment.
function(mcf5307_abi_stub_classify_over
        MCF5307_ABI_STUB_EXTERNAL MCF5307_ABI_STUB_DEFINED
        mcf5307_over_out_linkable mcf5307_over_out_internal
        mcf5307_over_out_absent)
    mcf5307_abi_stub_classify(mcf5307_over_linkable mcf5307_over_internal
        mcf5307_over_absent ${ARGN})
    set(${mcf5307_over_out_linkable} "${mcf5307_over_linkable}" PARENT_SCOPE)
    set(${mcf5307_over_out_internal} "${mcf5307_over_internal}" PARENT_SCOPE)
    set(${mcf5307_over_out_absent} "${mcf5307_over_absent}" PARENT_SCOPE)
endfunction()

# One arm. It writes a unit, compiles it, reads the object with the same reader,
# and answers with the category the verdict would put the route name in.
#
# The compile line is the stub's minus one flag. It carries `-std=c11`, the
# project's include directory and `-c`, exactly as the stub compile above does.
# It does not carry `-include` of the generated probe header, and the stub
# compile does. Adding it here would put the two probe names in the object and
# change no answer here, because the classifier below is asked about one name
# and the probe names are not it.
#
# `REJECTED` and `NO OBJECT` are two answers. Reporting `the compiler refused
# the unit` and `the compiler exited 0 and wrote nothing` as one answer is the
# two-faults-on-one-line defect: arm four asks for `REJECTED` and would get it
# from a compiler that accepted the unit and emitted nothing, and the detail
# line is clipped stderr, which a silent success has none of. The two answers
# are separate below, and `NO OBJECT` carries a detail of its own.
#
# The units are never linked into anything. They are compiled, read and left in
# the instrument directory, and no target of this project names them.
function(mcf5307_abi_stub_route_probe mcf5307_rp_out_category
        mcf5307_rp_out_detail mcf5307_rp_name mcf5307_rp_text)
    set(mcf5307_rp_src "${MCF5307_ABI_DIR}/${mcf5307_rp_name}.c")
    set(mcf5307_rp_obj
        "${MCF5307_ABI_DIR}/${mcf5307_rp_name}${CMAKE_C_OUTPUT_EXTENSION}")
    file(WRITE "${mcf5307_rp_src}"
"/* GENERATED by cmake/Nim.cmake step 4a control H. Do not edit this copy in
 * the build tree. It is compiled and read, and it is linked into nothing. */
${mcf5307_rp_text}")
    file(REMOVE "${mcf5307_rp_obj}")
    execute_process(
        COMMAND "${CMAKE_C_COMPILER}"
                -std=c11
                "-I${PROJECT_SOURCE_DIR}/include"
                -c
                -o "${mcf5307_rp_obj}"
                "${mcf5307_rp_src}"
        OUTPUT_VARIABLE mcf5307_rp_stdout
        ERROR_VARIABLE mcf5307_rp_stderr
        RESULT_VARIABLE mcf5307_rp_result)
    if(NOT mcf5307_rp_result EQUAL 0)
        mcf5307_clip(mcf5307_rp_head "${mcf5307_rp_stderr}" 600)
        set(${mcf5307_rp_out_category} "REJECTED" PARENT_SCOPE)
        set(${mcf5307_rp_out_detail}
            "exit ${mcf5307_rp_result}: ${mcf5307_rp_head}" PARENT_SCOPE)
        return()
    endif()
    if(NOT EXISTS "${mcf5307_rp_obj}")
        string(CONCAT mcf5307_rp_none
            "exit 0 and no ${mcf5307_rp_obj}. The object of an earlier run is "
            "removed before the compile, so there is nothing here to read.")
        set(${mcf5307_rp_out_category} "NO-OBJECT" PARENT_SCOPE)
        set(${mcf5307_rp_out_detail} "${mcf5307_rp_none}" PARENT_SCOPE)
        return()
    endif()
    mcf5307_abi_read_symbols(mcf5307_rp_defined_raw mcf5307_rp_external_raw
        "${mcf5307_rp_obj}")
    mcf5307_abi_strip(mcf5307_rp_defined ${mcf5307_rp_defined_raw})
    mcf5307_abi_strip(mcf5307_rp_external ${mcf5307_rp_external_raw})
    mcf5307_abi_stub_classify_over(
        "${mcf5307_rp_external}" "${mcf5307_rp_defined}"
        mcf5307_rp_linkable mcf5307_rp_internal mcf5307_rp_absent
        "${MCF5307_ABI_STUB_ROUTE_NAME}")
    if(NOT mcf5307_rp_internal STREQUAL "")
        set(${mcf5307_rp_out_category} "INTERNAL" PARENT_SCOPE)
    elseif(NOT mcf5307_rp_linkable STREQUAL "")
        set(${mcf5307_rp_out_category} "LINKABLE" PARENT_SCOPE)
    else()
        set(${mcf5307_rp_out_category} "ABSENT" PARENT_SCOPE)
    endif()
    set(${mcf5307_rp_out_detail}
        "defined: ${mcf5307_rp_defined} | external: ${mcf5307_rp_external}"
        PARENT_SCOPE)
endfunction()

# Arm one. The first route. Internal linkage from a `static` declaration ahead
# of the contract, and an anchor that keeps the definition from being dropped.
# The anchor is `used` for the
# reason the probe header gives: without it the anchor goes, the reference goes
# with it, and the definition goes with that.
mcf5307_abi_stub_route_probe(MCF5307_ABI_STUB_ROUTE_CATEGORY
    MCF5307_ABI_STUB_ROUTE_DETAIL internal_route
"static void ${MCF5307_ABI_STUB_ROUTE_NAME}(void);

#include \"mcf5307.h\"

static void ${MCF5307_ABI_STUB_ROUTE_NAME}(void) {}

__attribute__((used)) static void mcf5307_abi_stub_route_anchor(void)
{
    ${MCF5307_ABI_STUB_ROUTE_NAME}();
}
")

if(NOT MCF5307_ABI_STUB_ROUTE_CATEGORY STREQUAL "INTERNAL")
    message(FATAL_ERROR
        "mcf5307: step 4a failed: control H arm one: the internal-linkage "
        "route did not reach the INTERNAL category.\n"
        "  name     : ${MCF5307_ABI_STUB_ROUTE_NAME}\n"
        "  source   : ${MCF5307_ABI_DIR}/internal_route.c\n"
        "  expected : INTERNAL\n"
        "  read     : ${MCF5307_ABI_STUB_ROUTE_CATEGORY}\n"
        "  detail   : ${MCF5307_ABI_STUB_ROUTE_DETAIL}\n"
        "  reader   : ${MCF5307_ABI_NM}\n"
        "READ AS `ABSENT`, the route no longer produces a SURVIVING internal "
        "definition, and the INTERNAL branch below loses one of its two "
        "demonstrated ways in. The anchor above is what keeps the definition "
        "alive; check it first. READ AS `LINKABLE`, the `static` ahead of the "
        "contract stopped conferring internal linkage, and the branch can no "
        "longer separate a `static` published definition from a linkable one. "
        "READ AS `REJECTED`, the compiler refused the unit - a changed "
        "signature in the contract reads this way too. READ AS `NO-OBJECT`, "
        "the compiler accepted the unit and emitted nothing, which is a "
        "different fault from a refusal and is why the two are separate "
        "answers.")
endif()

# Arm two. The second route. An
# `__asm__` label renames the assembler symbol of a `static` helper, so the
# helper keeps internal linkage while carrying the published name. `used` is the
# anchor here, and it is load-bearing for the same reason it is in the probe
# header: an unreferenced `static` function is not emitted at all.
#
# The label is built from the measured prefix and not from a literal underscore,
# for the reason the comment above this control gives.
mcf5307_abi_stub_route_probe(MCF5307_ABI_STUB_ASMLABEL_CATEGORY
    MCF5307_ABI_STUB_ASMLABEL_DETAIL asm_label_route
"#include \"mcf5307.h\"

__attribute__((used)) static void mcf5307_abi_stub_route_alias(void)
    __asm__(\"${MCF5307_ABI_PREFIX}${MCF5307_ABI_STUB_ROUTE_NAME}\");

static void mcf5307_abi_stub_route_alias(void) {}
")

if(NOT MCF5307_ABI_STUB_ASMLABEL_CATEGORY STREQUAL "INTERNAL")
    message(FATAL_ERROR
        "mcf5307: step 4a failed: control H arm two: the `__asm__` label route "
        "did not reach the INTERNAL category.\n"
        "  name     : ${MCF5307_ABI_STUB_ROUTE_NAME}\n"
        "  label    : ${MCF5307_ABI_PREFIX}${MCF5307_ABI_STUB_ROUTE_NAME}\n"
        "  source   : ${MCF5307_ABI_DIR}/asm_label_route.c\n"
        "  expected : INTERNAL\n"
        "  read     : ${MCF5307_ABI_STUB_ASMLABEL_CATEGORY}\n"
        "  detail   : ${MCF5307_ABI_STUB_ASMLABEL_DETAIL}\n"
        "  reader   : ${MCF5307_ABI_NM}\n"
        "THIS ARM EXISTS BECAUSE THE COMMENT ABOVE NAMES THIS SHAPE. It was "
        "named and asserted there from `677a88b` onward with no compile behind "
        "it, while the sentence beside it declared every named route compiled. "
        "READ AS `ABSENT`, either `used` stopped keeping the definition alive "
        "or the label no longer renames the symbol, and the name the reader "
        "answers with is not the one the classifier is asked about - check "
        "`${MCF5307_ABI_PREFIX}` against what `${MCF5307_ABI_NM}` prints for "
        "this object. READ AS `LINKABLE`, the label promoted the helper out of "
        "internal linkage, and the INTERNAL branch can no longer be reached "
        "this way. READ AS `REJECTED`, the toolchain does not accept an "
        "`__asm__` label in this position under `-std=c11`. READ AS "
        "`NO-OBJECT`, it accepted the unit and emitted nothing.")
endif()

# Arm three. Not a route, and measured not to be one. `hidden` visibility keeps
# external linkage, so the name stays in the `-g` pass and this category never
# sees it. The shared-object verdict above is where `hidden` is a fault; here
# it must read LINKABLE, and a run where it reads INTERNAL means the two
# verdicts have swapped meanings.
mcf5307_abi_stub_route_probe(MCF5307_ABI_STUB_HIDDEN_CATEGORY
    MCF5307_ABI_STUB_HIDDEN_DETAIL hidden_route
"#include \"mcf5307.h\"

__attribute__((visibility(\"hidden\"))) void ${MCF5307_ABI_STUB_ROUTE_NAME}(void)
{
}
")

if(NOT MCF5307_ABI_STUB_HIDDEN_CATEGORY STREQUAL "LINKABLE")
    message(FATAL_ERROR
        "mcf5307: step 4a failed: control H arm three: `hidden` visibility on a "
        "published name did not stay LINKABLE.\n"
        "  name     : ${MCF5307_ABI_STUB_ROUTE_NAME}\n"
        "  source   : ${MCF5307_ABI_DIR}/hidden_route.c\n"
        "  expected : LINKABLE\n"
        "  read     : ${MCF5307_ABI_STUB_HIDDEN_CATEGORY}\n"
        "  detail   : ${MCF5307_ABI_STUB_HIDDEN_DETAIL}\n"
        "Visibility and linkage are different properties, and this step's two "
        "verdicts each own one of them. A `hidden` name that reads INTERNAL "
        "here would be reported as a `static` published definition by the "
        "branch below, which is a different fault with a different fix, and "
        "the message would send the reader to remove a `static` that is not "
        "there. READ AS `REJECTED` or `NO-OBJECT`, there is no object to "
        "classify and the question this arm asks was never reached.")
endif()

# Arm four. Not a route either. `static` after the contract include is a
# constraint violation, so no object exists to classify and the compile branch
# far above owns the report.
#
# It asks for `REJECTED` and not for `NO-OBJECT`. The claim this arm carries is
# that the compiler refuses this shape. A toolchain that accepted it and wrote
# no object would
# have satisfied the old combined answer and left the claim false.
mcf5307_abi_stub_route_probe(MCF5307_ABI_STUB_LATESTATIC_CATEGORY
    MCF5307_ABI_STUB_LATESTATIC_DETAIL late_static_route
"#include \"mcf5307.h\"

static void ${MCF5307_ABI_STUB_ROUTE_NAME}(void)
{
}
")

if(NOT MCF5307_ABI_STUB_LATESTATIC_CATEGORY STREQUAL "REJECTED")
    message(FATAL_ERROR
        "mcf5307: step 4a failed: control H arm four: `static` AFTER the "
        "contract include was not rejected by the compiler.\n"
        "  name     : ${MCF5307_ABI_STUB_ROUTE_NAME}\n"
        "  source   : ${MCF5307_ABI_DIR}/late_static_route.c\n"
        "  expected : REJECTED\n"
        "  read     : ${MCF5307_ABI_STUB_LATESTATIC_CATEGORY}\n"
        "  detail   : ${MCF5307_ABI_STUB_LATESTATIC_DETAIL}\n"
        "This file records that shape as a constraint violation - `static "
        "declaration follows non-static declaration` - and therefore as "
        "something the COMPILE branch reports rather than the verdict. A "
        "toolchain that accepts it makes that record false, and the category "
        "it lands in is the one named above. READ AS `NO-OBJECT`, it accepted "
        "the unit and emitted nothing, which is not a refusal either.")
endif()

# What this control compiles is four shapes: two are routes to the internal
# category and two are shapes measured not to reach it.
message(STATUS
    "mcf5307: step 4a control H compiled four shapes and asserted each "
    "category: `${MCF5307_ABI_STUB_ROUTE_NAME}` reaches INTERNAL by two "
    "routes (`static`-with-anchor, `__asm__`-label-with-`used`), and does not "
    "reach it by two others (hidden is LINKABLE, late-`static` is REJECTED)")

# ---------------------------------------------------------------------------
# The verdict itself, over the published set.
mcf5307_abi_stub_classify(MCF5307_ABI_STUB_LINKABLE MCF5307_ABI_STUB_INTERNAL
    MCF5307_ABI_STUB_ABSENT ${MCF5307_ABI_PUBLISHED})

# The stub's own external definitions. The two probe names above are this
# file's instrument and they are in no shipped artifact and in no test
# executable, so a message that says `defined by the stub` must not print
# them.
set(MCF5307_ABI_STUB_EXTERNAL_OWN "")
foreach(name IN LISTS MCF5307_ABI_STUB_EXTERNAL)
    if(NOT name IN_LIST MCF5307_ABI_STUB_INSTRUMENT)
        list(APPEND MCF5307_ABI_STUB_EXTERNAL_OWN "${name}")
    endif()
endforeach()

if(NOT MCF5307_ABI_STUB_ABSENT STREQUAL "")
    message(FATAL_ERROR
        "mcf5307: step 4a failed: ${MCF5307_ABI_CONTRACT_FILE} publishes a "
        "symbol that ${MCF5307_ABI_STUB_FILE} does not define.\n"
        "  missing from the stub : ${MCF5307_ABI_STUB_ABSENT}\n"
        "  published             : ${MCF5307_ABI_PUBLISHED}\n"
        "  defined by the stub   : ${MCF5307_ABI_STUB_EXTERNAL_OWN}\n"
        "  measured object       : ${MCF5307_ABI_STUB_OBJECT}\n"
        "  symbol lister         : ${MCF5307_ABI_NM}\n"
        "That file states its invariant as one definition, with an empty "
        "body, of EVERY function the contract declares, and it is the link "
        "partner of cases 3 and 4 of `t0_abi_header`. For a name it does not "
        "define it cannot turn a rename into a link error - the reference "
        "would be undefined either way. Add one empty definition for each "
        "name above, with the exact declared signature and a fixed benign "
        "return. Do not add behaviour: a test that needs behaviour links the "
        "real library.")
endif()

if(NOT MCF5307_ABI_STUB_INTERNAL STREQUAL "")
    message(FATAL_ERROR
        "mcf5307: step 4a failed: ${MCF5307_ABI_STUB_FILE} defines a "
        "published symbol with INTERNAL linkage.\n"
        "  internal        : ${MCF5307_ABI_STUB_INTERNAL}\n"
        "  measured object : ${MCF5307_ABI_STUB_OBJECT}\n"
        "A `static` definition is invisible to the link of `t0_abi_header`, "
        "so the reference there stays undefined and the definition here "
        "resolves nothing. This is a separate line from the missing-symbol "
        "message above because it is a separate fault: the definition exists "
        "and the linkage is wrong. Remove the `static`.")
endif()

# The other direction. An external name the contract does not declare.
#
# The probe names are exempted, and control G is not what covers that. The
# allowed set there is every other external name of the object, precisely so
# that a real unpublished export reaches this message instead of tripping the
# control. What covers the exemption is control I, above the compile: a
# stub that defines either probe name is `error: redefinition` and produces no
# object, so no run reaches this line with such a name in the set.
mcf5307_abi_stub_unallowed(MCF5307_ABI_STUB_EXTRA
    ${MCF5307_ABI_PUBLISHED} ${MCF5307_ABI_STUB_INSTRUMENT})

if(NOT MCF5307_ABI_STUB_EXTRA STREQUAL "")
    message(FATAL_ERROR
        "mcf5307: step 4a failed: ${MCF5307_ABI_STUB_FILE} defines an "
        "EXTERNAL symbol that ${MCF5307_ABI_CONTRACT_FILE} does not "
        "declare.\n"
        "  defined by the stub and not published : "
        "${MCF5307_ABI_STUB_EXTRA}\n"
        "  published                             : ${MCF5307_ABI_PUBLISHED}\n"
        "  defined by the stub                   : "
        "${MCF5307_ABI_STUB_EXTERNAL_OWN}\n"
        "Either the contract lost the declaration, or the stub grew a name "
        "outside its one job. That file's whole job is the published set, so "
        "an external name outside that set is one of those two faults, and "
        "this check does not guess which. A helper the file needs for itself "
        "is `static`, and this check says nothing about a `static` one.")
endif()

# The success line states the measurement and stops. It does not claim that
# cases 3 and 4 of `t0_abi_header` link, because this step never ran that link
# and two things it did not run can each falsify such a claim while this step
# exits 0.
#
#   The flags differ. The compile above carries `-std=c11` and no warning
#   flags. `tests/tests_cpu.cmake` sets `-Wall -Wextra -pedantic -Werror` and
#   compiles the same file with them in both cases, so a stub carrying an
#   unused local passes here and fails there.
#
#   The references are fewer than the definitions. `t0_abi_header.c` and
#   `t0_abi_header.cpp` take their addresses from a fixed list of their own
#   that names neither `mcf5307_set_reg`, `mcf5307_get_reg`, `mcf5307_halted`
#   nor `mcf5307_faulted`, so a definition here for those is a definition
#   nothing over there references.
#
# The flags are not matched here, and that is deliberate. Adding `-Werror` to
# this compile would make a warning in the stub fail the symbol gate, so one
# line would carry two faults. The warning dimension already has an owner that
# fails on it: the registered test `t0_abi_header`.
#
# The line names a set and a file, and the two must agree. The set printed here
# is the stub's own external definitions, and the instrument that is in the
# object but not in the set is named, so the two numbers a reader can get from
# the object are both accounted for.
#
# The instrument names the external read actually answers with. It is computed
# and not written down: the sentence below has to reconcile the number it
# prints with the number a reader gets from the object, and only a measured
# difference does that. The internal probe is in the `all` pass and not in this
# one, so naming both here would overstate by one in the other direction.
set(MCF5307_ABI_STUB_EXTERNAL_INSTRUMENT "")
foreach(name IN LISTS MCF5307_ABI_STUB_EXTERNAL)
    if(name IN_LIST MCF5307_ABI_STUB_INSTRUMENT)
        list(APPEND MCF5307_ABI_STUB_EXTERNAL_INSTRUMENT "${name}")
    endif()
endforeach()

list(LENGTH MCF5307_ABI_STUB_EXTERNAL_OWN MCF5307_ABI_STUB_EXTERNAL_OWN_COUNT)
list(LENGTH MCF5307_ABI_STUB_EXTERNAL MCF5307_ABI_STUB_EXTERNAL_COUNT)
message(STATUS
    "mcf5307: step 4a ${MCF5307_ABI_STUB_FILE} defines externally exactly the "
    "${MCF5307_ABI_STUB_EXTERNAL_OWN_COUNT} published symbol(s). "
    "${MCF5307_ABI_NM} answers ${MCF5307_ABI_STUB_EXTERNAL_COUNT} on "
    "${MCF5307_ABI_STUB_OBJECT}: those, and this step's own "
    "${MCF5307_ABI_STUB_EXTERNAL_INSTRUMENT}")

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
# text that no run can check. They belong in the same change as an
# `install(TARGETS ...)` rule, where they take effect.
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
