#include "internal.h"
#include "test_doubles.h"

int test_commands_backup_bind(void) {
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
        parse_target("alt-tab", target_spec) && target_spec[0] == 0x80 && target_spec[1] == 0x02 &&
        target_spec[2] == 0x04 && target_spec[3] == 0x2B && parse_target("dpi-up", target_spec) &&
        target_spec[1] == 0x03 && parse_target("previous-dpi", target_spec) &&
        target_spec[1] == 0x04 && parse_target("dpi-cycle", target_spec) &&
        target_spec[1] == 0x05 && parse_target("dpi-default", target_spec) &&
        target_spec[1] == 0x06 && parse_target("dpi-shift", target_spec) &&
        target_spec[1] == 0x07 && parse_target("next-profile", target_spec) &&
        target_spec[1] == 0x08 && parse_target("previous-profile", target_spec) &&
        target_spec[1] == 0x09 && parse_target("cycle-profile", target_spec) &&
        target_spec[1] == 0x0A && parse_target("g-shift", target_spec) && target_spec[1] == 0x0B &&
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

    return 0;
}
