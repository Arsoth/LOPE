#include "internal.h"
#include "test_doubles.h"

int test_commands_read(void) {
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

    return 0;
}
