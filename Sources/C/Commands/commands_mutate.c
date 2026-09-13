#include "internal.h"

bool dpi_value_in_list(const uint16_t *values, size_t count, uint16_t wanted) {
    for (size_t i = 0; i < count; i++) {
        if (values[i] == wanted) {
            return true;
        }
    }
    return false;
}

int run_set_dpi(const Options *options) {
    if (options->positional_count != 1) {
        fprintf(stderr, "set-dpi requires one to five comma-separated values, e.g. 800,1600\n");
        return 1;
    }
    uint16_t requested[5];
    size_t requested_count = 0;
    if (!parse_dpi_values(options->positionals[0], requested, &requested_count)) {
        fprintf(stderr,
                "invalid DPI list; use one to five comma-separated values from 100 to 65535\n");
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
    if (!adjustable_dpi_values(device, supported, &supported_count, MAX_DPI_VALUES, &sensor_count,
                               NULL)) {
        fprintf(stderr, "adjustable DPI feature 0x2201 is unavailable or unreadable\n");
        hid_context_release(&context);
        return 1;
    }
    if (sensor_count != 1) {
        fprintf(stderr,
                "refusing to edit onboard DPI: this device reports %u sensors; only one-sensor "
                "layouts are supported\n",
                sensor_count);
        hid_context_release(&context);
        return 1;
    }
    for (size_t i = 0; i < requested_count; i++) {
        if (!dpi_value_in_list(supported, supported_count, requested[i])) {
            fprintf(
                stderr,
                "refusing to edit onboard DPI: %u is not reported as a supported sensor value\n",
                requested[i]);
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
        fprintf(stderr,
                "refusing to choose a profile implicitly: this device has %zu profile slots. Use "
                "`--profile N`.\n",
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
    int default_index =
        options->dpi_default >= 0 ? options->dpi_default : profile.dpi_default_index + 1;
    int shift_index = options->dpi_shift >= 0 ? options->dpi_shift : profile.dpi_shift_index + 1;
    if (default_index < 1 || default_index > (int)requested_count || shift_index < 1 ||
        shift_index > (int)requested_count) {
        fprintf(stderr, "DPI indexes must be within the active stage count (1..%zu)\n",
                requested_count);
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
    printf(" (active %zu of 5, default %d, shift %d)\n", requested_count, default_index,
           shift_index);
    if (!options->yes) {
        free(profile.data);
        hid_context_release(&context);
        return ensure_write_confirmation("set-dpi");
    }
    if (!ensure_onboard_mode_for_write(device)) {
        free(profile.data);
        hid_context_release(&context);
        return 1;
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
    if (!write_dpi_stage_table(new_data, &profile, requested, requested_count)) {
        fprintf(stderr, "refusing to write: could not prepare the validated DPI table\n");
        free(new_data);
        free(profile.data);
        hid_context_release(&context);
        return 1;
    }
    new_data[1] = (uint8_t)(default_index - 1);
    new_data[2] = (uint8_t)(shift_index - 1);
    sector_put_crc(new_data, profile.data_length);
    bool written = write_sector(device, profile.headers[profile.selected_header].sector, new_data,
                                profile.data_length);
    bool verified =
        written && verify_sector_readback(device, profile.headers[profile.selected_header].sector,
                                          new_data, profile.data_length);
    if (!verified) {
        fprintf(stderr, "DPI write/readback verification failed; restore from %s\n", backup_path);
        free(new_data);
        free(profile.data);
        hid_context_release(&context);
        return 1;
    }
    printf("Verified: DPI profile readback CRC is OK and the complete sector matches.\n");
    sync_active_profile_default_dpi(device, (int)profile.selected_header + 1, default_index,
                                    requested[default_index - 1]);
    free(new_data);
    free(profile.data);
    hid_context_release(&context);
    return 0;
}

int run_set_profile_state(const Options *options) {
    if (options->positional_count != 2) {
        fprintf(stderr, "set-profile-state syntax: set-profile-state N enable|disable\n");
        return 1;
    }
    char *end = NULL;
    errno = 0;
    long requested_profile = strtol(options->positionals[0], &end, 10);
    if (errno != 0 || end == options->positionals[0] || *end != '\0' || requested_profile < 1 ||
        requested_profile > MAX_HEADERS) {
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
        fprintf(stderr, "refusing to edit profile state: the control sector or profile headers "
                        "were not validated\n");
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
        printf("Profile %ld is already %s; no control-sector write is needed.\n", requested_profile,
               enable ? "enabled" : "disabled");
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

    printf("Device: %s, profile %ld, control sector 0x%04X\n", device_label(device),
           requested_profile, control_sector);
    printf("Planned profile state: %s -> %s\n", was_enabled ? "enabled" : "disabled",
           enable ? "enabled" : "disabled");
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
    if (!ensure_onboard_mode_for_write(device)) {
        free(control);
        hid_context_release(&context);
        return 1;
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
        fprintf(stderr,
                "refusing to write: profile header is outside the validated control sector\n");
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
    bool verified = verify_sector_readback(device, control_sector, new_control, info.sector_size);
    if (!verified) {
        fprintf(stderr, "profile-state read-back verification failed; restore from %s\n",
                backup_path);
        free(new_control);
        free(control);
        hid_context_release(&context);
        return 1;
    }
    printf("Verified: profile control-sector CRC is OK and the complete sector matches.\n");
    free(new_control);
    free(control);
    hid_context_release(&context);
    return 0;
}

bool parse_batch_raw_record(const char *text, uint8_t spec[4]) {
    if (text == NULL || strlen(text) != 8) {
        return false;
    }
    for (size_t i = 0; i < 4; i++) {
        char pair[3] = {text[i * 2], text[i * 2 + 1], '\0'};
        char *end = NULL;
        errno = 0;
        unsigned long value = strtoul(pair, &end, 16);
        if (errno != 0 || end == pair || *end != '\0' || value > 0xFF) {
            return false;
        }
        spec[i] = (uint8_t)value;
    }
    return true;
}

bool parse_batch_button_change(const char *text, int *button, bool *gshift, uint8_t spec[4]) {
    if (text == NULL) {
        return false;
    }
    const char *payload = text;
    if (strncmp(payload, "gshift:", 7) == 0) {
        *gshift = true;
        payload += 7;
    } else if (strncmp(payload, "normal:", 7) == 0) {
        *gshift = false;
        payload += 7;
    } else {
        return false;
    }
    const char *separator = strchr(payload, ':');
    if (separator == NULL || separator == payload || separator[1] == '\0') {
        return false;
    }
    char number_text[16];
    size_t number_length = (size_t)(separator - payload);
    if (number_length >= sizeof(number_text)) {
        return false;
    }
    memcpy(number_text, payload, number_length);
    number_text[number_length] = '\0';
    char *end = NULL;
    errno = 0;
    long number = strtol(number_text, &end, 10);
    if (errno != 0 || end == number_text || *end != '\0' || number < 1 || number > 100000) {
        return false;
    }
    if (!parse_batch_raw_record(separator + 1, spec)) {
        return false;
    }
    *button = (int)number;
    return true;
}

bool parse_batch_rgb_change(const char *text, int *zone, uint8_t color[3]) {
    if (text == NULL) {
        return false;
    }
    const char *separator = strchr(text, ':');
    if (separator == NULL || separator == text || separator[1] == '\0') {
        return false;
    }
    char number_text[16];
    size_t number_length = (size_t)(separator - text);
    if (number_length >= sizeof(number_text)) {
        return false;
    }
    memcpy(number_text, text, number_length);
    number_text[number_length] = '\0';
    char *end = NULL;
    errno = 0;
    long number = strtol(number_text, &end, 10);
    if (errno != 0 || end == number_text || *end != '\0' || number < 1 ||
        number > RGB_PROFILE_RECORD_COUNT) {
        return false;
    }
    const char *hex = separator + 1;
    if (strlen(hex) != 6) {
        return false;
    }
    for (size_t i = 0; i < 3; i++) {
        char pair[3] = {hex[i * 2], hex[i * 2 + 1], '\0'};
        char *byte_end = NULL;
        errno = 0;
        unsigned long byte_value = strtoul(pair, &byte_end, 16);
        if (errno != 0 || byte_end == pair || *byte_end != '\0' || byte_value > 0xFF) {
            return false;
        }
        color[i] = (uint8_t)byte_value;
    }
    *zone = (int)number;
    return true;
}

bool parse_batch_profile_state(const char *text, int *profile, bool *enabled) {
    if (text == NULL) {
        return false;
    }
    const char *separator = strchr(text, ':');
    if (separator == NULL || separator == text || separator[1] == '\0') {
        return false;
    }
    char number_text[16];
    size_t number_length = (size_t)(separator - text);
    if (number_length >= sizeof(number_text)) {
        return false;
    }
    memcpy(number_text, text, number_length);
    number_text[number_length] = '\0';
    char *end = NULL;
    errno = 0;
    long number = strtol(number_text, &end, 10);
    if (errno != 0 || end == number_text || *end != '\0' || number < 1 || number > MAX_HEADERS) {
        return false;
    }
    if (strcmp(separator + 1, "enable") == 0) {
        *enabled = true;
    } else if (strcmp(separator + 1, "disable") == 0) {
        *enabled = false;
    } else {
        return false;
    }
    *profile = (int)number;
    return true;
}

bool batch_operation_id_is_safe(const char *operation_id) {
    if (operation_id == NULL || *operation_id == '\0' || strlen(operation_id) >= 96) {
        return false;
    }
    for (const char *cursor = operation_id; *cursor != '\0'; cursor++) {
        if (!(isalnum((unsigned char)*cursor) || *cursor == '-' || *cursor == '_' ||
              *cursor == '.')) {
            return false;
        }
    }
    return true;
}

bool make_batch_backup_path(const char *directory, const char *operation_id, char path[512]) {
    const char *base = directory == NULL || *directory == '\0' ? "." : directory;
    int length = snprintf(path, 512, "%s/%s.logiob", base, operation_id);
    return length > 0 && length < 512;
}

bool batch_sector_changed(const uint8_t *before, const uint8_t *after, size_t length) {
    return before != NULL && after != NULL && memcmp(before, after, length) != 0;
}

size_t batch_affected_sector_count(bool profile_changed, bool control_changed) {
    return (profile_changed ? 1U : 0U) + (control_changed ? 1U : 0U);
}

bool execute_batch_sector_plan(const BatchSector *plan, size_t plan_count, BatchSectorWriter writer,
                               void *context, size_t *verified_count, size_t *failed_index) {
    *verified_count = 0;
    for (size_t i = 0; i < plan_count; i++) {
        if (!writer(context, &plan[i])) {
            *failed_index = i;
            return false;
        }
        (*verified_count)++;
    }
    return true;
}

void print_batch_recovery(const char *operation_id, size_t verified_count, const char *failed_kind,
                          uint16_t failed_sector, const char *backup_path, bool has_backup) {
    fprintf(stderr,
            "Save operation %s failed after %zu sector(s) were verified. "
            "%s sector 0x%04X was not verified. Restore from the exact backups "
            "created for this operation:\n",
            operation_id, verified_count, failed_kind, failed_sector);
    if (has_backup) {
        fprintf(stderr, "  %s\n", backup_path);
    }
}

static bool write_batch_sector_and_verify(Device *device, uint16_t sector, const uint8_t *data,
                                          size_t length, const char *kind) {
    printf("Writing %s sector 0x%04X\n", kind, sector);
    if (!write_sector(device, sector, data, length)) {
        return false;
    }
    bool verified = verify_sector_readback(device, sector, data, length);
    if (!verified) {
        return false;
    }
    printf("Verified sector 0x%04X (%s): CRC is OK and the complete sector matches.\n", sector,
           kind);
    return true;
}

static bool write_batch_sector_with_device(void *context, const BatchSector *sector) {
    return write_batch_sector_and_verify((Device *)context, sector->sector, sector->data,
                                         sector->length, sector->kind);
}

int run_apply(const Options *options) {
    if (options->profile < 1) {
        fprintf(stderr, "apply requires an explicit --profile N selection\n");
        return 1;
    }
    uint32_t requested_report_rate = 0;
    if (options->report_rate != NULL &&
        !parse_report_rate_hertz(options->report_rate, &requested_report_rate)) {
        fprintf(stderr, "invalid --report-rate; use a positive integer rate in Hz\n");
        return 1;
    }
    if (options->button_change_count == 0 && options->rgb_change_count == 0 &&
        options->dpi_values == NULL && options->profile_state_change_count == 0 &&
        options->report_rate == NULL) {
        fprintf(stderr, "apply requires at least one button, RGB, DPI, polling-rate, or "
                        "profile-state change\n");
        return 1;
    }
    if (options->dpi_values == NULL && (options->dpi_default >= 0 || options->dpi_shift >= 0)) {
        fprintf(stderr, "--default and --shift require --dpi for apply\n");
        return 1;
    }

    int requested_buttons[MAX_BATCH_BUTTON_CHANGES];
    bool requested_gshift[MAX_BATCH_BUTTON_CHANGES];
    uint8_t requested_specs[MAX_BATCH_BUTTON_CHANGES][4];
    for (size_t i = 0; i < options->button_change_count; i++) {
        if (!parse_batch_button_change(options->button_changes[i], &requested_buttons[i],
                                       &requested_gshift[i], requested_specs[i])) {
            fprintf(stderr,
                    "invalid --button-change '%s'; use normal:N:8-hex-digit-raw-record or "
                    "gshift:N:8-hex-digit-raw-record\n",
                    options->button_changes[i]);
            return 1;
        }
        for (size_t previous = 0; previous < i; previous++) {
            if (requested_buttons[previous] == requested_buttons[i] &&
                requested_gshift[previous] == requested_gshift[i]) {
                fprintf(stderr, "duplicate --button-change for %sbutton %d\n",
                        requested_gshift[i] ? "G-Shift " : "", requested_buttons[i]);
                return 1;
            }
        }
        if (!spec_structurally_valid(requested_specs[i])) {
            fprintf(stderr, "invalid --button-change record for button %d\n", requested_buttons[i]);
            return 1;
        }
    }

    int requested_rgb_zones[MAX_BATCH_RGB_CHANGES];
    uint8_t requested_rgb_colors[MAX_BATCH_RGB_CHANGES][3];
    for (size_t i = 0; i < options->rgb_change_count; i++) {
        if (!parse_batch_rgb_change(options->rgb_changes[i], &requested_rgb_zones[i],
                                    requested_rgb_colors[i])) {
            fprintf(stderr, "invalid --rgb-change '%s'; use N:RRGGBB with a 1-based zone number\n",
                    options->rgb_changes[i]);
            return 1;
        }
        for (size_t previous = 0; previous < i; previous++) {
            if (requested_rgb_zones[previous] == requested_rgb_zones[i]) {
                fprintf(stderr, "duplicate --rgb-change for zone %d\n", requested_rgb_zones[i]);
                return 1;
            }
        }
    }

    int requested_states[MAX_BATCH_PROFILE_CHANGES];
    bool requested_enabled[MAX_BATCH_PROFILE_CHANGES];
    for (size_t i = 0; i < options->profile_state_change_count; i++) {
        if (!parse_batch_profile_state(options->profile_state_changes[i], &requested_states[i],
                                       &requested_enabled[i])) {
            fprintf(stderr, "invalid --profile-state-change '%s'; use N:enable or N:disable\n",
                    options->profile_state_changes[i]);
            return 1;
        }
        for (size_t previous = 0; previous < i; previous++) {
            if (requested_states[previous] == requested_states[i]) {
                fprintf(stderr, "duplicate --profile-state-change for profile %d\n",
                        requested_states[i]);
                return 1;
            }
        }
    }

    uint16_t requested_dpi[5] = {0};
    size_t requested_dpi_count = 0;
    if (options->dpi_values != NULL &&
        (!parse_dpi_values(options->dpi_values, requested_dpi, &requested_dpi_count) ||
         requested_dpi_count < 1 || requested_dpi_count > 5)) {
        fprintf(stderr,
                "invalid --dpi list; use one to five comma-separated values from 100 to 65535\n");
        return 1;
    }
    for (size_t i = 1; i < requested_dpi_count; i++) {
        if (requested_dpi[i] <= requested_dpi[i - 1]) {
            fprintf(stderr, "refusing to edit onboard DPI: stages must be strictly increasing\n");
            return 1;
        }
    }

    char generated_operation_id[96];
    if (options->operation_id == NULL) {
        time_t now = time(NULL);
        struct tm local_time;
        localtime_r(&now, &local_time);
        char stamp[64];
        strftime(stamp, sizeof(stamp), "%Y%m%d-%H%M%S", &local_time);
        snprintf(generated_operation_id, sizeof(generated_operation_id), "lope-%s-%ld", stamp,
                 (long)getpid());
    }
    const char *operation_id =
        options->operation_id == NULL ? generated_operation_id : options->operation_id;
    if (!batch_operation_id_is_safe(operation_id)) {
        fprintf(stderr, "invalid --operation-id; use only letters, numbers, '.', '-' or '_'\n");
        return 1;
    }

    HidContext context;
    bool context_ready = false;
    Device *device = NULL;
    ProfileInfo info;
    ProfileHeader headers[MAX_HEADERS];
    size_t header_count = 0;
    uint16_t control_sector = 0;
    uint8_t *control = NULL;
    uint8_t *new_control = NULL;
    Profile profile;
    uint8_t *new_profile = NULL;
    bool profile_affected = false;
    bool control_affected = false;
    int dpi_default_stage = -1;
    uint16_t dpi_default_value = 0;
    bool has_backup = false;
    char backup_path[512] = {0};
    BackupSectorSource backup_sectors[2];
    size_t backup_sector_count = 0;
    BatchSector plan[2];
    size_t plan_count = 0;
    size_t failed_index = 0;
    size_t verified_count = 0;
    int result = 1;
    memset(&context, 0, sizeof(context));
    memset(&info, 0, sizeof(info));
    memset(headers, 0, sizeof(headers));
    memset(&profile, 0, sizeof(profile));

    if (!hid_context_create(&context)) {
        return 1;
    }
    context_ready = true;
    Device devices[MAX_DEVICES];
    size_t device_count = 0;
    discover_devices_for_options(&context, options, devices, &device_count);
    if (!select_device(devices, device_count, options, &device)) {
        goto done;
    }
    if (is_g600_device(device)) {
        if (options->report_rate != NULL) {
            fprintf(stderr, "refusing to apply: G600 profile reports do not support saved "
                            "polling-rate edits\n");
            goto done;
        }
        result = run_g600_apply(options, device, requested_buttons, requested_gshift,
                                requested_specs, options->button_change_count, operation_id);
        goto done;
    }
    if (!get_profile_info(device, &info)) {
        goto done;
    }

    // Read and validate the control sector once whenever profile-state changes
    // are requested. Otherwise the lightweight header read is enough to prove
    // that the selected profile exists before the full profile-sector read.
    if (options->profile_state_change_count > 0) {
        control = (uint8_t *)malloc(info.sector_size);
        if (control == NULL ||
            !read_profile_control(device, &info, &control_sector, control, info.sector_size) ||
            !sector_crc_ok(control, info.sector_size) ||
            !parse_profile_headers(&info, control, info.sector_size, headers, &header_count)) {
            fprintf(
                stderr,
                "refusing to apply: the profile control sector or headers were not validated\n");
            goto done;
        }
    } else if (!read_profile_headers(device, &info, headers, &header_count)) {
        fprintf(stderr, "refusing to apply: the profile headers were not readable\n");
        goto done;
    }
    if ((size_t)options->profile > header_count) {
        fprintf(stderr, "refusing to apply: profile %d is out of range 1..%zu\n", options->profile,
                header_count);
        goto done;
    }

    bool wants_profile_sector = options->button_change_count > 0 || options->rgb_change_count > 0 ||
                                options->dpi_values != NULL || options->report_rate != NULL;
    if (wants_profile_sector) {
        if (!load_profile_with_headers(device, &info, headers, header_count, options->profile,
                                       &profile) ||
            !validate_profile_for_write(&profile)) {
            free(profile.data);
            profile.data = NULL;
            goto done;
        }
        new_profile = (uint8_t *)malloc(profile.data_length);
        if (new_profile == NULL) {
            fprintf(stderr, "out of memory while preparing the profile-sector update\n");
            goto done;
        }
        memcpy(new_profile, profile.data, profile.data_length);

        if (options->report_rate != NULL) {
            if (profile.data_length < 1) {
                fprintf(stderr,
                        "refusing to apply: the selected profile has no report-rate field\n");
                goto done;
            }
            uint8_t report_rate_interval = 0;
            if (!report_rate_profile_interval(device, requested_report_rate,
                                              &report_rate_interval)) {
                goto done;
            }
            new_profile[0] = report_rate_interval;
            printf("Planned profile polling rate: %u Hz (%u ms interval)\n", requested_report_rate,
                   report_rate_interval);
        }

        for (size_t i = 0; i < options->button_change_count; i++) {
            if (requested_buttons[i] > (int)profile.info.button_count) {
                fprintf(stderr, "refusing to apply: button %d is out of range 1..%u\n",
                        requested_buttons[i], profile.info.button_count);
                goto done;
            }
            if (requested_gshift[i] && !profile.gshift_layout_supported) {
                fprintf(
                    stderr,
                    "refusing to apply: the selected profile's G-Shift layout was not validated\n");
                goto done;
            }
            size_t button_offset =
                requested_gshift[i] ? profile.gshift_button_offset : profile.button_offset;
            size_t offset = button_offset + (size_t)(requested_buttons[i] - 1) * 4;
            memcpy(new_profile + offset, requested_specs[i], 4);
        }

        if (options->rgb_change_count > 0) {
            uint8_t zones[MAX_BATCH_RGB_CHANGES];
            for (size_t i = 0; i < options->rgb_change_count; i++) {
                if (requested_rgb_zones[i] < 1 ||
                    requested_rgb_zones[i] > (int)profile.rgb_zone_count) {
                    fprintf(stderr,
                            "refusing to apply: RGB zone %d is not advertised by the validated "
                            "profile (1..%zu)\n",
                            requested_rgb_zones[i], profile.rgb_zone_count);
                    goto done;
                }
                zones[i] = (uint8_t)(requested_rgb_zones[i] - 1);
            }
            if (!profile.rgb_layout_supported ||
                !write_rgb_zone_colors(new_profile, &profile, zones, requested_rgb_colors,
                                       options->rgb_change_count)) {
                fprintf(stderr,
                        "refusing to apply: the selected profile's RGB layout was not validated\n");
                goto done;
            }
        }

        if (options->dpi_values != NULL) {
            if (!profile.dpi_layout_supported || !profile.crc_ok) {
                fprintf(stderr, "refusing to apply: the selected profile's CRC or DPI layout was "
                                "not validated\n");
                goto done;
            }
            uint16_t supported[MAX_DPI_VALUES];
            size_t supported_count = 0;
            uint8_t sensor_count = 0;
            if (!adjustable_dpi_values(device, supported, &supported_count, MAX_DPI_VALUES,
                                       &sensor_count, NULL)) {
                fprintf(stderr, "refusing to apply: adjustable DPI capability 0x2201 is "
                                "unavailable or unreadable\n");
                goto done;
            }
            if (sensor_count != 1) {
                fprintf(stderr,
                        "refusing to apply: this device reports %u sensors; only one-sensor DPI "
                        "layouts are supported\n",
                        sensor_count);
                goto done;
            }
            for (size_t i = 0; i < requested_dpi_count; i++) {
                if (!dpi_value_in_list(supported, supported_count, requested_dpi[i])) {
                    fprintf(
                        stderr,
                        "refusing to apply: %u is not reported as a supported sensor DPI value\n",
                        requested_dpi[i]);
                    goto done;
                }
            }
            int default_index = options->dpi_default >= 0 ? options->dpi_default
                                                          : (int)profile.dpi_default_index + 1;
            int shift_index =
                options->dpi_shift >= 0 ? options->dpi_shift : (int)profile.dpi_shift_index + 1;
            if (default_index < 1 || default_index > (int)requested_dpi_count || shift_index < 1 ||
                shift_index > (int)requested_dpi_count) {
                fprintf(stderr,
                        "refusing to apply: DPI indexes must be within the active stage count "
                        "(1..%zu)\n",
                        requested_dpi_count);
                goto done;
            }
            if (!write_dpi_stage_table(new_profile, &profile, requested_dpi, requested_dpi_count)) {
                fprintf(stderr, "refusing to apply: could not prepare the validated DPI table\n");
                goto done;
            }
            new_profile[1] = (uint8_t)(default_index - 1);
            new_profile[2] = (uint8_t)(shift_index - 1);
            dpi_default_stage = default_index;
            dpi_default_value = requested_dpi[default_index - 1];
        }
        sector_put_crc(new_profile, profile.data_length);
        if (!sector_crc_ok(new_profile, profile.data_length)) {
            fprintf(stderr, "refusing to apply: internal profile-sector CRC validation failed\n");
            goto done;
        }
        profile_affected = batch_sector_changed(profile.data, new_profile, profile.data_length);
    }

    if (options->profile_state_change_count > 0) {
        bool final_enabled[MAX_HEADERS] = {false};
        for (size_t i = 0; i < header_count; i++) {
            final_enabled[i] = headers[i].enabled != 0;
        }
        for (size_t i = 0; i < options->profile_state_change_count; i++) {
            if (requested_states[i] > (int)header_count) {
                fprintf(stderr, "refusing to apply: profile state %d is out of range 1..%zu\n",
                        requested_states[i], header_count);
                goto done;
            }
            final_enabled[requested_states[i] - 1] = requested_enabled[i];
        }
        bool any_enabled = false;
        for (size_t i = 0; i < header_count; i++) {
            any_enabled = any_enabled || final_enabled[i];
        }
        if (!any_enabled) {
            fprintf(stderr,
                    "refusing to apply: at least one onboard profile must remain enabled\n");
            goto done;
        }
        new_control = (uint8_t *)malloc(info.sector_size);
        if (new_control == NULL) {
            fprintf(stderr, "out of memory while preparing the profile control-sector update\n");
            goto done;
        }
        memcpy(new_control, control, info.sector_size);
        for (size_t i = 0; i < options->profile_state_change_count; i++) {
            new_control[(requested_states[i] - 1) * 4 + 2] = requested_enabled[i] ? 1 : 0;
        }
        sector_put_crc(new_control, info.sector_size);
        if (!sector_crc_ok(new_control, info.sector_size)) {
            fprintf(stderr, "refusing to apply: internal control-sector CRC validation failed\n");
            goto done;
        }
        control_affected = batch_sector_changed(control, new_control, info.sector_size);
    }

    if (!profile_affected && !control_affected) {
        printf("Save operation %s has no effective changes; no sectors were written.\n",
               operation_id);
        result = 0;
        goto done;
    }

    printf("Save operation: %s\n", operation_id);
    printf("Preflight complete: %zu sector(s) will be written at most once.\n",
           batch_affected_sector_count(profile_affected, control_affected));
    if (profile_affected) {
        printf("Planned profile sector: 0x%04X\n", profile.headers[profile.selected_header].sector);
    }
    if (control_affected) {
        printf("Planned control sector: 0x%04X\n", control_sector);
    }
    if (!options->yes) {
        result = ensure_write_confirmation("apply");
        goto done;
    }
    if (!ensure_onboard_mode_for_write(device)) {
        goto done;
    }

    if (profile_affected) {
        backup_sectors[backup_sector_count++] =
            (BackupSectorSource){.sector = profile.headers[profile.selected_header].sector,
                                 .size = profile.data_length,
                                 .data = profile.data};
    }
    if (control_affected) {
        backup_sectors[backup_sector_count++] = (BackupSectorSource){
            .sector = control_sector, .size = info.sector_size, .data = control};
    }
    if (!make_batch_backup_path(options->backup_directory, operation_id, backup_path)) {
        fprintf(stderr, "could not create a backup path for save operation %s\n", operation_id);
        goto done;
    }
    if (!package_write_multi(backup_path, device, info.profile_format, backup_sectors,
                             backup_sector_count, true)) {
        fprintf(stderr,
                "save operation %s stopped before any sector write; the combined backup could not "
                "be created\n",
                operation_id);
        goto done;
    }
    has_backup = true;
    printf("Backup saved: %s (%zu exact sector snapshot(s))\n", backup_path, backup_sector_count);

    if (profile_affected) {
        plan[plan_count++] =
            (BatchSector){.sector = profile.headers[profile.selected_header].sector,
                          .data = new_profile,
                          .length = profile.data_length,
                          .kind = "profile"};
    }
    if (control_affected) {
        plan[plan_count++] = (BatchSector){.sector = control_sector,
                                           .data = new_control,
                                           .length = info.sector_size,
                                           .kind = "control"};
    }
    if (!execute_batch_sector_plan(plan, plan_count, write_batch_sector_with_device, device,
                                   &verified_count, &failed_index)) {
        print_batch_recovery(operation_id, verified_count, plan[failed_index].kind,
                             plan[failed_index].sector, backup_path, has_backup);
        goto done;
    }
    if (profile_affected && options->dpi_values != NULL && dpi_default_stage > 0) {
        sync_active_profile_default_dpi(device, options->profile, dpi_default_stage,
                                        dpi_default_value);
    }
    printf("Save operation %s complete: wrote %zu sector(s); every write was read back and "
           "verified.\n",
           operation_id, verified_count);
    result = 0;

done:
    free(new_profile);
    free(profile.data);
    free(new_control);
    free(control);
    if (context_ready) {
        hid_context_release(&context);
    }
    return result;
}
