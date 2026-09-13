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
