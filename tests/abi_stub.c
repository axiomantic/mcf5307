/* abi_stub.c - one definition, with an empty body, of every function
 * `include/mcf5307.h` declares.
 *
 * WHY IT EXISTS. Cases 3 and 4 of `t0_abi_header` COMPILE AND LINK, and
 * linking is what makes a RENAMED declaration a link error rather than
 * nothing at all. `-fsyntax-only` never links, so the two header compiles
 * alone cannot catch a rename. The real implementation cannot supply the
 * definitions either: it is written by a later task that depends on this
 * contract, so a check that waited for it could never pass at this task's
 * completion. This stub breaks that circle.
 *
 * NO LATER TASK EDITS THIS FILE. The real implementation supersedes it for
 * every later test; this translation unit stays exactly as strict and
 * exactly as empty as it is here, because its only job is to make the link
 * of the eighteen names succeed or fail.
 *
 * NOTHING HERE EMULATES ANYTHING. Every body is empty and every return is a
 * fixed benign value. A test that needs behaviour links the real library.
 */

#include <stddef.h>
#include <stdint.h>

#include "mcf5307.h"

/* ---------------------------------------------------------------- CPU core */

void mcf5307_runtime_init(void)
{
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

/* ------------------------------------------------ ISP1181 USB device model */

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
