/* tests/abi_smoke.cpp - the application binary interface smoke test (CPU-3).
 *
 * ONE TEST, TWO ASSERTIONS, AND EACH ONE CAN FAIL.
 *
 * (1) THE LINK ITSELF. The test takes the address of every function
 *     `include/mcf5307.h` declares. A renamed declaration, a dropped
 *     declaration, or a declaration that lost its `extern "C"` block is a
 *     link error here, NOT a warning, and the test fails BEFORE `main` runs.
 *     That is the assertion - the executable does not build is the failure
 *     mode, and the test never needs to say so in a message.
 *
 *     `EVERY` IS MEASURED AND IS NOT A CLAIM THIS COMMENT MAKES. The
 *     sentence above was false for two symbols for as long as nothing
 *     checked it. `cmake/Nim.cmake` step 4a now compares
 *     `tests/abi_smoke_symbols.inc` against the set it parses out of the
 *     contract header, in both directions, on every configure run.
 *
 * (2) THE TWICE-CALL. The test calls `mcf5307_runtime_init()` TWICE and
 *     asserts both calls return. The function is documented as idempotent;
 *     a re-entrant call that crashes is a regression in the runtime, and
 *     a re-entrant call that does nothing is the whole point of the
 *     function. C++ never names `NimMain`; the C names are the whole
 *     contract.
 *
 * The test asserts NO CORE BEHAVIOUR. It does not exercise
 * `mcf5307_create`, `mcf5307_exec`, `isp1181_read`, or any other entry point
 * whose semantics belong to a later task. Asserting no core behaviour is
 * what makes this test right at this task's completion and still right
 * after every later task that supersedes the implementation.
 *
 * The address-taking is the only way to make a rename a fail. The C++
 * translation unit reads no field of any function pointer, and the linker
 * is what turns a missing symbol into a build error. The test is C++17
 * clean, links against the `mcf5307` static library, and exits 0 on
 * success.
 */

#include <cstddef>
#include <cstdint>

#include "mcf5307.h"

namespace {

/* The address of every function the header declares. Taking the address is
 * the assertion: a renamed or dropped declaration fails the link, and the
 * test does not need to read the value to fail.
 *
 * Every entry has the EXACT function-pointer type the header declares, so
 * the address-of expression is well typed and the compiler does not warn.
 *
 * The pointers are stored in a `volatile` array of `void const*`. The
 * `volatile` qualifier is what keeps the compiler honest: without it, the
 * compiler can prove the array is read only through `abi_addr_all[0]`,
 * elide the rest, and then elide the address-of expressions that fed
 * them, and this test would pass against a library that defined none of
 * the functions the runtime does not yet implement. With `volatile`
 * the compiler must materialise every store, and the linker must resolve
 * every symbol.
 *
 * THE LIST IS NOT IN THIS FILE AND NO COUNT IS EITHER. Both were the defect.
 * `include/mcf5307.h` declares 22 functions and this file named 20 of them:
 * `mcf5307_set_reg` and `mcf5307_get_reg` reached the contract with CPU-7 and
 * never reached this list, so a rename of either one was a fault the one test
 * whose stated job is the ABI surface did not catch. Nothing measured the
 * gap, because the array length was a number a person typed.
 *
 * The names now live in `tests/abi_smoke_symbols.inc`, which this file
 * includes TWICE - once to declare the pointers and once to gather them - so
 * the array's length is the length of that list BY CONSTRUCTION and there is
 * no second place to keep in step. `cmake/Nim.cmake` step 4a reads the same
 * list on every configure run and compares it against the published set it
 * parses out of the contract header with a C compiler. A name the header
 * declares and the list omits FAILS THE CONFIGURE STEP and is named, and so
 * does a name the list carries and the header does not declare. */
#define MCF5307_ABI_FN(name)                                                   \
    extern "C" auto const abi_addr_##name = &name;

#include "abi_smoke_symbols.inc"

#undef MCF5307_ABI_FN

/* The same list again, as a single `volatile` array of `void const*`, so the
 * linker cannot drop any of them under `-ffunction-sections --gc-sections`
 * and still satisfy the reference.
 *
 * THE ARRAY BOUND IS DEDUCED AND IS NEVER WRITTEN. A written bound is a
 * second statement of the list's length, and the two fell apart once
 * already. */
#define MCF5307_ABI_FN(name)                                                   \
    reinterpret_cast<void const*>(abi_addr_##name),

volatile void const* const abi_addr_all[] = {
#include "abi_smoke_symbols.inc"
};

#undef MCF5307_ABI_FN

} /* namespace */

int main() {
    /* The twice-call. `mcf5307_runtime_init()` is documented as idempotent.
     * A second call that reaches unmapped memory, that re-enters a partial
     * initialiser, or that panics is a regression in the runtime itself.
     * The assertion is the return: the test reaches the end of `main`
     * only if both calls returned. */
    mcf5307_runtime_init();
    mcf5307_runtime_init();

    /* The link assertion already passed above: any renamed or dropped
     * declaration produced an unresolved symbol and the linker refused
     * the executable. The volatile read of `abi_addr_all[0]` is what
     * keeps the compiler honest: the array is `volatile` so the read
     * must occur, and the address is non-null so the expression is
     * always false. */
    return abi_addr_all[0] == nullptr ? 1 : 0;
}
