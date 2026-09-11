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

static int run_self_test(void) {
    const uint8_t sample[] = "123456789";
    if (crc16_ccitt_false(sample, 9) != 0x29B1) {
        fprintf(stderr, "CRC self-test failed\n");
        return 1;
    }
    uint8_t frame[LONG_REPORT_BYTES];
    const uint8_t ping_params[3] = {0x00, 0x00, 0x5A};
    size_t frame_length = build_hidpp_frame(false, 0x01, 0x001B, ping_params, sizeof(ping_params), frame);
    if (frame_length != SHORT_REPORT_BYTES || frame[0] != REPORT_SHORT || frame[1] != 0x01 ||
        frame[2] != 0x00 || frame[3] != 0x1B || memcmp(frame + 4, ping_params, 3) != 0) {
        fprintf(stderr, "short HID++ frame self-test failed\n");
        return 1;
    }
    uint8_t long_params[16];
    for (size_t i = 0; i < sizeof(long_params); i++) long_params[i] = (uint8_t)i;
    frame_length = build_hidpp_frame(true, 0xFF, 0x127B, long_params, sizeof(long_params), frame);
    if (frame_length != LONG_REPORT_BYTES || frame[0] != REPORT_LONG || frame[1] != 0xFF ||
        frame[2] != 0x12 || frame[3] != 0x7B || memcmp(frame + 4, long_params, 16) != 0) {
        fprintf(stderr, "long HID++ frame self-test failed\n");
        return 1;
    }
    Profile profile;
    uint16_t parsed_dpi[5] = {0};
    size_t parsed_dpi_count = 0;
    bool dpi_parser_ok = parse_dpi_values("800,1600", parsed_dpi, &parsed_dpi_count) &&
                         parsed_dpi_count == 2 && parsed_dpi[0] == 800 && parsed_dpi[1] == 1600 &&
                         !parse_dpi_values("800,1200,1600,2400,3200,6400", parsed_dpi, &parsed_dpi_count);
    if (!dpi_parser_ok) {
        fprintf(stderr, "DPI parser self-test failed\n");
        return 1;
    }
    memset(&profile, 0, sizeof(profile));
    profile.info.profile_format = 5;
    profile.info.button_count = 5;
    profile.data_length = 255;
    profile.data = (uint8_t *)calloc(profile.data_length, 1);
    if (profile.data == NULL) {
        return 1;
    }
    uint8_t specs[5][4] = {
        {0x80, 0x01, 0x00, 0x01},
        {0x80, 0x01, 0x00, 0x02},
        {0x80, 0x01, 0x00, 0x04},
        {0x80, 0x01, 0x00, 0x08},
        {0x80, 0x01, 0x00, 0x10},
    };
    for (size_t i = 0; i < 5; i++) {
        memcpy(profile.data + 32 + i * 4, specs[i], 4);
    }
    uint16_t sample_dpi[5] = {800, 1200, 1600, 2400, 3200};
    for (size_t i = 0; i < 5; i++) {
        write_le16(profile.data + 3 + i * 2, sample_dpi[i]);
    }
    profile.data[1] = 2;
    profile.data[2] = 0;
    sector_put_crc(profile.data, profile.data_length);
    profile.crc_ok = sector_crc_ok(profile.data, profile.data_length);
    detect_button_layout(&profile);
    detect_dpi_layout(&profile);
    uint8_t alt_tab[4];
    bool target_ok = parse_target("alt-tab", alt_tab) && alt_tab[0] == 0x80 && alt_tab[1] == 0x02 &&
                     alt_tab[2] == 0x04 && alt_tab[3] == 0x2B;
    int rear = find_rear_thumb_button(&profile);
    bool passed = profile.crc_ok && profile.layout_supported && profile.button_offset == 32 &&
                  profile.dpi_layout_supported && profile.dpi_offset == 3 &&
                  read_le16(profile.data + profile.dpi_offset + 2 * 2) == 1600 &&
                  rear == 4 && target_ok;
    write_le16(profile.data + 3 + 2 * 2, UINT16_MAX);
    write_le16(profile.data + 3 + 3 * 2, UINT16_MAX);
    write_le16(profile.data + 3 + 4 * 2, UINT16_MAX);
    profile.data[1] = 0;
    profile.data[2] = 1;
    detect_dpi_layout(&profile);
    passed = passed && profile.dpi_layout_supported && profile.dpi_count == 2 &&
             profile.dpi_default_index == 0 && profile.dpi_shift_index == 1;
    write_le16(profile.data + 3 + 2 * 2, 1600);
    write_le16(profile.data + 3 + 3 * 2, 3200);
    write_le16(profile.data + 3 + 4 * 2, 0);
    profile.data[1] = 1;
    profile.data[2] = 0;
    detect_dpi_layout(&profile);
    passed = passed && profile.dpi_layout_supported && profile.dpi_count == 4 &&
             profile.dpi_default_index == 1 && profile.dpi_shift_index == 0;
    free(profile.data);
    if (!passed) {
        fprintf(stderr, "profile/layout self-test failed\n");
        return 1;
    }

    Profile newer;
    memset(&newer, 0, sizeof(newer));
    newer.info.profile_format = 7;
    newer.info.button_count = 5;
    newer.data_length = 255;
    newer.data = (uint8_t *)calloc(newer.data_length, 1);
    if (newer.data == NULL) {
        return 1;
    }
    for (size_t i = 0; i < 5; i++) {
        memcpy(newer.data + 48 + i * 4, specs[i], 4);
    }
    sector_put_crc(newer.data, newer.data_length);
    newer.crc_ok = sector_crc_ok(newer.data, newer.data_length);
    detect_button_layout(&newer);
    bool newer_ok = newer.crc_ok && newer.layout_supported && newer.button_offset == 48 && find_rear_thumb_button(&newer) == 4;
    free(newer.data);
    if (!newer_ok) {
        fprintf(stderr, "newer profile layout self-test failed\n");
        return 1;
    }

    HidInterface dummy_interface;
    memset(&dummy_interface, 0, sizeof(dummy_interface));
    dummy_interface.vendor_id = LOGITECH_VID;
    dummy_interface.product_id = 0xC08B;
    Device dummy_device;
    memset(&dummy_device, 0, sizeof(dummy_device));
    dummy_device.iface = &dummy_interface;
    dummy_device.device_number = 0xFF;
    dummy_device.request_device_number = 0xFF;
    profile.headers[0].sector = 0x0123;
    profile.selected_header = 0;
    profile.info.profile_format = 5;
    profile.data_length = 255;
    profile.data = (uint8_t *)calloc(profile.data_length, 1);
    if (profile.data == NULL) {
        return 1;
    }
    sector_put_crc(profile.data, profile.data_length);
    char temp_path[] = "/tmp/lomps-selftest-XXXXXX";
    int temp_fd = mkstemp(temp_path);
    if (temp_fd < 0) {
        free(profile.data);
        return 1;
    }
    close(temp_fd);
    unlink(temp_path);
    bool package_ok = package_write(temp_path, &dummy_device, &profile, profile.data, true);
    BackupPackage package;
    if (package_ok) {
        package_ok = package_read(temp_path, &package);
    }
    if (package_ok) {
        package_ok = package.sector_count == 1 &&
                     package.sectors[0].sector == 0x0123 && package.sectors[0].size == 255 &&
                     memcmp(package.sectors[0].data, profile.data, 255) == 0;
        package_release(&package);
    }
    unlink(temp_path);

    uint8_t control_data[255] = {0};
    control_data[2] = 1;
    sector_put_crc(control_data, sizeof(control_data));
    BackupSectorSource combined_sources[2] = {
        {.sector = 0x0123, .size = 255, .data = profile.data},
        {.sector = 0x0000, .size = 255, .data = control_data}
    };
    char combined_path[] = "/tmp/lomps-selftest-combined-XXXXXX";
    int combined_fd = mkstemp(combined_path);
    if (combined_fd < 0) {
        free(profile.data);
        return 1;
    }
    close(combined_fd);
    unlink(combined_path);
    bool combined_package_ok = package_write_multi(combined_path, &dummy_device, 5,
                                                    combined_sources, 2, true);
    if (combined_package_ok) {
        combined_package_ok = package_read(combined_path, &package);
    }
    if (combined_package_ok) {
        combined_package_ok = package.sector_count == 2 &&
            package.sectors[0].sector == 0x0123 && package.sectors[1].sector == 0x0000 &&
            memcmp(package.sectors[0].data, profile.data, 255) == 0 &&
            memcmp(package.sectors[1].data, control_data, 255) == 0;
        package_release(&package);
    }
    unlink(combined_path);
    free(profile.data);
    if (!package_ok || !combined_package_ok) {
        fprintf(stderr, "backup package self-test failed\n");
        return 1;
    }

    uint8_t unchanged_before[4] = {0x10, 0x20, 0x30, 0x40};
    uint8_t unchanged_after[4] = {0x10, 0x20, 0x30, 0x40};
    uint8_t changed_after[4] = {0x10, 0x20, 0x30, 0x41};
    bool batch_plan_ok = !batch_sector_changed(unchanged_before, unchanged_after, sizeof(unchanged_before)) &&
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
        .outcomes = first_failure, .outcome_count = 1, .calls = 0
    };
    bool later_failure[] = {true, false};
    BatchWriterTestContext later_failure_context = {
        .outcomes = later_failure, .outcome_count = 2, .calls = 0
    };
    bool all_success[] = {true, true};
    BatchWriterTestContext all_success_context = {
        .outcomes = all_success, .outcome_count = 2, .calls = 0
    };
    BatchSector test_plan[2] = {
        {.sector = 0x0100, .data = unchanged_before, .length = sizeof(unchanged_before), .kind = "profile"},
        {.sector = 0x0001, .data = unchanged_before, .length = sizeof(unchanged_before), .kind = "control"}
    };
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
    printf("self-test: CRC-16, format/layout detection, batch planning/failure handling, rear-thumb identification, and Alt+Tab encoding passed\n");
    return 0;
}
