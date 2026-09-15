#include "profile_codec.h"

#include <string.h>

bool profile_codec_parse_info(const uint8_t *bytes, size_t length, ProfileCodecInfo *info) {
    if (bytes == NULL || info == NULL || length < PROFILE_CODEC_INFO_BYTES) {
        return false;
    }

    ProfileCodecInfo parsed = {
        .memory = bytes[0],
        .profile_format = bytes[1],
        .macro_format = bytes[2],
        .profile_count = bytes[3],
        .out_of_band = bytes[4],
        .button_count = bytes[5],
        .sector_count = bytes[6],
        .sector_size = (uint16_t)(((uint16_t)bytes[7] << 8) | bytes[8]),
        .shift_flags = bytes[9],
    };
    if (parsed.sector_size < 32 || parsed.sector_size > PROFILE_CODEC_MAX_SECTOR_BYTES ||
        parsed.button_count == 0 || parsed.button_count > 64) {
        return false;
    }
    *info = parsed;
    return true;
}

bool profile_codec_parse_headers(uint16_t sector_size, const uint8_t *control,
                                 size_t control_length, ProfileCodecHeader *headers,
                                 size_t *header_count) {
    if (control == NULL || headers == NULL || header_count == NULL) {
        return false;
    }
    *header_count = 0;
    size_t limit = control_length;
    if (control_length >= sector_size && limit >= 2) {
        limit -= 2;
    }
    for (size_t offset = 0; offset + 3 < limit && *header_count < PROFILE_CODEC_MAX_HEADERS;
         offset += 4) {
        if (control[offset] == 0xFF && control[offset + 1] == 0xFF) {
            break;
        }
        uint16_t sector = (uint16_t)(((uint16_t)control[offset] << 8) | control[offset + 1]);
        if (sector == 0) {
            break;
        }
        headers[*header_count].sector = sector;
        headers[*header_count].enabled = control[offset + 2];
        (*header_count)++;
    }
    return *header_count > 0;
}

uint16_t profile_codec_crc16_ccitt_false(const uint8_t *bytes, size_t length) {
    uint16_t crc = 0xFFFF;
    for (size_t i = 0; i < length; i++) {
        crc ^= (uint16_t)bytes[i] << 8;
        for (int bit = 0; bit < 8; bit++) {
            crc = (crc & 0x8000) ? (uint16_t)((crc << 1) ^ 0x1021) : (uint16_t)(crc << 1);
        }
    }
    return crc;
}

bool profile_codec_sector_crc_ok(const uint8_t *bytes, size_t length) {
    if (bytes == NULL || length < 2) {
        return false;
    }
    uint16_t stored = (uint16_t)(((uint16_t)bytes[length - 2] << 8) | bytes[length - 1]);
    return profile_codec_crc16_ccitt_false(bytes, length - 2) == stored;
}

void profile_codec_sector_put_crc(uint8_t *bytes, size_t length) {
    if (bytes == NULL || length < 2) {
        return;
    }
    uint16_t crc = profile_codec_crc16_ccitt_false(bytes, length - 2);
    bytes[length - 2] = (uint8_t)(crc >> 8);
    bytes[length - 1] = (uint8_t)(crc & 0xFF);
}

bool profile_codec_spec_is_disabled(const uint8_t spec[4]) {
    return spec != NULL && spec[0] == 0xFF && spec[1] == 0xFF && spec[2] == 0xFF && spec[3] == 0xFF;
}

bool profile_codec_spec_structurally_valid(const uint8_t spec[4]) {
    if (spec == NULL) {
        return false;
    }
    if (profile_codec_spec_is_disabled(spec)) {
        return true;
    }
    uint8_t behavior = spec[0] >> 4;
    if (behavior <= 0x02) {
        return true; // macro records are preserved but not edited by this tool
    }
    if (behavior == 0x08) {
        return spec[1] <= 0x03;
    }
    if (behavior == 0x09) {
        return spec[1] <= 0x11;
    }
    return false;
}

bool profile_codec_spec_known(const uint8_t spec[4]) {
    if (spec == NULL) {
        return false;
    }
    if (profile_codec_spec_is_disabled(spec)) {
        return true;
    }
    uint8_t behavior = spec[0] >> 4;
    return behavior == 0x08 || behavior == 0x09;
}

uint16_t profile_codec_read_le16(const uint8_t *bytes) {
    return (uint16_t)((uint16_t)bytes[0] | ((uint16_t)bytes[1] << 8));
}

void profile_codec_write_le16(uint8_t *bytes, uint16_t value) {
    bytes[0] = (uint8_t)(value & 0xFF);
    bytes[1] = (uint8_t)(value >> 8);
}

void profile_codec_detect_button_layout(const uint8_t *data, size_t data_length,
                                        uint8_t profile_format, uint8_t button_count,
                                        ProfileCodecButtonLayout *layout) {
    if (layout == NULL) {
        return;
    }
    *layout = (ProfileCodecButtonLayout){0};
    if (data == NULL || data_length < 2 || button_count == 0) {
        return;
    }
    size_t payload_length = data_length - 2;
    size_t expected = profile_format >= 6 ? 48 : 32;
    size_t candidates[2] = {expected, expected == 32 ? 48 : 32};
    for (size_t c = 0; c < 2; c++) {
        size_t offset = candidates[c];
        if (offset > payload_length || button_count > (payload_length - offset) / 4) {
            continue;
        }
        size_t valid = 0;
        size_t known = 0;
        for (size_t i = 0; i < button_count; i++) {
            const uint8_t *spec = data + offset + i * 4;
            valid += profile_codec_spec_structurally_valid(spec) ? 1 : 0;
            known += profile_codec_spec_known(spec) ? 1 : 0;
        }
        if (valid >= button_count - 1 && known >= 1) {
            layout->offset = offset;
            layout->valid_specs = valid;
            layout->known_specs = known;
            layout->supported = c == 0;
            return;
        }
    }

    // Diagnostic-only scan. It helps explain a new device format in a dump,
    // but it is deliberately not enough to authorize a write.
    if (button_count > payload_length / 4) {
        return;
    }
    size_t record_bytes = (size_t)button_count * 4;
    size_t best_offset = 0;
    size_t best_valid = 0;
    size_t best_known = 0;
    size_t best_count = 0;
    for (size_t offset = 0; offset <= payload_length - record_bytes; offset++) {
        size_t valid = 0;
        size_t known = 0;
        for (size_t i = 0; i < button_count; i++) {
            const uint8_t *spec = data + offset + i * 4;
            valid += profile_codec_spec_structurally_valid(spec) ? 1 : 0;
            known += profile_codec_spec_known(spec) ? 1 : 0;
        }
        if (known > best_known || (known == best_known && valid > best_valid)) {
            best_offset = offset;
            best_valid = valid;
            best_known = known;
            best_count = 1;
        } else if (known == best_known && valid == best_valid) {
            best_count++;
        }
    }
    if (best_count == 1 && best_valid >= button_count - 1 && best_known >= 1) {
        layout->offset = best_offset;
        layout->valid_specs = best_valid;
        layout->known_specs = best_known;
    }
}

void profile_codec_detect_gshift_button_layout(const uint8_t *data, size_t data_length,
                                               uint8_t button_count, size_t button_offset,
                                               bool candidate, ProfileCodecButtonLayout *layout) {
    if (layout == NULL) {
        return;
    }
    *layout = (ProfileCodecButtonLayout){0};
    if (!candidate || data == NULL || data_length < 2 || button_count == 0) {
        return;
    }
    size_t payload_length = data_length - 2;
    if (button_offset > payload_length || button_offset > SIZE_MAX - 64) {
        return;
    }
    size_t offset = button_offset + 64;
    if (offset > payload_length || button_count > (payload_length - offset) / 4) {
        return;
    }
    size_t valid = 0;
    size_t known = 0;
    for (size_t i = 0; i < button_count; i++) {
        const uint8_t *spec = data + offset + i * 4;
        valid += profile_codec_spec_structurally_valid(spec) ? 1 : 0;
        known += profile_codec_spec_known(spec) ? 1 : 0;
    }
    if (valid >= button_count - 1 && known >= 1) {
        layout->offset = offset;
        layout->valid_specs = valid;
        layout->known_specs = known;
        layout->supported = true;
    }
}

void profile_codec_detect_dpi_layout(const uint8_t *data, size_t data_length,
                                     uint8_t profile_format, bool zero_terminated,
                                     ProfileCodecDpiLayout *layout) {
    if (layout == NULL) {
        return;
    }
    *layout = (ProfileCodecDpiLayout){.unused_value = zero_terminated ? 0 : UINT16_MAX};
    if (data == NULL || profile_format > 5 || data_length < 15) {
        return;
    }
    uint16_t previous = 0;
    size_t count = 0;
    bool inactive = false;
    bool saw_unused_value = false;
    for (size_t i = 0; i < 5; i++) {
        uint16_t dpi = profile_codec_read_le16(data + 3 + i * 2);
        if (dpi == 0 || dpi == UINT16_MAX) {
            if (!saw_unused_value && !zero_terminated) {
                layout->unused_value = dpi;
            }
            saw_unused_value = true;
            inactive = true;
            continue;
        }
        if (inactive || dpi < 100 || (i > 0 && dpi <= previous)) {
            return;
        }
        previous = dpi;
        count++;
    }
    if (count == 0) {
        return;
    }
    if (data[1] >= count || data[2] >= count) {
        return;
    }
    layout->offset = 3;
    layout->count = count;
    layout->default_index = data[1];
    layout->shift_index = data[2];
    layout->supported = true;
}

static bool profile_codec_rgb_mode_is_known(uint8_t mode) {
    // Legacy onboard RGB records use the effect identifiers exposed by the
    // device's COLOR_LED_EFFECTS feature. Keep the list explicit so random
    // bytes still fail layout validation before a profile can be written.
    switch (mode) {
    case 0x00: // disabled
    case 0x01: // static
    case 0x02: // pulse
    case 0x03: // cycle
    case 0x04: // wave
    case 0x08: // boot
    case 0x09: // demo
    case 0x0A: // breathe
    case 0x0B: // ripple
    case 0x0E:
    case 0x0F:
    case 0x10:
    case 0x15:
    case 0x16:
    case 0x17:
        return true;
    default:
        return false;
    }
}

static bool
profile_codec_rgb_record_is_disabled(const uint8_t record[PROFILE_CODEC_RGB_RECORD_BYTES]) {
    for (size_t i = 0; i < PROFILE_CODEC_RGB_RECORD_BYTES; i++) {
        if (record[i] != 0xFF) {
            return false;
        }
    }
    return true;
}

void profile_codec_detect_rgb_layout(const uint8_t *data, size_t data_length,
                                     uint8_t profile_format, ProfileCodecRgbLayout *layout) {
    if (layout == NULL) {
        return;
    }
    *layout = (ProfileCodecRgbLayout){0};
    size_t required = PROFILE_CODEC_RGB_BASE_OFFSET +
                      PROFILE_CODEC_RGB_RECORD_BYTES * PROFILE_CODEC_RGB_RECORD_COUNT + 2;
    if (data == NULL || profile_format < 4 || profile_format > 5 || data_length < required) {
        return;
    }

    size_t last_present = 0;
    bool found = false;
    for (size_t index = 0; index < PROFILE_CODEC_RGB_RECORD_COUNT; index++) {
        const uint8_t *record =
            data + PROFILE_CODEC_RGB_BASE_OFFSET + index * PROFILE_CODEC_RGB_RECORD_BYTES;
        if (profile_codec_rgb_record_is_disabled(record)) {
            continue;
        }
        if (!profile_codec_rgb_mode_is_known(record[0])) {
            return;
        }
        layout->zone_present[index] = true;
        last_present = index;
        found = true;
    }
    if (!found) {
        return;
    }
    layout->offset = PROFILE_CODEC_RGB_BASE_OFFSET;
    layout->zone_count = last_present + 1;
    layout->supported = true;
}

bool profile_codec_write_rgb_zone_colors(uint8_t *data, size_t data_length, size_t rgb_offset,
                                         size_t rgb_zone_count,
                                         const bool zone_present[PROFILE_CODEC_RGB_RECORD_COUNT],
                                         const uint8_t zones[], const uint8_t colors[][3],
                                         size_t count) {
    if (data == NULL || zones == NULL || colors == NULL || zone_present == NULL || count == 0 ||
        count > PROFILE_CODEC_RGB_RECORD_COUNT || rgb_zone_count == 0 ||
        rgb_zone_count > PROFILE_CODEC_RGB_RECORD_COUNT || rgb_offset > data_length ||
        data_length - rgb_offset < PROFILE_CODEC_RGB_RECORD_BYTES * rgb_zone_count + 2) {
        return false;
    }
    bool seen[PROFILE_CODEC_RGB_RECORD_COUNT] = {false};
    for (size_t i = 0; i < count; i++) {
        size_t zone = zones[i];
        if (zone >= rgb_zone_count || zone >= PROFILE_CODEC_RGB_RECORD_COUNT || seen[zone] ||
            !zone_present[zone]) {
            return false;
        }
        seen[zone] = true;
        size_t offset =
            rgb_offset + zone * PROFILE_CODEC_RGB_RECORD_BYTES + PROFILE_CODEC_RGB_COLOR_OFFSET;
        memcpy(data + offset, colors[i], 3);
    }
    return true;
}

bool profile_codec_write_dpi_stage_table(uint8_t *data, size_t data_length, size_t dpi_offset,
                                         uint16_t unused_value, const uint16_t *stages,
                                         size_t count) {
    if (data == NULL || stages == NULL || count == 0 || count > 5 || dpi_offset > data_length ||
        data_length - dpi_offset < 5 * sizeof(uint16_t)) {
        return false;
    }
    for (size_t i = 0; i < count; i++) {
        profile_codec_write_le16(data + dpi_offset + i * 2, stages[i]);
    }
    for (size_t i = count; i < 5; i++) {
        profile_codec_write_le16(data + dpi_offset + i * 2, unused_value);
    }
    return true;
}

bool profile_codec_validate_profile_for_write(bool crc_ok, bool layout_supported,
                                              size_t data_length, size_t button_offset,
                                              uint8_t button_count, size_t valid_specs) {
    if (!crc_ok || !layout_supported || data_length < 2 || button_offset > data_length - 2 ||
        button_count > (data_length - 2 - button_offset) / 4) {
        return false;
    }
    return valid_specs >= (size_t)button_count - 1;
}
