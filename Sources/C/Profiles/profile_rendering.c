#include "profile_rendering.h"
#include "profile_io.h"
#include "hid_discovery.h"

#include <stdio.h>
#include <string.h>

const char *function_name(uint8_t value) {
    static const char *names[] = {
        "no action",     "tilt left",   "tilt right",     "next DPI",       "previous DPI",
        "cycle DPI",     "default DPI", "shift DPI",      "next profile",   "previous profile",
        "cycle profile", "G-shift",     "battery status", "profile select", "mode switch",
        "host button",   "scroll down", "scroll up",
    };
    return value <= 0x11 ? names[value] : "unknown function";
}

const char *key_name(uint8_t code) {
    switch (code) {
    case 0x04:
        return "A";
    case 0x05:
        return "B";
    case 0x06:
        return "C";
    case 0x07:
        return "D";
    case 0x08:
        return "E";
    case 0x09:
        return "F";
    case 0x0A:
        return "G";
    case 0x0B:
        return "H";
    case 0x0C:
        return "I";
    case 0x0D:
        return "J";
    case 0x0E:
        return "K";
    case 0x0F:
        return "L";
    case 0x10:
        return "M";
    case 0x11:
        return "N";
    case 0x12:
        return "O";
    case 0x13:
        return "P";
    case 0x14:
        return "Q";
    case 0x15:
        return "R";
    case 0x16:
        return "S";
    case 0x17:
        return "T";
    case 0x18:
        return "U";
    case 0x19:
        return "V";
    case 0x1C:
        return "Y";
    case 0x1D:
        return "Z";
    case 0x28:
        return "Enter";
    case 0x29:
        return "Escape";
    case 0x2B:
        return "Tab";
    case 0x2C:
        return "Space";
    case 0x2F:
        return "[";
    case 0x30:
        return "]";
    case 0x3A:
        return "F1";
    case 0x3B:
        return "F2";
    case 0x3C:
        return "F3";
    case 0x3D:
        return "F4";
    case 0x3E:
        return "F5";
    case 0x3F:
        return "F6";
    case 0x40:
        return "F7";
    case 0x41:
        return "F8";
    case 0x42:
        return "F9";
    case 0x43:
        return "F10";
    case 0x44:
        return "F11";
    case 0x45:
        return "F12";
    case 0x68:
        return "F13";
    case 0x69:
        return "F14";
    case 0x6A:
        return "F15";
    case 0x6B:
        return "F16";
    case 0x6C:
        return "F17";
    case 0x6D:
        return "F18";
    case 0x6E:
        return "F19";
    case 0x6F:
        return "F20";
    case 0x70:
        return "F21";
    case 0x71:
        return "F22";
    case 0x72:
        return "F23";
    case 0x73:
        return "F24";
    default:
        return "unknown key";
    }
}

void describe_spec(const uint8_t spec[4], char *out, size_t out_size) {
    if (spec_is_disabled(spec)) {
        snprintf(out, out_size, "disabled");
        return;
    }
    uint8_t behavior = spec[0] >> 4;
    if (behavior == 0x08) {
        if (spec[1] == 0x00) {
            snprintf(out, out_size, "no action");
        } else if (spec[1] == 0x01) {
            uint16_t mask = (uint16_t)(((uint16_t)spec[2] << 8) | spec[3]);
            const char *name = "mouse mask";
            switch (mask) {
            case 0x0001:
                name = "Left click";
                break;
            case 0x0002:
                name = "Right click";
                break;
            case 0x0004:
                name = "Middle click";
                break;
            case 0x0008:
                name = "Back / rear thumb";
                break;
            case 0x0010:
                name = "Forward";
                break;
            case 0x0020:
                name = "Button 6";
                break;
            case 0x0040:
                name = "Button 7";
                break;
            case 0x0080:
                name = "Button 8";
                break;
            default:
                break;
            }
            snprintf(out, out_size, "%s (mask 0x%04X)", name, mask);
        } else if (spec[1] == 0x02) {
            const char *modifier = "no modifier";
            if (spec[2] == 0x04)
                modifier = "Left Alt";
            else if (spec[2] == 0x01)
                modifier = "Left Ctrl";
            else if (spec[2] == 0x02)
                modifier = "Left Shift";
            else if (spec[2] == 0x08)
                modifier = "Left Command/GUI";
            else if (spec[2] != 0)
                modifier = "modifier bitmap";
            snprintf(out, out_size, "%s + %s (mod 0x%02X key 0x%02X)", modifier, key_name(spec[3]),
                     spec[2], spec[3]);
        } else if (spec[1] == 0x03) {
            uint16_t code = (uint16_t)(((uint16_t)spec[2] << 8) | spec[3]);
            snprintf(out, out_size, "consumer usage 0x%04X", code);
        } else {
            snprintf(out, out_size, "SEND type 0x%02X", spec[1]);
        }
        return;
    }
    if (behavior == 0x09) {
        snprintf(out, out_size, "%s", function_name(spec[1]));
        return;
    }
    if (behavior <= 0x02) {
        snprintf(out, out_size, "macro record (behavior 0x%X)", behavior);
        return;
    }
    snprintf(out, out_size, "unrecognized raw spec");
}

bool spec_is_back(const uint8_t spec[4]) {
    return spec[0] == 0x80 && spec[1] == 0x01 && spec[2] == 0x00 && spec[3] == 0x08;
}

void print_hex4(const uint8_t bytes[4]) {
    printf("%02X %02X %02X %02X", bytes[0], bytes[1], bytes[2], bytes[3]);
}

void print_profile_summary(const Profile *profile, bool show_buttons) {
    printf("Profile %zu (sector 0x%04X, enabled=%s)\n", profile->selected_header + 1,
           profile->headers[profile->selected_header].sector,
           profile->headers[profile->selected_header].enabled ? "yes" : "no");
    printf("  format: 0x%02X, macro format: 0x%02X, profiles: %u, buttons: %u, sectors: %u, sector "
           "bytes: %u\n",
           profile->info.profile_format, profile->info.macro_format, profile->info.profile_count,
           profile->info.button_count, profile->info.sector_count, profile->info.sector_size);
    printf("  CRC: %s\n",
           !profile->crc_checked ? "NOT_READ" : (profile->crc_ok ? "OK" : "INVALID"));
    if (profile->dpi_layout_supported) {
        printf("  DPI stages: ");
        for (size_t i = 0; i < profile->dpi_count; i++) {
            if (i != 0) {
                printf(", ");
            }
            printf("%u", read_le16(profile->data + profile->dpi_offset + i * 2));
        }
        printf(" (default %u, shift %u)\n", profile->dpi_default_index + 1,
               profile->dpi_shift_index + 1);
    } else {
        printf("  DPI stages: not recognized; stage editing is disabled\n");
    }
    if (profile->rgb_layout_supported) {
        size_t present_count = 0;
        for (size_t i = 0; i < profile->rgb_zone_count; i++) {
            if (profile->rgb_zone_present[i]) {
                present_count++;
            }
        }
        printf("  RGB zones: %zu (legacy 11-byte records at offset %zu)\n", present_count,
               profile->rgb_offset);
        for (size_t i = 0; i < profile->rgb_zone_count; i++) {
            if (!profile->rgb_zone_present[i]) {
                continue;
            }
            const uint8_t *record =
                profile->data + profile->rgb_offset + i * RGB_PROFILE_RECORD_BYTES;
            printf("  RGB zone %zu: %02X%02X%02X (mode 0x%02X)\n", i + 1,
                   record[RGB_PROFILE_COLOR_OFFSET], record[RGB_PROFILE_COLOR_OFFSET + 1],
                   record[RGB_PROFILE_COLOR_OFFSET + 2], record[0]);
        }
    } else {
        printf("  RGB zones: not recognized; color editing is disabled\n");
    }
    if (profile->button_offset != 0 || profile->layout_supported) {
        printf("  button array: offset %zu (%zu/%u structurally valid, %zu recognized)\n",
               profile->button_offset, profile->valid_specs, profile->info.button_count,
               profile->known_specs);
        if (!profile->layout_supported) {
            printf("  write safety: layout was only found diagnostically; writes are disabled\n");
        }
    } else {
        printf("  button array: not recognized; writes are disabled\n");
    }
    if (profile->gshift_layout_supported) {
        printf(
            "  G-Shift layout: supported (offset %zu; %zu/%u structurally valid, %zu recognized)\n",
            profile->gshift_button_offset, profile->gshift_valid_specs, profile->info.button_count,
            profile->gshift_known_specs);
    } else if ((profile->info.shift_flags & 0x03) == 0x02) {
        printf("  G-Shift layout: not recognized; editing is disabled\n");
    }
    if (!show_buttons || (profile->button_offset == 0 && !profile->layout_supported)) {
        return;
    }
    int back_count = 0;
    int back_button = 0;
    for (size_t i = 0; i < profile->info.button_count; i++) {
        const uint8_t *spec = profile->data + profile->button_offset + i * 4;
        char description[160];
        describe_spec(spec, description, sizeof(description));
        printf("  button %zu: %-30s [", i + 1, description);
        print_hex4(spec);
        printf("]\n");
        if (spec_is_back(spec)) {
            back_count++;
            back_button = (int)i + 1;
        }
    }
    if (profile->gshift_layout_supported) {
        for (size_t i = 0; i < profile->info.button_count; i++) {
            const uint8_t *spec = profile->data + profile->gshift_button_offset + i * 4;
            char description[160];
            describe_spec(spec, description, sizeof(description));
            printf("  G-Shift button %zu: %-30s [", i + 1, description);
            print_hex4(spec);
            printf("]\n");
        }
    }
    if (back_count == 1) {
        printf("  rear thumb mapping: profile button %d (unambiguous Back record)\n", back_button);
    } else if (back_count == 0) {
        printf("  rear thumb mapping: no current Back record; use watch and an explicit --button "
               "number\n");
    } else {
        printf("  rear thumb mapping: %d Back records; refusing to guess\n", back_count);
    }
}

int find_rear_thumb_button(const Profile *profile) {
    if (!profile->layout_supported || !profile->crc_ok) {
        return 0;
    }
    int found = 0;
    for (size_t i = 0; i < profile->info.button_count; i++) {
        if (spec_is_back(profile->data + profile->button_offset + i * 4)) {
            if (found != 0) {
                return 0;
            }
            found = (int)i + 1;
        }
    }
    return found;
}

void print_feature_list(const Device *device) {
    printf("  features: %zu\n", device->feature_count);
    for (size_t i = 0; i < device->feature_count; i++) {
        printf("    index %3u: 0x%04X v%u\n", device->features[i].index, device->features[i].id,
               device->features[i].version);
    }
}

void print_device_line(const Device *device, size_t index) {
    char key[64];
    format_device_key(device, key, sizeof(key));
    printf("[%zu] %s  %s  (HID++ %.1f, product 0x%04X, key %s)\n", index, device_connection(device),
           device_label(device), device->protocol, device->iface->product_id, key);
}
