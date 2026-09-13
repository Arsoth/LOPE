#include "internal.h"

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

typedef struct {
    const Reply *replies;
    size_t reply_count;
    size_t calls;
} ChannelRequestTestContext;

static ChannelRequestTestContext *g_channel_request_test_context = NULL;

// Test seam for channel_request_impl (see the HID transport module):
// replays canned replies in order so device_call/raw_request logic can be
// exercised without real IOKit hardware.
static Reply channel_request_test_double(HidChannel *channel, uint8_t device_number,
                                         uint16_t request_id, const uint8_t *params,
                                         size_t params_length, bool prefer_long,
                                         double timeout_seconds) {
    (void)channel;
    (void)device_number;
    (void)request_id;
    (void)params;
    (void)params_length;
    (void)prefer_long;
    (void)timeout_seconds;
    ChannelRequestTestContext *test = g_channel_request_test_context;
    if (test == NULL || test->calls >= test->reply_count) {
        Reply timeout_reply;
        memset(&timeout_reply, 0, sizeof(timeout_reply));
        timeout_reply.status = REPLY_TIMEOUT;
        return timeout_reply;
    }
    return test->replies[test->calls++];
}

typedef struct {
    const Device *devices;
    size_t count;
    int result;
} DiscoverDevicesTestContext;

static DiscoverDevicesTestContext *g_discover_devices_test_context = NULL;

// Test seam for discover_devices_for_options_impl (see
// HID discovery module): hands back a canned Device list so
// command-layer entry points (run_info, run_dpi, run_bind, ...) can be
// exercised without real IOKit hardware. Pairs with channel_request_impl,
// which mocks the HID++ traffic those commands make afterward.
static int discover_devices_for_options_test_double(HidContext *context, const Options *options,
                                                    Device *devices, size_t *count) {
    (void)context;
    (void)options;
    if (g_discover_devices_test_context == NULL) {
        *count = 0;
        return 0;
    }
    *count = g_discover_devices_test_context->count;
    for (size_t i = 0; i < *count; i++) {
        devices[i] = g_discover_devices_test_context->devices[i];
    }
    return g_discover_devices_test_context->result;
}

// Mirrors read_sector's chunking exactly (see the profile I/O module)
// so a full sector buffer can be turned into the sequence of 16-byte
// ONBOARD_READ_SECTOR replies that function expects, without needing real
// hardware. Returns the number of replies written, or 0 if capacity is too
// small.
static size_t build_sector_read_replies(const uint8_t *sector, size_t size, Reply *out,
                                        size_t capacity) {
    size_t count = 0;
    size_t copied = 0;
    while (copied < size) {
        size_t request_offset = copied;
        if (size - copied < 16) {
            request_offset = size - 16;
        }
        if (count >= capacity) {
            return 0;
        }
        Reply chunk;
        memset(&chunk, 0, sizeof(chunk));
        chunk.status = REPLY_OK;
        chunk.length = 16;
        memcpy(chunk.bytes, sector + request_offset, 16);
        out[count++] = chunk;
        size_t from = copied > request_offset ? copied - request_offset : 0;
        size_t take = 16 - from;
        if (take > size - copied) {
            take = size - copied;
        }
        copied += take;
    }
    return count;
}

int run_self_test(void) {
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

    bool interval_conversion_ok =
        report_rate_hertz_from_interval(0) == 0 && report_rate_hertz_from_interval(8) == 125 &&
        report_rate_hertz_from_interval(4) == 250 && report_rate_hertz_from_interval(2) == 500 &&
        report_rate_hertz_from_interval(1) == 1000 && report_rate_hertz_from_interval(3) == 333;
    if (!interval_conversion_ok) {
        fprintf(stderr, "report-rate interval conversion self-test failed\n");
        return 1;
    }

    ReportRateEntry rate_entries[MAX_REPORT_RATES];
    bool entries_from_mask_ok =
        report_rate_entries_from_mask(FEATURE_EXTENDED_REPORT_RATE, 0xFF, NULL, MAX_REPORT_RATES) ==
            0 &&
        report_rate_entries_from_mask(FEATURE_EXTENDED_REPORT_RATE, 0xFF, rate_entries, 0) == 0 &&
        report_rate_entries_from_mask(0x0000, 0xFF, rate_entries, MAX_REPORT_RATES) == 0;
    size_t extended_count = report_rate_entries_from_mask(
        FEATURE_EXTENDED_REPORT_RATE, (uint16_t)((1u << 0) | (1u << 3) | (1u << 6)), rate_entries,
        MAX_REPORT_RATES);
    entries_from_mask_ok = entries_from_mask_ok && extended_count == 3 &&
                           rate_entries[0].hertz == 125 && rate_entries[0].wire_value == 0 &&
                           rate_entries[1].hertz == 1000 && rate_entries[1].wire_value == 3 &&
                           rate_entries[2].hertz == 8000 && rate_entries[2].wire_value == 6;
    size_t adjustable_count = report_rate_entries_from_mask(
        FEATURE_ADJUSTABLE_REPORT_RATE, (uint16_t)((1u << 0) | (1u << 3) | (1u << 7)), rate_entries,
        MAX_REPORT_RATES);
    entries_from_mask_ok = entries_from_mask_ok && adjustable_count == 3 &&
                           rate_entries[0].hertz == 125 && rate_entries[0].wire_value == 8 &&
                           rate_entries[1].hertz == 250 && rate_entries[1].wire_value == 4 &&
                           rate_entries[2].hertz == 1000 && rate_entries[2].wire_value == 1;
    if (!entries_from_mask_ok) {
        fprintf(stderr, "report-rate mask decoding self-test failed\n");
        return 1;
    }

    HidInterface lightspeed_interface = {0};
    Device lightspeed_device = {0};
    lightspeed_device.iface = &lightspeed_interface;
    lightspeed_device.device_number = 1;
    lightspeed_interface.product_id = 0xC539;
    HidInterface wireless_interface = {0};
    Device wireless_device = {0};
    wireless_device.iface = &wireless_interface;
    wireless_device.device_number = 0xFF;
    wireless_interface.product_id = 0x4050;
    HidInterface wired_interface = {0};
    Device wired_device = {0};
    wired_device.iface = &wired_interface;
    wired_device.device_number = 0xFF;
    wired_interface.product_id = 0xC09A;
    bool connection_type_ok = report_rate_connection_type(&lightspeed_device) == 1 &&
                              report_rate_connection_type(&wireless_device) == 1 &&
                              report_rate_connection_type(&wired_device) == 0;
    if (!connection_type_ok) {
        fprintf(stderr, "report-rate connection-type self-test failed\n");
        return 1;
    }

    uint32_t parsed_hertz = 0;
    bool hertz_parser_ok = parse_report_rate_hertz("1000", &parsed_hertz) && parsed_hertz == 1000 &&
                           !parse_report_rate_hertz(NULL, &parsed_hertz) &&
                           !parse_report_rate_hertz("1000", NULL) &&
                           !parse_report_rate_hertz("", &parsed_hertz) &&
                           !parse_report_rate_hertz("0", &parsed_hertz) &&
                           !parse_report_rate_hertz("abc", &parsed_hertz) &&
                           !parse_report_rate_hertz("12x", &parsed_hertz);
    if (!hertz_parser_ok) {
        fprintf(stderr, "report-rate hertz parser self-test failed\n");
        return 1;
    }

    ReportRateCapabilities print_capabilities;
    memset(&print_capabilities, 0, sizeof(print_capabilities));
    print_capabilities.feature_id = FEATURE_EXTENDED_REPORT_RATE;
    print_capabilities.rate_count = 2;
    print_capabilities.rates[0] = (ReportRateEntry){125, 0};
    print_capabilities.rates[1] = (ReportRateEntry){1000, 3};
    print_capabilities.current_valid = true;
    print_capabilities.current_hertz = 1000;
    char print_path[] = "/tmp/lomps-selftest-print-XXXXXX";
    int print_fd = mkstemp(print_path);
    if (print_fd < 0) {
        fprintf(stderr, "report-rate print self-test failed to create temp file\n");
        return 1;
    }
    close(print_fd);
    int saved_stdout = dup(fileno(stdout));
    bool print_ok = saved_stdout >= 0 && freopen(print_path, "w", stdout) != NULL;
    if (print_ok) {
        print_report_rate_capabilities(&print_capabilities);
        print_capabilities.current_valid = false;
        print_report_rate_capabilities(&print_capabilities);
        fflush(stdout);
    }
    if (saved_stdout >= 0) {
        dup2(saved_stdout, fileno(stdout));
        close(saved_stdout);
        clearerr(stdout);
    }
    char print_contents[512] = {0};
    if (print_ok) {
        FILE *readback = fopen(print_path, "r");
        if (readback != NULL) {
            size_t read_bytes = fread(print_contents, 1, sizeof(print_contents) - 1, readback);
            print_contents[read_bytes] = '\0';
            fclose(readback);
        } else {
            print_ok = false;
        }
    }
    unlink(print_path);
    print_ok =
        print_ok && strstr(print_contents, "Report rate feature: 0x8061") != NULL &&
        strstr(print_contents, "Supported polling rates: 125, 1000") != NULL &&
        strstr(print_contents, "Current polling rate: 1000 Hz") != NULL &&
        strstr(print_contents, "Report rate error: current polling rate could not be read") != NULL;
    if (!print_ok) {
        fprintf(stderr, "report-rate capabilities print self-test failed\n");
        return 1;
    }

    channel_request_impl = channel_request_test_double;

    HidInterface capability_interface = {0};
    Device capability_device = {0};
    capability_device.iface = &capability_interface;

    const Reply extended_replies[] = {
        (Reply){.status = REPLY_OK, .length = 2, .bytes = {0x00, 0x49}},
        (Reply){.status = REPLY_OK, .length = 1, .bytes = {0x03}},
    };
    ChannelRequestTestContext extended_context = {
        .replies = extended_replies, .reply_count = 2, .calls = 0};
    capability_device.feature_count = 1;
    capability_device.features[0] = (Feature){.id = FEATURE_EXTENDED_REPORT_RATE, .index = 1};
    g_channel_request_test_context = &extended_context;
    ReportRateCapabilities extended_capabilities;
    bool extended_ok =
        read_report_rate_capabilities(&capability_device, &extended_capabilities) &&
        extended_capabilities.feature_id == FEATURE_EXTENDED_REPORT_RATE &&
        extended_capabilities.supported_mask == 0x49 && extended_capabilities.rate_count == 3 &&
        extended_capabilities.rates[0].hertz == 125 &&
        extended_capabilities.rates[1].hertz == 1000 &&
        extended_capabilities.rates[2].hertz == 8000 && extended_capabilities.current_valid &&
        extended_capabilities.current_hertz == 1000;

    const Reply extended_unmatched_replies[] = {
        (Reply){.status = REPLY_OK, .length = 2, .bytes = {0x00, 0x49}},
        (Reply){.status = REPLY_OK, .length = 1, .bytes = {0x07}},
    };
    ChannelRequestTestContext extended_unmatched_context = {
        .replies = extended_unmatched_replies, .reply_count = 2, .calls = 0};
    g_channel_request_test_context = &extended_unmatched_context;
    ReportRateCapabilities extended_unmatched_capabilities;
    extended_ok =
        extended_ok &&
        read_report_rate_capabilities(&capability_device, &extended_unmatched_capabilities) &&
        !extended_unmatched_capabilities.current_valid;

    const Reply extended_timeout_replies[] = {(Reply){.status = REPLY_TIMEOUT}};
    ChannelRequestTestContext extended_timeout_context = {
        .replies = extended_timeout_replies, .reply_count = 1, .calls = 0};
    g_channel_request_test_context = &extended_timeout_context;
    ReportRateCapabilities extended_timeout_capabilities;
    extended_ok = extended_ok && !read_report_rate_capabilities(&capability_device,
                                                                &extended_timeout_capabilities);

    const Reply extended_empty_mask_replies[] = {
        (Reply){.status = REPLY_OK, .length = 2, .bytes = {0x00, 0x00}}};
    ChannelRequestTestContext extended_empty_mask_context = {
        .replies = extended_empty_mask_replies, .reply_count = 1, .calls = 0};
    g_channel_request_test_context = &extended_empty_mask_context;
    ReportRateCapabilities extended_empty_mask_capabilities;
    extended_ok = extended_ok && !read_report_rate_capabilities(&capability_device,
                                                                &extended_empty_mask_capabilities);
    if (!extended_ok) {
        fprintf(stderr, "extended report-rate capability read self-test failed\n");
        return 1;
    }

    const Reply adjustable_replies[] = {
        (Reply){.status = REPLY_OK, .length = 1, .bytes = {0x81}},
        (Reply){.status = REPLY_OK, .length = 1, .bytes = {0x01}},
    };
    ChannelRequestTestContext adjustable_context = {
        .replies = adjustable_replies, .reply_count = 2, .calls = 0};
    capability_device.features[0] = (Feature){.id = FEATURE_ADJUSTABLE_REPORT_RATE, .index = 1};
    g_channel_request_test_context = &adjustable_context;
    ReportRateCapabilities adjustable_capabilities;
    bool adjustable_ok =
        read_report_rate_capabilities(&capability_device, &adjustable_capabilities) &&
        adjustable_capabilities.feature_id == FEATURE_ADJUSTABLE_REPORT_RATE &&
        adjustable_capabilities.supported_mask == 0x81 && adjustable_capabilities.rate_count == 2 &&
        adjustable_capabilities.rates[0].hertz == 125 &&
        adjustable_capabilities.rates[1].hertz == 1000 && adjustable_capabilities.current_valid &&
        adjustable_capabilities.current_hertz == 1000;

    const Reply adjustable_invalid_index_replies[] = {
        (Reply){.status = REPLY_OK, .length = 1, .bytes = {0x81}},
        (Reply){.status = REPLY_OK, .length = 1, .bytes = {0x00}},
    };
    ChannelRequestTestContext adjustable_invalid_index_context = {
        .replies = adjustable_invalid_index_replies, .reply_count = 2, .calls = 0};
    g_channel_request_test_context = &adjustable_invalid_index_context;
    ReportRateCapabilities adjustable_invalid_index_capabilities;
    adjustable_ok =
        adjustable_ok &&
        read_report_rate_capabilities(&capability_device, &adjustable_invalid_index_capabilities) &&
        !adjustable_invalid_index_capabilities.current_valid;

    const Reply adjustable_empty_mask_replies[] = {
        (Reply){.status = REPLY_OK, .length = 1, .bytes = {0x00}}};
    ChannelRequestTestContext adjustable_empty_mask_context = {
        .replies = adjustable_empty_mask_replies, .reply_count = 1, .calls = 0};
    g_channel_request_test_context = &adjustable_empty_mask_context;
    ReportRateCapabilities adjustable_empty_mask_capabilities;
    adjustable_ok = adjustable_ok && !read_report_rate_capabilities(
                                         &capability_device, &adjustable_empty_mask_capabilities);

    Device no_feature_device = {0};
    HidInterface no_feature_interface = {0};
    no_feature_device.iface = &no_feature_interface;
    ReportRateCapabilities no_feature_capabilities;
    adjustable_ok = adjustable_ok &&
                    !read_report_rate_capabilities(NULL, &adjustable_capabilities) &&
                    !read_report_rate_capabilities(&no_feature_device, NULL) &&
                    !read_report_rate_capabilities(&no_feature_device, &no_feature_capabilities);
    if (!adjustable_ok) {
        fprintf(stderr, "adjustable report-rate capability read self-test failed\n");
        return 1;
    }

    capability_device.features[0] = (Feature){.id = FEATURE_ADJUSTABLE_REPORT_RATE, .index = 1};
    ChannelRequestTestContext profile_interval_context = {
        .replies = adjustable_replies, .reply_count = 2, .calls = 0};
    g_channel_request_test_context = &profile_interval_context;
    uint8_t profile_interval_ms = 0;
    bool profile_interval_ok =
        report_rate_profile_interval(&capability_device, 1000, &profile_interval_ms) &&
        profile_interval_ms == 1 &&
        !report_rate_profile_interval(NULL, 1000, &profile_interval_ms) &&
        !report_rate_profile_interval(&capability_device, 1000, NULL);

    profile_interval_context.calls = 0;
    profile_interval_context.replies = extended_replies;
    capability_device.features[0] = (Feature){.id = FEATURE_EXTENDED_REPORT_RATE, .index = 1};
    profile_interval_ok =
        profile_interval_ok &&
        !report_rate_profile_interval(&capability_device, 8000, &profile_interval_ms);

    profile_interval_context.calls = 0;
    profile_interval_ok =
        profile_interval_ok &&
        report_rate_profile_interval(&capability_device, 125, &profile_interval_ms) &&
        profile_interval_ms == 8;

    profile_interval_context.calls = 0;
    profile_interval_ok =
        profile_interval_ok &&
        !report_rate_profile_interval(&capability_device, 9999, &profile_interval_ms);

    ChannelRequestTestContext profile_interval_no_feature_context = {
        .replies = NULL, .reply_count = 0, .calls = 0};
    g_channel_request_test_context = &profile_interval_no_feature_context;
    profile_interval_ok =
        profile_interval_ok &&
        !report_rate_profile_interval(&no_feature_device, 1000, &profile_interval_ms);
    if (!profile_interval_ok) {
        fprintf(stderr, "report-rate profile-interval self-test failed\n");
        return 1;
    }

    HidInterface select_interface_a = {0};
    select_interface_a.location_id = 0x1234;
    select_interface_a.registry_id = 0x5678;
    HidInterface select_interface_b = {0};
    select_interface_b.location_id = 0xAAAA;
    select_interface_b.registry_id = 0xBBBB;
    HidInterface select_interface_c = {0};
    Device select_devices[3];
    memset(select_devices, 0, sizeof(select_devices));
    select_devices[0].iface = &select_interface_a;
    select_devices[0].device_number = 0xFF;
    select_devices[0].request_device_number = 0xFF;
    select_devices[0].protocol = 1.0;
    select_devices[1].iface = &select_interface_b;
    select_devices[1].device_number = 1;
    select_devices[1].request_device_number = 1;
    select_devices[1].protocol = 2.0;
    select_devices[2].iface = &select_interface_c;
    select_devices[2].device_number = 0xFF;
    select_devices[2].request_device_number = 0xFF;
    select_devices[2].protocol = 1.0;

    Options select_options;
    memset(&select_options, 0, sizeof(select_options));
    select_options.device_index = -1;
    Device *selected = NULL;
    bool select_device_ok = !select_device(select_devices, 0, &select_options, &selected);

    select_options.device_key = "aaaa-bbbb-01";
    select_device_ok = select_device_ok &&
                       select_device(select_devices, 3, &select_options, &selected) &&
                       selected == &select_devices[1];

    select_options.device_key = "0000-0000-00";
    select_device_ok =
        select_device_ok && !select_device(select_devices, 3, &select_options, &selected);

    select_options.device_key = NULL;
    select_options.device_index = 2;
    select_device_ok = select_device_ok &&
                       select_device(select_devices, 3, &select_options, &selected) &&
                       selected == &select_devices[2];

    select_options.device_index = 5;
    select_device_ok =
        select_device_ok && !select_device(select_devices, 3, &select_options, &selected);

    select_options.device_index = -1;
    select_device_ok = select_device_ok &&
                       select_device(select_devices, 3, &select_options, &selected) &&
                       selected == &select_devices[1];

    Device fallback_devices[1];
    memset(fallback_devices, 0, sizeof(fallback_devices));
    HidInterface fallback_interface = {0};
    fallback_devices[0].iface = &fallback_interface;
    fallback_devices[0].device_number = 0xFF;
    fallback_devices[0].protocol = 1.0;
    select_device_ok = select_device_ok &&
                       select_device(fallback_devices, 1, &select_options, &selected) &&
                       selected == &fallback_devices[0];
    if (!select_device_ok) {
        fprintf(stderr, "select_device self-test failed\n");
        return 1;
    }

    uint16_t regular_dpi[4] = {800, 1600, 2400, 3200};
    uint16_t irregular_dpi[3] = {800, 1600, 2000};
    uint16_t single_dpi[1] = {800};
    char dpi_print_path[] = "/tmp/lomps-selftest-dpi-XXXXXX";
    int dpi_print_fd = mkstemp(dpi_print_path);
    if (dpi_print_fd < 0) {
        fprintf(stderr, "print_supported_dpi self-test failed to create temp file\n");
        return 1;
    }
    close(dpi_print_fd);
    int dpi_saved_stdout = dup(fileno(stdout));
    bool dpi_print_ok = dpi_saved_stdout >= 0 && freopen(dpi_print_path, "w", stdout) != NULL;
    if (dpi_print_ok) {
        print_supported_dpi(regular_dpi, 4);
        print_supported_dpi(irregular_dpi, 3);
        print_supported_dpi(single_dpi, 1);
        fflush(stdout);
    }
    if (dpi_saved_stdout >= 0) {
        dup2(dpi_saved_stdout, fileno(stdout));
        close(dpi_saved_stdout);
        clearerr(stdout);
    }
    char dpi_print_contents[512] = {0};
    if (dpi_print_ok) {
        FILE *readback = fopen(dpi_print_path, "r");
        if (readback != NULL) {
            size_t read_bytes =
                fread(dpi_print_contents, 1, sizeof(dpi_print_contents) - 1, readback);
            dpi_print_contents[read_bytes] = '\0';
            fclose(readback);
        } else {
            dpi_print_ok = false;
        }
    }
    unlink(dpi_print_path);
    dpi_print_ok = dpi_print_ok &&
                   strstr(dpi_print_contents, "Supported DPI: 800..3200 (step 800)") != NULL &&
                   strstr(dpi_print_contents, "Supported DPI: 800, 1600, 2000") != NULL &&
                   strstr(dpi_print_contents, "Supported DPI: 800\n") != NULL;
    if (!dpi_print_ok) {
        fprintf(stderr, "print_supported_dpi self-test failed\n");
        return 1;
    }

    discover_devices_for_options_impl = discover_devices_for_options_test_double;
    DiscoverDevicesTestContext empty_discovery_context = {.devices = NULL, .count = 0, .result = 1};
    g_discover_devices_test_context = &empty_discovery_context;
    Options command_options;
    memset(&command_options, 0, sizeof(command_options));
    command_options.device_index = -1;
    bool no_device_ok = run_info(&command_options) == 1 && run_profiles(&command_options) == 1 &&
                        run_dpi(&command_options) == 1 && run_current_dpi(&command_options) == 1;
    if (!no_device_ok) {
        fprintf(stderr, "command no-device self-test failed\n");
        return 1;
    }

    HidInterface no_capability_interface = {0};
    no_capability_interface.vendor_id = LOGITECH_VID;
    no_capability_interface.product_id = 0xC099;
    Device no_capability_devices[1];
    memset(no_capability_devices, 0, sizeof(no_capability_devices));
    no_capability_devices[0].iface = &no_capability_interface;
    no_capability_devices[0].device_number = 0xFF;
    no_capability_devices[0].request_device_number = 0xFF;
    no_capability_devices[0].protocol = 4.2;
    DiscoverDevicesTestContext no_capability_context = {
        .devices = no_capability_devices, .count = 1, .result = 1};
    g_discover_devices_test_context = &no_capability_context;
    bool no_capability_ok = run_info(&command_options) == 0 && run_profiles(&command_options) == 1;

    channel_request_impl = channel_request_test_double;
    ChannelRequestTestContext no_feature_channel_context = {
        .replies = NULL, .reply_count = 0, .calls = 0};
    g_channel_request_test_context = &no_feature_channel_context;
    no_capability_ok = no_capability_ok && run_dpi(&command_options) == 1 &&
                       run_current_dpi(&command_options) == 1;
    if (!no_capability_ok) {
        fprintf(stderr, "command no-capability self-test failed\n");
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

    uint8_t hex_byte_value = 0;
    uint16_t hex_word_value = 0;
    bool hex_parser_ok =
        parse_hex_byte("2B", &hex_byte_value) && hex_byte_value == 0x2B &&
        !parse_hex_byte("2G", &hex_byte_value) && !parse_hex_byte("", &hex_byte_value) &&
        !parse_hex_byte(NULL, &hex_byte_value) && !parse_hex_byte("100", &hex_byte_value) &&
        parse_hex_word("00E9", &hex_word_value) && hex_word_value == 0x00E9 &&
        !parse_hex_word("ZZZZ", &hex_word_value) && !parse_hex_word("", &hex_word_value) &&
        !parse_hex_word(NULL, &hex_word_value) && !parse_hex_word("10000", &hex_word_value);
    if (!hex_parser_ok) {
        fprintf(stderr, "parse_hex_byte/parse_hex_word self-test failed\n");
        return 1;
    }

    uint8_t target_spec[4] = {0};
    bool target_parser_ok =
        !parse_target(NULL, target_spec) &&
        !parse_target("this-is-not-a-real-target-name-that-is-way-too-long-for-the-buffer-size-"
                      "used-internally-by-parse-target-and-should-be-rejected-outright",
                      target_spec) &&
        parse_target("left", target_spec) && target_spec[2] == 0x00 && target_spec[3] == 0x01 &&
        parse_target("right-click", target_spec) && target_spec[3] == 0x02 &&
        parse_target("middle", target_spec) && target_spec[3] == 0x04 &&
        parse_target("back", target_spec) && target_spec[3] == 0x08 &&
        parse_target("forward", target_spec) && target_spec[3] == 0x10 &&
        parse_target("button6", target_spec) && target_spec[3] == 0x20 &&
        parse_target("button7", target_spec) && target_spec[3] == 0x40 &&
        parse_target("button8", target_spec) && target_spec[3] == 0x80 &&
        parse_target("Alt+Tab", target_spec) && target_spec[1] == 0x02 && target_spec[3] == 0x2B &&
        parse_target("dpi-up", target_spec) && target_spec[1] == 0x03 &&
        parse_target("previous-dpi", target_spec) && target_spec[1] == 0x04 &&
        parse_target("dpi-cycle", target_spec) && target_spec[1] == 0x05 &&
        parse_target("dpi-default", target_spec) && target_spec[1] == 0x06 &&
        parse_target("dpi-shift", target_spec) && target_spec[1] == 0x07 &&
        parse_target("next-profile", target_spec) && target_spec[1] == 0x08 &&
        parse_target("previous-profile", target_spec) && target_spec[1] == 0x09 &&
        parse_target("cycle-profile", target_spec) && target_spec[1] == 0x0A &&
        parse_target("g-shift", target_spec) && target_spec[1] == 0x0B &&
        parse_target("nav-back", target_spec) && target_spec[3] == 0x2F &&
        parse_target("cmd-]", target_spec) && target_spec[3] == 0x30 &&
        parse_target("none", target_spec) && target_spec[0] == 0xFF && target_spec[3] == 0xFF &&
        parse_target("key:04:2B", target_spec) && target_spec[2] == 0x04 &&
        target_spec[3] == 0x2B && !parse_target("key:04", target_spec) &&
        !parse_target("key:ZZ:2B", target_spec) && !parse_target("key::2B", target_spec) &&
        !parse_target("key:04:", target_spec) && parse_target("consumer:00E9", target_spec) &&
        target_spec[1] == 0x03 && target_spec[2] == 0x00 && target_spec[3] == 0xE9 &&
        !parse_target("consumer:ZZZZ", target_spec) && parse_target("80010004", target_spec) &&
        target_spec[0] == 0x80 && target_spec[3] == 0x04 &&
        !parse_target("8001000G", target_spec) && !parse_target("not-a-target", target_spec);
    if (!target_parser_ok) {
        fprintf(stderr, "parse_target self-test failed\n");
        return 1;
    }

    Options dump_options;
    memset(&dump_options, 0, sizeof(dump_options));
    dump_options.device_index = -1;
    bool backup_bind_validation_ok = run_dump(&dump_options) == 1;

    dump_options.path = "/tmp/lomps-selftest-dump-target.bin";
    discover_devices_for_options_impl = discover_devices_for_options_test_double;
    DiscoverDevicesTestContext backup_bind_empty_context = {
        .devices = NULL, .count = 0, .result = 1};
    g_discover_devices_test_context = &backup_bind_empty_context;
    backup_bind_validation_ok = backup_bind_validation_ok && run_dump(&dump_options) == 1;

    Options bind_options;
    memset(&bind_options, 0, sizeof(bind_options));
    bind_options.device_index = -1;
    backup_bind_validation_ok = backup_bind_validation_ok && run_bind(&bind_options) == 1;

    bind_options.target = "not-a-real-target";
    backup_bind_validation_ok = backup_bind_validation_ok && run_bind(&bind_options) == 1;

    bind_options.target = "alt-tab";
    backup_bind_validation_ok = backup_bind_validation_ok && run_bind(&bind_options) == 1;

    Options restore_options;
    memset(&restore_options, 0, sizeof(restore_options));
    restore_options.device_index = -1;
    backup_bind_validation_ok = backup_bind_validation_ok && run_restore(&restore_options) == 1;

    restore_options.path = "/tmp/lomps-selftest-nonexistent-package.logiob";
    unlink(restore_options.path);
    backup_bind_validation_ok = backup_bind_validation_ok && run_restore(&restore_options) == 1;
    if (!backup_bind_validation_ok) {
        fprintf(stderr, "run_dump/run_bind/run_restore validation self-test failed\n");
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
    if (!g600_apply_unsupported_ok) {
        fprintf(stderr, "run_g600_apply unsupported-change self-test failed\n");
        return 1;
    }

    Options g600_info_options;
    memset(&g600_info_options, 0, sizeof(g600_info_options));
    g600_info_options.profile = 99;
    bool g600_range_ok = run_g600_info(&g600_info_options, &g600_apply_device) == 1;
    if (!g600_range_ok) {
        fprintf(stderr, "run_g600_info out-of-range self-test failed\n");
        return 1;
    }

    bool mouse_button_name_ok = strcmp(mouse_button_name(0), "Left") == 0 &&
                                strcmp(mouse_button_name(3), "Back / rear thumb") == 0 &&
                                strcmp(mouse_button_name(7), "Button 8") == 0 &&
                                strcmp(mouse_button_name(9), "unknown") == 0;
    int decimal_value = 0;
    int slot_value = 0;
    bool decimal_slot_ok =
        parse_decimal("42", &decimal_value) && decimal_value == 42 &&
        !parse_decimal(NULL, &decimal_value) && !parse_decimal("", &decimal_value) &&
        !parse_decimal("-1", &decimal_value) && !parse_decimal("100001", &decimal_value) &&
        !parse_decimal("12x", &decimal_value) && parse_slot("ff", &slot_value) &&
        slot_value == 0xFF && parse_slot("0xFF", &slot_value) && slot_value == 0xFF &&
        parse_slot("3", &slot_value) && slot_value == 3 && !parse_slot("0", &slot_value) &&
        !parse_slot("7", &slot_value) && !parse_slot("bad", &slot_value);
    if (!mouse_button_name_ok || !decimal_slot_ok) {
        fprintf(stderr, "mouse_button_name/parse_decimal/parse_slot self-test failed\n");
        return 1;
    }

    char usage_path[] = "/tmp/lomps-selftest-usage-XXXXXX";
    int usage_fd = mkstemp(usage_path);
    if (usage_fd < 0) {
        fprintf(stderr, "print_usage self-test failed to create temp file\n");
        return 1;
    }
    close(usage_fd);
    int usage_saved_stdout = dup(fileno(stdout));
    bool usage_ok = usage_saved_stdout >= 0 && freopen(usage_path, "w", stdout) != NULL;
    if (usage_ok) {
        print_usage("lope");
        fflush(stdout);
    }
    if (usage_saved_stdout >= 0) {
        dup2(usage_saved_stdout, fileno(stdout));
        close(usage_saved_stdout);
        clearerr(stdout);
    }
    char usage_contents[4096] = {0};
    if (usage_ok) {
        FILE *readback = fopen(usage_path, "r");
        if (readback != NULL) {
            size_t read_bytes = fread(usage_contents, 1, sizeof(usage_contents) - 1, readback);
            usage_contents[read_bytes] = '\0';
            fclose(readback);
        } else {
            usage_ok = false;
        }
    }
    unlink(usage_path);
    usage_ok = usage_ok && strstr(usage_contents, "lope") != NULL;
    if (!usage_ok) {
        fprintf(stderr, "print_usage self-test failed\n");
        return 1;
    }

    Options parsed;
    char *default_command_argv[] = {"lope"};
    bool parse_options_ok =
        parse_options(1, default_command_argv, &parsed) && strcmp(parsed.command, "list") == 0;

    char *flags_argv[] = {"lope",           "list",          "--yes",      "--headers-only",
                          "--summary-only", "--sensor-only", "--with-dpi", "--with-report-rate"};
    parse_options_ok = parse_options_ok && parse_options(8, flags_argv, &parsed) && parsed.yes &&
                       parsed.headers_only && parsed.summary_only && parsed.sensor_only &&
                       parsed.include_dpi && parsed.include_report_rate;

    char *missing_value_argv[] = {"lope", "list", "--device"};
    parse_options_ok = parse_options_ok && !parse_options(3, missing_value_argv, &parsed);

    char *invalid_device_argv[] = {"lope", "list", "--device", "abc"};
    parse_options_ok = parse_options_ok && !parse_options(4, invalid_device_argv, &parsed);

    char *device_key_argv[] = {"lope", "list", "--device-key", "1-2-3"};
    parse_options_ok = parse_options_ok && parse_options(4, device_key_argv, &parsed) &&
                       strcmp(parsed.device_key, "1-2-3") == 0;

    char *invalid_slot_argv[] = {"lope", "list", "--slot", "99"};
    parse_options_ok = parse_options_ok && !parse_options(4, invalid_slot_argv, &parsed);

    char *invalid_profile_argv[] = {"lope", "info", "--profile", "0"};
    parse_options_ok = parse_options_ok && !parse_options(4, invalid_profile_argv, &parsed);

    char *invalid_button_argv[] = {"lope", "bind", "--button", "0", "alt-tab"};
    parse_options_ok = parse_options_ok && !parse_options(5, invalid_button_argv, &parsed);

    char *invalid_default_argv[] = {"lope", "set-dpi", "--default", "6", "800"};
    parse_options_ok = parse_options_ok && !parse_options(5, invalid_default_argv, &parsed);

    char *invalid_shift_argv[] = {"lope", "set-dpi", "--shift", "0", "800"};
    parse_options_ok = parse_options_ok && !parse_options(5, invalid_shift_argv, &parsed);

    char *dpi_report_rate_argv[] = {"lope",
                                    "apply",
                                    "--dpi",
                                    "800,1600",
                                    "--report-rate",
                                    "1000",
                                    "--backup-directory",
                                    "/tmp",
                                    "--operation-id",
                                    "op-1"};
    parse_options_ok =
        parse_options_ok && parse_options(10, dpi_report_rate_argv, &parsed) &&
        strcmp(parsed.dpi_values, "800,1600") == 0 && strcmp(parsed.report_rate, "1000") == 0 &&
        strcmp(parsed.backup_directory, "/tmp") == 0 && strcmp(parsed.operation_id, "op-1") == 0;

    char *too_many_button_changes_argv[(MAX_BATCH_BUTTON_CHANGES + 1) * 2 + 2];
    too_many_button_changes_argv[0] = "lope";
    too_many_button_changes_argv[1] = "apply";
    for (size_t i = 0; i < MAX_BATCH_BUTTON_CHANGES + 1; i++) {
        too_many_button_changes_argv[2 + i * 2] = "--button-change";
        too_many_button_changes_argv[3 + i * 2] = "normal:1:80010001";
    }
    parse_options_ok =
        parse_options_ok && !parse_options((int)((MAX_BATCH_BUTTON_CHANGES + 1) * 2 + 2),
                                           too_many_button_changes_argv, &parsed);

    char *too_many_rgb_changes_argv[(MAX_BATCH_RGB_CHANGES + 1) * 2 + 2];
    too_many_rgb_changes_argv[0] = "lope";
    too_many_rgb_changes_argv[1] = "apply";
    for (size_t i = 0; i < MAX_BATCH_RGB_CHANGES + 1; i++) {
        too_many_rgb_changes_argv[2 + i * 2] = "--rgb-change";
        too_many_rgb_changes_argv[3 + i * 2] = "1:AABBCC";
    }
    parse_options_ok =
        parse_options_ok && !parse_options((int)((MAX_BATCH_RGB_CHANGES + 1) * 2 + 2),
                                           too_many_rgb_changes_argv, &parsed);

    char *unknown_option_argv[] = {"lope", "list", "--bogus"};
    parse_options_ok = parse_options_ok && !parse_options(3, unknown_option_argv, &parsed);

    char *too_many_positionals_argv[] = {"lope", "unknown", "1", "2", "3", "4",
                                         "5",    "6",       "7", "8", "9"};
    parse_options_ok = parse_options_ok && !parse_options(11, too_many_positionals_argv, &parsed);

    char *device_and_key_argv[] = {"lope", "list", "--device", "1", "--device-key", "1-2-3"};
    parse_options_ok = parse_options_ok && !parse_options(6, device_and_key_argv, &parsed);

    char *device_and_slot_argv[] = {"lope", "list", "--device", "1", "--slot", "2"};
    parse_options_ok = parse_options_ok && !parse_options(6, device_and_slot_argv, &parsed);

    char *dump_missing_path_argv[] = {"lope", "dump"};
    parse_options_ok = parse_options_ok && !parse_options(2, dump_missing_path_argv, &parsed);

    char *dump_argv[] = {"lope", "dump", "/tmp/out.bin"};
    parse_options_ok = parse_options_ok && parse_options(3, dump_argv, &parsed) &&
                       strcmp(parsed.path, "/tmp/out.bin") == 0;

    char *bind_rear_thumb_argv[] = {"lope", "bind", "rear-thumb", "alt-tab"};
    parse_options_ok = parse_options_ok && parse_options(4, bind_rear_thumb_argv, &parsed) &&
                       strcmp(parsed.target, "alt-tab") == 0;

    char *bind_direct_argv[] = {"lope", "bind", "alt-tab"};
    parse_options_ok = parse_options_ok && parse_options(3, bind_direct_argv, &parsed) &&
                       strcmp(parsed.target, "alt-tab") == 0;

    char *bind_bad_argv[] = {"lope", "bind", "a", "b", "c"};
    parse_options_ok = parse_options_ok && !parse_options(5, bind_bad_argv, &parsed);

    char *set_dpi_bad_argv[] = {"lope", "set-dpi"};
    parse_options_ok = parse_options_ok && !parse_options(2, set_dpi_bad_argv, &parsed);

    char *set_profile_state_bad_argv[] = {"lope", "set-profile-state", "1"};
    parse_options_ok = parse_options_ok && !parse_options(3, set_profile_state_bad_argv, &parsed);

    char *set_report_rate_bad_argv[] = {"lope", "set-report-rate"};
    parse_options_ok = parse_options_ok && !parse_options(2, set_report_rate_bad_argv, &parsed);

    char *apply_positional_argv[] = {"lope", "apply", "extra"};
    parse_options_ok = parse_options_ok && !parse_options(3, apply_positional_argv, &parsed);

    char *unknown_command_positional_argv[] = {"lope", "totally-unknown-command", "extra"};
    parse_options_ok =
        parse_options_ok && !parse_options(3, unknown_command_positional_argv, &parsed);

    if (!parse_options_ok) {
        fprintf(stderr, "parse_options self-test failed\n");
        return 1;
    }

    char spec_description[160];
    uint8_t disabled_spec[4] = {0xFF, 0xFF, 0xFF, 0xFF};
    describe_spec(disabled_spec, spec_description, sizeof(spec_description));
    bool describe_spec_ok = strcmp(spec_description, "disabled") == 0;

    uint8_t no_action_spec[4] = {0x80, 0x00, 0x00, 0x00};
    describe_spec(no_action_spec, spec_description, sizeof(spec_description));
    describe_spec_ok = describe_spec_ok && strcmp(spec_description, "no action") == 0;

    uint8_t mouse_mask_spec[4] = {0x80, 0x01, 0x00, 0x08};
    describe_spec(mouse_mask_spec, spec_description, sizeof(spec_description));
    describe_spec_ok =
        describe_spec_ok && strstr(spec_description, "Back / rear thumb (mask 0x0008)") != NULL;

    uint8_t unknown_mask_spec[4] = {0x80, 0x01, 0x01, 0x00};
    describe_spec(unknown_mask_spec, spec_description, sizeof(spec_description));
    describe_spec_ok =
        describe_spec_ok && strstr(spec_description, "mouse mask (mask 0x0100)") != NULL;

    uint8_t key_alt_spec[4] = {0x80, 0x02, 0x04, 0x04};
    describe_spec(key_alt_spec, spec_description, sizeof(spec_description));
    describe_spec_ok = describe_spec_ok && strstr(spec_description, "Left Alt + A") != NULL;

    uint8_t key_ctrl_spec[4] = {0x80, 0x02, 0x01, 0x04};
    describe_spec(key_ctrl_spec, spec_description, sizeof(spec_description));
    describe_spec_ok = describe_spec_ok && strstr(spec_description, "Left Ctrl + A") != NULL;

    uint8_t key_shift_spec[4] = {0x80, 0x02, 0x02, 0x04};
    describe_spec(key_shift_spec, spec_description, sizeof(spec_description));
    describe_spec_ok = describe_spec_ok && strstr(spec_description, "Left Shift + A") != NULL;

    uint8_t key_gui_spec[4] = {0x80, 0x02, 0x08, 0x04};
    describe_spec(key_gui_spec, spec_description, sizeof(spec_description));
    describe_spec_ok = describe_spec_ok && strstr(spec_description, "Left Command/GUI + A") != NULL;

    uint8_t key_bitmap_spec[4] = {0x80, 0x02, 0x10, 0x04};
    describe_spec(key_bitmap_spec, spec_description, sizeof(spec_description));
    describe_spec_ok = describe_spec_ok && strstr(spec_description, "modifier bitmap + A") != NULL;

    uint8_t key_none_spec[4] = {0x80, 0x02, 0x00, 0x04};
    describe_spec(key_none_spec, spec_description, sizeof(spec_description));
    describe_spec_ok = describe_spec_ok && strstr(spec_description, "no modifier + A") != NULL;

    uint8_t consumer_spec[4] = {0x80, 0x03, 0x00, 0xE9};
    describe_spec(consumer_spec, spec_description, sizeof(spec_description));
    describe_spec_ok =
        describe_spec_ok && strstr(spec_description, "consumer usage 0x00E9") != NULL;

    uint8_t send_unknown_spec[4] = {0x80, 0x04, 0x00, 0x00};
    describe_spec(send_unknown_spec, spec_description, sizeof(spec_description));
    describe_spec_ok = describe_spec_ok && strstr(spec_description, "SEND type 0x04") != NULL;

    uint8_t function_spec[4] = {0x90, 0x08, 0x00, 0x00};
    describe_spec(function_spec, spec_description, sizeof(spec_description));
    describe_spec_ok = describe_spec_ok && strcmp(spec_description, "next profile") == 0 &&
                       strcmp(function_name(0x00), "no action") == 0 &&
                       strcmp(function_name(0x11), "scroll up") == 0 &&
                       strcmp(function_name(0x12), "unknown function") == 0;

    uint8_t macro_spec[4] = {0x10, 0x00, 0x00, 0x00};
    describe_spec(macro_spec, spec_description, sizeof(spec_description));
    describe_spec_ok =
        describe_spec_ok && strstr(spec_description, "macro record (behavior 0x1)") != NULL;

    uint8_t unrecognized_spec[4] = {0x30, 0x00, 0x00, 0x00};
    describe_spec(unrecognized_spec, spec_description, sizeof(spec_description));
    describe_spec_ok = describe_spec_ok && strcmp(spec_description, "unrecognized raw spec") == 0;

    describe_spec_ok = describe_spec_ok && strcmp(key_name(0x04), "A") == 0 &&
                       strcmp(key_name(0xFF), "unknown key") == 0 &&
                       spec_is_back(mouse_mask_spec) && !spec_is_back(no_action_spec);
    if (!describe_spec_ok) {
        fprintf(stderr, "describe_spec/function_name/key_name self-test failed\n");
        return 1;
    }

    char render_path[] = "/tmp/lomps-selftest-render-XXXXXX";
    int render_fd = mkstemp(render_path);
    if (render_fd < 0) {
        fprintf(stderr,
                "print_feature_list/print_device_line self-test failed to create temp file\n");
        return 1;
    }
    close(render_fd);
    HidInterface render_interface = {0};
    render_interface.product_id = 0xC099;
    Device render_device = {0};
    render_device.iface = &render_interface;
    render_device.protocol = 4.2;
    render_device.feature_count = 2;
    render_device.features[0] = (Feature){.id = FEATURE_ROOT, .index = 0, .version = 1};
    render_device.features[1] = (Feature){.id = FEATURE_ONBOARD_PROFILES, .index = 5, .version = 2};
    int render_saved_stdout = dup(fileno(stdout));
    bool render_ok = render_saved_stdout >= 0 && freopen(render_path, "w", stdout) != NULL;
    if (render_ok) {
        print_feature_list(&render_device);
        print_device_line(&render_device, 0);
        print_hex4(mouse_mask_spec);
        fflush(stdout);
    }
    if (render_saved_stdout >= 0) {
        dup2(render_saved_stdout, fileno(stdout));
        close(render_saved_stdout);
        clearerr(stdout);
    }
    char render_contents[1024] = {0};
    if (render_ok) {
        FILE *readback = fopen(render_path, "r");
        if (readback != NULL) {
            size_t read_bytes = fread(render_contents, 1, sizeof(render_contents) - 1, readback);
            render_contents[read_bytes] = '\0';
            fclose(readback);
        } else {
            render_ok = false;
        }
    }
    unlink(render_path);
    render_ok = render_ok && strstr(render_contents, "features: 2") != NULL &&
                strstr(render_contents, "index   0: 0x0000 v1") != NULL &&
                strstr(render_contents, "index   5: 0x8100 v2") != NULL &&
                strstr(render_contents, "HID++ 4.2, product 0xC099") != NULL &&
                strstr(render_contents, "80 01 00 08") != NULL;
    if (!render_ok) {
        fprintf(stderr, "print_feature_list/print_device_line self-test failed\n");
        return 1;
    }

    uint8_t mock_sector[255] = {0};
    uint8_t mock_button_specs[5][4] = {
        {0x80, 0x01, 0x00, 0x01}, {0x80, 0x01, 0x00, 0x02}, {0x80, 0x01, 0x00, 0x04},
        {0x80, 0x01, 0x00, 0x08}, {0x80, 0x01, 0x00, 0x10},
    };
    uint8_t mock_gshift_specs[5][4] = {
        {0x80, 0x01, 0x00, 0x10}, {0x80, 0x01, 0x00, 0x20}, {0x80, 0x01, 0x00, 0x40},
        {0x80, 0x01, 0x00, 0x80}, {0x80, 0x01, 0x01, 0x00},
    };
    for (size_t i = 0; i < 5; i++) {
        memcpy(mock_sector + 32 + i * 4, mock_button_specs[i], 4);
        memcpy(mock_sector + 96 + i * 4, mock_gshift_specs[i], 4);
    }
    uint16_t mock_dpi[5] = {800, 1200, 1600, 2400, 3200};
    for (size_t i = 0; i < 5; i++) {
        write_le16(mock_sector + 3 + i * 2, mock_dpi[i]);
    }
    for (size_t i = 0; i < RGB_PROFILE_RECORD_COUNT; i++) {
        memset(mock_sector + RGB_PROFILE_BASE_OFFSET + i * RGB_PROFILE_RECORD_BYTES, 0xFF,
               RGB_PROFILE_RECORD_BYTES);
    }
    mock_sector[RGB_PROFILE_BASE_OFFSET] = 0x01;
    mock_sector[RGB_PROFILE_BASE_OFFSET + 1] = 0x10;
    mock_sector[RGB_PROFILE_BASE_OFFSET + 2] = 0x20;
    mock_sector[RGB_PROFILE_BASE_OFFSET + 3] = 0x30;
    mock_sector[RGB_PROFILE_BASE_OFFSET + RGB_PROFILE_RECORD_BYTES] = 0x01;
    mock_sector[RGB_PROFILE_BASE_OFFSET + RGB_PROFILE_RECORD_BYTES + 1] = 0x40;
    mock_sector[RGB_PROFILE_BASE_OFFSET + RGB_PROFILE_RECORD_BYTES + 2] = 0x50;
    mock_sector[RGB_PROFILE_BASE_OFFSET + RGB_PROFILE_RECORD_BYTES + 3] = 0x60;
    mock_sector[1] = 2;
    mock_sector[2] = 0;
    sector_put_crc(mock_sector, sizeof(mock_sector));

    uint8_t mock_control[132] = {0};
    mock_control[0] = 0x01;
    mock_control[1] = 0x23;
    mock_control[2] = 0x01;
    mock_control[3] = 0x00;

    Reply mock_get_info_reply = {
        .status = REPLY_OK,
        .length = 10,
        .bytes = {0x00, 0x05, 0x00, 0x01, 0x00, 0x05, 0x01, 0x00, 0xFF, 0x02}};

    Reply load_selected_replies[1 + 16 + 32];
    size_t load_selected_reply_count = 0;
    load_selected_replies[load_selected_reply_count++] = mock_get_info_reply;
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

    // discover_devices() is exercised directly (bypassing hid_context_create's
    // real IOKit enumeration) by hand-building a HidContext whose interfaces
    // are already marked channel_open, which makes open_vendor_channels()
    // skip them without touching real hardware; channel_request_impl still
    // supplies the HID++ ping/pairing replies.
    HidInterface discover_direct_interface = {0};
    discover_direct_interface.is_vendor = true;
    discover_direct_interface.channel_open = true;
    discover_direct_interface.product_id = 0xC099;

    HidInterface discover_g600_interface = {0};
    discover_g600_interface.is_vendor = true;
    discover_g600_interface.channel_open = true;
    discover_g600_interface.product_id = G600_PRODUCT_ID;

    HidContext discover_context;
    memset(&discover_context, 0, sizeof(discover_context));
    HidInterface discover_items[2] = {discover_direct_interface, discover_g600_interface};
    discover_context.items = discover_items;
    discover_context.count = 2;

    Reply discover_ping_ok_reply = {.status = REPLY_OK, .length = 3, .bytes = {0x02, 0x00, 0x5A}};
    ChannelRequestTestContext discover_ping_context = {
        .replies = &discover_ping_ok_reply, .reply_count = 1, .calls = 0};
    channel_request_impl = channel_request_test_double;
    g_channel_request_test_context = &discover_ping_context;

    Device discover_devices_out[MAX_DEVICES];
    size_t discover_count = 0;
    bool discover_ok =
        discover_devices(&discover_context, -1, discover_devices_out, &discover_count, false) &&
        discover_count == 2 && discover_devices_out[0].protocol == 2.0 &&
        discover_devices_out[0].device_number == 0xFF &&
        discover_devices_out[1].iface == &discover_items[1] &&
        discover_devices_out[1].device_number == 0xFF;

    Reply discover_ping_fail_reply = {.status = REPLY_TIMEOUT};
    ChannelRequestTestContext discover_ping_fail_context = {
        .replies = &discover_ping_fail_reply, .reply_count = 1, .calls = 0};
    g_channel_request_test_context = &discover_ping_fail_context;
    HidInterface discover_unresponsive_interface = {0};
    discover_unresponsive_interface.is_vendor = true;
    discover_unresponsive_interface.channel_open = true;
    discover_unresponsive_interface.product_id = 0xC099;
    HidContext discover_unresponsive_context;
    memset(&discover_unresponsive_context, 0, sizeof(discover_unresponsive_context));
    discover_unresponsive_context.items = &discover_unresponsive_interface;
    discover_unresponsive_context.count = 1;
    size_t discover_unresponsive_count = 0;
    Device discover_unresponsive_devices[MAX_DEVICES];
    discover_ok =
        discover_ok &&
        discover_devices(&discover_unresponsive_context, -1, discover_unresponsive_devices,
                         &discover_unresponsive_count, false) &&
        discover_unresponsive_count == 0;
    if (!discover_ok) {
        fprintf(stderr, "discover_devices self-test failed\n");
        return 1;
    }

    Reply discover_key_ping_reply = {.status = REPLY_OK, .length = 3, .bytes = {0x02, 0x00, 0x5A}};
    ChannelRequestTestContext discover_key_context = {
        .replies = &discover_key_ping_reply, .reply_count = 1, .calls = 0};
    g_channel_request_test_context = &discover_key_context;
    HidInterface discover_key_interface = {0};
    discover_key_interface.is_vendor = true;
    discover_key_interface.channel_open = true;
    discover_key_interface.product_id = 0xC099;
    discover_key_interface.location_id = 0x1234;
    discover_key_interface.registry_id = 0x5678;
    HidContext discover_key_hid_context;
    memset(&discover_key_hid_context, 0, sizeof(discover_key_hid_context));
    discover_key_hid_context.items = &discover_key_interface;
    discover_key_hid_context.count = 1;
    Device discover_key_devices[MAX_DEVICES];
    size_t discover_key_count = 0;
    bool discover_by_key_ok = discover_device_by_key(&discover_key_hid_context, "1234-5678-ff",
                                                     discover_key_devices, &discover_key_count) &&
                              discover_key_count == 1 && discover_key_devices[0].protocol == 2.0;

    size_t discover_bad_key_count = 0;
    discover_by_key_ok = discover_by_key_ok &&
                         discover_device_by_key(&discover_key_hid_context, "not-a-key",
                                                discover_key_devices, &discover_bad_key_count) == 0;
    if (!discover_by_key_ok) {
        fprintf(stderr, "discover_device_by_key self-test failed\n");
        return 1;
    }

    Profile summary_profile;
    memset(&summary_profile, 0, sizeof(summary_profile));
    summary_profile.info.profile_format = 5;
    summary_profile.info.button_count = 5;
    summary_profile.info.shift_flags = 0x02;
    summary_profile.data = mock_sector;
    summary_profile.data_length = sizeof(mock_sector);
    summary_profile.crc_ok = sector_crc_ok(mock_sector, sizeof(mock_sector));
    summary_profile.crc_checked = true;
    summary_profile.headers[0].sector = 0x0123;
    summary_profile.headers[0].enabled = 1;
    summary_profile.selected_header = 0;
    detect_button_layout(&summary_profile);
    detect_gshift_button_layout(&summary_profile, NULL);
    detect_dpi_layout(&summary_profile, NULL);
    detect_rgb_layout(&summary_profile);

    char summary_path[] = "/tmp/lomps-selftest-summary-XXXXXX";
    int summary_fd = mkstemp(summary_path);
    if (summary_fd < 0) {
        fprintf(stderr, "print_profile_summary self-test failed to create temp file\n");
        return 1;
    }
    close(summary_fd);
    int summary_saved_stdout = dup(fileno(stdout));
    bool summary_ok = summary_saved_stdout >= 0 && freopen(summary_path, "w", stdout) != NULL;
    if (summary_ok) {
        print_profile_summary(&summary_profile, true);
        fflush(stdout);
    }
    if (summary_saved_stdout >= 0) {
        dup2(summary_saved_stdout, fileno(stdout));
        close(summary_saved_stdout);
        clearerr(stdout);
    }
    char summary_contents[4096] = {0};
    if (summary_ok) {
        FILE *readback = fopen(summary_path, "r");
        if (readback != NULL) {
            size_t read_bytes = fread(summary_contents, 1, sizeof(summary_contents) - 1, readback);
            summary_contents[read_bytes] = '\0';
            fclose(readback);
        } else {
            summary_ok = false;
        }
    }
    unlink(summary_path);
    summary_ok = summary_ok &&
                 strstr(summary_contents, "Profile 1 (sector 0x0123, enabled=yes)") != NULL &&
                 strstr(summary_contents, "CRC: OK") != NULL &&
                 strstr(summary_contents, "DPI stages: 800, 1200, 1600, 2400, 3200") != NULL &&
                 strstr(summary_contents, "RGB zones: 2") != NULL &&
                 strstr(summary_contents, "RGB zone 1: 102030 (mode 0x01)") != NULL &&
                 strstr(summary_contents, "RGB zone 2: 405060 (mode 0x01)") != NULL &&
                 strstr(summary_contents, "button array: offset 32") != NULL &&
                 strstr(summary_contents, "G-Shift layout: supported") != NULL &&
                 strstr(summary_contents, "button 1: Left click") != NULL &&
                 strstr(summary_contents, "G-Shift button 1:") != NULL &&
                 strstr(summary_contents, "rear thumb mapping:") != NULL;
    if (!summary_ok) {
        fprintf(stderr, "print_profile_summary self-test failed\n");
        return 1;
    }

    Profile summary_no_crc_profile = summary_profile;
    summary_no_crc_profile.crc_checked = false;
    char summary_no_crc_path[] = "/tmp/lomps-selftest-summary-nocrc-XXXXXX";
    int summary_no_crc_fd = mkstemp(summary_no_crc_path);
    if (summary_no_crc_fd < 0) {
        fprintf(stderr, "print_profile_summary NOT_READ self-test failed to create temp file\n");
        return 1;
    }
    close(summary_no_crc_fd);
    int summary_no_crc_saved_stdout = dup(fileno(stdout));
    bool summary_no_crc_ok =
        summary_no_crc_saved_stdout >= 0 && freopen(summary_no_crc_path, "w", stdout) != NULL;
    if (summary_no_crc_ok) {
        print_profile_summary(&summary_no_crc_profile, false);
        fflush(stdout);
    }
    if (summary_no_crc_saved_stdout >= 0) {
        dup2(summary_no_crc_saved_stdout, fileno(stdout));
        close(summary_no_crc_saved_stdout);
        clearerr(stdout);
    }
    char summary_no_crc_contents[1024] = {0};
    if (summary_no_crc_ok) {
        FILE *readback = fopen(summary_no_crc_path, "r");
        if (readback != NULL) {
            size_t read_bytes =
                fread(summary_no_crc_contents, 1, sizeof(summary_no_crc_contents) - 1, readback);
            summary_no_crc_contents[read_bytes] = '\0';
            fclose(readback);
        } else {
            summary_no_crc_ok = false;
        }
    }
    unlink(summary_no_crc_path);
    summary_no_crc_ok =
        summary_no_crc_ok && strstr(summary_no_crc_contents, "CRC: NOT_READ") != NULL;
    if (!summary_no_crc_ok) {
        fprintf(stderr, "print_profile_summary NOT_READ self-test failed\n");
        return 1;
    }

    // run_set_dpi end-to-end: the requested DPI list, and the resolved
    // default/shift indexes, exactly match what mock_sector already stores,
    // so the sector write_sector() performs is byte-identical to mock_sector
    // and the same data_chunks reply sequence can double as its readback.
    Reply set_dpi_replies[64];
    size_t set_dpi_reply_count = 0;
    set_dpi_replies[set_dpi_reply_count++] = (Reply){.status = REPLY_OK, .length = 1, .bytes = {1}};
    set_dpi_replies[set_dpi_reply_count++] =
        (Reply){.status = REPLY_OK,
                .length = 11,
                .bytes = {0x00, 0x03, 0x20, 0x04, 0xB0, 0x06, 0x40, 0x09, 0x60, 0x0C, 0x80}};
    set_dpi_replies[set_dpi_reply_count++] = mock_get_info_reply;
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

    // run_bind end-to-end: rebind button 4 (currently the mock Back/rear-thumb
    // record) to "middle", so the written sector differs from mock_sector at
    // exactly that 4-byte record; build a matching readback buffer for the
    // post-write verification.
    uint8_t bind_new_sector[255];
    memcpy(bind_new_sector, mock_sector, sizeof(mock_sector));
    bind_new_sector[32 + 3 * 4 + 0] = 0x80;
    bind_new_sector[32 + 3 * 4 + 1] = 0x01;
    bind_new_sector[32 + 3 * 4 + 2] = 0x00;
    bind_new_sector[32 + 3 * 4 + 3] = 0x04;
    sector_put_crc(bind_new_sector, sizeof(bind_new_sector));
    Reply bind_data_chunks[32];
    size_t bind_data_chunk_count =
        build_sector_read_replies(bind_new_sector, sizeof(bind_new_sector), bind_data_chunks, 32);
    if (bind_data_chunk_count == 0) {
        fprintf(stderr, "run_bind self-test failed to build readback replies\n");
        return 1;
    }

    Reply bind_replies[64];
    size_t bind_reply_count = 0;
    bind_replies[bind_reply_count++] = mock_get_info_reply;
    for (size_t i = 0; i < control_chunk_count; i++) {
        bind_replies[bind_reply_count++] = control_chunks[i];
    }
    for (size_t i = 0; i < data_chunk_count; i++) {
        bind_replies[bind_reply_count++] = data_chunks[i];
    }
    bind_replies[bind_reply_count++] =
        (Reply){.status = REPLY_OK, .length = 1, .bytes = {ONBOARD_MODE_ONBOARD}};
    Reply bind_generic_ok = {.status = REPLY_OK};
    bind_replies[bind_reply_count++] = bind_generic_ok; // startWrite
    for (size_t i = 0; i < 16; i++) {
        bind_replies[bind_reply_count++] = bind_generic_ok; // writeData
    }
    bind_replies[bind_reply_count++] = bind_generic_ok; // endWrite
    for (size_t i = 0; i < bind_data_chunk_count; i++) {
        bind_replies[bind_reply_count++] = bind_data_chunks[i]; // verify readback
    }
    if (bind_reply_count > sizeof(bind_replies) / sizeof(bind_replies[0])) {
        fprintf(stderr, "run_bind self-test reply buffer overflowed\n");
        return 1;
    }

    DiscoverDevicesTestContext bind_discovery_context = {
        .devices = &set_dpi_device, .count = 1, .result = 1};
    discover_devices_for_options_impl = discover_devices_for_options_test_double;
    g_discover_devices_test_context = &bind_discovery_context;

    ChannelRequestTestContext bind_channel_context = {
        .replies = bind_replies, .reply_count = bind_reply_count, .calls = 0};
    channel_request_impl = channel_request_test_double;
    g_channel_request_test_context = &bind_channel_context;

    const char *bind_backup_path = "/tmp/lomps-selftest-bind-backup.logiob";
    unlink(bind_backup_path);

    Options bind_run_options;
    memset(&bind_run_options, 0, sizeof(bind_run_options));
    bind_run_options.device_index = -1;
    bind_run_options.dpi_default = -1;
    bind_run_options.dpi_shift = -1;
    bind_run_options.yes = true;
    bind_run_options.backup_path = bind_backup_path;
    bind_run_options.target = "middle";
    bind_run_options.button = 4;

    int bind_result = run_bind(&bind_run_options);
    unlink(bind_backup_path);
    if (bind_result != 0) {
        fprintf(stderr, "run_bind happy-path self-test failed (result=%d)\n", bind_result);
        return 1;
    }

    discover_devices_for_options_impl = discover_devices_for_options_hardware;
    g_discover_devices_test_context = NULL;
    channel_request_impl = channel_request_hardware;
    g_channel_request_test_context = NULL;

    printf("self-test: receiver model-name fallback, connection types, CRC-16, DPI "
           "sentinel/compaction, format/layout detection, G600 legacy mapping, batch "
           "planning/failure handling, rear-thumb identification, Alt+Tab encoding, "
           "report-rate decoding, device selection, and command-layer discovery mocking "
           "passed\n");
    return 0;
}
