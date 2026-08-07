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
 * The 18 pointers are stored in a `volatile` array of `void const*`. The
 * `volatile` qualifier is what keeps the compiler honest: without it, the
 * compiler can prove the array is read only through `abi_addr_all[0]`,
 * elide the rest, and then elide the address-of expressions that fed
 * them, and this test would pass against a library that defined none of
 * the 17 functions the runtime does not yet implement. With `volatile`
 * the compiler must materialise every store, and the linker must resolve
 * every symbol. */
#define MCF5307_ABI_FN(name)                                                   \
    extern "C" auto const abi_addr_##name = &name

MCF5307_ABI_FN(mcf5307_runtime_init);
MCF5307_ABI_FN(mcf5307_create);
MCF5307_ABI_FN(mcf5307_destroy);
MCF5307_ABI_FN(mcf5307_reset);
MCF5307_ABI_FN(mcf5307_exec);
MCF5307_ABI_FN(mcf5307_set_irq);
MCF5307_ABI_FN(mcf5307_state_size);
MCF5307_ABI_FN(mcf5307_state_save);
MCF5307_ABI_FN(mcf5307_state_load);
MCF5307_ABI_FN(isp1181_create);
MCF5307_ABI_FN(isp1181_destroy);
MCF5307_ABI_FN(isp1181_read);
MCF5307_ABI_FN(isp1181_write);
MCF5307_ABI_FN(isp1181_rx);
MCF5307_ABI_FN(isp1181_tick);
MCF5307_ABI_FN(isp1181_state_size);
MCF5307_ABI_FN(isp1181_state_save);
MCF5307_ABI_FN(isp1181_state_load);

/* The 18 pointers as a single `volatile` array of `void const*`, so the
 * linker cannot drop any of them under `-ffunction-sections --gc-sections`
 * and still satisfy the reference. */
volatile void const* const abi_addr_all[18] = {
    reinterpret_cast<void const*>(abi_addr_mcf5307_runtime_init),
    reinterpret_cast<void const*>(abi_addr_mcf5307_create),
    reinterpret_cast<void const*>(abi_addr_mcf5307_destroy),
    reinterpret_cast<void const*>(abi_addr_mcf5307_reset),
    reinterpret_cast<void const*>(abi_addr_mcf5307_exec),
    reinterpret_cast<void const*>(abi_addr_mcf5307_set_irq),
    reinterpret_cast<void const*>(abi_addr_mcf5307_state_size),
    reinterpret_cast<void const*>(abi_addr_mcf5307_state_save),
    reinterpret_cast<void const*>(abi_addr_mcf5307_state_load),
    reinterpret_cast<void const*>(abi_addr_isp1181_create),
    reinterpret_cast<void const*>(abi_addr_isp1181_destroy),
    reinterpret_cast<void const*>(abi_addr_isp1181_read),
    reinterpret_cast<void const*>(abi_addr_isp1181_write),
    reinterpret_cast<void const*>(abi_addr_isp1181_rx),
    reinterpret_cast<void const*>(abi_addr_isp1181_tick),
    reinterpret_cast<void const*>(abi_addr_isp1181_state_size),
    reinterpret_cast<void const*>(abi_addr_isp1181_state_save),
    reinterpret_cast<void const*>(abi_addr_isp1181_state_load),
};

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
