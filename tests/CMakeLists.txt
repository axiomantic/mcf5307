# The `tests/` directory list. Task CPU-26 creates it and it holds one
# `include()` of the registration list beside it. THE REGISTRATION LIST IS THE
# FILE LATER TASKS EDIT, AND THIS FILE IS NOT.
#
# Keeping the two apart gives every later cpu task one file to append to and no
# reason to touch a file another task also touches.

include(tests_cpu.cmake)
