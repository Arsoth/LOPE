// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

#include "engine_boundary.h"
#include "commands_read.h"
#include "g600.h"
#include "hid_types.h"
#include "test_doubles.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static HidInterface *boundary_context_interfaces;
static size_t boundary_context_interface_count;

static int boundary_context_create(HidContext *context) {
    memset(context, 0, sizeof(*context));
    if (boundary_context_interface_count == 0) {
        return 1;
    }
    context->items = calloc(boundary_context_interface_count, sizeof(*context->items));
    if (context->items == NULL) {
        return 0;
    }
    memcpy(context->items, boundary_context_interfaces,
           boundary_context_interface_count * sizeof(*context->items));
    context->count = boundary_context_interface_count;
    return 1;
}

static int boundary_context_failure(HidContext *context) {
    (void)context;
    return 0;
}

static const Device *boundary_list_devices;
static size_t boundary_list_device_count;
static int boundary_list_result;

static int boundary_discover_list(HidContext *context, int requested_slot, Device *devices,
                                  size_t *count, bool inspect_features) {
    (void)context;
    (void)requested_slot;
    (void)inspect_features;
    *count = boundary_list_device_count;
    memcpy(devices, boundary_list_devices, *count * sizeof(*devices));
    return boundary_list_result;
}

static void boundary_prepare_device(HidInterface *iface, Device *device) {
    memset(iface, 0, sizeof(*iface));
    iface->vendor_id = LOGITECH_VID;
    iface->product_id = 0xC099;
    iface->is_mouse = true;
    snprintf(iface->product, sizeof(iface->product), "Boundary Mouse");
    memset(device, 0, sizeof(*device));
    device->iface = iface;
    device->device_number = 0xFF;
    device->request_device_number = 0xFF;
    device->protocol = 4.2;
    device->feature_count = 3;
    device->features[0] = (Feature){.id = FEATURE_ONBOARD_PROFILES, .index = 5};
    device->features[1] = (Feature){.id = FEATURE_ADJUSTABLE_DPI, .index = 6};
    device->features[2] = (Feature){.id = FEATURE_EXTENDED_REPORT_RATE, .index = 7};
    snprintf(device->name, sizeof(device->name), "Boundary Mouse");
}

static size_t boundary_profile_replies(const uint8_t *control, const uint8_t *profile,
                                       Reply *replies, size_t capacity) {
    Reply control_chunks[32];
    Reply profile_chunks[32];
    size_t control_count =
        build_sector_read_replies(control, MAX_HEADERS * 4 + 4, control_chunks, 32);
    size_t profile_count = build_sector_read_replies(profile, 255, profile_chunks, 32);
    size_t count = 0;
    if (capacity < 1 + control_count + profile_count) {
        return 0;
    }
    replies[count++] = k_mock_get_info_reply;
    memcpy(replies + count, control_chunks, control_count * sizeof(*replies));
    count += control_count;
    memcpy(replies + count, profile_chunks, profile_count * sizeof(*replies));
    return count + profile_count;
}

static bool output_contains(FILE *stream, const char *needle) {
    char output[32768];
    if (stream == NULL || needle == NULL) {
        return false;
    }
    fflush(stream);
    rewind(stream);
    size_t length = fread(output, 1, sizeof(output) - 1, stream);
    output[length] = '\0';
    return strstr(output, needle) != NULL;
}

int test_engine_boundary(void) {
    EngineBoundaryError error;
    engine_boundary_error_clear(&error);
    if (error.code != ENGINE_BOUNDARY_ERROR_NONE || error.message[0] != '\0') {
        fprintf(stderr, "engine boundary error-clear self-test failed\n");
        return 1;
    }
    engine_boundary_error_set(&error, ENGINE_BOUNDARY_ERROR_OPERATION, "bad \\\"request");
    if (error.code != ENGINE_BOUNDARY_ERROR_OPERATION ||
        strcmp(error.message, "bad \\\"request") != 0) {
        fprintf(stderr, "engine boundary error-set self-test failed\n");
        return 1;
    }
    for (int code = ENGINE_BOUNDARY_ERROR_NONE; code <= ENGINE_BOUNDARY_ERROR_OPERATION; code++) {
        if (strcmp(engine_boundary_error_code_name((EngineBoundaryErrorCode)code), "unknown") ==
            0) {
            fprintf(stderr, "engine boundary error-code self-test failed\n");
            return 1;
        }
    }
    if (strcmp(engine_boundary_error_code_name((EngineBoundaryErrorCode)99), "unknown") != 0) {
        fprintf(stderr, "engine boundary unknown-error self-test failed\n");
        return 1;
    }

    HidInterface iface = {
        .vendor_id = LOGITECH_VID,
        .product_id = 0xC08B,
        .location_id = 0x1234,
        .registry_id = 0x5678,
        .is_mouse = true,
    };
    snprintf(iface.product, sizeof(iface.product), "Boundary Mouse");
    snprintf(iface.transport, sizeof(iface.transport), "USB");
    Device device = {
        .iface = &iface,
        .device_number = 0xFF,
        .request_device_number = 0xFF,
        .protocol = 2.0,
    };
    snprintf(device.name, sizeof(device.name), "Boundary \"Mouse\"\n");
    EngineBoundaryDevice boundary_device;
    if (!engine_boundary_device_from_device(&device, 3, &boundary_device) ||
        boundary_device.index != 3 || boundary_device.vendor_id != LOGITECH_VID ||
        strcmp(boundary_device.name, device.name) != 0 ||
        strcmp(boundary_device.connection, "Wired") != 0 ||
        strcmp(boundary_device.device_key, "1234-5678-FF") != 0 ||
        engine_boundary_device_from_device(NULL, 0, &boundary_device) ||
        engine_boundary_device_from_device(&device, 0, NULL)) {
        fprintf(stderr, "engine boundary device projection self-test failed\n");
        return 1;
    }
    Device no_interface_device = device;
    no_interface_device.iface = NULL;
    if (engine_boundary_device_from_device(&no_interface_device, 0, &boundary_device)) {
        fprintf(stderr, "engine boundary missing-interface self-test failed\n");
        return 1;
    }

    uint8_t profile_bytes[255];
    build_mock_onboard_sector(profile_bytes);
    Profile profile = {0};
    profile.selected_header = 0;
    profile.header_count = 1;
    profile.headers[0] = (ProfileHeader){.sector = 0x0123, .enabled = 1};
    profile.info.profile_format = 5;
    profile.info.profile_count = 5;
    profile.info.button_count = 5;
    profile.info.sector_count = 1;
    profile.info.sector_size = 255;
    profile.info.shift_flags = 2;
    profile.data = profile_bytes;
    profile.data_length = sizeof(profile_bytes);
    profile.button_offset = 32;
    profile.layout_supported = true;
    profile.gshift_button_offset = 96;
    profile.gshift_layout_supported = true;
    profile.dpi_offset = 3;
    profile.dpi_count = 5;
    profile.dpi_default_index = 2;
    profile.dpi_shift_index = 0;
    profile.dpi_layout_supported = true;
    profile.rgb_offset = RGB_PROFILE_BASE_OFFSET;
    profile.rgb_zone_count = 2;
    profile.rgb_zone_present[0] = true;
    profile.rgb_zone_present[1] = true;
    profile.rgb_layout_supported = true;
    profile.crc_checked = true;
    profile.crc_ok = true;
    EngineBoundaryProfile boundary_profile;
    if (!engine_boundary_profile_from_profile(&profile, &boundary_profile, &error) ||
        boundary_profile.number != 1 || boundary_profile.sector != 0x0123 ||
        !boundary_profile.enabled || boundary_profile.format != 5 ||
        boundary_profile.button_count != 10 || boundary_profile.dpi_count != 5 ||
        boundary_profile.dpi_stages[0] != 800 || boundary_profile.dpi_default_stage != 3 ||
        boundary_profile.rgb_zone_count != 2 || boundary_profile.rgb_zones[1].color[0] != 0x40 ||
        engine_boundary_profile_from_profile(NULL, &boundary_profile, &error) ||
        engine_boundary_profile_from_profile(&profile, NULL, &error)) {
        fprintf(stderr, "engine boundary profile projection self-test failed\n");
        return 1;
    }
    EngineBoundaryProfile valid_boundary_profile = boundary_profile;
    profile.selected_header = 1;
    if (engine_boundary_profile_from_profile(&profile, &boundary_profile, &error) ||
        error.code != ENGINE_BOUNDARY_ERROR_PROFILE_UNAVAILABLE) {
        fprintf(stderr, "engine boundary invalid-profile self-test failed\n");
        return 1;
    }
    profile.selected_header = 0;

    Profile malformed_profile = profile;
    malformed_profile.selected_header = 0;
    malformed_profile.info.button_count = 2;
    malformed_profile.button_offset = sizeof(profile_bytes) + 1;
    malformed_profile.gshift_layout_supported = false;
    malformed_profile.dpi_offset = sizeof(profile_bytes) - 1;
    malformed_profile.dpi_count = 2;
    malformed_profile.rgb_offset = sizeof(profile_bytes) + 1;
    malformed_profile.rgb_zone_count = RGB_PROFILE_RECORD_COUNT + 1;
    malformed_profile.rgb_zone_present[0] = true;
    if (!engine_boundary_profile_from_profile(&malformed_profile, &boundary_profile, &error) ||
        boundary_profile.button_count != 0 || boundary_profile.dpi_count != 0 ||
        boundary_profile.rgb_zone_count != RGB_PROFILE_RECORD_COUNT) {
        fprintf(stderr, "engine boundary malformed-profile self-test failed\n");
        return 1;
    }
    Profile malformed_rgb_profile = profile;
    malformed_rgb_profile.selected_header = 0;
    malformed_rgb_profile.rgb_offset = sizeof(profile_bytes) - 1;
    malformed_rgb_profile.rgb_zone_count = 1;
    malformed_rgb_profile.rgb_zone_present[0] = true;
    if (!engine_boundary_profile_from_profile(&malformed_rgb_profile, &boundary_profile, &error) ||
        boundary_profile.rgb_zones[0].present) {
        fprintf(stderr, "engine boundary malformed-RGB self-test failed\n");
        return 1;
    }
    Profile skipped_button_profile = malformed_profile;
    skipped_button_profile.info.button_count = 1;
    skipped_button_profile.button_offset = 0;
    skipped_button_profile.layout_supported = false;
    skipped_button_profile.dpi_layout_supported = false;
    skipped_button_profile.rgb_zone_count = 0;
    if (!engine_boundary_profile_from_profile(&skipped_button_profile, &boundary_profile, &error) ||
        boundary_profile.button_count != 0) {
        fprintf(stderr, "engine boundary skipped-button self-test failed\n");
        return 1;
    }

    Profile zero_offset_profile = profile;
    zero_offset_profile.selected_header = 0;
    zero_offset_profile.info.button_count = 1;
    zero_offset_profile.button_offset = 0;
    zero_offset_profile.gshift_layout_supported = false;
    zero_offset_profile.dpi_layout_supported = false;
    zero_offset_profile.rgb_zone_count = 0;
    if (!engine_boundary_profile_from_profile(&zero_offset_profile, &boundary_profile, &error) ||
        boundary_profile.button_count != 1) {
        fprintf(stderr, "engine boundary zero-offset projection self-test failed\n");
        return 1;
    }

    Profile oversized_dpi_profile = profile;
    oversized_dpi_profile.dpi_count = MAX_DPI_VALUES + 1;
    if (!engine_boundary_profile_from_profile(&oversized_dpi_profile, &boundary_profile, &error) ||
        boundary_profile.dpi_count != 0) {
        fprintf(stderr, "engine boundary oversized-DPI projection self-test failed\n");
        return 1;
    }

    Profile null_rgb_data_profile = profile;
    null_rgb_data_profile.info.button_count = 0;
    null_rgb_data_profile.gshift_layout_supported = false;
    null_rgb_data_profile.dpi_layout_supported = false;
    null_rgb_data_profile.rgb_zone_count = 1;
    null_rgb_data_profile.rgb_zone_present[0] = true;
    null_rgb_data_profile.data = NULL;
    null_rgb_data_profile.data_length = 0;
    null_rgb_data_profile.rgb_offset = 0;
    if (!engine_boundary_profile_from_profile(&null_rgb_data_profile, &boundary_profile, &error) ||
        !boundary_profile.rgb_zones[0].present) {
        fprintf(stderr, "engine boundary null-RGB-data projection self-test failed\n");
        return 1;
    }

    Profile overflow_rgb_profile = null_rgb_data_profile;
    overflow_rgb_profile.data = profile_bytes;
    overflow_rgb_profile.data_length = SIZE_MAX;
    overflow_rgb_profile.rgb_offset = SIZE_MAX;
    overflow_rgb_profile.rgb_zone_count = 2;
    overflow_rgb_profile.rgb_zone_present[1] = true;
    if (!engine_boundary_profile_from_profile(&overflow_rgb_profile, &boundary_profile, &error) ||
        !boundary_profile.rgb_zones[1].present) {
        fprintf(stderr, "engine boundary overflow-RGB projection self-test failed\n");
        return 1;
    }

    Profile short_rgb_profile = null_rgb_data_profile;
    short_rgb_profile.data = profile_bytes;
    short_rgb_profile.data_length = RGB_PROFILE_BASE_OFFSET + 3;
    short_rgb_profile.rgb_offset = RGB_PROFILE_BASE_OFFSET;
    if (!engine_boundary_profile_from_profile(&short_rgb_profile, &boundary_profile, &error) ||
        boundary_profile.rgb_zones[0].present) {
        fprintf(stderr, "engine boundary short-RGB projection self-test failed\n");
        return 1;
    }

    HidInterface operation_iface;
    Device operation_device;
    boundary_prepare_device(&operation_iface, &operation_device);
    boundary_context_interfaces = &operation_iface;
    boundary_context_interface_count = 1;
    boundary_list_devices = &operation_device;
    boundary_list_device_count = 1;
    boundary_list_result = 1;
    DiscoverDevicesTestContext operation_discovery = {
        .devices = &operation_device, .count = 1, .result = 1};
    g_discover_devices_test_context = &operation_discovery;
    hid_context_create_impl = boundary_context_create;
    discover_devices_for_options_impl = discover_devices_for_options_test_double;
    discover_devices_for_list_impl = boundary_discover_list;

    EngineBoundaryDeviceList operation_list;
    EngineBoundaryError operation_error;
    if (!engine_boundary_list(NULL, &operation_list, &operation_error) ||
        operation_list.count != 1 || operation_list.devices[0].product_id != 0xC099) {
        fprintf(stderr, "engine boundary list operation self-test failed\n");
        return 1;
    }
    EngineBoundaryProfiles invalid_profiles;
    if (engine_boundary_list(NULL, NULL, &operation_error) ||
        engine_boundary_profiles(NULL, &invalid_profiles, &operation_error)) {
        fprintf(stderr, "engine boundary invalid-profile-argument self-test failed\n");
        return 1;
    }

    uint8_t control_bytes[255];
    build_mock_control_sector_two_profiles(control_bytes);
    Reply profile_replies[64];
    size_t profile_reply_count =
        boundary_profile_replies(control_bytes, profile_bytes, profile_replies, 64);
    ChannelRequestTestContext profile_context = {.replies = profile_replies,
                                                 .reply_count = profile_reply_count};
    g_channel_request_test_context = &profile_context;
    Options profile_options = {.device_index = -1, .profile = 1};
    EngineBoundaryProfiles operation_profiles;
    if (!engine_boundary_profiles(&profile_options, &operation_profiles, &operation_error) ||
        !operation_profiles.has_device || !operation_profiles.has_selected_profile ||
        operation_profiles.header_count != 2 ||
        operation_profiles.selected_profile.button_count != 10) {
        fprintf(stderr, "engine boundary profile operation self-test failed\n");
        return 1;
    }

    Device unstable_profile_device = operation_device;
    unstable_profile_device.iface = NULL;
    DiscoverDevicesTestContext unstable_profile_discovery = {
        .devices = &unstable_profile_device, .count = 1, .result = 1};
    g_discover_devices_test_context = &unstable_profile_discovery;
    if (engine_boundary_profiles(&profile_options, &operation_profiles, &operation_error) ||
        operation_error.code != ENGINE_BOUNDARY_ERROR_DEVICE_NOT_FOUND) {
        fprintf(stderr, "engine boundary unstable-device self-test failed\n");
        return 1;
    }
    g_discover_devices_test_context = &operation_discovery;

    uint8_t disabled_control[255];
    build_mock_control_sector_two_profiles(disabled_control);
    disabled_control[2] = 0;
    disabled_control[6] = 0;
    sector_put_crc(disabled_control, sizeof(disabled_control));
    Reply disabled_control_chunks[32];
    Reply disabled_profile_chunks[32];
    size_t disabled_control_count = build_sector_read_replies(
        disabled_control, MAX_HEADERS * 4 + 4, disabled_control_chunks,
        sizeof(disabled_control_chunks) / sizeof(disabled_control_chunks[0]));
    size_t disabled_profile_count = build_sector_read_replies(
        profile_bytes, sizeof(profile_bytes), disabled_profile_chunks,
        sizeof(disabled_profile_chunks) / sizeof(disabled_profile_chunks[0]));
    Reply disabled_profile_replies[64];
    disabled_profile_replies[0] = k_mock_get_info_reply;
    memcpy(disabled_profile_replies + 1, disabled_control_chunks,
           disabled_control_count * sizeof(disabled_control_chunks[0]));
    memcpy(disabled_profile_replies + 1 + disabled_control_count, disabled_profile_chunks,
           disabled_profile_count * sizeof(disabled_profile_chunks[0]));
    ChannelRequestTestContext disabled_profile_context = {
        .replies = disabled_profile_replies,
        .reply_count = 1 + disabled_control_count + disabled_profile_count,
        .calls = 0,
    };
    g_channel_request_test_context = &disabled_profile_context;
    Options no_enabled_profile_options = profile_options;
    no_enabled_profile_options.profile = 0;
    if (!engine_boundary_profiles(&no_enabled_profile_options, &operation_profiles,
                                  &operation_error) ||
        operation_profiles.selected_profile.number != 1) {
        fprintf(stderr, "engine boundary no-enabled-default self-test failed\n");
        return 1;
    }
    g_channel_request_test_context = &profile_context;

    profile_context.calls = 0;
    profile_options.headers_only = true;
    if (!engine_boundary_profiles(&profile_options, &operation_profiles, &operation_error) ||
        operation_profiles.has_selected_profile || operation_profiles.header_count != 2) {
        fprintf(stderr, "engine boundary header-only operation self-test failed\n");
        return 1;
    }
    profile_options.headers_only = false;

    Reply dpi_replies[8] = {
        {.status = REPLY_OK, .length = 1, .bytes = {1}},
        {.status = REPLY_OK,
         .length = 11,
         .bytes = {0x00, 0x03, 0x20, 0x04, 0xB0, 0x06, 0x40, 0x09, 0x60, 0x0C, 0x80}},
        {.status = REPLY_OK, .length = 3, .bytes = {0, 0x06, 0x40}},
    };
    const size_t dpi_reply_count = 3;
    ChannelRequestTestContext dpi_context = {.replies = dpi_replies,
                                             .reply_count = dpi_reply_count};
    g_channel_request_test_context = &dpi_context;
    Options dpi_options = {.device_index = -1, .profile = 1, .sensor_only = true};
    EngineBoundaryDPIResult operation_dpi;
    if (!engine_boundary_dpi(&dpi_options, &operation_dpi, &operation_error) ||
        !operation_dpi.dpi.available || operation_dpi.dpi.supported_count != 5 ||
        operation_dpi.dpi.current_sensor_dpi != 1600) {
        fprintf(stderr, "engine boundary DPI operation self-test failed\n");
        return 1;
    }
    dpi_context.calls = 0;
    if (!engine_boundary_current_dpi(&dpi_options, &operation_dpi, &operation_error) ||
        operation_dpi.dpi.current_sensor_dpi != 1600) {
        fprintf(stderr, "engine boundary current-DPI operation self-test failed\n");
        return 1;
    }
    if (engine_boundary_dpi(NULL, &operation_dpi, &operation_error) ||
        engine_boundary_dpi(&dpi_options, NULL, &operation_error)) {
        fprintf(stderr, "engine boundary invalid-DPI-argument self-test failed\n");
        return 1;
    }
    hid_context_create_impl = boundary_context_failure;
    if (engine_boundary_dpi(&dpi_options, &operation_dpi, &operation_error) ||
        operation_error.code != ENGINE_BOUNDARY_ERROR_HID_CONTEXT) {
        fprintf(stderr, "engine boundary DPI context failure self-test failed\n");
        return 1;
    }
    hid_context_create_impl = boundary_context_create;
    DiscoverDevicesTestContext no_device_discovery = {.devices = NULL, .count = 0, .result = 1};
    g_discover_devices_test_context = &no_device_discovery;
    if (engine_boundary_dpi(&dpi_options, &operation_dpi, &operation_error) ||
        operation_error.code != ENGINE_BOUNDARY_ERROR_DEVICE_NOT_FOUND) {
        fprintf(stderr, "engine boundary DPI selection failure self-test failed\n");
        return 1;
    }
    g_discover_devices_test_context = &operation_discovery;
    Device no_dpi_device = operation_device;
    no_dpi_device.feature_count = 1;
    no_dpi_device.features[0] = (Feature){.id = FEATURE_ONBOARD_PROFILES, .index = 5};
    DiscoverDevicesTestContext no_dpi_discovery = {
        .devices = &no_dpi_device, .count = 1, .result = 1};
    g_discover_devices_test_context = &no_dpi_discovery;
    dpi_context.calls = 0;
    if (engine_boundary_dpi(&dpi_options, &operation_dpi, &operation_error) ||
        operation_error.code != ENGINE_BOUNDARY_ERROR_DPI_UNAVAILABLE) {
        fprintf(stderr, "engine boundary DPI unavailable self-test failed\n");
        return 1;
    }
    g_discover_devices_test_context = &operation_discovery;
    g_channel_request_test_context = &dpi_context;
    dpi_context.calls = 0;
    Options dpi_profile_options = dpi_options;
    dpi_profile_options.sensor_only = false;
    Reply dpi_profile_replies[80];
    size_t dpi_profile_reply_count = dpi_reply_count;
    memcpy(dpi_profile_replies, dpi_replies, sizeof(dpi_replies));
    memcpy(dpi_profile_replies + dpi_profile_reply_count, profile_replies,
           profile_reply_count * sizeof(Reply));
    dpi_profile_reply_count += profile_reply_count;
    dpi_context.replies = dpi_profile_replies;
    dpi_context.reply_count = dpi_profile_reply_count;
    if (!engine_boundary_dpi(&dpi_profile_options, &operation_dpi, &operation_error) ||
        !operation_dpi.has_onboard_profile) {
        fprintf(stderr, "engine boundary onboard-DPI profile self-test failed\n");
        return 1;
    }
    Reply recovery_dpi_replies[7] = {
        dpi_replies[0],
        dpi_replies[1],
        {.status = REPLY_OK, .length = 3, .bytes = {0, 0x03, 0xE7}},
        {.status = REPLY_OK, .length = 2, .bytes = {0, 1}},
        k_mock_generic_ok_reply,
        {.status = REPLY_OK, .length = 1, .bytes = {2}},
        dpi_replies[2],
    };
    Reply recovery_profile_replies[80];
    memcpy(recovery_profile_replies, profile_replies, profile_reply_count * sizeof(Reply));
    memcpy(recovery_profile_replies + profile_reply_count, recovery_dpi_replies,
           sizeof(recovery_dpi_replies));
    ChannelRequestTestContext recovery_profile_context = {
        .replies = recovery_profile_replies,
        .reply_count =
            profile_reply_count + sizeof(recovery_dpi_replies) / sizeof(recovery_dpi_replies[0]),
        .calls = 0,
    };
    g_channel_request_test_context = &recovery_profile_context;
    Options recovery_profile_options = profile_options;
    recovery_profile_options.include_dpi = true;
    if (!engine_boundary_profiles(&recovery_profile_options, &operation_profiles,
                                  &operation_error) ||
        operation_profiles.dpi.current_sensor_dpi != 1600) {
        fprintf(stderr, "engine boundary DPI-recovery self-test failed\n");
        return 1;
    }
    g_channel_request_test_context = &dpi_context;
    dpi_context.replies = dpi_replies;
    dpi_context.reply_count = dpi_reply_count;
    dpi_context.calls = 0;
    HidInterface g600_dpi_iface = operation_iface;
    g600_dpi_iface.product_id = G600_PRODUCT_ID;
    Device g600_dpi_device = operation_device;
    g600_dpi_device.iface = &g600_dpi_iface;
    g600_dpi_device.features[0] = (Feature){.id = FEATURE_ADJUSTABLE_DPI, .index = 6};
    DiscoverDevicesTestContext g600_dpi_discovery = {
        .devices = &g600_dpi_device, .count = 1, .result = 1};
    g_discover_devices_test_context = &g600_dpi_discovery;
    if (!engine_boundary_dpi(&dpi_profile_options, &operation_dpi, &operation_error) ||
        strstr(operation_dpi.onboard_profile_error, "legacy G600") == NULL) {
        fprintf(stderr, "engine boundary G600-DPI profile self-test failed\n");
        return 1;
    }
    g_discover_devices_test_context = &operation_discovery;
    g_channel_request_test_context = &dpi_context;
    dpi_context.replies = dpi_replies;
    dpi_context.reply_count = dpi_reply_count;
    dpi_context.calls = 0;
    if (!engine_boundary_dpi(&dpi_profile_options, &operation_dpi, &operation_error) ||
        strstr(operation_dpi.onboard_profile_error, "not readable") == NULL) {
        fprintf(stderr, "engine boundary unreadable-DPI profile self-test failed\n");
        return 1;
    }

    Options summary_options = profile_options;
    summary_options.summary_only = true;
    g_channel_request_test_context = &profile_context;
    profile_context.calls = 0;
    (void)engine_boundary_profiles(&summary_options, &operation_profiles, &operation_error);
    Options default_profile_options = profile_options;
    default_profile_options.profile = 0;
    profile_context.calls = 0;
    if (!engine_boundary_profiles(&default_profile_options, &operation_profiles,
                                  &operation_error) ||
        operation_profiles.selected_profile.number != 1) {
        fprintf(stderr, "engine boundary default-profile self-test failed\n");
        return 1;
    }
    Options profile_optional_options = profile_options;
    profile_optional_options.include_dpi = true;
    profile_optional_options.include_report_rate = true;
    profile_context.calls = 0;
    if (!engine_boundary_profiles(&profile_optional_options, &operation_profiles,
                                  &operation_error) ||
        operation_profiles.dpi.available || operation_profiles.report_rate.available) {
        fprintf(stderr, "engine boundary optional-capability failure self-test failed\n");
        return 1;
    }
    Options report_success_options = profile_options;
    report_success_options.include_report_rate = true;
    Reply optional_success_replies[80];
    size_t optional_success_count = profile_reply_count;
    memcpy(optional_success_replies, profile_replies, profile_reply_count * sizeof(Reply));
    optional_success_replies[optional_success_count++] =
        (Reply){.status = REPLY_OK, .length = 2, .bytes = {0, 0x49}};
    optional_success_replies[optional_success_count++] =
        (Reply){.status = REPLY_OK, .length = 1, .bytes = {3}};
    profile_context.replies = optional_success_replies;
    profile_context.reply_count = optional_success_count;
    profile_context.calls = 0;
    if (!engine_boundary_profiles(&report_success_options, &operation_profiles, &operation_error) ||
        !operation_profiles.report_rate.available ||
        operation_profiles.report_rate.rate_count != 3) {
        fprintf(stderr, "engine boundary optional-capability success self-test failed\n");
        return 1;
    }
    Options dpi_boundary_options = profile_options;
    dpi_boundary_options.include_dpi = true;
    Reply dpi_boundary_replies[80];
    size_t dpi_boundary_count = profile_reply_count;
    memcpy(dpi_boundary_replies, profile_replies, profile_reply_count * sizeof(Reply));
    memcpy(dpi_boundary_replies + dpi_boundary_count, dpi_replies, sizeof(dpi_replies));
    dpi_boundary_count += sizeof(dpi_replies) / sizeof(dpi_replies[0]);
    dpi_boundary_replies[dpi_boundary_count++] =
        (Reply){.status = REPLY_OK, .length = 2, .bytes = {0, 0}};
    profile_context.replies = dpi_boundary_replies;
    profile_context.reply_count = dpi_boundary_count;
    profile_context.calls = 0;
    if (!engine_boundary_profiles(&dpi_boundary_options, &operation_profiles, &operation_error) ||
        !operation_profiles.dpi.available) {
        fprintf(stderr, "engine boundary optional-DPI success self-test failed\n");
        return 1;
    }
    profile_context.replies = profile_replies;
    profile_context.reply_count = profile_reply_count;
    profile_context.calls = 0;

    hid_context_create_impl = boundary_context_failure;
    if (engine_boundary_profiles(&profile_options, &operation_profiles, &operation_error) ||
        operation_error.code != ENGINE_BOUNDARY_ERROR_HID_CONTEXT) {
        fprintf(stderr, "engine boundary profile context failure self-test failed\n");
        return 1;
    }
    hid_context_create_impl = boundary_context_create;
    Options optional_range_options = profile_optional_options;
    optional_range_options.profile = 9;
    profile_context.calls = 0;
    (void)engine_boundary_profiles(&optional_range_options, &operation_profiles, &operation_error);

    operation_discovery.result = 0;
    if (engine_boundary_profiles(&profile_options, &operation_profiles, &operation_error) ||
        operation_error.code != ENGINE_BOUNDARY_ERROR_DISCOVERY) {
        fprintf(stderr, "engine boundary profile discovery failure self-test failed\n");
        return 1;
    }
    operation_discovery.result = 1;
    operation_discovery.count = 0;
    if (engine_boundary_profiles(&profile_options, &operation_profiles, &operation_error) ||
        operation_error.code != ENGINE_BOUNDARY_ERROR_DEVICE_NOT_FOUND) {
        fprintf(stderr, "engine boundary profile selection failure self-test failed\n");
        return 1;
    }
    operation_discovery.count = 1;
    profile_context.replies = NULL;
    profile_context.reply_count = 0;
    profile_context.calls = 0;
    if (engine_boundary_profiles(&profile_options, &operation_profiles, &operation_error) ||
        operation_error.code != ENGINE_BOUNDARY_ERROR_PROFILE_UNAVAILABLE) {
        fprintf(stderr, "engine boundary profile-info failure self-test failed\n");
        return 1;
    }
    profile_context.replies = profile_replies;
    profile_context.reply_count = profile_reply_count;
    profile_context.calls = 0;
    Reply info_only_reply = k_mock_get_info_reply;
    profile_context.replies = &info_only_reply;
    profile_context.reply_count = 1;
    if (engine_boundary_profiles(&profile_options, &operation_profiles, &operation_error) ||
        operation_error.code != ENGINE_BOUNDARY_ERROR_PROFILE_UNAVAILABLE) {
        fprintf(stderr, "engine boundary profile-header failure self-test failed\n");
        return 1;
    }
    profile_context.replies = profile_replies;
    profile_context.reply_count = profile_reply_count;
    profile_context.calls = 0;
    Options out_of_range_options = profile_options;
    out_of_range_options.profile = 9;
    if (engine_boundary_profiles(&out_of_range_options, &operation_profiles, &operation_error) ||
        operation_error.code != ENGINE_BOUNDARY_ERROR_PROFILE_UNAVAILABLE) {
        fprintf(stderr, "engine boundary profile-range failure self-test failed\n");
        return 1;
    }
    profile_context.calls = 0;
    profile_context.reply_count = 1 + (profile_reply_count - 1) / 2;
    if (engine_boundary_profiles(&profile_options, &operation_profiles, &operation_error) ||
        operation_error.code != ENGINE_BOUNDARY_ERROR_PROFILE_UNAVAILABLE) {
        fprintf(stderr, "engine boundary profile-load failure self-test failed\n");
        return 1;
    }
    profile_context.reply_count = profile_reply_count;
    profile_context.calls = 0;
    HidInterface g600_iface = operation_iface;
    g600_iface.product_id = G600_PRODUCT_ID;
    Device g600_device = operation_device;
    g600_device.iface = &g600_iface;
    DiscoverDevicesTestContext g600_discovery = {.devices = &g600_device, .count = 1, .result = 1};
    g_discover_devices_test_context = &g600_discovery;
    if (engine_boundary_profiles(&profile_options, &operation_profiles, &operation_error) ||
        operation_error.code != ENGINE_BOUNDARY_ERROR_UNSUPPORTED) {
        fprintf(stderr, "engine boundary G600-profile failure self-test failed\n");
        return 1;
    }
    g_discover_devices_test_context = &operation_discovery;

    EngineBoundaryDeviceList list_failure;
    discover_devices_for_list_impl = boundary_discover_list;
    HidInterface list_interfaces[2] = {{.is_vendor = true}, {.is_vendor = false}};
    boundary_context_interfaces = list_interfaces;
    boundary_context_interface_count = 2;
    Device list_devices[1] = {operation_device};
    list_devices[0].iface = &operation_iface;
    boundary_list_devices = list_devices;
    if (!engine_boundary_list(NULL, &list_failure, &operation_error) ||
        list_failure.vendor_interface_count != 1 || list_failure.count != 1) {
        fprintf(stderr, "engine boundary list projection self-test failed\n");
        return 1;
    }
    HidInterface list_non_mouse_iface = {.is_vendor = false};
    Device list_non_mouse = operation_device;
    list_non_mouse.iface = &list_non_mouse_iface;
    list_non_mouse.feature_count = 0;
    snprintf(list_non_mouse.name, sizeof(list_non_mouse.name), "Keyboard");
    Device list_devices_with_non_mouse[2] = {list_non_mouse, operation_device};
    boundary_list_devices = list_devices_with_non_mouse;
    boundary_list_device_count = 2;
    if (!engine_boundary_list(NULL, &list_failure, &operation_error) || list_failure.count != 1) {
        fprintf(stderr, "engine boundary list-filter self-test failed\n");
        return 1;
    }
    HidInterface duplicate_candidate_iface = {.product_id = 0x4085, .is_mouse = true};
    HidInterface duplicate_receiver_iface = {.product_id = 0xC539};
    Device duplicate_devices[2] = {0};
    duplicate_devices[0].iface = &duplicate_candidate_iface;
    duplicate_devices[0].device_number = 0xFF;
    snprintf(duplicate_devices[0].name, sizeof(duplicate_devices[0].name), "Duplicate Mouse");
    duplicate_devices[1].iface = &duplicate_receiver_iface;
    duplicate_devices[1].device_number = 1;
    snprintf(duplicate_devices[1].name, sizeof(duplicate_devices[1].name), "Duplicate Mouse");
    boundary_list_devices = duplicate_devices;
    boundary_list_device_count = 2;
    if (!engine_boundary_list(NULL, &list_failure, &operation_error) || list_failure.count != 1) {
        fprintf(stderr, "engine boundary duplicate-endpoint self-test failed\n");
        return 1;
    }
    boundary_list_devices = list_devices;
    boundary_list_device_count = 1;
    boundary_list_result = 0;
    if (engine_boundary_list(NULL, &list_failure, &operation_error) ||
        operation_error.code != ENGINE_BOUNDARY_ERROR_DISCOVERY) {
        fprintf(stderr, "engine boundary list failure self-test failed\n");
        return 1;
    }
    hid_context_create_impl = boundary_context_failure;
    if (engine_boundary_list(NULL, &list_failure, &operation_error) ||
        operation_error.code != ENGINE_BOUNDARY_ERROR_HID_CONTEXT) {
        fprintf(stderr, "engine boundary context failure self-test failed\n");
        return 1;
    }
    hid_context_create_impl = boundary_context_create;
    discover_devices_for_list_impl = discover_devices;

    EngineBoundaryDeviceList list = {0};
    list.vendor_interface_count = 1;
    list.count = 2;
    list.devices[0] = boundary_device;
    list.devices[1] = boundary_device;
    list.devices[1].index = 2;
    EngineBoundaryProfiles profiles = {0};
    profiles.has_device = true;
    profiles.device = boundary_device;
    profiles.profile_capacity = 5;
    profiles.header_count = 2;
    profiles.headers[0] =
        (EngineBoundaryProfileHeader){.number = 1, .sector = 0x0123, .enabled = true};
    profiles.headers[1] =
        (EngineBoundaryProfileHeader){.number = 2, .sector = 0x0200, .enabled = false};
    profiles.has_selected_profile = true;
    profiles.selected_profile = valid_boundary_profile;
    profiles.dpi.requested = true;
    profiles.dpi.available = true;
    profiles.dpi.sensor_count = 1;
    profiles.dpi.supported_count = 2;
    profiles.dpi.supported_values[0] = 800;
    profiles.dpi.supported_values[1] = 1600;
    profiles.dpi.current_sensor_dpi = 800;
    profiles.report_rate.requested = true;
    profiles.report_rate.available = true;
    profiles.report_rate.rate_count = 2;
    profiles.report_rate.rates[0] = (ReportRateEntry){.hertz = 1000, .wire_value = 4};
    profiles.report_rate.rates[1] = (ReportRateEntry){.hertz = 500, .wire_value = 8};
    profiles.report_rate.current_valid = true;
    profiles.report_rate.current_hertz = 1000;

    EngineBoundaryDPIResult dpi = {0};
    dpi.has_device = true;
    dpi.device = boundary_device;
    dpi.dpi = profiles.dpi;
    dpi.has_onboard_profile = true;
    dpi.onboard_profile = valid_boundary_profile;
    snprintf(dpi.onboard_profile_error, sizeof(dpi.onboard_profile_error), "none");
    EngineBoundaryWriteResult write = {0};
    snprintf(write.operation, sizeof(write.operation), "apply");
    snprintf(write.operation_id, sizeof(write.operation_id), "test-1");
    write.has_device = true;
    write.device = boundary_device;
    write.profile = 1;
    write.changed = true;
    write.dry_run = true;
    write.completed = true;
    write.planned_count = 2;
    snprintf(write.planned_sectors[0].kind, sizeof(write.planned_sectors[0].kind), "profile");
    write.planned_sectors[0].sector = 0x0123;
    write.planned_sectors[0].length = 255;
    snprintf(write.planned_sectors[1].kind, sizeof(write.planned_sectors[1].kind), "control");
    write.planned_sectors[1].sector = 0x0001;
    write.planned_sectors[1].length = 255;
    write.has_backup = true;
    snprintf(write.backup_path, sizeof(write.backup_path), "/tmp/test.backup");
    write.verified_count = 1;

    EngineBoundaryDevice escaped_device = {0};
    escaped_device.index = 1;
    snprintf(escaped_device.name, sizeof(escaped_device.name),
             "quote\" slash\\ back\b form\f line\n return\r tab\t control\x01");
    EngineBoundaryDeviceList escaped_list = {.count = 1};
    escaped_list.devices[0] = escaped_device;
    EngineBoundaryProfiles empty_profiles = profiles;
    empty_profiles.has_selected_profile = false;
    empty_profiles.header_count = 0;
    EngineBoundaryDPIResult empty_dpi = dpi;
    empty_dpi.has_onboard_profile = false;
    EngineBoundaryWriteResult empty_write = write;
    empty_write.has_device = false;
    empty_write.planned_count = 0;

    FILE *stream = tmpfile();
    if (stream == NULL) {
        fprintf(stderr, "engine boundary temporary-stream self-test failed\n");
        return 1;
    }
    engine_boundary_print_device_list_json(stream, &list);
    engine_boundary_print_device_list_json(stream, &escaped_list);
    engine_boundary_print_profiles_json(stream, &profiles);
    engine_boundary_print_profiles_json(stream, &empty_profiles);
    engine_boundary_print_dpi_json(stream, &dpi, false);
    engine_boundary_print_dpi_json(stream, &dpi, true);
    engine_boundary_print_dpi_json(stream, &empty_dpi, false);
    engine_boundary_print_write_json(stream, &write);
    engine_boundary_print_write_json(stream, &empty_write);
    engine_boundary_print_error(stream, &error);
    engine_boundary_print_error(stream, NULL);
    bool device_json = output_contains(stream, "\"kind\":\"device_list\"");
    bool profiles_json = output_contains(stream, "\"kind\":\"profiles\"");
    bool dpi_json = output_contains(stream, "\"kind\":\"dpi\"");
    bool current_dpi_json = output_contains(stream, "\"kind\":\"current_dpi\"");
    bool write_json = output_contains(stream, "\"kind\":\"write\"");
    bool error_json = output_contains(stream, "\"ok\":false");
    bool escaped_json = output_contains(stream, "Boundary");
    bool json_ok = device_json && profiles_json && dpi_json && current_dpi_json && write_json &&
                   error_json && escaped_json;
    if (!json_ok) {
        fprintf(stderr, "engine boundary JSON projection self-test failed\n");
        fclose(stream);
        return 1;
    }
    fclose(stream);

    if (engine_boundary_run(NULL) != 2) {
        fprintf(stderr, "engine boundary invalid-request self-test failed\n");
        return 1;
    }
    Options unsupported = {.command = "unsupported"};
    if (engine_boundary_run(&unsupported) != 2) {
        fprintf(stderr, "engine boundary unsupported-command self-test failed\n");
        return 1;
    }
    g_discover_devices_test_context = &operation_discovery;
    discover_devices_for_list_impl = boundary_discover_list;
    boundary_list_result = 1;
    Options run_list = {.command = "list"};
    if (engine_boundary_run(&run_list) != 0) {
        fprintf(stderr, "engine boundary list-dispatch self-test failed\n");
        return 1;
    }
    boundary_list_result = 0;
    if (engine_boundary_run(&run_list) != 1) {
        fprintf(stderr, "engine boundary list-error-dispatch self-test failed\n");
        return 1;
    }
    boundary_list_result = 1;
    discover_devices_for_options_impl = discover_devices_for_options_test_double;
    g_discover_devices_test_context = &operation_discovery;
    g_channel_request_test_context = &profile_context;
    profile_context.replies = profile_replies;
    profile_context.reply_count = profile_reply_count;
    profile_context.calls = 0;
    Options run_profiles = {.command = "profiles", .device_index = -1, .profile = 1};
    if (engine_boundary_run(&run_profiles) != 0) {
        fprintf(stderr, "engine boundary profiles-dispatch self-test failed\n");
        return 1;
    }
    operation_discovery.result = 0;
    if (engine_boundary_run(&run_profiles) != 1) {
        fprintf(stderr, "engine boundary profiles-error-dispatch self-test failed\n");
        return 1;
    }
    operation_discovery.result = 1;
    g_channel_request_test_context = &dpi_context;
    dpi_context.calls = 0;
    Options run_dpi = {.command = "dpi", .device_index = -1, .profile = 1, .sensor_only = true};
    if (engine_boundary_run(&run_dpi) != 0) {
        fprintf(stderr, "engine boundary DPI-dispatch self-test failed\n");
        return 1;
    }
    operation_discovery.result = 0;
    if (engine_boundary_run(&run_dpi) != 1) {
        fprintf(stderr, "engine boundary DPI-error-dispatch self-test failed\n");
        return 1;
    }
    operation_discovery.result = 1;
    dpi_context.calls = 0;
    Options run_current_dpi = run_dpi;
    run_current_dpi.command = "current-dpi";
    if (engine_boundary_run(&run_current_dpi) != 0) {
        fprintf(stderr, "engine boundary current-DPI-dispatch self-test failed\n");
        return 1;
    }

    Options run_apply = {.command = "apply",
                         .device_index = -1,
                         .profile = 1,
                         .dpi_default = -1,
                         .dpi_shift = -1,
                         .operation_id = "boundary-noop"};
    run_apply.profile_state_changes[0] = "1:enable";
    run_apply.profile_state_change_count = 1;
    operation_discovery.count = 0;
    if (engine_boundary_run(&run_apply) != 1) {
        fprintf(stderr, "engine boundary apply-error-dispatch self-test failed\n");
        return 1;
    }
    operation_discovery.count = 1;
    Reply apply_noop_control_chunks[32];
    size_t apply_noop_control_count = build_sector_read_replies(
        control_bytes, sizeof(control_bytes), apply_noop_control_chunks,
        sizeof(apply_noop_control_chunks) / sizeof(apply_noop_control_chunks[0]));
    Reply apply_noop_replies[40];
    apply_noop_replies[0] = k_mock_get_info_reply;
    memcpy(apply_noop_replies + 1, apply_noop_control_chunks,
           apply_noop_control_count * sizeof(apply_noop_control_chunks[0]));
    ChannelRequestTestContext apply_noop_context = {
        .replies = apply_noop_replies,
        .reply_count = apply_noop_control_count + 1,
        .calls = 0,
    };
    g_channel_request_test_context = &apply_noop_context;
    if (engine_boundary_run(&run_apply) != 0) {
        fprintf(stderr, "engine boundary apply-dispatch self-test failed\n");
        return 1;
    }
    return 0;
}
