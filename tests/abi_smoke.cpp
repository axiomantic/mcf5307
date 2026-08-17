/* tests/abi_smoke.cpp - the application binary interface smoke test.
 *
 * ONE TEST, AND EACH ASSERTION CAN FAIL.
 *
 * (1) THE LINK ITSELF. The test takes the address of every function
 *     `include/mcf5307.h` declares. A renamed declaration, a dropped
 *     declaration, or a declaration that lost its `extern "C"` block is a
 *     link error here, NOT a warning, and the test fails BEFORE `main` runs.
 *     That is the assertion - the executable does not build is the failure
 *     mode, and the test never needs to say so in a message.
 *
 *     `EVERY` IS MEASURED AND IS NOT A CLAIM THIS COMMENT MAKES.
 *     `cmake/Nim.cmake` step 4a compares
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
 * The address-taking is the only way to make a rename a fail. The C++
 * translation unit reads no field of any function pointer, and the linker
 * is what turns a missing symbol into a build error. The test is C++17
 * clean, links against the `mcf5307` static library, and exits 0 on
 * success.
 */

#include <cstddef>
#include <cstdint>
#include <type_traits>

#include "mcf5307.h"

namespace {

/* The address of every function the header declares. Taking the address is
 * the assertion: a renamed or dropped declaration fails the link, and the
 * test does not need to read the value to fail.
 *
 * Every entry has the EXACT function-pointer type the header declares, so
 * the address-of expression is well typed and the compiler does not warn.
 *
 * THE LIST IS NOT IN THIS FILE AND NO COUNT IS EITHER.
 *
 * The names live in `tests/abi_smoke_symbols.inc`, which this file
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

/* The same list again, as one array that `main` READS IN FULL AT RUN TIME.
 *
 * THE ARRAY BOUND IS DEDUCED AND IS NEVER WRITTEN. A written bound is a
 * second statement of the list's length.
 *
 * WHERE THE `volatile` SITS IS THE WHOLE MECHANISM, and putting it one
 * position to the left silently disarms this test. `void const* const
 * volatile` qualifies THE POINTER OBJECT: reading it is an observable side
 * effect the compiler is not allowed to skip, so the array must exist in
 * memory, so its initialiser's relocations must exist, so the linker must
 * resolve every name they carry. `volatile void const* const` - one token
 * earlier - qualifies THE POINTEE instead and leaves the array an ordinary
 * constant that the compiler folds into the comparison and never emits at
 * all. The `static_assert` below is what keeps the two apart, because
 * nothing else does: both spellings compile, both look deliberate, and only
 * one of them anchors anything.
 *
 * WHY THE READ IS IN `main` AND NOT AN ATTRIBUTE. `__attribute__((used))`
 * and `retain` would also hold the symbols against a dead-stripping linker.
 * They are rejected here for the reason this test was disarmed in the first
 * place: NOTHING IN THE BUILD CAN CHECK THEM. An attribute a toolchain does
 * not honour is not an error, it is silence - and silence here is a test
 * that keeps passing while it anchors nothing, which is the exact failure
 * this file is being repaired from. A volatile read is ordinary language
 * semantics rather than a request the toolchain may decline, its one
 * failure mode is the qualifier's position, and the `static_assert` above
 * fails the build over that. Prefer the mechanism whose breakage is
 * loud. */
#define MCF5307_ABI_FN(name)                                                   \
    reinterpret_cast<void const*>(abi_addr_##name),

void const* const volatile abi_addr_all[] = {
#include "abi_smoke_symbols.inc"
};

#undef MCF5307_ABI_FN

static_assert(
    std::is_volatile<std::remove_extent<decltype(abi_addr_all)>::type>::value,
    "abi_addr_all's ELEMENTS must be volatile-qualified. If this fires, the "
    "qualifier has migrated onto the pointee and the array is a plain "
    "constant again: the compiler may fold the reads in main, emit no array, "
    "and let the linker drop every symbol this test exists to require.");

} /* namespace */

int main() {
    /* The twice-call. `mcf5307_runtime_init()` is documented as idempotent.
     * A second call that reaches unmapped memory, that re-enters a partial
     * initialiser, or that panics is a regression in the runtime itself.
     * The assertion is the return: the test reaches the end of `main`
     * only if both calls returned. */
    mcf5307_runtime_init();
    mcf5307_runtime_init();

    /* THIS LOOP IS THE ANCHOR AND NOT A CHECK. The comparison cannot fail -
     * every element is the address of a function - and the return value is
     * not what this loop is for. It is here so that every element is READ,
     * because a volatile read is what the compiler must keep and what the
     * linker must therefore resolve. The failure this file exists to
     * produce happens EARLIER THAN ANY OF THIS: a name the library no
     * longer defines is an unresolved symbol and there is no executable to
     * run.
     *
     * The range-`for` is what makes `every` true without writing a count. */
    for (void const* const address : abi_addr_all) {
        if (address == nullptr) {
            return 1;
        }
    }

    return 0;
}
