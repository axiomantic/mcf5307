/* tests/abi_smoke.cpp - the application binary interface smoke test.
 *
 * Three assertions, and each one can fail.
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
 * (3) The backend macro VALUES, not their names. The two
 *     `MCF5307_ISP1181_BACKEND_*` macros are written out in
 *     `include/mcf5307.h` and again, as Nim constants, in
 *     `src/isp1181/stub.nim`. Every other mechanism here compares symbol
 *     NAMES: step 4a, the committed list and the address set above would all
 *     stay green if one side renumbered. `tests/t_isp1181_stub.nim` pins the
 *     numbers on the Nim side only, so it would stay green too, and a C
 *     caller passing `MCF5307_ISP1181_BACKEND_FULL_MODEL` would then be
 *     refused - or worse, silently handed the stub.
 *
 *     The assertion is behavioural rather than a returned 1, because an
 *     accepted call proves only that the number was in range. Under the full
 *     model a byte delivered to endpoint 0 reads back through the peek
 *     command; under the stub every read answers 0x00. Each macro is used to
 *     select, and the read that follows says which device actually answered.
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

static_assert(
    std::is_volatile<std::remove_extent<decltype(abi_addr_all)>::type>::value,
    "abi_addr_all's ELEMENTS must be volatile-qualified. If this fires, the "
    "qualifier has migrated onto the pointee and the array is a plain "
    "constant again: the compiler may fold the reads in main, emit no array, "
    "and let the linker drop every symbol this test exists to require.");

/* The CS3 window's two ports, and the command bytes the peek needs. These are
 * the same numbers `tests/t_isp1181_stub.nim` drives; this test exists to say
 * the C header's macros reach the same device that suite reaches. */
constexpr uint32_t kDataPort = 0x13000000u;
constexpr uint32_t kCommandPort = 0x13000010u;
constexpr uint8_t kEndpointConfig0 = 0x20u;
constexpr uint8_t kPeekByte = 0xD2u;
constexpr uint8_t kDelivered = 0xA5u;

/* A value neither macro names. The refusal case needs one, and it must not
 * become a third backend by accident. */
constexpr int kUnnamedBackend = 7;

void isp_irq(void*, int) {}
void isp_tx(void*, int, const uint8_t*, size_t) {}

/* Delivers one packet to endpoint 0 and reads the first byte back. Answers
 * 0x00 from the stub, which keeps nothing, and 0xA5 from the full model. */
uint8_t peek_endpoint0(isp1181_ctx* h) {
    uint8_t packet[4] = {kDelivered, 0x5Au, 0x3Cu, 0xC3u};
    isp1181_rx(h, 0, packet, sizeof packet);
    isp1181_write(h, kCommandPort, kEndpointConfig0);
    isp1181_write(h, kDataPort, 0x00u);
    isp1181_write(h, kCommandPort, kPeekByte);
    return isp1181_read(h, kDataPort);
}

/* Non-zero on the first failure. Each return value is distinct so a red run
 * names the case through the exit status alone. */
int check_backend_macros() {
    static_assert(MCF5307_ISP1181_BACKEND_STUB !=
                      MCF5307_ISP1181_BACKEND_FULL_MODEL,
                  "abi_smoke: the two backend macros carry the same value, so "
                  "neither selects anything.");

    isp1181_ctx* h = isp1181_create(nullptr, &isp_irq, &isp_tx);
    if (h == nullptr) return 2;

    int rc = 0;
    if (isp1181_set_backend(h, MCF5307_ISP1181_BACKEND_FULL_MODEL) != 1) {
        rc = 3; /* the header's full-model number is not one the model takes */
    } else if (peek_endpoint0(h) != kDelivered) {
        rc = 4; /* it was taken, but it did not select the full model */
    } else if (isp1181_set_backend(h, MCF5307_ISP1181_BACKEND_STUB) != 1) {
        rc = 5; /* the header's stub number is not one the model takes */
    } else if (peek_endpoint0(h) != 0x00u) {
        rc = 6; /* it was taken, but it did not select the stub */
    } else if (isp1181_set_backend(h, kUnnamedBackend) != 0) {
        rc = 7; /* an unnamed number was accepted, so range is not checked */
    }

    isp1181_destroy(h);
    return rc;
}

} /* namespace */

int main() {
    /* The twice-call. `mcf5307_runtime_init()` is documented as idempotent.
     * A second call that reaches unmapped memory, that re-enters a partial
     * initialiser, or that panics is a regression in the runtime itself.
     * The assertion is the return: the test reaches the end of `main`
     * only if both calls returned. */
    mcf5307_runtime_init();
    mcf5307_runtime_init();

    /* The backend macros. This runs after the runtime is up, because it is
     * the first thing here that calls into Nim code holding state. */
    if (const int rc = check_backend_macros(); rc != 0) return rc;

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
