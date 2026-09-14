// G600 legacy feature-report support.
//
// The G600 predates the HID++ 0x8100 onboard-profile transport used by the
// other writable mice in this project. Its three profile reports are fixed
// 154-byte feature reports with 20 three-byte button records in two banks.

#include "g600.h"
#include "backup.h"
#include "hid_discovery.h"
#include "profile_io.h"
#include "hid_transport.h"

#include <stdio.h>
#include <string.h>

G600FeatureReportGetFn g600_get_feature_report_impl = channel_get_feature_report;
G600FeatureReportSetFn g600_set_feature_report_impl = channel_set_feature_report;

bool is_g600_device(const Device *device) {
    return device != NULL && device->iface != NULL &&
           (device->iface->product_id == G600_PRODUCT_ID ||
            text_contains_case_insensitive(device->iface->product, "G600"));
}

bool g600_profile_report_id(int profile_number, uint8_t *report_id) {
    if (profile_number < 1 || profile_number > G600_PROFILE_COUNT) {
        return false;
    }
    if (report_id != NULL) {
        *report_id = (uint8_t)(G600_FIRST_PROFILE_REPORT + profile_number - 1);
    }
    return true;
}

uint16_t g600_profile_sector(int profile_number) {
    uint8_t report_id = 0;
    return g600_profile_report_id(profile_number, &report_id) ? report_id : 0;
}

bool g600_read_profile(Device *device, int profile_number, uint8_t report[G600_REPORT_BYTES]) {
    uint8_t report_id = 0;
    if (!is_g600_device(device) || !g600_profile_report_id(profile_number, &report_id)) {
        return false;
    }
    size_t length = 0;
    if (!g600_get_feature_report_impl(&device->iface->channel, report_id, report, G600_REPORT_BYTES,
                                      &length) ||
        length < G600_REPORT_BYTES || report[0] != report_id) {
        fprintf(stderr, "could not read G600 profile %d feature report 0x%02X\n", profile_number,
                report_id);
        return false;
    }
    return true;
}

bool g600_write_profile(Device *device, int profile_number, uint8_t report[G600_REPORT_BYTES]) {
    uint8_t report_id = 0;
    if (!is_g600_device(device) || !g600_profile_report_id(profile_number, &report_id) ||
        report[0] != report_id) {
        return false;
    }
    return g600_set_feature_report_impl(&device->iface->channel, report_id, report,
                                        G600_REPORT_BYTES);
}

void g600_native_to_spec(const uint8_t native[3], uint8_t spec[4]) {
    uint8_t code = native[0];
    if (code == 0 && native[1] == 0 && native[2] == 0) {
        memset(spec, 0xFF, 4);
        return;
    }
    if (code == 0) {
        spec[0] = 0x80;
        spec[1] = 0x02;
        spec[2] = native[1];
        spec[3] = native[2];
        return;
    }
    if (code >= 1 && code <= 5) {
        spec[0] = 0x80;
        spec[1] = 0x01;
        spec[2] = 0x00;
        spec[3] = (uint8_t)(1U << (code - 1));
        return;
    }
    switch (code) {
    case 0x11:
        spec[0] = 0x90;
        spec[1] = 0x03;
        spec[2] = 0x00;
        spec[3] = 0x00;
        return;
    case 0x12:
        spec[0] = 0x90;
        spec[1] = 0x04;
        spec[2] = 0x00;
        spec[3] = 0x00;
        return;
    case 0x13:
        spec[0] = 0x90;
        spec[1] = 0x05;
        spec[2] = 0x00;
        spec[3] = 0x00;
        return;
    case 0x14:
        spec[0] = 0x90;
        spec[1] = 0x0A;
        spec[2] = 0x00;
        spec[3] = 0x00;
        return;
    case 0x15:
        spec[0] = 0x90;
        spec[1] = 0x07;
        spec[2] = 0x00;
        spec[3] = 0x00;
        return;
    case 0x17:
        spec[0] = 0x90;
        spec[1] = 0x0B;
        spec[2] = 0x00;
        spec[3] = 0x00;
        return;
    default:
        // Preserve an otherwise unknown legacy function as a consumer-like
        // extension that this writer can round-trip without guessing its
        // meaning. The UI still presents the raw record for that case.
        spec[0] = 0x80;
        spec[1] = 0x03;
        spec[2] = 0x00;
        spec[3] = code;
        return;
    }
}

bool g600_spec_to_native(const uint8_t spec[4], uint8_t native[3]) {
    if (spec_is_disabled(spec)) {
        memset(native, 0, 3);
        return true;
    }
    if (spec[0] == 0x80 && spec[1] == 0x02) {
        native[0] = 0;
        native[1] = spec[2];
        native[2] = spec[3];
        return true;
    }
    if (spec[0] == 0x80 && spec[1] == 0x01 && spec[2] == 0x00) {
        switch (spec[3]) {
        case 0x01:
            native[0] = 1;
            break;
        case 0x02:
            native[0] = 2;
            break;
        case 0x04:
            native[0] = 3;
            break;
        case 0x08:
            native[0] = 4;
            break;
        case 0x10:
            native[0] = 5;
            break;
        default:
            return false;
        }
        native[1] = 0;
        native[2] = 0;
        return true;
    }
    if (spec[0] == 0x80 && spec[1] == 0x03 && spec[2] == 0x00) {
        switch (spec[3]) {
        case 0x11:
        case 0x12:
        case 0x13:
        case 0x14:
        case 0x15:
        case 0x17:
            native[0] = spec[3];
            native[1] = 0;
            native[2] = 0;
            return true;
        default:
            return false;
        }
    }
    if (spec[0] == 0x90 && spec[2] == 0x00 && spec[3] == 0x00) {
        switch (spec[1]) {
        case 0x03:
            native[0] = 0x11;
            break;
        case 0x04:
            native[0] = 0x12;
            break;
        case 0x05:
            native[0] = 0x13;
            break;
        case 0x0A:
            native[0] = 0x14;
            break;
        case 0x07:
            native[0] = 0x15;
            break;
        case 0x0B:
            native[0] = 0x17;
            break;
        default:
            return false;
        }
        native[1] = 0;
        native[2] = 0;
        return true;
    }
    return false;
}

void g600_describe_native(const uint8_t native[3], char *out, size_t out_size) {
    if (native[0] == 0 && native[1] == 0 && native[2] == 0) {
        snprintf(out, out_size, "disabled");
        return;
    }
    if (native[0] == 0) {
        snprintf(out, out_size, "keyboard chord (mod 0x%02X key 0x%02X)", native[1], native[2]);
        return;
    }
    switch (native[0]) {
    case 1:
        snprintf(out, out_size, "Left click");
        return;
    case 2:
        snprintf(out, out_size, "Right click");
        return;
    case 3:
        snprintf(out, out_size, "Middle click");
        return;
    case 4:
        snprintf(out, out_size, "Back / rear thumb");
        return;
    case 5:
        snprintf(out, out_size, "Forward");
        return;
    case 0x11:
        snprintf(out, out_size, "next DPI");
        return;
    case 0x12:
        snprintf(out, out_size, "previous DPI");
        return;
    case 0x13:
        snprintf(out, out_size, "cycle DPI");
        return;
    case 0x14:
        snprintf(out, out_size, "cycle profile");
        return;
    case 0x15:
        snprintf(out, out_size, "shift DPI");
        return;
    case 0x17:
        snprintf(out, out_size, "G-Shift");
        return;
    default:
        snprintf(out, out_size, "G600 function 0x%02X", native[0]);
        return;
    }
}

void g600_print_hex4(const uint8_t bytes[4]) {
    printf("%02X %02X %02X %02X", bytes[0], bytes[1], bytes[2], bytes[3]);
}

void g600_print_profile_summary(int profile_number, const uint8_t report[G600_REPORT_BYTES],
                                bool show_buttons) {
    uint8_t report_id = report[0];
    printf("Profile %d (sector 0x%04X, enabled=yes)\n", profile_number,
           g600_profile_sector(profile_number));
    printf("  format: 0x%02X, macro format: 0x00, profiles: %d, buttons: %d, sectors: %d, sector "
           "bytes: %d\n",
           G600_BACKUP_PROFILE_FORMAT, G600_PROFILE_COUNT, G600_BUTTON_COUNT, G600_PROFILE_COUNT,
           G600_REPORT_BYTES);
    printf("  CRC: NOT_APPLICABLE (legacy feature report)\n");
    printf("  DPI stages: not recognized; stage editing is disabled\n");
    printf("  button array: offset %d (20/20 structurally valid, 20 recognized)\n",
           G600_NORMAL_BUTTON_OFFSET);
    printf("  G-Shift layout: supported (legacy feature report 0x%02X; offset %d; 20/20 "
           "structurally valid, 20 recognized)\n",
           report_id, G600_GSHIFT_BUTTON_OFFSET);
    if (!show_buttons) {
        return;
    }
    for (size_t i = 0; i < G600_BUTTON_COUNT; i++) {
        uint8_t spec[4];
        char description[160];
        g600_native_to_spec(report + G600_NORMAL_BUTTON_OFFSET + i * 3, spec);
        g600_describe_native(report + G600_NORMAL_BUTTON_OFFSET + i * 3, description,
                             sizeof(description));
        printf("  button %zu: %-30s [", i + 1, description);
        g600_print_hex4(spec);
        printf("]\n");

        g600_native_to_spec(report + G600_GSHIFT_BUTTON_OFFSET + i * 3, spec);
        g600_describe_native(report + G600_GSHIFT_BUTTON_OFFSET + i * 3, description,
                             sizeof(description));
        printf("  G-Shift button %zu: %-24s [", i + 1, description);
        g600_print_hex4(spec);
        printf("]\n");
    }
}

int run_g600_info(const Options *options, Device *device) {
    int profile_number = options->profile > 0 ? options->profile : 1;
    if (!g600_profile_report_id(profile_number, NULL)) {
        fprintf(stderr, "G600 profile %d is out of range 1..%d\n", profile_number,
                G600_PROFILE_COUNT);
        return 1;
    }
    uint8_t report[G600_REPORT_BYTES];
    if (!g600_read_profile(device, profile_number, report)) {
        return 1;
    }
    printf("  onboard profiles: legacy G600 feature reports\n");
    printf("  onboard descriptor: 3 profiles, 20 buttons, 154-byte feature reports\n");
    printf("  G-Shift: supported (separate 20-button bank in every profile)\n");
    g600_print_profile_summary(profile_number, report, true);
    return 0;
}

int run_g600_profiles(const Options *options, Device *device) {
    if (options->profile > G600_PROFILE_COUNT) {
        fprintf(stderr, "profile %d is out of range 1..%d\n", options->profile, G600_PROFILE_COUNT);
        return 1;
    }
    printf("Onboard profiles for %s:\n", device_label(device));
    printf("Profile capacity: %d\n", G600_PROFILE_COUNT);
    for (int profile = 1; profile <= G600_PROFILE_COUNT; profile++) {
        printf("Profile %d (sector 0x%04X, enabled=yes)\n", profile, g600_profile_sector(profile));
    }
    if (options->headers_only && !options->include_dpi) {
        return 0;
    }

    int selected = options->profile > 0 ? options->profile : 1;
    if (options->include_dpi) {
        printf("Selected profile: %d\n", selected);
        uint8_t report[G600_REPORT_BYTES];
        if (!g600_read_profile(device, selected, report)) {
            return 1;
        }
        g600_print_profile_summary(selected, report, true);
        printf("Device: %s\n", device_label(device));
        printf("DPI error: G600 DPI stages are outside the legacy button-layer writer\n");
        return 0;
    }

    int first = options->profile > 0 ? options->profile : 1;
    int last = options->profile > 0 ? options->profile : G600_PROFILE_COUNT;
    for (int profile = first; profile <= last; profile++) {
        uint8_t report[G600_REPORT_BYTES];
        if (g600_read_profile(device, profile, report)) {
            g600_print_profile_summary(profile, report, true);
        }
    }
    return 0;
}

bool g600_make_backup_path(const Options *options, const char *operation_id, char path[512]) {
    const char *base = options->backup_directory == NULL || *options->backup_directory == '\0'
                           ? "."
                           : options->backup_directory;
    int length = snprintf(path, 512, "%s/%s.logiob", base,
                          operation_id == NULL ? "g600-save" : operation_id);
    return length > 0 && length < 512;
}

int run_g600_apply(const Options *options, Device *device, const int *requested_buttons,
                   const bool *requested_gshift, const uint8_t requested_specs[][4],
                   size_t requested_count, const char *operation_id) {
    if (options->rgb_change_count > 0 || options->dpi_values != NULL ||
        options->profile_state_change_count > 0) {
        fprintf(stderr,
                "G600 apply currently supports button and G-Shift assignments only; DPI, RGB, and "
                "profile-state writes are not part of its legacy feature reports\n");
        return 1;
    }
    uint8_t report[G600_REPORT_BYTES];
    uint8_t updated[G600_REPORT_BYTES];
    if (!g600_read_profile(device, options->profile, report)) {
        return 1;
    }
    memcpy(updated, report, sizeof(updated));
    for (size_t i = 0; i < requested_count; i++) {
        if (requested_buttons[i] < 1 || requested_buttons[i] > G600_BUTTON_COUNT) {
            fprintf(stderr, "refusing to apply: G600 button %d is out of range 1..%d\n",
                    requested_buttons[i], G600_BUTTON_COUNT);
            return 1;
        }
        uint8_t native[3];
        if (!g600_spec_to_native(requested_specs[i], native)) {
            fprintf(stderr,
                    "refusing to apply: raw record for G600 button %d is not supported by its "
                    "native mapping\n",
                    requested_buttons[i]);
            return 1;
        }
        size_t offset = requested_gshift[i] ? G600_GSHIFT_BUTTON_OFFSET : G600_NORMAL_BUTTON_OFFSET;
        memcpy(updated + offset + (size_t)(requested_buttons[i] - 1) * 3, native, 3);
    }
    if (memcmp(report, updated, sizeof(report)) == 0) {
        printf("Save operation %s has no effective changes; no G600 feature report was written.\n",
               operation_id == NULL ? "g600-save" : operation_id);
        return 0;
    }

    operation_id = operation_id == NULL ? "g600-save" : operation_id;
    printf("Save operation: %s\n", operation_id);
    printf("Preflight complete: 1 G600 feature report will be written at most once.\n");
    printf("Planned profile report: 0x%02X (profile %d)\n", report[0], options->profile);
    if (!options->yes) {
        return ensure_write_confirmation("apply");
    }

    char backup_path[512];
    if (!g600_make_backup_path(options, operation_id, backup_path)) {
        fprintf(stderr, "could not create a backup path for save operation %s\n", operation_id);
        return 1;
    }
    BackupSectorSource backup = {
        .sector = g600_profile_sector(options->profile), .size = G600_REPORT_BYTES, .data = report};
    if (!package_write_multi(backup_path, device, G600_BACKUP_PROFILE_FORMAT, &backup, 1, true)) {
        fprintf(stderr,
                "save operation %s stopped before any G600 write; the exact backup could not be "
                "created\n",
                operation_id);
        return 1;
    }
    printf("Backup saved: %s (1 exact G600 profile snapshot)\n", backup_path);
    printf("Writing G600 profile report 0x%02X\n", report[0]);
    if (!g600_write_profile(device, options->profile, updated)) {
        fprintf(
            stderr,
            "save operation %s failed while writing G600 profile report 0x%02X; backup is at %s\n",
            operation_id, report[0], backup_path);
        return 1;
    }
    uint8_t verified[G600_REPORT_BYTES];
    if (!g600_read_profile(device, options->profile, verified) ||
        memcmp(updated, verified, sizeof(updated)) != 0) {
        fprintf(stderr,
                "save operation %s failed: G600 profile report 0x%02X was not verified; backup is "
                "at %s\n",
                operation_id, report[0], backup_path);
        return 1;
    }
    printf("Verified sector 0x%04X (G600 profile): complete feature report matches.\n",
           g600_profile_sector(options->profile));
    printf("Save operation %s complete: wrote 1 sector(s); the complete G600 feature report was "
           "read back and verified.\n",
           operation_id);
    return 0;
}

int run_g600_dump(const Options *options, Device *device) {
    int profile_number = options->profile > 0 ? options->profile : 1;
    uint8_t report[G600_REPORT_BYTES];
    if (!g600_read_profile(device, profile_number, report)) {
        return 1;
    }
    BackupSectorSource source = {
        .sector = g600_profile_sector(profile_number), .size = G600_REPORT_BYTES, .data = report};
    int ok =
        package_write_multi(options->path, device, G600_BACKUP_PROFILE_FORMAT, &source, 1, false);
    if (ok) {
        printf("dumped G600 profile %d report 0x%02X (%d bytes) to %s\n", profile_number, report[0],
               G600_REPORT_BYTES, options->path);
    }
    return ok ? 0 : 1;
}

int run_g600_restore(const Options *options, Device *device, const BackupPackage *package) {
    if (package->profile_format != G600_BACKUP_PROFILE_FORMAT || package->sector_count != 1 ||
        package->sectors[0].size != G600_REPORT_BYTES) {
        fprintf(stderr, "refusing G600 restore: expected one 154-byte legacy profile report\n");
        return 1;
    }
    int profile_number = (int)package->sectors[0].sector - G600_FIRST_PROFILE_REPORT + 1;
    uint8_t report_id = 0;
    if (!g600_profile_report_id(profile_number, &report_id) ||
        package->sectors[0].data[0] != report_id) {
        fprintf(stderr,
                "refusing G600 restore: backup report ID does not match a G600 profile slot\n");
        return 1;
    }
    uint8_t current[G600_REPORT_BYTES];
    if (!g600_read_profile(device, profile_number, current)) {
        return 1;
    }
    bool matches = memcmp(current, package->sectors[0].data, G600_REPORT_BYTES) == 0;
    printf("Restore target: %s, 1 G600 profile report\n", device_label(device));
    printf("  Profile %d report 0x%02X: backup is exact; current report: %s\n", profile_number,
           report_id, matches ? "already matches" : "will be restored");
    if (matches) {
        printf("Nothing to do; the connected G600 profile already matches the backup.\n");
        return 0;
    }
    if (!options->yes) {
        return ensure_write_confirmation("restore");
    }

    char pre_restore_path[512];
    int pre_restore_length = snprintf(pre_restore_path, sizeof(pre_restore_path),
                                      "%s.pre-restore.logiob", options->path);
    BackupSectorSource current_source = {
        .sector = g600_profile_sector(profile_number), .size = G600_REPORT_BYTES, .data = current};
    if (pre_restore_length <= 0 || pre_restore_length >= (int)sizeof(pre_restore_path) ||
        !package_write_multi(pre_restore_path, device, G600_BACKUP_PROFILE_FORMAT, &current_source,
                             1, false)) {
        fprintf(stderr,
                "could not save the G600 pre-restore state; no mouse write was attempted\n");
        return 1;
    }
    printf("Saved G600 pre-restore state to %s\n", pre_restore_path);
    if (!g600_write_profile(device, profile_number, package->sectors[0].data)) {
        fprintf(stderr, "G600 restore failed; pre-restore state is at %s\n", pre_restore_path);
        return 1;
    }
    uint8_t verified[G600_REPORT_BYTES];
    if (!g600_read_profile(device, profile_number, verified) ||
        memcmp(verified, package->sectors[0].data, G600_REPORT_BYTES) != 0) {
        fprintf(stderr, "G600 restore read-back verification failed; pre-restore state is at %s\n",
                pre_restore_path);
        return 1;
    }
    printf("Restored G600 profile %d and verified an exact feature-report match.\n",
           profile_number);
    return 0;
}
