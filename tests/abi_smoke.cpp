/* tests/abi_smoke.cpp - the application binary interface smoke test.
 *
 * Two assertions, and each one can fail.
 *
 * (1) The link itself. The test takes the address of every function
 *     `include/mcf5307.h` declares and the library defines. A renamed
 *     definition, a definition that lost its `exportc` name, or a
 *     declaration that lost its `extern "C"` block is a link error here, not
 *     a warning, and the test fails before `main` runs. That is the
 *     assertion - the executable does not build is the failure mode, and the
 *     test never needs to say so in a message.
 *
 *     "Every" is measured, not claimed. `cmake/Nim.cmake` step 4a measures
 *     the defined and exported set with `nm`, and `tests/tests_cpu.cmake`
 *     generates this test's address set from that measurement, so no
 *     hand-written list stands between the two.
 *
 *     The set is also held to a committed expectation, and that is a
 *     separate mechanism. A purely measured set cannot report an ABI
 *     addition nobody intended: it simply grows and the check still passes.
 *     `tests/abi_smoke_symbols.inc` is the committed list of the symbols
 *     this project intends to export, step 4a part two compares the two sets
 *     in both directions on every configure run, and a mismatch stops the
 *     configure step with the symbol named. The measured set is the fact;
 *     the committed list is the expectation.
 *
 * (2) The twice-call. The test calls `mcf5307_runtime_init()` twice and
 *     asserts both calls return. The function is documented as idempotent;
 *     a re-entrant call that crashes is a regression in the runtime. C++
 *     never names `NimMain`; the C names are the whole contract.
 *
 * Asserting no core behaviour is
 * what makes this test right at this task's completion and still right
 * after every later task that supersedes the implementation.
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
 * The address set is the defined set and not the published set. This test
 * links the real library, and most of the published surface has no definition
 * yet, so an address set taken from the header is an unresolved symbol per
 * unimplemented name and no executable at all. The whole published surface is
 * asserted by cases 3 and 4 of `t0_abi_header`, which link it against
 * `tests/abi_stub.c`. A name nothing defines cannot be renamed and cannot be
 * dropped, so asserting it here buys no coverage those cases do not give.
 *
 * Every entry has the exact function-pointer type the header declares, so
 * the address-of expression is well typed and the compiler does not warn.
 *
 * The pointers are stored in a `volatile` array of `void const*`. The
 * `volatile` qualifier is what keeps the compiler honest: without it, the
 * compiler can prove the array is read only through `abi_addr_all[0]`,
 * elide the rest, and then elide the address-of expressions that fed
 * them. With `volatile`
 * the compiler must materialise every store, and the linker must resolve
 * every symbol.
 *
 * THE LIST IS NOT IN THIS FILE AND NO COUNT IS EITHER.
 *
 * What keeps the measurement honest is a second, committed file.
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
 * The array bound is deduced and is never written. A written bound is a
 * second statement of the list's length. */
#define MCF5307_ABI_FN(name)                                                   \
    reinterpret_cast<void const*>(abi_addr_##name),

volatile void const* const abi_addr_all[] = {
#include "abi_smoke_implemented.h"
};

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
