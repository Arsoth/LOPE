#include "commands_set_dpi.h"
#include "profile_io.h"
#include "test_doubles.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int set_dpi_context_create_failure(HidContext *context) {
    (void)context;
    return 0;
}

int test_commands_set_dpi(void) {
    uint16_t dpi_list_values[MAX_DPI_VALUES] = {800, 1600, 2400};
    bool dpi_value_in_list_ok =
        dpi_value_in_list(dpi_list_values, 3, 1600) && !dpi_value_in_list(dpi_list_values, 3, 3200);
    if (!dpi_value_in_list_ok) {
        fprintf(stderr, "dpi_value_in_list self-test failed\n");
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
    set_dpi_replies[set_dpi_reply_count++] = k_mock_onboard_mode_reply;
    set_dpi_replies[set_dpi_reply_count++] = k_mock_generic_ok_reply; // startWrite
    for (size_t i = 0; i < 16; i++) {
        set_dpi_replies[set_dpi_reply_count++] = k_mock_generic_ok_reply; // writeData
    }
    set_dpi_replies[set_dpi_reply_count++] = k_mock_generic_ok_reply; // endWrite
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

    // run_set_dpi validation/error paths: each case is set up with just
    // enough mock replies to reach the branch under test, relying on
    // channel_request_test_double's out-of-replies timeout to fail whatever
    // device call comes next.
    Options set_dpi_bad_count = {0};
    if (run_set_dpi(&set_dpi_bad_count) != 1) {
        fprintf(stderr, "run_set_dpi positional-count self-test failed\n");
        return 1;
    }

    Options set_dpi_bad_list = {0};
    set_dpi_bad_list.positional_count = 1;
    set_dpi_bad_list.positionals[0] = "not-a-list";
    if (run_set_dpi(&set_dpi_bad_list) != 1) {
        fprintf(stderr, "run_set_dpi invalid-DPI-list self-test failed\n");
        return 1;
    }

    Options set_dpi_no_device = {0};
    set_dpi_no_device.positional_count = 1;
    set_dpi_no_device.positionals[0] = "800,1600";
    set_dpi_no_device.device_index = -1;
    DiscoverDevicesTestContext set_dpi_empty_discovery = {.devices = NULL, .count = 0, .result = 1};
    discover_devices_for_options_impl = discover_devices_for_options_test_double;
    g_discover_devices_test_context = &set_dpi_empty_discovery;
    if (run_set_dpi(&set_dpi_no_device) != 1) {
        fprintf(stderr, "run_set_dpi no-device self-test failed\n");
        return 1;
    }

    Device set_dpi_device_no_feature = set_dpi_device;
    set_dpi_device_no_feature.feature_count = 1;
    set_dpi_device_no_feature.features[0] = (Feature){.id = FEATURE_ONBOARD_PROFILES, .index = 5};
    DiscoverDevicesTestContext set_dpi_no_feature_discovery = {
        .devices = &set_dpi_device_no_feature, .count = 1, .result = 1};
    g_discover_devices_test_context = &set_dpi_no_feature_discovery;
    ChannelRequestTestContext set_dpi_empty_channel = {
        .replies = NULL, .reply_count = 0, .calls = 0};
    channel_request_impl = channel_request_test_double;
    g_channel_request_test_context = &set_dpi_empty_channel;
    Options set_dpi_no_dpi_feature = {0};
    set_dpi_no_dpi_feature.positional_count = 1;
    set_dpi_no_dpi_feature.positionals[0] = "800,1600";
    set_dpi_no_dpi_feature.device_index = -1;
    if (run_set_dpi(&set_dpi_no_dpi_feature) != 1) {
        fprintf(stderr, "run_set_dpi missing-ADJUSTABLE_DPI-feature self-test failed\n");
        return 1;
    }

    DiscoverDevicesTestContext set_dpi_full_discovery = {
        .devices = &set_dpi_device, .count = 1, .result = 1};
    g_discover_devices_test_context = &set_dpi_full_discovery;

    Reply set_dpi_sensor_count_1 = {.status = REPLY_OK, .length = 1, .bytes = {1}};
    Reply set_dpi_sensor_count_2 = {.status = REPLY_OK, .length = 1, .bytes = {2}};
    Reply set_dpi_sensor_list = {
        .status = REPLY_OK,
        .length = 11,
        .bytes = {0x00, 0x03, 0x20, 0x04, 0xB0, 0x06, 0x40, 0x09, 0x60, 0x0C, 0x80}};

    Reply set_dpi_sensor_count_replies[] = {set_dpi_sensor_count_2, set_dpi_sensor_list};
    ChannelRequestTestContext set_dpi_sensor_count_channel = {
        .replies = set_dpi_sensor_count_replies, .reply_count = 2, .calls = 0};
    g_channel_request_test_context = &set_dpi_sensor_count_channel;
    Options set_dpi_multi_sensor = {0};
    set_dpi_multi_sensor.positional_count = 1;
    set_dpi_multi_sensor.positionals[0] = "800,1600";
    set_dpi_multi_sensor.device_index = -1;
    if (run_set_dpi(&set_dpi_multi_sensor) != 1) {
        fprintf(stderr, "run_set_dpi multi-sensor self-test failed\n");
        return 1;
    }

    Reply set_dpi_probe_replies[] = {set_dpi_sensor_count_1, set_dpi_sensor_list};
    ChannelRequestTestContext set_dpi_probe_channel = {
        .replies = set_dpi_probe_replies, .reply_count = 2, .calls = 0};

    g_channel_request_test_context = &set_dpi_probe_channel;
    Options set_dpi_unsupported_value = {0};
    set_dpi_unsupported_value.positional_count = 1;
    set_dpi_unsupported_value.positionals[0] = "900,1000";
    set_dpi_unsupported_value.device_index = -1;
    if (run_set_dpi(&set_dpi_unsupported_value) != 1) {
        fprintf(stderr, "run_set_dpi unsupported-DPI-value self-test failed\n");
        return 1;
    }

    set_dpi_probe_channel.calls = 0;
    g_channel_request_test_context = &set_dpi_probe_channel;
    Options set_dpi_decreasing = {0};
    set_dpi_decreasing.positional_count = 1;
    set_dpi_decreasing.positionals[0] = "1600,800";
    set_dpi_decreasing.device_index = -1;
    if (run_set_dpi(&set_dpi_decreasing) != 1) {
        fprintf(stderr, "run_set_dpi non-increasing-DPI self-test failed\n");
        return 1;
    }

    set_dpi_probe_channel.calls = 0;
    g_channel_request_test_context = &set_dpi_probe_channel;
    Options set_dpi_profile_load_fails = {0};
    set_dpi_profile_load_fails.positional_count = 1;
    set_dpi_profile_load_fails.positionals[0] = "800,1600";
    set_dpi_profile_load_fails.device_index = -1;
    if (run_set_dpi(&set_dpi_profile_load_fails) != 1) {
        fprintf(stderr, "run_set_dpi profile-load-failure self-test failed\n");
        return 1;
    }

    uint8_t set_dpi_crc_bad_sector[255];
    memcpy(set_dpi_crc_bad_sector, mock_sector, sizeof(set_dpi_crc_bad_sector));
    set_dpi_crc_bad_sector[254] ^= 0xFF;
    Reply set_dpi_crc_bad_data_chunks[32];
    size_t set_dpi_crc_bad_data_chunk_count = build_sector_read_replies(
        set_dpi_crc_bad_sector, sizeof(set_dpi_crc_bad_sector), set_dpi_crc_bad_data_chunks, 32);
    if (set_dpi_crc_bad_data_chunk_count == 0) {
        fprintf(stderr,
                "run_set_dpi self-test failed to build corrupted mock sector-read replies\n");
        return 1;
    }
    Reply set_dpi_crc_bad_replies[64];
    size_t set_dpi_crc_bad_reply_count = 0;
    set_dpi_crc_bad_replies[set_dpi_crc_bad_reply_count++] = set_dpi_sensor_count_1;
    set_dpi_crc_bad_replies[set_dpi_crc_bad_reply_count++] = set_dpi_sensor_list;
    set_dpi_crc_bad_replies[set_dpi_crc_bad_reply_count++] = k_mock_get_info_reply;
    for (size_t i = 0; i < control_chunk_count; i++) {
        set_dpi_crc_bad_replies[set_dpi_crc_bad_reply_count++] = control_chunks[i];
    }
    for (size_t i = 0; i < set_dpi_crc_bad_data_chunk_count; i++) {
        set_dpi_crc_bad_replies[set_dpi_crc_bad_reply_count++] = set_dpi_crc_bad_data_chunks[i];
    }
    ChannelRequestTestContext set_dpi_crc_bad_channel = {
        .replies = set_dpi_crc_bad_replies, .reply_count = set_dpi_crc_bad_reply_count, .calls = 0};
    g_channel_request_test_context = &set_dpi_crc_bad_channel;
    Options set_dpi_crc_bad_options = {0};
    set_dpi_crc_bad_options.positional_count = 1;
    set_dpi_crc_bad_options.positionals[0] = "800,1600";
    set_dpi_crc_bad_options.device_index = -1;
    if (run_set_dpi(&set_dpi_crc_bad_options) != 1) {
        fprintf(stderr, "run_set_dpi invalid-CRC self-test failed\n");
        return 1;
    }

    // Shared full-chain reply prefix (sensor probe, profile load) for the
    // remaining cases, all of which need a successfully validated profile
    // before reaching their branch under test.
    Reply set_dpi_loaded_replies[64];
    size_t set_dpi_loaded_reply_count = 0;
    set_dpi_loaded_replies[set_dpi_loaded_reply_count++] = set_dpi_sensor_count_1;
    set_dpi_loaded_replies[set_dpi_loaded_reply_count++] = set_dpi_sensor_list;
    set_dpi_loaded_replies[set_dpi_loaded_reply_count++] = k_mock_get_info_reply;
    for (size_t i = 0; i < control_chunk_count; i++) {
        set_dpi_loaded_replies[set_dpi_loaded_reply_count++] = control_chunks[i];
    }
    for (size_t i = 0; i < data_chunk_count; i++) {
        set_dpi_loaded_replies[set_dpi_loaded_reply_count++] = data_chunks[i];
    }
    size_t set_dpi_loaded_prefix_count = set_dpi_loaded_reply_count;

    Reply set_dpi_out_of_range_replies[64];
    memcpy(set_dpi_out_of_range_replies, set_dpi_loaded_replies,
           set_dpi_loaded_prefix_count * sizeof(Reply));
    ChannelRequestTestContext set_dpi_out_of_range_channel = {
        .replies = set_dpi_out_of_range_replies,
        .reply_count = set_dpi_loaded_prefix_count,
        .calls = 0};
    g_channel_request_test_context = &set_dpi_out_of_range_channel;
    Options set_dpi_out_of_range = {0};
    set_dpi_out_of_range.positional_count = 1;
    set_dpi_out_of_range.positionals[0] = "800,1600";
    set_dpi_out_of_range.device_index = -1;
    set_dpi_out_of_range.dpi_default = 5;
    set_dpi_out_of_range.dpi_shift = -1;
    if (run_set_dpi(&set_dpi_out_of_range) != 1) {
        fprintf(stderr, "run_set_dpi out-of-range DPI index self-test failed\n");
        return 1;
    }

    Reply set_dpi_preview_replies[64];
    memcpy(set_dpi_preview_replies, set_dpi_loaded_replies,
           set_dpi_loaded_prefix_count * sizeof(Reply));
    ChannelRequestTestContext set_dpi_preview_channel = {
        .replies = set_dpi_preview_replies, .reply_count = set_dpi_loaded_prefix_count, .calls = 0};
    g_channel_request_test_context = &set_dpi_preview_channel;
    Options set_dpi_preview = {0};
    set_dpi_preview.positional_count = 1;
    set_dpi_preview.positionals[0] = "800,1600";
    set_dpi_preview.device_index = -1;
    set_dpi_preview.dpi_default = 1;
    set_dpi_preview.dpi_shift = 1;
    set_dpi_preview.yes = false;
    if (run_set_dpi(&set_dpi_preview) != 0) {
        fprintf(stderr, "run_set_dpi preview-mode self-test failed\n");
        return 1;
    }

    Reply set_dpi_mode_switch_replies[64];
    memcpy(set_dpi_mode_switch_replies, set_dpi_loaded_replies,
           set_dpi_loaded_prefix_count * sizeof(Reply));
    set_dpi_mode_switch_replies[set_dpi_loaded_prefix_count] = k_mock_host_mode_reply;
    ChannelRequestTestContext set_dpi_mode_switch_channel = {.replies = set_dpi_mode_switch_replies,
                                                             .reply_count =
                                                                 set_dpi_loaded_prefix_count + 1,
                                                             .calls = 0};
    g_channel_request_test_context = &set_dpi_mode_switch_channel;
    Options set_dpi_mode_switch_fails = {0};
    set_dpi_mode_switch_fails.positional_count = 1;
    set_dpi_mode_switch_fails.positionals[0] = "800,1600";
    set_dpi_mode_switch_fails.device_index = -1;
    set_dpi_mode_switch_fails.dpi_default = 1;
    set_dpi_mode_switch_fails.dpi_shift = 1;
    set_dpi_mode_switch_fails.yes = true;
    if (run_set_dpi(&set_dpi_mode_switch_fails) != 1) {
        fprintf(stderr, "run_set_dpi onboard-mode-switch-failure self-test failed\n");
        return 1;
    }

    Reply set_dpi_backup_fail_replies[64];
    memcpy(set_dpi_backup_fail_replies, set_dpi_loaded_replies,
           set_dpi_loaded_prefix_count * sizeof(Reply));
    set_dpi_backup_fail_replies[set_dpi_loaded_prefix_count] = k_mock_onboard_mode_reply;
    ChannelRequestTestContext set_dpi_backup_fail_channel = {.replies = set_dpi_backup_fail_replies,
                                                             .reply_count =
                                                                 set_dpi_loaded_prefix_count + 1,
                                                             .calls = 0};
    g_channel_request_test_context = &set_dpi_backup_fail_channel;
    Options set_dpi_backup_fail = {0};
    set_dpi_backup_fail.positional_count = 1;
    set_dpi_backup_fail.positionals[0] = "800,1600";
    set_dpi_backup_fail.device_index = -1;
    set_dpi_backup_fail.dpi_default = 1;
    set_dpi_backup_fail.dpi_shift = 1;
    set_dpi_backup_fail.yes = true;
    set_dpi_backup_fail.backup_path = "/nonexistent-lope-test-directory/backup.bin";
    if (run_set_dpi(&set_dpi_backup_fail) != 1) {
        fprintf(stderr, "run_set_dpi backup-write-failure self-test failed\n");
        return 1;
    }

    Reply set_dpi_write_fail_replies[64];
    memcpy(set_dpi_write_fail_replies, set_dpi_loaded_replies,
           set_dpi_loaded_prefix_count * sizeof(Reply));
    set_dpi_write_fail_replies[set_dpi_loaded_prefix_count] = k_mock_onboard_mode_reply;
    ChannelRequestTestContext set_dpi_write_fail_channel = {.replies = set_dpi_write_fail_replies,
                                                            .reply_count =
                                                                set_dpi_loaded_prefix_count + 1,
                                                            .calls = 0};
    g_channel_request_test_context = &set_dpi_write_fail_channel;
    const char *set_dpi_write_fail_backup_path =
        "/tmp/lomps-selftest-set-dpi-write-fail-backup.logiob";
    unlink(set_dpi_write_fail_backup_path);
    Options set_dpi_write_fail = {0};
    set_dpi_write_fail.positional_count = 1;
    set_dpi_write_fail.positionals[0] = "800,1600";
    set_dpi_write_fail.device_index = -1;
    set_dpi_write_fail.dpi_default = 1;
    set_dpi_write_fail.dpi_shift = 1;
    set_dpi_write_fail.yes = true;
    set_dpi_write_fail.backup_path = set_dpi_write_fail_backup_path;
    int set_dpi_write_fail_result = run_set_dpi(&set_dpi_write_fail);
    unlink(set_dpi_write_fail_backup_path);
    if (set_dpi_write_fail_result != 1) {
        fprintf(stderr, "run_set_dpi write/verify-failure self-test failed\n");
        return 1;
    }

    // run_set_dpi refuses to pick an implicit profile when --profile is
    // omitted and the device has more than one profile slot.
    uint8_t set_dpi_multi_header_control[132];
    memset(set_dpi_multi_header_control, 0, sizeof(set_dpi_multi_header_control));
    set_dpi_multi_header_control[0] = 0x01;
    set_dpi_multi_header_control[1] = 0x23;
    set_dpi_multi_header_control[2] = 0x01;
    set_dpi_multi_header_control[4] = 0x02;
    set_dpi_multi_header_control[5] = 0x00;
    set_dpi_multi_header_control[6] = 0x01;
    Reply set_dpi_multi_header_chunks[32];
    size_t set_dpi_multi_header_chunk_count = build_sector_read_replies(
        set_dpi_multi_header_control, sizeof(set_dpi_multi_header_control),
        set_dpi_multi_header_chunks, 32);
    if (set_dpi_multi_header_chunk_count == 0) {
        fprintf(stderr, "run_set_dpi self-test failed to build multi-header control replies\n");
        return 1;
    }
    Reply set_dpi_multi_header_replies[64];
    size_t set_dpi_multi_header_reply_count = 0;
    set_dpi_multi_header_replies[set_dpi_multi_header_reply_count++] = set_dpi_sensor_count_1;
    set_dpi_multi_header_replies[set_dpi_multi_header_reply_count++] = set_dpi_sensor_list;
    set_dpi_multi_header_replies[set_dpi_multi_header_reply_count++] = k_mock_get_info_reply;
    for (size_t i = 0; i < set_dpi_multi_header_chunk_count; i++) {
        set_dpi_multi_header_replies[set_dpi_multi_header_reply_count++] =
            set_dpi_multi_header_chunks[i];
    }
    for (size_t i = 0; i < data_chunk_count; i++) {
        set_dpi_multi_header_replies[set_dpi_multi_header_reply_count++] = data_chunks[i];
    }
    ChannelRequestTestContext set_dpi_multi_header_channel = {
        .replies = set_dpi_multi_header_replies,
        .reply_count = set_dpi_multi_header_reply_count,
        .calls = 0};
    g_channel_request_test_context = &set_dpi_multi_header_channel;
    Options set_dpi_multi_header = {0};
    set_dpi_multi_header.positional_count = 1;
    set_dpi_multi_header.positionals[0] = "800,1600";
    set_dpi_multi_header.device_index = -1;
    if (run_set_dpi(&set_dpi_multi_header) != 1) {
        fprintf(stderr, "run_set_dpi implicit-profile-with-multiple-slots self-test failed\n");
        return 1;
    }

    // Exercise the remaining inexpensive command branches: constructor
    // failure, valid-CRC profiles with an invalid DPI layout, zero-based
    // index rejection, and a successful write followed by a bad read-back.
    hid_context_create_impl = set_dpi_context_create_failure;
    Options set_dpi_context_failure = {0};
    set_dpi_context_failure.positional_count = 1;
    set_dpi_context_failure.positionals[0] = "800,1600";
    if (run_set_dpi(&set_dpi_context_failure) != 1) {
        fprintf(stderr, "run_set_dpi context-failure self-test failed\n");
        return 1;
    }
    hid_context_create_impl = hid_context_create_hardware;

    uint8_t set_dpi_bad_layout_sector[255];
    memcpy(set_dpi_bad_layout_sector, mock_sector, sizeof(set_dpi_bad_layout_sector));
    set_dpi_bad_layout_sector[3] = 0;
    set_dpi_bad_layout_sector[4] = 0;
    sector_put_crc(set_dpi_bad_layout_sector, sizeof(set_dpi_bad_layout_sector));
    Reply set_dpi_bad_layout_chunks[32];
    size_t set_dpi_bad_layout_chunk_count =
        build_sector_read_replies(set_dpi_bad_layout_sector, sizeof(set_dpi_bad_layout_sector),
                                  set_dpi_bad_layout_chunks, 32);
    Reply set_dpi_bad_layout_replies[64];
    size_t set_dpi_bad_layout_reply_count = 0;
    set_dpi_bad_layout_replies[set_dpi_bad_layout_reply_count++] = set_dpi_sensor_count_1;
    set_dpi_bad_layout_replies[set_dpi_bad_layout_reply_count++] = set_dpi_sensor_list;
    set_dpi_bad_layout_replies[set_dpi_bad_layout_reply_count++] = k_mock_get_info_reply;
    for (size_t i = 0; i < control_chunk_count; i++) {
        set_dpi_bad_layout_replies[set_dpi_bad_layout_reply_count++] = control_chunks[i];
    }
    for (size_t i = 0; i < set_dpi_bad_layout_chunk_count; i++) {
        set_dpi_bad_layout_replies[set_dpi_bad_layout_reply_count++] = set_dpi_bad_layout_chunks[i];
    }
    ChannelRequestTestContext set_dpi_bad_layout_channel = {.replies = set_dpi_bad_layout_replies,
                                                            .reply_count =
                                                                set_dpi_bad_layout_reply_count,
                                                            .calls = 0};
    g_channel_request_test_context = &set_dpi_bad_layout_channel;
    Options set_dpi_bad_layout = {0};
    set_dpi_bad_layout.positional_count = 1;
    set_dpi_bad_layout.positionals[0] = "800,1600";
    set_dpi_bad_layout.device_index = -1;
    if (run_set_dpi(&set_dpi_bad_layout) != 1) {
        fprintf(stderr, "run_set_dpi invalid-DPI-layout self-test failed\n");
        return 1;
    }

    // Both zero values reach the two lower-bound sides of the index check.
    set_dpi_out_of_range_channel.calls = 0;
    g_channel_request_test_context = &set_dpi_out_of_range_channel;
    Options set_dpi_default_zero = set_dpi_out_of_range;
    set_dpi_default_zero.dpi_default = 0;
    set_dpi_default_zero.dpi_shift = -1;
    if (run_set_dpi(&set_dpi_default_zero) != 1) {
        fprintf(stderr, "run_set_dpi zero-default-index self-test failed\n");
        return 1;
    }

    set_dpi_out_of_range_channel.calls = 0;
    g_channel_request_test_context = &set_dpi_out_of_range_channel;
    Options set_dpi_shift_zero = set_dpi_out_of_range;
    set_dpi_shift_zero.dpi_default = 1;
    set_dpi_shift_zero.dpi_shift = 0;
    if (run_set_dpi(&set_dpi_shift_zero) != 1) {
        fprintf(stderr, "run_set_dpi zero-shift-index self-test failed\n");
        return 1;
    }

    set_dpi_out_of_range_channel.calls = 0;
    g_channel_request_test_context = &set_dpi_out_of_range_channel;
    Options set_dpi_shift_too_high = set_dpi_out_of_range;
    set_dpi_shift_too_high.dpi_default = 1;
    set_dpi_shift_too_high.dpi_shift = 5;
    if (run_set_dpi(&set_dpi_shift_too_high) != 1) {
        fprintf(stderr, "run_set_dpi shift-index-too-high self-test failed\n");
        return 1;
    }

    uint8_t set_dpi_wrong_readback[255];
    memcpy(set_dpi_wrong_readback, mock_sector, sizeof(set_dpi_wrong_readback));
    set_dpi_wrong_readback[3] ^= 0x01;
    sector_put_crc(set_dpi_wrong_readback, sizeof(set_dpi_wrong_readback));
    Reply set_dpi_wrong_chunks[32];
    size_t set_dpi_wrong_chunk_count = build_sector_read_replies(
        set_dpi_wrong_readback, sizeof(set_dpi_wrong_readback), set_dpi_wrong_chunks, 32);
    Reply set_dpi_readback_fail_replies[192];
    size_t set_dpi_readback_fail_count = 0;
    for (size_t i = 0; i < set_dpi_loaded_prefix_count; i++) {
        set_dpi_readback_fail_replies[set_dpi_readback_fail_count++] = set_dpi_loaded_replies[i];
    }
    set_dpi_readback_fail_replies[set_dpi_readback_fail_count++] = k_mock_onboard_mode_reply;
    set_dpi_readback_fail_replies[set_dpi_readback_fail_count++] = k_mock_generic_ok_reply;
    for (size_t i = 0; i < 16; i++) {
        set_dpi_readback_fail_replies[set_dpi_readback_fail_count++] = k_mock_generic_ok_reply;
    }
    set_dpi_readback_fail_replies[set_dpi_readback_fail_count++] = k_mock_generic_ok_reply;
    for (size_t attempt = 0; attempt < 5; attempt++) {
        for (size_t i = 0; i < set_dpi_wrong_chunk_count; i++) {
            set_dpi_readback_fail_replies[set_dpi_readback_fail_count++] = set_dpi_wrong_chunks[i];
        }
    }
    set_dpi_readback_fail_replies[set_dpi_readback_fail_count++] = k_mock_generic_ok_reply;
    ChannelRequestTestContext set_dpi_readback_fail_channel = {
        .replies = set_dpi_readback_fail_replies,
        .reply_count = set_dpi_readback_fail_count,
        .calls = 0};
    g_channel_request_test_context = &set_dpi_readback_fail_channel;
    const char *set_dpi_readback_backup = "/tmp/lomps-selftest-set-dpi-readback-fail.logiob";
    unlink(set_dpi_readback_backup);
    Options set_dpi_readback_fail = {0};
    set_dpi_readback_fail.positional_count = 1;
    set_dpi_readback_fail.positionals[0] = "800,1600";
    set_dpi_readback_fail.device_index = -1;
    set_dpi_readback_fail.dpi_default = 1;
    set_dpi_readback_fail.dpi_shift = 1;
    set_dpi_readback_fail.yes = true;
    set_dpi_readback_fail.backup_path = set_dpi_readback_backup;
    int set_dpi_readback_result = run_set_dpi(&set_dpi_readback_fail);
    unlink(set_dpi_readback_backup);
    if (set_dpi_readback_result != 1) {
        fprintf(stderr, "run_set_dpi readback-failure self-test failed\n");
        return 1;
    }

    return 0;
}
