/* tests/abi_smoke.cpp - the application binary interface smoke test.
 *
 * Each assertion below can fail on its own.
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
 * (3) The backend macro values, not their names. The two
 *     `MCF5307_ISP1181_BACKEND_*` macros are written out in
 *     `include/mcf5307.h` and again, as Nim constants, in
 *     `src/isp1181/stub.nim`. Every other mechanism here compares symbol
 *     names: step 4a, the committed list and the address set above would all
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
 * (4) The concurrent first call. Several threads enter
 *     `mcf5307_runtime_init` on a cold latch behind a start gate, and every
 *     one of them must return 1. A latch built on a plain boolean lets two
 *     threads run the initializer, which is the failure this shape catches.
 *
 *     It runs before the twice-call: run it second and the latch is already
 *     closed, so every racer takes the early return and the case is vacuous.
 *
 * The address-taking is the only way to make a rename a fail. The C++
 * translation unit reads no field of any function pointer, and the linker
 * is what turns a missing symbol into a build error. The test is C++17
 * clean, links against the `mcf5307` static library, and exits 0 on
 * success.
 */

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <type_traits>
#include <thread>
#include <vector>

#include "mcf5307.h"

namespace {

/* The address of every function the header declares and the library defines.
 * Taking the address is the assertion: a renamed or dropped definition fails
 * the link, and the test does not need to read the value to fail.
 *
 * The address set is the defined set and not the published set. It is
 * generated from what step 4a measured, so a published name with no
 * definition cannot make this test unlinkable. The whole published surface is
 * asserted by cases 3 and 4 of `t0_abi_header`, which link it against
 * `tests/abi_stub.c`. A name nothing defines cannot be renamed and cannot be
 * dropped, so asserting it here buys no coverage those cases do not give.
 *
 * Every entry has the exact function-pointer type the header declares, so
 * the address-of expression is well typed and the compiler does not warn.
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

/* The same list again, as one array that `main` reads in full at run time.
 *
 * Where the `volatile` sits is the whole mechanism, and putting it one
 * position to the left silently disarms this test. `void const* const
 * volatile` qualifies the pointer object: reading it is an observable side
 * effect the compiler is not allowed to skip, so the array must exist in
 * memory, so its initialiser's relocations must exist, so the linker must
 * resolve every name they carry. `volatile void const* const` - one token
 * earlier - qualifies the pointee instead and leaves the array an ordinary
 * constant that the compiler folds into the comparison and never emits at
 * all. The `static_assert` below is what keeps the two apart, because
 * nothing else does: both spellings compile, both look deliberate, and only
 * one of them anchors anything.
 *
 * The read is in `main` rather than an attribute. `__attribute__((used))`
 * and `retain` would also hold the symbols against a dead-stripping linker,
 * but nothing in the build can check them: an attribute a toolchain does not
 * honour is not an error, it is silence, and silence here is a test that
 * keeps passing while it anchors nothing. A volatile read is ordinary
 * language semantics rather than a request the toolchain may decline, its
 * one failure mode is the qualifier's position, and the `static_assert`
 * above fails the build over that. Prefer the mechanism whose breakage is
 * loud. */
#define MCF5307_ABI_FN(name)                                                   \
    reinterpret_cast<void const*>(abi_addr_##name),

void const* const volatile abi_addr_all[] = {
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

static_assert(
    std::is_volatile<std::remove_extent<decltype(abi_addr_all)>::type>::value,
    "abi_addr_all's ELEMENTS must be volatile-qualified. If this fires, the "
    "qualifier has migrated onto the pointee and the array is a plain "
    "constant again: the compiler may fold the reads in main, emit no array, "
    "and let the linker drop every symbol this test exists to require.");
/* Enough threads that the losers are real losers and not threads that
 * started after the winner had already finished. */
constexpr int kRacers = 8;

/* True when every racer returned from `mcf5307_runtime_init`. A thread that
 * hangs never joins and the test times out instead of answering. */
bool all_racers_returned() {
    std::atomic<bool> gate{false};
    std::atomic<int> returned{0};

    std::vector<std::thread> racers;
    racers.reserve(kRacers);
    for (int i = 0; i < kRacers; ++i) {
        racers.emplace_back([&gate, &returned]() {
            /* The spin is the point: a thread that called straight away would
             * be serialised by its own creation cost, and the latch would be
             * closed before the next thread reached it. */
            while (!gate.load(std::memory_order_acquire)) {
            }
            /* The status is consumed, not discarded: the entry point is
             * MCF5307_MUST_CHECK. No racer stalls the latch, so a healthy
             * runtime answers 1 to every one of them. */
            if (mcf5307_runtime_init() == 1) {
                returned.fetch_add(1, std::memory_order_relaxed);
            }
        });
    }

    gate.store(true, std::memory_order_release);
    for (std::thread& t : racers) t.join();

    return returned.load(std::memory_order_relaxed) == kRacers;
}

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
 * 0x00 from the stub, which keeps nothing, and 0xA5 from the full model, and
 * -1 when the delivery itself disagreed with the selected backend.
 *
 * `expect_accepted` is the status the backend owes: the full model takes the
 * packet and answers 1, the stub refuses every packet and answers 0. That
 * status is a discriminator in its own right, so it is asserted rather than
 * discarded - and a delivery that went the wrong way would make the peek
 * below answer for a reason this test is not asking about. */
int peek_endpoint0(isp1181_ctx* h, int expect_accepted) {
    uint8_t packet[4] = {kDelivered, 0x5Au, 0x3Cu, 0xC3u};
    if (isp1181_rx(h, 0, packet, sizeof packet) != expect_accepted) return -1;
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
    if (h == nullptr) return 10;

    int rc = 0;
    if (isp1181_set_backend(h, MCF5307_ISP1181_BACKEND_FULL_MODEL) != 1) {
        rc = 11; /* the header's full-model number is not one the model takes */
    } else if (peek_endpoint0(h, 1) != kDelivered) {
        rc = 12; /* it was taken, but it did not select the full model */
    } else if (isp1181_set_backend(h, MCF5307_ISP1181_BACKEND_STUB) != 1) {
        rc = 13; /* the header's stub number is not one the model takes */
    } else if (peek_endpoint0(h, 0) != 0x00) {
        rc = 14; /* it was taken, but it did not select the stub */
    } else if (isp1181_set_backend(h, kUnnamedBackend) != 0) {
        rc = 15; /* an unnamed number was accepted, so range is not checked */
    }

    isp1181_destroy(h);
    return rc;
}

} /* namespace */

int main() {
    /* The concurrent first call, before any other call closes the latch. */
    if (!all_racers_returned()) return 4;

    /* The twice-call. `mcf5307_runtime_init()` is documented as idempotent.
     * A second call that reaches unmapped memory, that re-enters a partial
     * initialiser, or that panics is a regression in the runtime itself.
     *
     * The returned status is read, and reading it is what makes this the
     * positive control for `t_runtime_latch`. That suite drives the status to
     * 0 on a latch it stalls deliberately; a status call that answered 0 for
     * every reason would satisfy it just as well. This is the only place a
     * healthy runtime's answer is asserted, and it is asserted through the
     * published C entry point rather than against the Nim procedure behind
     * it. */
    if (mcf5307_runtime_init() != 1) {
        return 2;
    }
    if (mcf5307_runtime_init() != 1) {
        return 3;
    }

    /* The backend macros. This runs after the runtime is up, because it is
     * the first thing here that calls into Nim code holding state. */
    if (const int rc = check_backend_macros(); rc != 0) return rc;

    /* This loop is the anchor, not a check. The comparison cannot fail -
     * every element is the address of a function - and the return value is
     * not what this loop is for. It is here so that every element is read,
     * because a volatile read is what the compiler must keep and what the
     * linker must therefore resolve. The failure this file exists to
     * produce happens earlier than any of this: a name the library no
     * longer defines is an unresolved symbol and there is no executable to
     * run. */
    for (void const* const address : abi_addr_all) {
        if (address == nullptr) {
            return 1;
        }
    }

    return 0;
}
