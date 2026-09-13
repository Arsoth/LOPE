#include "internal.h"
#include "test_doubles.h"

int test_report_rate(void) {
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
                              report_rate_connection_type(&wired_device) == 0 &&
                              report_rate_connection_type(NULL) == 0;
    if (!connection_type_ok) {
        fprintf(stderr, "report-rate connection-type self-test failed\n");
        return 1;
    }

    uint32_t parsed_hertz = 0;
    bool hertz_parser_ok =
        parse_report_rate_hertz("1000", &parsed_hertz) && parsed_hertz == 1000 &&
        parse_report_rate_hertz("4294967295", &parsed_hertz) && parsed_hertz == UINT32_MAX &&
        !parse_report_rate_hertz(NULL, &parsed_hertz) && !parse_report_rate_hertz("1000", NULL) &&
        !parse_report_rate_hertz("", &parsed_hertz) &&
        !parse_report_rate_hertz("0", &parsed_hertz) &&
        !parse_report_rate_hertz("abc", &parsed_hertz) &&
        !parse_report_rate_hertz("12x", &parsed_hertz) &&
        !parse_report_rate_hertz("4294967296", &parsed_hertz) &&
        !parse_report_rate_hertz("-1", &parsed_hertz);
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

    const Reply adjustable_unsupported_current_replies[] = {
        (Reply){.status = REPLY_OK, .length = 1, .bytes = {0x01}},
        (Reply){.status = REPLY_OK, .length = 1, .bytes = {0x02}},
    };
    ChannelRequestTestContext adjustable_unsupported_current_context = {
        .replies = adjustable_unsupported_current_replies,
        .reply_count = 2,
        .calls = 0,
    };
    g_channel_request_test_context = &adjustable_unsupported_current_context;
    ReportRateCapabilities adjustable_unsupported_current_capabilities;
    adjustable_ok = adjustable_ok &&
                    read_report_rate_capabilities(&capability_device,
                                                  &adjustable_unsupported_current_capabilities) &&
                    !adjustable_unsupported_current_capabilities.current_valid &&
                    adjustable_unsupported_current_capabilities.current_hertz == 0;

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

    Options invalid_rate_options = {0};
    invalid_rate_options.positionals[0] = "0";
    invalid_rate_options.positional_count = 1;
    if (run_set_report_rate(&invalid_rate_options) != 1) {
        fprintf(stderr, "run_set_report_rate invalid-input self-test failed\n");
        return 1;
    }

    return 0;
}
