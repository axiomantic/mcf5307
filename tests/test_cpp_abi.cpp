/* tests/test_cpp_abi.cpp - C++ ABI verification test (CPU-3)
 *
 * Verifies that include/mcf5307.h and ${NIMCACHE_DIR}/mcf5307_nim.h compile
 * cleanly together in a C++ translation unit, and that no exceptions propagate
 * across the C ABI boundary.
 */

#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <type_traits>
#include <exception>
#include <stdexcept>
#include <iostream>

#include "mcf5307.h"

namespace NimHeader {
#include "mcf5307_nim.h"
}

// ------------------------------------------------------------- Static Assertions

// Verify opaque context types
static_assert(sizeof(mcf5307_ctx*) == sizeof(void*), "mcf5307_ctx pointer size");
static_assert(sizeof(isp1181_ctx*) == sizeof(void*), "isp1181_ctx pointer size");

// Verify enum values
static_assert(MCF5307_BUS_OK == 0, "MCF5307_BUS_OK");
static_assert(MCF5307_BUS_UNMAPPED == 1, "MCF5307_BUS_UNMAPPED");
static_assert(MCF5307_BUS_SIZE_ILLEGAL == 2, "MCF5307_BUS_SIZE_ILLEGAL");
static_assert(MCF5307_BUS_FAULT == 3, "MCF5307_BUS_FAULT");

// Verify callback function pointers are function pointer types
static_assert(std::is_pointer<mcf5307_read_fn>::value, "read_fn");
static_assert(std::is_pointer<mcf5307_write_fn>::value, "write_fn");
static_assert(std::is_pointer<mcf5307_iack_fn>::value, "iack_fn");
static_assert(std::is_pointer<isp1181_irq_fn>::value, "irq_fn");
static_assert(std::is_pointer<isp1181_tx_fn>::value, "tx_fn");

// ------------------------------------------------------------- Dummy Callbacks

static uint32_t g_dummy_read_count = 0;
static uint32_t g_dummy_write_count = 0;

extern "C" uint32_t dummy_read_fn(void* user, uint32_t addr, int size, mcf5307_bus_status* status) noexcept {
    (void)user; (void)addr; (void)size;
    g_dummy_read_count++;
    if (status) *status = MCF5307_BUS_OK;
    return 0x12345678u;
}

extern "C" void dummy_write_fn(void* user, uint32_t addr, int size, uint32_t val, mcf5307_bus_status* status) noexcept {
    (void)user; (void)addr; (void)size; (void)val;
    g_dummy_write_count++;
    if (status) *status = MCF5307_BUS_OK;
}

extern "C" void dummy_iack_fn(void* user, int level, uint8_t vector) noexcept {
    (void)user; (void)level; (void)vector;
}

// Helper template to test that a lambda does not throw any exception
template <typename F>
bool test_no_exception(F&& f) noexcept {
    try {
        f();
        return true;
    } catch (...) {
        return false;
    }
}

int main() {
    std::cout << "[CPU-3] Testing C++ ABI compatibility and exception safety...\n";

    // Test 1: runtime_init
    bool ok1 = test_no_exception([]() {
        mcf5307_runtime_init();
    });
    if (!ok1) {
        std::cerr << "FAILED: mcf5307_runtime_init threw exception\n";
        return 1;
    }

    // Test 2: state sizes
    bool ok2 = test_no_exception([]() {
        size_t cpu_sz = mcf5307_state_size();
        size_t usb_sz = isp1181_state_size();
        (void)cpu_sz; (void)usb_sz;
    });
    if (!ok2) {
        std::cerr << "FAILED: state_size calls threw exception\n";
        return 2;
    }

    // Test 3: Context creation, execution, and destruction
    bool ok3 = test_no_exception([]() {
        mcf5307_ctx* ctx = mcf5307_create(nullptr, dummy_read_fn, dummy_write_fn, dummy_iack_fn);
        if (ctx != nullptr) {
            mcf5307_reset(ctx, 0x10000, 0x00004);
            uint32_t ran = mcf5307_exec(ctx, 10);
            (void)ran;
            mcf5307_set_irq(ctx, 4, 64, 0);
            mcf5307_destroy(ctx);
        }
    });
    if (!ok3) {
        std::cerr << "FAILED: mcf5307 lifecycle operations threw exception\n";
        return 3;
    }

    // Test 4: USB device context lifecycle
    bool ok4 = test_no_exception([]() {
        isp1181_irq_fn irq_cb = nullptr;
        isp1181_tx_fn tx_cb = nullptr;
        isp1181_ctx* uctx = isp1181_create(nullptr, irq_cb, tx_cb);
        if (uctx != nullptr) {
            isp1181_write(uctx, 0x00, 0xFF);
            (void)isp1181_read(uctx, 0x00);
            isp1181_tick(uctx, 1);
            isp1181_destroy(uctx);
        }
    });
    if (!ok4) {
        std::cerr << "FAILED: isp1181 lifecycle operations threw exception\n";
        return 4;
    }

    std::cout << "[CPU-3] PASSED: C++ ABI verification complete.\n";
    return 0;
}
