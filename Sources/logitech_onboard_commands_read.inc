static void print_supported_dpi(const uint16_t *values, size_t count);

static int run_list(void) {
    HidContext context;
    if (!hid_context_create(&context)) {
        return 1;
    }
    Device devices[MAX_DEVICES];
    size_t count = 0;
    // Listing only needs stable identities and pairing presence. Capability
    // discovery is deferred until the selected device is queried, avoiding
    // dozens of HID++ requests on every GUI refresh.
    discover_devices(&context, -1, devices, &count, false);
    size_t vendor_interfaces = 0;
    for (size_t i = 0; i < context.count; i++) {
        if (context.items[i].is_vendor) {
            vendor_interfaces++;
        }
    }
    printf("Logitech HID++ vendor interfaces: %zu\n", vendor_interfaces);
    size_t mouse_count = 0;
    for (size_t i = 0; i < count; i++) {
        if (!is_mouse_device(&devices[i]) ||
            is_duplicate_direct_mouse_endpoint(&devices[i], devices, count)) {
            continue;
        }
        print_device_line(&devices[i], i);
        mouse_count++;
    }
    if (mouse_count == 0) {
        printf("No reachable Logitech mouse devices found.\n");
    }
    hid_context_release(&context);
    return 0;
}

static int select_device(Device *devices, size_t count, const Options *options, Device **selected) {
    if (count == 0) {
        fprintf(stderr, "no reachable Logitech HID++ device found\n");
        return 0;
    }
    if (options->device_key != NULL) {
        for (size_t i = 0; i < count; i++) {
            char key[64];
            format_device_key(&devices[i], key, sizeof(key));
            if (strcmp(options->device_key, key) == 0) {
                *selected = &devices[i];
                return 1;
            }
        }
        fprintf(stderr, "device key '%s' was not found among reachable devices\n", options->device_key);
        return 0;
    }
    if (options->device_index >= 0) {
        if ((size_t)options->device_index >= count) {
            fprintf(stderr, "device index %d is out of range 0..%zu\n", options->device_index, count - 1);
            return 0;
        }
        *selected = &devices[options->device_index];
        return 1;
    }
    for (size_t i = 0; i < count; i++) {
        if (devices[i].device_number != 0xFF && devices[i].protocol >= 2.0) {
            *selected = &devices[i];
            return 1;
        }
    }
    *selected = &devices[0];
    return 1;
}

static int run_info(const Options *options) {
    HidContext context;
    if (!hid_context_create(&context)) {
        return 1;
    }
    Device devices[MAX_DEVICES];
    size_t count = 0;
    discover_devices_for_options(&context, options, devices, &count);
    Device *device = NULL;
    if (!select_device(devices, count, options, &device)) {
        hid_context_release(&context);
        return 1;
    }
    printf("Device: %s\n", device_label(device));
    printf("  vendor/product: 0x%04X / 0x%04X\n", device->iface->vendor_id, device->iface->product_id);
    printf("  connection: %s, device number: 0x%02X\n",
           device->device_number == 0xFF ? "direct or receiver" : "receiver",
           device->device_number);
    printf("  HID++ protocol: %.1f\n", device->protocol);
    print_feature_list(device);

    ProfileInfo profile_info;
    if (!device_feature_index(device, FEATURE_ONBOARD_PROFILES, &(uint8_t){0}) ||
        !get_profile_info(device, &profile_info)) {
        printf("  onboard profiles: unavailable (feature 0x8100 not usable)\n");
        hid_context_release(&context);
        return 0;
    }
    printf("  onboard descriptor: memory 0x%02X, format 0x%02X, macro format 0x%02X, shift flags 0x%02X\n",
           profile_info.memory, profile_info.profile_format, profile_info.macro_format, profile_info.shift_flags);
    printf("  onboard counts: profiles %u, buttons %u, sectors %u, sector size %u bytes\n",
           profile_info.profile_count, profile_info.button_count, profile_info.sector_count, profile_info.sector_size);
    ProfileHeader headers[MAX_HEADERS];
    size_t header_count = 0;
    if (read_profile_headers(device, &profile_info, headers, &header_count)) {
        printf("  profile headers:\n");
        for (size_t i = 0; i < header_count; i++) {
            printf("    profile %zu: sector 0x%04X, enabled=%s\n",
                   i + 1, headers[i].sector, headers[i].enabled ? "yes" : "no");
        }
        Profile profile;
        if (load_profile_with_headers(device, &profile_info, headers, header_count, options->profile, &profile)) {
            printf("  selected profile:\n");
            print_profile_summary(&profile, true);
            free(profile.data);
        }
    } else {
        printf("  profile headers: unavailable\n");
    }
    hid_context_release(&context);
    return 0;
}

static int run_profiles(const Options *options) {
    HidContext context;
    if (!hid_context_create(&context)) {
        return 1;
    }
    Device devices[MAX_DEVICES];
    size_t count = 0;
    discover_devices_for_options(&context, options, devices, &count);
    Device *device = NULL;
    if (!select_device(devices, count, options, &device)) {
        hid_context_release(&context);
        return 1;
    }
    ProfileInfo info;
    if (!get_profile_info(device, &info)) {
        hid_context_release(&context);
        return 1;
    }
    printf("Onboard profiles for %s:\n", device_label(device));
    // Keep the device-reported capacity separate from the number of profile
    // headers that were readable. The GUI uses this stable marker to explain
    // partially provisioned or unusual onboard-profile layouts.
    // Emit it before the header walk so the UI can show capacity while the
    // remaining profile reads are still in progress.
    printf("Profile capacity: %u\n", info.profile_count);
    fflush(stdout);
    ProfileHeader headers[MAX_HEADERS];
    size_t header_count = 0;
    if (!read_profile_headers(device, &info, headers, &header_count)) {
        fprintf(stderr, "could not find onboard profile headers\n");
        hid_context_release(&context);
        return 1;
    }
    int requested_profile = options->profile;
    if (options->include_dpi && requested_profile > 0 &&
        (size_t)requested_profile > header_count) {
        // The GUI keeps the last selected profile while the user changes
        // devices. If that slot does not exist on the new mouse, use its
        // first enabled slot and report the actual selection below.
        requested_profile = 0;
    }
    if (options->headers_only && !options->include_dpi) {
        for (size_t i = 0; i < header_count; i++) {
            printf("Profile %zu (sector 0x%04X, enabled=%s)\n",
                   i + 1, headers[i].sector, headers[i].enabled ? "yes" : "no");
        }
        hid_context_release(&context);
        return 0;
    }

    if (options->include_dpi) {
        // The GUI needs the complete profile list, but only the selected
        // profile's records and onboard DPI stages. Emit lightweight headers
        // for every slot before the detailed selected-profile summary so the
        // caller can populate its picker without reading every full sector.
        for (size_t i = 0; i < header_count; i++) {
            printf("Profile %zu (sector 0x%04X, enabled=%s)\n",
                   i + 1, headers[i].sector, headers[i].enabled ? "yes" : "no");
        }

        size_t selected = 0;
        if (requested_profile > 0) {
            selected = (size_t)requested_profile - 1;
        } else {
            for (size_t i = 0; i < header_count; i++) {
                if (headers[i].enabled != 0) {
                    selected = i;
                    break;
                }
            }
        }

        Profile profile;
        if (options->summary_only
                ? load_profile_summary_with_headers(device, &info, headers, header_count,
                                                     (int)selected + 1, &profile)
                : load_profile_with_headers(device, &info, headers, header_count,
                                             (int)selected + 1, &profile)) {
            printf("Selected profile: %zu\n", selected + 1);
            print_profile_summary(&profile, true);
            free(profile.data);
        }
    } else {
        size_t first = 0;
        size_t last = header_count;
        if (requested_profile > 0) {
            if ((size_t)requested_profile > header_count) {
                fprintf(stderr, "profile %d is out of range 1..%zu\n", options->profile, header_count);
                hid_context_release(&context);
                return 1;
            }
            first = (size_t)requested_profile - 1;
            last = first + 1;
        }

        for (size_t i = first; i < last; i++) {
            Profile profile;
            int loaded = options->summary_only
                ? load_profile_summary_with_headers(device, &info, headers, header_count, (int)i + 1, &profile)
                : load_profile_with_headers(device, &info, headers, header_count, (int)i + 1, &profile);
            if (loaded) {
                print_profile_summary(&profile, true);
                free(profile.data);
            }
        }
    }
    if (options->include_dpi) {
        uint16_t values[MAX_DPI_VALUES];
        size_t value_count = 0;
        uint8_t sensor_count = 0;
        uint16_t current = 0;
        if (adjustable_dpi_values(device, values, &value_count, MAX_DPI_VALUES,
                                  &sensor_count, &current)) {
            printf("Device: %s\n", device_label(device));
            printf("DPI sensors: %u\n", sensor_count);
            print_supported_dpi(values, value_count);
            printf("Current sensor 1 DPI: %u\n", current);
        } else {
            printf("DPI error: adjustable DPI feature 0x2201 is unavailable or unreadable\n");
        }
    }
    hid_context_release(&context);
    return 0;
}

static void print_supported_dpi(const uint16_t *values, size_t count) {
    printf("Supported DPI: ");
    if (count >= 2) {
        uint16_t step = (uint16_t)(values[1] - values[0]);
        bool regular = step > 0;
        for (size_t i = 2; regular && i < count; i++) {
            regular = (uint16_t)(values[i] - values[i - 1]) == step;
        }
        if (regular) {
            printf("%u..%u (step %u)\n", values[0], values[count - 1], step);
            return;
        }
    }
    for (size_t i = 0; i < count; i++) {
        if (i != 0) {
            printf(", ");
        }
        printf("%u", values[i]);
    }
    printf("\n");
}

static int run_dpi(const Options *options) {
    HidContext context;
    if (!hid_context_create(&context)) {
        return 1;
    }
    Device devices[MAX_DEVICES];
    size_t count = 0;
    discover_devices_for_options(&context, options, devices, &count);
    Device *device = NULL;
    if (!select_device(devices, count, options, &device)) {
        hid_context_release(&context);
        return 1;
    }
    uint16_t values[MAX_DPI_VALUES];
    size_t value_count = 0;
    uint8_t sensor_count = 0;
    uint16_t current = 0;
    if (!adjustable_dpi_values(device, values, &value_count, MAX_DPI_VALUES, &sensor_count, &current)) {
        fprintf(stderr, "adjustable DPI feature 0x2201 is unavailable or unreadable\n");
        hid_context_release(&context);
        return 1;
    }
    printf("Device: %s\n", device_label(device));
    printf("DPI sensors: %u\n", sensor_count);
    print_supported_dpi(values, value_count);
    printf("Current sensor 1 DPI: %u\n", current);

    if (options->sensor_only) {
        hid_context_release(&context);
        return 0;
    }

    Profile profile;
    if (load_selected_profile(device, options->profile, &profile)) {
        if (profile.dpi_layout_supported) {
            printf("Onboard profile %zu DPI stages: ", profile.selected_header + 1);
            for (size_t i = 0; i < profile.dpi_count; i++) {
                if (i != 0) {
                    printf(", ");
                }
                printf("%u", read_le16(profile.data + profile.dpi_offset + i * 2));
            }
            printf(" (default %u, shift %u)\n",
                   profile.dpi_default_index + 1,
                   profile.dpi_shift_index + 1);
        } else {
            printf("Onboard profile DPI layout: not recognized; stage editing is disabled\n");
        }
        free(profile.data);
    }
    hid_context_release(&context);
    return 0;
}

static int parse_dpi_values(const char *text, uint16_t values[5], size_t *count_out) {
    if (text == NULL) {
        return 0;
    }
    char copy[256];
    if (strlen(text) >= sizeof(copy)) {
        return 0;
    }
    strcpy(copy, text);
    char *save = NULL;
    char *part = strtok_r(copy, ",", &save);
    size_t count = 0;
    while (part != NULL && count < 5) {
        errno = 0;
        char *end = NULL;
        unsigned long value = strtoul(part, &end, 10);
        while (end != NULL && *end == ' ') {
            end++;
        }
        if (errno != 0 || end == part || *end != '\0' || value < 100 || value > UINT16_MAX) {
            return 0;
        }
        values[count++] = (uint16_t)value;
        part = strtok_r(NULL, ",", &save);
    }
    if (count == 0 || part != NULL) {
        return 0;
    }
    if (count_out != NULL) {
        *count_out = count;
    }
    return 1;
}
