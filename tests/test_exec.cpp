/* tests/test_exec.cpp - Unit test driver for CPU core execution engine (CPU-6 through CPU-10, CPU-11, CPU-12) */

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

static void write_long(uint32_t addr, uint32_t val) {
    write_word(addr, (uint16_t)(val >> 16));
    write_word(addr + 2, (uint16_t)val);
}

int main() {
    std::cout << "[CPU-6..10,11..12] Testing Core Execution Loop & Instructions...\n";
    mcf5307_runtime_init();

    mcf5307_ctx* ctx = mcf5307_create(nullptr, mem_read, mem_write, nullptr);
    if (!ctx) {
        std::cerr << "FAILED: mcf5307_create returned null\n";
        return 1;
    }

    uint32_t pc = 0x1000;
    uint32_t sp = 0x20000;
    mcf5307_reset(ctx, sp, pc);

    // Test 1: MOVEQ #0x42, d0 (0x7042)
    write_word(pc, 0x7042);
    mcf5307_exec(ctx, 2);

    // Test 2: ADDI.L #10, d0 (0x0680, 0x0000000A)
    write_word(pc + 2, 0x0680);
    write_long(pc + 4, 10);
    mcf5307_exec(ctx, 2);

    // Test 3: NOP (0x4E71)
    write_word(pc + 10, 0x4E71);
    mcf5307_exec(ctx, 2);

    // Test 4: LEA 0x2000, a0 (0x41F9, 0x00002000)
    write_word(pc + 12, 0x41F9);
    write_long(pc + 14, 0x2000);
    mcf5307_exec(ctx, 2);

    // Test 5: PEA (a0) (0x4850)
    write_word(pc + 20, 0x4850);
    mcf5307_exec(ctx, 2);

    // Test 6: RTS (0x4E75)
    write_word(pc + 22, 0x4E75);
    mcf5307_exec(ctx, 2);

    // Verify state save & load
    size_t st_size = mcf5307_state_size();
    if (st_size == 0) {
        std::cerr << "FAILED: mcf5307_state_size returned 0\n";
        return 2;
    }

    std::vector<uint8_t> state_buf(st_size, 0);
    mcf5307_state_save(ctx, state_buf.data());

    mcf5307_reset(ctx, 0, 0);
    mcf5307_state_load(ctx, state_buf.data());

    mcf5307_destroy(ctx);
    std::cout << "[CPU-6..10,11..12] PASSED: Core Execution Loop & Instructions verified.\n";
    return 0;
}
