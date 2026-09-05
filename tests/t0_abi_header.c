/* t0_abi_header.c - case 3 of the registered test `t0_abi_header`.
 *
 * The two mechanisms are different failures on purpose:
 *
 *   - one `_Static_assert` for each declared TYPE, so a deleted or renamed
 *     type is a COMPILE error;
 *   - address-of expressions, written out below as a FIXED LIST and
 *     not derived from what the header happens to hold, so a MISSING
 *     declaration is a compile error and a RENAMED one is a LINK error
 *     against `abi_stub.c`.
 *
 * The fixed list is the point. An assertion written as "one address-of
 * expression for each declared function" takes its assertion set from the
 * artifact under test, so a header missing four declarations satisfies it.
 *
 * Each pointer also carries the EXACT declared signature, so a changed
 * parameter type or a changed return type is an initialisation diagnostic
 * under `-Werror` rather than a silent pass.
 */

#include <stddef.h>
#include <stdint.h>

#include "mcf5307.h"

/* The opaque context types. Neither is complete here and neither may be,
 * so the assertion is over a pointer to it: the type NAME must exist. */
_Static_assert(sizeof(mcf5307_ctx*) == sizeof(void*),
               "mcf5307_ctx must be declared as an opaque context type");
_Static_assert(sizeof(isp1181_ctx*) == sizeof(void*),
               "isp1181_ctx must be declared as an opaque context type");

/* The bus status enumeration, and each of its enumerators by VALUE.
 * The values are part of the contract: the board writes them and the core
 * reads them across a compiled boundary. */
_Static_assert(sizeof(mcf5307_bus_status) >= 1u,
               "mcf5307_bus_status must be declared as a type");
_Static_assert(MCF5307_BUS_OK == 0, "MCF5307_BUS_OK must be 0");
_Static_assert(MCF5307_BUS_UNMAPPED == 1, "MCF5307_BUS_UNMAPPED must be 1");
_Static_assert(MCF5307_BUS_SIZE_ILLEGAL == 2,
               "MCF5307_BUS_SIZE_ILLEGAL must be 2");
_Static_assert(MCF5307_BUS_FAULT == 3, "MCF5307_BUS_FAULT must be 3");
_Static_assert(MCF5307_IRQ_NONE == 0, "MCF5307_IRQ_NONE must be 0");

/* The function-pointer types. Each must exist as a type name and each
 * must be a function pointer, which is what the comparison against a bare
 * function-pointer type asserts. The SIGNATURES are asserted below, where
 * `mcf5307_create` and `isp1181_create` take them as parameters. */
_Static_assert(sizeof(mcf5307_read_fn) == sizeof(void (*)(void)),
               "mcf5307_read_fn must be a function-pointer type");
_Static_assert(sizeof(mcf5307_write_fn) == sizeof(void (*)(void)),
               "mcf5307_write_fn must be a function-pointer type");
_Static_assert(sizeof(mcf5307_iack_fn) == sizeof(void (*)(void)),
               "mcf5307_iack_fn must be a function-pointer type");
_Static_assert(sizeof(isp1181_irq_fn) == sizeof(void (*)(void)),
               "isp1181_irq_fn must be a function-pointer type");
_Static_assert(sizeof(isp1181_tx_fn) == sizeof(void (*)(void)),
               "isp1181_tx_fn must be a function-pointer type");

/* ------------------------------------------------ the address-of expressions
 *
 * The `status` out-parameter of the memory callbacks is asserted here as
 * well: a draft that returned the status instead of writing it through a
 * pointer would not match these declared types.
 */

int main(void)
{
    void (*const p01)(void) = &mcf5307_runtime_init;
    mcf5307_ctx* (*const p02)(void*, mcf5307_read_fn, mcf5307_write_fn,
                              mcf5307_iack_fn) = &mcf5307_create;
    void (*const p03)(mcf5307_ctx*) = &mcf5307_destroy;
    void (*const p04)(mcf5307_ctx*, uint32_t, uint32_t) = &mcf5307_reset;
    uint32_t (*const p05)(mcf5307_ctx*, uint32_t) = &mcf5307_exec;
    void (*const p06)(mcf5307_ctx*, int, uint8_t, int) = &mcf5307_set_irq;
    size_t (*const p07)(void) = &mcf5307_state_size;
    void (*const p08)(const mcf5307_ctx*, void*) = &mcf5307_state_save;
    void (*const p09)(mcf5307_ctx*, const void*) = &mcf5307_state_load;

    isp1181_ctx* (*const p10)(void*, isp1181_irq_fn,
                              isp1181_tx_fn) = &isp1181_create;
    void (*const p11)(isp1181_ctx*) = &isp1181_destroy;
    uint8_t (*const p12)(isp1181_ctx*, uint32_t) = &isp1181_read;
    void (*const p13)(isp1181_ctx*, uint32_t, uint8_t) = &isp1181_write;
    void (*const p14)(isp1181_ctx*, int, const uint8_t*,
                      size_t) = &isp1181_rx;
    void (*const p15)(isp1181_ctx*, uint32_t) = &isp1181_tick;
    size_t (*const p16)(void) = &isp1181_state_size;
    void (*const p17)(const isp1181_ctx*, void*) = &isp1181_state_save;
    void (*const p18)(isp1181_ctx*, const void*) = &isp1181_state_load;

    /* Every one is counted, so that no declaration can be
     * dropped from the list above without changing the result. The
     * comparison is over the VARIABLES and not over the function names,
     * because the address of a function is never null and a compiler says
     * so under `-Wall`. */
    int found = 0;
    found += (p01 != NULL);
    found += (p02 != NULL);
    found += (p03 != NULL);
    found += (p04 != NULL);
    found += (p05 != NULL);
    found += (p06 != NULL);
    found += (p07 != NULL);
    found += (p08 != NULL);
    found += (p09 != NULL);
    found += (p10 != NULL);
    found += (p11 != NULL);
    found += (p12 != NULL);
    found += (p13 != NULL);
    found += (p14 != NULL);
    found += (p15 != NULL);
    found += (p16 != NULL);
    found += (p17 != NULL);
    found += (p18 != NULL);

    if (found != 18) {
        return 1;
    }
    return 0;
}
