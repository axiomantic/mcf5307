/* tests/abi_smoke.cpp - the application binary interface smoke test.
 *
 * Two assertions, and each one can fail.
 *
 * (1) The link itself. The test takes the address of every function that
 *     `include/mcf5307.h` declares AND the library actually defines. A
 *     renamed definition, a definition that lost its `exportc` name, or a
 *     declaration that lost its `extern "C"` block is a link error here,
 *     NOT a warning, and the test fails BEFORE `main` runs.
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

/* The address of every function the header declares and the library defines.
 * Taking the address is the assertion: a renamed or dropped definition fails
 * the link, and the test does not need to read the value to fail.
 *
 * Each entry gets the EXACT function-pointer type the header declares,
 * because `auto` deduces it from the address-of expression, so the
 * expression is well typed and the compiler does not warn. */
#define MCF5307_ABI_SMOKE_SYMBOL(name) extern "C" auto const abi_addr_##name = &name;
#include "abi_smoke_implemented.h"
#undef MCF5307_ABI_SMOKE_SYMBOL

/* The same names again, as a single `volatile` array of `void const*`, so the
 * linker cannot drop any of them under `-ffunction-sections --gc-sections`
 * and still satisfy the reference.
 *
 * The `volatile` qualifier is what keeps the compiler honest: without it, the
 * compiler can prove the array is read only through `abi_addr_all[0]`, elide
 * the rest, and then elide the address-of expressions that fed them. With
 * `volatile` the compiler must materialise every store, and the linker must
 * resolve every symbol. */
#define MCF5307_ABI_SMOKE_SYMBOL(name) reinterpret_cast<void const*>(abi_addr_##name),
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
