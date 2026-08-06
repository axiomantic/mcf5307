# The cpu track's registration list for `tests/`.
#
# CPU-26 CREATES THIS FILE EMPTY AND REGISTERS NOTHING IN IT. That is the
# correct state for the skeleton, and CPU-26's own check asserts it by reading
# `Total Tests: 0` out of the CTest listing.
#
# Each later cpu task adds its own `add_test(NAME <name> ...)` line here, with
# whatever target the name needs, and attaches that target to the `mcf5307_tests`
# aggregate that the root list creates.
