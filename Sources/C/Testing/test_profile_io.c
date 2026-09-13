#include "internal.h"
#include "test_doubles.h"

int test_profile_io(void) {
    const uint8_t sample[] = "123456789";
    if (crc16_ccitt_false(sample, 9) != 0x29B1) {
        fprintf(stderr, "CRC self-test failed\n");
        return 1;
    }

    Profile truncated = {0};
    truncated.info.button_count = 1;
    detect_button_layout(&truncated);
    detect_gshift_button_layout(&truncated, NULL);
    detect_dpi_layout(&truncated, NULL);
    detect_rgb_layout(&truncated);
    uint8_t short_data[4] = {0};
    Profile short_profile = {0};
    short_profile.data = short_data;
    short_profile.data_length = sizeof(short_data);
    short_profile.dpi_layout_supported = true;
    short_profile.dpi_offset = 0;
    uint16_t short_dpi[1] = {800};
    bool malformed_profile_ok = !short_profile.layout_supported &&
                                !short_profile.gshift_layout_supported &&
                                !short_profile.rgb_layout_supported &&
                                !write_dpi_stage_table(short_data, &short_profile, short_dpi, 1);
    uint8_t short_rgb_data[RGB_PROFILE_RECORD_BYTES + 1] = {0};
    Profile short_rgb_profile = {0};
    short_rgb_profile.data_length = sizeof(short_rgb_data);
    short_rgb_profile.rgb_layout_supported = true;
    short_rgb_profile.rgb_offset = 0;
    short_rgb_profile.rgb_zone_count = 1;
    short_rgb_profile.rgb_zone_present[0] = true;
    uint8_t short_rgb_zone[1] = {0};
    uint8_t short_rgb_color[1][3] = {{0xAA, 0xBB, 0xCC}};
    malformed_profile_ok =
        malformed_profile_ok && !write_rgb_zone_colors(short_rgb_data, &short_rgb_profile,
                                                       short_rgb_zone, short_rgb_color, 1);
    sector_put_crc(NULL, 0);
    malformed_profile_ok = malformed_profile_ok && !sector_crc_ok(NULL, 2);
    malformed_profile_ok =
        malformed_profile_ok && !adjustable_dpi_values(NULL, NULL, NULL, 0, NULL, NULL);
    if (!malformed_profile_ok) {
        fprintf(stderr, "truncated profile safety self-test failed\n");
        return 1;
    }

    uint8_t disabled_record[4] = {0xFF, 0xFF, 0xFF, 0xFF};
    uint8_t macro_record[4] = {0x20, 0, 0, 0};
    uint8_t mouse_record[4] = {0x80, 0x03, 0, 0};
    uint8_t invalid_mouse_record[4] = {0x80, 0x04, 0, 0};
    uint8_t function_record[4] = {0x90, 0x11, 0, 0};
    uint8_t invalid_function_record[4] = {0x90, 0x12, 0, 0};
    uint8_t unknown_record[4] = {0x30, 0, 0, 0};
    bool spec_validation_ok =
        spec_structurally_valid(disabled_record) && spec_structurally_valid(macro_record) &&
        spec_structurally_valid(mouse_record) && !spec_structurally_valid(invalid_mouse_record) &&
        spec_structurally_valid(function_record) &&
        !spec_structurally_valid(invalid_function_record) &&
        !spec_structurally_valid(unknown_record) && spec_known(disabled_record) &&
        spec_known(mouse_record) && spec_known(function_record) && !spec_known(macro_record) &&
        !spec_known(unknown_record);
    if (!spec_validation_ok) {
        fprintf(stderr, "profile spec validation self-test failed\n");
        return 1;
    }

    ProfileInfo header_info = {.sector_size = 255};
    ProfileHeader parsed_headers[MAX_HEADERS];
    size_t parsed_header_count = 99;
    uint8_t header_control[132] = {0};
    header_control[0] = 0x01;
    header_control[1] = 0x23;
    header_control[2] = 1;
    header_control[4] = 0x02;
    header_control[5] = 0x00;
    bool header_parse_ok =
        parse_profile_headers(NULL, header_control, sizeof(header_control), parsed_headers,
                              &parsed_header_count) == 0 &&
        parse_profile_headers(&header_info, NULL, sizeof(header_control), parsed_headers,
                              &parsed_header_count) == 0 &&
        parse_profile_headers(&header_info, header_control, sizeof(header_control), NULL,
                              &parsed_header_count) == 0 &&
        parse_profile_headers(&header_info, header_control, sizeof(header_control), parsed_headers,
                              NULL) == 0 &&
        parse_profile_headers(&header_info, header_control, sizeof(header_control), parsed_headers,
                              &parsed_header_count) == 1 &&
        parsed_header_count == 2 && parsed_headers[0].sector == 0x0123 &&
        parsed_headers[1].sector == 0x0200;
    uint8_t empty_headers[4] = {0xFF, 0xFF, 0x00, 0x00};
    header_parse_ok = header_parse_ok &&
                      parse_profile_headers(&header_info, empty_headers, sizeof(empty_headers),
                                            parsed_headers, &parsed_header_count) == 0 &&
                      parsed_header_count == 0;
    if (!header_parse_ok) {
        fprintf(stderr, "profile header parsing self-test failed\n");
        return 1;
    }

    HidInterface io_interface = {0};
    Device io_device = {0};
    io_device.iface = &io_interface;
    io_device.feature_count = 1;
    io_device.features[0] = (Feature){.id = FEATURE_ONBOARD_PROFILES, .index = 5};
    ProfileInfo io_info = {.sector_size = 32};
    uint8_t zero_sector[32] = {0};
    uint8_t first_sector[32] = {0};
    first_sector[0] = 0x01;
    first_sector[1] = 0x23;
    Reply zero_chunks[4];
    Reply first_chunks[4];
    size_t zero_chunk_count =
        build_sector_read_replies(zero_sector, sizeof(zero_sector), zero_chunks, 4);
    size_t first_chunk_count =
        build_sector_read_replies(first_sector, sizeof(first_sector), first_chunks, 4);
    Reply fallback_replies[4];
    memcpy(fallback_replies, zero_chunks, zero_chunk_count * sizeof(Reply));
    memcpy(fallback_replies + zero_chunk_count, first_chunks, first_chunk_count * sizeof(Reply));
    ChannelRequestTestContext fallback_context = {
        .replies = fallback_replies,
        .reply_count = zero_chunk_count + first_chunk_count,
        .calls = 0,
    };
    channel_request_impl = channel_request_test_double;
    g_channel_request_test_context = &fallback_context;
    uint8_t control_readback[32] = {0};
    uint16_t control_sector = 99;
    bool control_read_ok =
        read_profile_control(&io_device, &io_info, &control_sector, control_readback,
                             sizeof(control_readback)) == 1 &&
        control_sector == 1 && control_readback[0] == 0x01 &&
        read_profile_control(NULL, &io_info, NULL, control_readback, sizeof(control_readback)) ==
            0 &&
        read_profile_control(&io_device, &io_info, NULL, NULL, sizeof(control_readback)) == 0;
    if (!control_read_ok) {
        fprintf(stderr, "profile control-sector read self-test failed\n");
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

    const Reply profile_info_timeout = {.status = REPLY_TIMEOUT};
    const Reply profile_info_short = {.status = REPLY_OK, .length = 9};
    const Reply profile_info_bad_sector = {
        .status = REPLY_OK,
        .length = 10,
        .bytes = {0, 5, 0, 1, 0, 5, 1, 0, 31, 2},
    };
    const Reply profile_info_bad_buttons = {
        .status = REPLY_OK,
        .length = 10,
        .bytes = {0, 5, 0, 1, 0, 0, 1, 0, 32, 2},
    };
    const Reply profile_info_valid = {
        .status = REPLY_OK,
        .length = 10,
        .bytes = {3, 5, 1, 2, 4, 5, 6, 0, 32, 7},
    };
    ProfileInfo parsed_info;
    const Reply *info_replies[] = {&profile_info_timeout, &profile_info_short,
                                   &profile_info_bad_sector, &profile_info_bad_buttons,
                                   &profile_info_valid};
    bool profile_info_ok = true;
    for (size_t i = 0; i < sizeof(info_replies) / sizeof(info_replies[0]); i++) {
        ChannelRequestTestContext info_context = {
            .replies = info_replies[i],
            .reply_count = 1,
            .calls = 0,
        };
        g_channel_request_test_context = &info_context;
        int result = get_profile_info(&io_device, &parsed_info);
        profile_info_ok =
            profile_info_ok &&
            ((i == sizeof(info_replies) / sizeof(info_replies[0]) - 1) ? result == 1 : result == 0);
    }
    profile_info_ok = profile_info_ok && get_profile_info(NULL, &parsed_info) == 0 &&
                      get_profile_info(&io_device, NULL) == 0 && parsed_info.memory == 3 &&
                      parsed_info.profile_format == 5 && parsed_info.macro_format == 1 &&
                      parsed_info.profile_count == 2 && parsed_info.out_of_band == 4 &&
                      parsed_info.button_count == 5 && parsed_info.sector_count == 6 &&
                      parsed_info.sector_size == 32 && parsed_info.shift_flags == 7;
    if (!profile_info_ok) {
        fprintf(stderr, "profile-info validation self-test failed\n");
        return 1;
    }

    Profile profile;
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
    // find_rear_thumb_button lives in profile_rendering.c; exercised here
    // against this same detect_button_layout fixture rather than duplicating it.
    int rear = find_rear_thumb_button(&profile);
    bool passed = profile.crc_ok && profile.layout_supported && profile.button_offset == 32 &&
                  profile.gshift_layout_supported && profile.gshift_button_offset == 96 &&
                  profile.dpi_layout_supported && profile.dpi_offset == 3 &&
                  read_le16(profile.data + profile.dpi_offset + 2 * 2) == 1600 && rear == 4 &&
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

    uint8_t diagnostic_data[70] = {0};
    diagnostic_data[7] = 0x80;
    diagnostic_data[8] = 0x01;
    diagnostic_data[10] = 0x00;
    diagnostic_data[11] = 0x01;
    Profile diagnostic_profile = {0};
    diagnostic_profile.info.button_count = 1;
    diagnostic_profile.data = diagnostic_data;
    diagnostic_profile.data_length = sizeof(diagnostic_data);
    detect_button_layout(&diagnostic_profile);
    bool layout_edge_ok = !diagnostic_profile.layout_supported &&
                          diagnostic_profile.button_offset == 7 &&
                          diagnostic_profile.known_specs == 1;

    uint8_t fallback_data[70] = {0};
    memcpy(fallback_data + 32, specs[0], sizeof(specs[0]));
    Profile fallback_profile = {0};
    fallback_profile.info.profile_format = 7;
    fallback_profile.info.button_count = 1;
    fallback_profile.data = fallback_data;
    fallback_profile.data_length = sizeof(fallback_data);
    detect_button_layout(&fallback_profile);
    layout_edge_ok = layout_edge_ok && !fallback_profile.layout_supported &&
                     fallback_profile.button_offset == 32;
    layout_edge_ok = layout_edge_ok && !profile_reports_gshift(NULL, NULL) && !is_g603_device(NULL);
    Profile gshift_short = {0};
    gshift_short.info.shift_flags = 0x02;
    gshift_short.info.button_count = 1;
    gshift_short.layout_supported = true;
    gshift_short.data = short_data;
    gshift_short.data_length = sizeof(short_data);
    detect_gshift_button_layout(&gshift_short, NULL);
    layout_edge_ok = layout_edge_ok && !gshift_short.gshift_layout_supported;

    uint8_t invalid_dpi_data[15] = {0};
    Profile invalid_dpi = {0};
    invalid_dpi.info.profile_format = 5;
    invalid_dpi.data = invalid_dpi_data;
    invalid_dpi.data_length = sizeof(invalid_dpi_data);
    write_le16(invalid_dpi_data + 3, 800);
    write_le16(invalid_dpi_data + 5, 1200);
    write_le16(invalid_dpi_data + 7, 0);
    write_le16(invalid_dpi_data + 9, 1600);
    invalid_dpi_data[1] = 2;
    invalid_dpi_data[2] = 0;
    detect_dpi_layout(&invalid_dpi, NULL);
    bool dpi_edge_ok = !invalid_dpi.dpi_layout_supported;
    invalid_dpi.info.profile_format = 6;
    detect_dpi_layout(&invalid_dpi, NULL);
    dpi_edge_ok = dpi_edge_ok && !invalid_dpi.dpi_layout_supported;
    Profile no_rgb = {0};
    uint8_t no_rgb_data[255] = {0};
    no_rgb.info.profile_format = 5;
    no_rgb.data = no_rgb_data;
    no_rgb.data_length = sizeof(no_rgb_data);
    memset(no_rgb_data + RGB_PROFILE_BASE_OFFSET, 0xFF,
           RGB_PROFILE_RECORD_BYTES * RGB_PROFILE_RECORD_COUNT);
    detect_rgb_layout(&no_rgb);
    dpi_edge_ok = dpi_edge_ok && !no_rgb.rgb_layout_supported;
    if (!layout_edge_ok || !dpi_edge_ok) {
        fprintf(stderr, "profile layout edge-case self-test failed\n");
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

    uint8_t mock_sector[255];
    build_mock_onboard_sector(mock_sector);
    uint8_t mock_control[132];
    build_mock_control_sector(mock_control);

    Reply load_selected_replies[1 + 16 + 32];
    size_t load_selected_reply_count = 0;
    load_selected_replies[load_selected_reply_count++] = k_mock_get_info_reply;
    Reply control_chunks[16];
    size_t control_chunk_count =
        build_sector_read_replies(mock_control, sizeof(mock_control), control_chunks, 16);
    for (size_t i = 0; i < control_chunk_count; i++) {
        load_selected_replies[load_selected_reply_count++] = control_chunks[i];
    }
    Reply data_chunks[32];
    size_t data_chunk_count =
        build_sector_read_replies(mock_sector, sizeof(mock_sector), data_chunks, 32);
    for (size_t i = 0; i < data_chunk_count; i++) {
        load_selected_replies[load_selected_reply_count++] = data_chunks[i];
    }
    if (control_chunk_count == 0 || data_chunk_count == 0) {
        fprintf(stderr, "mock sector-read reply generation self-test failed\n");
        return 1;
    }

    HidInterface load_selected_interface = {0};
    Device load_selected_device = {0};
    load_selected_device.iface = &load_selected_interface;
    load_selected_device.feature_count = 1;
    load_selected_device.features[0] = (Feature){.id = FEATURE_ONBOARD_PROFILES, .index = 5};

    channel_request_impl = channel_request_test_double;
    ChannelRequestTestContext load_selected_context = {
        .replies = load_selected_replies, .reply_count = load_selected_reply_count, .calls = 0};
    g_channel_request_test_context = &load_selected_context;

    Profile loaded_profile;
    bool load_selected_ok =
        load_selected_profile(&load_selected_device, 0, &loaded_profile) && loaded_profile.crc_ok &&
        loaded_profile.dpi_layout_supported && loaded_profile.layout_supported &&
        loaded_profile.button_offset == 32 && loaded_profile.gshift_layout_supported &&
        loaded_profile.gshift_button_offset == 96 && loaded_profile.rgb_layout_supported &&
        loaded_profile.rgb_zone_count == 2 && loaded_profile.header_count == 1 &&
        loaded_profile.selected_header == 0 && loaded_profile.headers[0].sector == 0x0123;
    if (load_selected_ok) {
        free(loaded_profile.data);
    }
    if (!load_selected_ok) {
        fprintf(stderr, "load_selected_profile self-test failed\n");
        return 1;
    }

    Reply write_ok_reply = {.status = REPLY_OK};
    Reply write_replies[18];
    size_t write_reply_count = 0;
    write_replies[write_reply_count++] = write_ok_reply; // startWrite
    for (size_t i = 0; i < 16; i++) {
        write_replies[write_reply_count++] = write_ok_reply; // writeData chunks
    }
    write_replies[write_reply_count++] = write_ok_reply; // endWrite
    ChannelRequestTestContext write_sector_context = {
        .replies = write_replies, .reply_count = write_reply_count, .calls = 0};
    g_channel_request_test_context = &write_sector_context;
    bool write_sector_ok =
        write_sector(&load_selected_device, 0x0123, mock_sector, sizeof(mock_sector)) &&
        !write_sector(&load_selected_device, 0x0123, mock_sector, 1) &&
        !write_sector(&load_selected_device, 0x0123, mock_sector, MAX_SECTOR_BYTES + 1);

    Reply write_start_fail_replies[1] = {(Reply){.status = REPLY_TIMEOUT}};
    ChannelRequestTestContext write_start_fail_context = {
        .replies = write_start_fail_replies, .reply_count = 1, .calls = 0};
    g_channel_request_test_context = &write_start_fail_context;
    write_sector_ok = write_sector_ok && !write_sector(&load_selected_device, 0x0123, mock_sector,
                                                       sizeof(mock_sector));

    Reply write_data_fail_replies[2] = {write_ok_reply, (Reply){.status = REPLY_TIMEOUT}};
    ChannelRequestTestContext write_data_fail_context = {
        .replies = write_data_fail_replies, .reply_count = 2, .calls = 0};
    g_channel_request_test_context = &write_data_fail_context;
    write_sector_ok = write_sector_ok && !write_sector(&load_selected_device, 0x0123, mock_sector,
                                                       sizeof(mock_sector));

    Reply write_end_fail_replies[18];
    for (size_t i = 0; i < 17; i++) {
        write_end_fail_replies[i] = write_ok_reply;
    }
    write_end_fail_replies[17] = (Reply){.status = REPLY_TIMEOUT};
    ChannelRequestTestContext write_end_fail_context = {
        .replies = write_end_fail_replies, .reply_count = 18, .calls = 0};
    g_channel_request_test_context = &write_end_fail_context;
    write_sector_ok = write_sector_ok && !write_sector(&load_selected_device, 0x0123, mock_sector,
                                                       sizeof(mock_sector));
    if (!write_sector_ok) {
        fprintf(stderr, "write_sector self-test failed\n");
        return 1;
    }

    ChannelRequestTestContext verify_readback_context = {
        .replies = data_chunks, .reply_count = data_chunk_count, .calls = 0};
    g_channel_request_test_context = &verify_readback_context;
    bool verify_readback_ok =
        verify_sector_readback(&load_selected_device, 0x0123, mock_sector, sizeof(mock_sector));

    uint8_t mismatched_sector[255];
    memcpy(mismatched_sector, mock_sector, sizeof(mock_sector));
    mismatched_sector[10] ^= 0xFF;
    ChannelRequestTestContext verify_readback_mismatch_context = {
        .replies = data_chunks, .reply_count = data_chunk_count, .calls = 0};
    g_channel_request_test_context = &verify_readback_mismatch_context;
    verify_readback_ok =
        verify_readback_ok && !verify_sector_readback(&load_selected_device, 0x0123,
                                                      mismatched_sector, sizeof(mismatched_sector));
    if (!verify_readback_ok) {
        fprintf(stderr, "verify_sector_readback self-test failed\n");
        return 1;
    }

    Reply onboard_mode_host_replies[] = {
        (Reply){.status = REPLY_OK, .length = 1, .bytes = {ONBOARD_MODE_HOST}},
        (Reply){.status = REPLY_OK},
        (Reply){.status = REPLY_OK, .length = 1, .bytes = {ONBOARD_MODE_ONBOARD}},
    };
    ChannelRequestTestContext onboard_mode_host_context = {
        .replies = onboard_mode_host_replies, .reply_count = 3, .calls = 0};
    g_channel_request_test_context = &onboard_mode_host_context;
    uint8_t onboard_mode_value = 0;
    bool onboard_mode_ok = ensure_onboard_mode_for_write(&load_selected_device) &&
                           get_onboard_mode(&load_selected_device, &onboard_mode_value) == false;

    Reply onboard_mode_already_replies[] = {
        (Reply){.status = REPLY_OK, .length = 1, .bytes = {ONBOARD_MODE_ONBOARD}}};
    ChannelRequestTestContext onboard_mode_already_context = {
        .replies = onboard_mode_already_replies, .reply_count = 1, .calls = 0};
    g_channel_request_test_context = &onboard_mode_already_context;
    onboard_mode_ok = onboard_mode_ok && ensure_onboard_mode_for_write(&load_selected_device);

    Reply onboard_mode_query_fail_replies[] = {(Reply){.status = REPLY_TIMEOUT}};
    ChannelRequestTestContext onboard_mode_query_fail_context = {
        .replies = onboard_mode_query_fail_replies, .reply_count = 1, .calls = 0};
    g_channel_request_test_context = &onboard_mode_query_fail_context;
    onboard_mode_ok = onboard_mode_ok && ensure_onboard_mode_for_write(&load_selected_device);

    Reply onboard_mode_switch_fail_replies[] = {
        (Reply){.status = REPLY_OK, .length = 1, .bytes = {ONBOARD_MODE_HOST}},
        (Reply){.status = REPLY_TIMEOUT},
    };
    ChannelRequestTestContext onboard_mode_switch_fail_context = {
        .replies = onboard_mode_switch_fail_replies, .reply_count = 2, .calls = 0};
    g_channel_request_test_context = &onboard_mode_switch_fail_context;
    onboard_mode_ok = onboard_mode_ok && !ensure_onboard_mode_for_write(&load_selected_device);
    if (!onboard_mode_ok) {
        fprintf(stderr, "onboard-mode self-test failed\n");
        return 1;
    }

    const Reply dpi_values_replies[] = {
        (Reply){.status = REPLY_OK, .length = 1, .bytes = {0}},
        (Reply){.status = REPLY_OK, .length = 7, .bytes = {0, 0x03, 0x20, 0xE0, 0x02, 0x03, 0x25}},
        (Reply){.status = REPLY_OK, .length = 3, .bytes = {0, 0x03, 0x25}},
    };
    io_device.features[0] = (Feature){.id = FEATURE_ADJUSTABLE_DPI, .index = 5};
    ChannelRequestTestContext dpi_values_context = {
        .replies = dpi_values_replies,
        .reply_count = 3,
        .calls = 0,
    };
    g_channel_request_test_context = &dpi_values_context;
    uint16_t adjustable_values[8] = {0};
    size_t adjustable_value_count = 0;
    uint8_t adjustable_sensor_count = 0;
    uint16_t adjustable_current = 0;
    bool adjustable_values_ok =
        adjustable_dpi_values(&io_device, adjustable_values, &adjustable_value_count,
                              sizeof(adjustable_values) / sizeof(adjustable_values[0]),
                              &adjustable_sensor_count, &adjustable_current) == 1 &&
        adjustable_value_count == 4 && adjustable_values[0] == 800 && adjustable_values[1] == 802 &&
        adjustable_values[2] == 804 && adjustable_values[3] == 805 &&
        adjustable_sensor_count == 1 && adjustable_current == 805;

    const Reply dpi_range_no_end[] = {
        (Reply){.status = REPLY_OK, .length = 1, .bytes = {1}},
        (Reply){.status = REPLY_OK, .length = 3, .bytes = {0, 0xE0, 0x02}},
    };
    const Reply dpi_range_zero_step[] = {
        (Reply){.status = REPLY_OK, .length = 1, .bytes = {1}},
        (Reply){.status = REPLY_OK, .length = 7, .bytes = {0, 0x03, 0x20, 0xE0, 0x00, 0x03, 0x25}},
    };
    const Reply dpi_range_descending[] = {
        (Reply){.status = REPLY_OK, .length = 1, .bytes = {1}},
        (Reply){.status = REPLY_OK, .length = 7, .bytes = {0, 0x03, 0x20, 0xE0, 0x02, 0x03, 0x1F}},
    };
    const Reply dpi_range_first[] = {
        (Reply){.status = REPLY_OK, .length = 1, .bytes = {1}},
        (Reply){.status = REPLY_OK, .length = 5, .bytes = {0, 0xE0, 0x02, 0x03, 0x25}},
    };
    const Reply dpi_sensor_count_fail[] = {(Reply){.status = REPLY_TIMEOUT}};
    const Reply dpi_list_fail[] = {
        (Reply){.status = REPLY_OK, .length = 1, .bytes = {1}},
        (Reply){.status = REPLY_TIMEOUT},
    };
    const Reply dpi_current_fail[] = {
        dpi_values_replies[0],
        dpi_values_replies[1],
        (Reply){.status = REPLY_TIMEOUT},
    };
    const struct {
        const Reply *replies;
        size_t count;
        size_t capacity;
        bool expected;
    } dpi_invalid_cases[] = {
        {dpi_range_no_end, 2, 8, false},      {dpi_range_zero_step, 2, 8, false},
        {dpi_range_descending, 2, 8, false},  {dpi_range_first, 2, 8, false},
        {dpi_sensor_count_fail, 1, 8, false}, {dpi_list_fail, 2, 8, false},
        {dpi_current_fail, 3, 8, false},      {dpi_values_replies, 3, 2, false},
    };
    for (size_t i = 0; i < sizeof(dpi_invalid_cases) / sizeof(dpi_invalid_cases[0]); i++) {
        ChannelRequestTestContext invalid_dpi_context = {
            .replies = dpi_invalid_cases[i].replies,
            .reply_count = dpi_invalid_cases[i].count,
            .calls = 0,
        };
        g_channel_request_test_context = &invalid_dpi_context;
        size_t invalid_count = 0;
        adjustable_values_ok =
            adjustable_values_ok &&
            (adjustable_dpi_values(&io_device, adjustable_values, &invalid_count,
                                   dpi_invalid_cases[i].capacity, NULL,
                                   &adjustable_current) == (dpi_invalid_cases[i].expected ? 1 : 0));
    }
    Device no_dpi_device = io_device;
    no_dpi_device.feature_count = 0;
    adjustable_values_ok =
        adjustable_values_ok && adjustable_dpi_values(&no_dpi_device, adjustable_values,
                                                      &adjustable_value_count, 8, NULL, NULL) == 0;
    if (!adjustable_values_ok) {
        fprintf(stderr, "adjustable DPI value decoding self-test failed\n");
        return 1;
    }

    return 0;
}
