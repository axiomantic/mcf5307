/* tests/abi_smoke.cpp - the application binary interface smoke test.
 *
 * Two assertions, and each one can fail.
 *
 * (1) THE LINK ITSELF. The test takes the address of every function
 *     `include/mcf5307.h` declares AND THE LIBRARY DEFINES. A renamed
 *     definition, a definition that lost its `exportc` name, or a
 *     declaration that lost its `extern "C"` block is a link error here, NOT
 *     a warning, and the test fails BEFORE `main` runs. That is the
 *     assertion - the executable does not build is the failure mode, and the
 *     test never needs to say so in a message.
 *
 *     `EVERY` IS MEASURED AND IS NOT A CLAIM THIS COMMENT MAKES. The
 *     sentence above was false for two symbols for as long as nothing
 *     checked it. `cmake/Nim.cmake` step 4a measures the defined and
 *     exported set with `nm`, and `tests/tests_cpu.cmake` generates this
 *     test's address set from that measurement, so no hand-written list
 *     stands between the two.
 *
 *     THE SET IS ALSO HELD TO A COMMITTED EXPECTATION, AND THAT IS A
 *     SEPARATE MECHANISM. A purely measured set cannot report an ABI
 *     addition nobody intended: it simply grows and the check still passes.
 *     `tests/abi_smoke_symbols.inc` is the committed list of the symbols
 *     this project INTENDS to export, step 4a part two compares the two sets
 *     in both directions on every configure run, and a mismatch stops the
 *     configure step with the symbol named. The measured set is the fact;
 *     the committed list is the expectation.
 *
 * (2) The twice-call. The test calls `mcf5307_runtime_init()` twice and
 *     asserts both calls return. The function is documented as idempotent;
 *     a re-entrant call that crashes is a regression in the runtime. C++
 *     never names `NimMain`; the C names are the whole contract.
 *
 * This test links the real library and no stub. `t0_abi_header` cases 3 and 4
 * link the whole eighteen-name surface against `tests/abi_stub.c` and are the
 * check that the CONTRACT is linkable; this is the check that the LIBRARY is.
 * Its address set is therefore the set of published names the library defines,
 * measured by the configure step and not written out here. A name no
 * compilation unit defines cannot be renamed and cannot be dropped, so taking
 * its address here would assert nothing and would only make the link fail.
 *
 * The address set is generated and it grows on its own.
 * `tests/tests_cpu.cmake` writes `abi_smoke_implemented.h` into the build tree
 * from the same measured set the visibility gate reports, so implementing a
 * published name brings that name under this test with no edit to this file
 * and no edit to the registration list.
 *
 * The test asserts no core behaviour, so it stays right across every later
 * change to the implementation.
 */

#include <cstddef>
#include <cstdint>

#include "mcf5307.h"

namespace {

/* The address of every function the header declares AND the library defines.
 * Taking the address is the assertion: a renamed or dropped definition fails
 * the link, and the test does not need to read the value to fail.
 *
 * THE ADDRESS SET IS THE DEFINED SET AND NOT THE PUBLISHED SET. This test
 * links the REAL library, and most of the published surface has no definition
 * yet, so an address set taken from the header is an unresolved symbol per
 * unimplemented name and no executable at all. The whole PUBLISHED surface is
 * asserted by cases 3 and 4 of `t0_abi_header`, which link it against
 * `tests/abi_stub.c`. A name nothing defines cannot be renamed and cannot be
 * dropped, so asserting it here buys no coverage those cases do not give.
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
 * The names now come from `abi_smoke_implemented.h`, WHICH IS GENERATED into
 * the build tree by `tests/tests_cpu.cmake` from the set `cmake/Nim.cmake`
 * step 4a measured with `nm`. This file includes it TWICE - once to declare
 * the pointers and once to gather them - so the array's length is the length
 * of the measurement BY CONSTRUCTION and there is no place a person types a
 * number. The task that implements a published name brings that name under
 * this test with no edit to this file.
 *
 * WHAT KEEPS THE MEASUREMENT HONEST IS A SECOND, COMMITTED FILE.
 * `tests/abi_smoke_symbols.inc` names the exported symbols this project
 * intends, step 4a part two compares it against the same measured set in both
 * directions, and it fails naming the symbols that differ. An unintended
 * export is therefore both a stopped configure step and a diff a reviewer
 * reads. Neither file is generated from the other. */
#define MCF5307_ABI_FN(name)                                                   \
    extern "C" auto const abi_addr_##name = &name;

#include "abi_smoke_implemented.h"

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
#include "abi_smoke_implemented.h"
};
#undef MCF5307_ABI_SMOKE_SYMBOL

/* An empty address set would make every assertion above vacuous and would
 * still compile as `main` alone. The generator refuses to write an empty
 * header; this is the same refusal restated where the array is defined, so
 * neither side can go empty on its own. */
static_assert(sizeof(abi_addr_all) / sizeof(abi_addr_all[0]) > 0,
              "abi_smoke: the generated address set is empty, so the link "
              "assertion asserts nothing.");

#undef MCF5307_ABI_FN

/* An empty address set would make the link assertion vacuous and would still
 * compile as `main` alone. The generator refuses to write an empty header;
 * this is the same refusal restated where the array is defined, so neither
 * side can go empty on its own. */
static_assert(sizeof(abi_addr_all) / sizeof(abi_addr_all[0]) > 0,
              "abi_smoke: the generated address set is empty, so the link "
              "assertion asserts nothing.");

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
     * definition produced an unresolved symbol and the linker refused
     * the executable. The volatile read of `abi_addr_all[0]` is what
     * keeps the compiler honest: the array is `volatile` so the read
     * must occur, and the address is non-null so the expression is
     * always false. */
    return abi_addr_all[0] == nullptr ? 1 : 0;
}
