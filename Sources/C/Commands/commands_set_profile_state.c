#include "internal.h"

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
