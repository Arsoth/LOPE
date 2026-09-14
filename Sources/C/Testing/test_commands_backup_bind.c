#include "commands_backup_bind.h"
#include "backup.h"
#include "g600.h"
#include "profile_io.h"
#include "test_doubles.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static int create_empty_hid_context_for_backup_bind(HidContext *context) {
    memset(context, 0, sizeof(*context));
    return 1;
}

static int create_failed_hid_context_for_backup_bind(HidContext *context) {
    (void)context;
    return 0;
}

static bool fail_g600_feature_report_for_backup_bind(HidChannel *channel, uint8_t report_id,
                                                     uint8_t *report, size_t capacity,
                                                     size_t *length) {
    (void)channel;
    (void)report_id;
    (void)report;
    (void)capacity;
    (void)length;
    return false;
}

static Device make_backup_bind_device(HidInterface *interface) {
    memset(interface, 0, sizeof(*interface));
    interface->vendor_id = LOGITECH_VID;
    interface->product_id = 0xC099;
    Device device;
    memset(&device, 0, sizeof(device));
    device.iface = interface;
    device.device_number = 0xFF;
    device.request_device_number = 0xFF;
    device.protocol = 4.2;
    device.feature_count = 2;
    device.features[0] = (Feature){.id = FEATURE_ADJUSTABLE_DPI, .index = 3};
    device.features[1] = (Feature){.id = FEATURE_ONBOARD_PROFILES, .index = 5};
    return device;
}

static size_t append_replies(Reply *out, size_t offset, const Reply *replies, size_t count) {
    memcpy(out + offset, replies, count * sizeof(*replies));
    return offset + count;
}

static size_t append_sector_replies(Reply *out, size_t offset, const uint8_t *sector,
                                    size_t sector_size) {
    Reply chunks[32];
    size_t count = build_sector_read_replies(sector, sector_size, chunks, 32);
    return count == 0 ? 0 : append_replies(out, offset, chunks, count);
}

static size_t build_bind_profile_replies(Reply *out, const uint8_t *control,
                                         const uint8_t *profile) {
    size_t count = 0;
    out[count++] = k_mock_get_info_reply;
    count = append_sector_replies(out, count, control, MAX_HEADERS * 4 + 4);
    if (count == 0) {
        return 0;
    }
    count = append_sector_replies(out, count, profile, 255);
    return count;
}

static bool write_restore_package(const char *path, const Device *device, uint16_t sector,
                                  uint8_t profile_format, const uint8_t *data, size_t size) {
    BackupSectorSource source = {.sector = sector, .size = (uint16_t)size, .data = data};
    unlink(path);
    return package_write_multi(path, device, profile_format, &source, 1, false) != 0;
}

static size_t build_restore_profile_replies(Reply *out, const uint8_t *control,
                                            const uint8_t *current_profile) {
    size_t count = 0;
    out[count++] = k_mock_get_info_reply;
    count = append_sector_replies(out, count, control, 255);
    if (count == 0) {
        return 0;
    }
    count = append_sector_replies(out, count, current_profile, 255);
    return count;
}

static void install_backup_bind_mocks(DiscoverDevicesTestContext *discovery) {
    hid_context_create_impl = create_empty_hid_context_for_backup_bind;
    discover_devices_for_options_impl = discover_devices_for_options_test_double;
    g_discover_devices_test_context = discovery;
    channel_request_impl = channel_request_test_double;
}

int test_commands_backup_bind(void) {
    uint8_t hex_byte_value = 0;
    uint16_t hex_word_value = 0;
    bool hex_parser_ok =
        parse_hex_byte("2B", &hex_byte_value) && hex_byte_value == 0x2B &&
        !parse_hex_byte("2G", &hex_byte_value) && !parse_hex_byte("", &hex_byte_value) &&
        !parse_hex_byte(NULL, &hex_byte_value) && !parse_hex_byte("100", &hex_byte_value) &&
        !parse_hex_byte("GG", &hex_byte_value) &&
        !parse_hex_byte("FFFFFFFFFFFFFFFFFFFF", &hex_byte_value) &&
        parse_hex_word("00E9", &hex_word_value) && hex_word_value == 0x00E9 &&
        !parse_hex_word("ZZZZ", &hex_word_value) && !parse_hex_word("", &hex_word_value) &&
        !parse_hex_word(NULL, &hex_word_value) && !parse_hex_word("10000", &hex_word_value) &&
        !parse_hex_word("FFFFFFFFFFFFFFFFFFFF", &hex_word_value);
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
        parse_target("left-click", target_spec) && target_spec[3] == 0x01 &&
        parse_target("right", target_spec) && target_spec[3] == 0x02 &&
        parse_target("right-click", target_spec) && target_spec[3] == 0x02 &&
        parse_target("middle", target_spec) && target_spec[3] == 0x04 &&
        parse_target("middle-click", target_spec) && target_spec[3] == 0x04 &&
        parse_target("back", target_spec) && target_spec[3] == 0x08 &&
        parse_target("forward", target_spec) && target_spec[3] == 0x10 &&
        parse_target("button6", target_spec) && target_spec[3] == 0x20 &&
        parse_target("button7", target_spec) && target_spec[3] == 0x40 &&
        parse_target("button8", target_spec) && target_spec[3] == 0x80 &&
        parse_target("Alt+Tab", target_spec) && target_spec[1] == 0x02 && target_spec[3] == 0x2B &&
        parse_target("alt-tab", target_spec) && target_spec[0] == 0x80 && target_spec[1] == 0x02 &&
        target_spec[2] == 0x04 && target_spec[3] == 0x2B && parse_target("alt_tab", target_spec) &&
        target_spec[3] == 0x2B && parse_target("dpi-up", target_spec) && target_spec[1] == 0x03 &&
        parse_target("previous-dpi", target_spec) && target_spec[1] == 0x04 &&
        parse_target("next-dpi", target_spec) && target_spec[1] == 0x03 &&
        parse_target("dpi-down", target_spec) && target_spec[1] == 0x04 &&
        parse_target("dpi-cycle", target_spec) && target_spec[1] == 0x05 &&
        parse_target("cycle-dpi", target_spec) && target_spec[1] == 0x05 &&
        parse_target("dpi-default", target_spec) && target_spec[1] == 0x06 &&
        parse_target("dpi-shift", target_spec) && target_spec[1] == 0x07 &&
        parse_target("next-profile", target_spec) && target_spec[1] == 0x08 &&
        parse_target("previous-profile", target_spec) && target_spec[1] == 0x09 &&
        parse_target("cycle-profile", target_spec) && target_spec[1] == 0x0A &&
        parse_target("g-shift", target_spec) && target_spec[1] == 0x0B &&
        parse_target("nav-back", target_spec) && target_spec[3] == 0x2F &&
        parse_target("nav-forward", target_spec) && target_spec[3] == 0x30 &&
        parse_target("cmd-]", target_spec) && target_spec[3] == 0x30 &&
        parse_target("disable", target_spec) && target_spec[0] == 0xFF && target_spec[3] == 0xFF &&
        parse_target("off", target_spec) && target_spec[0] == 0xFF && target_spec[3] == 0xFF &&
        parse_target("none", target_spec) && target_spec[0] == 0xFF && target_spec[3] == 0xFF &&
        parse_target("key:04:2B", target_spec) && target_spec[2] == 0x04 &&
        target_spec[3] == 0x2B && !parse_target("key:04", target_spec) &&
        !parse_target("key:ZZ:2B", target_spec) && !parse_target("key::2B", target_spec) &&
        !parse_target("key:04:", target_spec) && parse_target("consumer:00E9", target_spec) &&
        target_spec[1] == 0x03 && target_spec[2] == 0x00 && target_spec[3] == 0xE9 &&
        !parse_target("consumer:ZZZZ", target_spec) &&
        !parse_target("key:1234567890ABCDEF:2B", target_spec) &&
        !parse_target("key:01:1234567890ABCDEF", target_spec) &&
        parse_target("80010004", target_spec) && target_spec[0] == 0x80 && target_spec[3] == 0x04 &&
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

    // run_bind end-to-end: rebind button 4 (currently the mock Back/rear-thumb
    // record) to "middle", so the written sector differs from the mock
    // sector at exactly that 4-byte record; build a matching readback buffer
    // for the post-write verification.
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
        fprintf(stderr, "run_bind self-test failed to build mock sector-read replies\n");
        return 1;
    }

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
    bind_replies[bind_reply_count++] = k_mock_get_info_reply;
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

    HidInterface bind_device_interface = {0};
    bind_device_interface.product_id = 0xC099;
    bind_device_interface.vendor_id = LOGITECH_VID;
    Device bind_device;
    memset(&bind_device, 0, sizeof(bind_device));
    bind_device.iface = &bind_device_interface;
    bind_device.device_number = 0xFF;
    bind_device.request_device_number = 0xFF;
    bind_device.protocol = 4.2;
    bind_device.feature_count = 2;
    bind_device.features[0] = (Feature){.id = FEATURE_ADJUSTABLE_DPI, .index = 3};
    bind_device.features[1] = (Feature){.id = FEATURE_ONBOARD_PROFILES, .index = 5};

    DiscoverDevicesTestContext bind_discovery_context = {
        .devices = &bind_device, .count = 1, .result = 1};
    discover_devices_for_options_impl = discover_devices_for_options_test_double;
    g_discover_devices_test_context = &bind_discovery_context;

    // Exercise run_dump through the same profile-I/O seam as bind. The
    // command creates its own HID context, so replace only that constructor
    // with an empty deterministic context for this command-level test.
    Reply dump_replies[40];
    size_t dump_reply_count = 0;
    dump_replies[dump_reply_count++] = k_mock_get_info_reply;
    for (size_t i = 0; i < control_chunk_count; i++) {
        dump_replies[dump_reply_count++] = control_chunks[i];
    }
    for (size_t i = 0; i < data_chunk_count; i++) {
        dump_replies[dump_reply_count++] = data_chunks[i];
    }
    ChannelRequestTestContext dump_channel_context = {.replies = dump_replies,
                                                      .reply_count = dump_reply_count};
    g_channel_request_test_context = &dump_channel_context;
    hid_context_create_impl = create_empty_hid_context_for_backup_bind;
    const char *dump_path = "/tmp/lomps-selftest-dump-success.logiob";
    unlink(dump_path);
    Options dump_success_options = {0};
    dump_success_options.device_index = -1;
    dump_success_options.profile = 1;
    dump_success_options.path = dump_path;
    bool dump_success_ok = run_dump(&dump_success_options) == 0 && access(dump_path, F_OK) == 0;
    unlink(dump_path);
    hid_context_create_impl = hid_context_create_hardware;
    if (!dump_success_ok) {
        fprintf(stderr, "run_dump seam self-test failed\n");
        return 1;
    }

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

    char default_bind_backup_path[512];
    default_backup_path(default_bind_backup_path, sizeof(default_bind_backup_path), "lomps-backup");
    unlink(default_bind_backup_path);
    bind_channel_context.calls = 0;
    Options bind_default_backup = bind_run_options;
    bind_default_backup.backup_path = NULL;
    if (run_bind(&bind_default_backup) != 0) {
        fprintf(stderr, "run_bind default-backup-path self-test failed\n");
        unlink(default_bind_backup_path);
        return 1;
    }
    unlink(default_bind_backup_path);

    uint8_t wrong_bind_readback[255];
    memcpy(wrong_bind_readback, bind_new_sector, sizeof(wrong_bind_readback));
    wrong_bind_readback[40] ^= 0x01;
    sector_put_crc(wrong_bind_readback, sizeof(wrong_bind_readback));
    Reply wrong_bind_chunks[32];
    size_t wrong_bind_chunk_count = build_sector_read_replies(
        wrong_bind_readback, sizeof(wrong_bind_readback), wrong_bind_chunks, 32);
    Reply bind_verify_failure_replies[160];
    size_t bind_verify_failure_count = 0;
    bind_verify_failure_count = append_replies(bind_verify_failure_replies, 0, bind_replies,
                                               1 + control_chunk_count + data_chunk_count + 1 + 18);
    for (size_t attempt = 0; attempt < 5; attempt++) {
        size_t next_count = append_replies(bind_verify_failure_replies, bind_verify_failure_count,
                                           wrong_bind_chunks, wrong_bind_chunk_count);
        if (next_count == 0) {
            fprintf(stderr, "run_bind self-test failed to build verification-failure replies\n");
            return 1;
        }
        bind_verify_failure_count = next_count;
    }
    ChannelRequestTestContext bind_verify_failure_context = {.replies = bind_verify_failure_replies,
                                                             .reply_count =
                                                                 bind_verify_failure_count,
                                                             .calls = 0};
    g_channel_request_test_context = &bind_verify_failure_context;
    const char *bind_verify_failure_path = "/tmp/lomps-selftest-bind-verify-failure.logiob";
    unlink(bind_verify_failure_path);
    Options bind_verify_failure = bind_run_options;
    bind_verify_failure.backup_path = bind_verify_failure_path;
    if (run_bind(&bind_verify_failure) != 1) {
        fprintf(stderr, "run_bind verification-failure self-test failed\n");
        unlink(bind_verify_failure_path);
        return 1;
    }
    unlink(bind_verify_failure_path);

    // Exercise the remaining command-level bind decisions with the same
    // deterministic profile, changing only the branch-specific input or
    // reply sequence.
    HidInterface branch_interface;
    Device branch_device = make_backup_bind_device(&branch_interface);
    DiscoverDevicesTestContext branch_discovery = {
        .devices = &branch_device, .count = 1, .result = 1};
    uint8_t branch_control[255];
    uint8_t branch_profile[255];
    build_mock_control_sector_two_profiles(branch_control);
    build_mock_onboard_sector(branch_profile);
    Reply branch_profile_replies[80];
    size_t branch_profile_reply_count =
        build_bind_profile_replies(branch_profile_replies, branch_control, branch_profile);
    if (branch_profile_reply_count == 0) {
        fprintf(stderr, "run_bind branch self-test failed to build profile replies\n");
        return 1;
    }
    ChannelRequestTestContext branch_profile_context = {.replies = branch_profile_replies,
                                                        .reply_count = branch_profile_reply_count};
    install_backup_bind_mocks(&branch_discovery);
    g_channel_request_test_context = &branch_profile_context;

    Options dump_context_failure = {.device_index = -1,
                                    .path = "/tmp/lomps-selftest-dump-context-failure.logiob"};
    hid_context_create_impl = create_failed_hid_context_for_backup_bind;
    if (run_dump(&dump_context_failure) != 1) {
        fprintf(stderr, "run_dump context-failure self-test failed\n");
        return 1;
    }
    hid_context_create_impl = create_empty_hid_context_for_backup_bind;

    Reply dump_load_failure_replies[1] = {k_mock_get_info_reply};
    ChannelRequestTestContext dump_load_failure_context = {
        .replies = dump_load_failure_replies, .reply_count = 1, .calls = 0};
    g_channel_request_test_context = &dump_load_failure_context;
    Options dump_load_failure = {
        .device_index = -1, .profile = 1, .path = "/tmp/lomps-selftest-dump-load-failure.logiob"};
    unlink(dump_load_failure.path);
    if (run_dump(&dump_load_failure) != 1) {
        fprintf(stderr, "run_dump profile-load-failure self-test failed\n");
        return 1;
    }

    HidInterface dump_g600_interface = {0};
    dump_g600_interface.vendor_id = LOGITECH_VID;
    dump_g600_interface.product_id = G600_PRODUCT_ID;
    Device dump_g600_device = {0};
    dump_g600_device.iface = &dump_g600_interface;
    DiscoverDevicesTestContext dump_g600_discovery = {
        .devices = &dump_g600_device, .count = 1, .result = 1};
    g_discover_devices_test_context = &dump_g600_discovery;
    g600_get_feature_report_impl = fail_g600_feature_report_for_backup_bind;
    Options dump_g600_options = {
        .device_index = -1, .profile = 1, .path = "/tmp/lomps-selftest-dump-g600.logiob"};
    unlink(dump_g600_options.path);
    if (run_dump(&dump_g600_options) != 1) {
        fprintf(stderr, "run_dump G600-dispatch self-test failed\n");
        return 1;
    }
    g600_get_feature_report_impl = channel_get_feature_report;
    g_discover_devices_test_context = &branch_discovery;

    Options implicit_profile = {0};
    implicit_profile.device_index = -1;
    implicit_profile.target = "middle";
    implicit_profile.button = 4;
    hid_context_create_impl = create_failed_hid_context_for_backup_bind;
    if (run_bind(&implicit_profile) != 1) {
        fprintf(stderr, "run_bind context-failure self-test failed\n");
        return 1;
    }
    hid_context_create_impl = create_empty_hid_context_for_backup_bind;
    if (run_bind(&implicit_profile) != 1) {
        fprintf(stderr, "run_bind implicit-profile refusal self-test failed\n");
        return 1;
    }

    dump_load_failure_context.calls = 0;
    g_channel_request_test_context = &dump_load_failure_context;
    Options bind_load_failure = implicit_profile;
    bind_load_failure.profile = 1;
    if (run_bind(&bind_load_failure) != 1) {
        fprintf(stderr, "run_bind profile-load-failure self-test failed\n");
        return 1;
    }

    uint8_t invalid_bind_profile[255];
    memcpy(invalid_bind_profile, branch_profile, sizeof(invalid_bind_profile));
    invalid_bind_profile[254] ^= 0xFF;
    Reply invalid_bind_replies[80];
    size_t invalid_bind_reply_count =
        build_bind_profile_replies(invalid_bind_replies, branch_control, invalid_bind_profile);
    ChannelRequestTestContext invalid_bind_context = {.replies = invalid_bind_replies,
                                                      .reply_count = invalid_bind_reply_count};
    g_channel_request_test_context = &invalid_bind_context;
    Options invalid_bind = implicit_profile;
    invalid_bind.profile = 1;
    if (run_bind(&invalid_bind) != 1) {
        fprintf(stderr, "run_bind invalid-profile self-test failed\n");
        return 1;
    }

    const char *dump_invalid_crc_path = "/tmp/lomps-selftest-dump-invalid-crc.logiob";
    unlink(dump_invalid_crc_path);
    Options dump_invalid_crc = {.device_index = -1, .profile = 1, .path = dump_invalid_crc_path};
    invalid_bind_context.calls = 0;
    if (run_dump(&dump_invalid_crc) != 0 || access(dump_invalid_crc_path, F_OK) != 0) {
        fprintf(stderr, "run_dump invalid-CRC self-test failed\n");
        unlink(dump_invalid_crc_path);
        return 1;
    }
    unlink(dump_invalid_crc_path);

    const char *dump_package_failure_path =
        "/no-such-lope-test-directory/dump-package-failure.logiob";
    branch_profile_context.calls = 0;
    g_channel_request_test_context = &branch_profile_context;
    Options dump_package_failure = {
        .device_index = -1, .profile = 1, .path = dump_package_failure_path};
    if (run_dump(&dump_package_failure) != 1) {
        fprintf(stderr, "run_dump package-write-failure self-test failed\n");
        return 1;
    }

    uint8_t no_rear_profile[255];
    memcpy(no_rear_profile, branch_profile, sizeof(no_rear_profile));
    no_rear_profile[32 + 3 * 4 + 0] = 0x80;
    no_rear_profile[32 + 3 * 4 + 1] = 0x01;
    no_rear_profile[32 + 3 * 4 + 2] = 0x00;
    no_rear_profile[32 + 3 * 4 + 3] = 0x02;
    sector_put_crc(no_rear_profile, sizeof(no_rear_profile));
    Reply no_rear_replies[80];
    size_t no_rear_reply_count =
        build_bind_profile_replies(no_rear_replies, branch_control, no_rear_profile);
    ChannelRequestTestContext no_rear_context = {.replies = no_rear_replies,
                                                 .reply_count = no_rear_reply_count};
    g_channel_request_test_context = &no_rear_context;
    Options auto_button = implicit_profile;
    auto_button.profile = 1;
    auto_button.button = 0;
    if (run_bind(&auto_button) != 1) {
        fprintf(stderr, "run_bind rear-thumb-not-found self-test failed\n");
        return 1;
    }

    g_channel_request_test_context = &branch_profile_context;
    Options out_of_range = implicit_profile;
    out_of_range.profile = 1;
    out_of_range.button = 6;
    branch_profile_context.calls = 0;
    g_channel_request_test_context = &branch_profile_context;
    if (run_bind(&out_of_range) != 1) {
        fprintf(stderr, "run_bind button-range self-test failed\n");
        return 1;
    }

    Options negative_button = implicit_profile;
    negative_button.profile = 1;
    negative_button.button = -1;
    branch_profile_context.calls = 0;
    g_channel_request_test_context = &branch_profile_context;
    if (run_bind(&negative_button) != 1) {
        fprintf(stderr, "run_bind negative-button self-test failed\n");
        return 1;
    }

    Options already_bound = implicit_profile;
    already_bound.profile = 1;
    already_bound.target = "back";
    branch_profile_context.calls = 0;
    g_channel_request_test_context = &branch_profile_context;
    if (run_bind(&already_bound) != 0) {
        fprintf(stderr, "run_bind no-op self-test failed\n");
        return 1;
    }

    Options bind_preview = implicit_profile;
    bind_preview.profile = 1;
    bind_preview.backup_path = "/tmp/lomps-selftest-bind-preview.logiob";
    branch_profile_context.calls = 0;
    g_channel_request_test_context = &branch_profile_context;
    if (run_bind(&bind_preview) != 0) {
        fprintf(stderr, "run_bind preview self-test failed\n");
        return 1;
    }

    Reply bind_mode_failure_replies[82];
    size_t bind_mode_failure_count = append_replies(
        bind_mode_failure_replies, 0, branch_profile_replies, branch_profile_reply_count);
    bind_mode_failure_replies[bind_mode_failure_count++] = k_mock_host_mode_reply;
    bind_mode_failure_replies[bind_mode_failure_count++] = (Reply){.status = REPLY_TIMEOUT};
    ChannelRequestTestContext bind_mode_failure_context = {.replies = bind_mode_failure_replies,
                                                           .reply_count = bind_mode_failure_count};
    g_channel_request_test_context = &bind_mode_failure_context;
    Options bind_mode_failure = bind_preview;
    bind_mode_failure.yes = true;
    if (run_bind(&bind_mode_failure) != 1) {
        fprintf(stderr, "run_bind mode-failure self-test failed\n");
        return 1;
    }

    Reply bind_package_failure_replies[82];
    size_t bind_package_failure_count = append_replies(
        bind_package_failure_replies, 0, branch_profile_replies, branch_profile_reply_count);
    bind_package_failure_replies[bind_package_failure_count++] = k_mock_onboard_mode_reply;
    ChannelRequestTestContext bind_package_failure_context = {
        .replies = bind_package_failure_replies, .reply_count = bind_package_failure_count};
    g_channel_request_test_context = &bind_package_failure_context;
    Options bind_package_failure = bind_preview;
    bind_package_failure.yes = true;
    bind_package_failure.backup_path = "/nonexistent-lope-test-directory/bind.logiob";
    if (run_bind(&bind_package_failure) != 1) {
        fprintf(stderr, "run_bind package-failure self-test failed\n");
        return 1;
    }

    Reply bind_write_failure_replies[82];
    size_t bind_write_failure_count = append_replies(
        bind_write_failure_replies, 0, branch_profile_replies, branch_profile_reply_count);
    bind_write_failure_replies[bind_write_failure_count++] = k_mock_onboard_mode_reply;
    bind_write_failure_replies[bind_write_failure_count++] = (Reply){.status = REPLY_TIMEOUT};
    ChannelRequestTestContext bind_write_failure_context = {
        .replies = bind_write_failure_replies, .reply_count = bind_write_failure_count};
    g_channel_request_test_context = &bind_write_failure_context;
    const char *bind_write_failure_path = "/tmp/lomps-selftest-bind-write-failure.logiob";
    unlink(bind_write_failure_path);
    Options bind_write_failure = bind_preview;
    bind_write_failure.yes = true;
    bind_write_failure.backup_path = bind_write_failure_path;
    if (run_bind(&bind_write_failure) != 1) {
        fprintf(stderr, "run_bind write-failure self-test failed\n");
        return 1;
    }
    unlink(bind_write_failure_path);

    // Restore uses a package read from disk, but all device interaction is
    // still driven by the shared HID++ reply seam. Cover validation, preview,
    // mode/write failures, readback failure, and a successful restore.
    uint8_t restore_current[255];
    memcpy(restore_current, branch_profile, sizeof(restore_current));
    restore_current[32] ^= 0x01;
    sector_put_crc(restore_current, sizeof(restore_current));
    const char *restore_path = "/tmp/lomps-selftest-restore.logiob";
    const char *restore_pre_path = "/tmp/lomps-selftest-restore.logiob.pre-restore.logiob";
    unlink(restore_pre_path);
    if (!write_restore_package(restore_path, &branch_device, 0x0123, 5, branch_profile,
                               sizeof(branch_profile))) {
        fprintf(stderr, "run_restore self-test failed to create package\n");
        return 1;
    }

    Reply restore_prefix[80];
    size_t restore_prefix_count =
        build_restore_profile_replies(restore_prefix, branch_control, restore_current);
    if (restore_prefix_count == 0) {
        fprintf(stderr, "run_restore self-test failed to build read replies\n");
        unlink(restore_path);
        return 1;
    }
    install_backup_bind_mocks(&branch_discovery);
    ChannelRequestTestContext restore_context = {.replies = restore_prefix,
                                                 .reply_count = restore_prefix_count};
    g_channel_request_test_context = &restore_context;
    Options backup_restore_options = {.device_index = -1, .path = restore_path};
    if (run_restore(&backup_restore_options) != 0) {
        fprintf(stderr, "run_restore preview self-test failed\n");
        unlink(restore_path);
        return 1;
    }

    Reply restore_no_change_prefix[80];
    size_t restore_no_change_count =
        build_restore_profile_replies(restore_no_change_prefix, branch_control, branch_profile);
    ChannelRequestTestContext restore_no_change_context = {.replies = restore_no_change_prefix,
                                                           .reply_count = restore_no_change_count};
    g_channel_request_test_context = &restore_no_change_context;
    if (run_restore(&backup_restore_options) != 0) {
        fprintf(stderr, "run_restore no-change self-test failed\n");
        unlink(restore_path);
        return 1;
    }

    Reply restore_mode_failure_replies[82];
    size_t restore_mode_failure_count =
        append_replies(restore_mode_failure_replies, 0, restore_prefix, restore_prefix_count);
    restore_mode_failure_replies[restore_mode_failure_count++] = k_mock_host_mode_reply;
    restore_mode_failure_replies[restore_mode_failure_count++] = (Reply){.status = REPLY_TIMEOUT};
    ChannelRequestTestContext restore_mode_failure_context = {
        .replies = restore_mode_failure_replies, .reply_count = restore_mode_failure_count};
    g_channel_request_test_context = &restore_mode_failure_context;
    backup_restore_options.yes = true;
    if (run_restore(&backup_restore_options) != 1) {
        fprintf(stderr, "run_restore mode-failure self-test failed\n");
        unlink(restore_path);
        return 1;
    }

    mkdir(restore_pre_path, 0700);
    Reply restore_preflight_failure_replies[82];
    size_t restore_preflight_failure_count =
        append_replies(restore_preflight_failure_replies, 0, restore_prefix, restore_prefix_count);
    restore_preflight_failure_replies[restore_preflight_failure_count++] =
        k_mock_onboard_mode_reply;
    ChannelRequestTestContext restore_preflight_failure_context = {
        .replies = restore_preflight_failure_replies,
        .reply_count = restore_preflight_failure_count};
    g_channel_request_test_context = &restore_preflight_failure_context;
    if (run_restore(&backup_restore_options) != 1) {
        fprintf(stderr, "run_restore pre-restore-failure self-test failed\n");
        rmdir(restore_pre_path);
        unlink(restore_path);
        return 1;
    }
    rmdir(restore_pre_path);

    Reply restore_write_failure_replies[82];
    size_t restore_write_failure_count =
        append_replies(restore_write_failure_replies, 0, restore_prefix, restore_prefix_count);
    restore_write_failure_replies[restore_write_failure_count++] = k_mock_onboard_mode_reply;
    for (size_t i = 0; i < 18; i++) {
        restore_write_failure_replies[restore_write_failure_count++] =
            i == 0 ? (Reply){.status = REPLY_TIMEOUT} : k_mock_generic_ok_reply;
    }
    ChannelRequestTestContext restore_write_failure_context = {
        .replies = restore_write_failure_replies, .reply_count = restore_write_failure_count};
    g_channel_request_test_context = &restore_write_failure_context;
    if (run_restore(&backup_restore_options) != 1) {
        fprintf(stderr, "run_restore write-failure self-test failed\n");
        unlink(restore_path);
        return 1;
    }
    unlink(restore_pre_path);

    uint8_t wrong_restore_profile[255];
    memcpy(wrong_restore_profile, restore_current, sizeof(wrong_restore_profile));
    wrong_restore_profile[33] ^= 0x01;
    sector_put_crc(wrong_restore_profile, sizeof(wrong_restore_profile));
    Reply restore_readback_failure_replies[180];
    size_t restore_readback_failure_count =
        append_replies(restore_readback_failure_replies, 0, restore_prefix, restore_prefix_count);
    restore_readback_failure_replies[restore_readback_failure_count++] = k_mock_onboard_mode_reply;
    for (size_t i = 0; i < 18; i++) {
        restore_readback_failure_replies[restore_readback_failure_count++] =
            k_mock_generic_ok_reply;
    }
    for (size_t attempt = 0; attempt < 5; attempt++) {
        size_t next =
            append_sector_replies(restore_readback_failure_replies, restore_readback_failure_count,
                                  wrong_restore_profile, sizeof(wrong_restore_profile));
        if (next == 0) {
            fprintf(stderr, "run_restore self-test failed to build readback replies\n");
            unlink(restore_path);
            return 1;
        }
        restore_readback_failure_count = next;
    }
    ChannelRequestTestContext restore_readback_failure_context = {
        .replies = restore_readback_failure_replies, .reply_count = restore_readback_failure_count};
    g_channel_request_test_context = &restore_readback_failure_context;
    if (run_restore(&backup_restore_options) != 1) {
        fprintf(stderr, "run_restore readback-failure self-test failed\n");
        unlink(restore_path);
        return 1;
    }
    unlink(restore_pre_path);

    Reply restore_success_replies[100];
    size_t restore_success_count =
        append_replies(restore_success_replies, 0, restore_prefix, restore_prefix_count);
    restore_success_replies[restore_success_count++] = k_mock_onboard_mode_reply;
    for (size_t i = 0; i < 18; i++) {
        restore_success_replies[restore_success_count++] = k_mock_generic_ok_reply;
    }
    size_t next = append_sector_replies(restore_success_replies, restore_success_count,
                                        branch_profile, sizeof(branch_profile));
    if (next == 0) {
        fprintf(stderr, "run_restore self-test failed to build success replies\n");
        unlink(restore_path);
        return 1;
    }
    restore_success_count = next;
    ChannelRequestTestContext restore_success_context = {.replies = restore_success_replies,
                                                         .reply_count = restore_success_count};
    g_channel_request_test_context = &restore_success_context;
    if (run_restore(&backup_restore_options) != 0) {
        fprintf(stderr, "run_restore success self-test failed\n");
        unlink(restore_path);
        unlink(restore_pre_path);
        return 1;
    }
    unlink(restore_path);
    unlink(restore_pre_path);

    // Additional restore guards use valid packages with deliberately narrow
    // reply streams so each command-level refusal is reached without any
    // production seam or hardware dependency.
    const char *restore_edge_path = "/tmp/lomps-selftest-restore-edge.logiob";
    unlink(restore_edge_path);
    if (!write_restore_package(restore_edge_path, &branch_device, 0x0123, 5, branch_profile,
                               sizeof(branch_profile))) {
        fprintf(stderr, "run_restore self-test failed to create edge-case package\n");
        return 1;
    }
    Options restore_edge_options = {.device_index = -1, .path = restore_edge_path, .yes = true};
    install_backup_bind_mocks(&branch_discovery);
    hid_context_create_impl = create_failed_hid_context_for_backup_bind;
    if (run_restore(&restore_edge_options) != 1) {
        fprintf(stderr, "run_restore context-failure self-test failed\n");
        unlink(restore_edge_path);
        return 1;
    }
    hid_context_create_impl = create_empty_hid_context_for_backup_bind;

    DiscoverDevicesTestContext restore_empty_discovery = {.devices = NULL, .count = 0, .result = 1};
    g_discover_devices_test_context = &restore_empty_discovery;
    if (run_restore(&restore_edge_options) != 1) {
        fprintf(stderr, "run_restore select-device-failure self-test failed\n");
        unlink(restore_edge_path);
        return 1;
    }
    g_discover_devices_test_context = &branch_discovery;

    HidInterface other_product_interface = branch_interface;
    other_product_interface.product_id = 0xC098;
    Device other_product_device = branch_device;
    other_product_device.iface = &other_product_interface;
    const char *restore_product_mismatch_path =
        "/tmp/lomps-selftest-restore-product-mismatch.logiob";
    unlink(restore_product_mismatch_path);
    if (!write_restore_package(restore_product_mismatch_path, &other_product_device, 0x0123, 5,
                               branch_profile, sizeof(branch_profile))) {
        fprintf(stderr, "run_restore self-test failed to create product-mismatch package\n");
        unlink(restore_edge_path);
        return 1;
    }
    Options restore_product_mismatch = {
        .device_index = -1, .path = restore_product_mismatch_path, .yes = true};
    if (run_restore(&restore_product_mismatch) != 1) {
        fprintf(stderr, "run_restore product-mismatch self-test failed\n");
        unlink(restore_product_mismatch_path);
        unlink(restore_edge_path);
        return 1;
    }
    unlink(restore_product_mismatch_path);

    HidInterface zero_product_interface = branch_interface;
    zero_product_interface.product_id = 0;
    Device zero_product_device = branch_device;
    zero_product_device.iface = &zero_product_interface;
    const char *restore_zero_product_path = "/tmp/lomps-selftest-restore-zero-product.logiob";
    unlink(restore_zero_product_path);
    if (!write_restore_package(restore_zero_product_path, &zero_product_device, 0x0123, 5,
                               branch_profile, sizeof(branch_profile))) {
        fprintf(stderr, "run_restore self-test failed to create zero-product package\n");
        unlink(restore_edge_path);
        return 1;
    }
    Options restore_zero_product = {
        .device_index = -1, .path = restore_zero_product_path, .yes = true};
    Reply restore_no_replies[1] = {{0}};
    ChannelRequestTestContext restore_no_reply_context = {
        .replies = restore_no_replies, .reply_count = 0, .calls = 0};
    g_channel_request_test_context = &restore_no_reply_context;
    if (run_restore(&restore_zero_product) != 1) {
        fprintf(stderr, "run_restore zero-product self-test failed\n");
        unlink(restore_zero_product_path);
        unlink(restore_edge_path);
        return 1;
    }
    unlink(restore_zero_product_path);

    Reply restore_info_only_replies[1] = {k_mock_get_info_reply};
    ChannelRequestTestContext restore_info_only_context = {
        .replies = restore_info_only_replies, .reply_count = 1, .calls = 0};
    g_channel_request_test_context = &restore_info_only_context;
    uint8_t short_restore_data[254];
    memcpy(short_restore_data, branch_profile, sizeof(short_restore_data));
    const char *restore_size_mismatch_path = "/tmp/lomps-selftest-restore-size-mismatch.logiob";
    unlink(restore_size_mismatch_path);
    if (!write_restore_package(restore_size_mismatch_path, &branch_device, 0x0123, 5,
                               short_restore_data, sizeof(short_restore_data))) {
        fprintf(stderr, "run_restore self-test failed to create size-mismatch package\n");
        unlink(restore_edge_path);
        return 1;
    }
    Options restore_size_mismatch = {
        .device_index = -1, .path = restore_size_mismatch_path, .yes = true};
    if (run_restore(&restore_size_mismatch) != 1) {
        fprintf(stderr, "run_restore size-mismatch self-test failed\n");
        unlink(restore_size_mismatch_path);
        unlink(restore_edge_path);
        return 1;
    }
    unlink(restore_size_mismatch_path);

    const char *restore_format_mismatch_path = "/tmp/lomps-selftest-restore-format-mismatch.logiob";
    unlink(restore_format_mismatch_path);
    if (!write_restore_package(restore_format_mismatch_path, &branch_device, 0x0123, 4,
                               branch_profile, sizeof(branch_profile))) {
        fprintf(stderr, "run_restore self-test failed to create format-mismatch package\n");
        unlink(restore_edge_path);
        return 1;
    }
    Options restore_format_mismatch = {
        .device_index = -1, .path = restore_format_mismatch_path, .yes = true};
    restore_info_only_context.calls = 0;
    if (run_restore(&restore_format_mismatch) != 1) {
        fprintf(stderr, "run_restore format-mismatch self-test failed\n");
        unlink(restore_format_mismatch_path);
        unlink(restore_edge_path);
        return 1;
    }
    unlink(restore_format_mismatch_path);

    g_channel_request_test_context = &restore_info_only_context;
    restore_info_only_context.calls = 0;
    if (run_restore(&restore_edge_options) != 1) {
        fprintf(stderr, "run_restore control-read-failure self-test failed\n");
        unlink(restore_edge_path);
        return 1;
    }

    const char *restore_no_headers_path = "/tmp/lomps-selftest-restore-control-sector.logiob";
    unlink(restore_no_headers_path);
    if (!write_restore_package(restore_no_headers_path, &branch_device, 0, 5, branch_control,
                               sizeof(branch_control))) {
        fprintf(stderr, "run_restore self-test failed to create control-sector package\n");
        unlink(restore_edge_path);
        return 1;
    }
    Reply restore_control_match_replies[80];
    size_t restore_control_match_count = build_restore_profile_replies(
        restore_control_match_replies, branch_control, branch_control);
    ChannelRequestTestContext restore_control_match_context = {
        .replies = restore_control_match_replies,
        .reply_count = restore_control_match_count,
        .calls = 0};
    g_channel_request_test_context = &restore_control_match_context;
    Options restore_no_headers = {.device_index = -1, .path = restore_no_headers_path};
    if (run_restore(&restore_no_headers) != 0) {
        fprintf(stderr, "run_restore control-sector self-test failed\n");
        unlink(restore_no_headers_path);
        unlink(restore_edge_path);
        return 1;
    }
    unlink(restore_no_headers_path);

    uint8_t invalid_restore_control[255];
    memcpy(invalid_restore_control, branch_control, sizeof(invalid_restore_control));
    invalid_restore_control[254] ^= 0x01;
    Reply restore_invalid_control_replies[80];
    size_t restore_invalid_control_count = build_restore_profile_replies(
        restore_invalid_control_replies, invalid_restore_control, branch_profile);
    ChannelRequestTestContext restore_invalid_control_context = {
        .replies = restore_invalid_control_replies,
        .reply_count = restore_invalid_control_count,
        .calls = 0};
    g_channel_request_test_context = &restore_invalid_control_context;
    if (run_restore(&restore_edge_options) != 1) {
        fprintf(stderr, "run_restore invalid-control-CRC self-test failed\n");
        unlink(restore_edge_path);
        return 1;
    }

    uint8_t empty_restore_control[255] = {0};
    empty_restore_control[3] = 1;
    sector_put_crc(empty_restore_control, sizeof(empty_restore_control));
    Reply restore_empty_control_replies[80];
    size_t restore_empty_control_count = build_restore_profile_replies(
        restore_empty_control_replies, empty_restore_control, branch_profile);
    ChannelRequestTestContext restore_empty_control_context = {
        .replies = restore_empty_control_replies,
        .reply_count = restore_empty_control_count,
        .calls = 0};
    g_channel_request_test_context = &restore_empty_control_context;
    if (run_restore(&restore_edge_options) != 1) {
        fprintf(stderr, "run_restore empty-control self-test failed\n");
        unlink(restore_edge_path);
        return 1;
    }

    const char *restore_unknown_sector_path = "/tmp/lomps-selftest-restore-unknown-sector.logiob";
    unlink(restore_unknown_sector_path);
    if (!write_restore_package(restore_unknown_sector_path, &branch_device, 0x0999, 5,
                               branch_profile, sizeof(branch_profile))) {
        fprintf(stderr, "run_restore self-test failed to create unknown-sector package\n");
        unlink(restore_edge_path);
        return 1;
    }
    Reply restore_headers_only_replies[40];
    size_t restore_headers_only_count = 0;
    restore_headers_only_replies[restore_headers_only_count++] = k_mock_get_info_reply;
    restore_headers_only_count =
        append_sector_replies(restore_headers_only_replies, restore_headers_only_count,
                              branch_control, sizeof(branch_control));
    ChannelRequestTestContext restore_headers_only_context = {
        .replies = restore_headers_only_replies,
        .reply_count = restore_headers_only_count,
        .calls = 0};
    g_channel_request_test_context = &restore_headers_only_context;
    Options restore_unknown_sector = {
        .device_index = -1, .path = restore_unknown_sector_path, .yes = true};
    if (run_restore(&restore_unknown_sector) != 1) {
        fprintf(stderr, "run_restore unknown-sector self-test failed\n");
        unlink(restore_unknown_sector_path);
        unlink(restore_edge_path);
        return 1;
    }
    unlink(restore_unknown_sector_path);

    const char *restore_second_header_path = "/tmp/lomps-selftest-restore-second-header.logiob";
    unlink(restore_second_header_path);
    if (!write_restore_package(restore_second_header_path, &branch_device, 0x0200, 5,
                               branch_profile, sizeof(branch_profile))) {
        fprintf(stderr, "run_restore self-test failed to create second-header package\n");
        unlink(restore_edge_path);
        return 1;
    }
    Reply restore_second_header_replies[80];
    size_t restore_second_header_count = build_restore_profile_replies(
        restore_second_header_replies, branch_control, branch_profile);
    ChannelRequestTestContext restore_second_header_context = {
        .replies = restore_second_header_replies,
        .reply_count = restore_second_header_count,
        .calls = 0};
    g_channel_request_test_context = &restore_second_header_context;
    Options restore_second_header = {.device_index = -1, .path = restore_second_header_path};
    if (run_restore(&restore_second_header) != 0) {
        fprintf(stderr, "run_restore second-header self-test failed\n");
        unlink(restore_second_header_path);
        unlink(restore_edge_path);
        return 1;
    }
    unlink(restore_second_header_path);

    Reply restore_current_read_fail_replies[40];
    size_t restore_current_read_fail_count = 0;
    restore_current_read_fail_replies[restore_current_read_fail_count++] = k_mock_get_info_reply;
    restore_current_read_fail_count =
        append_sector_replies(restore_current_read_fail_replies, restore_current_read_fail_count,
                              branch_control, sizeof(branch_control));
    ChannelRequestTestContext restore_current_read_fail_context = {
        .replies = restore_current_read_fail_replies,
        .reply_count = restore_current_read_fail_count,
        .calls = 0};
    g_channel_request_test_context = &restore_current_read_fail_context;
    if (run_restore(&restore_edge_options) != 1) {
        fprintf(stderr, "run_restore current-read-failure self-test failed\n");
        unlink(restore_edge_path);
        return 1;
    }

    uint8_t invalid_current_restore[255];
    memcpy(invalid_current_restore, branch_profile, sizeof(invalid_current_restore));
    invalid_current_restore[32] ^= 0x01;
    Reply restore_invalid_current_replies[80];
    size_t restore_invalid_current_count = build_restore_profile_replies(
        restore_invalid_current_replies, branch_control, invalid_current_restore);
    ChannelRequestTestContext restore_invalid_current_context = {
        .replies = restore_invalid_current_replies,
        .reply_count = restore_invalid_current_count,
        .calls = 0};
    g_channel_request_test_context = &restore_invalid_current_context;
    Options restore_invalid_current = {.device_index = -1, .path = restore_edge_path};
    if (run_restore(&restore_invalid_current) != 0) {
        fprintf(stderr, "run_restore invalid-current-CRC self-test failed\n");
        unlink(restore_edge_path);
        return 1;
    }

    HidInterface restore_g600_interface = {0};
    restore_g600_interface.vendor_id = LOGITECH_VID;
    restore_g600_interface.product_id = G600_PRODUCT_ID;
    Device restore_g600_device = {0};
    restore_g600_device.iface = &restore_g600_interface;
    uint8_t restore_g600_data[G600_REPORT_BYTES] = {0};
    restore_g600_data[0] = G600_FIRST_PROFILE_REPORT;
    const char *restore_g600_path = "/tmp/lomps-selftest-restore-g600-dispatch.logiob";
    unlink(restore_g600_path);
    if (!write_restore_package(restore_g600_path, &restore_g600_device, G600_FIRST_PROFILE_REPORT,
                               G600_BACKUP_PROFILE_FORMAT, restore_g600_data,
                               sizeof(restore_g600_data))) {
        fprintf(stderr, "run_restore self-test failed to create G600 package\n");
        unlink(restore_edge_path);
        return 1;
    }
    DiscoverDevicesTestContext restore_g600_discovery = {
        .devices = &restore_g600_device, .count = 1, .result = 1};
    g_discover_devices_test_context = &restore_g600_discovery;
    g600_get_feature_report_impl = fail_g600_feature_report_for_backup_bind;
    Options restore_g600_options = {.device_index = -1, .path = restore_g600_path, .yes = true};
    if (run_restore(&restore_g600_options) != 1) {
        fprintf(stderr, "run_restore G600-dispatch self-test failed\n");
        g600_get_feature_report_impl = channel_get_feature_report;
        unlink(restore_g600_path);
        unlink(restore_edge_path);
        return 1;
    }
    g600_get_feature_report_impl = channel_get_feature_report;
    unlink(restore_g600_path);
    unlink(restore_edge_path);

    hid_context_create_impl = hid_context_create_hardware;

    return 0;
}
