/* tests/test_registers.cpp - Test driver for CPU-5 register set */

#include <iostream>

#include "mcf5307.h"

extern "C" {
    int mcf5307_test_registers_eval(void);
}

int main() {
    std::cout << "[CPU-5] Testing register set (d0..d7, a0..a7, pc, sr, sp, vbr, mbar, rambar0, rambar1, cacr, acr0, acr1)...\n";
    mcf5307_runtime_init();

    int res = mcf5307_test_registers_eval();
    if (res != 0) {
        std::cerr << "FAILED: mcf5307_test_registers_eval returned error code " << res << "\n";
        return res;
    }

    std::cout << "[CPU-5] PASSED: Register set verification complete.\n";
    return 0;
}
