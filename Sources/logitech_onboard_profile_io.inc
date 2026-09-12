static uint16_t crc16_ccitt_false(const uint8_t *bytes, size_t length) {
    uint16_t crc = 0xFFFF;
    for (size_t i = 0; i < length; i++) {
        crc ^= (uint16_t)bytes[i] << 8;
        for (int bit = 0; bit < 8; bit++) {
            crc = (crc & 0x8000) ? (uint16_t)((crc << 1) ^ 0x1021) : (uint16_t)(crc << 1);
        }
    }
    return crc;
}

static bool sector_crc_ok(const uint8_t *bytes, size_t length) {
    if (length < 2) {
        return false;
    }
    uint16_t stored = (uint16_t)(((uint16_t)bytes[length - 2] << 8) | bytes[length - 1]);
    return crc16_ccitt_false(bytes, length - 2) == stored;
}

static void sector_put_crc(uint8_t *bytes, size_t length) {
    uint16_t crc = crc16_ccitt_false(bytes, length - 2);
    bytes[length - 2] = (uint8_t)(crc >> 8);
    bytes[length - 1] = (uint8_t)(crc & 0xFF);
}

static int get_profile_info(Device *device, ProfileInfo *info) {
    Reply reply = device_call(device, FEATURE_ONBOARD_PROFILES, ONBOARD_GET_INFO, NULL, 0, 2.0);
    if (reply.status != REPLY_OK) {
        print_reply_error("ONBOARD_PROFILES.getInfo", reply);
        return 0;
    }
    if (reply.length < 10) {
        fprintf(stderr, "ONBOARD_PROFILES.getInfo returned only %zu bytes\n", reply.length);
        return 0;
    }
    memset(info, 0, sizeof(*info));
    info->memory = reply.bytes[0];
    info->profile_format = reply.bytes[1];
    info->macro_format = reply.bytes[2];
    info->profile_count = reply.bytes[3];
    info->out_of_band = reply.bytes[4];
    info->button_count = reply.bytes[5];
    info->sector_count = reply.bytes[6];
    info->sector_size = (uint16_t)(((uint16_t)reply.bytes[7] << 8) | reply.bytes[8]);
    info->shift_flags = reply.bytes[9];
    if (info->sector_size < 32 || info->sector_size > MAX_SECTOR_BYTES || info->sector_size < 2) {
        fprintf(stderr, "device reported implausible onboard sector size %u\n", info->sector_size);
        return 0;
    }
    if (info->button_count == 0 || info->button_count > 64) {
        fprintf(stderr, "device reported implausible button count %u\n", info->button_count);
        return 0;
    }
    return 1;
}

static int read_sector(Device *device, uint16_t sector, size_t size, uint8_t *out) {
    if (size < 2 || size > MAX_SECTOR_BYTES) {
        return 0;
    }
    size_t copied = 0;
    while (copied < size) {
        size_t request_offset = copied;
        if (size - copied < 16) {
            request_offset = size - 16;
        }
        // readSector takes only the sector number and byte offset. The
        // length field belongs to startWrite (0x60), not to readSector
        // (0x50); appending two zero bytes can make some firmware return a
        // response that does not represent the requested sector.
        uint8_t params[4] = {
            (uint8_t)(sector >> 8), (uint8_t)(sector & 0xFF),
            (uint8_t)(request_offset >> 8), (uint8_t)(request_offset & 0xFF),
        };
        Reply reply = device_call(device, FEATURE_ONBOARD_PROFILES, ONBOARD_READ_SECTOR,
                                  params, sizeof(params), 2.0);
        if (reply.status != REPLY_OK || reply.length < 16) {
            print_reply_error("ONBOARD_PROFILES.readSector", reply);
            if (reply.status == REPLY_OK) {
                fprintf(stderr, "readSector returned only %zu bytes\n", reply.length);
            }
            return 0;
        }
        size_t from = copied > request_offset ? copied - request_offset : 0;
        size_t take = 16 - from;
        if (take > size - copied) {
            take = size - copied;
        }
        memcpy(out + copied, reply.bytes + from, take);
        copied += take;
    }
    return 1;
}

static int write_sector(Device *device, uint16_t sector, const uint8_t *bytes, size_t length) {
    if (length < 2 || length > MAX_SECTOR_BYTES) {
        return 0;
    }
    uint8_t start_params[6] = {
        (uint8_t)(sector >> 8), (uint8_t)(sector & 0xFF), 0, 0,
        (uint8_t)(length >> 8), (uint8_t)(length & 0xFF),
    };
    // The payload-bearing memory commands are explicitly long reports. The
    // commit command has no payload and must use the normal short/long choice;
    // G502 X firmware rejects a forced long endWrite frame on some revisions.
    Reply reply = device_call_long(device, FEATURE_ONBOARD_PROFILES, ONBOARD_START_WRITE,
                                   start_params, sizeof(start_params), 4.0);
    if (reply.status != REPLY_OK) {
        print_reply_error("ONBOARD_PROFILES.startWrite", reply);
        return 0;
    }
    size_t offset = 0;
    while (offset < length) {
        size_t take = length - offset;
        if (take > 16) {
            take = 16;
        }
        reply = device_call_long(device, FEATURE_ONBOARD_PROFILES, ONBOARD_WRITE_DATA,
                                 bytes + offset, take, 4.0);
        if (reply.status != REPLY_OK) {
            print_reply_error("ONBOARD_PROFILES.writeData", reply);
            return 0;
        }
        offset += take;
    }
    reply = device_call(device, FEATURE_ONBOARD_PROFILES, ONBOARD_END_WRITE, NULL, 0, 4.0);
    if (reply.status != REPLY_OK) {
        print_reply_error("ONBOARD_PROFILES.endWrite", reply);
        return 0;
    }
    // endWrite acknowledges the transfer before flash commit is necessarily
    // visible to readSector. Give the device a short settle window; callers
    // also retry exact readback without repeating the write transaction.
    usleep(100000);
    return 1;
}

#define SECTOR_VERIFY_ATTEMPTS 5
#define SECTOR_VERIFY_RETRY_DELAY_US 100000

static bool verify_sector_readback(Device *device,
                                   uint16_t sector,
                                   const uint8_t *expected,
                                   size_t length) {
    for (size_t attempt = 0; attempt < SECTOR_VERIFY_ATTEMPTS; attempt++) {
        if (attempt > 0) {
            usleep(SECTOR_VERIFY_RETRY_DELAY_US);
        }
        uint8_t *readback = (uint8_t *)malloc(length);
        if (readback == NULL) {
            return false;
        }
        bool verified = read_sector(device, sector, length, readback) &&
                        sector_crc_ok(readback, length) &&
                        memcmp(readback, expected, length) == 0;
        free(readback);
        if (verified) {
            if (attempt > 0) {
                printf("Exact sector readback succeeded after retry %zu.\n", attempt);
            }
            return true;
        }
    }
    return false;
}

static bool get_onboard_mode(Device *device, uint8_t *mode_out) {
    Reply reply = device_call(device, FEATURE_ONBOARD_PROFILES, ONBOARD_GET_MODE,
                              NULL, 0, 2.0);
    if (reply.status != REPLY_OK || reply.length < 1) {
        print_reply_error("ONBOARD_PROFILES.getMode", reply);
        return false;
    }
    *mode_out = reply.bytes[0];
    return true;
}

static bool set_onboard_mode(Device *device, uint8_t mode) {
    uint8_t params[1] = {mode};
    Reply reply = device_call(device, FEATURE_ONBOARD_PROFILES, ONBOARD_SET_MODE,
                              params, sizeof(params), 2.0);
    if (reply.status != REPLY_OK) {
        print_reply_error("ONBOARD_PROFILES.setMode", reply);
        return false;
    }
    return true;
}

static bool ensure_onboard_mode_for_write(Device *device) {
    uint8_t mode = 0;
    if (!get_onboard_mode(device, &mode)) {
        // Some older profile implementations expose the storage commands but
        // not the mode query. Preserve their existing write path.
        fprintf(stderr, "warning: could not query onboard mode; continuing without changing it\n");
        return true;
    }
    if (mode == ONBOARD_MODE_ONBOARD) {
        return true;
    }
    printf("Device is in host-controlled mode; switching to onboard mode before writing.\n");
    if (!set_onboard_mode(device, ONBOARD_MODE_ONBOARD) ||
        !get_onboard_mode(device, &mode) || mode != ONBOARD_MODE_ONBOARD) {
        fprintf(stderr, "could not switch the mouse to onboard mode; no profile write was attempted\n");
        return false;
    }
    return true;
}

static bool get_current_onboard_profile(Device *device, uint8_t *profile_index_out) {
    Reply reply = device_call(device, FEATURE_ONBOARD_PROFILES, ONBOARD_GET_CURRENT_PROFILE,
                              NULL, 0, 2.0);
    if (reply.status != REPLY_OK || reply.length < 2) {
        print_reply_error("ONBOARD_PROFILES.getCurrentProfile", reply);
        return false;
    }
    // The profile index is returned in the second parameter. Keep the raw
    // value here; G502 X firmware returns a one-based profile number while
    // some older devices use a zero-based value.
    *profile_index_out = reply.bytes[1];
    return true;
}

static bool is_g502x_family_device(const Device *device) {
    if (device == NULL || device->iface == NULL) {
        return false;
    }
    switch (device->iface->product_id) {
        case 0xC095: // G502 X PLUS
        case 0xC098: // G502 X LIGHTSPEED
        case 0xC099: // G502 X
        case 0x4099: // G502 X PLUS through receiver
        case 0x409F: // G502 X LIGHTSPEED through receiver
            return true;
        default:
            break;
    }
    return text_contains_case_insensitive(device_label(device), "G502 X") ||
           text_contains_case_insensitive(device_label(device), "G502X");
}

static int current_onboard_profile_number(const Device *device, uint8_t raw_index) {
    if (is_g502x_family_device(device)) {
        return raw_index == 0 ? 0 : (int)raw_index;
    }
    return (int)raw_index + 1;
}

static bool set_current_onboard_dpi_index(Device *device, uint8_t index) {
    uint8_t params[1] = {index};
    Reply reply = device_call(device, FEATURE_ONBOARD_PROFILES,
                              ONBOARD_SET_CURRENT_DPI_INDEX,
                              params, sizeof(params), 2.0);
    if (reply.status != REPLY_OK) {
        print_reply_error("ONBOARD_PROFILES.setCurrentDpiIndex", reply);
        return false;
    }
    return true;
}

static bool get_current_onboard_dpi_index(Device *device, uint8_t *index_out) {
    Reply reply = device_call(device, FEATURE_ONBOARD_PROFILES,
                              ONBOARD_GET_CURRENT_DPI_INDEX,
                              NULL, 0, 2.0);
    if (reply.status != REPLY_OK || reply.length < 1) {
        print_reply_error("ONBOARD_PROFILES.getCurrentDpiIndex", reply);
        return false;
    }
    *index_out = reply.bytes[0];
    return true;
}

static bool get_current_sensor_dpi(Device *device, uint8_t sensor_index, uint16_t *dpi_out) {
    const uint8_t params[3] = {sensor_index, 0, 0};
    Reply reply = device_call(device, FEATURE_ADJUSTABLE_DPI, 0x20,
                              params, sizeof(params), 2.0);
    if (reply.status != REPLY_OK || reply.length < 3) {
        print_reply_error("ADJUSTABLE_DPI.getSensorDpi", reply);
        return false;
    }
    *dpi_out = (uint16_t)(((uint16_t)reply.bytes[1] << 8) | reply.bytes[2]);
    return true;
}

static bool live_dpi_matches(Device *device, uint16_t expected_dpi) {
    uint16_t current_dpi = 0;
    return get_current_sensor_dpi(device, 0, &current_dpi) && current_dpi == expected_dpi;
}

static bool set_live_dpi_index_and_verify(Device *device,
                                          uint8_t desired_index,
                                          uint16_t expected_dpi) {
    // A G502 X can still be finishing its profile-sector commit when the
    // first 0x8100 DPI-index command arrives (especially after a receiver or
    // KVM reconnect). Repeat the complete set/read/physical-DPI verification
    // rather than accepting a matching index byte while the sensor remains at
    // a stale or boot-safe value such as 25600.
    for (size_t attempt = 0; attempt < 4; attempt++) {
        if (attempt > 0) {
            usleep(150000);
        }
        if (!set_current_onboard_dpi_index(device, desired_index)) {
            continue;
        }
        uint8_t current_index = 0;
        if (get_current_onboard_dpi_index(device, &current_index) &&
            current_index == desired_index &&
            live_dpi_matches(device, expected_dpi)) {
            return true;
        }
    }
    return false;
}

static bool profile_contains_dpi(const uint16_t *stages,
                                 size_t stage_count,
                                 uint16_t dpi) {
    for (size_t i = 0; i < stage_count; i++) {
        if (stages[i] == dpi) {
            return true;
        }
    }
    return false;
}

static void sync_active_profile_default_dpi(Device *device,
                                             int profile_number,
                                             int default_stage,
                                             uint16_t default_dpi) {
    uint8_t active_profile = 0;
    if (!get_current_onboard_profile(device, &active_profile)) {
        fprintf(stderr, "warning: saved DPI profile, but could not identify the active profile for live DPI sync\n");
        return;
    }
    int active_profile_number = current_onboard_profile_number(device, active_profile);
    if (active_profile_number != profile_number) {
        printf("Live DPI unchanged: active onboard profile is %u; saved profile %d is not active.\n",
               (unsigned)active_profile_number, profile_number);
        return;
    }
    uint8_t desired_index = (uint8_t)(default_stage - 1);
    if (!set_live_dpi_index_and_verify(device, desired_index, default_dpi)) {
        fprintf(stderr, "warning: profile sector is saved, but the live DPI remained different from %u after retrying\n",
                default_dpi);
        return;
    }
    printf("Live default DPI: %u (stage %d; sensor value verified).\n", default_dpi, default_stage);
}

static bool recover_live_dpi_if_needed(Device *device,
                                       int profile_number,
                                       const uint16_t *stages,
                                       size_t stage_count,
                                       int default_stage,
                                       uint16_t current_dpi) {
    if (stage_count == 0 || default_stage < 1 || default_stage > (int)stage_count ||
        profile_number < 1) {
        return false;
    }

    uint8_t active_profile = 0;
    if (!get_current_onboard_profile(device, &active_profile) ||
        current_onboard_profile_number(device, active_profile) != profile_number ||
        profile_contains_dpi(stages, stage_count, current_dpi)) {
        return false;
    }

    uint16_t default_dpi = stages[default_stage - 1];
    printf("Live DPI %u is not an active stage; restoring profile %d default %u.\n",
           current_dpi, profile_number, default_dpi);
    if (!set_live_dpi_index_and_verify(device, (uint8_t)(default_stage - 1), default_dpi)) {
        fprintf(stderr, "warning: could not repair the live DPI after reconnect; stored profile data was left unchanged\n");
        return false;
    }
    printf("Recovered live DPI: %u (stage %d; sensor value verified).\n",
           default_dpi, default_stage);
    return true;
}

static int read_profile_control(Device *device,
                                const ProfileInfo *info,
                                uint16_t *control_sector_out,
                                uint8_t *control,
                                size_t control_length) {
    uint16_t header_sector = 0;
    if (!read_sector(device, 0, control_length, control)) {
        return 0;
    }
    bool all_zero = true;
    bool all_ff = true;
    for (size_t i = 0; i < 4 && i < info->sector_size; i++) {
        all_zero = all_zero && control[i] == 0x00;
        all_ff = all_ff && control[i] == 0xFF;
    }
    if (all_zero || all_ff) {
        header_sector = 1;
        if (!read_sector(device, header_sector, control_length, control)) {
            return 0;
        }
    }
    if (control_sector_out != NULL) {
        *control_sector_out = header_sector;
    }
    return 1;
}

static int parse_profile_headers(const ProfileInfo *info,
                                const uint8_t *control,
                                size_t control_length,
                                ProfileHeader *headers,
                                size_t *header_count) {
    *header_count = 0;
    size_t limit = control_length;
    if (control_length >= info->sector_size && limit >= 2) {
        limit -= 2;
    }
    for (size_t offset = 0; offset + 3 < limit && *header_count < MAX_HEADERS; offset += 4) {
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

static int read_profile_headers(Device *device,
                                const ProfileInfo *info,
                                ProfileHeader *headers,
                                size_t *header_count) {
    size_t control_length = info->sector_size;
    size_t maximum_header_bytes = MAX_HEADERS * 4 + 4;
    if (control_length > maximum_header_bytes) {
        control_length = maximum_header_bytes;
    }
    uint8_t *control = (uint8_t *)malloc(control_length);
    if (control == NULL) {
        return 0;
    }
    bool ok = read_profile_control(device, info, NULL, control, control_length) &&
              parse_profile_headers(info, control, control_length, headers, header_count);
    free(control);
    return ok;
}

static bool spec_is_disabled(const uint8_t spec[4]) {
    return spec[0] == 0xFF && spec[1] == 0xFF && spec[2] == 0xFF && spec[3] == 0xFF;
}

static bool spec_structurally_valid(const uint8_t spec[4]) {
    if (spec_is_disabled(spec)) {
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

static bool spec_known(const uint8_t spec[4]) {
    if (spec_is_disabled(spec)) {
        return true;
    }
    uint8_t behavior = spec[0] >> 4;
    return behavior == 0x08 || behavior == 0x09;
}

static void detect_button_layout(Profile *profile) {
    profile->button_offset = 0;
    profile->valid_specs = 0;
    profile->known_specs = 0;
    profile->layout_supported = false;
    size_t count = profile->info.button_count;
    size_t expected = profile->info.profile_format >= 6 ? 48 : 32;
    size_t candidates[2] = {expected, expected == 32 ? 48 : 32};
    for (size_t c = 0; c < 2; c++) {
        size_t offset = candidates[c];
        if (offset + count * 4 > profile->data_length - 2) {
            continue;
        }
        size_t valid = 0;
        size_t known = 0;
        for (size_t i = 0; i < count; i++) {
            const uint8_t *spec = profile->data + offset + i * 4;
            valid += spec_structurally_valid(spec) ? 1 : 0;
            known += spec_known(spec) ? 1 : 0;
        }
        if (valid >= count - 1 && known >= 1) {
            profile->button_offset = offset;
            profile->valid_specs = valid;
            profile->known_specs = known;
            profile->layout_supported = c == 0;
            return;
        }
    }

    // Diagnostic-only scan. It helps explain a new device format in a dump,
    // but it is deliberately not enough to authorize a write.
    size_t best_offset = 0;
    size_t best_valid = 0;
    size_t best_known = 0;
    size_t best_count = 0;
    for (size_t offset = 0; offset + count * 4 <= profile->data_length - 2; offset++) {
        size_t valid = 0;
        size_t known = 0;
        for (size_t i = 0; i < count; i++) {
            const uint8_t *spec = profile->data + offset + i * 4;
            valid += spec_structurally_valid(spec) ? 1 : 0;
            known += spec_known(spec) ? 1 : 0;
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
    if (best_count == 1 && best_valid >= count - 1 && best_known >= 1) {
        profile->button_offset = best_offset;
        profile->valid_specs = best_valid;
        profile->known_specs = best_known;
    }
}

static bool is_g603_device(const Device *device) {
    if (device == NULL) {
        return false;
    }
    if (device->iface != NULL && device->iface->product_id == 0xB01C) {
        return true;
    }
    return text_contains_case_insensitive(device_label(device), "G603");
}

static bool profile_reports_gshift(const Profile *profile, const Device *device) {
    if ((profile->info.shift_flags & 0x03) == 0x02) {
        return true;
    }

    // G603 onboard profiles expose a real G-Shift bank on format-3 firmware,
    // but some firmware revisions do not advertise it in getInfo.shift_flags.
    // Keep this exception device- and format-specific; the bank is still
    // validated below before it can be shown or written.
    return is_g603_device(device) &&
           profile->info.profile_format == 3 &&
           profile->info.button_count == 6;
}

// Modern HID++ 0x8100 profiles place the G-Shift bank 64 bytes after the
// normal button bank. The device hint is only a candidate selector: a
// plausible-looking second bank must still pass the same record validation.
static void detect_gshift_button_layout(Profile *profile, const Device *device) {
    profile->gshift_button_offset = 0;
    profile->gshift_valid_specs = 0;
    profile->gshift_known_specs = 0;
    profile->gshift_layout_supported = false;
    if (!profile->layout_supported || !profile_reports_gshift(profile, device)) {
        return;
    }
    size_t count = profile->info.button_count;
    size_t offset = profile->button_offset + 64;
    if (offset + count * 4 > profile->data_length - 2) {
        return;
    }
    size_t valid = 0;
    size_t known = 0;
    for (size_t i = 0; i < count; i++) {
        const uint8_t *spec = profile->data + offset + i * 4;
        valid += spec_structurally_valid(spec) ? 1 : 0;
        known += spec_known(spec) ? 1 : 0;
    }
    if (valid >= count - 1 && known >= 1) {
        profile->gshift_button_offset = offset;
        profile->gshift_valid_specs = valid;
        profile->gshift_known_specs = known;
        profile->gshift_layout_supported = true;
    }
}

static uint16_t read_le16(const uint8_t *bytes) {
    return (uint16_t)((uint16_t)bytes[0] | ((uint16_t)bytes[1] << 8));
}

static void write_le16(uint8_t *bytes, uint16_t value) {
    bytes[0] = (uint8_t)(value & 0xFF);
    bytes[1] = (uint8_t)(value >> 8);
}

static bool device_uses_zero_terminated_dpi(const Device *device) {
    if (device == NULL || device->iface == NULL) {
        return false;
    }
    switch (device->iface->product_id) {
        case 0xC084: // G102/G203 family
        case 0xC092: // G203 LIGHTSYNC
        case 0xB01C: // G603 LIGHTSPEED
            return true;
        default:
            break;
    }
    return text_contains_case_insensitive(device_label(device), "G102") ||
           text_contains_case_insensitive(device_label(device), "G203") ||
           text_contains_case_insensitive(device_label(device), "G603");
}

static void detect_dpi_layout(Profile *profile, const Device *device) {
    bool zero_terminated = device_uses_zero_terminated_dpi(device);
    profile->dpi_offset = 0;
    profile->dpi_count = 0;
    profile->dpi_default_index = 0;
    profile->dpi_shift_index = 0;
    profile->dpi_unused_value = zero_terminated ? 0 : UINT16_MAX;
    profile->dpi_layout_supported = false;

    // Known format-3/4/5 sectors store one to five little-endian DPI stages at
    // offsets 3..12; unused stage slots are 0 or 0xFFFF. Bytes 1 and 2 select
    // the default and shift stages. Treat this as a validated format
    // candidate, never as a universal offset.
    if (profile->info.profile_format > 5 || profile->data_length < 15 ||
        profile->data_length - 2 < 13) {
        return;
    }
    uint16_t previous = 0;
    size_t count = 0;
    bool inactive = false;
    bool saw_unused_value = false;
    for (size_t i = 0; i < 5; i++) {
        uint16_t dpi = read_le16(profile->data + 3 + i * 2);
        // G603 format-3 firmware uses zero for unused stages, while newer
        // gaming mice commonly use 0xFFFF. Both values terminate the active
        // ascending DPI list.
        if (dpi == 0 || dpi == UINT16_MAX) {
            if (!saw_unused_value && !zero_terminated) {
                profile->dpi_unused_value = dpi;
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
    if (count == 0 || profile->data[1] >= count || profile->data[2] >= count) {
        return;
    }
    profile->dpi_offset = 3;
    profile->dpi_count = count;
    profile->dpi_default_index = profile->data[1];
    profile->dpi_shift_index = profile->data[2];
    profile->dpi_layout_supported = true;
}

static bool rgb_mode_is_known(uint8_t mode) {
    // Legacy onboard RGB records use off, solid, cycling, and breathing.
    return mode == 0x00 || mode == 0x01 || mode == 0x03 || mode == 0x0A;
}

static bool rgb_record_is_disabled(const uint8_t record[RGB_PROFILE_RECORD_BYTES]) {
    for (size_t i = 0; i < RGB_PROFILE_RECORD_BYTES; i++) {
        if (record[i] != 0xFF) {
            return false;
        }
    }
    return true;
}

static void detect_rgb_layout(Profile *profile) {
    profile->rgb_offset = 0;
    profile->rgb_zone_count = 0;
    memset(profile->rgb_zone_present, 0, sizeof(profile->rgb_zone_present));
    profile->rgb_layout_supported = false;

    // The 208..251 RGB area is part of the validated format-4/5 layout.
    // Newer formats may move or repurpose these bytes, so they stay read-only.
    if (profile->info.profile_format < 4 || profile->info.profile_format > 5 ||
        profile->data_length < RGB_PROFILE_BASE_OFFSET +
            RGB_PROFILE_RECORD_BYTES * RGB_PROFILE_RECORD_COUNT + 2) {
        return;
    }

    size_t last_present = 0;
    bool found = false;
    for (size_t index = 0; index < RGB_PROFILE_RECORD_COUNT; index++) {
        const uint8_t *record = profile->data + RGB_PROFILE_BASE_OFFSET +
            index * RGB_PROFILE_RECORD_BYTES;
        if (rgb_record_is_disabled(record)) {
            continue;
        }
        if (!rgb_mode_is_known(record[0])) {
            // Do not expose a partial layout when any populated record is not
            // proven; a later firmware variant may use a different layout.
            return;
        }
        profile->rgb_zone_present[index] = true;
        last_present = index;
        found = true;
    }
    if (!found) {
        return;
    }
    profile->rgb_offset = RGB_PROFILE_BASE_OFFSET;
    // G502 X PLUS stores its controllable LIGHTSYNC cluster in the second
    // lighting slot, leaving the first slot disabled. Keep the record index
    // stable so the UI and write path can address sparse layouts.
    profile->rgb_zone_count = last_present + 1;
    profile->rgb_layout_supported = true;
}

static bool write_rgb_zone_colors(uint8_t *data,
                                  const Profile *profile,
                                  const uint8_t zones[],
                                  const uint8_t colors[][3],
                                  size_t count) {
    if (data == NULL || profile == NULL || zones == NULL || colors == NULL ||
        !profile->rgb_layout_supported || count == 0 ||
        count > RGB_PROFILE_RECORD_COUNT ||
        profile->rgb_offset + RGB_PROFILE_RECORD_BYTES * profile->rgb_zone_count + 2 >
            profile->data_length) {
        return false;
    }
    bool seen[RGB_PROFILE_RECORD_COUNT] = {false};
    for (size_t i = 0; i < count; i++) {
        size_t zone = zones[i];
        if (zone >= profile->rgb_zone_count || seen[zone]) {
            return false;
        }
        if (!profile->rgb_zone_present[zone]) {
            return false;
        }
        seen[zone] = true;
        size_t offset = profile->rgb_offset + zone * RGB_PROFILE_RECORD_BYTES +
            RGB_PROFILE_COLOR_OFFSET;
        memcpy(data + offset, colors[i], 3);
    }
    return true;
}

static bool write_dpi_stage_table(uint8_t *data,
                                  const Profile *profile,
                                  const uint16_t *stages,
                                  size_t count) {
    if (data == NULL || profile == NULL || stages == NULL ||
        !profile->dpi_layout_supported || count == 0 || count > 5) {
        return false;
    }
    for (size_t i = 0; i < count; i++) {
        write_le16(data + profile->dpi_offset + i * 2, stages[i]);
    }
    for (size_t i = count; i < 5; i++) {
        write_le16(data + profile->dpi_offset + i * 2, profile->dpi_unused_value);
    }
    return true;
}

static int adjustable_dpi_values(Device *device,
                                 uint16_t *values,
                                 size_t *value_count,
                                 size_t value_capacity,
                                 uint8_t *sensor_count_out,
                                 uint16_t *current_out) {
    if (!device_feature_index(device, FEATURE_ADJUSTABLE_DPI, &(uint8_t){0})) {
        return 0;
    }
    const uint8_t empty_params[3] = {0, 0, 0};
    // 0x2201 uses short requests with long responses on G502 X firmware. The
    // old forced-long request was accepted inconsistently across direct USB,
    // receiver, and post-reconnect paths. device_call selects short here and
    // still applies the receiver fallback when required.
    Reply reply = device_call(device, FEATURE_ADJUSTABLE_DPI, 0x00,
                              empty_params, sizeof(empty_params), 2.0);
    if (reply.status != REPLY_OK || reply.length < 1) {
        print_reply_error("ADJUSTABLE_DPI.getSensorCount", reply);
        return 0;
    }
    uint8_t sensor_count = reply.bytes[0];

    const uint8_t sensor_params[3] = {0, 0, 0};
    reply = device_call(device, FEATURE_ADJUSTABLE_DPI, 0x10,
                        sensor_params, sizeof(sensor_params), 2.0);
    if (reply.status != REPLY_OK || reply.length < 3) {
        print_reply_error("ADJUSTABLE_DPI.getSensorDpiList", reply);
        return 0;
    }
    size_t count = 0;
    uint16_t raw[8];
    size_t raw_count = 0;
    for (size_t offset = 1; offset + 1 < reply.length && raw_count < sizeof(raw) / sizeof(raw[0]); offset += 2) {
        uint16_t value = (uint16_t)(((uint16_t)reply.bytes[offset] << 8) | reply.bytes[offset + 1]);
        if (value == 0) {
            break;
        }
        raw[raw_count++] = value;
    }
    for (size_t i = 0; i < raw_count; i++) {
        uint16_t value = raw[i];
        if ((value >> 13) == 0x07) {
            if (count == 0 || i + 1 >= raw_count) {
                return 0;
            }
            uint16_t step = value & 0x1FFF;
            uint16_t end = raw[++i];
            if (step == 0 || end < values[count - 1]) {
                return 0;
            }
            uint32_t next = (uint32_t)values[count - 1] + step;
            while (next <= end) {
                if (count >= value_capacity) {
                    return 0;
                }
                values[count++] = (uint16_t)next;
                next += step;
            }
            if (count == 0 || values[count - 1] != end) {
                if (count >= value_capacity) {
                    return 0;
                }
                values[count++] = end;
            }
        } else {
            if (count >= value_capacity) {
                return 0;
            }
            values[count++] = value;
        }
    }
    if (count == 0) {
        return 0;
    }
    *value_count = count;
    if (sensor_count_out != NULL) {
        // A few gaming-mouse firmware revisions report zero from getSensorCount
        // while still exposing a valid sensor-0 DPI list. Treat a successful
        // sensor-0 list as one sensor; never infer additional sensors.
        *sensor_count_out = sensor_count == 0 ? 1 : sensor_count;
    }
    if (current_out != NULL) {
        if (!get_current_sensor_dpi(device, 0, current_out)) {
            return 0;
        }
    }
    return 1;
}

static int load_profile_with_headers(Device *device,
                                     const ProfileInfo *info,
                                     const ProfileHeader *headers,
                                     size_t header_count,
                                     int requested_profile,
                                     Profile *profile) {
    memset(profile, 0, sizeof(*profile));
    profile->info = *info;
    profile->header_count = header_count;
    if (header_count > MAX_HEADERS) {
        return 0;
    }
    memcpy(profile->headers, headers, header_count * sizeof(*headers));
    size_t selected = 0;
    if (requested_profile > 0) {
        if ((size_t)requested_profile > header_count) {
            fprintf(stderr, "profile %d is out of range 1..%zu\n", requested_profile, header_count);
            return 0;
        }
        selected = (size_t)requested_profile - 1;
    } else {
        bool found_enabled = false;
        for (size_t i = 0; i < header_count; i++) {
            if (headers[i].enabled != 0) {
                selected = i;
                found_enabled = true;
                break;
            }
        }
        if (!found_enabled) {
            selected = 0;
        }
    }
    profile->selected_header = selected;
    profile->data_length = info->sector_size;
    profile->data = (uint8_t *)malloc(profile->data_length);
    if (profile->data == NULL) {
        return 0;
    }
    if (!read_sector(device, headers[selected].sector, profile->data_length, profile->data)) {
        free(profile->data);
        profile->data = NULL;
        return 0;
    }
    profile->crc_ok = sector_crc_ok(profile->data, profile->data_length);
    profile->crc_checked = true;
    detect_button_layout(profile);
    detect_gshift_button_layout(profile, device);
    detect_dpi_layout(profile, device);
    detect_rgb_layout(profile);
    return 1;
}

static int load_profile_summary_with_headers(Device *device,
                                             const ProfileInfo *info,
                                             const ProfileHeader *headers,
                                             size_t header_count,
                                             int requested_profile,
                                             Profile *profile) {
    memset(profile, 0, sizeof(*profile));
    profile->info = *info;
    profile->header_count = header_count;
    if (header_count > MAX_HEADERS) {
        return 0;
    }
    memcpy(profile->headers, headers, header_count * sizeof(*headers));
    size_t selected = 0;
    if (requested_profile > 0) {
        if ((size_t)requested_profile > header_count) {
            fprintf(stderr, "profile %d is out of range 1..%zu\n", requested_profile, header_count);
            return 0;
        }
        selected = (size_t)requested_profile - 1;
    } else {
        bool found_enabled = false;
        for (size_t i = 0; i < header_count; i++) {
            if (headers[i].enabled != 0) {
                selected = i;
                found_enabled = true;
                break;
            }
        }
        if (!found_enabled) {
            selected = 0;
        }
    }
    profile->selected_header = selected;

    // The GUI only needs the format prefix, DPI stages, and button records on
    // its first pass. Avoid reading the rest of a large sector; a full sector
    // read remains available to explicit reload/write paths where CRC is
    // required.
    size_t summary_length = RGB_PROFILE_BASE_OFFSET +
        RGB_PROFILE_RECORD_BYTES * RGB_PROFILE_RECORD_COUNT + 2;
    if (summary_length > info->sector_size) {
        summary_length = info->sector_size;
    }
    profile->data_length = summary_length;
    profile->data = (uint8_t *)malloc(profile->data_length);
    if (profile->data == NULL) {
        return 0;
    }
    if (!read_sector(device, headers[selected].sector, profile->data_length, profile->data)) {
        free(profile->data);
        profile->data = NULL;
        return 0;
    }
    profile->crc_ok = false;
    profile->crc_checked = false;
    detect_button_layout(profile);
    detect_gshift_button_layout(profile, device);
    detect_dpi_layout(profile, device);
    detect_rgb_layout(profile);
    return 1;
}

static int load_selected_profile(Device *device, int requested_profile, Profile *profile) {
