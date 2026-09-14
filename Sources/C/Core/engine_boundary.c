// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

#include "internal.h"

#include <stdarg.h>

static bool boundary_fail(EngineBoundaryError *error, EngineBoundaryErrorCode code,
                          const char *format, ...) {
    if (error != NULL) {
        error->code = code;
        va_list arguments;
        va_start(arguments, format);
        vsnprintf(error->message, sizeof(error->message), format, arguments);
        va_end(arguments);
    }
    return false;
}

void engine_boundary_error_clear(EngineBoundaryError *error) {
    if (error != NULL) {
        error->code = ENGINE_BOUNDARY_ERROR_NONE;
        error->message[0] = '\0';
    }
}

void engine_boundary_error_set(EngineBoundaryError *error, EngineBoundaryErrorCode code,
                               const char *message) {
    if (error == NULL) {
        return;
    }
    error->code = code;
    snprintf(error->message, sizeof(error->message), "%s", message == NULL ? "" : message);
}

const char *engine_boundary_error_code_name(EngineBoundaryErrorCode code) {
    switch (code) {
    case ENGINE_BOUNDARY_ERROR_NONE:
        return "none";
    case ENGINE_BOUNDARY_ERROR_INVALID_REQUEST:
        return "invalid_request";
    case ENGINE_BOUNDARY_ERROR_HID_CONTEXT:
        return "hid_context";
    case ENGINE_BOUNDARY_ERROR_DISCOVERY:
        return "discovery";
    case ENGINE_BOUNDARY_ERROR_DEVICE_NOT_FOUND:
        return "device_not_found";
    case ENGINE_BOUNDARY_ERROR_PROFILE_UNAVAILABLE:
        return "profile_unavailable";
    case ENGINE_BOUNDARY_ERROR_DPI_UNAVAILABLE:
        return "dpi_unavailable";
    case ENGINE_BOUNDARY_ERROR_UNSUPPORTED:
        return "unsupported";
    case ENGINE_BOUNDARY_ERROR_OPERATION:
        return "operation";
    }
    return "unknown";
}

bool engine_boundary_device_from_device(const Device *device, size_t index,
                                        EngineBoundaryDevice *result) {
    if (device == NULL || device->iface == NULL || result == NULL) {
        return false;
    }
    memset(result, 0, sizeof(*result));
    result->index = index;
    result->vendor_id = device->iface->vendor_id;
    result->product_id = device_mouse_product_id(device);
    result->device_number = device->device_number;
    result->request_device_number = device->request_device_number;
    result->protocol = device->protocol;
    snprintf(result->name, sizeof(result->name), "%s", device_label(device));
    snprintf(result->connection, sizeof(result->connection), "%s", device_connection(device));
    format_device_key(device, result->device_key, sizeof(result->device_key));
    return true;
}

static bool profile_bytes_are_in_bounds(const Profile *profile, size_t offset, size_t index,
                                        size_t stride, size_t width) {
    if (profile == NULL || profile->data == NULL || offset > profile->data_length ||
        index > (SIZE_MAX - offset) / stride) {
        return false;
    }
    size_t record_offset = offset + index * stride;
    return width <= profile->data_length - record_offset;
}

static bool profile_record_is_in_bounds(const Profile *profile, size_t offset, size_t index) {
    return profile_bytes_are_in_bounds(profile, offset, index, 4, 4);
}

static bool append_profile_button(const Profile *profile, EngineBoundaryProfile *result,
                                  size_t offset, size_t index, bool gshift) {
    if (result->button_count >= sizeof(result->buttons) / sizeof(result->buttons[0]) ||
        !profile_record_is_in_bounds(profile, offset, index)) {
        return false;
    }
    EngineBoundaryButton *button = &result->buttons[result->button_count++];
    button->number = (int)index + 1;
    button->gshift = gshift;
    memcpy(button->raw, profile->data + offset + index * 4, sizeof(button->raw));
    describe_spec(button->raw, button->description, sizeof(button->description));
    return true;
}

bool engine_boundary_profile_from_profile(const Profile *profile, EngineBoundaryProfile *result,
                                          EngineBoundaryError *error) {
    if (profile == NULL || result == NULL) {
        return boundary_fail(error, ENGINE_BOUNDARY_ERROR_INVALID_REQUEST,
                             "a profile and result are required");
    }
    memset(result, 0, sizeof(*result));
    if (profile->selected_header >= profile->header_count) {
        return boundary_fail(error, ENGINE_BOUNDARY_ERROR_PROFILE_UNAVAILABLE,
                             "the selected profile header is outside the validated header list");
    }
    result->number = (int)profile->selected_header + 1;
    result->sector = profile->headers[profile->selected_header].sector;
    result->enabled = profile->headers[profile->selected_header].enabled != 0;
    result->memory = profile->info.memory;
    result->format = profile->info.profile_format;
    result->macro_format = profile->info.macro_format;
    result->profile_capacity = profile->info.profile_count;
    result->button_capacity = profile->info.button_count;
    result->sector_count = profile->info.sector_count;
    result->sector_size = profile->info.sector_size;
    result->shift_flags = profile->info.shift_flags;
    result->crc_checked = profile->crc_checked;
    result->crc_valid = profile->crc_ok;
    result->button_layout_supported = profile->layout_supported;
    result->gshift_layout_supported = profile->gshift_layout_supported;
    result->dpi_layout_supported = profile->dpi_layout_supported;
    result->rgb_layout_supported = profile->rgb_layout_supported;

    for (size_t i = 0; i < profile->info.button_count; i++) {
        if (profile->button_offset != 0 || profile->layout_supported) {
            append_profile_button(profile, result, profile->button_offset, i, false);
        }
    }
    if (profile->gshift_layout_supported) {
        for (size_t i = 0; i < profile->info.button_count; i++) {
            append_profile_button(profile, result, profile->gshift_button_offset, i, true);
        }
    }

    if (profile->dpi_layout_supported && profile->dpi_count <= MAX_DPI_VALUES) {
        result->dpi_count = profile->dpi_count;
        result->dpi_default_stage = (uint8_t)(profile->dpi_default_index + 1);
        result->dpi_shift_stage = (uint8_t)(profile->dpi_shift_index + 1);
        for (size_t i = 0; i < result->dpi_count; i++) {
            if (!profile_bytes_are_in_bounds(profile, profile->dpi_offset, i, 2, 2)) {
                result->dpi_count = i;
                break;
            }
            result->dpi_stages[i] = read_le16(profile->data + profile->dpi_offset + i * 2);
        }
    }

    result->rgb_zone_count = profile->rgb_zone_count;
    if (result->rgb_zone_count > RGB_PROFILE_RECORD_COUNT) {
        result->rgb_zone_count = RGB_PROFILE_RECORD_COUNT;
    }
    for (size_t i = 0; i < result->rgb_zone_count; i++) {
        result->rgb_zones[i].number = i + 1;
        result->rgb_zones[i].present = profile->rgb_zone_present[i];
        if (!result->rgb_zones[i].present || profile->data == NULL ||
            profile->rgb_offset > profile->data_length ||
            i > (SIZE_MAX - profile->rgb_offset) / RGB_PROFILE_RECORD_BYTES) {
            continue;
        }
        size_t record_offset = profile->rgb_offset + i * RGB_PROFILE_RECORD_BYTES;
        if (record_offset > profile->data_length - 2 || 4 > profile->data_length - record_offset) {
            result->rgb_zones[i].present = false;
            continue;
        }
        const uint8_t *record = profile->data + record_offset;
        result->rgb_zones[i].mode = record[0];
        memcpy(result->rgb_zones[i].color, record + RGB_PROFILE_COLOR_OFFSET, 3);
    }
    return true;
}

static bool copy_selected_device(Device *devices, size_t count, const Options *options,
                                 EngineBoundaryDevice *result, Device **selected,
                                 EngineBoundaryError *error) {
    if (!select_device(devices, count, options, selected)) {
        return boundary_fail(error, ENGINE_BOUNDARY_ERROR_DEVICE_NOT_FOUND,
                             "no reachable Logitech HID++ device matched the selector");
    }
    size_t index = (size_t)(*selected - devices);
    if (!engine_boundary_device_from_device(*selected, index, result)) {
        return boundary_fail(error, ENGINE_BOUNDARY_ERROR_DEVICE_NOT_FOUND,
                             "the selected device did not contain a stable HID identity");
    }
    return true;
}

bool engine_boundary_list(const Options *options, EngineBoundaryDeviceList *result,
                          EngineBoundaryError *error) {
    (void)options;
    if (result == NULL) {
        return boundary_fail(error, ENGINE_BOUNDARY_ERROR_INVALID_REQUEST,
                             "a device-list result is required");
    }
    memset(result, 0, sizeof(*result));
    engine_boundary_error_clear(error);
    HidContext context;
    if (!hid_context_create(&context)) {
        return boundary_fail(error, ENGINE_BOUNDARY_ERROR_HID_CONTEXT,
                             "could not create the HID context");
    }
    Device devices[MAX_DEVICES];
    size_t count = 0;
    if (!discover_devices_for_list_impl(&context, -1, devices, &count, false)) {
        hid_context_release(&context);
        return boundary_fail(error, ENGINE_BOUNDARY_ERROR_DISCOVERY, "device discovery failed");
    }
    for (size_t i = 0; i < context.count; i++) {
        result->vendor_interface_count += context.items[i].is_vendor ? 1U : 0U;
    }
    for (size_t i = 0; i < count; i++) {
        if (!is_mouse_device(&devices[i]) ||
            is_duplicate_direct_mouse_endpoint(&devices[i], devices, count)) {
            continue;
        }
        if (result->count >= MAX_DEVICES ||
            !engine_boundary_device_from_device(&devices[i], i, &result->devices[result->count])) {
            hid_context_release(&context);
            return boundary_fail(error, ENGINE_BOUNDARY_ERROR_DISCOVERY,
                                 "device discovery returned an invalid or oversized device list");
        }
        result->count++;
    }
    hid_context_release(&context);
    return true;
}

static void copy_profile_headers(const ProfileHeader *headers, size_t count,
                                 EngineBoundaryProfiles *result) {
    result->header_count = count > MAX_HEADERS ? MAX_HEADERS : count;
    for (size_t i = 0; i < result->header_count; i++) {
        result->headers[i].number = (int)i + 1;
        result->headers[i].sector = headers[i].sector;
        result->headers[i].enabled = headers[i].enabled != 0;
    }
}

static size_t default_profile_index(const ProfileHeader *headers, size_t count) {
    for (size_t i = 0; i < count; i++) {
        if (headers[i].enabled != 0) {
            return i;
        }
    }
    return 0;
}

static void collect_profile_dpi(Device *device, EngineBoundaryDPI *result) {
    uint16_t values[MAX_DPI_VALUES];
    size_t value_count = 0;
    uint8_t sensor_count = 0;
    uint16_t current = 0;
    result->requested = true;
    if (!adjustable_dpi_values(device, values, &value_count, MAX_DPI_VALUES, &sensor_count,
                               &current)) {
        snprintf(result->error, sizeof(result->error),
                 "adjustable DPI feature 0x2201 is unavailable or unreadable");
        return;
    }
    result->available = true;
    result->sensor_count = sensor_count;
    result->supported_count = value_count;
    memcpy(result->supported_values, values, value_count * sizeof(values[0]));
    result->current_sensor_dpi = current;
}

static void collect_profile_report_rate(Device *device, EngineBoundaryReportRate *result) {
    ReportRateCapabilities capabilities;
    result->requested = true;
    if (!read_report_rate_capabilities(device, &capabilities)) {
        snprintf(result->error, sizeof(result->error),
                 "no readable HID++ report-rate feature (0x8061 or 0x8060)");
        return;
    }
    result->available = true;
    result->feature_id = capabilities.feature_id;
    result->rate_count = capabilities.rate_count;
    memcpy(result->rates, capabilities.rates, capabilities.rate_count * sizeof(result->rates[0]));
    result->current_valid = capabilities.current_valid;
    result->current_hertz = capabilities.current_hertz;
}

bool engine_boundary_profiles(const Options *options, EngineBoundaryProfiles *result,
                              EngineBoundaryError *error) {
    if (options == NULL || result == NULL) {
        return boundary_fail(error, ENGINE_BOUNDARY_ERROR_INVALID_REQUEST,
                             "profile options and a result are required");
    }
    memset(result, 0, sizeof(*result));
    engine_boundary_error_clear(error);
    HidContext context;
    if (!hid_context_create(&context)) {
        return boundary_fail(error, ENGINE_BOUNDARY_ERROR_HID_CONTEXT,
                             "could not create the HID context");
    }
    Device devices[MAX_DEVICES];
    size_t count = 0;
    if (!discover_devices_for_options(&context, options, devices, &count)) {
        hid_context_release(&context);
        return boundary_fail(error, ENGINE_BOUNDARY_ERROR_DISCOVERY, "device discovery failed");
    }
    Device *device = NULL;
    if (!copy_selected_device(devices, count, options, &result->device, &device, error)) {
        hid_context_release(&context);
        return false;
    }
    result->has_device = true;
    if (is_g600_device(device)) {
        hid_context_release(&context);
        return boundary_fail(error, ENGINE_BOUNDARY_ERROR_UNSUPPORTED,
                             "structured profile output does not support legacy G600 reports");
    }
    ProfileInfo info;
    if (!get_profile_info(device, &info)) {
        hid_context_release(&context);
        return boundary_fail(error, ENGINE_BOUNDARY_ERROR_PROFILE_UNAVAILABLE,
                             "feature 0x8100 did not return a usable onboard profile descriptor");
    }
    result->profile_capacity = info.profile_count;
    ProfileHeader headers[MAX_HEADERS];
    size_t header_count = 0;
    if (!read_profile_headers(device, &info, headers, &header_count)) {
        hid_context_release(&context);
        return boundary_fail(error, ENGINE_BOUNDARY_ERROR_PROFILE_UNAVAILABLE,
                             "onboard profile headers were not readable or valid");
    }
    copy_profile_headers(headers, header_count, result);

    int requested_profile = options->profile;
    if ((options->include_dpi || options->include_report_rate) && requested_profile > 0 &&
        (size_t)requested_profile > header_count) {
        requested_profile = 0;
    }
    if (options->headers_only && !options->include_dpi && !options->include_report_rate) {
        hid_context_release(&context);
        return true;
    }
    if (header_count == 0 || (requested_profile > 0 && (size_t)requested_profile > header_count)) {
        hid_context_release(&context);
        return boundary_fail(error, ENGINE_BOUNDARY_ERROR_PROFILE_UNAVAILABLE,
                             "the requested profile is outside the validated header list");
    }
    size_t selected = requested_profile > 0 ? (size_t)requested_profile - 1
                                            : default_profile_index(headers, header_count);
    Profile profile;
    int loaded = options->summary_only
                     ? load_profile_summary_with_headers(device, &info, headers, header_count,
                                                         (int)selected + 1, &profile)
                     : load_profile_with_headers(device, &info, headers, header_count,
                                                 (int)selected + 1, &profile);
    if (!loaded) {
        hid_context_release(&context);
        return boundary_fail(error, ENGINE_BOUNDARY_ERROR_PROFILE_UNAVAILABLE,
                             "the selected onboard profile sector was not readable or valid");
    }
    EngineBoundaryError profile_error;
    bool projected =
        engine_boundary_profile_from_profile(&profile, &result->selected_profile, &profile_error);
    free(profile.data);
    if (!projected) {
        hid_context_release(&context);
        return boundary_fail(error, profile_error.code, "%s", profile_error.message);
    }
    result->has_selected_profile = true;

    if (options->include_dpi) {
        collect_profile_dpi(device, &result->dpi);
        if (result->dpi.available && result->selected_profile.dpi_count > 0 &&
            result->selected_profile.dpi_count <= 5) {
            uint16_t stages[5] = {0};
            memcpy(stages, result->selected_profile.dpi_stages,
                   result->selected_profile.dpi_count * sizeof(stages[0]));
            if (recover_live_dpi_if_needed(device, result->selected_profile.number, stages,
                                           result->selected_profile.dpi_count,
                                           result->selected_profile.dpi_default_stage,
                                           result->dpi.current_sensor_dpi)) {
                result->dpi.current_sensor_dpi =
                    stages[result->selected_profile.dpi_default_stage - 1];
            }
        }
    }
    if (options->include_report_rate) {
        collect_profile_report_rate(device, &result->report_rate);
    }
    hid_context_release(&context);
    return true;
}

static bool collect_dpi_result(const Options *options, EngineBoundaryDPIResult *result,
                               bool include_profile, EngineBoundaryError *error) {
    if (options == NULL || result == NULL) {
        return boundary_fail(error, ENGINE_BOUNDARY_ERROR_INVALID_REQUEST,
                             "DPI options and a result are required");
    }
    memset(result, 0, sizeof(*result));
    engine_boundary_error_clear(error);
    HidContext context;
    if (!hid_context_create(&context)) {
        return boundary_fail(error, ENGINE_BOUNDARY_ERROR_HID_CONTEXT,
                             "could not create the HID context");
    }
    Device devices[MAX_DEVICES];
    size_t count = 0;
    if (!discover_devices_for_options(&context, options, devices, &count)) {
        hid_context_release(&context);
        return boundary_fail(error, ENGINE_BOUNDARY_ERROR_DISCOVERY, "device discovery failed");
    }
    Device *device = NULL;
    if (!copy_selected_device(devices, count, options, &result->device, &device, error)) {
        hid_context_release(&context);
        return false;
    }
    result->has_device = true;
    collect_profile_dpi(device, &result->dpi);
    if (!result->dpi.available) {
        hid_context_release(&context);
        return boundary_fail(error, ENGINE_BOUNDARY_ERROR_DPI_UNAVAILABLE, "%s", result->dpi.error);
    }
    if (include_profile && !options->sensor_only && !is_g600_device(device)) {
        Profile profile;
        if (load_selected_profile(device, options->profile, &profile)) {
            EngineBoundaryError profile_error;
            if (engine_boundary_profile_from_profile(&profile, &result->onboard_profile,
                                                     &profile_error)) {
                result->has_onboard_profile = true;
            } else {
                snprintf(result->onboard_profile_error, sizeof(result->onboard_profile_error), "%s",
                         profile_error.message);
            }
            free(profile.data);
        } else {
            snprintf(result->onboard_profile_error, sizeof(result->onboard_profile_error),
                     "the selected onboard profile was not readable");
        }
    } else if (include_profile && is_g600_device(device)) {
        snprintf(result->onboard_profile_error, sizeof(result->onboard_profile_error),
                 "legacy G600 profile reports do not expose the standard DPI layout");
    }
    hid_context_release(&context);
    return true;
}

bool engine_boundary_dpi(const Options *options, EngineBoundaryDPIResult *result,
                         EngineBoundaryError *error) {
    return collect_dpi_result(options, result, true, error);
}

bool engine_boundary_current_dpi(const Options *options, EngineBoundaryDPIResult *result,
                                 EngineBoundaryError *error) {
    return collect_dpi_result(options, result, false, error);
}

static void json_string(FILE *out, const char *value) {
    fputc('"', out);
    const unsigned char *cursor = (const unsigned char *)(value == NULL ? "" : value);
    for (; *cursor != '\0'; cursor++) {
        switch (*cursor) {
        case '"':
            fputs("\\\"", out);
            break;
        case '\\':
            fputs("\\\\", out);
            break;
        case '\b':
            fputs("\\b", out);
            break;
        case '\f':
            fputs("\\f", out);
            break;
        case '\n':
            fputs("\\n", out);
            break;
        case '\r':
            fputs("\\r", out);
            break;
        case '\t':
            fputs("\\t", out);
            break;
        default:
            if (*cursor < 0x20) {
                fprintf(out, "\\u%04X", *cursor);
            } else {
                fputc(*cursor, out);
            }
            break;
        }
    }
    fputc('"', out);
}

static void json_bool(FILE *out, bool value) { fputs(value ? "true" : "false", out); }

static void print_json_device(FILE *out, const EngineBoundaryDevice *device) {
    fprintf(out,
            "{\"index\":%zu,\"vendor_id\":%u,\"product_id\":%u,\"device_number\":%u,"
            "\"request_device_number\":%u,\"protocol\":%.1f,\"name\":",
            device->index, device->vendor_id, device->product_id, device->device_number,
            device->request_device_number, device->protocol);
    json_string(out, device->name);
    fputs(",\"connection\":", out);
    json_string(out, device->connection);
    fputs(",\"device_key\":", out);
    json_string(out, device->device_key);
    fputc('}', out);
}

static void print_json_dpi(FILE *out, const EngineBoundaryDPI *dpi) {
    fprintf(out, "{\"requested\":");
    json_bool(out, dpi->requested);
    fputs(",\"available\":", out);
    json_bool(out, dpi->available);
    fprintf(out, ",\"sensor_count\":%u,\"supported_values\":[", dpi->sensor_count);
    for (size_t i = 0; i < dpi->supported_count; i++) {
        if (i != 0) {
            fputc(',', out);
        }
        fprintf(out, "%u", dpi->supported_values[i]);
    }
    fprintf(out, "],\"current_sensor_dpi\":%u,\"error\":", dpi->current_sensor_dpi);
    json_string(out, dpi->error);
    fputc('}', out);
}

static void print_json_profile(FILE *out, const EngineBoundaryProfile *profile) {
    fprintf(out, "{\"number\":%d,\"sector\":%u,\"enabled\":", profile->number, profile->sector);
    json_bool(out, profile->enabled);
    fprintf(out,
            ",\"memory\":%u,\"format\":%u,\"macro_format\":%u,"
            "\"profile_capacity\":%u,\"button_capacity\":%u,\"sector_count\":%u,"
            "\"sector_size\":%u,\"shift_flags\":%u,\"crc_checked\":",
            profile->memory, profile->format, profile->macro_format, profile->profile_capacity,
            profile->button_capacity, profile->sector_count, profile->sector_size,
            profile->shift_flags);
    json_bool(out, profile->crc_checked);
    fputs(",\"crc_valid\":", out);
    json_bool(out, profile->crc_valid);
    fputs(",\"layouts\":{\"buttons\":", out);
    json_bool(out, profile->button_layout_supported);
    fputs(",\"gshift\":", out);
    json_bool(out, profile->gshift_layout_supported);
    fputs(",\"dpi\":", out);
    json_bool(out, profile->dpi_layout_supported);
    fputs(",\"rgb\":", out);
    json_bool(out, profile->rgb_layout_supported);
    fputs("},\"buttons\":[", out);
    for (size_t i = 0; i < profile->button_count; i++) {
        if (i != 0) {
            fputc(',', out);
        }
        const EngineBoundaryButton *button = &profile->buttons[i];
        fprintf(out, "{\"number\":%d,\"layer\":", button->number);
        json_string(out, button->gshift ? "gShift" : "normal");
        fputs(",\"raw\":[", out);
        for (size_t byte = 0; byte < sizeof(button->raw); byte++) {
            if (byte != 0) {
                fputc(',', out);
            }
            fprintf(out, "%u", button->raw[byte]);
        }
        fputs("],\"description\":", out);
        json_string(out, button->description);
        fputc('}', out);
    }
    fputs("],\"dpi_stages\":[", out);
    for (size_t i = 0; i < profile->dpi_count; i++) {
        if (i != 0) {
            fputc(',', out);
        }
        fprintf(out, "%u", profile->dpi_stages[i]);
    }
    fprintf(out, "],\"dpi_default_stage\":%u,\"dpi_shift_stage\":%u,\"rgb_zones\":[",
            profile->dpi_default_stage, profile->dpi_shift_stage);
    for (size_t i = 0; i < profile->rgb_zone_count; i++) {
        if (i != 0) {
            fputc(',', out);
        }
        fprintf(out, "{\"number\":%zu,\"present\":", profile->rgb_zones[i].number);
        json_bool(out, profile->rgb_zones[i].present);
        fprintf(out, ",\"mode\":%u,\"color\":[%u,%u,%u]}", profile->rgb_zones[i].mode,
                profile->rgb_zones[i].color[0], profile->rgb_zones[i].color[1],
                profile->rgb_zones[i].color[2]);
    }
    fputs("]}", out);
}

void engine_boundary_print_error(FILE *out, const EngineBoundaryError *error) {
    EngineBoundaryError fallback = {.code = ENGINE_BOUNDARY_ERROR_OPERATION};
    if (error == NULL) {
        snprintf(fallback.message, sizeof(fallback.message), "structured engine operation failed");
        error = &fallback;
    }
    fprintf(out, "{\"contract_version\":%d,\"ok\":false,\"error\":{\"code\":",
            LOPE_ENGINE_CONTRACT_VERSION);
    json_string(out, engine_boundary_error_code_name(error->code));
    fputs(",\"message\":", out);
    json_string(out, error->message);
    fputs("}}\n", out);
}

void engine_boundary_print_device_list_json(FILE *out, const EngineBoundaryDeviceList *result) {
    fprintf(out,
            "{\"contract_version\":%d,\"ok\":true,\"kind\":\"device_list\","
            "\"vendor_interface_count\":%zu,\"devices\":[",
            LOPE_ENGINE_CONTRACT_VERSION, result->vendor_interface_count);
    for (size_t i = 0; i < result->count; i++) {
        if (i != 0) {
            fputc(',', out);
        }
        print_json_device(out, &result->devices[i]);
    }
    fprintf(out, "],\"device_count\":%zu}\n", result->count);
}

static void print_json_report_rate(FILE *out, const EngineBoundaryReportRate *report_rate) {
    fputs("{\"requested\":", out);
    json_bool(out, report_rate->requested);
    fputs(",\"available\":", out);
    json_bool(out, report_rate->available);
    fprintf(out, ",\"feature_id\":%u,\"rates\":[", report_rate->feature_id);
    for (size_t i = 0; i < report_rate->rate_count; i++) {
        if (i != 0) {
            fputc(',', out);
        }
        fprintf(out, "{\"hertz\":%u,\"wire_value\":%u}", report_rate->rates[i].hertz,
                report_rate->rates[i].wire_value);
    }
    fputs("],\"current_valid\":", out);
    json_bool(out, report_rate->current_valid);
    fprintf(out, ",\"current_hertz\":%u,\"error\":", report_rate->current_hertz);
    json_string(out, report_rate->error);
    fputc('}', out);
}

void engine_boundary_print_profiles_json(FILE *out, const EngineBoundaryProfiles *result) {
    fprintf(out, "{\"contract_version\":%d,\"ok\":true,\"kind\":\"profiles\",\"device\":",
            LOPE_ENGINE_CONTRACT_VERSION);
    print_json_device(out, &result->device);
    fprintf(out, ",\"profile_capacity\":%u,\"headers\":[", result->profile_capacity);
    for (size_t i = 0; i < result->header_count; i++) {
        if (i != 0) {
            fputc(',', out);
        }
        fprintf(out, "{\"number\":%d,\"sector\":%u,\"enabled\":", result->headers[i].number,
                result->headers[i].sector);
        json_bool(out, result->headers[i].enabled);
        fputc('}', out);
    }
    fputs("],\"selected_profile\":", out);
    if (result->has_selected_profile) {
        print_json_profile(out, &result->selected_profile);
    } else {
        fputs("null", out);
    }
    fputs(",\"dpi\":", out);
    print_json_dpi(out, &result->dpi);
    fputs(",\"report_rate\":", out);
    print_json_report_rate(out, &result->report_rate);
    fputs("}\n", out);
}

void engine_boundary_print_dpi_json(FILE *out, const EngineBoundaryDPIResult *result,
                                    bool current_only) {
    fprintf(out, "{\"contract_version\":%d,\"ok\":true,\"kind\":", LOPE_ENGINE_CONTRACT_VERSION);
    json_string(out, current_only ? "current_dpi" : "dpi");
    fputs(",\"device\":", out);
    print_json_device(out, &result->device);
    fputs(",\"dpi\":", out);
    print_json_dpi(out, &result->dpi);
    if (!current_only) {
        fputs(",\"onboard_profile\":", out);
        if (result->has_onboard_profile) {
            print_json_profile(out, &result->onboard_profile);
        } else {
            fputs("null", out);
        }
        fputs(",\"onboard_profile_error\":", out);
        json_string(out, result->onboard_profile_error);
    }
    fputs("}\n", out);
}

void engine_boundary_print_write_json(FILE *out, const EngineBoundaryWriteResult *result) {
    fprintf(out,
            "{\"contract_version\":%d,\"ok\":true,\"kind\":\"write\","
            "\"operation\":",
            LOPE_ENGINE_CONTRACT_VERSION);
    json_string(out, result->operation);
    fputs(",\"operation_id\":", out);
    json_string(out, result->operation_id);
    fputs(",\"device\":", out);
    if (result->has_device) {
        print_json_device(out, &result->device);
    } else {
        fputs("null", out);
    }
    fprintf(out, ",\"profile\":%d,\"changed\":", result->profile);
    json_bool(out, result->changed);
    fputs(",\"dry_run\":", out);
    json_bool(out, result->dry_run);
    fputs(",\"completed\":", out);
    json_bool(out, result->completed);
    fputs(",\"planned_sectors\":[", out);
    for (size_t i = 0; i < result->planned_count; i++) {
        if (i != 0) {
            fputc(',', out);
        }
        fprintf(out, "{\"kind\":");
        json_string(out, result->planned_sectors[i].kind);
        fprintf(out, ",\"sector\":%u,\"length\":%zu}", result->planned_sectors[i].sector,
                result->planned_sectors[i].length);
    }
    fputs("],\"has_backup\":", out);
    json_bool(out, result->has_backup);
    fputs(",\"backup_path\":", out);
    json_string(out, result->backup_path);
    fprintf(out, ",\"verified_sectors\":%zu}\n", result->verified_count);
}

int engine_boundary_run(const Options *options) {
    if (options == NULL || options->command == NULL) {
        EngineBoundaryError error;
        engine_boundary_error_set(&error, ENGINE_BOUNDARY_ERROR_INVALID_REQUEST,
                                  "a structured command is required");
        engine_boundary_print_error(stdout, &error);
        return 2;
    }
    EngineBoundaryError error;
    if (strcmp(options->command, "list") == 0) {
        EngineBoundaryDeviceList result;
        if (!engine_boundary_list(options, &result, &error)) {
            engine_boundary_print_error(stdout, &error);
            return 1;
        }
        engine_boundary_print_device_list_json(stdout, &result);
        return 0;
    }
    if (strcmp(options->command, "profiles") == 0) {
        EngineBoundaryProfiles result;
        if (!engine_boundary_profiles(options, &result, &error)) {
            engine_boundary_print_error(stdout, &error);
            return 1;
        }
        engine_boundary_print_profiles_json(stdout, &result);
        return 0;
    }
    if (strcmp(options->command, "dpi") == 0 || strcmp(options->command, "current-dpi") == 0) {
        bool current_only = strcmp(options->command, "current-dpi") == 0;
        EngineBoundaryDPIResult result;
        bool ok = current_only ? engine_boundary_current_dpi(options, &result, &error)
                               : engine_boundary_dpi(options, &result, &error);
        if (!ok) {
            engine_boundary_print_error(stdout, &error);
            return 1;
        }
        engine_boundary_print_dpi_json(stdout, &result, current_only);
        return 0;
    }
    if (strcmp(options->command, "apply") == 0) {
        EngineBoundaryWriteResult result;
        memset(&result, 0, sizeof(result));
        int status = engine_apply(options, &result, &error);
        if (status != 0) {
            engine_boundary_print_error(stdout, &error);
            return status;
        }
        engine_boundary_print_write_json(stdout, &result);
        return 0;
    }
    engine_boundary_error_set(
        &error, ENGINE_BOUNDARY_ERROR_UNSUPPORTED,
        "structured output supports list, profiles, dpi, current-dpi, and apply commands");
    engine_boundary_print_error(stdout, &error);
    return 2;
}
