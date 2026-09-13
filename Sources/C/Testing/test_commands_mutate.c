#include "internal.h"
#include "test_doubles.h"

typedef struct {
    const bool *outcomes;
    size_t outcome_count;
    size_t calls;
} BatchWriterTestContext;

static bool batch_test_writer(void *context, const BatchSector *sector) {
    BatchWriterTestContext *test = (BatchWriterTestContext *)context;
    (void)sector;
    if (test->calls >= test->outcome_count) {
        return false;
    }
    return test->outcomes[test->calls++];
}

int test_commands_mutate(void) {
    uint8_t unchanged_before[4] = {0x10, 0x20, 0x30, 0x40};
    uint8_t unchanged_after[4] = {0x10, 0x20, 0x30, 0x40};
    uint8_t changed_after[4] = {0x10, 0x20, 0x30, 0x41};
    bool batch_plan_ok =
        !batch_sector_changed(unchanged_before, unchanged_after, sizeof(unchanged_before)) &&
        batch_sector_changed(unchanged_before, changed_after, sizeof(unchanged_before)) &&
        batch_affected_sector_count(true, false) == 1 &&
        batch_affected_sector_count(false, true) == 1 &&
        batch_affected_sector_count(true, true) == 2 &&
        batch_affected_sector_count(false, false) == 0;
    if (!batch_plan_ok) {
        fprintf(stderr, "batch sector planning self-test failed\n");
        return 1;
    }

    bool first_failure[] = {false};
    BatchWriterTestContext first_failure_context = {
        .outcomes = first_failure, .outcome_count = 1, .calls = 0};
    bool later_failure[] = {true, false};
    BatchWriterTestContext later_failure_context = {
        .outcomes = later_failure, .outcome_count = 2, .calls = 0};
    bool all_success[] = {true, true};
    BatchWriterTestContext all_success_context = {
        .outcomes = all_success, .outcome_count = 2, .calls = 0};
    BatchSector test_plan[2] = {{.sector = 0x0100,
                                 .data = unchanged_before,
                                 .length = sizeof(unchanged_before),
                                 .kind = "profile"},
                                {.sector = 0x0001,
                                 .data = unchanged_before,
                                 .length = sizeof(unchanged_before),
                                 .kind = "control"}};
    size_t test_verified = 0;
    size_t test_failed = 0;
    bool batch_failure_tests_ok =
        !execute_batch_sector_plan(test_plan, 1, batch_test_writer, &first_failure_context,
                                   &test_verified, &test_failed) &&
        test_verified == 0 && test_failed == 0 && first_failure_context.calls == 1 &&
        !execute_batch_sector_plan(test_plan, 2, batch_test_writer, &later_failure_context,
                                   &test_verified, &test_failed) &&
        test_verified == 1 && test_failed == 1 && later_failure_context.calls == 2 &&
        execute_batch_sector_plan(test_plan, 2, batch_test_writer, &all_success_context,
                                  &test_verified, &test_failed) &&
        test_verified == 2 && all_success_context.calls == 2;
    if (!batch_failure_tests_ok) {
        fprintf(stderr, "batch failure-path self-test failed\n");
        return 1;
    }

    uint16_t dpi_list_values[MAX_DPI_VALUES] = {800, 1600, 2400};
    bool dpi_value_in_list_ok =
        dpi_value_in_list(dpi_list_values, 3, 1600) && !dpi_value_in_list(dpi_list_values, 3, 3200);
    if (!dpi_value_in_list_ok) {
        fprintf(stderr, "dpi_value_in_list self-test failed\n");
        return 1;
    }

    uint8_t raw_record_spec[4] = {0};
    bool raw_record_ok = parse_batch_raw_record("80010004", raw_record_spec) &&
                         raw_record_spec[0] == 0x80 && raw_record_spec[1] == 0x01 &&
                         raw_record_spec[2] == 0x00 && raw_record_spec[3] == 0x04 &&
                         !parse_batch_raw_record("8001000", raw_record_spec) &&
                         !parse_batch_raw_record("8001000G", raw_record_spec) &&
                         !parse_batch_raw_record(NULL, raw_record_spec);
    if (!raw_record_ok) {
        fprintf(stderr, "parse_batch_raw_record self-test failed\n");
        return 1;
    }

    int profile_state_number = 0;
    bool profile_state_enabled = false;
    bool profile_state_parser_ok =
        parse_batch_profile_state("3:enable", &profile_state_number, &profile_state_enabled) &&
        profile_state_number == 3 && profile_state_enabled &&
        parse_batch_profile_state("2:disable", &profile_state_number, &profile_state_enabled) &&
        profile_state_number == 2 && !profile_state_enabled &&
        !parse_batch_profile_state("bad", &profile_state_number, &profile_state_enabled) &&
        !parse_batch_profile_state("2:maybe", &profile_state_number, &profile_state_enabled) &&
        !parse_batch_profile_state(NULL, &profile_state_number, &profile_state_enabled);
    if (!profile_state_parser_ok) {
        fprintf(stderr, "parse_batch_profile_state self-test failed\n");
        return 1;
    }

    bool operation_id_ok = batch_operation_id_is_safe("lope-20260101-120000-42") &&
                           !batch_operation_id_is_safe(NULL) && !batch_operation_id_is_safe("") &&
                           !batch_operation_id_is_safe("bad id!");
    if (!operation_id_ok) {
        fprintf(stderr, "batch_operation_id_is_safe self-test failed\n");
        return 1;
    }

    char batch_backup_path[512] = {0};
    bool batch_backup_path_ok = make_batch_backup_path("/tmp/backups", "op-1", batch_backup_path) &&
                                strcmp(batch_backup_path, "/tmp/backups/op-1.logiob") == 0 &&
                                make_batch_backup_path(NULL, "op-2", batch_backup_path) &&
                                strcmp(batch_backup_path, "./op-2.logiob") == 0 &&
                                make_batch_backup_path("", "op-3", batch_backup_path) &&
                                strcmp(batch_backup_path, "./op-3.logiob") == 0;
    if (!batch_backup_path_ok) {
        fprintf(stderr, "make_batch_backup_path self-test failed\n");
        return 1;
    }

    char batch_recovery_path[] = "/tmp/lomps-selftest-recovery-XXXXXX";
    int batch_recovery_fd = mkstemp(batch_recovery_path);
    if (batch_recovery_fd < 0) {
        fprintf(stderr, "print_batch_recovery self-test failed to create temp file\n");
        return 1;
    }
    close(batch_recovery_fd);
    int batch_recovery_saved_stderr = dup(fileno(stderr));
    bool batch_recovery_ok =
        batch_recovery_saved_stderr >= 0 && freopen(batch_recovery_path, "w", stderr) != NULL;
    if (batch_recovery_ok) {
        print_batch_recovery("op-1", 1, "control", 0x0001, "/tmp/backup.logiob", true);
        print_batch_recovery("op-2", 0, "profile", 0x0123, NULL, false);
        fflush(stderr);
    }
    if (batch_recovery_saved_stderr >= 0) {
        dup2(batch_recovery_saved_stderr, fileno(stderr));
        close(batch_recovery_saved_stderr);
        clearerr(stderr);
    }
    char batch_recovery_contents[512] = {0};
    if (batch_recovery_ok) {
        FILE *readback = fopen(batch_recovery_path, "r");
        if (readback != NULL) {
            size_t read_bytes =
                fread(batch_recovery_contents, 1, sizeof(batch_recovery_contents) - 1, readback);
            batch_recovery_contents[read_bytes] = '\0';
            fclose(readback);
        } else {
            batch_recovery_ok = false;
        }
    }
    unlink(batch_recovery_path);
    batch_recovery_ok =
        batch_recovery_ok &&
        strstr(batch_recovery_contents,
               "Save operation op-1 failed after 1 sector(s) were verified.") != NULL &&
        strstr(batch_recovery_contents, "control sector 0x0001 was not verified") != NULL &&
        strstr(batch_recovery_contents, "/tmp/backup.logiob") != NULL &&
        strstr(batch_recovery_contents,
               "Save operation op-2 failed after 0 sector(s) were verified.") != NULL &&
        strstr(batch_recovery_contents, "profile sector 0x0123 was not verified") != NULL;
    if (!batch_recovery_ok) {
        fprintf(stderr, "print_batch_recovery self-test failed\n");
        return 1;
    }

    uint8_t parsed_rgb_color[3] = {0};
    int parsed_rgb_zone = 0;
    bool rgb_parser_ok = parse_batch_rgb_change("2:A1B2C3", &parsed_rgb_zone, parsed_rgb_color) &&
                         parsed_rgb_zone == 2 && parsed_rgb_color[0] == 0xA1 &&
                         parsed_rgb_color[1] == 0xB2 && parsed_rgb_color[2] == 0xC3 &&
                         !parse_batch_rgb_change("3:GG0000", &parsed_rgb_zone, parsed_rgb_color);
    if (!rgb_parser_ok) {
        fprintf(stderr, "parse_batch_rgb_change self-test failed\n");
        return 1;
    }

    int parsed_button = 0;
    bool parsed_gshift = false;
    uint8_t parsed_button_spec[4] = {0};
    bool gshift_parser_ok = parse_batch_button_change("gshift:3:80010004", &parsed_button,
                                                      &parsed_gshift, parsed_button_spec) &&
                            parsed_button == 3 && parsed_gshift && parsed_button_spec[3] == 0x04;
    bool normal_parser_ok = parse_batch_button_change("normal:2:80010002", &parsed_button,
                                                      &parsed_gshift, parsed_button_spec) &&
                            parsed_button == 2 && !parsed_gshift && parsed_button_spec[3] == 0x02;
    if (!gshift_parser_ok || !normal_parser_ok) {
        fprintf(stderr, "parse_batch_button_change self-test failed\n");
        return 1;
    }

    Options apply_options;
    memset(&apply_options, 0, sizeof(apply_options));
    apply_options.dpi_default = -1;
    apply_options.dpi_shift = -1;
    bool apply_validation_ok = run_apply(&apply_options) == 1;

    apply_options.profile = 1;
    apply_options.report_rate = "not-a-number";
    apply_validation_ok = apply_validation_ok && run_apply(&apply_options) == 1;

    apply_options.report_rate = NULL;
    apply_validation_ok = apply_validation_ok && run_apply(&apply_options) == 1;

    const char *valid_rgb_change = "1:AABBCC";
    apply_options.rgb_changes[0] = valid_rgb_change;
    apply_options.rgb_change_count = 1;
    apply_options.dpi_default = 0;
    apply_validation_ok = apply_validation_ok && run_apply(&apply_options) == 1;
    apply_options.dpi_default = -1;

    const char *invalid_button_change = "sideways:1:80010001";
    apply_options.button_changes[0] = invalid_button_change;
    apply_options.button_change_count = 1;
    apply_validation_ok = apply_validation_ok && run_apply(&apply_options) == 1;

    const char *duplicate_button_change_a = "normal:1:80010001";
    const char *duplicate_button_change_b = "normal:1:80010002";
    apply_options.button_changes[0] = duplicate_button_change_a;
    apply_options.button_changes[1] = duplicate_button_change_b;
    apply_options.button_change_count = 2;
    apply_validation_ok = apply_validation_ok && run_apply(&apply_options) == 1;

    const char *structurally_invalid_button_change = "normal:1:30000000";
    apply_options.button_changes[0] = structurally_invalid_button_change;
    apply_options.button_change_count = 1;
    apply_validation_ok = apply_validation_ok && run_apply(&apply_options) == 1;
    apply_options.button_change_count = 0;

    const char *invalid_rgb_change = "not-valid";
    apply_options.rgb_changes[0] = invalid_rgb_change;
    apply_options.rgb_change_count = 1;
    apply_validation_ok = apply_validation_ok && run_apply(&apply_options) == 1;

    const char *duplicate_rgb_change_a = "1:AABBCC";
    const char *duplicate_rgb_change_b = "1:112233";
    apply_options.rgb_changes[0] = duplicate_rgb_change_a;
    apply_options.rgb_changes[1] = duplicate_rgb_change_b;
    apply_options.rgb_change_count = 2;
    apply_validation_ok = apply_validation_ok && run_apply(&apply_options) == 1;
    apply_options.rgb_change_count = 1;
    apply_options.rgb_changes[0] = valid_rgb_change;

    const char *invalid_profile_state_change = "not-valid";
    apply_options.profile_state_changes[0] = invalid_profile_state_change;
    apply_options.profile_state_change_count = 1;
    apply_validation_ok = apply_validation_ok && run_apply(&apply_options) == 1;

    const char *duplicate_profile_state_a = "1:enable";
    const char *duplicate_profile_state_b = "1:disable";
    apply_options.profile_state_changes[0] = duplicate_profile_state_a;
    apply_options.profile_state_changes[1] = duplicate_profile_state_b;
    apply_options.profile_state_change_count = 2;
    apply_validation_ok = apply_validation_ok && run_apply(&apply_options) == 1;
    apply_options.profile_state_change_count = 0;

    apply_options.dpi_values = "not-a-list";
    apply_validation_ok = apply_validation_ok && run_apply(&apply_options) == 1;

    apply_options.dpi_values = "1600,800";
    apply_validation_ok = apply_validation_ok && run_apply(&apply_options) == 1;
    apply_options.dpi_values = NULL;

    apply_options.operation_id = "bad id!";
    apply_validation_ok = apply_validation_ok && run_apply(&apply_options) == 1;
    if (!apply_validation_ok) {
        fprintf(stderr, "run_apply validation self-test failed\n");
        return 1;
    }

    apply_options.operation_id = NULL;
    apply_options.device_index = -1;
    discover_devices_for_options_impl = discover_devices_for_options_test_double;
    DiscoverDevicesTestContext apply_empty_discovery_context = {
        .devices = NULL, .count = 0, .result = 1};
    g_discover_devices_test_context = &apply_empty_discovery_context;
    bool apply_no_device_ok = run_apply(&apply_options) == 1;
    if (!apply_no_device_ok) {
        fprintf(stderr, "run_apply no-device self-test failed\n");
        return 1;
    }

    // run_set_dpi end-to-end: the requested DPI list, and the resolved
    // default/shift indexes, exactly match what the mock sector already
    // stores, so the sector write_sector() performs is byte-identical to it
    // and the same data_chunks reply sequence can double as its readback.
    uint8_t mock_sector[255];
    build_mock_onboard_sector(mock_sector);
    uint8_t mock_control[132];
    build_mock_control_sector(mock_control);
    Reply control_chunks[16];
    size_t control_chunk_count =
        build_sector_read_replies(mock_control, sizeof(mock_control), control_chunks, 16);
    Reply data_chunks[32];
    size_t data_chunk_count =
        build_sector_read_replies(mock_sector, sizeof(mock_sector), data_chunks, 32);
    if (control_chunk_count == 0 || data_chunk_count == 0) {
        fprintf(stderr, "run_set_dpi self-test failed to build mock sector-read replies\n");
        return 1;
    }

    Reply set_dpi_replies[64];
    size_t set_dpi_reply_count = 0;
    set_dpi_replies[set_dpi_reply_count++] = (Reply){.status = REPLY_OK, .length = 1, .bytes = {1}};
    set_dpi_replies[set_dpi_reply_count++] =
        (Reply){.status = REPLY_OK,
                .length = 11,
                .bytes = {0x00, 0x03, 0x20, 0x04, 0xB0, 0x06, 0x40, 0x09, 0x60, 0x0C, 0x80}};
    set_dpi_replies[set_dpi_reply_count++] = k_mock_get_info_reply;
    for (size_t i = 0; i < control_chunk_count; i++) {
        set_dpi_replies[set_dpi_reply_count++] = control_chunks[i];
    }
    for (size_t i = 0; i < data_chunk_count; i++) {
        set_dpi_replies[set_dpi_reply_count++] = data_chunks[i];
    }
    set_dpi_replies[set_dpi_reply_count++] =
        (Reply){.status = REPLY_OK, .length = 1, .bytes = {ONBOARD_MODE_ONBOARD}};
    Reply set_dpi_generic_ok = {.status = REPLY_OK};
    set_dpi_replies[set_dpi_reply_count++] = set_dpi_generic_ok; // startWrite
    for (size_t i = 0; i < 16; i++) {
        set_dpi_replies[set_dpi_reply_count++] = set_dpi_generic_ok; // writeData
    }
    set_dpi_replies[set_dpi_reply_count++] = set_dpi_generic_ok; // endWrite
    for (size_t i = 0; i < data_chunk_count; i++) {
        set_dpi_replies[set_dpi_reply_count++] = data_chunks[i]; // verify readback
    }
    set_dpi_replies[set_dpi_reply_count++] =
        (Reply){.status = REPLY_OK, .length = 2, .bytes = {0, 0}}; // get_current_onboard_profile
    if (set_dpi_reply_count > sizeof(set_dpi_replies) / sizeof(set_dpi_replies[0])) {
        fprintf(stderr, "run_set_dpi self-test reply buffer overflowed\n");
        return 1;
    }

    HidInterface set_dpi_interface = {0};
    set_dpi_interface.product_id = 0xC099;
    set_dpi_interface.vendor_id = LOGITECH_VID;
    Device set_dpi_device;
    memset(&set_dpi_device, 0, sizeof(set_dpi_device));
    set_dpi_device.iface = &set_dpi_interface;
    set_dpi_device.device_number = 0xFF;
    set_dpi_device.request_device_number = 0xFF;
    set_dpi_device.protocol = 4.2;
    set_dpi_device.feature_count = 2;
    set_dpi_device.features[0] = (Feature){.id = FEATURE_ADJUSTABLE_DPI, .index = 3};
    set_dpi_device.features[1] = (Feature){.id = FEATURE_ONBOARD_PROFILES, .index = 5};

    DiscoverDevicesTestContext set_dpi_discovery_context = {
        .devices = &set_dpi_device, .count = 1, .result = 1};
    discover_devices_for_options_impl = discover_devices_for_options_test_double;
    g_discover_devices_test_context = &set_dpi_discovery_context;

    ChannelRequestTestContext set_dpi_channel_context = {
        .replies = set_dpi_replies, .reply_count = set_dpi_reply_count, .calls = 0};
    channel_request_impl = channel_request_test_double;
    g_channel_request_test_context = &set_dpi_channel_context;

    const char *set_dpi_backup_path = "/tmp/lomps-selftest-set-dpi-backup.logiob";
    unlink(set_dpi_backup_path);

    Options set_dpi_options;
    memset(&set_dpi_options, 0, sizeof(set_dpi_options));
    set_dpi_options.device_index = -1;
    set_dpi_options.dpi_default = -1;
    set_dpi_options.dpi_shift = -1;
    set_dpi_options.yes = true;
    set_dpi_options.backup_path = set_dpi_backup_path;
    const char *set_dpi_positional = "800,1200,1600,2400,3200";
    set_dpi_options.positionals[0] = set_dpi_positional;
    set_dpi_options.positional_count = 1;

    int set_dpi_result = run_set_dpi(&set_dpi_options);
    unlink(set_dpi_backup_path);
    if (set_dpi_result != 0) {
        fprintf(stderr, "run_set_dpi happy-path self-test failed (result=%d)\n", set_dpi_result);
        return 1;
    }

    return 0;
}
