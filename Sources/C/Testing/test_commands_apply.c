#include "commands_apply.h"
#include "engine_boundary.h"
#include "g600.h"
#include "profile_io.h"
#include "test_doubles.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef struct {
    const bool *outcomes;
    size_t outcome_count;
    size_t calls;
} BatchWriterTestContext;

static int apply_context_create_failure(HidContext *context) {
    (void)context;
    return 0;
}

static bool batch_test_writer(void *context, const BatchSector *sector) {
    BatchWriterTestContext *test = (BatchWriterTestContext *)context;
    (void)sector;
    if (test->calls >= test->outcome_count) {
        return false;
    }
    return test->outcomes[test->calls++];
}

int test_commands_apply(void) {
    uint8_t unchanged_before[4] = {0x10, 0x20, 0x30, 0x40};
    uint8_t unchanged_after[4] = {0x10, 0x20, 0x30, 0x40};
    uint8_t changed_after[4] = {0x10, 0x20, 0x30, 0x41};
    bool batch_plan_ok =
        !batch_sector_changed(unchanged_before, unchanged_after, sizeof(unchanged_before)) &&
        batch_sector_changed(unchanged_before, changed_after, sizeof(unchanged_before)) &&
        !batch_sector_changed(NULL, changed_after, sizeof(unchanged_before)) &&
        !batch_sector_changed(unchanged_before, NULL, sizeof(unchanged_before)) &&
        batch_affected_sector_count(true, false) == 1 &&
        batch_affected_sector_count(false, true) == 1 &&
        batch_affected_sector_count(true, true) == 2 &&
        batch_affected_sector_count(false, false) == 0;
    if (!batch_plan_ok) {
        fprintf(stderr, "batch sector planning self-test failed\n");
        return 1;
    }
    EngineBoundaryWriteResult null_options_boundary;
    EngineBoundaryError null_options_error;
    if (engine_apply(NULL, &null_options_boundary, &null_options_error) != 1 ||
        null_options_boundary.profile != 0 || !null_options_boundary.dry_run) {
        fprintf(stderr, "engine_apply null-options self-test failed\n");
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

    uint8_t raw_record_spec[4] = {0};
    bool raw_record_ok = parse_batch_raw_record("80010004", raw_record_spec) &&
                         raw_record_spec[0] == 0x80 && raw_record_spec[1] == 0x01 &&
                         raw_record_spec[2] == 0x00 && raw_record_spec[3] == 0x04 &&
                         !parse_batch_raw_record("8001000", raw_record_spec) &&
                         !parse_batch_raw_record("8001000G", raw_record_spec) &&
                         !parse_batch_raw_record("ZZ000000", raw_record_spec) &&
                         !parse_batch_raw_record("  000000", raw_record_spec) &&
                         !parse_batch_raw_record("++000000", raw_record_spec) &&
                         !parse_batch_raw_record("-10010004", raw_record_spec) &&
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
        !parse_batch_profile_state(NULL, &profile_state_number, &profile_state_enabled) &&
        !parse_batch_profile_state(":enable", &profile_state_number, &profile_state_enabled) &&
        !parse_batch_profile_state("2:", &profile_state_number, &profile_state_enabled) &&
        !parse_batch_profile_state("12345678901234567:enable", &profile_state_number,
                                   &profile_state_enabled) &&
        !parse_batch_profile_state("-1:enable", &profile_state_number, &profile_state_enabled) &&
        !parse_batch_profile_state("ZZ:enable", &profile_state_number, &profile_state_enabled) &&
        !parse_batch_profile_state("5x:enable", &profile_state_number, &profile_state_enabled) &&
        !parse_batch_profile_state("0:enable", &profile_state_number, &profile_state_enabled) &&
        !parse_batch_profile_state("99:enable", &profile_state_number, &profile_state_enabled) &&
        !parse_batch_profile_state("abc:enable", &profile_state_number, &profile_state_enabled);
    if (!profile_state_parser_ok) {
        fprintf(stderr, "parse_batch_profile_state self-test failed\n");
        return 1;
    }

    bool operation_id_ok = batch_operation_id_is_safe("lope-20260101-120000-42") &&
                           batch_operation_id_is_safe("save_with.dot") &&
                           batch_operation_id_is_safe("save.with-dot_2") &&
                           !batch_operation_id_is_safe(NULL) && !batch_operation_id_is_safe("") &&
                           !batch_operation_id_is_safe("bad id!");
    char long_operation_id[97];
    memset(long_operation_id, 'a', sizeof(long_operation_id) - 1);
    long_operation_id[sizeof(long_operation_id) - 1] = '\0';
    operation_id_ok = operation_id_ok && !batch_operation_id_is_safe(long_operation_id);
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
    bool rgb_parser_ok =
        parse_batch_rgb_change("2:A1B2C3", &parsed_rgb_zone, parsed_rgb_color) &&
        parsed_rgb_zone == 2 && parsed_rgb_color[0] == 0xA1 && parsed_rgb_color[1] == 0xB2 &&
        parsed_rgb_color[2] == 0xC3 &&
        !parse_batch_rgb_change("3:GG0000", &parsed_rgb_zone, parsed_rgb_color) &&
        !parse_batch_rgb_change("1:ZZ0000", &parsed_rgb_zone, parsed_rgb_color) &&
        !parse_batch_rgb_change("1:1G0000", &parsed_rgb_zone, parsed_rgb_color) &&
        !parse_batch_rgb_change(NULL, &parsed_rgb_zone, parsed_rgb_color) &&
        !parse_batch_rgb_change(":AABBCC", &parsed_rgb_zone, parsed_rgb_color) &&
        !parse_batch_rgb_change("1:", &parsed_rgb_zone, parsed_rgb_color) &&
        !parse_batch_rgb_change("12345678901234567:AABBCC", &parsed_rgb_zone, parsed_rgb_color) &&
        !parse_batch_rgb_change("999:AABBCC", &parsed_rgb_zone, parsed_rgb_color) &&
        !parse_batch_rgb_change("5x:AABBCC", &parsed_rgb_zone, parsed_rgb_color) &&
        !parse_batch_rgb_change("0:AABBCC", &parsed_rgb_zone, parsed_rgb_color) &&
        !parse_batch_rgb_change("-1:AABBCC", &parsed_rgb_zone, parsed_rgb_color) &&
        !parse_batch_rgb_change("abc:AABBCC", &parsed_rgb_zone, parsed_rgb_color) &&
        !parse_batch_rgb_change("1:AABBC", &parsed_rgb_zone, parsed_rgb_color);
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

    bool button_parser_edge_cases_ok =
        !parse_batch_button_change(NULL, &parsed_button, &parsed_gshift, parsed_button_spec) &&
        !parse_batch_button_change("sideways:1:80010001", &parsed_button, &parsed_gshift,
                                   parsed_button_spec) &&
        !parse_batch_button_change("normal:80010004", &parsed_button, &parsed_gshift,
                                   parsed_button_spec) &&
        !parse_batch_button_change("normal::80010004", &parsed_button, &parsed_gshift,
                                   parsed_button_spec) &&
        !parse_batch_button_change("normal:3:", &parsed_button, &parsed_gshift,
                                   parsed_button_spec) &&
        !parse_batch_button_change("normal:12345678901234567:80010004", &parsed_button,
                                   &parsed_gshift, parsed_button_spec) &&
        !parse_batch_button_change("normal:0:80010004", &parsed_button, &parsed_gshift,
                                   parsed_button_spec) &&
        !parse_batch_button_change("normal:200000:80010004", &parsed_button, &parsed_gshift,
                                   parsed_button_spec) &&
        !parse_batch_button_change("normal:abc:80010004", &parsed_button, &parsed_gshift,
                                   parsed_button_spec) &&
        !parse_batch_button_change("normal:5x:80010004", &parsed_button, &parsed_gshift,
                                   parsed_button_spec) &&
        !parse_batch_button_change("normal:ZZ:80010004", &parsed_button, &parsed_gshift,
                                   parsed_button_spec) &&
        !parse_batch_button_change("normal:3:800100", &parsed_button, &parsed_gshift,
                                   parsed_button_spec);
    if (!button_parser_edge_cases_ok) {
        fprintf(stderr, "parse_batch_button_change edge-case self-test failed\n");
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

    const char *duplicate_gshift_change_a = "gshift:1:80010001";
    const char *duplicate_gshift_change_b = "gshift:1:80010002";
    apply_options.button_changes[0] = duplicate_gshift_change_a;
    apply_options.button_changes[1] = duplicate_gshift_change_b;
    apply_validation_ok = apply_validation_ok && run_apply(&apply_options) == 1;
    apply_options.button_changes[0] = duplicate_button_change_a;
    apply_options.button_changes[1] = duplicate_button_change_b;

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

    apply_options.dpi_shift = 0;
    apply_validation_ok = apply_validation_ok && run_apply(&apply_options) == 1;
    apply_options.dpi_shift = -1;

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

    // run_apply device-interaction paths, reusing the same 255-byte mock
    // profile sector, 132-byte single-header control sector, and 255-byte
    // two-header control sector patterns as the set-dpi and
    // set-profile-state self-tests.
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
        fprintf(stderr, "run_apply self-test failed to build mock sector-read replies\n");
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

    HidInterface profile_state_interface = {0};
    profile_state_interface.product_id = 0xC099;
    profile_state_interface.vendor_id = LOGITECH_VID;
    Device profile_state_device;
    memset(&profile_state_device, 0, sizeof(profile_state_device));
    profile_state_device.iface = &profile_state_interface;
    profile_state_device.device_number = 0xFF;
    profile_state_device.request_device_number = 0xFF;
    profile_state_device.protocol = 4.2;
    profile_state_device.feature_count = 1;
    profile_state_device.features[0] = (Feature){.id = FEATURE_ONBOARD_PROFILES, .index = 5};

    Reply set_dpi_sensor_count_1 = {.status = REPLY_OK, .length = 1, .bytes = {1}};
    Reply set_dpi_sensor_count_2 = {.status = REPLY_OK, .length = 1, .bytes = {2}};
    Reply set_dpi_sensor_list = {
        .status = REPLY_OK,
        .length = 11,
        .bytes = {0x00, 0x03, 0x20, 0x04, 0xB0, 0x06, 0x40, 0x09, 0x60, 0x0C, 0x80}};

    uint8_t set_dpi_crc_bad_sector[255];
    memcpy(set_dpi_crc_bad_sector, mock_sector, sizeof(set_dpi_crc_bad_sector));
    set_dpi_crc_bad_sector[254] ^= 0xFF;
    Reply set_dpi_crc_bad_data_chunks[32];
    size_t set_dpi_crc_bad_data_chunk_count = build_sector_read_replies(
        set_dpi_crc_bad_sector, sizeof(set_dpi_crc_bad_sector), set_dpi_crc_bad_data_chunks, 32);
    if (set_dpi_crc_bad_data_chunk_count == 0) {
        fprintf(stderr, "run_apply self-test failed to build corrupted mock sector-read replies\n");
        return 1;
    }

    uint8_t profile_state_control[255];
    build_mock_control_sector_two_profiles(profile_state_control);
    Reply profile_state_control_chunks[32];
    size_t profile_state_control_chunk_count = build_sector_read_replies(
        profile_state_control, sizeof(profile_state_control), profile_state_control_chunks, 32);
    if (profile_state_control_chunk_count == 0) {
        fprintf(stderr, "run_apply self-test failed to build mock control-sector replies\n");
        return 1;
    }

    uint8_t profile_state_bad_crc_control[255];
    memcpy(profile_state_bad_crc_control, profile_state_control,
           sizeof(profile_state_bad_crc_control));
    profile_state_bad_crc_control[254] ^= 0xFF;
    Reply profile_state_bad_crc_chunks[32];
    size_t profile_state_bad_crc_chunk_count = build_sector_read_replies(
        profile_state_bad_crc_control, sizeof(profile_state_bad_crc_control),
        profile_state_bad_crc_chunks, 32);
    if (profile_state_bad_crc_chunk_count == 0) {
        fprintf(stderr, "run_apply self-test failed to build corrupted control-sector replies\n");
        return 1;
    }

    uint8_t profile_state_after[255];
    memcpy(profile_state_after, profile_state_control, sizeof(profile_state_after));
    profile_state_after[6] = 1;
    sector_put_crc(profile_state_after, sizeof(profile_state_after));
    Reply profile_state_after_chunks[32];
    size_t profile_state_after_chunk_count = build_sector_read_replies(
        profile_state_after, sizeof(profile_state_after), profile_state_after_chunks, 32);
    if (profile_state_after_chunk_count == 0) {
        fprintf(stderr, "run_apply self-test failed to build post-write control replies\n");
        return 1;
    }

    HidInterface apply2_g600_interface = set_dpi_interface;
    apply2_g600_interface.product_id = G600_PRODUCT_ID;
    Device apply2_g600_device = set_dpi_device;
    apply2_g600_device.iface = &apply2_g600_interface;
    DiscoverDevicesTestContext apply2_g600_discovery = {
        .devices = &apply2_g600_device, .count = 1, .result = 1};
    discover_devices_for_options_impl = discover_devices_for_options_test_double;
    g_discover_devices_test_context = &apply2_g600_discovery;
    Options apply2_g600_options = {0};
    apply2_g600_options.profile = 1;
    apply2_g600_options.report_rate = "1000";
    apply2_g600_options.device_index = -1;
    apply2_g600_options.dpi_default = -1;
    apply2_g600_options.dpi_shift = -1;
    if (run_apply(&apply2_g600_options) != 1) {
        fprintf(stderr, "run_apply G600-report-rate-rejection self-test failed\n");
        return 1;
    }

    DiscoverDevicesTestContext apply2_discovery = {
        .devices = &set_dpi_device, .count = 1, .result = 1};
    g_discover_devices_test_context = &apply2_discovery;
    channel_request_impl = channel_request_test_double;

    const char *apply2_valid_button_change = "normal:1:80010004";

    ChannelRequestTestContext apply2_no_info_channel = {
        .replies = NULL, .reply_count = 0, .calls = 0};
    g_channel_request_test_context = &apply2_no_info_channel;
    Options apply2_no_info = {0};
    apply2_no_info.profile = 1;
    apply2_no_info.device_index = -1;
    apply2_no_info.dpi_default = -1;
    apply2_no_info.dpi_shift = -1;
    apply2_no_info.button_changes[0] = apply2_valid_button_change;
    apply2_no_info.button_change_count = 1;
    if (run_apply(&apply2_no_info) != 1) {
        fprintf(stderr, "run_apply get-profile-info-failure self-test failed\n");
        return 1;
    }

    Reply apply2_no_headers_replies[1] = {k_mock_get_info_reply};
    ChannelRequestTestContext apply2_no_headers_channel = {
        .replies = apply2_no_headers_replies, .reply_count = 1, .calls = 0};
    g_channel_request_test_context = &apply2_no_headers_channel;
    Options apply2_no_headers = {0};
    apply2_no_headers.profile = 1;
    apply2_no_headers.device_index = -1;
    apply2_no_headers.dpi_default = -1;
    apply2_no_headers.dpi_shift = -1;
    apply2_no_headers.button_changes[0] = apply2_valid_button_change;
    apply2_no_headers.button_change_count = 1;
    if (run_apply(&apply2_no_headers) != 1) {
        fprintf(stderr, "run_apply profile-headers-unreadable self-test failed\n");
        return 1;
    }

    Reply apply2_headers_replies[40];
    size_t apply2_headers_reply_count = 0;
    apply2_headers_replies[apply2_headers_reply_count++] = k_mock_get_info_reply;
    for (size_t i = 0; i < control_chunk_count; i++) {
        apply2_headers_replies[apply2_headers_reply_count++] = control_chunks[i];
    }
    size_t apply2_headers_prefix_count = apply2_headers_reply_count;

    Reply apply2_profile_load_fail_replies[40];
    memcpy(apply2_profile_load_fail_replies, apply2_headers_replies,
           apply2_headers_prefix_count * sizeof(Reply));
    ChannelRequestTestContext apply2_profile_load_fail_channel = {
        .replies = apply2_profile_load_fail_replies,
        .reply_count = apply2_headers_prefix_count,
        .calls = 0};
    g_channel_request_test_context = &apply2_profile_load_fail_channel;
    Options apply2_profile_load_fail = {0};
    apply2_profile_load_fail.profile = 1;
    apply2_profile_load_fail.device_index = -1;
    apply2_profile_load_fail.dpi_default = -1;
    apply2_profile_load_fail.dpi_shift = -1;
    apply2_profile_load_fail.button_changes[0] = apply2_valid_button_change;
    apply2_profile_load_fail.button_change_count = 1;
    if (run_apply(&apply2_profile_load_fail) != 1) {
        fprintf(stderr, "run_apply profile-load-failure self-test failed\n");
        return 1;
    }

    Reply apply2_out_of_range_replies[40];
    memcpy(apply2_out_of_range_replies, apply2_headers_replies,
           apply2_headers_prefix_count * sizeof(Reply));
    ChannelRequestTestContext apply2_out_of_range_channel = {.replies = apply2_out_of_range_replies,
                                                             .reply_count =
                                                                 apply2_headers_prefix_count,
                                                             .calls = 0};
    g_channel_request_test_context = &apply2_out_of_range_channel;
    Options apply2_out_of_range = {0};
    apply2_out_of_range.profile = 2;
    apply2_out_of_range.device_index = -1;
    apply2_out_of_range.dpi_default = -1;
    apply2_out_of_range.dpi_shift = -1;
    apply2_out_of_range.button_changes[0] = apply2_valid_button_change;
    apply2_out_of_range.button_change_count = 1;
    if (run_apply(&apply2_out_of_range) != 1) {
        fprintf(stderr, "run_apply profile-out-of-range self-test failed\n");
        return 1;
    }

    Reply apply2_bad_crc_replies[80];
    size_t apply2_bad_crc_reply_count = 0;
    for (size_t i = 0; i < apply2_headers_prefix_count; i++) {
        apply2_bad_crc_replies[apply2_bad_crc_reply_count++] = apply2_headers_replies[i];
    }
    for (size_t i = 0; i < set_dpi_crc_bad_data_chunk_count; i++) {
        apply2_bad_crc_replies[apply2_bad_crc_reply_count++] = set_dpi_crc_bad_data_chunks[i];
    }
    ChannelRequestTestContext apply2_bad_crc_channel = {
        .replies = apply2_bad_crc_replies, .reply_count = apply2_bad_crc_reply_count, .calls = 0};
    g_channel_request_test_context = &apply2_bad_crc_channel;
    Options apply2_bad_crc = {0};
    apply2_bad_crc.profile = 1;
    apply2_bad_crc.device_index = -1;
    apply2_bad_crc.dpi_default = -1;
    apply2_bad_crc.dpi_shift = -1;
    apply2_bad_crc.button_changes[0] = apply2_valid_button_change;
    apply2_bad_crc.button_change_count = 1;
    if (run_apply(&apply2_bad_crc) != 1) {
        fprintf(stderr, "run_apply invalid-profile-CRC self-test failed\n");
        return 1;
    }

    // Shared full-chain reply prefix (getInfo, headers, loaded profile
    // sector) for the remaining profile-sector cases.
    Reply apply2_loaded_replies[80];
    size_t apply2_loaded_reply_count = 0;
    for (size_t i = 0; i < apply2_headers_prefix_count; i++) {
        apply2_loaded_replies[apply2_loaded_reply_count++] = apply2_headers_replies[i];
    }
    for (size_t i = 0; i < data_chunk_count; i++) {
        apply2_loaded_replies[apply2_loaded_reply_count++] = data_chunks[i];
    }
    size_t apply2_loaded_prefix_count = apply2_loaded_reply_count;

    // A profile can have a valid normal button layout while its advertised
    // G-Shift bank is not validated. The command must reject only the
    // G-Shift edit, after reaching that specific layout check.
    uint8_t apply2_gshift_bad_sector[255];
    memcpy(apply2_gshift_bad_sector, mock_sector, sizeof(apply2_gshift_bad_sector));
    memset(apply2_gshift_bad_sector + 96, 0, 5 * 4);
    sector_put_crc(apply2_gshift_bad_sector, sizeof(apply2_gshift_bad_sector));
    Reply apply2_gshift_bad_chunks[32];
    size_t apply2_gshift_bad_chunk_count = build_sector_read_replies(
        apply2_gshift_bad_sector, sizeof(apply2_gshift_bad_sector), apply2_gshift_bad_chunks, 32);
    Reply apply2_gshift_replies[80];
    size_t apply2_gshift_reply_count = 0;
    Reply apply2_gshift_info = k_mock_get_info_reply;
    apply2_gshift_info.bytes[9] = 0x02;
    apply2_gshift_replies[apply2_gshift_reply_count++] = apply2_gshift_info;
    for (size_t i = 0; i < control_chunk_count; i++) {
        apply2_gshift_replies[apply2_gshift_reply_count++] = control_chunks[i];
    }
    for (size_t i = 0; i < apply2_gshift_bad_chunk_count; i++) {
        apply2_gshift_replies[apply2_gshift_reply_count++] = apply2_gshift_bad_chunks[i];
    }
    ChannelRequestTestContext apply2_gshift_channel = {
        .replies = apply2_gshift_replies, .reply_count = apply2_gshift_reply_count, .calls = 0};
    g_channel_request_test_context = &apply2_gshift_channel;
    Options apply2_gshift = {0};
    apply2_gshift.profile = 1;
    apply2_gshift.device_index = -1;
    apply2_gshift.dpi_default = -1;
    apply2_gshift.dpi_shift = -1;
    apply2_gshift.button_changes[0] = "gshift:1:80010002";
    apply2_gshift.button_change_count = 1;
    if (run_apply(&apply2_gshift) != 1) {
        fprintf(stderr, "run_apply unsupported-G-Shift-layout self-test failed\n");
        return 1;
    }

    // RGB records are independently validated. An unknown populated mode
    // should reach run_apply's RGB-layout rejection without invalidating the
    // otherwise writable button layout.
    uint8_t apply2_rgb_bad_sector[255];
    memcpy(apply2_rgb_bad_sector, mock_sector, sizeof(apply2_rgb_bad_sector));
    memset(apply2_rgb_bad_sector + RGB_PROFILE_BASE_OFFSET, 0xFF, RGB_PROFILE_RECORD_BYTES);
    sector_put_crc(apply2_rgb_bad_sector, sizeof(apply2_rgb_bad_sector));
    Reply apply2_rgb_bad_chunks[32];
    size_t apply2_rgb_bad_chunk_count = build_sector_read_replies(
        apply2_rgb_bad_sector, sizeof(apply2_rgb_bad_sector), apply2_rgb_bad_chunks, 32);
    Reply apply2_rgb_bad_replies[80];
    size_t apply2_rgb_bad_reply_count = 0;
    for (size_t i = 0; i < apply2_headers_prefix_count; i++) {
        apply2_rgb_bad_replies[apply2_rgb_bad_reply_count++] = apply2_headers_replies[i];
    }
    for (size_t i = 0; i < apply2_rgb_bad_chunk_count; i++) {
        apply2_rgb_bad_replies[apply2_rgb_bad_reply_count++] = apply2_rgb_bad_chunks[i];
    }
    ChannelRequestTestContext apply2_rgb_bad_channel = {
        .replies = apply2_rgb_bad_replies, .reply_count = apply2_rgb_bad_reply_count, .calls = 0};
    g_channel_request_test_context = &apply2_rgb_bad_channel;
    Options apply2_rgb_bad = {0};
    apply2_rgb_bad.profile = 1;
    apply2_rgb_bad.device_index = -1;
    apply2_rgb_bad.dpi_default = -1;
    apply2_rgb_bad.dpi_shift = -1;
    apply2_rgb_bad.rgb_changes[0] = "1:AABBCC";
    apply2_rgb_bad.rgb_change_count = 1;
    if (run_apply(&apply2_rgb_bad) != 1) {
        fprintf(stderr, "run_apply unsupported-RGB-layout self-test failed\n");
        return 1;
    }

    // Exercise both sides of the DPI layout/CRC guard. These cases stop in
    // preflight, before capability reads or any write is attempted.
    uint8_t apply2_dpi_bad_layout_sector[255];
    memcpy(apply2_dpi_bad_layout_sector, mock_sector, sizeof(apply2_dpi_bad_layout_sector));
    write_le16(apply2_dpi_bad_layout_sector + 3, 0);
    sector_put_crc(apply2_dpi_bad_layout_sector, sizeof(apply2_dpi_bad_layout_sector));
    Reply apply2_dpi_bad_layout_chunks[32];
    size_t apply2_dpi_bad_layout_count = build_sector_read_replies(
        apply2_dpi_bad_layout_sector, sizeof(apply2_dpi_bad_layout_sector),
        apply2_dpi_bad_layout_chunks, 32);
    Reply apply2_dpi_bad_layout_replies[80];
    size_t apply2_dpi_bad_layout_reply_count = 0;
    for (size_t i = 0; i < apply2_headers_prefix_count; i++) {
        apply2_dpi_bad_layout_replies[apply2_dpi_bad_layout_reply_count++] =
            apply2_headers_replies[i];
    }
    for (size_t i = 0; i < apply2_dpi_bad_layout_count; i++) {
        apply2_dpi_bad_layout_replies[apply2_dpi_bad_layout_reply_count++] =
            apply2_dpi_bad_layout_chunks[i];
    }
    ChannelRequestTestContext apply2_dpi_bad_layout_channel = {
        .replies = apply2_dpi_bad_layout_replies,
        .reply_count = apply2_dpi_bad_layout_reply_count,
        .calls = 0};
    g_channel_request_test_context = &apply2_dpi_bad_layout_channel;
    Options apply2_dpi_bad_layout = {0};
    apply2_dpi_bad_layout.profile = 1;
    apply2_dpi_bad_layout.device_index = -1;
    apply2_dpi_bad_layout.dpi_values = "800,1600";
    apply2_dpi_bad_layout.dpi_default = -1;
    apply2_dpi_bad_layout.dpi_shift = -1;
    if (run_apply(&apply2_dpi_bad_layout) != 1) {
        fprintf(stderr, "run_apply unsupported-DPI-layout self-test failed\n");
        return 1;
    }

    ChannelRequestTestContext apply2_dpi_bad_crc_channel = {
        .replies = apply2_bad_crc_replies, .reply_count = apply2_bad_crc_reply_count, .calls = 0};
    g_channel_request_test_context = &apply2_dpi_bad_crc_channel;
    Options apply2_dpi_bad_crc = {0};
    apply2_dpi_bad_crc.profile = 1;
    apply2_dpi_bad_crc.device_index = -1;
    apply2_dpi_bad_crc.dpi_values = "800,1600";
    apply2_dpi_bad_crc.dpi_default = -1;
    apply2_dpi_bad_crc.dpi_shift = -1;
    if (run_apply(&apply2_dpi_bad_crc) != 1) {
        fprintf(stderr, "run_apply invalid-DPI-profile-CRC self-test failed\n");
        return 1;
    }

    // Leaving both indexes unspecified uses the profile's validated default
    // and shift indexes. Preview mode reaches that fallback without requiring
    // a write transaction.
    Reply apply2_dpi_fallback_replies[96];
    size_t apply2_dpi_fallback_reply_count = apply2_loaded_prefix_count;
    memcpy(apply2_dpi_fallback_replies, apply2_loaded_replies,
           apply2_loaded_prefix_count * sizeof(Reply));
    apply2_dpi_fallback_replies[apply2_dpi_fallback_reply_count++] = set_dpi_sensor_count_1;
    apply2_dpi_fallback_replies[apply2_dpi_fallback_reply_count++] = set_dpi_sensor_list;
    ChannelRequestTestContext apply2_dpi_fallback_channel = {.replies = apply2_dpi_fallback_replies,
                                                             .reply_count =
                                                                 apply2_dpi_fallback_reply_count,
                                                             .calls = 0};
    g_channel_request_test_context = &apply2_dpi_fallback_channel;
    Options apply2_dpi_fallback = {0};
    apply2_dpi_fallback.profile = 1;
    apply2_dpi_fallback.device_index = -1;
    apply2_dpi_fallback.dpi_values = "800,1200,1600,2400,3200";
    apply2_dpi_fallback.dpi_default = -1;
    apply2_dpi_fallback.dpi_shift = -1;
    if (run_apply(&apply2_dpi_fallback) != 0) {
        fprintf(stderr, "run_apply DPI-index-fallback preview self-test failed\n");
        return 1;
    }

    Reply apply2_button_range_replies[80];
    memcpy(apply2_button_range_replies, apply2_loaded_replies,
           apply2_loaded_prefix_count * sizeof(Reply));
    ChannelRequestTestContext apply2_button_range_channel = {.replies = apply2_button_range_replies,
                                                             .reply_count =
                                                                 apply2_loaded_prefix_count,
                                                             .calls = 0};
    g_channel_request_test_context = &apply2_button_range_channel;
    Options apply2_button_range = {0};
    apply2_button_range.profile = 1;
    apply2_button_range.device_index = -1;
    apply2_button_range.dpi_default = -1;
    apply2_button_range.dpi_shift = -1;
    apply2_button_range.button_changes[0] = "normal:99:80010004";
    apply2_button_range.button_change_count = 1;
    if (run_apply(&apply2_button_range) != 1) {
        fprintf(stderr, "run_apply button-out-of-range self-test failed\n");
        return 1;
    }

    Reply apply2_rgb_range_replies[80];
    memcpy(apply2_rgb_range_replies, apply2_loaded_replies,
           apply2_loaded_prefix_count * sizeof(Reply));
    ChannelRequestTestContext apply2_rgb_range_channel = {
        .replies = apply2_rgb_range_replies, .reply_count = apply2_loaded_prefix_count, .calls = 0};
    g_channel_request_test_context = &apply2_rgb_range_channel;
    Options apply2_rgb_range = {0};
    apply2_rgb_range.profile = 1;
    apply2_rgb_range.device_index = -1;
    apply2_rgb_range.dpi_default = -1;
    apply2_rgb_range.dpi_shift = -1;
    apply2_rgb_range.rgb_changes[0] = "99:AABBCC";
    apply2_rgb_range.rgb_change_count = 1;
    if (run_apply(&apply2_rgb_range) != 1) {
        fprintf(stderr, "run_apply RGB-zone-out-of-range self-test failed\n");
        return 1;
    }

    DiscoverDevicesTestContext apply2_no_dpi_discovery = {
        .devices = &profile_state_device, .count = 1, .result = 1};
    g_discover_devices_test_context = &apply2_no_dpi_discovery;
    Reply apply2_no_dpi_replies[80];
    memcpy(apply2_no_dpi_replies, apply2_loaded_replies,
           apply2_loaded_prefix_count * sizeof(Reply));
    ChannelRequestTestContext apply2_no_dpi_channel = {
        .replies = apply2_no_dpi_replies, .reply_count = apply2_loaded_prefix_count, .calls = 0};
    g_channel_request_test_context = &apply2_no_dpi_channel;
    Options apply2_no_dpi = {0};
    apply2_no_dpi.profile = 1;
    apply2_no_dpi.device_index = -1;
    apply2_no_dpi.dpi_values = "800,1600";
    apply2_no_dpi.dpi_default = -1;
    apply2_no_dpi.dpi_shift = -1;
    if (run_apply(&apply2_no_dpi) != 1) {
        fprintf(stderr, "run_apply missing-ADJUSTABLE_DPI-feature self-test failed\n");
        return 1;
    }
    g_discover_devices_test_context = &apply2_discovery;

    Reply apply2_multi_sensor_replies[80];
    size_t apply2_multi_sensor_reply_count = 0;
    for (size_t i = 0; i < apply2_loaded_prefix_count; i++) {
        apply2_multi_sensor_replies[apply2_multi_sensor_reply_count++] = apply2_loaded_replies[i];
    }
    apply2_multi_sensor_replies[apply2_multi_sensor_reply_count++] = set_dpi_sensor_count_2;
    apply2_multi_sensor_replies[apply2_multi_sensor_reply_count++] = set_dpi_sensor_list;
    ChannelRequestTestContext apply2_multi_sensor_channel = {.replies = apply2_multi_sensor_replies,
                                                             .reply_count =
                                                                 apply2_multi_sensor_reply_count,
                                                             .calls = 0};
    g_channel_request_test_context = &apply2_multi_sensor_channel;
    Options apply2_multi_sensor = {0};
    apply2_multi_sensor.profile = 1;
    apply2_multi_sensor.device_index = -1;
    apply2_multi_sensor.dpi_values = "800,1600";
    apply2_multi_sensor.dpi_default = -1;
    apply2_multi_sensor.dpi_shift = -1;
    if (run_apply(&apply2_multi_sensor) != 1) {
        fprintf(stderr, "run_apply multi-sensor-DPI self-test failed\n");
        return 1;
    }

    Reply apply2_dpi_unsupported_replies[80];
    size_t apply2_dpi_unsupported_reply_count = 0;
    for (size_t i = 0; i < apply2_loaded_prefix_count; i++) {
        apply2_dpi_unsupported_replies[apply2_dpi_unsupported_reply_count++] =
            apply2_loaded_replies[i];
    }
    apply2_dpi_unsupported_replies[apply2_dpi_unsupported_reply_count++] = set_dpi_sensor_count_1;
    apply2_dpi_unsupported_replies[apply2_dpi_unsupported_reply_count++] = set_dpi_sensor_list;
    ChannelRequestTestContext apply2_dpi_unsupported_channel = {
        .replies = apply2_dpi_unsupported_replies,
        .reply_count = apply2_dpi_unsupported_reply_count,
        .calls = 0};
    g_channel_request_test_context = &apply2_dpi_unsupported_channel;
    Options apply2_dpi_unsupported = {0};
    apply2_dpi_unsupported.profile = 1;
    apply2_dpi_unsupported.device_index = -1;
    apply2_dpi_unsupported.dpi_values = "900,1000";
    apply2_dpi_unsupported.dpi_default = -1;
    apply2_dpi_unsupported.dpi_shift = -1;
    if (run_apply(&apply2_dpi_unsupported) != 1) {
        fprintf(stderr, "run_apply unsupported-DPI-value self-test failed\n");
        return 1;
    }

    Reply apply2_dpi_range_replies[80];
    size_t apply2_dpi_range_reply_count = 0;
    for (size_t i = 0; i < apply2_loaded_prefix_count; i++) {
        apply2_dpi_range_replies[apply2_dpi_range_reply_count++] = apply2_loaded_replies[i];
    }
    apply2_dpi_range_replies[apply2_dpi_range_reply_count++] = set_dpi_sensor_count_1;
    apply2_dpi_range_replies[apply2_dpi_range_reply_count++] = set_dpi_sensor_list;
    ChannelRequestTestContext apply2_dpi_range_channel = {.replies = apply2_dpi_range_replies,
                                                          .reply_count =
                                                              apply2_dpi_range_reply_count,
                                                          .calls = 0};
    g_channel_request_test_context = &apply2_dpi_range_channel;
    Options apply2_dpi_range = {0};
    apply2_dpi_range.profile = 1;
    apply2_dpi_range.device_index = -1;
    apply2_dpi_range.dpi_values = "800,1600";
    apply2_dpi_range.dpi_default = 5;
    apply2_dpi_range.dpi_shift = -1;
    if (run_apply(&apply2_dpi_range) != 1) {
        fprintf(stderr, "run_apply DPI-index-out-of-range self-test failed\n");
        return 1;
    }

    // Shared full-chain reply prefix (getInfo + two-header control sector)
    // for the profile-state-only cases, none of which touch the profile
    // sector at all.
    Reply apply2_control_loaded_replies[40];
    size_t apply2_control_loaded_reply_count = 0;
    apply2_control_loaded_replies[apply2_control_loaded_reply_count++] = k_mock_get_info_reply;
    for (size_t i = 0; i < profile_state_control_chunk_count; i++) {
        apply2_control_loaded_replies[apply2_control_loaded_reply_count++] =
            profile_state_control_chunks[i];
    }
    size_t apply2_control_loaded_prefix_count = apply2_control_loaded_reply_count;

    Reply apply2_state_range_replies[40];
    memcpy(apply2_state_range_replies, apply2_control_loaded_replies,
           apply2_control_loaded_prefix_count * sizeof(Reply));
    ChannelRequestTestContext apply2_state_range_channel = {.replies = apply2_state_range_replies,
                                                            .reply_count =
                                                                apply2_control_loaded_prefix_count,
                                                            .calls = 0};
    g_channel_request_test_context = &apply2_state_range_channel;
    Options apply2_state_range = {0};
    apply2_state_range.profile = 1;
    apply2_state_range.device_index = -1;
    apply2_state_range.dpi_default = -1;
    apply2_state_range.dpi_shift = -1;
    apply2_state_range.profile_state_changes[0] = "3:enable";
    apply2_state_range.profile_state_change_count = 1;
    if (run_apply(&apply2_state_range) != 1) {
        fprintf(stderr, "run_apply profile-state-out-of-range self-test failed\n");
        return 1;
    }

    Reply apply2_all_disabled_replies[40];
    memcpy(apply2_all_disabled_replies, apply2_control_loaded_replies,
           apply2_control_loaded_prefix_count * sizeof(Reply));
    ChannelRequestTestContext apply2_all_disabled_channel = {.replies = apply2_all_disabled_replies,
                                                             .reply_count =
                                                                 apply2_control_loaded_prefix_count,
                                                             .calls = 0};
    g_channel_request_test_context = &apply2_all_disabled_channel;
    Options apply2_all_disabled = {0};
    apply2_all_disabled.profile = 1;
    apply2_all_disabled.device_index = -1;
    apply2_all_disabled.dpi_default = -1;
    apply2_all_disabled.dpi_shift = -1;
    apply2_all_disabled.profile_state_changes[0] = "1:disable";
    apply2_all_disabled.profile_state_change_count = 1;
    if (run_apply(&apply2_all_disabled) != 1) {
        fprintf(stderr, "run_apply all-profiles-disabled self-test failed\n");
        return 1;
    }

    Reply apply2_noop_replies[40];
    memcpy(apply2_noop_replies, apply2_control_loaded_replies,
           apply2_control_loaded_prefix_count * sizeof(Reply));
    ChannelRequestTestContext apply2_noop_channel = {.replies = apply2_noop_replies,
                                                     .reply_count =
                                                         apply2_control_loaded_prefix_count,
                                                     .calls = 0};
    g_channel_request_test_context = &apply2_noop_channel;
    Options apply2_noop = {0};
    apply2_noop.profile = 1;
    apply2_noop.device_index = -1;
    apply2_noop.dpi_default = -1;
    apply2_noop.dpi_shift = -1;
    apply2_noop.profile_state_changes[0] = "1:enable";
    apply2_noop.profile_state_change_count = 1;
    if (run_apply(&apply2_noop) != 0) {
        fprintf(stderr, "run_apply no-effective-changes self-test failed\n");
        return 1;
    }

    Reply apply2_preview_replies[40];
    memcpy(apply2_preview_replies, apply2_control_loaded_replies,
           apply2_control_loaded_prefix_count * sizeof(Reply));
    ChannelRequestTestContext apply2_preview_channel = {.replies = apply2_preview_replies,
                                                        .reply_count =
                                                            apply2_control_loaded_prefix_count,
                                                        .calls = 0};
    g_channel_request_test_context = &apply2_preview_channel;
    Options apply2_preview = {0};
    apply2_preview.profile = 1;
    apply2_preview.device_index = -1;
    apply2_preview.dpi_default = -1;
    apply2_preview.dpi_shift = -1;
    apply2_preview.profile_state_changes[0] = "2:enable";
    apply2_preview.profile_state_change_count = 1;
    apply2_preview.yes = false;
    if (run_apply(&apply2_preview) != 0) {
        fprintf(stderr, "run_apply preview-mode self-test failed\n");
        return 1;
    }

    Reply apply2_mode_switch_replies[40];
    memcpy(apply2_mode_switch_replies, apply2_control_loaded_replies,
           apply2_control_loaded_prefix_count * sizeof(Reply));
    apply2_mode_switch_replies[apply2_control_loaded_prefix_count] = k_mock_host_mode_reply;
    ChannelRequestTestContext apply2_mode_switch_channel = {
        .replies = apply2_mode_switch_replies,
        .reply_count = apply2_control_loaded_prefix_count + 1,
        .calls = 0};
    g_channel_request_test_context = &apply2_mode_switch_channel;
    Options apply2_mode_switch = {0};
    apply2_mode_switch.profile = 1;
    apply2_mode_switch.device_index = -1;
    apply2_mode_switch.dpi_default = -1;
    apply2_mode_switch.dpi_shift = -1;
    apply2_mode_switch.profile_state_changes[0] = "2:enable";
    apply2_mode_switch.profile_state_change_count = 1;
    apply2_mode_switch.yes = true;
    if (run_apply(&apply2_mode_switch) != 1) {
        fprintf(stderr, "run_apply onboard-mode-switch-failure self-test failed\n");
        return 1;
    }

    Reply apply2_long_directory_replies[40];
    memcpy(apply2_long_directory_replies, apply2_control_loaded_replies,
           apply2_control_loaded_prefix_count * sizeof(Reply));
    apply2_long_directory_replies[apply2_control_loaded_prefix_count] = k_mock_onboard_mode_reply;
    ChannelRequestTestContext apply2_long_directory_channel = {
        .replies = apply2_long_directory_replies,
        .reply_count = apply2_control_loaded_prefix_count + 1,
        .calls = 0};
    g_channel_request_test_context = &apply2_long_directory_channel;
    char apply2_long_directory[600];
    memset(apply2_long_directory, 'a', sizeof(apply2_long_directory) - 1);
    apply2_long_directory[sizeof(apply2_long_directory) - 1] = '\0';
    Options apply2_long_directory_options = {0};
    apply2_long_directory_options.profile = 1;
    apply2_long_directory_options.device_index = -1;
    apply2_long_directory_options.dpi_default = -1;
    apply2_long_directory_options.dpi_shift = -1;
    apply2_long_directory_options.profile_state_changes[0] = "2:enable";
    apply2_long_directory_options.profile_state_change_count = 1;
    apply2_long_directory_options.yes = true;
    apply2_long_directory_options.backup_directory = apply2_long_directory;
    apply2_long_directory_options.operation_id = "lope-apply-long-directory-test";
    if (run_apply(&apply2_long_directory_options) != 1) {
        fprintf(stderr, "run_apply backup-path-too-long self-test failed\n");
        return 1;
    }

    Reply apply2_backup_fail_replies[40];
    memcpy(apply2_backup_fail_replies, apply2_control_loaded_replies,
           apply2_control_loaded_prefix_count * sizeof(Reply));
    apply2_backup_fail_replies[apply2_control_loaded_prefix_count] = k_mock_onboard_mode_reply;
    ChannelRequestTestContext apply2_backup_fail_channel = {
        .replies = apply2_backup_fail_replies,
        .reply_count = apply2_control_loaded_prefix_count + 1,
        .calls = 0};
    g_channel_request_test_context = &apply2_backup_fail_channel;
    Options apply2_backup_fail = {0};
    apply2_backup_fail.profile = 1;
    apply2_backup_fail.device_index = -1;
    apply2_backup_fail.dpi_default = -1;
    apply2_backup_fail.dpi_shift = -1;
    apply2_backup_fail.profile_state_changes[0] = "2:enable";
    apply2_backup_fail.profile_state_change_count = 1;
    apply2_backup_fail.yes = true;
    apply2_backup_fail.backup_directory = "/nonexistent-lope-test-directory";
    apply2_backup_fail.operation_id = "lope-apply-backup-fail-test";
    if (run_apply(&apply2_backup_fail) != 1) {
        fprintf(stderr, "run_apply backup-write-failure self-test failed\n");
        return 1;
    }

    // execute_batch_sector_plan failure: the profile sector loads fine but
    // the actual hardware write never gets a reply.
    Reply apply2_plan_fail_replies[80];
    size_t apply2_plan_fail_reply_count = 0;
    for (size_t i = 0; i < apply2_loaded_prefix_count; i++) {
        apply2_plan_fail_replies[apply2_plan_fail_reply_count++] = apply2_loaded_replies[i];
    }
    apply2_plan_fail_replies[apply2_plan_fail_reply_count++] = k_mock_onboard_mode_reply;
    ChannelRequestTestContext apply2_plan_fail_channel = {.replies = apply2_plan_fail_replies,
                                                          .reply_count =
                                                              apply2_plan_fail_reply_count,
                                                          .calls = 0};
    g_channel_request_test_context = &apply2_plan_fail_channel;
    const char *apply2_plan_fail_directory = "/tmp";
    Options apply2_plan_fail = {0};
    apply2_plan_fail.profile = 1;
    apply2_plan_fail.device_index = -1;
    apply2_plan_fail.dpi_default = -1;
    apply2_plan_fail.dpi_shift = -1;
    apply2_plan_fail.button_changes[0] = "normal:1:80010002";
    apply2_plan_fail.button_change_count = 1;
    apply2_plan_fail.yes = true;
    apply2_plan_fail.backup_directory = apply2_plan_fail_directory;
    apply2_plan_fail.operation_id = "lope-apply-plan-fail-test";
    char apply2_plan_fail_backup_path[512];
    make_batch_backup_path(apply2_plan_fail_directory, apply2_plan_fail.operation_id,
                           apply2_plan_fail_backup_path);
    unlink(apply2_plan_fail_backup_path);
    int apply2_plan_fail_result = run_apply(&apply2_plan_fail);
    unlink(apply2_plan_fail_backup_path);
    if (apply2_plan_fail_result != 1) {
        fprintf(stderr, "run_apply sector-write-failure self-test failed\n");
        return 1;
    }

    // Happy path: change button 1 on the profile sector, exercising the
    // full backup + write + verify-readback path end to end.
    uint8_t apply2_happy_after[255];
    memcpy(apply2_happy_after, mock_sector, sizeof(apply2_happy_after));
    apply2_happy_after[32] = 0x80;
    apply2_happy_after[33] = 0x01;
    apply2_happy_after[34] = 0x00;
    apply2_happy_after[35] = 0x02;
    apply2_happy_after[96] = 0x80;
    apply2_happy_after[97] = 0x01;
    apply2_happy_after[98] = 0x00;
    apply2_happy_after[99] = 0x10;
    sector_put_crc(apply2_happy_after, sizeof(apply2_happy_after));
    Reply apply2_happy_after_chunks[32];
    size_t apply2_happy_after_chunk_count = build_sector_read_replies(
        apply2_happy_after, sizeof(apply2_happy_after), apply2_happy_after_chunks, 32);
    if (apply2_happy_after_chunk_count == 0) {
        fprintf(stderr,
                "run_apply self-test failed to build post-write mock sector-read replies\n");
        return 1;
    }
    Reply apply2_happy_replies[128];
    size_t apply2_happy_reply_count = 0;
    for (size_t i = 0; i < apply2_loaded_prefix_count; i++) {
        apply2_happy_replies[apply2_happy_reply_count++] = apply2_loaded_replies[i];
    }
    apply2_happy_replies[apply2_happy_reply_count++] = k_mock_onboard_mode_reply;
    apply2_happy_replies[apply2_happy_reply_count++] = k_mock_generic_ok_reply; // startWrite
    for (size_t i = 0; i < 16; i++) {
        apply2_happy_replies[apply2_happy_reply_count++] = k_mock_generic_ok_reply; // writeData
    }
    apply2_happy_replies[apply2_happy_reply_count++] = k_mock_generic_ok_reply; // endWrite
    for (size_t i = 0; i < apply2_happy_after_chunk_count; i++) {
        apply2_happy_replies[apply2_happy_reply_count++] = apply2_happy_after_chunks[i]; // verify
    }
    if (apply2_happy_reply_count > sizeof(apply2_happy_replies) / sizeof(apply2_happy_replies[0])) {
        fprintf(stderr, "run_apply self-test reply buffer overflowed\n");
        return 1;
    }
    ChannelRequestTestContext apply2_happy_channel = {
        .replies = apply2_happy_replies, .reply_count = apply2_happy_reply_count, .calls = 0};
    g_channel_request_test_context = &apply2_happy_channel;
    const char *apply2_happy_directory = "/tmp";
    Options apply2_happy = {0};
    apply2_happy.profile = 1;
    apply2_happy.device_index = -1;
    apply2_happy.dpi_default = -1;
    apply2_happy.dpi_shift = -1;
    apply2_happy.button_changes[0] = "normal:1:80010002";
    apply2_happy.button_changes[1] = "gshift:1:80010010";
    apply2_happy.button_change_count = 2;
    apply2_happy.yes = true;
    apply2_happy.backup_directory = apply2_happy_directory;
    apply2_happy.operation_id = "lope-apply-happy-test";
    char apply2_happy_backup_path[512];
    make_batch_backup_path(apply2_happy_directory, apply2_happy.operation_id,
                           apply2_happy_backup_path);
    unlink(apply2_happy_backup_path);
    EngineBoundaryWriteResult apply2_happy_boundary;
    EngineBoundaryError apply2_happy_error;
    int apply2_happy_result =
        engine_apply(&apply2_happy, &apply2_happy_boundary, &apply2_happy_error);
    unlink(apply2_happy_backup_path);
    if (apply2_happy_result != 0 || !apply2_happy_boundary.completed ||
        !apply2_happy_boundary.changed || apply2_happy_boundary.planned_count != 1 ||
        apply2_happy_boundary.verified_count != 1 ||
        apply2_happy_error.code != ENGINE_BOUNDARY_ERROR_NONE) {
        fprintf(stderr, "run_apply happy-path self-test failed (result=%d)\n", apply2_happy_result);
        return 1;
    }

    // run_apply's own select_device failure (distinct from the earlier
    // pre-discovery validation-only cases).
    DiscoverDevicesTestContext apply2_no_device_discovery = {
        .devices = NULL, .count = 0, .result = 1};
    g_discover_devices_test_context = &apply2_no_device_discovery;
    Options apply2_no_device = {0};
    apply2_no_device.profile = 1;
    apply2_no_device.device_index = -1;
    apply2_no_device.dpi_default = -1;
    apply2_no_device.dpi_shift = -1;
    apply2_no_device.button_changes[0] = apply2_valid_button_change;
    apply2_no_device.button_change_count = 1;
    if (run_apply(&apply2_no_device) != 1) {
        fprintf(stderr, "run_apply select-device-failure self-test failed\n");
        return 1;
    }
    g_discover_devices_test_context = &apply2_discovery;

    Device apply2_unstable_device = set_dpi_device;
    apply2_unstable_device.iface = NULL;
    DiscoverDevicesTestContext apply2_unstable_discovery = {
        .devices = &apply2_unstable_device, .count = 1, .result = 1};
    g_discover_devices_test_context = &apply2_unstable_discovery;
    Options apply2_unstable = {0};
    apply2_unstable.profile = 1;
    apply2_unstable.device_index = -1;
    apply2_unstable.dpi_default = -1;
    apply2_unstable.dpi_shift = -1;
    apply2_unstable.button_changes[0] = apply2_valid_button_change;
    apply2_unstable.button_change_count = 1;
    EngineBoundaryWriteResult apply2_unstable_boundary;
    EngineBoundaryError apply2_unstable_error;
    if (engine_apply(&apply2_unstable, &apply2_unstable_boundary, &apply2_unstable_error) != 1 ||
        apply2_unstable_error.code != ENGINE_BOUNDARY_ERROR_DEVICE_NOT_FOUND) {
        fprintf(stderr, "engine_apply unstable-device self-test failed\n");
        return 1;
    }
    g_discover_devices_test_context = &apply2_discovery;

    // G600 dispatch: run_apply hands off to run_g600_apply for a button
    // change once it recognizes the product ID.
    Reply apply2_g600_dispatch_replies[8] = {{.status = REPLY_TIMEOUT}, {.status = REPLY_TIMEOUT},
                                             {.status = REPLY_TIMEOUT}, {.status = REPLY_TIMEOUT},
                                             {.status = REPLY_TIMEOUT}, {.status = REPLY_TIMEOUT},
                                             {.status = REPLY_TIMEOUT}, {.status = REPLY_TIMEOUT}};
    ChannelRequestTestContext apply2_g600_dispatch_channel = {
        .replies = apply2_g600_dispatch_replies, .reply_count = 8, .calls = 0};
    g_channel_request_test_context = &apply2_g600_dispatch_channel;
    g_discover_devices_test_context = &apply2_g600_discovery;
    Options apply2_g600_dispatch_options = {0};
    apply2_g600_dispatch_options.profile = 1;
    apply2_g600_dispatch_options.device_index = -1;
    apply2_g600_dispatch_options.dpi_default = -1;
    apply2_g600_dispatch_options.dpi_shift = -1;
    apply2_g600_dispatch_options.button_changes[0] = apply2_valid_button_change;
    apply2_g600_dispatch_options.button_change_count = 1;
    // run_g600_apply's own device I/O fails against these timeouts, so this
    // only exercises that run_apply reaches and returns the dispatch, not
    // a successful G600 write (which test_g600.c covers directly).
    run_apply(&apply2_g600_dispatch_options);
    EngineBoundaryWriteResult g600_boundary;
    EngineBoundaryError g600_error;
    if (engine_apply(&apply2_g600_dispatch_options, &g600_boundary, &g600_error) != 1 ||
        g600_error.code != ENGINE_BOUNDARY_ERROR_UNSUPPORTED) {
        fprintf(stderr, "engine_apply G600 structured-output self-test failed\n");
        return 1;
    }
    g_discover_devices_test_context = &apply2_discovery;

    // profile-state validation failure inside run_apply's own control read
    // (distinct from run_set_profile_state's equivalent check).
    Reply apply2_state_bad_crc_replies[40];
    size_t apply2_state_bad_crc_reply_count = 0;
    apply2_state_bad_crc_replies[apply2_state_bad_crc_reply_count++] = k_mock_get_info_reply;
    for (size_t i = 0; i < profile_state_bad_crc_chunk_count; i++) {
        apply2_state_bad_crc_replies[apply2_state_bad_crc_reply_count++] =
            profile_state_bad_crc_chunks[i];
    }
    ChannelRequestTestContext apply2_state_bad_crc_channel = {
        .replies = apply2_state_bad_crc_replies,
        .reply_count = apply2_state_bad_crc_reply_count,
        .calls = 0};
    g_channel_request_test_context = &apply2_state_bad_crc_channel;
    Options apply2_state_bad_crc = {0};
    apply2_state_bad_crc.profile = 1;
    apply2_state_bad_crc.device_index = -1;
    apply2_state_bad_crc.dpi_default = -1;
    apply2_state_bad_crc.dpi_shift = -1;
    apply2_state_bad_crc.profile_state_changes[0] = "1:enable";
    apply2_state_bad_crc.profile_state_change_count = 1;
    if (run_apply(&apply2_state_bad_crc) != 1) {
        fprintf(stderr, "run_apply profile-state-control-validation-failure self-test failed\n");
        return 1;
    }

    // report-rate handling inside run_apply: the mock device has no
    // report-rate feature, so this exercises the failure path only.
    Reply apply2_report_rate_replies[80];
    memcpy(apply2_report_rate_replies, apply2_loaded_replies,
           apply2_loaded_prefix_count * sizeof(Reply));
    ChannelRequestTestContext apply2_report_rate_channel = {.replies = apply2_report_rate_replies,
                                                            .reply_count =
                                                                apply2_loaded_prefix_count,
                                                            .calls = 0};
    g_channel_request_test_context = &apply2_report_rate_channel;
    Options apply2_report_rate = {0};
    apply2_report_rate.profile = 1;
    apply2_report_rate.device_index = -1;
    apply2_report_rate.dpi_default = -1;
    apply2_report_rate.dpi_shift = -1;
    apply2_report_rate.button_changes[0] = apply2_valid_button_change;
    apply2_report_rate.button_change_count = 1;
    apply2_report_rate.report_rate = "1000";
    if (run_apply(&apply2_report_rate) != 1) {
        fprintf(stderr, "run_apply report-rate-unavailable self-test failed\n");
        return 1;
    }

    // A readable extended report-rate feature exercises the representable
    // profile-interval path and keeps polling-rate edits covered separately
    // from the failure case above.
    Device apply2_report_device = set_dpi_device;
    apply2_report_device.feature_count = 3;
    apply2_report_device.features[2] = (Feature){.id = FEATURE_EXTENDED_REPORT_RATE, .index = 6};
    DiscoverDevicesTestContext apply2_report_discovery = {
        .devices = &apply2_report_device, .count = 1, .result = 1};
    g_discover_devices_test_context = &apply2_report_discovery;
    uint8_t apply2_report_after[255];
    memcpy(apply2_report_after, mock_sector, sizeof(apply2_report_after));
    apply2_report_after[0] = 1;
    sector_put_crc(apply2_report_after, sizeof(apply2_report_after));
    Reply apply2_report_after_chunks[32];
    size_t apply2_report_after_chunk_count = build_sector_read_replies(
        apply2_report_after, sizeof(apply2_report_after), apply2_report_after_chunks, 32);
    Reply apply2_report_success_replies[128];
    size_t apply2_report_success_count = 0;
    for (size_t i = 0; i < apply2_loaded_prefix_count; i++) {
        apply2_report_success_replies[apply2_report_success_count++] = apply2_loaded_replies[i];
    }
    apply2_report_success_replies[apply2_report_success_count++] =
        (Reply){.status = REPLY_OK, .length = 2, .bytes = {0x00, 0x0F}};
    apply2_report_success_replies[apply2_report_success_count++] =
        (Reply){.status = REPLY_OK, .length = 1, .bytes = {3}};
    apply2_report_success_replies[apply2_report_success_count++] = k_mock_onboard_mode_reply;
    apply2_report_success_replies[apply2_report_success_count++] = k_mock_generic_ok_reply;
    for (size_t i = 0; i < 16; i++) {
        apply2_report_success_replies[apply2_report_success_count++] = k_mock_generic_ok_reply;
    }
    apply2_report_success_replies[apply2_report_success_count++] = k_mock_generic_ok_reply;
    for (size_t i = 0; i < apply2_report_after_chunk_count; i++) {
        apply2_report_success_replies[apply2_report_success_count++] =
            apply2_report_after_chunks[i];
    }
    ChannelRequestTestContext apply2_report_success_channel = {
        .replies = apply2_report_success_replies,
        .reply_count = apply2_report_success_count,
        .calls = 0};
    g_channel_request_test_context = &apply2_report_success_channel;
    Options apply2_report_success = {0};
    apply2_report_success.profile = 1;
    apply2_report_success.device_index = -1;
    apply2_report_success.dpi_default = -1;
    apply2_report_success.dpi_shift = -1;
    apply2_report_success.report_rate = "1000";
    apply2_report_success.yes = true;
    apply2_report_success.backup_directory = "/tmp";
    apply2_report_success.operation_id = "lope-apply-report-rate-test";
    char apply2_report_success_backup_path[512];
    make_batch_backup_path("/tmp", apply2_report_success.operation_id,
                           apply2_report_success_backup_path);
    unlink(apply2_report_success_backup_path);
    if (run_apply(&apply2_report_success) != 0) {
        fprintf(stderr, "run_apply report-rate success self-test failed\n");
        return 1;
    }
    unlink(apply2_report_success_backup_path);
    g_discover_devices_test_context = &apply2_discovery;

    // execute_batch_sector_plan's own verify-readback failure: the write
    // itself succeeds, but nothing answers the follow-up readSector calls.
    Reply apply2_verify_fail_replies[80];
    size_t apply2_verify_fail_reply_count = 0;
    for (size_t i = 0; i < apply2_loaded_prefix_count; i++) {
        apply2_verify_fail_replies[apply2_verify_fail_reply_count++] = apply2_loaded_replies[i];
    }
    apply2_verify_fail_replies[apply2_verify_fail_reply_count++] = k_mock_onboard_mode_reply;
    apply2_verify_fail_replies[apply2_verify_fail_reply_count++] =
        k_mock_generic_ok_reply; // startWrite
    for (size_t i = 0; i < 16; i++) {
        apply2_verify_fail_replies[apply2_verify_fail_reply_count++] =
            k_mock_generic_ok_reply; // writeData
    }
    apply2_verify_fail_replies[apply2_verify_fail_reply_count++] =
        k_mock_generic_ok_reply; // endWrite
    ChannelRequestTestContext apply2_verify_fail_channel = {.replies = apply2_verify_fail_replies,
                                                            .reply_count =
                                                                apply2_verify_fail_reply_count,
                                                            .calls = 0};
    g_channel_request_test_context = &apply2_verify_fail_channel;
    const char *apply2_verify_fail_directory = "/tmp";
    Options apply2_verify_fail = {0};
    apply2_verify_fail.profile = 1;
    apply2_verify_fail.device_index = -1;
    apply2_verify_fail.dpi_default = -1;
    apply2_verify_fail.dpi_shift = -1;
    apply2_verify_fail.button_changes[0] = "normal:1:80010002";
    apply2_verify_fail.button_change_count = 1;
    apply2_verify_fail.yes = true;
    apply2_verify_fail.backup_directory = apply2_verify_fail_directory;
    apply2_verify_fail.operation_id = "lope-apply-verify-fail-test";
    char apply2_verify_fail_backup_path[512];
    make_batch_backup_path(apply2_verify_fail_directory, apply2_verify_fail.operation_id,
                           apply2_verify_fail_backup_path);
    unlink(apply2_verify_fail_backup_path);
    int apply2_verify_fail_result = run_apply(&apply2_verify_fail);
    unlink(apply2_verify_fail_backup_path);
    if (apply2_verify_fail_result != 1) {
        fprintf(stderr, "run_apply verify-readback-failure self-test failed\n");
        return 1;
    }

    // Combined happy path: an RGB zone change and a DPI stage change (both
    // on the profile sector) together with a profile-state change (on the
    // control sector), producing two verified sector writes plus the
    // post-write DPI sync call. The expected post-write bytes are computed
    // with the same detection/write helpers run_apply itself uses, rather
    // than hand-encoded, so this doesn't duplicate their internal format.
    // (Independent byte-level correctness of those helpers is asserted
    // against hand-picked literals in test_profile_io.c; this test only
    // exercises run_apply's own wiring and write/verify plumbing.)
    Profile apply2_scratch;
    memset(&apply2_scratch, 0, sizeof(apply2_scratch));
    apply2_scratch.info.profile_format = 5;
    apply2_scratch.info.button_count = 5;
    apply2_scratch.data_length = 255;
    uint8_t apply2_scratch_data[255];
    memcpy(apply2_scratch_data, mock_sector, sizeof(apply2_scratch_data));
    apply2_scratch.data = apply2_scratch_data;
    detect_button_layout(&apply2_scratch);
    detect_gshift_button_layout(&apply2_scratch, &set_dpi_device);
    detect_dpi_layout(&apply2_scratch, &set_dpi_device);
    detect_rgb_layout(&apply2_scratch);

    uint8_t apply2_combo_after[255];
    memcpy(apply2_combo_after, mock_sector, sizeof(apply2_combo_after));
    uint8_t apply2_combo_zones[1] = {0};
    uint8_t apply2_combo_colors[1][3] = {{0xAA, 0xBB, 0xCC}};
    if (!write_rgb_zone_colors(apply2_combo_after, &apply2_scratch, apply2_combo_zones,
                               apply2_combo_colors, 1)) {
        fprintf(stderr, "run_apply self-test failed to prepare the expected RGB write\n");
        return 1;
    }
    uint16_t apply2_combo_dpi[2] = {800, 1600};
    if (!write_dpi_stage_table(apply2_combo_after, &apply2_scratch, apply2_combo_dpi, 2)) {
        fprintf(stderr, "run_apply self-test failed to prepare the expected DPI write\n");
        return 1;
    }
    apply2_combo_after[1] = 0; // default index 1 (1-based) -> stored as 0
    apply2_combo_after[2] = 0; // shift index 1 (1-based) -> stored as 0
    sector_put_crc(apply2_combo_after, sizeof(apply2_combo_after));
    Reply apply2_combo_after_chunks[32];
    size_t apply2_combo_after_chunk_count = build_sector_read_replies(
        apply2_combo_after, sizeof(apply2_combo_after), apply2_combo_after_chunks, 32);
    if (apply2_combo_after_chunk_count == 0) {
        fprintf(stderr,
                "run_apply self-test failed to build the combined-profile readback replies\n");
        return 1;
    }

    Reply apply2_combo_replies[192];
    size_t apply2_combo_reply_count = 0;
    apply2_combo_replies[apply2_combo_reply_count++] = k_mock_get_info_reply;
    for (size_t i = 0; i < profile_state_control_chunk_count; i++) {
        apply2_combo_replies[apply2_combo_reply_count++] = profile_state_control_chunks[i];
    }
    for (size_t i = 0; i < data_chunk_count; i++) {
        apply2_combo_replies[apply2_combo_reply_count++] = data_chunks[i];
    }
    apply2_combo_replies[apply2_combo_reply_count++] = set_dpi_sensor_count_1;
    apply2_combo_replies[apply2_combo_reply_count++] = set_dpi_sensor_list;
    apply2_combo_replies[apply2_combo_reply_count++] = k_mock_onboard_mode_reply;
    apply2_combo_replies[apply2_combo_reply_count++] =
        k_mock_generic_ok_reply; // profile startWrite
    for (size_t i = 0; i < 16; i++) {
        apply2_combo_replies[apply2_combo_reply_count++] =
            k_mock_generic_ok_reply; // profile writeData
    }
    apply2_combo_replies[apply2_combo_reply_count++] = k_mock_generic_ok_reply; // profile endWrite
    for (size_t i = 0; i < apply2_combo_after_chunk_count; i++) {
        apply2_combo_replies[apply2_combo_reply_count++] =
            apply2_combo_after_chunks[i]; // profile verify
    }
    apply2_combo_replies[apply2_combo_reply_count++] =
        k_mock_generic_ok_reply; // control startWrite
    for (size_t i = 0; i < 16; i++) {
        apply2_combo_replies[apply2_combo_reply_count++] =
            k_mock_generic_ok_reply; // control writeData
    }
    apply2_combo_replies[apply2_combo_reply_count++] = k_mock_generic_ok_reply; // control endWrite
    for (size_t i = 0; i < profile_state_after_chunk_count; i++) {
        apply2_combo_replies[apply2_combo_reply_count++] =
            profile_state_after_chunks[i]; // control verify
    }
    apply2_combo_replies[apply2_combo_reply_count++] =
        (Reply){.status = REPLY_OK, .length = 2, .bytes = {0, 0}}; // get_current_onboard_profile
    if (apply2_combo_reply_count > sizeof(apply2_combo_replies) / sizeof(apply2_combo_replies[0])) {
        fprintf(stderr, "run_apply self-test combined reply buffer overflowed\n");
        return 1;
    }
    ChannelRequestTestContext apply2_combo_channel = {
        .replies = apply2_combo_replies, .reply_count = apply2_combo_reply_count, .calls = 0};
    g_channel_request_test_context = &apply2_combo_channel;
    const char *apply2_combo_directory = "/tmp";
    Options apply2_combo = {0};
    apply2_combo.profile = 1;
    apply2_combo.device_index = -1;
    apply2_combo.rgb_changes[0] = "1:AABBCC";
    apply2_combo.rgb_change_count = 1;
    apply2_combo.dpi_values = "800,1600";
    apply2_combo.dpi_default = 1;
    apply2_combo.dpi_shift = 1;
    apply2_combo.profile_state_changes[0] = "2:enable";
    apply2_combo.profile_state_change_count = 1;
    apply2_combo.yes = true;
    apply2_combo.backup_directory = apply2_combo_directory;
    apply2_combo.operation_id = "lope-apply-combo-test";
    char apply2_combo_backup_path[512];
    make_batch_backup_path(apply2_combo_directory, apply2_combo.operation_id,
                           apply2_combo_backup_path);
    unlink(apply2_combo_backup_path);
    int apply2_combo_result = run_apply(&apply2_combo);
    unlink(apply2_combo_backup_path);
    if (apply2_combo_result != 0) {
        fprintf(
            stderr,
            "run_apply combined RGB+DPI+profile-state happy-path self-test failed (result=%d)\n",
            apply2_combo_result);
        return 1;
    }

    // A control-only update also needs to exercise the plan's profile=false
    // branch and the disabled-state assignment. Start with both slots enabled
    // so disabling profile 2 remains a valid effective change.
    uint8_t apply2_both_enabled_control[255];
    memcpy(apply2_both_enabled_control, profile_state_control, sizeof(apply2_both_enabled_control));
    apply2_both_enabled_control[6] = 1;
    sector_put_crc(apply2_both_enabled_control, sizeof(apply2_both_enabled_control));
    Reply apply2_both_enabled_chunks[32];
    size_t apply2_both_enabled_chunk_count =
        build_sector_read_replies(apply2_both_enabled_control, sizeof(apply2_both_enabled_control),
                                  apply2_both_enabled_chunks, 32);
    uint8_t apply2_disable_profile2_control[255];
    memcpy(apply2_disable_profile2_control, apply2_both_enabled_control,
           sizeof(apply2_disable_profile2_control));
    apply2_disable_profile2_control[6] = 0;
    sector_put_crc(apply2_disable_profile2_control, sizeof(apply2_disable_profile2_control));
    Reply apply2_disable_profile2_chunks[32];
    size_t apply2_disable_profile2_chunk_count = build_sector_read_replies(
        apply2_disable_profile2_control, sizeof(apply2_disable_profile2_control),
        apply2_disable_profile2_chunks, 32);
    Reply apply2_control_only_replies[96];
    size_t apply2_control_only_reply_count = 0;
    apply2_control_only_replies[apply2_control_only_reply_count++] = k_mock_get_info_reply;
    for (size_t i = 0; i < apply2_both_enabled_chunk_count; i++) {
        apply2_control_only_replies[apply2_control_only_reply_count++] =
            apply2_both_enabled_chunks[i];
    }
    apply2_control_only_replies[apply2_control_only_reply_count++] = k_mock_onboard_mode_reply;
    apply2_control_only_replies[apply2_control_only_reply_count++] = k_mock_generic_ok_reply;
    for (size_t i = 0; i < 16; i++) {
        apply2_control_only_replies[apply2_control_only_reply_count++] = k_mock_generic_ok_reply;
    }
    apply2_control_only_replies[apply2_control_only_reply_count++] = k_mock_generic_ok_reply;
    for (size_t i = 0; i < apply2_disable_profile2_chunk_count; i++) {
        apply2_control_only_replies[apply2_control_only_reply_count++] =
            apply2_disable_profile2_chunks[i];
    }
    ChannelRequestTestContext apply2_control_only_channel = {.replies = apply2_control_only_replies,
                                                             .reply_count =
                                                                 apply2_control_only_reply_count,
                                                             .calls = 0};
    g_channel_request_test_context = &apply2_control_only_channel;
    Options apply2_control_only = {0};
    apply2_control_only.profile = 1;
    apply2_control_only.device_index = -1;
    apply2_control_only.dpi_default = -1;
    apply2_control_only.dpi_shift = -1;
    apply2_control_only.profile_state_changes[0] = "2:disable";
    apply2_control_only.profile_state_change_count = 1;
    apply2_control_only.yes = true;
    apply2_control_only.backup_directory = "/tmp";
    apply2_control_only.operation_id = "lope-apply-control-only-test";
    char apply2_control_only_backup_path[512];
    make_batch_backup_path(apply2_control_only.backup_directory, apply2_control_only.operation_id,
                           apply2_control_only_backup_path);
    unlink(apply2_control_only_backup_path);
    int apply2_control_only_result = run_apply(&apply2_control_only);
    unlink(apply2_control_only_backup_path);
    if (apply2_control_only_result != 0) {
        fprintf(stderr, "run_apply control-only disable self-test failed\n");
        return 1;
    }

    // Exercise the two short-circuit failures in the profile-state control
    // read: an unavailable sector and a readable sector with no headers.
    g_discover_devices_test_context = &apply2_discovery;
    Reply apply2_control_read_failure_replies[1] = {k_mock_get_info_reply};
    ChannelRequestTestContext apply2_control_read_failure_channel = {
        .replies = apply2_control_read_failure_replies, .reply_count = 1, .calls = 0};
    g_channel_request_test_context = &apply2_control_read_failure_channel;
    Options apply2_control_read_failure = {0};
    apply2_control_read_failure.profile = 1;
    apply2_control_read_failure.device_index = -1;
    apply2_control_read_failure.dpi_default = -1;
    apply2_control_read_failure.dpi_shift = -1;
    apply2_control_read_failure.profile_state_changes[0] = "1:enable";
    apply2_control_read_failure.profile_state_change_count = 1;
    if (run_apply(&apply2_control_read_failure) != 1) {
        fprintf(stderr, "run_apply control-read-failure self-test failed\n");
        return 1;
    }

    uint8_t apply2_empty_control[255] = {0};
    sector_put_crc(apply2_empty_control, sizeof(apply2_empty_control));
    Reply apply2_empty_control_chunks[32];
    size_t apply2_empty_control_chunk_count = build_sector_read_replies(
        apply2_empty_control, sizeof(apply2_empty_control), apply2_empty_control_chunks, 32);
    Reply apply2_empty_control_replies[40];
    size_t apply2_empty_control_reply_count = 0;
    apply2_empty_control_replies[apply2_empty_control_reply_count++] = k_mock_get_info_reply;
    for (size_t i = 0; i < apply2_empty_control_chunk_count; i++) {
        apply2_empty_control_replies[apply2_empty_control_reply_count++] =
            apply2_empty_control_chunks[i];
    }
    ChannelRequestTestContext apply2_empty_control_channel = {
        .replies = apply2_empty_control_replies,
        .reply_count = apply2_empty_control_reply_count,
        .calls = 0};
    g_channel_request_test_context = &apply2_empty_control_channel;
    if (run_apply(&apply2_control_read_failure) != 1) {
        fprintf(stderr, "run_apply empty-control-headers self-test failed\n");
        return 1;
    }

    // A valid normal-button layout with an invalid second bank must reject a
    // G-Shift edit after profile loading, rather than treating the bank as
    // writable merely because the device advertises the shift flag.
    uint8_t apply2_bad_gshift_sector[255];
    memcpy(apply2_bad_gshift_sector, mock_sector, sizeof(apply2_bad_gshift_sector));
    memset(apply2_bad_gshift_sector + 96, 0, 20);
    sector_put_crc(apply2_bad_gshift_sector, sizeof(apply2_bad_gshift_sector));
    Reply apply2_bad_gshift_chunks[32];
    size_t apply2_bad_gshift_chunk_count = build_sector_read_replies(
        apply2_bad_gshift_sector, sizeof(apply2_bad_gshift_sector), apply2_bad_gshift_chunks, 32);
    Reply apply2_bad_gshift_replies[80];
    size_t apply2_bad_gshift_reply_count = 0;
    for (size_t i = 0; i < apply2_headers_prefix_count; i++) {
        apply2_bad_gshift_replies[apply2_bad_gshift_reply_count++] = apply2_headers_replies[i];
    }
    for (size_t i = 0; i < apply2_bad_gshift_chunk_count; i++) {
        apply2_bad_gshift_replies[apply2_bad_gshift_reply_count++] = apply2_bad_gshift_chunks[i];
    }
    ChannelRequestTestContext apply2_bad_gshift_channel = {.replies = apply2_bad_gshift_replies,
                                                           .reply_count =
                                                               apply2_bad_gshift_reply_count,
                                                           .calls = 0};
    g_channel_request_test_context = &apply2_bad_gshift_channel;
    Options apply2_bad_gshift = {0};
    apply2_bad_gshift.profile = 1;
    apply2_bad_gshift.device_index = -1;
    apply2_bad_gshift.dpi_default = -1;
    apply2_bad_gshift.dpi_shift = -1;
    apply2_bad_gshift.button_changes[0] = "gshift:1:80010002";
    apply2_bad_gshift.button_change_count = 1;
    if (run_apply(&apply2_bad_gshift) != 1) {
        fprintf(stderr, "run_apply invalid-G-Shift-layout self-test failed\n");
        return 1;
    }

    // An otherwise writable profile can still have an unrecognized DPI
    // layout. This reaches run_apply's layout validation before any sensor
    // capability requests are attempted.
    uint8_t apply2_bad_dpi_sector[255];
    memcpy(apply2_bad_dpi_sector, mock_sector, sizeof(apply2_bad_dpi_sector));
    write_le16(apply2_bad_dpi_sector + 5, 0);
    sector_put_crc(apply2_bad_dpi_sector, sizeof(apply2_bad_dpi_sector));
    Reply apply2_bad_dpi_chunks[32];
    size_t apply2_bad_dpi_chunk_count = build_sector_read_replies(
        apply2_bad_dpi_sector, sizeof(apply2_bad_dpi_sector), apply2_bad_dpi_chunks, 32);
    Reply apply2_bad_dpi_replies[80];
    size_t apply2_bad_dpi_reply_count = 0;
    for (size_t i = 0; i < apply2_headers_prefix_count; i++) {
        apply2_bad_dpi_replies[apply2_bad_dpi_reply_count++] = apply2_headers_replies[i];
    }
    for (size_t i = 0; i < apply2_bad_dpi_chunk_count; i++) {
        apply2_bad_dpi_replies[apply2_bad_dpi_reply_count++] = apply2_bad_dpi_chunks[i];
    }
    ChannelRequestTestContext apply2_bad_dpi_channel = {
        .replies = apply2_bad_dpi_replies, .reply_count = apply2_bad_dpi_reply_count, .calls = 0};
    g_channel_request_test_context = &apply2_bad_dpi_channel;
    Options apply2_bad_dpi = {0};
    apply2_bad_dpi.profile = 1;
    apply2_bad_dpi.device_index = -1;
    apply2_bad_dpi.dpi_values = "800,1200";
    apply2_bad_dpi.dpi_default = -1;
    apply2_bad_dpi.dpi_shift = -1;
    if (run_apply(&apply2_bad_dpi) != 1) {
        fprintf(stderr, "run_apply invalid-DPI-layout self-test failed\n");
        return 1;
    }

    // Defaults omitted: run_apply inherits the indexes already stored in the
    // profile. Preview mode makes this a no-write test while still traversing
    // the complete DPI preparation path.
    Reply apply2_inherited_dpi_replies[100];
    size_t apply2_inherited_dpi_reply_count = 0;
    for (size_t i = 0; i < apply2_loaded_prefix_count; i++) {
        apply2_inherited_dpi_replies[apply2_inherited_dpi_reply_count++] = apply2_loaded_replies[i];
    }
    apply2_inherited_dpi_replies[apply2_inherited_dpi_reply_count++] = set_dpi_sensor_count_1;
    apply2_inherited_dpi_replies[apply2_inherited_dpi_reply_count++] = set_dpi_sensor_list;
    ChannelRequestTestContext apply2_inherited_dpi_channel = {
        .replies = apply2_inherited_dpi_replies,
        .reply_count = apply2_inherited_dpi_reply_count,
        .calls = 0};
    g_channel_request_test_context = &apply2_inherited_dpi_channel;
    Options apply2_inherited_dpi = {0};
    apply2_inherited_dpi.profile = 1;
    apply2_inherited_dpi.device_index = -1;
    apply2_inherited_dpi.dpi_values = "800,1200,1600";
    apply2_inherited_dpi.dpi_default = -1;
    apply2_inherited_dpi.dpi_shift = -1;
    if (run_apply(&apply2_inherited_dpi) != 0) {
        fprintf(stderr, "run_apply inherited-DPI-index preview self-test failed\n");
        return 1;
    }

    Reply apply2_shift_range_replies[100];
    size_t apply2_shift_range_reply_count = 0;
    for (size_t i = 0; i < apply2_loaded_prefix_count; i++) {
        apply2_shift_range_replies[apply2_shift_range_reply_count++] = apply2_loaded_replies[i];
    }
    apply2_shift_range_replies[apply2_shift_range_reply_count++] = set_dpi_sensor_count_1;
    apply2_shift_range_replies[apply2_shift_range_reply_count++] = set_dpi_sensor_list;
    ChannelRequestTestContext apply2_shift_range_channel = {.replies = apply2_shift_range_replies,
                                                            .reply_count =
                                                                apply2_shift_range_reply_count,
                                                            .calls = 0};
    g_channel_request_test_context = &apply2_shift_range_channel;
    Options apply2_shift_range = apply2_inherited_dpi;
    apply2_shift_range.dpi_default = 1;
    apply2_shift_range.dpi_shift = 6;
    if (run_apply(&apply2_shift_range) != 1) {
        fprintf(stderr, "run_apply shift-index-out-of-range self-test failed\n");
        return 1;
    }

    // A requested disable that is already in effect still exercises the false
    // arm of the control-state write ternary without requiring a hardware write.
    ChannelRequestTestContext apply2_disable_preview_channel = {
        .replies = apply2_control_loaded_replies,
        .reply_count = apply2_control_loaded_prefix_count,
        .calls = 0};
    g_channel_request_test_context = &apply2_disable_preview_channel;
    Options apply2_disable_preview = {0};
    apply2_disable_preview.profile = 1;
    apply2_disable_preview.device_index = -1;
    apply2_disable_preview.dpi_default = -1;
    apply2_disable_preview.dpi_shift = -1;
    apply2_disable_preview.profile_state_changes[0] = "2:disable";
    apply2_disable_preview.profile_state_change_count = 1;
    if (run_apply(&apply2_disable_preview) != 0) {
        fprintf(stderr, "run_apply disable-preview self-test failed\n");
        return 1;
    }

    // Control-only success covers the batch plan's no-profile branch and the
    // post-write DPI-sync condition's false arm.
    Reply apply2_control_only_enable_replies[100];
    size_t apply2_control_only_enable_reply_count = 0;
    for (size_t i = 0; i < apply2_control_loaded_prefix_count; i++) {
        apply2_control_only_enable_replies[apply2_control_only_enable_reply_count++] =
            apply2_control_loaded_replies[i];
    }
    apply2_control_only_enable_replies[apply2_control_only_enable_reply_count++] =
        k_mock_onboard_mode_reply;
    apply2_control_only_enable_replies[apply2_control_only_enable_reply_count++] =
        k_mock_generic_ok_reply;
    for (size_t i = 0; i < 16; i++) {
        apply2_control_only_enable_replies[apply2_control_only_enable_reply_count++] =
            k_mock_generic_ok_reply;
    }
    apply2_control_only_enable_replies[apply2_control_only_enable_reply_count++] =
        k_mock_generic_ok_reply;
    for (size_t i = 0; i < profile_state_after_chunk_count; i++) {
        apply2_control_only_enable_replies[apply2_control_only_enable_reply_count++] =
            profile_state_after_chunks[i];
    }
    ChannelRequestTestContext apply2_control_only_enable_channel = {
        .replies = apply2_control_only_enable_replies,
        .reply_count = apply2_control_only_enable_reply_count,
        .calls = 0};
    g_channel_request_test_context = &apply2_control_only_enable_channel;
    Options apply2_control_only_enable = {0};
    apply2_control_only_enable.profile = 1;
    apply2_control_only_enable.device_index = -1;
    apply2_control_only_enable.dpi_default = -1;
    apply2_control_only_enable.dpi_shift = -1;
    apply2_control_only_enable.profile_state_changes[0] = "2:enable";
    apply2_control_only_enable.profile_state_change_count = 1;
    apply2_control_only_enable.yes = true;
    apply2_control_only_enable.backup_directory = "/tmp";
    apply2_control_only_enable.operation_id = "lope-apply-control-only-test";
    char apply2_control_only_enable_backup_path[512];
    make_batch_backup_path("/tmp", apply2_control_only_enable.operation_id,
                           apply2_control_only_enable_backup_path);
    unlink(apply2_control_only_enable_backup_path);
    EngineBoundaryWriteResult control_only_boundary;
    EngineBoundaryError control_only_error;
    if (engine_apply(&apply2_control_only_enable, &control_only_boundary, &control_only_error) !=
            0 ||
        !control_only_boundary.completed || !control_only_boundary.changed ||
        control_only_boundary.planned_count != 1 || control_only_boundary.verified_count != 1 ||
        control_only_error.code != ENGINE_BOUNDARY_ERROR_NONE) {
        fprintf(stderr, "run_apply control-only success self-test failed\n");
        return 1;
    }
    unlink(apply2_control_only_enable_backup_path);

    // The command should stop before discovery when HID context setup fails.
    hid_context_create_impl = apply_context_create_failure;
    Options apply_context_failure = {0};
    apply_context_failure.profile = 1;
    apply_context_failure.device_index = -1;
    apply_context_failure.dpi_default = -1;
    apply_context_failure.dpi_shift = -1;
    apply_context_failure.button_changes[0] = apply2_valid_button_change;
    apply_context_failure.button_change_count = 1;
    if (run_apply(&apply_context_failure) != 1) {
        fprintf(stderr, "run_apply context-creation-failure self-test failed\n");
        return 1;
    }
    hid_context_create_impl = hid_context_create_hardware;

    return 0;
}
