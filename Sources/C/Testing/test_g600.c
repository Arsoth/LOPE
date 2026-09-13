#include "internal.h"

static uint8_t g600_fixture_report[G600_REPORT_BYTES];
static bool g600_fixture_get_fails;
static bool g600_fixture_set_fails;
static bool g600_fixture_update_on_set = true;
static int g600_fixture_fail_report_id = -1;
static size_t g600_fixture_length = G600_REPORT_BYTES;
static bool g600_fixture_wrong_report_id;
static bool g600_fixture_fail_get_after_set;
static size_t g600_fixture_get_calls;
static size_t g600_fixture_set_calls;

static bool g600_fixture_get(HidChannel *channel, uint8_t report_id, uint8_t *report,
                             size_t capacity, size_t *length) {
    (void)channel;
    g600_fixture_get_calls++;
    if (g600_fixture_get_fails || g600_fixture_fail_report_id == report_id || report == NULL ||
        length == NULL || capacity < G600_REPORT_BYTES) {
        return false;
    }
    memcpy(report, g600_fixture_report, G600_REPORT_BYTES);
    report[0] = g600_fixture_wrong_report_id ? (uint8_t)(report_id + 1) : report_id;
    *length = g600_fixture_length;
    return true;
}

static bool g600_fixture_set(HidChannel *channel, uint8_t report_id, uint8_t *report,
                             size_t length) {
    (void)channel;
    g600_fixture_set_calls++;
    if (g600_fixture_set_fails || report == NULL || length != G600_REPORT_BYTES ||
        report[0] != report_id) {
        return false;
    }
    if (g600_fixture_update_on_set) {
        memcpy(g600_fixture_report, report, G600_REPORT_BYTES);
    }
    if (g600_fixture_fail_get_after_set) {
        g600_fixture_get_fails = true;
    }
    return true;
}

static void g600_reset_fixture(void) {
    memset(g600_fixture_report, 0, sizeof(g600_fixture_report));
    g600_fixture_get_fails = false;
    g600_fixture_set_fails = false;
    g600_fixture_update_on_set = true;
    g600_fixture_fail_report_id = -1;
    g600_fixture_length = G600_REPORT_BYTES;
    g600_fixture_wrong_report_id = false;
    g600_fixture_fail_get_after_set = false;
    g600_fixture_get_calls = 0;
    g600_fixture_set_calls = 0;
}

int test_g600(void) {
    HidInterface g600_interface = {0};
    Device g600_device = {0};
    g600_interface.product_id = G600_PRODUCT_ID;
    g600_device.iface = &g600_interface;
    uint8_t g600_keyboard[3] = {0x00, 0x04, 0x2B};
    uint8_t g600_mouse[3] = {0x04, 0x00, 0x00};
    uint8_t g600_shift[3] = {0x17, 0x00, 0x00};
    uint8_t g600_spec[4] = {0};
    uint8_t g600_native[3] = {0};
    g600_native_to_spec(g600_keyboard, g600_spec);
    bool g600_mapping_ok = is_g600_device(&g600_device) && g600_spec[0] == 0x80 &&
                           g600_spec[1] == 0x02 && g600_spec[2] == 0x04 && g600_spec[3] == 0x2B &&
                           g600_spec_to_native(g600_spec, g600_native) &&
                           memcmp(g600_keyboard, g600_native, sizeof(g600_native)) == 0;
    g600_native_to_spec(g600_mouse, g600_spec);
    g600_mapping_ok = g600_mapping_ok && g600_spec[0] == 0x80 && g600_spec[1] == 0x01 &&
                      g600_spec[2] == 0x00 && g600_spec[3] == 0x08 &&
                      g600_spec_to_native(g600_spec, g600_native) &&
                      memcmp(g600_mouse, g600_native, sizeof(g600_native)) == 0;
    g600_native_to_spec(g600_shift, g600_spec);
    g600_mapping_ok = g600_mapping_ok && g600_spec[0] == 0x90 && g600_spec[1] == 0x0B &&
                      g600_spec[2] == 0x00 && g600_spec[3] == 0x00 &&
                      g600_spec_to_native(g600_spec, g600_native) &&
                      memcmp(g600_shift, g600_native, sizeof(g600_native)) == 0 &&
                      g600_profile_sector(1) == 0x00F3 && g600_profile_sector(3) == 0x00F5;
    if (!g600_mapping_ok) {
        fprintf(stderr, "G600 legacy mapping self-test failed\n");
        return 1;
    }

    bool g600_round_trip_ok = g600_profile_report_id(1, NULL) && !g600_profile_report_id(0, NULL) &&
                              !g600_profile_report_id(G600_PROFILE_COUNT + 1, NULL);
    uint8_t round_trip_codes[] = {1, 2, 3, 4, 5, 0x11, 0x12, 0x13, 0x14, 0x15, 0x17};
    for (size_t i = 0; i < sizeof(round_trip_codes); i++) {
        uint8_t native_code[3] = {round_trip_codes[i], 0, 0};
        uint8_t spec[4] = {0};
        uint8_t decoded[3] = {0};
        g600_native_to_spec(native_code, spec);
        g600_round_trip_ok = g600_round_trip_ok && g600_spec_to_native(spec, decoded) &&
                             memcmp(native_code, decoded, sizeof(native_code)) == 0;
    }
    uint8_t disabled_spec[4] = {0xFF, 0xFF, 0xFF, 0xFF};
    uint8_t disabled_native[3] = {1, 2, 3};
    uint8_t unsupported_mouse[4] = {0x80, 0x01, 0x00, 0x20};
    uint8_t unsupported_consumer[4] = {0x80, 0x03, 0x00, 0x99};
    uint8_t unsupported_function[4] = {0x90, 0x06, 0x00, 0x00};
    uint8_t malformed_mouse[4] = {0x80, 0x01, 0x01, 0x01};
    uint8_t malformed_consumer[4] = {0x80, 0x03, 0x01, 0x11};
    uint8_t malformed_function[4] = {0x90, 0x03, 0x01, 0x00};
    uint8_t malformed_function_value[4] = {0x90, 0x03, 0x00, 0x01};
    uint8_t unknown_spec[4] = {0x70, 0x00, 0x00, 0x00};
    g600_round_trip_ok =
        g600_round_trip_ok && g600_spec_to_native(disabled_spec, disabled_native) &&
        memcmp(disabled_native, (uint8_t[3]){0, 0, 0}, 3) == 0 &&
        !g600_spec_to_native(unsupported_mouse, disabled_native) &&
        !g600_spec_to_native(unsupported_consumer, disabled_native) &&
        !g600_spec_to_native(unsupported_function, disabled_native) &&
        !g600_spec_to_native(malformed_mouse, disabled_native) &&
        !g600_spec_to_native(malformed_consumer, disabled_native) &&
        !g600_spec_to_native(malformed_function, disabled_native) &&
        !g600_spec_to_native(malformed_function_value, disabled_native) &&
        !g600_spec_to_native(unknown_spec, disabled_native) && g600_profile_sector(0) == 0;
    char malformed_description[160] = {0};
    g600_describe_native((uint8_t[3]){0, 0, 1}, malformed_description,
                         sizeof(malformed_description));
    g600_round_trip_ok =
        g600_round_trip_ok && strstr(malformed_description, "keyboard chord") != NULL;
    const uint8_t consumer_codes[] = {0x11, 0x12, 0x13, 0x14, 0x15, 0x17};
    for (size_t i = 0; i < sizeof(consumer_codes); i++) {
        uint8_t consumer_spec[4] = {0x80, 0x03, 0x00, consumer_codes[i]};
        uint8_t consumer_native[3] = {0};
        g600_round_trip_ok = g600_round_trip_ok &&
                             g600_spec_to_native(consumer_spec, consumer_native) &&
                             memcmp(consumer_native, (uint8_t[3]){consumer_codes[i], 0, 0}, 3) == 0;
    }
    HidInterface named_g600_interface = {0};
    Device named_g600_device = {0};
    named_g600_device.iface = &named_g600_interface;
    snprintf(named_g600_interface.product, sizeof(named_g600_interface.product), "Logitech G600");
    bool g600_edge_ok = is_g600_device(&named_g600_device) && !is_g600_device(&(Device){0}) &&
                        !is_g600_device(NULL);
    if (!g600_round_trip_ok || !g600_edge_ok) {
        fprintf(stderr, "G600 mapping edge-case self-test failed\n");
        return 1;
    }

    uint8_t g600_report[G600_REPORT_BYTES] = {0};
    g600_report[0] = 0x03;
    uint8_t g600_native_codes[][3] = {
        {0x00, 0x00, 0x00}, {0x00, 0x04, 0x2B}, {0x01, 0x00, 0x00}, {0x02, 0x00, 0x00},
        {0x03, 0x00, 0x00}, {0x04, 0x00, 0x00}, {0x05, 0x00, 0x00}, {0x11, 0x00, 0x00},
        {0x12, 0x00, 0x00}, {0x13, 0x00, 0x00}, {0x14, 0x00, 0x00}, {0x15, 0x00, 0x00},
        {0x17, 0x00, 0x00}, {0x99, 0x00, 0x00},
    };
    for (size_t i = 0; i < sizeof(g600_native_codes) / sizeof(g600_native_codes[0]); i++) {
        memcpy(g600_report + G600_NORMAL_BUTTON_OFFSET + i * 3, g600_native_codes[i], 3);
    }
    char g600_print_path[] = "/tmp/lomps-selftest-g600-XXXXXX";
    int g600_print_fd = mkstemp(g600_print_path);
    if (g600_print_fd < 0) {
        fprintf(stderr, "g600_print_profile_summary self-test failed to create temp file\n");
        return 1;
    }
    close(g600_print_fd);
    int g600_saved_stdout = dup(fileno(stdout));
    bool g600_print_ok = g600_saved_stdout >= 0 && freopen(g600_print_path, "w", stdout) != NULL;
    if (g600_print_ok) {
        g600_print_profile_summary(1, g600_report, true);
        fflush(stdout);
    }
    if (g600_saved_stdout >= 0) {
        dup2(g600_saved_stdout, fileno(stdout));
        close(g600_saved_stdout);
        clearerr(stdout);
    }
    char g600_print_contents[4096] = {0};
    if (g600_print_ok) {
        FILE *readback = fopen(g600_print_path, "r");
        if (readback != NULL) {
            size_t read_bytes =
                fread(g600_print_contents, 1, sizeof(g600_print_contents) - 1, readback);
            g600_print_contents[read_bytes] = '\0';
            fclose(readback);
        } else {
            g600_print_ok = false;
        }
    }
    unlink(g600_print_path);
    g600_print_ok = g600_print_ok &&
                    strstr(g600_print_contents, "Profile 1 (sector 0x00F3, enabled=yes)") != NULL &&
                    strstr(g600_print_contents, "disabled") != NULL &&
                    strstr(g600_print_contents, "keyboard chord (mod 0x04 key 0x2B)") != NULL &&
                    strstr(g600_print_contents, "Left click") != NULL &&
                    strstr(g600_print_contents, "Right click") != NULL &&
                    strstr(g600_print_contents, "Middle click") != NULL &&
                    strstr(g600_print_contents, "Back / rear thumb") != NULL &&
                    strstr(g600_print_contents, "Forward") != NULL &&
                    strstr(g600_print_contents, "next DPI") != NULL &&
                    strstr(g600_print_contents, "previous DPI") != NULL &&
                    strstr(g600_print_contents, "cycle DPI") != NULL &&
                    strstr(g600_print_contents, "cycle profile") != NULL &&
                    strstr(g600_print_contents, "shift DPI") != NULL &&
                    strstr(g600_print_contents, "G-Shift") != NULL &&
                    strstr(g600_print_contents, "G600 function 0x99") != NULL;
    if (!g600_print_ok) {
        fprintf(stderr, "g600_print_profile_summary self-test failed\n");
        return 1;
    }

    Options g600_backup_path_options;
    memset(&g600_backup_path_options, 0, sizeof(g600_backup_path_options));
    char g600_backup_path[512] = {0};
    bool g600_backup_path_ok =
        g600_make_backup_path(&g600_backup_path_options, NULL, g600_backup_path) &&
        strcmp(g600_backup_path, "./g600-save.logiob") == 0;
    g600_backup_path_options.backup_directory = "/tmp/g600";
    g600_backup_path_ok =
        g600_backup_path_ok &&
        g600_make_backup_path(&g600_backup_path_options, "op-9", g600_backup_path) &&
        strcmp(g600_backup_path, "/tmp/g600/op-9.logiob") == 0;
    g600_backup_path_options.backup_directory = "";
    g600_backup_path_ok =
        g600_backup_path_ok &&
        g600_make_backup_path(&g600_backup_path_options, "op-10", g600_backup_path) &&
        strcmp(g600_backup_path, "./op-10.logiob") == 0;
    if (!g600_backup_path_ok) {
        fprintf(stderr, "g600_make_backup_path self-test failed\n");
        return 1;
    }

    HidInterface g600_apply_interface = {0};
    Device g600_apply_device = {0};
    g600_apply_device.iface = &g600_apply_interface;
    Options g600_apply_options;
    memset(&g600_apply_options, 0, sizeof(g600_apply_options));
    g600_apply_options.rgb_change_count = 1;
    int g600_apply_button = 1;
    bool g600_apply_gshift = false;
    uint8_t g600_apply_spec[1][4] = {{0x80, 0x01, 0x00, 0x01}};
    bool g600_apply_unsupported_ok =
        run_g600_apply(&g600_apply_options, &g600_apply_device, &g600_apply_button,
                       &g600_apply_gshift, g600_apply_spec, 1, "op-1") == 1;
    g600_apply_options.rgb_change_count = 0;
    g600_apply_options.dpi_values = "800";
    g600_apply_unsupported_ok =
        g600_apply_unsupported_ok &&
        run_g600_apply(&g600_apply_options, &g600_apply_device, &g600_apply_button,
                       &g600_apply_gshift, g600_apply_spec, 1, "op-dpi") == 1;
    g600_apply_options.dpi_values = NULL;
    g600_apply_options.profile_state_change_count = 1;
    g600_apply_unsupported_ok =
        g600_apply_unsupported_ok &&
        run_g600_apply(&g600_apply_options, &g600_apply_device, &g600_apply_button,
                       &g600_apply_gshift, g600_apply_spec, 1, "op-state") == 1;
    if (!g600_apply_unsupported_ok) {
        fprintf(stderr, "run_g600_apply unsupported-change self-test failed\n");
        return 1;
    }

    Options g600_info_options;
    memset(&g600_info_options, 0, sizeof(g600_info_options));
    g600_info_options.profile = 99;
    bool g600_range_ok = run_g600_info(&g600_info_options, &g600_apply_device) == 1;
    g600_apply_interface.product_id = G600_PRODUCT_ID;
    g600_info_options.profile = 1;
    g600_range_ok = g600_range_ok && run_g600_info(&g600_info_options, &g600_apply_device) == 1;
    Options g600_headers_options = {0};
    g600_headers_options.headers_only = true;
    g600_range_ok =
        g600_range_ok && run_g600_profiles(&g600_headers_options, &g600_apply_device) == 0;
    Options g600_dpi_options = {0};
    g600_dpi_options.include_dpi = true;
    g600_range_ok = g600_range_ok && run_g600_profiles(&g600_dpi_options, &g600_apply_device) == 1;
    Options g600_all_profiles_options = {0};
    g600_range_ok =
        g600_range_ok && run_g600_profiles(&g600_all_profiles_options, &g600_apply_device) == 0;
    Options g600_dump_options = {.path = "/tmp/lomps-selftest-g600-dump.logiob"};
    g600_range_ok = g600_range_ok && run_g600_dump(&g600_dump_options, &g600_apply_device) == 1;
    unlink(g600_dump_options.path);
    uint8_t g600_write_report[G600_REPORT_BYTES] = {0};
    g600_write_report[0] = G600_FIRST_PROFILE_REPORT;
    g600_range_ok = g600_range_ok && !g600_read_profile(NULL, 1, g600_write_report) &&
                    !g600_read_profile(&g600_apply_device, 0, g600_write_report) &&
                    !g600_write_profile(&g600_apply_device, 1, g600_write_report) &&
                    !g600_write_profile(&g600_apply_device, 0, g600_write_report);
    char long_backup_directory[512];
    memset(long_backup_directory, 'x', sizeof(long_backup_directory) - 1);
    long_backup_directory[sizeof(long_backup_directory) - 1] = '\0';
    g600_backup_path_options.backup_directory = long_backup_directory;
    g600_range_ok =
        g600_range_ok && !g600_make_backup_path(&g600_backup_path_options, "op", g600_backup_path);
    g600_range_ok = g600_range_ok && !g600_write_profile(NULL, 1, g600_write_report);
    if (!g600_range_ok) {
        fprintf(stderr, "run_g600_info out-of-range self-test failed\n");
        return 1;
    }

    g600_interface.vendor_id = LOGITECH_VID;
    g600_interface.product_id = G600_PRODUCT_ID;
    g600_reset_fixture();
    g600_fixture_report[31] = 0x01;
    g600_fixture_report[94] = 0x17;
    g600_get_feature_report_impl = g600_fixture_get;
    g600_set_feature_report_impl = g600_fixture_set;

    uint8_t io_report[G600_REPORT_BYTES] = {0};
    bool g600_transport_ok = g600_read_profile(&g600_device, 1, io_report) &&
                             io_report[0] == G600_FIRST_PROFILE_REPORT && io_report[31] == 0x01 &&
                             g600_fixture_get_calls == 1;
    g600_fixture_get_fails = true;
    g600_transport_ok = g600_transport_ok && !g600_read_profile(&g600_device, 1, io_report);
    g600_fixture_get_fails = false;
    g600_fixture_length = G600_REPORT_BYTES - 1;
    g600_transport_ok = g600_transport_ok && !g600_read_profile(&g600_device, 1, io_report);
    g600_fixture_length = G600_REPORT_BYTES;
    g600_fixture_wrong_report_id = true;
    g600_transport_ok = g600_transport_ok && !g600_read_profile(&g600_device, 1, io_report);
    g600_fixture_wrong_report_id = false;
    g600_transport_ok = g600_transport_ok && !g600_read_profile(&g600_device, 1, NULL);

    io_report[0] = G600_FIRST_PROFILE_REPORT;
    g600_fixture_set_fails = true;
    g600_transport_ok = g600_transport_ok && !g600_write_profile(&g600_device, 1, io_report);
    g600_fixture_set_fails = false;
    g600_transport_ok = g600_transport_ok && g600_write_profile(&g600_device, 1, io_report) &&
                        g600_fixture_set_calls >= 2 &&
                        !g600_write_profile(&g600_device, 1, (uint8_t[G600_REPORT_BYTES]){0});
    if (!g600_transport_ok) {
        fprintf(stderr, "G600 feature-report transport self-test failed\n");
        return 1;
    }

    g600_print_profile_summary(1, g600_report, false);
    Options g600_info_success_options = {.profile = 1};
    bool g600_command_ok = run_g600_info(&g600_info_success_options, &g600_device) == 0;

    Options g600_profiles_invalid = {.profile = G600_PROFILE_COUNT + 1};
    g600_command_ok =
        g600_command_ok && run_g600_profiles(&g600_profiles_invalid, &g600_device) == 1;
    Options g600_profiles_selected = {.profile = 2};
    g600_command_ok =
        g600_command_ok && run_g600_profiles(&g600_profiles_selected, &g600_device) == 0;
    Options g600_profiles_dpi = {.profile = 2, .include_dpi = true};
    g600_command_ok = g600_command_ok && run_g600_profiles(&g600_profiles_dpi, &g600_device) == 0;
    g600_fixture_fail_report_id = G600_FIRST_PROFILE_REPORT + 1;
    Options g600_profiles_dpi_fail = {.profile = 2, .include_dpi = true};
    g600_command_ok =
        g600_command_ok && run_g600_profiles(&g600_profiles_dpi_fail, &g600_device) == 1;
    g600_fixture_fail_report_id = -1;
    Options g600_profiles_all = {0};
    g600_command_ok = g600_command_ok && run_g600_profiles(&g600_profiles_all, &g600_device) == 0;
    Options g600_profiles_all_with_failure = {0};
    g600_fixture_fail_report_id = G600_FIRST_PROFILE_REPORT + 1;
    g600_command_ok =
        g600_command_ok && run_g600_profiles(&g600_profiles_all_with_failure, &g600_device) == 0;
    g600_fixture_fail_report_id = -1;
    if (!g600_command_ok) {
        fprintf(stderr, "G600 command success-path self-test failed\n");
        return 1;
    }

    Options g600_dump_success = {.path = "/tmp/lomps-selftest-g600-success.logiob", .profile = 1};
    unlink(g600_dump_success.path);
    bool g600_dump_ok = run_g600_dump(&g600_dump_success, &g600_device) == 0;
    BackupPackage dumped_g600 = {0};
    g600_dump_ok = g600_dump_ok && package_read(g600_dump_success.path, &dumped_g600) &&
                   dumped_g600.profile_format == G600_BACKUP_PROFILE_FORMAT &&
                   dumped_g600.sector_count == 1 && dumped_g600.sectors[0].sector == 0x00F3 &&
                   dumped_g600.sectors[0].size == G600_REPORT_BYTES;
    package_release(&dumped_g600);
    unlink(g600_dump_success.path);
    Options g600_dump_failure = {.path = "/no-such-g600-directory/dump.logiob", .profile = 1};
    g600_dump_ok = g600_dump_ok && run_g600_dump(&g600_dump_failure, &g600_device) == 1;
    g600_fixture_get_fails = true;
    g600_dump_ok = g600_dump_ok && run_g600_dump(&g600_dump_success, &g600_device) == 1;
    g600_fixture_get_fails = false;
    if (!g600_dump_ok) {
        fprintf(stderr, "G600 dump self-test failed\n");
        return 1;
    }

    Options g600_apply_run_options = {.profile = 1, .backup_directory = "/tmp", .yes = true};
    int apply_buttons[2] = {1, 2};
    bool apply_gshift[2] = {false, true};
    uint8_t apply_specs[2][4] = {{0x80, 0x01, 0x00, 0x01}, {0x90, 0x0B, 0x00, 0x00}};
    uint8_t apply_invalid_spec[1][4] = {{0x90, 0x06, 0x00, 0x00}};
    int apply_invalid_button[1] = {0};
    int apply_too_large_button[1] = {G600_BUTTON_COUNT + 1};
    bool g600_apply_ok =
        run_g600_apply(&g600_apply_run_options, &g600_device, apply_buttons, apply_gshift,
                       apply_specs, 0, NULL) == 0 &&
        run_g600_apply(&g600_apply_run_options, &g600_device, apply_invalid_button, apply_gshift,
                       apply_specs, 1, "invalid-button") == 1 &&
        run_g600_apply(&g600_apply_run_options, &g600_device, apply_too_large_button, apply_gshift,
                       apply_specs, 1, "large-button") == 1 &&
        run_g600_apply(&g600_apply_run_options, &g600_device, apply_buttons, apply_gshift,
                       apply_invalid_spec, 1, "invalid-spec") == 1;

    Options preview_apply_options = g600_apply_run_options;
    preview_apply_options.yes = false;
    g600_fixture_report[31] = 0;
    g600_fixture_report[94] = 0;
    g600_apply_ok =
        g600_apply_ok && run_g600_apply(&preview_apply_options, &g600_device, apply_buttons,
                                        apply_gshift, apply_specs, 2, "preview-apply") == 0;
    char long_operation_id[512];
    memset(long_operation_id, 'o', sizeof(long_operation_id) - 1);
    long_operation_id[sizeof(long_operation_id) - 1] = '\0';
    g600_apply_ok =
        g600_apply_ok && run_g600_apply(&g600_apply_run_options, &g600_device, apply_buttons,
                                        apply_gshift, apply_specs, 2, long_operation_id) == 1;

    unlink("/tmp/g600-apply-success.logiob");
    g600_fixture_update_on_set = true;
    g600_apply_ok =
        g600_apply_ok && run_g600_apply(&g600_apply_run_options, &g600_device, apply_buttons,
                                        apply_gshift, apply_specs, 2, "g600-apply-success") == 0;
    unlink("/tmp/g600-apply-success.logiob");

    g600_fixture_set_fails = true;
    g600_fixture_report[31] = 0;
    g600_fixture_report[94] = 0;
    unlink("/tmp/g600-apply-write-fail.logiob");
    g600_apply_ok =
        g600_apply_ok && run_g600_apply(&g600_apply_run_options, &g600_device, apply_buttons,
                                        apply_gshift, apply_specs, 1, "g600-apply-write-fail") == 1;
    unlink("/tmp/g600-apply-write-fail.logiob");
    g600_fixture_set_fails = false;
    g600_fixture_update_on_set = false;
    g600_fixture_report[31] = 0;
    g600_fixture_report[94] = 0;
    unlink("/tmp/g600-apply-verify-fail.logiob");
    g600_apply_ok = g600_apply_ok &&
                    run_g600_apply(&g600_apply_run_options, &g600_device, apply_buttons,
                                   apply_gshift, apply_specs, 1, "g600-apply-verify-fail") == 1;
    unlink("/tmp/g600-apply-verify-fail.logiob");
    g600_fixture_update_on_set = true;
    g600_fixture_get_fails = true;
    g600_apply_ok =
        g600_apply_ok && run_g600_apply(&g600_apply_run_options, &g600_device, apply_buttons,
                                        apply_gshift, apply_specs, 1, "g600-apply-read-fail") == 1;
    g600_fixture_get_fails = false;
    if (!g600_apply_ok) {
        fprintf(stderr, "G600 apply self-test failed\n");
        return 1;
    }

    g600_fixture_report[31] = 0;
    unlink("/tmp/g600-save.logiob");
    g600_apply_ok = run_g600_apply(&g600_apply_run_options, &g600_device, apply_buttons,
                                   apply_gshift, apply_specs, 1, NULL) == 0;
    unlink("/tmp/g600-save.logiob");
    Options g600_apply_backup_failure = g600_apply_run_options;
    g600_apply_backup_failure.backup_directory = "/no-such-g600-directory";
    g600_fixture_report[31] = 0;
    g600_apply_ok = g600_apply_ok &&
                    run_g600_apply(&g600_apply_backup_failure, &g600_device, apply_buttons,
                                   apply_gshift, apply_specs, 1, "g600-apply-backup-fail") == 1;
    if (!g600_apply_ok) {
        fprintf(stderr, "G600 apply backup-path self-test failed\n");
        return 1;
    }

    BackupPackage restore_package = {0};
    restore_package.profile_format = G600_BACKUP_PROFILE_FORMAT;
    restore_package.sector_count = 1;
    restore_package.sectors[0].sector = G600_FIRST_PROFILE_REPORT;
    restore_package.sectors[0].size = G600_REPORT_BYTES;
    restore_package.sectors[0].data = (uint8_t *)calloc(G600_REPORT_BYTES, 1);
    if (restore_package.sectors[0].data == NULL) {
        return 1;
    }
    restore_package.sectors[0].data[0] = G600_FIRST_PROFILE_REPORT;
    restore_package.sectors[0].data[31] = 0x05;
    Options restore_options = {.path = "/tmp/lomps-selftest-g600-restore.logiob", .yes = true};
    unlink(restore_options.path);
    unlink("/tmp/lomps-selftest-g600-restore.logiob.pre-restore.logiob");
    bool g600_restore_ok = true;
    restore_package.profile_format = 0;
    g600_restore_ok =
        g600_restore_ok && run_g600_restore(&restore_options, &g600_device, &restore_package) == 1;
    restore_package.profile_format = G600_BACKUP_PROFILE_FORMAT;
    restore_package.sector_count = 0;
    g600_restore_ok =
        g600_restore_ok && run_g600_restore(&restore_options, &g600_device, &restore_package) == 1;
    restore_package.sector_count = 1;
    restore_package.sectors[0].size = G600_REPORT_BYTES - 1;
    g600_restore_ok =
        g600_restore_ok && run_g600_restore(&restore_options, &g600_device, &restore_package) == 1;
    restore_package.sectors[0].size = G600_REPORT_BYTES;
    restore_package.sectors[0].data[0] = 0;
    g600_restore_ok =
        g600_restore_ok && run_g600_restore(&restore_options, &g600_device, &restore_package) == 1;
    restore_package.sectors[0].data[0] = G600_FIRST_PROFILE_REPORT;
    memcpy(g600_fixture_report, restore_package.sectors[0].data, G600_REPORT_BYTES);
    g600_fixture_report[0] = G600_FIRST_PROFILE_REPORT;
    g600_restore_ok =
        g600_restore_ok && run_g600_restore(&restore_options, &g600_device, &restore_package) == 0;
    g600_fixture_report[31] = 0;
    g600_restore_ok =
        g600_restore_ok && run_g600_restore(&restore_options, &g600_device, &restore_package) == 0;
    Options restore_preview = restore_options;
    restore_preview.yes = false;
    g600_fixture_report[31] = 0;
    g600_restore_ok =
        g600_restore_ok && run_g600_restore(&restore_preview, &g600_device, &restore_package) == 0;
    g600_fixture_report[31] = 0;
    g600_fixture_get_fails = true;
    g600_restore_ok =
        g600_restore_ok && run_g600_restore(&restore_options, &g600_device, &restore_package) == 1;
    g600_fixture_get_fails = false;
    restore_package.sectors[0].sector = G600_FIRST_PROFILE_REPORT + G600_PROFILE_COUNT;
    g600_restore_ok =
        g600_restore_ok && run_g600_restore(&restore_options, &g600_device, &restore_package) == 1;
    restore_package.sectors[0].sector = G600_FIRST_PROFILE_REPORT;
    g600_fixture_report[31] = 0;
    g600_fixture_fail_get_after_set = true;
    g600_restore_ok =
        g600_restore_ok && run_g600_restore(&restore_options, &g600_device, &restore_package) == 1;
    g600_fixture_fail_get_after_set = false;
    g600_fixture_get_fails = false;
    g600_fixture_report[31] = 0;
    char long_restore_path[512];
    memset(long_restore_path, 'r', sizeof(long_restore_path) - 1);
    long_restore_path[sizeof(long_restore_path) - 1] = '\0';
    Options restore_long_path = {.path = long_restore_path, .yes = true};
    g600_restore_ok = g600_restore_ok &&
                      run_g600_restore(&restore_long_path, &g600_device, &restore_package) == 1;
    Options restore_bad_directory = {.path = "/no-such-g600-directory/restore.logiob", .yes = true};
    g600_fixture_report[31] = 0;
    g600_restore_ok = g600_restore_ok &&
                      run_g600_restore(&restore_bad_directory, &g600_device, &restore_package) == 1;
    g600_fixture_set_fails = true;
    g600_restore_ok =
        g600_restore_ok && run_g600_restore(&restore_options, &g600_device, &restore_package) == 1;
    g600_fixture_set_fails = false;
    g600_fixture_update_on_set = false;
    g600_restore_ok =
        g600_restore_ok && run_g600_restore(&restore_options, &g600_device, &restore_package) == 1;
    g600_fixture_update_on_set = true;
    g600_fixture_report[31] = 0;
    g600_restore_ok =
        g600_restore_ok && run_g600_restore(&restore_options, &g600_device, &restore_package) == 0;
    unlink(restore_options.path);
    unlink("/tmp/lomps-selftest-g600-restore.logiob.pre-restore.logiob");
    package_release(&restore_package);
    g600_get_feature_report_impl = channel_get_feature_report;
    g600_set_feature_report_impl = channel_set_feature_report;
    if (!g600_restore_ok) {
        fprintf(stderr, "G600 restore self-test failed\n");
        return 1;
    }

    return 0;
}
