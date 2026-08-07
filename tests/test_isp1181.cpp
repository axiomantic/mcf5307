/* tests/test_isp1181.cpp - Unit test driver for ISP1181 CS3 peripheral bridge (CPU-15) */

#include <iostream>
#include <vector>
#include <cstdint>
#include <cstring>

#include "mcf5307.h"

static int g_irq_asserted = 0;
static std::vector<uint8_t> g_tx_buf;
static int g_tx_ep = -1;

static void isp_irq_cb(void* user, int asserted) {
    (void)user;
    g_irq_asserted = asserted;
}

static void isp_tx_cb(void* user, int endpoint, const uint8_t* data, size_t len) {
    (void)user;
    g_tx_ep = endpoint;
    g_tx_buf.assign(data, data + len);
}

int main() {
    std::cout << "[CPU-15] Testing ISP1181 CS3 Peripheral Bridge...\n";
    mcf5307_runtime_init();

    isp1181_ctx* ctx = isp1181_create(nullptr, isp_irq_cb, isp_tx_cb);
    if (!ctx) {
        std::cerr << "FAILED: isp1181_create returned null\n";
        return 1;
    }

    // 1. Read Chip ID
    isp1181_write(ctx, 1, 0x70); // Command port: Chip ID reg
    uint8_t chip_id = isp1181_read(ctx, 0); // Data port
    if (chip_id != 0x11) {
        std::cerr << "FAILED: Chip ID read 0x" << std::hex << (int)chip_id << " expected 0x11\n";
        isp1181_destroy(ctx);
        return 2;
    }

    // 2. Enable interrupt bit 0
    isp1181_write(ctx, 1, 0xB2); // Command port: Interrupt Enable
    isp1181_write(ctx, 0, 0x01); // Enable EP0 interrupt

    // 3. Receive host data to EP0
    uint8_t rx_data[] = { 0x12, 0x34, 0x56, 0x78 };
    isp1181_rx(ctx, 0, rx_data, sizeof(rx_data));

    if (g_irq_asserted != 1) {
        std::cerr << "FAILED: Expected IRQ asserted after RX\n";
        isp1181_destroy(ctx);
        return 3;
    }

    // Read back RX data from EP0 buffer
    isp1181_write(ctx, 1, 0x00); // Command port: EP0 buffer
    for (size_t i = 0; i < sizeof(rx_data); ++i) {
        uint8_t b = isp1181_read(ctx, 0);
        if (b != rx_data[i]) {
            std::cerr << "FAILED: EP0 RX byte " << i << " mismatch: got 0x" << std::hex << (int)b << "\n";
            isp1181_destroy(ctx);
            return 4;
        }
    }

    // 4. Test State Save & Load
    size_t sz = isp1181_state_size();
    if (sz == 0) {
        std::cerr << "FAILED: isp1181_state_size returned 0\n";
        isp1181_destroy(ctx);
        return 5;
    }

    std::vector<uint8_t> snap(sz, 0);
    isp1181_state_save(ctx, snap.data());

    isp1181_write(ctx, 1, 0xF4); // Soft reset
    isp1181_state_load(ctx, snap.data());

    isp1181_destroy(ctx);
    std::cout << "[CPU-15] PASSED: ISP1181 CS3 Peripheral Bridge verified.\n";
    return 0;
}
