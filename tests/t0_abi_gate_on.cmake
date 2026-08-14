# The driver of the registered test `t0_abi_gate_on`. `GATE_CACHE_OFFSET` and
# `GATE_STAMP_OFFSET` are RELATIVE paths - to the build tree's `CMakeCache.txt`
# and to the record step 4a left behind - resolved HERE against the working
# directory, so the files read are the running tree's and not this file's.

foreach(offset_name GATE_CACHE_OFFSET GATE_STAMP_OFFSET)
    if(NOT ${offset_name})
        message(FATAL_ERROR
            "t0_abi_gate_on: ${offset_name} is empty or unset. ctest passes "
            "it. Run `ctest -R '^t0_abi_gate_on$'` from a build tree rather "
            "than running this file directly.")
    endif()
endforeach()

# In script mode CMAKE_CURRENT_BINARY_DIR is the directory cmake was started
# in, and ctest starts a test in the binary directory that registered it - in
# the tree ctest itself was invoked in, which is the anchor that makes this
# survive a copied build tree. BASE_DIR is named rather than defaulted.
get_filename_component(GATE_CACHE "${GATE_CACHE_OFFSET}" ABSOLUTE
    BASE_DIR "${CMAKE_CURRENT_BINARY_DIR}")

if(NOT EXISTS "${GATE_CACHE}")
    message(FATAL_ERROR
        "t0_abi_gate_on: no cache file at ${GATE_CACHE}. The test reads the "
        "persisted cache entry, and there is nothing here to read.")
endif()

file(STRINGS "${GATE_CACHE}" gate_lines REGEX "^MCF5307_ABI_GATE:")
list(LENGTH gate_lines gate_count)
if(NOT gate_count EQUAL 1)
    message(FATAL_ERROR
        "t0_abi_gate_on: ${GATE_CACHE} carries ${gate_count} "
        "MCF5307_ABI_GATE entr(y/ies) and exactly 1 is expected: "
        "`${gate_lines}`. Zero means cmake/Nim.cmake no longer declares the "
        "switch, and step 4a is then unreachable rather than off.")
endif()

string(REGEX REPLACE "^MCF5307_ABI_GATE:[A-Z]+=" "" gate_value "${gate_lines}")
if(NOT gate_value)
    message(FATAL_ERROR
        "t0_abi_gate_on: MCF5307_ABI_GATE is `${gate_value}` in ${GATE_CACHE}. "
        "THE SWITCH IS OFF IN THIS BUILD TREE. The configure-time warning "
        "`mcf5307: step 4a IS TURNED OFF` in cmake/Nim.cmake enumerates what a "
        "run without step 4a did not measure; that warning is the one "
        "statement of it. The entry is a CACHE entry and it persists: "
        "reconfigure this tree with -DMCF5307_ABI_GATE=ON, or configure a "
        "fresh tree.")
endif()

# The switch reads on. That is the switch and not the work, so the rest of this
# driver reads the record step 4a leaves when it actually runs.
get_filename_component(GATE_STAMP "${GATE_STAMP_OFFSET}" ABSOLUTE
    BASE_DIR "${CMAKE_CURRENT_BINARY_DIR}")

if(NOT EXISTS "${GATE_STAMP}")
    message(FATAL_ERROR
        "t0_abi_gate_on: MCF5307_ABI_GATE reads `${gate_value}` in "
        "${GATE_CACHE} AND STEP 4a'S BRANCH STILL DID NOT RUN IN THE MOST "
        "RECENT CONFIGURE OF THIS TREE THAT REACHED tests/. There is no "
        "${GATE_STAMP}. "
        "cmake/Nim.cmake writes that record at the END of step 4a's own "
        "branch and tests/tests_cpu.cmake MOVES it here on every configure, "
        "so a tree whose branch ran has one and a tree whose branch did not "
        "has none. Two ways to reach this state: the branch was deleted from "
        "cmake/Nim.cmake while the `set()` that declares the switch was kept, "
        "or a parent list file set MCF5307_ABI_GATE as a NORMAL variable "
        "before add_subdirectory() and it shadows the cache entry from the "
        "second configure onward. The configure-time warning `mcf5307: step "
        "4a IS TURNED OFF` enumerates what an unmeasured build does not know "
        "about itself.")
endif()

file(STRINGS "${GATE_STAMP}" stamp_lines)
list(LENGTH stamp_lines stamp_line_count)
if(NOT stamp_line_count EQUAL 7)
    message(FATAL_ERROR
        "t0_abi_gate_on: ${GATE_STAMP} carries ${stamp_line_count} line(s) and "
        "exactly 7 are expected: `${stamp_lines}`. cmake/Nim.cmake writes the "
        "record in one `file(WRITE)` at the end of step 4a, so a short record "
        "is a record the writer and this reader no longer agree on.")
endif()

list(GET stamp_lines 0 stamp_head)
if(NOT stamp_head STREQUAL "MCF5307_ABI_GATE_RAN")
    message(FATAL_ERROR
        "t0_abi_gate_on: ${GATE_STAMP} opens with `${stamp_head}` and "
        "`MCF5307_ABI_GATE_RAN` is expected. The file in that place is not the "
        "record step 4a writes.")
endif()

set(stamp_index 1)
foreach(key IN ITEMS CONTRACT PUBLISHED VISIBLE UNIMPLEMENTED STUB_EXTERNAL_OWN
        SITES)
    list(GET stamp_lines ${stamp_index} stamp_line)
    if(NOT stamp_line MATCHES "^${key}=(.*)$")
        message(FATAL_ERROR
            "t0_abi_gate_on: line ${stamp_index} of ${GATE_STAMP} is "
            "`${stamp_line}` and a `${key}=` line is expected there.")
    endif()
    set(stamp_${key} "${CMAKE_MATCH_1}")
    math(EXPR stamp_index "${stamp_index} + 1")
endforeach()

if(stamp_CONTRACT STREQUAL "")
    message(FATAL_ERROR
        "t0_abi_gate_on: ${GATE_STAMP} names no contract file. Step 4a reads "
        "one file for the published set and records which.")
endif()

foreach(key PUBLISHED VISIBLE UNIMPLEMENTED STUB_EXTERNAL_OWN SITES)
    if(NOT "${stamp_${key}}" MATCHES "^[0-9]+$")
        message(FATAL_ERROR
            "t0_abi_gate_on: ${GATE_STAMP} records ${key}=`${stamp_${key}}`, "
            "which is not a count. Step 4a records what it measured.")
    endif()
endforeach()

# The site counter. Step 4a's three parts and nine controls each add one where
# they finish, and control A runs on both reads, so a branch with every site in
# it records thirteen. A part or a control deleted from cmake/Nim.cmake takes
# its increment with it and lands here as a shortfall.
if(NOT stamp_SITES EQUAL 13)
    message(FATAL_ERROR
        "t0_abi_gate_on: ${GATE_STAMP} records SITES=${stamp_SITES} and 13 are "
        "expected. Step 4a's three parts and nine controls each increment "
        "MCF5307_ABI_GATE_SITES where they finish, and control A increments on "
        "the calibration read and again on the contract read. A count below 13 "
        "is a part or a control that is no longer in cmake/Nim.cmake; a count "
        "above it is a site counted twice. Either way the branch that ran is "
        "not the branch this test is written against.")
endif()

# The counts came from separate measurements - the published set read out of
# the contract header, `nm` on the measurement shared object, and `nm` on the
# link-partner stub object - so holding them against each other is a check and
# not a restatement.
if(stamp_PUBLISHED LESS 1)
    message(FATAL_ERROR
        "t0_abi_gate_on: ${GATE_STAMP} records PUBLISHED=${stamp_PUBLISHED}. "
        "Step 4a ran against a contract header it read no published symbol "
        "out of, and the three parts then measured an empty set.")
endif()

math(EXPR stamp_partition "${stamp_VISIBLE} + ${stamp_UNIMPLEMENTED}")
if(NOT stamp_partition EQUAL stamp_PUBLISHED)
    message(FATAL_ERROR
        "t0_abi_gate_on: ${GATE_STAMP} records PUBLISHED=${stamp_PUBLISHED} "
        "but VISIBLE=${stamp_VISIBLE} plus "
        "UNIMPLEMENTED=${stamp_UNIMPLEMENTED} is ${stamp_partition}. Part one "
        "of step 4a puts every published symbol in exactly one of those two: "
        "exported by the measurement shared object, or defined by no "
        "compilation unit. A published symbol in neither is one part one did "
        "not account for.")
endif()

if(NOT stamp_STUB_EXTERNAL_OWN EQUAL stamp_PUBLISHED)
    message(FATAL_ERROR
        "t0_abi_gate_on: ${GATE_STAMP} records "
        "STUB_EXTERNAL_OWN=${stamp_STUB_EXTERNAL_OWN} against "
        "PUBLISHED=${stamp_PUBLISHED}. Part three of step 4a holds the "
        "external definitions of the link-partner stub equal to the published "
        "set, so the two counts are the same count when it has run.")
endif()

message("t0_abi_gate_on: MCF5307_ABI_GATE is `${gate_value}` in ${GATE_CACHE}, "
    "and step 4a's BRANCH RAN THROUGH - no fault fired and all "
    "${stamp_SITES} sites ran - in the most recent configure of this tree "
    "THAT REACHED tests/. ${GATE_STAMP} records CONTRACT=${stamp_CONTRACT} "
    "PUBLISHED=${stamp_PUBLISHED} VISIBLE=${stamp_VISIBLE} "
    "UNIMPLEMENTED=${stamp_UNIMPLEMENTED} "
    "STUB_EXTERNAL_OWN=${stamp_STUB_EXTERNAL_OWN}. THAT IS WHAT THIS TEST "
    "ASSERTS AND ALL OF IT: that the branch RAN, not that the gate is "
    "CORRECT. A configure that aborts inside step 4a never reaches tests/ and "
    "leaves the previous stamp standing, which is why this line says `that "
    "reached tests/`.")
