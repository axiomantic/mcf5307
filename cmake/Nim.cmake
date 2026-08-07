# cmake/Nim.cmake
# Configure-time checks and helpers for the Nim 2.2.10 toolchain.

find_program(NIM_EXECUTABLE nim REQUIRED)

# Check Nim compiler version (pinned to 2.2.10)
execute_process(
    COMMAND "${NIM_EXECUTABLE}" --version
    OUTPUT_VARIABLE NIM_VERSION_OUTPUT
    ERROR_VARIABLE NIM_VERSION_ERROR
    RESULT_VARIABLE NIM_VERSION_RESULT
)

if(NOT NIM_VERSION_RESULT EQUAL 0)
    message(FATAL_ERROR "Failed to run Nim compiler: ${NIM_VERSION_ERROR}")
endif()

string(REGEX MATCH "Nim Compiler Version ([0-9]+\\.[0-9]+\\.[0-9]+)" NIM_VERSION_MATCH "${NIM_VERSION_OUTPUT}")
if(NOT NIM_VERSION_MATCH)
    message(FATAL_ERROR "Could not parse Nim version from output:\n${NIM_VERSION_OUTPUT}")
endif()

set(NIM_VERSION "${CMAKE_MATCH_1}")

if(NOT NIM_VERSION STREQUAL "2.2.10")
    message(FATAL_ERROR "Nim toolchain pinned at 2.2.10, but found Nim version ${NIM_VERSION}")
endif()

# Configure-time prefix check for Nim toolchain
get_filename_component(NIM_BIN_DIR "${NIM_EXECUTABLE}" REALPATH)
get_filename_component(NIM_BIN_DIR "${NIM_BIN_DIR}" DIRECTORY)
get_filename_component(NIM_PREFIX "${NIM_BIN_DIR}" DIRECTORY)

# Locate Nim stdlib include directory containing nimbase.h
find_path(NIM_INCLUDE_DIR nimbase.h
    HINTS
        "${NIM_PREFIX}/lib"
        "${NIM_PREFIX}/lib/nim"
    REQUIRED
)

message(STATUS "Found Nim 2.2.10 at prefix: ${NIM_PREFIX} (include: ${NIM_INCLUDE_DIR})")
