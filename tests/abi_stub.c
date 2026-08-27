/* abi_stub.c - one definition, with an empty body and EXTERNAL LINKAGE, of
 * every function `include/mcf5307.h` declares.
 *
 * WHY IT EXISTS. Cases 3 and 4 of `t0_abi_header` COMPILE AND LINK, and
 * linking is what makes a RENAMED declaration a link error rather than
 * nothing at all. `-fsyntax-only` never links, so the two header compiles
 * alone cannot catch a rename. This stub supplies the definitions the real
 * implementation does not yet carry.
 *
 * `cmake/Nim.cmake` step 4a, part three COMPILES this file, reads the
 * symbols the object defines with `nm`, and compares that set against the
 * published set it parses out of the contract with a C compiler. NO COUNT IS
 * WRITTEN HERE OR THERE. A count is a third number beside the header and the
 * code, and it falls behind them both.
 *
 * WHAT NO LATER TASK MAY DO TO THIS FILE, AND WHAT THE FREEZE NEVER MEANT.
 * The freeze is on BEHAVIOUR and it still holds: every body stays empty,
 * every return stays a fixed benign value, and nothing here emulates
 * anything. A test that needs behaviour links the real library. THE SET OF
 * DEFINITIONS IS NOT FROZEN and never could be, because it is the contract's
 * own published set: it moves when the contract moves, and a file forbidden
 * to move with it is a file whose opening sentence goes stale in silence.
 * The gate is what makes that movement mechanical rather than remembered.
 *
 * A HELPER WITH INTERNAL LINKAGE IS ALLOWED AND IS NOT MEASURED. The gate
 * compares EXTERNAL definitions, because an external definition is what the
 * link of `t0_abi_header` resolves against. A published name defined `static`
 * here would resolve nothing there, so the gate refuses that and says nothing
 * about a `static` name the contract never declared.
 *
 * `tests/abi_smoke.cpp` does take the address of EVERY published name, through
 * `tests/abi_smoke_symbols.inc`, and step 4a holds that list against the
 * contract in both directions. That gate is what keeps the word `every` true,
 * and it is why no number is written beside it.
 */

#include <stddef.h>
#include <stdint.h>

#include "mcf5307.h"

/* The runtime bridge. It returns 0, which the contract reads as "the runtime
 * is NOT initialised". That is the fixed benign value here for the same reason
 * `mcf5307_set_reg` returns 0 below: of the two answers it is the one that
 * claims less, and a caller that believed a stub had brought a runtime up
 * would proceed on the strength of it. */
int mcf5307_runtime_init(void)
{
    return 0;
}

mcf5307_ctx* mcf5307_create(void* user,
                            mcf5307_read_fn rd,
                            mcf5307_write_fn wr,
                            mcf5307_iack_fn iack)
{
    (void)user;
    (void)rd;
    (void)wr;
    (void)iack;
    return NULL;
}

void mcf5307_destroy(mcf5307_ctx* ctx)
{
    (void)ctx;
}

void mcf5307_reset(mcf5307_ctx* ctx, uint32_t initial_sp, uint32_t initial_pc)
{
    (void)ctx;
    (void)initial_sp;
    (void)initial_pc;
}

uint32_t mcf5307_exec(mcf5307_ctx* ctx, uint32_t max_cycles)
{
    (void)ctx;
    (void)max_cycles;
    return 0u;
}

/* The register bridge. `mcf5307_set_reg` returns 0, which the
 * contract reads as "the write did not happen", and `mcf5307_get_reg` returns
 * 0. Both are the fixed benign value of a stub and neither is a register. */
int mcf5307_set_reg(mcf5307_ctx* ctx, int index, uint32_t value)
{
    (void)ctx;
    (void)index;
    (void)value;
    return 0;
}

uint32_t mcf5307_get_reg(const mcf5307_ctx* ctx, int index)
{
    (void)ctx;
    (void)index;
    return 0u;
}

/* The run state. Both return 0, which the contract reads as "not
 * halted" and "not faulted" - the answer it also gives for a nil context. */
int mcf5307_halted(const mcf5307_ctx* ctx)
{
    (void)ctx;
    return 0;
}

int mcf5307_faulted(const mcf5307_ctx* ctx)
{
    (void)ctx;
    return 0;
}

void mcf5307_set_irq(mcf5307_ctx* ctx, int level, uint8_t vector,
                     int autovector)
{
    (void)ctx;
    (void)level;
    (void)vector;
    (void)autovector;
}

size_t mcf5307_state_size(void)
{
    return (size_t)0;
}

void mcf5307_state_save(const mcf5307_ctx* ctx, void* dst)
{
    (void)ctx;
    (void)dst;
}

void mcf5307_state_load(mcf5307_ctx* ctx, const void* src)
{
    (void)ctx;
    (void)src;
}

isp1181_ctx* isp1181_create(void* user, isp1181_irq_fn irq, isp1181_tx_fn tx)
{
    (void)user;
    (void)irq;
    (void)tx;
    return NULL;
}

void isp1181_destroy(isp1181_ctx* ctx)
{
    (void)ctx;
}

uint8_t isp1181_read(isp1181_ctx* ctx, uint32_t addr)
{
    (void)ctx;
    (void)addr;
    return (uint8_t)0;
}

void isp1181_write(isp1181_ctx* ctx, uint32_t addr, uint8_t value)
{
    (void)ctx;
    (void)addr;
    (void)value;
}

void isp1181_rx(isp1181_ctx* ctx, int endpoint, const uint8_t* data,
                size_t len)
{
    (void)ctx;
    (void)endpoint;
    (void)data;
    (void)len;
}

int isp1181_setup(isp1181_ctx* ctx, const uint8_t* data, size_t len)
{
    (void)ctx;
    (void)data;
    (void)len;
    return 0;
}

int isp1181_in_token(isp1181_ctx* ctx, int endpoint)
{
    (void)ctx;
    (void)endpoint;
    return 0;
}

int isp1181_set_backend(isp1181_ctx* ctx, int backend)
{
    (void)ctx;
    (void)backend;
    return 0;
}

void isp1181_tick(isp1181_ctx* ctx, uint32_t sof_frames)
{
    (void)ctx;
    (void)sof_frames;
}

size_t isp1181_state_size(void)
{
    return (size_t)0;
}

void isp1181_state_save(const isp1181_ctx* ctx, void* dst)
{
    (void)ctx;
    (void)dst;
}

void isp1181_state_load(isp1181_ctx* ctx, const void* src)
{
    (void)ctx;
    (void)src;
}
