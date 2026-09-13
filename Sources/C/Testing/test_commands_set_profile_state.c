#include "internal.h"
#include "test_doubles.h"

int test_commands_set_profile_state(void) {
    // run_set_profile_state: trivial argument-validation failures need no
    // device or channel mocking at all.
    Options profile_state_bad_count = {0};
    profile_state_bad_count.positional_count = 1;
    if (run_set_profile_state(&profile_state_bad_count) != 1) {
        fprintf(stderr, "run_set_profile_state positional-count self-test failed\n");
        return 1;
    }

    Options profile_state_bad_number = {0};
    profile_state_bad_number.positional_count = 2;
    profile_state_bad_number.positionals[0] = "not-a-number";
    profile_state_bad_number.positionals[1] = "enable";
    if (run_set_profile_state(&profile_state_bad_number) != 1) {
        fprintf(stderr, "run_set_profile_state invalid-profile-number self-test failed\n");
        return 1;
    }

    Options profile_state_bad_word = {0};
    profile_state_bad_word.positional_count = 2;
    profile_state_bad_word.positionals[0] = "1";
    profile_state_bad_word.positionals[1] = "maybe";
    if (run_set_profile_state(&profile_state_bad_word) != 1) {
        fprintf(stderr, "run_set_profile_state invalid-state-word self-test failed\n");
        return 1;
    }

    Options profile_state_no_device = {0};
    profile_state_no_device.positional_count = 2;
    profile_state_no_device.positionals[0] = "1";
    profile_state_no_device.positionals[1] = "enable";
    profile_state_no_device.device_index = -1;
    DiscoverDevicesTestContext profile_state_empty_discovery = {
        .devices = NULL, .count = 0, .result = 1};
    discover_devices_for_options_impl = discover_devices_for_options_test_double;
    g_discover_devices_test_context = &profile_state_empty_discovery;
    if (run_set_profile_state(&profile_state_no_device) != 1) {
        fprintf(stderr, "run_set_profile_state no-device self-test failed\n");
        return 1;
    }

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
    DiscoverDevicesTestContext profile_state_discovery = {
        .devices = &profile_state_device, .count = 1, .result = 1};
    g_discover_devices_test_context = &profile_state_discovery;
    channel_request_impl = channel_request_test_double;

    ChannelRequestTestContext profile_state_no_info_channel = {
        .replies = NULL, .reply_count = 0, .calls = 0};
    g_channel_request_test_context = &profile_state_no_info_channel;
    Options profile_state_info_fails = {0};
    profile_state_info_fails.positional_count = 2;
    profile_state_info_fails.positionals[0] = "1";
    profile_state_info_fails.positionals[1] = "enable";
    profile_state_info_fails.device_index = -1;
    if (run_set_profile_state(&profile_state_info_fails) != 1) {
        fprintf(stderr, "run_set_profile_state get-profile-info-failure self-test failed\n");
        return 1;
    }

    // A 255-byte control sector (matching k_mock_get_info_reply's reported
    // sector size) with two profile headers: profile 1 (sector 0x0123,
    // enabled) and profile 2 (sector 0x0200, disabled).
    uint8_t profile_state_control[255];
    build_mock_control_sector_two_profiles(profile_state_control);

    Reply profile_state_control_chunks[32];
    size_t profile_state_control_chunk_count = build_sector_read_replies(
        profile_state_control, sizeof(profile_state_control), profile_state_control_chunks, 32);
    if (profile_state_control_chunk_count == 0) {
        fprintf(stderr,
                "run_set_profile_state self-test failed to build mock control-sector replies\n");
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
        fprintf(
            stderr,
            "run_set_profile_state self-test failed to build corrupted control-sector replies\n");
        return 1;
    }
    Reply profile_state_bad_crc_replies[40];
    size_t profile_state_bad_crc_reply_count = 0;
    profile_state_bad_crc_replies[profile_state_bad_crc_reply_count++] = k_mock_get_info_reply;
    for (size_t i = 0; i < profile_state_bad_crc_chunk_count; i++) {
        profile_state_bad_crc_replies[profile_state_bad_crc_reply_count++] =
            profile_state_bad_crc_chunks[i];
    }
    ChannelRequestTestContext profile_state_bad_crc_channel = {
        .replies = profile_state_bad_crc_replies,
        .reply_count = profile_state_bad_crc_reply_count,
        .calls = 0};
    g_channel_request_test_context = &profile_state_bad_crc_channel;
    Options profile_state_bad_crc_options = {0};
    profile_state_bad_crc_options.positional_count = 2;
    profile_state_bad_crc_options.positionals[0] = "1";
    profile_state_bad_crc_options.positionals[1] = "enable";
    profile_state_bad_crc_options.device_index = -1;
    if (run_set_profile_state(&profile_state_bad_crc_options) != 1) {
        fprintf(stderr, "run_set_profile_state invalid-control-CRC self-test failed\n");
        return 1;
    }

    // Shared full-chain reply prefix (getInfo + one valid control-sector
    // read) for the remaining cases, all of which need validated headers
    // before reaching their branch under test.
    Reply profile_state_loaded_replies[40];
    size_t profile_state_loaded_reply_count = 0;
    profile_state_loaded_replies[profile_state_loaded_reply_count++] = k_mock_get_info_reply;
    for (size_t i = 0; i < profile_state_control_chunk_count; i++) {
        profile_state_loaded_replies[profile_state_loaded_reply_count++] =
            profile_state_control_chunks[i];
    }
    size_t profile_state_loaded_prefix_count = profile_state_loaded_reply_count;

    Reply profile_state_out_of_range_replies[40];
    memcpy(profile_state_out_of_range_replies, profile_state_loaded_replies,
           profile_state_loaded_prefix_count * sizeof(Reply));
    ChannelRequestTestContext profile_state_out_of_range_channel = {
        .replies = profile_state_out_of_range_replies,
        .reply_count = profile_state_loaded_prefix_count,
        .calls = 0};
    g_channel_request_test_context = &profile_state_out_of_range_channel;
    Options profile_state_out_of_range = {0};
    profile_state_out_of_range.positional_count = 2;
    profile_state_out_of_range.positionals[0] = "3";
    profile_state_out_of_range.positionals[1] = "enable";
    profile_state_out_of_range.device_index = -1;
    if (run_set_profile_state(&profile_state_out_of_range) != 1) {
        fprintf(stderr, "run_set_profile_state profile-out-of-range self-test failed\n");
        return 1;
    }

    Reply profile_state_noop_replies[40];
    memcpy(profile_state_noop_replies, profile_state_loaded_replies,
           profile_state_loaded_prefix_count * sizeof(Reply));
    ChannelRequestTestContext profile_state_noop_channel = {.replies = profile_state_noop_replies,
                                                            .reply_count =
                                                                profile_state_loaded_prefix_count,
                                                            .calls = 0};
    g_channel_request_test_context = &profile_state_noop_channel;
    Options profile_state_noop = {0};
    profile_state_noop.positional_count = 2;
    profile_state_noop.positionals[0] = "1";
    profile_state_noop.positionals[1] = "enable";
    profile_state_noop.device_index = -1;
    if (run_set_profile_state(&profile_state_noop) != 0) {
        fprintf(stderr, "run_set_profile_state already-in-state self-test failed\n");
        return 1;
    }

    Reply profile_state_last_enabled_replies[40];
    memcpy(profile_state_last_enabled_replies, profile_state_loaded_replies,
           profile_state_loaded_prefix_count * sizeof(Reply));
    ChannelRequestTestContext profile_state_last_enabled_channel = {
        .replies = profile_state_last_enabled_replies,
        .reply_count = profile_state_loaded_prefix_count,
        .calls = 0};
    g_channel_request_test_context = &profile_state_last_enabled_channel;
    Options profile_state_last_enabled = {0};
    profile_state_last_enabled.positional_count = 2;
    profile_state_last_enabled.positionals[0] = "1";
    profile_state_last_enabled.positionals[1] = "disable";
    profile_state_last_enabled.device_index = -1;
    if (run_set_profile_state(&profile_state_last_enabled) != 1) {
        fprintf(stderr, "run_set_profile_state disable-last-enabled self-test failed\n");
        return 1;
    }

    Reply profile_state_preview_replies[40];
    memcpy(profile_state_preview_replies, profile_state_loaded_replies,
           profile_state_loaded_prefix_count * sizeof(Reply));
    ChannelRequestTestContext profile_state_preview_channel = {
        .replies = profile_state_preview_replies,
        .reply_count = profile_state_loaded_prefix_count,
        .calls = 0};
    g_channel_request_test_context = &profile_state_preview_channel;
    Options profile_state_preview = {0};
    profile_state_preview.positional_count = 2;
    profile_state_preview.positionals[0] = "2";
    profile_state_preview.positionals[1] = "enable";
    profile_state_preview.device_index = -1;
    profile_state_preview.yes = false;
    if (run_set_profile_state(&profile_state_preview) != 0) {
        fprintf(stderr, "run_set_profile_state preview-mode self-test failed\n");
        return 1;
    }

    Reply profile_state_mode_switch_replies[40];
    memcpy(profile_state_mode_switch_replies, profile_state_loaded_replies,
           profile_state_loaded_prefix_count * sizeof(Reply));
    profile_state_mode_switch_replies[profile_state_loaded_prefix_count] = k_mock_host_mode_reply;
    ChannelRequestTestContext profile_state_mode_switch_channel = {
        .replies = profile_state_mode_switch_replies,
        .reply_count = profile_state_loaded_prefix_count + 1,
        .calls = 0};
    g_channel_request_test_context = &profile_state_mode_switch_channel;
    Options profile_state_mode_switch_fails = {0};
    profile_state_mode_switch_fails.positional_count = 2;
    profile_state_mode_switch_fails.positionals[0] = "2";
    profile_state_mode_switch_fails.positionals[1] = "enable";
    profile_state_mode_switch_fails.device_index = -1;
    profile_state_mode_switch_fails.yes = true;
    if (run_set_profile_state(&profile_state_mode_switch_fails) != 1) {
        fprintf(stderr, "run_set_profile_state onboard-mode-switch-failure self-test failed\n");
        return 1;
    }

    Reply profile_state_backup_fail_replies[40];
    memcpy(profile_state_backup_fail_replies, profile_state_loaded_replies,
           profile_state_loaded_prefix_count * sizeof(Reply));
    profile_state_backup_fail_replies[profile_state_loaded_prefix_count] =
        k_mock_onboard_mode_reply;
    ChannelRequestTestContext profile_state_backup_fail_channel = {
        .replies = profile_state_backup_fail_replies,
        .reply_count = profile_state_loaded_prefix_count + 1,
        .calls = 0};
    g_channel_request_test_context = &profile_state_backup_fail_channel;
    Options profile_state_backup_fail = {0};
    profile_state_backup_fail.positional_count = 2;
    profile_state_backup_fail.positionals[0] = "2";
    profile_state_backup_fail.positionals[1] = "enable";
    profile_state_backup_fail.device_index = -1;
    profile_state_backup_fail.yes = true;
    profile_state_backup_fail.backup_path = "/nonexistent-lope-test-directory/backup.bin";
    if (run_set_profile_state(&profile_state_backup_fail) != 1) {
        fprintf(stderr, "run_set_profile_state backup-write-failure self-test failed\n");
        return 1;
    }

    Reply profile_state_write_fail_replies[40];
    memcpy(profile_state_write_fail_replies, profile_state_loaded_replies,
           profile_state_loaded_prefix_count * sizeof(Reply));
    profile_state_write_fail_replies[profile_state_loaded_prefix_count] = k_mock_onboard_mode_reply;
    ChannelRequestTestContext profile_state_write_fail_channel = {
        .replies = profile_state_write_fail_replies,
        .reply_count = profile_state_loaded_prefix_count + 1,
        .calls = 0};
    g_channel_request_test_context = &profile_state_write_fail_channel;
    const char *profile_state_write_fail_backup_path =
        "/tmp/lomps-selftest-profile-state-write-fail-backup.logiob";
    unlink(profile_state_write_fail_backup_path);
    Options profile_state_write_fail = {0};
    profile_state_write_fail.positional_count = 2;
    profile_state_write_fail.positionals[0] = "2";
    profile_state_write_fail.positionals[1] = "enable";
    profile_state_write_fail.device_index = -1;
    profile_state_write_fail.yes = true;
    profile_state_write_fail.backup_path = profile_state_write_fail_backup_path;
    int profile_state_write_fail_result = run_set_profile_state(&profile_state_write_fail);
    unlink(profile_state_write_fail_backup_path);
    if (profile_state_write_fail_result != 1) {
        fprintf(stderr, "run_set_profile_state write-failure self-test failed\n");
        return 1;
    }

    // Happy path: enable profile 2, which starts disabled in the mock
    // control sector, exercising the full write + verify-readback path.
    uint8_t profile_state_after[255];
    memcpy(profile_state_after, profile_state_control, sizeof(profile_state_after));
    profile_state_after[6] = 1;
    sector_put_crc(profile_state_after, sizeof(profile_state_after));
    Reply profile_state_after_chunks[32];
    size_t profile_state_after_chunk_count = build_sector_read_replies(
        profile_state_after, sizeof(profile_state_after), profile_state_after_chunks, 32);
    if (profile_state_after_chunk_count == 0) {
        fprintf(stderr, "run_set_profile_state self-test failed to build post-write mock "
                        "sector-read replies\n");
        return 1;
    }
    Reply profile_state_happy_replies[80];
    size_t profile_state_happy_reply_count = 0;
    for (size_t i = 0; i < profile_state_loaded_prefix_count; i++) {
        profile_state_happy_replies[profile_state_happy_reply_count++] =
            profile_state_loaded_replies[i];
    }
    profile_state_happy_replies[profile_state_happy_reply_count++] = k_mock_onboard_mode_reply;
    profile_state_happy_replies[profile_state_happy_reply_count++] =
        k_mock_generic_ok_reply; // startWrite
    for (size_t i = 0; i < 16; i++) {
        profile_state_happy_replies[profile_state_happy_reply_count++] =
            k_mock_generic_ok_reply; // writeData
    }
    profile_state_happy_replies[profile_state_happy_reply_count++] =
        k_mock_generic_ok_reply; // endWrite
    for (size_t i = 0; i < profile_state_after_chunk_count; i++) {
        profile_state_happy_replies[profile_state_happy_reply_count++] =
            profile_state_after_chunks[i]; // verify readback
    }
    if (profile_state_happy_reply_count >
        sizeof(profile_state_happy_replies) / sizeof(profile_state_happy_replies[0])) {
        fprintf(stderr, "run_set_profile_state self-test reply buffer overflowed\n");
        return 1;
    }
    ChannelRequestTestContext profile_state_happy_channel = {.replies = profile_state_happy_replies,
                                                             .reply_count =
                                                                 profile_state_happy_reply_count,
                                                             .calls = 0};
    g_channel_request_test_context = &profile_state_happy_channel;
    const char *profile_state_happy_backup_path = "/tmp/lomps-selftest-profile-state-backup.logiob";
    unlink(profile_state_happy_backup_path);
    Options profile_state_happy = {0};
    profile_state_happy.positional_count = 2;
    profile_state_happy.positionals[0] = "2";
    profile_state_happy.positionals[1] = "enable";
    profile_state_happy.device_index = -1;
    profile_state_happy.yes = true;
    profile_state_happy.backup_path = profile_state_happy_backup_path;
    int profile_state_happy_result = run_set_profile_state(&profile_state_happy);
    unlink(profile_state_happy_backup_path);
    if (profile_state_happy_result != 0) {
        fprintf(stderr, "run_set_profile_state happy-path self-test failed (result=%d)\n",
                profile_state_happy_result);
        return 1;
    }

    return 0;
}
