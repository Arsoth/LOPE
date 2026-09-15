#include "selftest.h"
#include "selftest_modules.h"
#include "test_doubles.h"

#include <stdio.h>
#include <time.h>

typedef struct {
    const char *name;
    int (*run)(void);
} SelfTestCase;

int run_self_test(void) {
    const SelfTestCase cases[] = {
        {"hid_transport", test_hid_transport},
        {"hid_discovery", test_hid_discovery},
        {"profile_codec", test_profile_codec},
        {"profile_io", test_profile_io},
        {"profile_rendering", test_profile_rendering},
        {"report_rate", test_report_rate},
        {"g600", test_g600},
        {"backup_codec", test_backup_codec},
        {"backup", test_backup},
        {"commands_read", test_commands_read},
        {"commands_set_dpi", test_commands_set_dpi},
        {"commands_set_profile_state", test_commands_set_profile_state},
        {"commands_apply", test_commands_apply},
        {"commands_backup_bind", test_commands_backup_bind},
        {"watch_cli", test_watch_cli},
        {"engine_boundary", test_engine_boundary},
    };
    const size_t case_count = sizeof(cases) / sizeof(cases[0]);

    struct timespec start_time;
    clock_gettime(CLOCK_MONOTONIC, &start_time);

    int passed = 0;
    int failed = 0;
    for (size_t i = 0; i < case_count; i++) {
        if (cases[i].run() == 0) {
            passed++;
        } else {
            failed++;
            fprintf(stderr, "self-test module failed: %s\n", cases[i].name);
        }
    }

    // Seams are only reset once, after every case has run: each case that
    // uses discover_devices_for_options_impl/channel_request_impl sets its
    // own test double and context immediately before use, so resetting
    // between cases serves no isolation purpose and instead points a
    // mid-suite call at the real hardware implementation, which crashes
    // when it runs against a mocked device with no live handle.
    reset_hid_test_seams();

    struct timespec end_time;
    clock_gettime(CLOCK_MONOTONIC, &end_time);
    double duration_seconds = (double)(end_time.tv_sec - start_time.tv_sec) +
                              (double)(end_time.tv_nsec - start_time.tv_nsec) / 1e9;

    printf("self-test: %d passed, %d failed, %d total (%.3fs)\n", passed, failed, (int)case_count,
           duration_seconds);

    return failed == 0 ? 0 : 1;
}
