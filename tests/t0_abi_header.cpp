/* t0_abi_header.cpp - case 4 of the registered test `t0_abi_header`.
 *
 * The C++ half of the same assertion. It makes the same address-of
 * expressions and the same per-type assertions THROUGH `extern "C"`, which
 * `include/mcf5407.h` supplies for a C++ translation unit. That linkage is
 * what makes this file link against `abi_stub.c`, a C translation unit, and
 * what makes a rename a link error here too rather than a mangled symbol
 * nobody looks for.
 *
 * The C++ build is what makes the forbidden list testable. A C++ reference
 * parameter, a namespace, a template, an overload, a C++ object or a
 * reference in the header is either a syntax error in the C build of case 3
 * or a diagnostic under `-Wall -Wextra -pedantic -Werror`.
 * Nothing here catches an exception, because nothing may throw one across
 * this boundary in either direction.
 *
 * Each pointer is `volatile`. A read of a volatile object must happen, which
 * is what forces the initialiser to be materialised and the relocation
 * against the named function to survive into the link. Without it the
 * comparisons below are `&function != NULL`, which an optimising compiler
 * folds to true: measured at `-O2`, all eighteen address-of expressions were
 * eliminated and the executable linked with no reference to any of them, so a
 * renamed declaration -- the fault cases 3 and 4 exist to catch -- linked
 * clean. The check then held only at `-O0` and reported a pass at every other
 * optimisation level.
 */

#include <cstddef>
#include <cstdint>

#include "mcf5407.h"

static_assert(sizeof(mcf5407_ctx*) == sizeof(void*),
              "mcf5407_ctx must be declared as an opaque context type");
static_assert(sizeof(isp1181_ctx*) == sizeof(void*),
              "isp1181_ctx must be declared as an opaque context type");

static_assert(sizeof(mcf5407_bus_status) >= 1u,
              "mcf5407_bus_status must be declared as a type");
static_assert(MCF5407_BUS_OK == 0, "MCF5407_BUS_OK must be 0");
static_assert(MCF5407_BUS_UNMAPPED == 1, "MCF5407_BUS_UNMAPPED must be 1");
static_assert(MCF5407_BUS_SIZE_ILLEGAL == 2,
              "MCF5407_BUS_SIZE_ILLEGAL must be 2");
static_assert(MCF5407_BUS_FAULT == 3, "MCF5407_BUS_FAULT must be 3");

static_assert(MCF5407_IRQ_NONE == 0, "MCF5407_IRQ_NONE must be 0");

static_assert(sizeof(mcf5407_read_fn) == sizeof(void (*)()),
              "mcf5407_read_fn must be a function-pointer type");
static_assert(sizeof(mcf5407_write_fn) == sizeof(void (*)()),
              "mcf5407_write_fn must be a function-pointer type");
static_assert(sizeof(mcf5407_iack_fn) == sizeof(void (*)()),
              "mcf5407_iack_fn must be a function-pointer type");
static_assert(sizeof(isp1181_irq_fn) == sizeof(void (*)()),
              "isp1181_irq_fn must be a function-pointer type");
static_assert(sizeof(isp1181_tx_fn) == sizeof(void (*)()),
              "isp1181_tx_fn must be a function-pointer type");

/* ------------------------------------------------ the address-of expressions
 *
 * Each pointer variable carries `extern "C"` linkage through the type it is
 * declared with, because the header declares every one of these functions
 * inside its `extern "C"` block.
 */

int main()
{
    int (*const volatile p01)() = &mcf5407_runtime_init;
    mcf5407_ctx* (*const volatile p02)(void*, mcf5407_read_fn, mcf5407_write_fn,
                              mcf5407_iack_fn) = &mcf5407_create;
    void (*const volatile p03)(mcf5407_ctx*) = &mcf5407_destroy;
    void (*const volatile p04)(mcf5407_ctx*, uint32_t, uint32_t) = &mcf5407_reset;
    uint32_t (*const volatile p05)(mcf5407_ctx*, uint32_t) = &mcf5407_exec;
    void (*const volatile p06)(mcf5407_ctx*, int, uint8_t, int) = &mcf5407_set_irq;
    size_t (*const volatile p07)() = &mcf5407_state_size;
    void (*const volatile p08)(const mcf5407_ctx*, void*) = &mcf5407_state_save;
    void (*const volatile p09)(mcf5407_ctx*, const void*) = &mcf5407_state_load;

    isp1181_ctx* (*const volatile p10)(void*, isp1181_irq_fn,
                              isp1181_tx_fn) = &isp1181_create;
    void (*const volatile p11)(isp1181_ctx*) = &isp1181_destroy;
    uint8_t (*const volatile p12)(isp1181_ctx*, uint32_t) = &isp1181_read;
    void (*const volatile p13)(isp1181_ctx*, uint32_t, uint8_t) = &isp1181_write;
    int (*const volatile p14)(isp1181_ctx*, int, const uint8_t*,
                     size_t) = &isp1181_rx;
    void (*const volatile p15)(isp1181_ctx*, uint32_t) = &isp1181_tick;
    size_t (*const volatile p16)() = &isp1181_state_size;
    void (*const volatile p17)(const isp1181_ctx*, void*) = &isp1181_state_save;
    void (*const volatile p18)(isp1181_ctx*, const void*) = &isp1181_state_load;

    int found = 0;
    found += (p01 != nullptr);
    found += (p02 != nullptr);
    found += (p03 != nullptr);
    found += (p04 != nullptr);
    found += (p05 != nullptr);
    found += (p06 != nullptr);
    found += (p07 != nullptr);
    found += (p08 != nullptr);
    found += (p09 != nullptr);
    found += (p10 != nullptr);
    found += (p11 != nullptr);
    found += (p12 != nullptr);
    found += (p13 != nullptr);
    found += (p14 != nullptr);
    found += (p15 != nullptr);
    found += (p16 != nullptr);
    found += (p17 != nullptr);
    found += (p18 != nullptr);

    if (found != 18) {
        return 1;
    }
    return 0;
}
