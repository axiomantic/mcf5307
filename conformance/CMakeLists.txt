# The `conformance/` directory list. Task CPU-26 creates it and it holds one
# `include()` of the registration list beside it.
#
# `conformance/` IS NOT `tests/`. The generated ColdFire conformance corpus and
# its runner register their own names, and they register them here rather than
# in `tests/tests_cpu.cmake`.

include(conformance_cpu.cmake)
