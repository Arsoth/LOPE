#include "internal.h"
#include "selftest_modules.h"
#include "test_doubles.h"

int run_self_test(void) {
    if (test_hid_transport() != 0) {
        return 1;
    }
    if (test_hid_discovery() != 0) {
        return 1;
    }
    if (test_profile_io() != 0) {
        return 1;
    }
    if (test_profile_rendering() != 0) {
        return 1;
    }
    if (test_report_rate() != 0) {
        return 1;
    }
    if (test_g600() != 0) {
        return 1;
    }
    if (test_backup() != 0) {
        return 1;
    }
    if (test_commands_read() != 0) {
        return 1;
    }
    if (test_commands_mutate() != 0) {
        return 1;
    }
    if (test_commands_backup_bind() != 0) {
        return 1;
    }
    if (test_watch_cli() != 0) {
        return 1;
    }

    reset_hid_test_seams();

    printf("self-test: receiver model-name fallback, connection types, CRC-16, DPI "
           "sentinel/compaction, format/layout detection, G600 legacy mapping, batch "
           "planning/failure handling, rear-thumb identification, Alt+Tab encoding, "
           "report-rate decoding, device selection, and command-layer discovery mocking "
           "passed\n");
    return 0;
}
