static int run_dump(const Options *options) {
    if (options->path == NULL) {
        fprintf(stderr, "dump requires an output path\n");
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
    Profile profile;
    if (!load_selected_profile(device, options->profile, &profile)) {
        hid_context_release(&context);
        return 1;
    }
    if (!profile.crc_ok) {
        fprintf(stderr, "warning: dumping a sector with an invalid CRC; it cannot be used for restore until repaired by the vendor software\n");
    }
    int ok = package_write(options->path, device, &profile, profile.data, false);
    if (ok) {
        printf("dumped profile %zu sector 0x%04X (%zu bytes) to %s\n",
               profile.selected_header + 1,
               profile.headers[profile.selected_header].sector,
               profile.data_length,
               options->path);
    }
    free(profile.data);
    hid_context_release(&context);
    return ok ? 0 : 1;
}

static int parse_hex_byte(const char *text, uint8_t *value) {
    if (text == NULL || *text == '\0') {
        return 0;
    }
    char *end = NULL;
    errno = 0;
    unsigned long number = strtoul(text, &end, 16);
    if (errno != 0 || end == text || *end != '\0' || number > 0xFF) {
        return 0;
    }
    *value = (uint8_t)number;
    return 1;
}

static int parse_hex_word(const char *text, uint16_t *value) {
    if (text == NULL || *text == '\0') {
        return 0;
    }
    char *end = NULL;
    errno = 0;
    unsigned long number = strtoul(text, &end, 16);
    if (errno != 0 || end == text || *end != '\0' || number > 0xFFFF) {
        return 0;
    }
    *value = (uint16_t)number;
    return 1;
}

static int parse_target(const char *target, uint8_t spec[4]) {
    if (target == NULL) {
        return 0;
    }
    char lower[128];
    size_t length = strlen(target);
    if (length >= sizeof(lower)) {
        return 0;
    }
    for (size_t i = 0; i <= length; i++) {
        char c = target[i];
        if (c >= 'A' && c <= 'Z') {
            c = (char)(c - 'A' + 'a');
        }
        lower[i] = c;
    }
    uint16_t mouse_mask = 0;
    if (strcmp(lower, "left") == 0 || strcmp(lower, "left-click") == 0) mouse_mask = 0x0001;
    else if (strcmp(lower, "right") == 0 || strcmp(lower, "right-click") == 0) mouse_mask = 0x0002;
    else if (strcmp(lower, "middle") == 0 || strcmp(lower, "middle-click") == 0) mouse_mask = 0x0004;
    else if (strcmp(lower, "back") == 0) mouse_mask = 0x0008;
    else if (strcmp(lower, "forward") == 0) mouse_mask = 0x0010;
    else if (strcmp(lower, "button6") == 0) mouse_mask = 0x0020;
    else if (strcmp(lower, "button7") == 0) mouse_mask = 0x0040;
    else if (strcmp(lower, "button8") == 0) mouse_mask = 0x0080;
    if (mouse_mask != 0) {
        spec[0] = 0x80; spec[1] = 0x01;
        spec[2] = (uint8_t)(mouse_mask >> 8); spec[3] = (uint8_t)mouse_mask;
        return 1;
    }
    if (strcmp(lower, "alt-tab") == 0 || strcmp(lower, "alt+tab") == 0 || strcmp(lower, "alt_tab") == 0) {
        spec[0] = 0x80; spec[1] = 0x02; spec[2] = 0x04; spec[3] = 0x2B;
        return 1;
    }
    if (strcmp(lower, "dpi-up") == 0 || strcmp(lower, "next-dpi") == 0) {
        spec[0] = 0x90; spec[1] = 0x03; spec[2] = 0x00; spec[3] = 0x00;
        return 1;
    }
    if (strcmp(lower, "dpi-down") == 0 || strcmp(lower, "previous-dpi") == 0) {
        spec[0] = 0x90; spec[1] = 0x04; spec[2] = 0x00; spec[3] = 0x00;
        return 1;
    }
    if (strcmp(lower, "dpi-cycle") == 0 || strcmp(lower, "cycle-dpi") == 0) {
        spec[0] = 0x90; spec[1] = 0x05; spec[2] = 0x00; spec[3] = 0x00;
        return 1;
    }
    if (strcmp(lower, "dpi-default") == 0) {
        spec[0] = 0x90; spec[1] = 0x06; spec[2] = 0x00; spec[3] = 0x00;
        return 1;
    }
    if (strcmp(lower, "dpi-shift") == 0) {
        spec[0] = 0x90; spec[1] = 0x07; spec[2] = 0x00; spec[3] = 0x00;
        return 1;
    }
    if (strcmp(lower, "next-profile") == 0 || strcmp(lower, "previous-profile") == 0 ||
        strcmp(lower, "cycle-profile") == 0 || strcmp(lower, "g-shift") == 0) {
        uint8_t function = 0x00;
        if (strcmp(lower, "next-profile") == 0) function = 0x08;
        else if (strcmp(lower, "previous-profile") == 0) function = 0x09;
        else if (strcmp(lower, "cycle-profile") == 0) function = 0x0A;
        else function = 0x0B;
        spec[0] = 0x90; spec[1] = function; spec[2] = 0x00; spec[3] = 0x00;
        return 1;
    }
    if (strcmp(lower, "nav-back") == 0 || strcmp(lower, "cmd-[") == 0) {
        spec[0] = 0x80; spec[1] = 0x02; spec[2] = 0x08; spec[3] = 0x2F;
        return 1;
    }
    if (strcmp(lower, "nav-forward") == 0 || strcmp(lower, "cmd-]") == 0) {
        spec[0] = 0x80; spec[1] = 0x02; spec[2] = 0x08; spec[3] = 0x30;
        return 1;
    }
    if (strcmp(lower, "disable") == 0 || strcmp(lower, "none") == 0 || strcmp(lower, "off") == 0) {
        memset(spec, 0xFF, 4);
        return 1;
    }
    if (strncmp(lower, "key:", 4) == 0) {
        const char *colon = strchr(lower + 4, ':');
        if (colon == NULL) {
            return 0;
        }
        char modifier_text[16];
        char key_text[16];
        size_t modifier_length = (size_t)(colon - (lower + 4));
        if (modifier_length == 0 || modifier_length >= sizeof(modifier_text) || strlen(colon + 1) >= sizeof(key_text)) {
            return 0;
        }
        memcpy(modifier_text, lower + 4, modifier_length);
        modifier_text[modifier_length] = '\0';
        strcpy(key_text, colon + 1);
        uint8_t modifier = 0;
        uint8_t key = 0;
        if (!parse_hex_byte(modifier_text, &modifier) || !parse_hex_byte(key_text, &key)) {
            return 0;
        }
        spec[0] = 0x80; spec[1] = 0x02; spec[2] = modifier; spec[3] = key;
        return 1;
    }
    if (strncmp(lower, "consumer:", 9) == 0) {
        uint16_t consumer = 0;
        if (!parse_hex_word(lower + 9, &consumer)) {
            return 0;
        }
        spec[0] = 0x80; spec[1] = 0x03;
        spec[2] = (uint8_t)(consumer >> 8); spec[3] = (uint8_t)consumer;
        return 1;
    }
    if (strlen(lower) == 8) {
        for (int i = 0; i < 4; i++) {
            char pair[3] = {lower[i * 2], lower[i * 2 + 1], '\0'};
            if (!parse_hex_byte(pair, &spec[i])) {
                return 0;
            }
        }
        return 1;
    }
    return 0;
}

static int run_bind(const Options *options) {
    if (options->target == NULL) {
        fprintf(stderr, "bind requires a target such as alt-tab or key:04:2B\n");
        return 1;
    }
    uint8_t requested_spec[4];
    if (!parse_target(options->target, requested_spec)) {
        fprintf(stderr, "unrecognized target '%s'\n", options->target);
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
    Profile profile;
    if (!load_selected_profile(device, options->profile, &profile)) {
        hid_context_release(&context);
        return 1;
    }
    if (options->profile == 0 && profile.header_count > 1) {
        fprintf(stderr, "refusing to choose a profile implicitly: this device has %zu profile slots. Use `--profile N` after reviewing `profiles`.\n",
                profile.header_count);
        free(profile.data);
        hid_context_release(&context);
        return 1;
    }
    if (!validate_profile_for_write(&profile)) {
        free(profile.data);
        hid_context_release(&context);
        return 1;
    }
    int button = options->button;
    if (button == 0) {
        button = find_rear_thumb_button(&profile);
        if (button == 0) {
            fprintf(stderr, "could not identify one rear-thumb profile record. Run `profiles` and `watch`, then use `--button N`.\n");
            free(profile.data);
            hid_context_release(&context);
            return 1;
        }
    }
    if (button < 1 || button > profile.info.button_count) {
        fprintf(stderr, "button %d is out of range 1..%u\n", button, profile.info.button_count);
        free(profile.data);
        hid_context_release(&context);
        return 1;
    }
    size_t offset = profile.button_offset + (size_t)(button - 1) * 4;
    uint8_t old_spec[4];
    memcpy(old_spec, profile.data + offset, 4);
    char old_description[160];
    char new_description[160];
    describe_spec(old_spec, old_description, sizeof(old_description));
    describe_spec(requested_spec, new_description, sizeof(new_description));
    printf("Device: %s, profile %d, sector 0x%04X\n", device_label(device), (int)profile.selected_header + 1,
           profile.headers[profile.selected_header].sector);
    printf("Planned change: button %d: %s -> %s\n", button, old_description, new_description);
    printf("Raw change: ");
    print_hex4(old_spec);
    printf(" -> ");
    print_hex4(requested_spec);
    printf("\n");
    if (memcmp(old_spec, requested_spec, 4) == 0) {
        printf("Nothing to do; the requested binding is already present.\n");
        free(profile.data);
        hid_context_release(&context);
        return 0;
    }
    char backup_path[512];
    if (options->backup_path != NULL) {
        snprintf(backup_path, sizeof(backup_path), "%s", options->backup_path);
    } else {
        default_backup_path(backup_path, sizeof(backup_path), "lomps-backup");
    }
    printf("Backup: %s\n", backup_path);
    if (!options->yes) {
        free(profile.data);
        hid_context_release(&context);
        return ensure_write_confirmation("bind");
    }
    if (!package_write(backup_path, device, &profile, profile.data, true)) {
        free(profile.data);
        hid_context_release(&context);
        return 1;
    }
    printf("Saved the original sector before writing.\n");

    uint8_t *new_data = (uint8_t *)malloc(profile.data_length);
    if (new_data == NULL) {
        fprintf(stderr, "out of memory while preparing the new sector\n");
        free(profile.data);
        hid_context_release(&context);
        return 1;
    }
    memcpy(new_data, profile.data, profile.data_length);
    memcpy(new_data + offset, requested_spec, 4);
    sector_put_crc(new_data, profile.data_length);
    if (!sector_crc_ok(new_data, profile.data_length)) {
        fprintf(stderr, "internal CRC verification failed; no mouse write was attempted\n");
        free(new_data);
        free(profile.data);
        hid_context_release(&context);
        return 1;
    }
    if (!write_sector(device, profile.headers[profile.selected_header].sector, new_data, profile.data_length)) {
        fprintf(stderr, "write failed; restore from %s if the device reports a partial change\n", backup_path);
        free(new_data);
        free(profile.data);
        hid_context_release(&context);
        return 1;
    }
    uint8_t *readback = (uint8_t *)malloc(profile.data_length);
    if (readback == NULL || !read_sector(device, profile.headers[profile.selected_header].sector,
                                         profile.data_length, readback)) {
        fprintf(stderr, "could not read back the sector; restore from %s\n", backup_path);
        free(readback);
        free(new_data);
        free(profile.data);
        hid_context_release(&context);
        return 1;
    }
    bool verified = sector_crc_ok(readback, profile.data_length) && memcmp(readback, new_data, profile.data_length) == 0;
    if (!verified) {
        fprintf(stderr, "read-back verification failed; restore from %s\n", backup_path);
        free(readback);
        free(new_data);
        free(profile.data);
        hid_context_release(&context);
        return 1;
    }
    printf("Verified: read-back CRC is OK and the complete sector matches.\n");
    printf("The mouse now stores %s on button %d.\n", new_description, button);
    free(readback);
    free(new_data);
    free(profile.data);
    hid_context_release(&context);
    return 0;
}

static int run_restore(const Options *options) {
    if (options->path == NULL) {
        fprintf(stderr, "restore requires a backup package path\n");
        return 1;
    }
    BackupPackage package;
    if (!package_read(options->path, &package)) {
        return 1;
    }
    HidContext context;
    if (!hid_context_create(&context)) {
        package_release(&package);
        return 1;
    }
    Device devices[MAX_DEVICES];
    size_t count = 0;
    discover_devices_for_options(&context, options, devices, &count);
    Device *device = NULL;
    if (!select_device(devices, count, options, &device)) {
        hid_context_release(&context);
        package_release(&package);
        return 1;
    }
    if (package.product_id != 0 && package.product_id != device->iface->product_id) {
        fprintf(stderr, "refusing restore: backup product 0x%04X does not match connected product 0x%04X\n",
                package.product_id, device->iface->product_id);
        hid_context_release(&context);
        package_release(&package);
        return 1;
    }
    ProfileInfo info;
    if (!get_profile_info(device, &info)) {
        hid_context_release(&context);
        package_release(&package);
        return 1;
    }
    if (package.size != info.sector_size || package.profile_format != info.profile_format) {
        fprintf(stderr, "refusing restore: backup format/sector size (0x%02X/%u) does not match device (0x%02X/%u)\n",
                package.profile_format, package.size, info.profile_format, info.sector_size);
        hid_context_release(&context);
        package_release(&package);
        return 1;
    }
    uint8_t *control = (uint8_t *)malloc(info.sector_size);
    if (control == NULL) {
        hid_context_release(&context);
        package_release(&package);
        return 1;
    }
    uint16_t control_sector = 0;
    if (!read_profile_control(device, &info, &control_sector, control, info.sector_size)) {
        free(control);
        hid_context_release(&context);
        package_release(&package);
        return 1;
    }
    ProfileHeader headers[MAX_HEADERS];
    size_t header_count = 0;
    size_t selected = 0;
    bool found = package.sector == control_sector;
    if (!found) {
        if (!parse_profile_headers(&info, control, info.sector_size, headers, &header_count)) {
            free(control);
            hid_context_release(&context);
            package_release(&package);
            return 1;
        }
        for (size_t i = 0; i < header_count; i++) {
            if (headers[i].sector == package.sector) {
                selected = i;
                found = true;
                break;
            }
        }
    }
    if (!found) {
        fprintf(stderr, "refusing restore: sector 0x%04X is not present in the connected device's profile headers\n", package.sector);
        free(control);
        hid_context_release(&context);
        package_release(&package);
        return 1;
    }
    free(control);
    uint8_t *current = (uint8_t *)malloc(info.sector_size);
    if (current == NULL || !read_sector(device, package.sector, info.sector_size, current)) {
        fprintf(stderr, "could not read the current target sector before restore\n");
        free(current);
        hid_context_release(&context);
        package_release(&package);
        return 1;
    }
    printf("Restore target: %s, sector 0x%04X, %u bytes\n", device_label(device), package.sector, package.size);
    printf("Backup CRC: OK; current CRC: %s\n", sector_crc_ok(current, info.sector_size) ? "OK" : "INVALID");
    printf("The backup was made for device 0x%04X via device number 0x%02X; connected product is 0x%04X via 0x%02X.\n",
           package.product_id, package.device_number, device->iface->product_id, device->device_number);
    if (memcmp(current, package.data, package.size) == 0) {
        printf("Nothing to do; the connected sector already matches the backup.\n");
        free(current);
        hid_context_release(&context);
        package_release(&package);
        return 0;
    }
    if (!options->yes) {
        free(current);
        hid_context_release(&context);
        package_release(&package);
        return ensure_write_confirmation("restore");
    }

    Profile pre_restore;
    memset(&pre_restore, 0, sizeof(pre_restore));
    pre_restore.info = info;
    pre_restore.headers[0].sector = package.sector;
    pre_restore.headers[0].enabled = package.sector == control_sector ? 1 : headers[selected].enabled;
    pre_restore.selected_header = 0;
    pre_restore.data = current;
    pre_restore.data_length = info.sector_size;
    char pre_restore_path[512];
    snprintf(pre_restore_path, sizeof(pre_restore_path), "%s.pre-restore.bin", options->path);
    if (!package_write(pre_restore_path, device, &pre_restore, current, false)) {
        fprintf(stderr, "could not save the pre-restore sector; no mouse write was attempted\n");
        free(current);
        hid_context_release(&context);
        package_release(&package);
        return 1;
    }
    printf("Saved pre-restore state to %s\n", pre_restore_path);
    if (!write_sector(device, package.sector, package.data, package.size)) {
        fprintf(stderr, "restore write failed; pre-restore state is at %s\n", pre_restore_path);
        free(current);
        hid_context_release(&context);
        package_release(&package);
        return 1;
    }
    uint8_t *readback = (uint8_t *)malloc(package.size);
    bool readback_ok = readback != NULL && read_sector(device, package.sector, package.size, readback);
    bool verified = readback_ok && sector_crc_ok(readback, package.size) && memcmp(readback, package.data, package.size) == 0;
    if (!verified) {
        fprintf(stderr, "restore read-back verification failed; pre-restore state is at %s\n", pre_restore_path);
        free(readback);
        free(current);
        hid_context_release(&context);
        package_release(&package);
        return 1;
    }
    printf("Restored sector 0x%04X and verified an exact read-back match.\n", package.sector);
    free(readback);
    free(current);
    hid_context_release(&context);
    package_release(&package);
    return 0;
}
