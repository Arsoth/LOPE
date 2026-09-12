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
    Reply g603_pairing = {0};
    g603_pairing.status = REPLY_OK;
    g603_pairing.length = 8;
    g603_pairing.bytes[3] = 0x40;
    g603_pairing.bytes[4] = 0x6C;
    Reply unknown_pairing = g603_pairing;
    unknown_pairing.bytes[3] = 0x40;
    unknown_pairing.bytes[4] = 0x00;
    if (strcmp(receiver_pairing_model_name(g603_pairing), "G603 LIGHTSPEED") != 0 ||
        receiver_pairing_model_name(unknown_pairing) != NULL) {
        fprintf(stderr, "receiver model-name fallback self-test failed\n");
        return 1;
    }
    HidInterface connection_interface = {0};
    Device connection_device = {0};
    connection_device.iface = &connection_interface;
    connection_device.device_number = 1;
    connection_interface.product_id = 0xC539;
    bool connection_types_ok = strcmp(device_connection(&connection_device), "LIGHTSPEED") == 0;
    connection_interface.product_id = 0xC548;
    connection_types_ok =
        connection_types_ok && strcmp(device_connection(&connection_device), "Bolt") == 0;
    connection_interface.product_id = 0xC52B;
    connection_types_ok =
        connection_types_ok && strcmp(device_connection(&connection_device), "Unifying") == 0;
    if (!connection_types_ok) {
        fprintf(stderr, "receiver connection-type self-test failed\n");
        return 1;
    }
    HidInterface profile_index_interface = {0};
    Device profile_index_device = {0};
    profile_index_device.iface = &profile_index_interface;
    profile_index_interface.product_id = 0xC099; // G502 X
    bool profile_index_ok = current_onboard_profile_number(&profile_index_device, 1) == 1 &&
                            current_onboard_profile_number(&profile_index_device, 2) == 2;
    profile_index_interface.product_id = 0xC08B; // G502 HERO
    profile_index_ok =
        profile_index_ok && current_onboard_profile_number(&profile_index_device, 0) == 1;
    if (!profile_index_ok) {
        fprintf(stderr, "onboard profile-index mapping self-test failed\n");
        return 1;
    }
    uint8_t frame[LONG_REPORT_BYTES];
    const uint8_t ping_params[3] = {0x00, 0x00, 0x5A};
    size_t frame_length =
        build_hidpp_frame(false, 0x01, 0x001B, ping_params, sizeof(ping_params), frame);
    if (frame_length != SHORT_REPORT_BYTES || frame[0] != REPORT_SHORT || frame[1] != 0x01 ||
        frame[2] != 0x00 || frame[3] != 0x1B || memcmp(frame + 4, ping_params, 3) != 0) {
        fprintf(stderr, "short HID++ frame self-test failed\n");
        return 1;
    }
    uint8_t long_params[16];
    for (size_t i = 0; i < sizeof(long_params); i++)
        long_params[i] = (uint8_t)i;
    frame_length = build_hidpp_frame(true, 0xFF, 0x127B, long_params, sizeof(long_params), frame);
    if (frame_length != LONG_REPORT_BYTES || frame[0] != REPORT_LONG || frame[1] != 0xFF ||
        frame[2] != 0x12 || frame[3] != 0x7B || memcmp(frame + 4, long_params, 16) != 0) {
        fprintf(stderr, "long HID++ frame self-test failed\n");
        return 1;
    }
    Profile profile;
    uint16_t parsed_dpi[5] = {0};
    size_t parsed_dpi_count = 0;
    bool dpi_parser_ok =
        parse_dpi_values("800,1600", parsed_dpi, &parsed_dpi_count) && parsed_dpi_count == 2 &&
        parsed_dpi[0] == 800 && parsed_dpi[1] == 1600 &&
        !parse_dpi_values("800,1200,1600,2400,3200,6400", parsed_dpi, &parsed_dpi_count);
    if (!dpi_parser_ok) {
        fprintf(stderr, "DPI parser self-test failed\n");
        return 1;
    }
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
    memset(&profile, 0, sizeof(profile));
    profile.info.profile_format = 5;
    profile.info.button_count = 5;
    profile.info.shift_flags = 0x02;
    profile.data_length = 255;
    profile.data = (uint8_t *)calloc(profile.data_length, 1);
    if (profile.data == NULL) {
        return 1;
    }
    uint8_t specs[5][4] = {
        {0x80, 0x01, 0x00, 0x01}, {0x80, 0x01, 0x00, 0x02}, {0x80, 0x01, 0x00, 0x04},
        {0x80, 0x01, 0x00, 0x08}, {0x80, 0x01, 0x00, 0x10},
    };
    for (size_t i = 0; i < 5; i++) {
        memcpy(profile.data + 32 + i * 4, specs[i], 4);
    }
    uint8_t gshift_specs[5][4] = {
        {0x80, 0x01, 0x00, 0x10}, {0x80, 0x01, 0x00, 0x20}, {0x80, 0x01, 0x00, 0x40},
        {0x80, 0x01, 0x00, 0x80}, {0x80, 0x01, 0x01, 0x00},
    };
    for (size_t i = 0; i < 5; i++) {
        memcpy(profile.data + 96 + i * 4, gshift_specs[i], 4);
    }
    uint16_t sample_dpi[5] = {800, 1200, 1600, 2400, 3200};
    for (size_t i = 0; i < 5; i++) {
        write_le16(profile.data + 3 + i * 2, sample_dpi[i]);
    }
    for (size_t i = 0; i < RGB_PROFILE_RECORD_COUNT; i++) {
        memset(profile.data + RGB_PROFILE_BASE_OFFSET + i * RGB_PROFILE_RECORD_BYTES, 0xFF,
               RGB_PROFILE_RECORD_BYTES);
    }
    profile.data[RGB_PROFILE_BASE_OFFSET] = 0x01;
    profile.data[RGB_PROFILE_BASE_OFFSET + 1] = 0x10;
    profile.data[RGB_PROFILE_BASE_OFFSET + 2] = 0x20;
    profile.data[RGB_PROFILE_BASE_OFFSET + 3] = 0x30;
    profile.data[RGB_PROFILE_BASE_OFFSET + RGB_PROFILE_RECORD_BYTES] = 0x01;
    profile.data[RGB_PROFILE_BASE_OFFSET + RGB_PROFILE_RECORD_BYTES + 1] = 0x40;
    profile.data[RGB_PROFILE_BASE_OFFSET + RGB_PROFILE_RECORD_BYTES + 2] = 0x50;
    profile.data[RGB_PROFILE_BASE_OFFSET + RGB_PROFILE_RECORD_BYTES + 3] = 0x60;
    profile.data[1] = 2;
    profile.data[2] = 0;
    sector_put_crc(profile.data, profile.data_length);
    profile.crc_ok = sector_crc_ok(profile.data, profile.data_length);
    detect_button_layout(&profile);
    detect_gshift_button_layout(&profile, NULL);
    HidInterface g203_interface = {0};
    Device g203_device = {0};
    g203_interface.product_id = 0xC092;
    snprintf(g203_device.name, sizeof(g203_device.name), "G203 LIGHTSYNC Gaming Mouse");
    g203_device.iface = &g203_interface;
    detect_dpi_layout(&profile, &g203_device);
    detect_rgb_layout(&profile);
    uint8_t parsed_rgb_color[3] = {0};
    int parsed_rgb_zone = 0;
    bool rgb_parser_ok = parse_batch_rgb_change("2:A1B2C3", &parsed_rgb_zone, parsed_rgb_color) &&
                         parsed_rgb_zone == 2 && parsed_rgb_color[0] == 0xA1 &&
                         parsed_rgb_color[1] == 0xB2 && parsed_rgb_color[2] == 0xC3 &&
                         !parse_batch_rgb_change("3:GG0000", &parsed_rgb_zone, parsed_rgb_color);
    int parsed_button = 0;
    bool parsed_gshift = false;
    uint8_t parsed_button_spec[4] = {0};
    bool gshift_parser_ok = parse_batch_button_change("gshift:3:80010004", &parsed_button,
                                                      &parsed_gshift, parsed_button_spec) &&
                            parsed_button == 3 && parsed_gshift && parsed_button_spec[3] == 0x04;
    bool normal_parser_ok = parse_batch_button_change("normal:2:80010002", &parsed_button,
                                                      &parsed_gshift, parsed_button_spec) &&
                            parsed_button == 2 && !parsed_gshift && parsed_button_spec[3] == 0x02;
    uint8_t rgb_zones[1] = {1};
    uint8_t rgb_colors[1][3] = {{0xAA, 0xBB, 0xCC}};
    bool rgb_write_ok =
        write_rgb_zone_colors(profile.data, &profile, rgb_zones, rgb_colors, 1) &&
        profile.data[RGB_PROFILE_BASE_OFFSET + RGB_PROFILE_RECORD_BYTES + 1] == 0xAA &&
        profile.data[RGB_PROFILE_BASE_OFFSET + RGB_PROFILE_RECORD_BYTES + 2] == 0xBB &&
        profile.data[RGB_PROFILE_BASE_OFFSET + RGB_PROFILE_RECORD_BYTES + 3] == 0xCC;
    uint8_t saved_invalid_mode =
        profile.data[RGB_PROFILE_BASE_OFFSET + 2 * RGB_PROFILE_RECORD_BYTES];
    profile.data[RGB_PROFILE_BASE_OFFSET + 2 * RGB_PROFILE_RECORD_BYTES] = 0x7F;
    detect_rgb_layout(&profile);
    bool rgb_unsupported_ok = !profile.rgb_layout_supported;
    profile.data[RGB_PROFILE_BASE_OFFSET + 2 * RGB_PROFILE_RECORD_BYTES] = saved_invalid_mode;
    detect_rgb_layout(&profile);
    uint8_t alt_tab[4];
    bool target_ok = parse_target("alt-tab", alt_tab) && alt_tab[0] == 0x80 && alt_tab[1] == 0x02 &&
                     alt_tab[2] == 0x04 && alt_tab[3] == 0x2B;
    int rear = find_rear_thumb_button(&profile);
    bool passed = profile.crc_ok && profile.layout_supported && profile.button_offset == 32 &&
                  profile.gshift_layout_supported && profile.gshift_button_offset == 96 &&
                  profile.dpi_layout_supported && profile.dpi_offset == 3 &&
                  read_le16(profile.data + profile.dpi_offset + 2 * 2) == 1600 && rear == 4 &&
                  target_ok && rgb_parser_ok && gshift_parser_ok && normal_parser_ok &&
                  rgb_write_ok && rgb_unsupported_ok && profile.rgb_layout_supported &&
                  profile.rgb_zone_count == 2;
    uint16_t compacted_dpi[4] = {800, 1200, 2400, 3200};
    bool compacted_write_ok = write_dpi_stage_table(profile.data, &profile, compacted_dpi, 4);
    bool compacted_table_ok = compacted_write_ok && profile.dpi_unused_value == 0;
    for (size_t i = 0; compacted_table_ok && i < 4; i++) {
        compacted_table_ok = read_le16(profile.data + 3 + i * 2) == compacted_dpi[i];
    }
    compacted_table_ok = compacted_table_ok && read_le16(profile.data + 3 + 4 * 2) == 0;
    passed = passed && compacted_table_ok;
    write_le16(profile.data + 3 + 2 * 2, UINT16_MAX);
    write_le16(profile.data + 3 + 3 * 2, UINT16_MAX);
    write_le16(profile.data + 3 + 4 * 2, UINT16_MAX);
    profile.data[1] = 0;
    profile.data[2] = 1;
    detect_dpi_layout(&profile, NULL);
    passed = passed && profile.dpi_layout_supported && profile.dpi_count == 2 &&
             profile.dpi_default_index == 0 && profile.dpi_shift_index == 1;
    write_le16(profile.data + 3 + 2 * 2, 1600);
    write_le16(profile.data + 3 + 3 * 2, 3200);
    write_le16(profile.data + 3 + 4 * 2, 0);
    profile.data[1] = 1;
    profile.data[2] = 0;
    detect_dpi_layout(&profile, NULL);
    passed = passed && profile.dpi_layout_supported && profile.dpi_count == 4 &&
             profile.dpi_default_index == 1 && profile.dpi_shift_index == 0;
    free(profile.data);
    if (!passed) {
        fprintf(stderr, "profile/layout self-test failed\n");
        return 1;
    }

    Profile g603_profile;
    memset(&g603_profile, 0, sizeof(g603_profile));
    g603_profile.info.profile_format = 3;
    g603_profile.info.button_count = 6;
    g603_profile.info.shift_flags = 0;
    g603_profile.data_length = 255;
    g603_profile.data = (uint8_t *)calloc(g603_profile.data_length, 1);
    if (g603_profile.data == NULL) {
        return 1;
    }
    for (size_t i = 0; i < 5; i++) {
        memcpy(g603_profile.data + 32 + i * 4, specs[i], 4);
        memcpy(g603_profile.data + 96 + i * 4, gshift_specs[i], 4);
    }
    memcpy(g603_profile.data + 32 + 5 * 4, specs[0], 4);
    memcpy(g603_profile.data + 96 + 5 * 4, gshift_specs[0], 4);
    HidInterface g603_interface = {0};
    Device g603_device = {0};
    g603_interface.product_id = 0xB01C;
    snprintf(g603_device.name, sizeof(g603_device.name), "G603 LIGHTSPEED");
    g603_device.iface = &g603_interface;
    detect_button_layout(&g603_profile);
    detect_gshift_button_layout(&g603_profile, &g603_device);
    bool g603_ok = g603_profile.layout_supported && g603_profile.button_offset == 32 &&
                   g603_profile.gshift_layout_supported && g603_profile.gshift_button_offset == 96;
    free(g603_profile.data);
    if (!g603_ok) {
        fprintf(stderr, "G603 G-Shift layout self-test failed\n");
        return 1;
    }

    Profile newer;
    memset(&newer, 0, sizeof(newer));
    newer.info.profile_format = 7;
    newer.info.button_count = 5;
    newer.info.shift_flags = 0x02;
    newer.data_length = 255;
    newer.data = (uint8_t *)calloc(newer.data_length, 1);
    if (newer.data == NULL) {
        return 1;
    }
    for (size_t i = 0; i < 5; i++) {
        memcpy(newer.data + 48 + i * 4, specs[i], 4);
        memcpy(newer.data + 112 + i * 4, gshift_specs[i], 4);
    }
    sector_put_crc(newer.data, newer.data_length);
    newer.crc_ok = sector_crc_ok(newer.data, newer.data_length);
    detect_button_layout(&newer);
    detect_gshift_button_layout(&newer, NULL);
    bool newer_ok = newer.crc_ok && newer.layout_supported && newer.button_offset == 48 &&
                    newer.gshift_layout_supported && newer.gshift_button_offset == 112 &&
                    find_rear_thumb_button(&newer) == 4;
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
        package_ok = package.sector_count == 1 && package.sectors[0].sector == 0x0123 &&
                     package.sectors[0].size == 255 &&
                     memcmp(package.sectors[0].data, profile.data, 255) == 0;
        package_release(&package);
    }
    unlink(temp_path);

    uint8_t control_data[255] = {0};
    control_data[2] = 1;
    sector_put_crc(control_data, sizeof(control_data));
    BackupSectorSource combined_sources[2] = {
        {.sector = 0x0123, .size = 255, .data = profile.data},
        {.sector = 0x0000, .size = 255, .data = control_data}};
    char combined_path[] = "/tmp/lomps-selftest-combined-XXXXXX";
    int combined_fd = mkstemp(combined_path);
    if (combined_fd < 0) {
        free(profile.data);
        return 1;
    }
    close(combined_fd);
    unlink(combined_path);
    bool combined_package_ok =
        package_write_multi(combined_path, &dummy_device, 5, combined_sources, 2, true);
    if (combined_package_ok) {
        combined_package_ok = package_read(combined_path, &package);
    }
    if (combined_package_ok) {
        combined_package_ok = package.sector_count == 2 && package.sectors[0].sector == 0x0123 &&
                              package.sectors[1].sector == 0x0000 &&
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
    printf("self-test: receiver model-name fallback, connection types, CRC-16, DPI "
           "sentinel/compaction, format/layout detection, G600 legacy mapping, batch "
           "planning/failure handling, rear-thumb identification, and Alt+Tab encoding passed\n");
    return 0;
}
