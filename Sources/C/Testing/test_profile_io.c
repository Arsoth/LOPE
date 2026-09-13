#include "internal.h"
#include "test_doubles.h"

int test_profile_io(void) {
    const uint8_t sample[] = "123456789";
    if (crc16_ccitt_false(sample, 9) != 0x29B1) {
        fprintf(stderr, "CRC self-test failed\n");
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

    return 0;
}
