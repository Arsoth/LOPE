static bool dpi_value_in_list(const uint16_t *values, size_t count, uint16_t wanted) {
    for (size_t i = 0; i < count; i++) {
        if (values[i] == wanted) {
            return true;
        }
    }
    return false;
}

static int run_set_dpi(const Options *options) {
    if (options->positional_count != 1) {
        fprintf(stderr, "set-dpi requires one to five comma-separated values, e.g. 800,1600\n");
        return 1;
    }
    uint16_t requested[5];
    size_t requested_count = 0;
    if (!parse_dpi_values(options->positionals[0], requested, &requested_count)) {
        fprintf(stderr, "invalid DPI list; use one to five comma-separated values from 100 to 65535\n");
        return 1;
    }

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
    uint16_t supported[MAX_DPI_VALUES];
    size_t supported_count = 0;
    uint8_t sensor_count = 0;
    if (!adjustable_dpi_values(device, supported, &supported_count, MAX_DPI_VALUES, &sensor_count, NULL)) {
        fprintf(stderr, "adjustable DPI feature 0x2201 is unavailable or unreadable\n");
        hid_context_release(&context);
        return 1;
    }
    if (sensor_count != 1) {
        fprintf(stderr, "refusing to edit onboard DPI: this device reports %u sensors; only one-sensor layouts are supported\n", sensor_count);
        hid_context_release(&context);
        return 1;
    }
    for (size_t i = 0; i < requested_count; i++) {
        if (!dpi_value_in_list(supported, supported_count, requested[i])) {
            fprintf(stderr, "refusing to edit onboard DPI: %u is not reported as a supported sensor value\n", requested[i]);
            hid_context_release(&context);
            return 1;
        }
        if (i > 0 && requested[i] <= requested[i - 1]) {
            fprintf(stderr, "refusing to edit onboard DPI: stages must be strictly increasing\n");
            hid_context_release(&context);
            return 1;
        }
    }

    Profile profile;
    if (!load_selected_profile(device, options->profile, &profile)) {
        hid_context_release(&context);
        return 1;
    }
    if (options->profile == 0 && profile.header_count > 1) {
        fprintf(stderr, "refusing to choose a profile implicitly: this device has %zu profile slots. Use `--profile N`.\n",
                profile.header_count);
        free(profile.data);
        hid_context_release(&context);
        return 1;
    }
    if (!profile.crc_ok || !profile.dpi_layout_supported) {
        fprintf(stderr, "refusing to write: this profile's CRC or DPI layout was not validated\n");
        free(profile.data);
        hid_context_release(&context);
        return 1;
    }
    int default_index = options->dpi_default >= 0 ? options->dpi_default : profile.dpi_default_index + 1;
    int shift_index = options->dpi_shift >= 0 ? options->dpi_shift : profile.dpi_shift_index + 1;
    if (default_index < 1 || default_index > (int)requested_count ||
        shift_index < 1 || shift_index > (int)requested_count) {
        fprintf(stderr, "DPI indexes must be within the active stage count (1..%zu)\n", requested_count);
        free(profile.data);
        hid_context_release(&context);
        return 1;
    }
    printf("Device: %s, profile %d, sector 0x%04X\n", device_label(device),
           (int)profile.selected_header + 1, profile.headers[profile.selected_header].sector);
    printf("Planned DPI stages: ");
    for (size_t i = 0; i < requested_count; i++) {
        if (i != 0) {
            printf(", ");
        }
        printf("%u", requested[i]);
    }
    printf(" (active %zu of 5, default %d, shift %d)\n",
           requested_count, default_index, shift_index);
    if (!options->yes) {
        free(profile.data);
        hid_context_release(&context);
        return ensure_write_confirmation("set-dpi");
    }

    char backup_path[512];
    if (options->backup_path != NULL) {
        snprintf(backup_path, sizeof(backup_path), "%s", options->backup_path);
    } else {
        default_backup_path(backup_path, sizeof(backup_path), "lomps-dpi-backup");
    }
    if (!package_write(backup_path, device, &profile, profile.data, true)) {
        free(profile.data);
        hid_context_release(&context);
        return 1;
    }
    printf("Saved the original profile sector to %s\n", backup_path);
    uint8_t *new_data = (uint8_t *)malloc(profile.data_length);
    if (new_data == NULL) {
        fprintf(stderr, "out of memory while preparing the DPI update\n");
        free(profile.data);
        hid_context_release(&context);
        return 1;
    }
    memcpy(new_data, profile.data, profile.data_length);
    for (size_t i = 0; i < requested_count; i++) {
        write_le16(new_data + profile.dpi_offset + i * 2, requested[i]);
    }
    for (size_t i = requested_count; i < 5; i++) {
        write_le16(new_data + profile.dpi_offset + i * 2, UINT16_MAX);
    }
    new_data[1] = (uint8_t)(default_index - 1);
    new_data[2] = (uint8_t)(shift_index - 1);
    sector_put_crc(new_data, profile.data_length);
    bool written = write_sector(device, profile.headers[profile.selected_header].sector,
                                new_data, profile.data_length);
    uint8_t *readback = written ? (uint8_t *)malloc(profile.data_length) : NULL;
    bool verified = readback != NULL && read_sector(device, profile.headers[profile.selected_header].sector,
                                                    profile.data_length, readback) &&
                    sector_crc_ok(readback, profile.data_length) &&
                    memcmp(readback, new_data, profile.data_length) == 0;
    if (!verified) {
        fprintf(stderr, "DPI write/readback verification failed; restore from %s\n", backup_path);
        free(readback);
        free(new_data);
        free(profile.data);
        hid_context_release(&context);
        return 1;
    }
    printf("Verified: DPI profile readback CRC is OK and the complete sector matches.\n");
    free(readback);
    free(new_data);
    free(profile.data);
    hid_context_release(&context);
    return 0;
}

static int run_set_profile_state(const Options *options) {
    if (options->positional_count != 2) {
        fprintf(stderr, "set-profile-state syntax: set-profile-state N enable|disable\n");
        return 1;
    }
    char *end = NULL;
    errno = 0;
    long requested_profile = strtol(options->positionals[0], &end, 10);
    if (errno != 0 || end == options->positionals[0] || *end != '\0' ||
        requested_profile < 1 || requested_profile > MAX_HEADERS) {
        fprintf(stderr, "invalid profile number '%s'\n", options->positionals[0]);
        return 1;
    }
    bool enable = false;
    if (strcmp(options->positionals[1], "enable") == 0) {
        enable = true;
    } else if (strcmp(options->positionals[1], "disable") != 0) {
        fprintf(stderr, "profile state must be enable or disable\n");
        return 1;
    }

    HidContext context;
    if (!hid_context_create(&context)) {
        return 1;
    }
    Device devices[MAX_DEVICES];
    size_t device_count = 0;
    discover_devices_for_options(&context, options, devices, &device_count);
    Device *device = NULL;
    if (!select_device(devices, device_count, options, &device)) {
        hid_context_release(&context);
        return 1;
    }

    ProfileInfo info;
    if (!get_profile_info(device, &info)) {
        hid_context_release(&context);
        return 1;
    }
    uint8_t *control = (uint8_t *)malloc(info.sector_size);
    if (control == NULL) {
        fprintf(stderr, "out of memory while reading the profile control sector\n");
        hid_context_release(&context);
        return 1;
    }
    uint16_t control_sector = 0;
    ProfileHeader headers[MAX_HEADERS];
    size_t header_count = 0;
    if (!read_profile_control(device, &info, &control_sector, control, info.sector_size) ||
        !sector_crc_ok(control, info.sector_size) ||
        !parse_profile_headers(&info, control, info.sector_size, headers, &header_count)) {
        fprintf(stderr, "refusing to edit profile state: the control sector or profile headers were not validated\n");
        free(control);
        hid_context_release(&context);
        return 1;
    }
    if (requested_profile > (long)header_count) {
        fprintf(stderr, "profile %ld is out of range; the device exposes %zu profile slots\n",
                requested_profile, header_count);
        free(control);
        hid_context_release(&context);
        return 1;
    }
    size_t selected = (size_t)requested_profile - 1;
    bool was_enabled = headers[selected].enabled != 0;
    if (was_enabled == enable) {
        printf("Profile %ld is already %s; no control-sector write is needed.\n",
               requested_profile, enable ? "enabled" : "disabled");
        free(control);
        hid_context_release(&context);
        return 0;
    }
    if (!enable) {
        size_t enabled_count = 0;
        for (size_t i = 0; i < header_count; i++) {
            enabled_count += headers[i].enabled != 0 ? 1 : 0;
        }
        if (enabled_count <= 1) {
            fprintf(stderr, "refusing to disable the last enabled onboard profile\n");
            free(control);
            hid_context_release(&context);
            return 1;
        }
    }

    printf("Device: %s, profile %ld, control sector 0x%04X\n",
           device_label(device), requested_profile, control_sector);
    printf("Planned profile state: %s -> %s\n",
           was_enabled ? "enabled" : "disabled", enable ? "enabled" : "disabled");
    char backup_path[512];
    if (options->backup_path != NULL) {
        snprintf(backup_path, sizeof(backup_path), "%s", options->backup_path);
    } else {
        default_backup_path(backup_path, sizeof(backup_path), "lomps-profile-state-backup");
    }
    printf("Backup: %s\n", backup_path);
    if (!options->yes) {
        free(control);
        hid_context_release(&context);
        return ensure_write_confirmation("set-profile-state");
    }

    Profile control_profile;
    memset(&control_profile, 0, sizeof(control_profile));
    control_profile.info = info;
    control_profile.headers[0].sector = control_sector;
    control_profile.headers[0].enabled = 1;
    control_profile.selected_header = 0;
    control_profile.data = control;
    control_profile.data_length = info.sector_size;
    control_profile.crc_ok = true;
    if (!package_write(backup_path, device, &control_profile, control, true)) {
        free(control);
        hid_context_release(&context);
        return 1;
    }
    printf("Saved the original profile control sector before writing.\n");
    uint8_t *new_control = (uint8_t *)malloc(info.sector_size);
    if (new_control == NULL) {
        fprintf(stderr, "out of memory while preparing the profile-state update\n");
        free(control);
        hid_context_release(&context);
        return 1;
    }
    memcpy(new_control, control, info.sector_size);
    size_t enabled_offset = selected * 4 + 2;
    if (enabled_offset >= info.sector_size - 2) {
        fprintf(stderr, "refusing to write: profile header is outside the validated control sector\n");
        free(new_control);
        free(control);
        hid_context_release(&context);
        return 1;
    }
    new_control[enabled_offset] = enable ? 1 : 0;
    sector_put_crc(new_control, info.sector_size);
    if (!sector_crc_ok(new_control, info.sector_size) ||
        !write_sector(device, control_sector, new_control, info.sector_size)) {
        fprintf(stderr, "profile-state write failed; restore from %s\n", backup_path);
        free(new_control);
        free(control);
        hid_context_release(&context);
        return 1;
    }
    uint8_t *readback = (uint8_t *)malloc(info.sector_size);
    bool verified = readback != NULL && read_sector(device, control_sector, info.sector_size, readback) &&
                    sector_crc_ok(readback, info.sector_size) &&
                    memcmp(readback, new_control, info.sector_size) == 0;
    if (!verified) {
        fprintf(stderr, "profile-state read-back verification failed; restore from %s\n", backup_path);
        free(readback);
        free(new_control);
        free(control);
        hid_context_release(&context);
        return 1;
    }
    printf("Verified: profile control-sector CRC is OK and the complete sector matches.\n");
    free(readback);
    free(new_control);
    free(control);
    hid_context_release(&context);
    return 0;
}
