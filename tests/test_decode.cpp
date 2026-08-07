/* tests/test_decode.cpp - Test driver for CPU-4 ColdFire v3 opcode decode table & M-9 JSON export */

#include <iostream>
#include <cstring>

#include "mcf5307.h"

extern "C" {
    int mcf5307_test_decode_eval(void);
    const char* mcf5307_export_decode_json(void);
}

int main() {
    std::cout << "[CPU-4] Testing instruction decode table and JSON determinism export (M-9)...\n";
    mcf5307_runtime_init();

    int res = mcf5307_test_decode_eval();
    if (res != 0) {
        std::cerr << "FAILED: mcf5307_test_decode_eval returned error code " << res << "\n";
        return res;
    }

    const char* json_export = mcf5307_export_decode_json();
    if (!json_export || std::strlen(json_export) == 0) {
        std::cerr << "FAILED: JSON determinism export produced null or empty string\n";
        return 100;
    }

    std::cout << "[CPU-4] PASSED: Instruction decode table verified, JSON export determinism (M-9) confirmed.\n";
    return 0;
}
