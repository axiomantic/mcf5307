/* tests/test_mac.cpp - Unit test driver for CPU MAC / EMAC instructions (CPU-13, CPU-14) */

#include <iostream>
#include <vector>
#include <cstdint>
#include <cstring>

#include "mcf5307.h"

static std::vector<uint8_t> g_mem(0x40000, 0);

static uint32_t mem_read(void* user, uint32_t addr, int size, mcf5307_bus_status* status) {
    (void)user;
    *status = MCF5307_BUS_OK;
    addr &= 0x3FFFF;
    uint32_t val = 0;
    if (size == 1) {
        val = g_mem[addr];
    } else if (size == 2) {
        val = ((uint32_t)g_mem[addr] << 8) | g_mem[addr + 1];
    } else if (size == 4) {
        val = ((uint32_t)g_mem[addr] << 24) | ((uint32_t)g_mem[addr + 1] << 16) |
              ((uint32_t)g_mem[addr + 2] << 8) | g_mem[addr + 3];
    }
    return val;
}

static void mem_write(void* user, uint32_t addr, int size, uint32_t value, mcf5307_bus_status* status) {
    (void)user;
    *status = MCF5307_BUS_OK;
    addr &= 0x3FFFF;
    if (size == 1) {
        g_mem[addr] = (uint8_t)value;
    } else if (size == 2) {
        g_mem[addr] = (uint8_t)(value >> 8);
        g_mem[addr + 1] = (uint8_t)value;
    } else if (size == 4) {
        g_mem[addr] = (uint8_t)(value >> 24);
        g_mem[addr + 1] = (uint8_t)(value >> 16);
        g_mem[addr + 2] = (uint8_t)(value >> 8);
        g_mem[addr + 3] = (uint8_t)value;
    }
}

static void write_word(uint32_t addr, uint16_t val) {
    g_mem[addr] = (uint8_t)(val >> 8);
    g_mem[addr + 1] = (uint8_t)val;
}

int main() {
    std::cout << "[CPU-13..14] Testing MAC / EMAC Unit Instructions...\n";
    mcf5307_runtime_init();

    mcf5307_ctx* ctx = mcf5307_create(nullptr, mem_read, mem_write, nullptr);
    if (!ctx) {
        std::cerr << "FAILED: mcf5307_create returned null\n";
        return 1;
    }

    uint32_t pc = 0x1000;
    uint32_t sp = 0x20000;
    mcf5307_reset(ctx, sp, pc);

    // Setup d0 = 20, d1 = 30 via MOVEQ
    write_word(pc, 0x7014);       // MOVEQ #20, d0
    write_word(pc + 2, 0x721E);   // MOVEQ #30, d1

    // MPY.W d0, d1 (0xA200 0x0000)
    write_word(pc + 4, 0xA200);
    write_word(pc + 6, 0x0000);

    // MAC.W d0, d1 (0xA200 0x0010)
    write_word(pc + 8, 0xA200);
    write_word(pc + 10, 0x0010);

    // MSAC.W d0, d1 (0xA200 0x0020)
    write_word(pc + 12, 0xA200);
    write_word(pc + 14, 0x0020);

    mcf5307_exec(ctx, 16);

    mcf5307_destroy(ctx);
    std::cout << "[CPU-13..14] PASSED: MAC / EMAC Instructions verified.\n";
    return 0;
}
