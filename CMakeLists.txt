# The root of the `mcf5307` CMake project.

cmake_minimum_required(VERSION 3.20)

project(mcf5307
    VERSION 0.1.0
    DESCRIPTION "An MCF5307 ColdFire core and an ISP1181 USB device model"
    LANGUAGES C CXX)

enable_testing()

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
include(Nim)

# Nim build integration generating mcf5307_nim.h
set(NIMCACHE_DIR "${CMAKE_CURRENT_BINARY_DIR}/nimcache")
file(MAKE_DIRECTORY "${NIMCACHE_DIR}")

set(NIM_ENTRY "${CMAKE_CURRENT_SOURCE_DIR}/src/mcf5307.nim")

# Flags per §7.11: --panics:on is required, --checks:off is forbidden
set(NIM_FLAGS
    c
    --noMain
    --noLinking
    --header:mcf5307_nim.h
    --panics:on
    --nimcache:${NIMCACHE_DIR}
)

execute_process(
    COMMAND "${NIM_EXECUTABLE}" ${NIM_FLAGS} "${NIM_ENTRY}"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    RESULT_VARIABLE NIM_BUILD_RES
)

if(NOT NIM_BUILD_RES EQUAL 0)
    message(FATAL_ERROR "Nim compilation failed with code ${NIM_BUILD_RES}")
endif()

file(GLOB NIM_GENERATED_C "${NIMCACHE_DIR}/*.c")
file(GLOB_RECURSE NIM_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/src/*.nim")

add_custom_command(
    OUTPUT ${NIM_GENERATED_C} "${NIMCACHE_DIR}/mcf5307_nim.h"
    COMMAND "${NIM_EXECUTABLE}" ${NIM_FLAGS} "${NIM_ENTRY}"
    DEPENDS ${NIM_SOURCES}
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    COMMENT "Compiling Nim sources to C (with --panics:on)"
)

# Export the CMake target mcf5307::mcf5307
add_library(mcf5307 STATIC ${NIM_GENERATED_C})
add_library(mcf5307::mcf5307 ALIAS mcf5307)

target_include_directories(mcf5307 PUBLIC
    $<BUILD_INTERFACE:${PROJECT_SOURCE_DIR}/include>
    $<BUILD_INTERFACE:${NIMCACHE_DIR}>
    $<BUILD_INTERFACE:${NIM_INCLUDE_DIR}>
)

export(TARGETS mcf5307 NAMESPACE mcf5307:: FILE "${CMAKE_CURRENT_BINARY_DIR}/mcf5307Targets.cmake")

# The T0 test aggregate.
add_custom_target(mcf5307_tests
    COMMENT "Building the mcf5307 T0 test set")

add_subdirectory(tests)
add_subdirectory(conformance)
