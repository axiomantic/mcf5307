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

set(MCF5307_NIM_ENTRY "${PROJECT_SOURCE_DIR}/src/mcf5307.nim")
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

# Each entry module's command is written out and is never derived from the
# entry name. A derived prefix cannot collide. It would therefore make the
# duplicate half of step 2a unable to fail. A check that cannot fail is worse
# than no check.
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
# Steps 2 to 6 build the one library of the one-project convention. The note of
# check step 3 names the integration a second entry module would need.
set(MCF5307_NIM_COMMAND ${MCF5307_NIM_COMMAND_mcf5307})

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
# The generated C includes `nimbase.h` from the Nim installation. Measured on
# Nim 2.2.10, that is the only header of the toolchain the units name, and
# every other header they name is a system header. One unit compiled with the
# Nim library directory as its sole `-I` confirms it. The cache directory is
# therefore not on the search path here: the units live in it, and a quoted
# include resolves against the including file's own directory first.
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
    message(FATAL_ERROR
        "mcf5307: step 4 failed: nimbase.h was not found. Every generated C "
        "unit includes that header.\n"
        "  compiler       : ${MCF5307_NIM_EXECUTABLE}\n"
        "  dump exit      : ${MCF5307_NIM_DUMP_RESULT}\n"
        "  dump stdout    : ${MCF5307_NIM_DUMP_OUTPUT}\n"
        "  dump stderr    : ${MCF5307_NIM_DUMP_ERROR}\n"
        "  directory tried: ${MCF5307_NIM_LIB_DIR}\n"
        "The directory comes from the compiler's own `dump` report, and a path "
        "walk from the resolved executable is the fallback.")
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
#   `-w`, or `/w` for MSVC, silences the warnings of the units themselves. It
#   is appended after `CMAKE_C_FLAGS`, so it also disarms a `-Werror` that a
#   consumer set there. Measured: without it, a configure with
#   `-Wall -Wextra -Werror` builds until Nim's own `digitsutils.nim.c` raises
#   `variable 'T1_' set but not used`, and the build fails.
#
# The collision is scheduled and not hypothetical. `tests/tests_cpu.cmake`
# already compiles with `-Wall -Wextra -pedantic -Werror`.
target_include_directories(mcf5307_nim_objs SYSTEM PRIVATE
    "${MCF5307_NIM_LIB_DIR}")
target_compile_options(mcf5307_nim_objs PRIVATE
    "$<IF:$<C_COMPILER_ID:MSVC>,/w,-w>")
set_target_properties(mcf5307_nim_objs PROPERTIES
    C_STANDARD 11
    POSITION_INDEPENDENT_CODE ON)

# Nim 2.2 builds with threads on. Measured on Nim 2.2.10, the unit list holds
# `std/typedthreads`, which is what that setting puts there.
#
# The generated runtime names no thread function of its own. `nm` over the
# archive reports zero matches for `pthread`. It reports two for
# `__tlv_bootstrap` in the same run, which is the positive control. Nim's own
# link command in the JSON build file carries `-ldl` and no `-lpthread`. The
# thread-local storage the runtime uses goes through the platform's own
# mechanism.
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
# procedure. Measured on Nim 2.2.10, `{.exportc, cdecl.}` alone translates to
# `N_LIB_PRIVATE`, which `nimbase.h` defines as `visibility("hidden")` for gcc
# and clang. The same procedure with `dynlib` translates to `N_LIB_EXPORT`,
# which is `visibility("default")`.
#
# No check that exists could see that fault. `nm` over the static archive
# reports a hidden symbol as `T`, and the smoke test of CPU-3 links statically.
# A shared object built from the archive is the first thing that reports it,
# and nothing in this project builds one. This check reads the generated C
# instead, where the decision is plain text.
#
# It reads what the compiler wrote and not a separate declaration of intent. It
# holds for a symbol a later cpu task adds, without an edit here.
#
# The name list comes from the header Nim writes for `--header:`. Nim declares
# every `exportc` procedure of the compilation in that header and declares no
# procedure that is not one. A C name Nim mangled for an internal procedure
# never reaches the header. That is what keeps an internal name out of this
# check when its Nim identifier happens to start with the prefix.
#
# The storage class comes from the generated `.c` units, where `N_LIB_EXPORT`
# and `N_LIB_PRIVATE` are the visibility attribute itself.

set(MCF5307_ABI_PREFIX "mcf5307_")

# The names Nim's own runtime scaffolding takes under `--nimMainPrefix:`. They
# share the prefix and they are not part of the published surface. A procedure
# a later task exports under one of these names is skipped by this check.
set(MCF5307_ABI_SCAFFOLDING "")
foreach(suffix
        NimMain NimMainInner NimMainModule
        PreMain PreMainInner NimDestroyGlobals)
    list(APPEND MCF5307_ABI_SCAFFOLDING "${MCF5307_NIM_ENTRY_PREFIX}${suffix}")
endforeach()

set(MCF5307_ABI_DECLARATION
    "N_[A-Z_]+\\(.*[, \t](${MCF5307_ABI_PREFIX}[A-Za-z0-9_]+)\\)\\(")

set(MCF5307_ABI_HEADER_FILE "${MCF5307_NIMCACHE}/${MCF5307_NIM_HEADER}")
if(NOT EXISTS "${MCF5307_ABI_HEADER_FILE}")
    message(FATAL_ERROR
        "mcf5307: step 4a failed: ${MCF5307_ABI_HEADER_FILE} does not exist. "
        "Step 2 passes `--header:${MCF5307_NIM_HEADER}`, so the file is the "
        "compiler's own list of the exported procedures, and the check reads "
        "its names from there.")
endif()

set(MCF5307_ABI_NAMES "")
file(STRINGS "${MCF5307_ABI_HEADER_FILE}" MCF5307_ABI_HEADER_LINES)
foreach(line IN LISTS MCF5307_ABI_HEADER_LINES)
    if(NOT line MATCHES "${MCF5307_ABI_DECLARATION}")
        continue()
    endif()
    if(CMAKE_MATCH_1 IN_LIST MCF5307_ABI_SCAFFOLDING)
        continue()
    endif()
    list(APPEND MCF5307_ABI_NAMES "${CMAKE_MATCH_1}")
endforeach()
list(REMOVE_DUPLICATES MCF5307_ABI_NAMES)

# The first positive control. An empty name list makes every test below vacuous
# and an empty hidden list is exactly what a pass looks like.
if(MCF5307_ABI_NAMES STREQUAL "")
    message(FATAL_ERROR
        "mcf5307: step 4a failed: ${MCF5307_ABI_HEADER_FILE} names no exported "
        "procedure with the `${MCF5307_ABI_PREFIX}` prefix. This project "
        "exports at least `mcf5307_runtime_init`, so an empty list means the "
        "check no longer reads what it was written to read.")
endif()

set(MCF5307_ABI_VISIBLE "")
set(MCF5307_ABI_HIDDEN "")
foreach(unit IN LISTS MCF5307_NIM_C_SOURCES)
    file(STRINGS "${unit}" MCF5307_ABI_LINES)
    foreach(line IN LISTS MCF5307_ABI_LINES)
        if(NOT line MATCHES
                "^(N_LIB_EXPORT|N_LIB_PRIVATE)?[ \t]*${MCF5307_ABI_DECLARATION}")
            continue()
        endif()
        set(MCF5307_ABI_STORAGE "${CMAKE_MATCH_1}")
        set(MCF5307_ABI_SYMBOL "${CMAKE_MATCH_2}")
        if(NOT MCF5307_ABI_SYMBOL IN_LIST MCF5307_ABI_NAMES)
            continue()
        endif()
        if(MCF5307_ABI_STORAGE STREQUAL "N_LIB_EXPORT")
            list(APPEND MCF5307_ABI_VISIBLE "${MCF5307_ABI_SYMBOL}")
        else()
            list(APPEND MCF5307_ABI_HIDDEN "${MCF5307_ABI_SYMBOL}")
        endif()
    endforeach()
endforeach()
list(REMOVE_DUPLICATES MCF5307_ABI_VISIBLE)
list(REMOVE_DUPLICATES MCF5307_ABI_HIDDEN)

if(NOT MCF5307_ABI_HIDDEN STREQUAL "")
    message(FATAL_ERROR
        "mcf5307: step 4a failed: a published symbol is emitted hidden.\n"
        "  hidden  : ${MCF5307_ABI_HIDDEN}\n"
        "  visible : ${MCF5307_ABI_VISIBLE}\n"
        "A symbol listed as hidden carries `N_LIB_PRIVATE` in the generated C, "
        "which is `__attribute__((visibility(\"hidden\")))`. Its Nim "
        "declaration lost the `mcf5307Abi` pragma of `src/mcf5307.nim`, and "
        "`dynlib` inside that pragma is what makes the symbol visible. The "
        "archive still builds and `nm` over the archive still reports the "
        "symbol, so this is the only step that reports the fault.")
endif()

# The second positive control. Every name the header published has to have been
# seen in a unit. A name seen nowhere was neither passed nor failed, and this
# check would have said nothing about it.
set(MCF5307_ABI_UNSEEN "")
foreach(name IN LISTS MCF5307_ABI_NAMES)
    if(NOT name IN_LIST MCF5307_ABI_VISIBLE)
        list(APPEND MCF5307_ABI_UNSEEN "${name}")
    endif()
endforeach()
if(NOT MCF5307_ABI_UNSEEN STREQUAL "")
    message(FATAL_ERROR
        "mcf5307: step 4a failed: a published symbol was not found in any "
        "generated C unit.\n"
        "  unseen  : ${MCF5307_ABI_UNSEEN}\n"
        "  visible : ${MCF5307_ABI_VISIBLE}\n"
        "${MCF5307_ABI_HEADER_FILE} names it and the units of step 3 do not "
        "define it. The check reported nothing about that symbol, and silence "
        "is not a pass.")
endif()

list(LENGTH MCF5307_ABI_VISIBLE MCF5307_ABI_VISIBLE_COUNT)
message(STATUS
    "mcf5307: step 4a ${MCF5307_ABI_VISIBLE_COUNT} published symbol(s) are "
    "emitted visible: ${MCF5307_ABI_VISIBLE}")

# ---------------------------------------------------------------------------
# Step 5. The static library.
#
# It carries the objects of step 4 and the hand-written public header. The
# generated `mcf5307_nim.h` is not the contract and is not published. The
# contract is `include/mcf5307.h`, which is reviewed as one file.
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
