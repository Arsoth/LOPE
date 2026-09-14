#include "commands_read.h"
#include "g600.h"
#include "profile_io.h"
#include "test_doubles.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int create_empty_hid_context(HidContext *context) {
    memset(context, 0, sizeof(*context));
    return 1;
}

static int create_failed_hid_context(HidContext *context) {
    (void)context;
    return 0;
}

static bool read_g600_get_feature_report_failure(HidChannel *channel, uint8_t report_id,
                                                 uint8_t *report, size_t capacity, size_t *length) {
    (void)channel;
    (void)report_id;
    (void)report;
    (void)capacity;
    (void)length;
    return false;
}

static size_t append_read_replies(Reply *out, size_t offset, const Reply *replies, size_t count) {
    memcpy(out + offset, replies, count * sizeof(*replies));
    return offset + count;
}

static HidContext *list_context_template;
static const Device *list_devices_template;
static size_t list_device_count_template;

static int create_list_hid_context(HidContext *context) {
    memset(context, 0, sizeof(*context));
    if (list_context_template == NULL || list_context_template->count == 0) {
        return 1;
    }
    context->items = (HidInterface *)malloc(list_context_template->count * sizeof(HidInterface));
    if (context->items == NULL) {
        return 0;
    }
    memcpy(context->items, list_context_template->items,
           list_context_template->count * sizeof(HidInterface));
    context->count = list_context_template->count;
    return 1;
}

static int discover_devices_for_list_test(HidContext *context, int requested_slot, Device *devices,
                                          size_t *count, bool inspect_features) {
    (void)context;
    (void)requested_slot;
    (void)inspect_features;
    *count = list_device_count_template;
    memcpy(devices, list_devices_template, *count * sizeof(Device));
    return 1;
}

int test_commands_read(void) {
    uint16_t parsed_dpi[5] = {0};
    size_t parsed_dpi_count = 0;
    bool dpi_parser_ok =
        parse_dpi_values("800,1600", parsed_dpi, &parsed_dpi_count) && parsed_dpi_count == 2 &&
        parsed_dpi[0] == 800 && parsed_dpi[1] == 1600 &&
        !parse_dpi_values("800,1200,1600,2400,3200,6400", parsed_dpi, &parsed_dpi_count) &&
        parse_dpi_values("800, 1600,2400,3200,6400", parsed_dpi, NULL) &&
        !parse_dpi_values(NULL, parsed_dpi, &parsed_dpi_count) &&
        !parse_dpi_values("", parsed_dpi, &parsed_dpi_count) &&
        !parse_dpi_values("99,1600", parsed_dpi, &parsed_dpi_count) &&
        !parse_dpi_values("800,65536", parsed_dpi, &parsed_dpi_count) &&
        !parse_dpi_values("800x", parsed_dpi, &parsed_dpi_count) &&
        !parse_dpi_values("abc,1600", parsed_dpi, &parsed_dpi_count) &&
        !parse_dpi_values("999999999999999999999999999999,1600", parsed_dpi, &parsed_dpi_count) &&
        parse_dpi_values("800 ,1600", parsed_dpi, &parsed_dpi_count);
    if (!dpi_parser_ok) {
        fprintf(stderr, "DPI parser self-test failed\n");
        return 1;
    }
    char oversized_dpi_text[257];
    memset(oversized_dpi_text, '1', sizeof(oversized_dpi_text) - 1);
    oversized_dpi_text[sizeof(oversized_dpi_text) - 1] = '\0';
    if (parse_dpi_values(oversized_dpi_text, parsed_dpi, &parsed_dpi_count)) {
        fprintf(stderr, "DPI parser oversized-input self-test failed\n");
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

    Device receiver_fallback_device = {0};
    receiver_fallback_device.device_number = 1;
    receiver_fallback_device.protocol = 1.0;
    receiver_fallback_device.iface = &select_interface_b;
    select_options.device_index = -1;
    select_options.device_key = NULL;
    select_device_ok = select_device_ok &&
                       select_device(&receiver_fallback_device, 1, &select_options, &selected) &&
                       selected == &receiver_fallback_device;
    if (!select_device_ok) {
        fprintf(stderr, "select_device self-test failed\n");
        return 1;
    }

    HidInterface list_interface = {0};
    list_interface.vendor_id = LOGITECH_VID;
    list_interface.product_id = 0xC099;
    list_interface.is_vendor = true;
    list_interface.is_mouse = true;
    snprintf(list_interface.product, sizeof(list_interface.product), "Coverage Mouse");
    Device list_device = {0};
    list_device.iface = &list_interface;
    list_device.device_number = 0xFF;
    list_device.request_device_number = 0xFF;
    list_device.protocol = 2.0;
    snprintf(list_device.name, sizeof(list_device.name), "Coverage Mouse");
    HidInterface list_items[1] = {list_interface};
    HidContext list_template = {.items = list_items, .count = 1};
    list_context_template = &list_template;
    list_devices_template = &list_device;
    list_device_count_template = 1;
    discover_devices_for_list_impl = discover_devices_for_list_test;
    hid_context_create_impl = create_list_hid_context;
    Options context_failure_options = {0};
    context_failure_options.device_index = -1;
    hid_context_create_impl = create_failed_hid_context;
    if (run_list() != 1 || run_info(&context_failure_options) != 1 ||
        run_profiles(&context_failure_options) != 1 || run_dpi(&context_failure_options) != 1 ||
        run_current_dpi(&context_failure_options) != 1) {
        fprintf(stderr, "read command context-failure self-test failed\n");
        return 1;
    }
    hid_context_create_impl = create_list_hid_context;
    if (run_list() != 0) {
        fprintf(stderr, "run_list populated-device self-test failed\n");
        return 1;
    }
    list_device_count_template = 0;
    if (run_list() != 0) {
        fprintf(stderr, "run_list empty-device self-test failed\n");
        return 1;
    }

    // Keep one non-mouse device and one direct wireless endpoint paired with
    // a receiver slot. Both should be suppressed by list rendering.
    HidInterface list_keyboard_interface = {0};
    list_keyboard_interface.vendor_id = LOGITECH_VID;
    snprintf(list_keyboard_interface.product, sizeof(list_keyboard_interface.product),
             "Coverage Keyboard");
    HidInterface list_receiver_interface = {0};
    list_receiver_interface.vendor_id = LOGITECH_VID;
    list_receiver_interface.product_id = 0xC539;
    snprintf(list_receiver_interface.product, sizeof(list_receiver_interface.product), "Receiver");
    HidInterface list_duplicate_interface = {0};
    list_duplicate_interface.vendor_id = LOGITECH_VID;
    list_duplicate_interface.product_id = 0x4085;
    list_duplicate_interface.is_mouse = true;
    snprintf(list_duplicate_interface.product, sizeof(list_duplicate_interface.product),
             "Duplicate Mouse");
    HidInterface list_branch_items[3] = {list_keyboard_interface, list_receiver_interface,
                                         list_duplicate_interface};
    list_branch_items[0].is_vendor = false;
    Device list_branch_devices[3] = {0};
    list_branch_devices[0].iface = &list_keyboard_interface;
    list_branch_devices[1].iface = &list_receiver_interface;
    list_branch_devices[1].device_number = 1;
    snprintf(list_branch_devices[1].name, sizeof(list_branch_devices[1].name), "Duplicate Mouse");
    list_branch_devices[2].iface = &list_duplicate_interface;
    list_branch_devices[2].device_number = 0xFF;
    list_branch_devices[2].request_device_number = 0xFF;
    snprintf(list_branch_devices[2].name, sizeof(list_branch_devices[2].name), "Duplicate Mouse");
    HidContext list_branch_template = {.items = list_branch_items, .count = 3};
    list_context_template = &list_branch_template;
    list_devices_template = list_branch_devices;
    list_device_count_template = 3;
    if (run_list() != 0) {
        fprintf(stderr, "run_list filtered-device self-test failed\n");
        return 1;
    }
    list_context_template = &list_template;
    list_devices_template = &list_device;
    list_device_count_template = 1;
    discover_devices_for_list_impl = discover_devices;

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

    // The command layer also owns the legacy G600 dispatch. Use its feature
    // report seam so both read commands can reach that branch without live
    // hardware.
    HidInterface read_g600_interface = {0};
    read_g600_interface.vendor_id = LOGITECH_VID;
    read_g600_interface.product_id = G600_PRODUCT_ID;
    Device read_g600_device = {0};
    read_g600_device.iface = &read_g600_interface;
    read_g600_device.device_number = 0xFF;
    read_g600_device.request_device_number = 0xFF;
    read_g600_device.protocol = 1.0;
    DiscoverDevicesTestContext read_g600_discovery = {
        .devices = &read_g600_device, .count = 1, .result = 1};
    g_discover_devices_test_context = &read_g600_discovery;
    g600_get_feature_report_impl = read_g600_get_feature_report_failure;
    Options read_g600_options = {.device_index = -1, .profile = 1};
    Options read_g600_headers_options = read_g600_options;
    read_g600_headers_options.headers_only = true;
    if (run_info(&read_g600_options) != 1 || run_profiles(&read_g600_headers_options) != 0) {
        fprintf(stderr, "command G600 dispatch self-test failed\n");
        return 1;
    }
    g600_get_feature_report_impl = channel_get_feature_report;

    // A selected non-G600 device that advertises onboard profiles but cannot
    // answer getInfo reaches run_info's second half of the OR condition.
    HidInterface read_info_failure_interface = {0};
    read_info_failure_interface.vendor_id = LOGITECH_VID;
    read_info_failure_interface.product_id = 0xC099;
    Device read_info_failure_device = {0};
    read_info_failure_device.iface = &read_info_failure_interface;
    read_info_failure_device.device_number = 0xFF;
    read_info_failure_device.request_device_number = 0xFF;
    read_info_failure_device.protocol = 4.2;
    read_info_failure_device.feature_count = 1;
    read_info_failure_device.features[0] = (Feature){.id = FEATURE_ONBOARD_PROFILES, .index = 5};
    DiscoverDevicesTestContext read_info_failure_discovery = {
        .devices = &read_info_failure_device, .count = 1, .result = 1};
    g_discover_devices_test_context = &read_info_failure_discovery;
    ChannelRequestTestContext read_info_failure_channel = {.replies = NULL, .reply_count = 0};
    g_channel_request_test_context = &read_info_failure_channel;
    Options read_info_failure_options = {.device_index = -1, .profile = 1};
    if (run_info(&read_info_failure_options) != 0) {
        fprintf(stderr, "command run_info getInfo-failure self-test failed\n");
        return 1;
    }

    // A paired endpoint (non-FF device number) reports a receiver-backed
    // connection even when its profile feature list is unavailable.
    HidInterface read_receiver_style_interface = {0};
    read_receiver_style_interface.vendor_id = LOGITECH_VID;
    read_receiver_style_interface.product_id = 0xC099;
    snprintf(read_receiver_style_interface.product, sizeof(read_receiver_style_interface.product),
             "Paired Mouse");
    Device read_receiver_style_device = {0};
    read_receiver_style_device.iface = &read_receiver_style_interface;
    read_receiver_style_device.device_number = 1;
    read_receiver_style_device.request_device_number = 0xFF;
    read_receiver_style_device.protocol = 2.0;
    DiscoverDevicesTestContext read_receiver_style_discovery = {
        .devices = &read_receiver_style_device, .count = 1, .result = 1};
    g_discover_devices_test_context = &read_receiver_style_discovery;
    if (run_info(&read_info_failure_options) != 0) {
        fprintf(stderr, "command run_info receiver-connection self-test failed\n");
        return 1;
    }

    // The command entry points own context creation, so inject an empty
    // context here while the discovery and HID++ seams provide the selected
    // device and deterministic profile replies. This covers the normal read
    // command flow without depending on a physical HID device.
    hid_context_create_impl = create_empty_hid_context;
    HidInterface read_interface = {0};
    read_interface.vendor_id = LOGITECH_VID;
    read_interface.product_id = 0xC099;
    Device read_device = {0};
    read_device.iface = &read_interface;
    read_device.device_number = 0xFF;
    read_device.request_device_number = 0xFF;
    read_device.protocol = 4.2;
    read_device.feature_count = 2;
    read_device.features[0] = (Feature){.id = FEATURE_ONBOARD_PROFILES, .index = 5};
    read_device.features[1] = (Feature){.id = FEATURE_ADJUSTABLE_DPI, .index = 3};
    read_device.features[2] = (Feature){.id = FEATURE_EXTENDED_REPORT_RATE, .index = 7};
    read_device.feature_count = 3;
    DiscoverDevicesTestContext read_discovery = {.devices = &read_device, .count = 1, .result = 1};
    g_discover_devices_test_context = &read_discovery;

    uint8_t read_control[255];
    uint8_t read_profile[255];
    build_mock_control_sector_two_profiles(read_control);
    build_mock_onboard_sector(read_profile);
    Reply read_control_chunks[32];
    Reply read_profile_chunks[32];
    size_t read_control_count =
        build_sector_read_replies(read_control, MAX_HEADERS * 4 + 4, read_control_chunks, 32);
    size_t read_profile_count =
        build_sector_read_replies(read_profile, sizeof(read_profile), read_profile_chunks, 32);
    Reply read_sensor_count = {.status = REPLY_OK, .length = 1, .bytes = {1}};
    Reply read_sensor_list = {
        .status = REPLY_OK,
        .length = 11,
        .bytes = {0x00, 0x03, 0x20, 0x04, 0xB0, 0x06, 0x40, 0x09, 0x60, 0x0C, 0x80}};
    Reply read_sensor_current = {.status = REPLY_OK, .length = 3, .bytes = {0, 0x06, 0x40}};
    Reply read_current_dpi = {.status = REPLY_OK, .length = 3, .bytes = {0, 0x06, 0x40}};

    Reply read_info_replies[64];
    size_t read_info_reply_count = 0;
    read_info_replies[read_info_reply_count++] = k_mock_get_info_reply;
    for (size_t i = 0; i < read_control_count; i++) {
        read_info_replies[read_info_reply_count++] = read_control_chunks[i];
    }
    for (size_t i = 0; i < read_profile_count; i++) {
        read_info_replies[read_info_reply_count++] = read_profile_chunks[i];
    }
    ChannelRequestTestContext read_info_context = {.replies = read_info_replies,
                                                   .reply_count = read_info_reply_count};
    g_channel_request_test_context = &read_info_context;

    // Exercise the readable-device error branches independently of the full
    // command flow below: a valid feature descriptor followed by an
    // unavailable control/profile sector must be reported without crashing.
    Reply read_info_only_reply = k_mock_get_info_reply;
    ChannelRequestTestContext read_info_header_failure_context = {
        .replies = &read_info_only_reply, .reply_count = 1, .calls = 0};
    g_channel_request_test_context = &read_info_header_failure_context;
    Options read_failure_options = {.device_index = -1, .profile = 1};
    if (run_info(&read_failure_options) != 0 || run_profiles(&read_failure_options) != 1) {
        fprintf(stderr, "command read header-failure self-test failed\n");
        return 1;
    }

    Reply read_info_profile_failure_replies[32];
    size_t read_info_profile_failure_count = 0;
    read_info_profile_failure_replies[read_info_profile_failure_count++] = k_mock_get_info_reply;
    for (size_t i = 0; i < read_control_count; i++) {
        read_info_profile_failure_replies[read_info_profile_failure_count++] =
            read_control_chunks[i];
    }
    ChannelRequestTestContext read_info_profile_failure_context = {
        .replies = read_info_profile_failure_replies,
        .reply_count = read_info_profile_failure_count,
        .calls = 0};
    g_channel_request_test_context = &read_info_profile_failure_context;
    if (run_info(&read_failure_options) != 0) {
        fprintf(stderr, "command read profile-failure self-test failed\n");
        return 1;
    }

    Reply read_profiles_header_failure_replies[2] = {k_mock_get_info_reply,
                                                     (Reply){.status = REPLY_TIMEOUT}};
    ChannelRequestTestContext read_profiles_header_failure_context = {
        .replies = read_profiles_header_failure_replies, .reply_count = 2, .calls = 0};
    g_channel_request_test_context = &read_profiles_header_failure_context;
    if (run_profiles(&read_failure_options) != 1) {
        fprintf(stderr, "command run_profiles header-failure self-test failed\n");
        return 1;
    }

    Reply read_profile_list_replies[80];
    size_t read_profile_list_count = 0;
    read_profile_list_replies[read_profile_list_count++] = k_mock_get_info_reply;
    for (size_t i = 0; i < read_control_count; i++) {
        read_profile_list_replies[read_profile_list_count++] = read_control_chunks[i];
    }
    for (size_t profile = 0; profile < 2; profile++) {
        for (size_t i = 0; i < read_profile_count; i++) {
            read_profile_list_replies[read_profile_list_count++] = read_profile_chunks[i];
        }
    }
    ChannelRequestTestContext read_profile_list_context = {
        .replies = read_profile_list_replies, .reply_count = read_profile_list_count, .calls = 0};
    g_channel_request_test_context = &read_profile_list_context;
    Options read_all_profiles_options = {.device_index = -1, .profile = 0};
    if (run_profiles(&read_all_profiles_options) != 0) {
        fprintf(stderr, "command read all-profiles self-test failed\n");
        return 1;
    }

    ChannelRequestTestContext read_summary_context = {
        .replies = read_info_replies, .reply_count = read_info_reply_count, .calls = 0};
    g_channel_request_test_context = &read_summary_context;
    Options read_summary_options = {.device_index = -1, .profile = 1, .summary_only = true};
    if (run_profiles(&read_summary_options) != 0) {
        fprintf(stderr, "command read summary-profile self-test failed\n");
        return 1;
    }

    ChannelRequestTestContext read_profile_range_context = {
        .replies = read_info_replies, .reply_count = read_info_reply_count, .calls = 0};
    g_channel_request_test_context = &read_profile_range_context;
    Options read_profile_range_options = {.device_index = -1, .profile = 3};
    if (run_profiles(&read_profile_range_options) != 1) {
        fprintf(stderr, "command read profile-range self-test failed\n");
        return 1;
    }
    g_channel_request_test_context = &read_info_context;

    Options read_info_options = {0};
    read_info_options.device_index = -1;
    read_info_options.profile = 1;
    bool read_commands_ok = run_info(&read_info_options) == 0 && read_info_context.calls == 26;

    Reply read_headers_replies[32];
    size_t read_headers_reply_count = 0;
    read_headers_replies[read_headers_reply_count++] = k_mock_get_info_reply;
    for (size_t i = 0; i < read_control_count; i++) {
        read_headers_replies[read_headers_reply_count++] = read_control_chunks[i];
    }
    ChannelRequestTestContext read_headers_context = {.replies = read_headers_replies,
                                                      .reply_count = read_headers_reply_count};
    g_channel_request_test_context = &read_headers_context;
    Options read_headers_options = read_info_options;
    read_headers_options.headers_only = true;
    read_commands_ok = read_commands_ok && run_profiles(&read_headers_options) == 0 &&
                       read_headers_context.calls == 10;

    Reply read_profiles_replies[80];
    size_t read_profiles_reply_count = 0;
    read_profiles_replies[read_profiles_reply_count++] = k_mock_get_info_reply;
    for (size_t i = 0; i < read_control_count; i++) {
        read_profiles_replies[read_profiles_reply_count++] = read_control_chunks[i];
    }
    for (size_t i = 0; i < read_profile_count; i++) {
        read_profiles_replies[read_profiles_reply_count++] = read_profile_chunks[i];
    }
    read_profiles_replies[read_profiles_reply_count++] = read_sensor_count;
    read_profiles_replies[read_profiles_reply_count++] = read_sensor_list;
    read_profiles_replies[read_profiles_reply_count++] = read_sensor_current;
    ChannelRequestTestContext read_profiles_context = {.replies = read_profiles_replies,
                                                       .reply_count = read_profiles_reply_count};
    g_channel_request_test_context = &read_profiles_context;
    Options read_detailed_options = read_info_options;
    read_detailed_options.include_dpi = true;
    read_detailed_options.summary_only = true;
    read_commands_ok = read_commands_ok && run_profiles(&read_detailed_options) == 0;

    // The explicit DPI details path also supports a full profile-sector
    // read, not only the GUI summary prefix.
    ChannelRequestTestContext read_full_dpi_context = {
        .replies = read_profiles_replies, .reply_count = read_profiles_reply_count, .calls = 0};
    g_channel_request_test_context = &read_full_dpi_context;
    Options read_full_dpi_options = read_info_options;
    read_full_dpi_options.include_dpi = true;
    read_full_dpi_options.summary_only = false;
    read_commands_ok = read_commands_ok && run_profiles(&read_full_dpi_options) == 0;

    // A selected-profile read can fail while the live adjustable-DPI
    // capability remains readable; the command should still print its
    // sensor summary and take the selected-stage-empty branch.
    Reply read_profile_load_failure_replies[80];
    size_t read_profile_load_failure_count = 0;
    read_profile_load_failure_replies[read_profile_load_failure_count++] = k_mock_get_info_reply;
    for (size_t i = 0; i < read_control_count; i++) {
        read_profile_load_failure_replies[read_profile_load_failure_count++] =
            read_control_chunks[i];
    }
    read_profile_load_failure_replies[read_profile_load_failure_count++] =
        (Reply){.status = REPLY_TIMEOUT};
    read_profile_load_failure_replies[read_profile_load_failure_count++] = read_sensor_count;
    read_profile_load_failure_replies[read_profile_load_failure_count++] = read_sensor_list;
    read_profile_load_failure_replies[read_profile_load_failure_count++] = read_sensor_current;
    ChannelRequestTestContext read_profile_load_failure_context = {
        .replies = read_profile_load_failure_replies,
        .reply_count = read_profile_load_failure_count,
        .calls = 0};
    g_channel_request_test_context = &read_profile_load_failure_context;
    read_commands_ok = read_commands_ok && run_profiles(&read_full_dpi_options) == 0;

    Reply read_report_profiles_replies[96];
    size_t read_report_profiles_count = 0;
    read_report_profiles_count = append_read_replies(
        read_report_profiles_replies, 0, read_profiles_replies, read_profiles_reply_count);
    read_report_profiles_replies[read_report_profiles_count++] =
        (Reply){.status = REPLY_OK, .length = 2, .bytes = {0x00, 0x49}};
    read_report_profiles_replies[read_report_profiles_count++] =
        (Reply){.status = REPLY_OK, .length = 1, .bytes = {0x03}};
    ChannelRequestTestContext read_report_profiles_context = {
        .replies = read_report_profiles_replies,
        .reply_count = read_report_profiles_count,
        .calls = 0};
    g_channel_request_test_context = &read_report_profiles_context;
    Options read_report_profiles_options = read_detailed_options;
    read_report_profiles_options.profile = 3;
    read_report_profiles_options.include_report_rate = true;
    read_commands_ok = read_commands_ok && run_profiles(&read_report_profiles_options) == 0;

    Reply read_report_failure_replies[80];
    size_t read_report_failure_count = append_read_replies(
        read_report_failure_replies, 0, read_profiles_replies, read_profiles_reply_count);
    read_report_failure_replies[read_report_failure_count++] = (Reply){.status = REPLY_TIMEOUT};
    ChannelRequestTestContext read_report_failure_context = {.replies = read_report_failure_replies,
                                                             .reply_count =
                                                                 read_report_failure_count,
                                                             .calls = 0};
    g_channel_request_test_context = &read_report_failure_context;
    read_report_profiles_options.profile = 1;
    read_commands_ok = read_commands_ok && run_profiles(&read_report_profiles_options) == 0;

    // Report-rate-only mode has a different reply sequence from the combined
    // DPI/report flow above: it loads the selected profile, then queries the
    // extended report-rate mask and current wire value.
    size_t read_profile_base_count = 1 + read_control_count + read_profile_count;
    Reply read_report_only_replies[96];
    size_t read_report_only_count = append_read_replies(
        read_report_only_replies, 0, read_profiles_replies, read_profile_base_count);
    read_report_only_replies[read_report_only_count++] =
        (Reply){.status = REPLY_OK, .length = 2, .bytes = {0x00, 0x49}};
    read_report_only_replies[read_report_only_count++] =
        (Reply){.status = REPLY_OK, .length = 1, .bytes = {0x03}};
    ChannelRequestTestContext read_report_only_context = {
        .replies = read_report_only_replies, .reply_count = read_report_only_count, .calls = 0};
    g_channel_request_test_context = &read_report_only_context;
    Options read_report_only_options = read_info_options;
    read_report_only_options.include_report_rate = true;
    if (run_profiles(&read_report_only_options) != 0) {
        fprintf(stderr, "command read report-rate-only self-test failed\n");
        return 1;
    }

    // A profile can load successfully while the subsequent adjustable-DPI
    // capability query fails. run_profiles reports the device error but still
    // completes the read command.
    Reply read_profiles_dpi_failure_replies[96];
    size_t read_profiles_dpi_failure_count = append_read_replies(
        read_profiles_dpi_failure_replies, 0, read_profiles_replies, read_profile_base_count);
    read_profiles_dpi_failure_replies[read_profiles_dpi_failure_count++] =
        (Reply){.status = REPLY_TIMEOUT};
    ChannelRequestTestContext read_profiles_dpi_failure_context = {
        .replies = read_profiles_dpi_failure_replies,
        .reply_count = read_profiles_dpi_failure_count,
        .calls = 0};
    g_channel_request_test_context = &read_profiles_dpi_failure_context;
    Options read_profiles_dpi_failure_options = read_detailed_options;
    if (run_profiles(&read_profiles_dpi_failure_options) != 0) {
        fprintf(stderr, "command read DPI-capability-failure self-test failed\n");
        return 1;
    }

    Reply read_dpi_replies[64];
    size_t read_dpi_reply_count = 0;
    read_dpi_replies[read_dpi_reply_count++] = read_sensor_count;
    read_dpi_replies[read_dpi_reply_count++] = read_sensor_list;
    read_dpi_replies[read_dpi_reply_count++] = read_sensor_current;
    read_dpi_replies[read_dpi_reply_count++] = k_mock_get_info_reply;
    for (size_t i = 0; i < read_control_count; i++) {
        read_dpi_replies[read_dpi_reply_count++] = read_control_chunks[i];
    }
    for (size_t i = 0; i < read_profile_count; i++) {
        read_dpi_replies[read_dpi_reply_count++] = read_profile_chunks[i];
    }
    ChannelRequestTestContext read_dpi_context = {.replies = read_dpi_replies,
                                                  .reply_count = read_dpi_reply_count};
    g_channel_request_test_context = &read_dpi_context;
    Options read_dpi_options = read_info_options;
    read_commands_ok = read_commands_ok && run_dpi(&read_dpi_options) == 0;

    uint8_t read_bad_dpi_profile[255];
    memcpy(read_bad_dpi_profile, read_profile, sizeof(read_bad_dpi_profile));
    write_le16(read_bad_dpi_profile + 5, 0);
    sector_put_crc(read_bad_dpi_profile, sizeof(read_bad_dpi_profile));
    Reply read_bad_dpi_profile_chunks[32];
    size_t read_bad_dpi_profile_count = build_sector_read_replies(
        read_bad_dpi_profile, sizeof(read_bad_dpi_profile), read_bad_dpi_profile_chunks, 32);
    Reply read_bad_dpi_replies[96];
    size_t read_bad_dpi_reply_count = 0;
    read_bad_dpi_replies[read_bad_dpi_reply_count++] = read_sensor_count;
    read_bad_dpi_replies[read_bad_dpi_reply_count++] = read_sensor_list;
    read_bad_dpi_replies[read_bad_dpi_reply_count++] = read_sensor_current;
    read_bad_dpi_replies[read_bad_dpi_reply_count++] = k_mock_get_info_reply;
    for (size_t i = 0; i < read_control_count; i++) {
        read_bad_dpi_replies[read_bad_dpi_reply_count++] = read_control_chunks[i];
    }
    for (size_t i = 0; i < read_bad_dpi_profile_count; i++) {
        read_bad_dpi_replies[read_bad_dpi_reply_count++] = read_bad_dpi_profile_chunks[i];
    }
    ChannelRequestTestContext read_bad_dpi_context = {
        .replies = read_bad_dpi_replies, .reply_count = read_bad_dpi_reply_count, .calls = 0};
    g_channel_request_test_context = &read_bad_dpi_context;
    if (run_dpi(&read_dpi_options) != 0) {
        fprintf(stderr, "command read unrecognized-DPI-layout self-test failed\n");
        return 1;
    }

    Reply read_dpi_only_replies[] = {read_sensor_count, read_sensor_list, read_sensor_current};
    ChannelRequestTestContext read_dpi_profile_failure_context = {
        .replies = read_dpi_only_replies,
        .reply_count = sizeof(read_dpi_only_replies) / sizeof(read_dpi_only_replies[0]),
        .calls = 0};
    g_channel_request_test_context = &read_dpi_profile_failure_context;
    read_commands_ok = read_commands_ok && run_dpi(&read_dpi_options) == 0;

    ChannelRequestTestContext read_sensor_only_context = {
        .replies = read_dpi_only_replies,
        .reply_count = sizeof(read_dpi_only_replies) / sizeof(read_dpi_only_replies[0]),
        .calls = 0};
    g_channel_request_test_context = &read_sensor_only_context;
    Options read_sensor_only_options = read_dpi_options;
    read_sensor_only_options.sensor_only = true;
    read_commands_ok = read_commands_ok && run_dpi(&read_sensor_only_options) == 0;

    ChannelRequestTestContext read_current_context = {.replies = &read_current_dpi,
                                                      .reply_count = 1};
    g_channel_request_test_context = &read_current_context;
    read_commands_ok = read_commands_ok && run_current_dpi(&read_dpi_options) == 0 &&
                       read_current_context.calls == 1;

    ChannelRequestTestContext read_current_failure_context = {
        .replies = NULL, .reply_count = 0, .calls = 0};
    g_channel_request_test_context = &read_current_failure_context;
    if (run_current_dpi(&read_dpi_options) != 1) {
        fprintf(stderr, "command read current-DPI-failure self-test failed\n");
        return 1;
    }
    hid_context_create_impl = hid_context_create_hardware;
    if (!read_commands_ok) {
        fprintf(stderr, "command read-flow seam self-test failed\n");
        return 1;
    }

    return 0;
}
