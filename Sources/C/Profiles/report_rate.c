// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

// HID++ report-rate support is connection-scoped.  0x8061's actual list
// query is therefore preferred over the device-wide 0x8060 list whenever the
// feature is present; it is the only list this module exposes to callers.

#include "report_rate.h"
#include "commands_read.h"
#include "hid_discovery.h"
#include "hid_transport.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

uint32_t report_rate_hertz_from_interval(uint8_t milliseconds) {
    if (milliseconds == 0) {
        return 0;
    }
    // The UI presents integer polling rates. Keep the original millisecond
    // value in wire_value so a rounded label such as 333 Hz still writes the
    // exact 3 ms value reported by a legacy 0x8060 device.
    return (1000u + milliseconds / 2u) / milliseconds;
}

size_t report_rate_entries_from_mask(uint16_t feature_id, uint16_t mask, ReportRateEntry *entries,
                                     size_t capacity) {
    if (entries == NULL || capacity == 0) {
        return 0;
    }

    size_t count = 0;
    if (feature_id == FEATURE_EXTENDED_REPORT_RATE) {
        static const uint32_t extended_rates[MAX_REPORT_RATES] = {125,  250,  500,  1000,
                                                                  2000, 4000, 8000, 0};
        for (uint8_t index = 0; index < 7 && count < capacity; index++) {
            if ((mask & (uint16_t)(1u << index)) != 0) {
                entries[count++] = (ReportRateEntry){extended_rates[index], index};
            }
        }
        return count;
    }

    if (feature_id == FEATURE_ADJUSTABLE_REPORT_RATE) {
        // 0x8060 reports intervals in milliseconds. Iterate backwards so
        // the derived Hz values remain ascending in CLI output and Swift.
        for (int milliseconds = 8; milliseconds >= 1 && count < capacity; milliseconds--) {
            uint16_t bit = (uint16_t)(1u << (milliseconds - 1));
            if ((mask & bit) != 0) {
                entries[count++] = (ReportRateEntry){
                    report_rate_hertz_from_interval((uint8_t)milliseconds), (uint8_t)milliseconds};
            }
        }
    }
    return count;
}

uint8_t report_rate_connection_type(const Device *device) {
    // HID++ 0x8061 defines 0 as wired USB and 1 as gaming wireless. The
    // discovery layer's connection names are the existing source of truth;
    // Bluetooth/Bolt/Unifying devices are treated as wired for this feature,
    // since 0x8061's active-list query remains authoritative for visibility.
    if (device == NULL || device->iface == NULL) {
        return 0;
    }
    const char *connection = device_connection(device);
    return connection != NULL &&
                   (strcmp(connection, "LIGHTSPEED") == 0 || strcmp(connection, "Wireless") == 0)
               ? 1
               : 0;
}

bool read_report_rate_capabilities(Device *device, ReportRateCapabilities *capabilities) {
    if (device == NULL || capabilities == NULL) {
        return false;
    }
    memset(capabilities, 0, sizeof(*capabilities));

    uint8_t unused_index = 0;
    if (device_feature_index(device, FEATURE_EXTENDED_REPORT_RATE, &unused_index)) {
        capabilities->feature_id = FEATURE_EXTENDED_REPORT_RATE;
        const uint8_t params[3] = {0, 0, 0};
        Reply reply =
            device_call(device, FEATURE_EXTENDED_REPORT_RATE, 0x10, params, sizeof(params), 1.0);
        if (reply.status != REPLY_OK || reply.length < 2) {
            return false;
        }
        capabilities->supported_mask = (uint16_t)(((uint16_t)reply.bytes[0] << 8) | reply.bytes[1]);
        capabilities->rate_count =
            report_rate_entries_from_mask(capabilities->feature_id, capabilities->supported_mask,
                                          capabilities->rates, MAX_REPORT_RATES);
        if (capabilities->rate_count == 0) {
            return false;
        }

        const uint8_t connection_params[3] = {report_rate_connection_type(device), 0, 0};
        reply = device_call(device, FEATURE_EXTENDED_REPORT_RATE, 0x20, connection_params,
                            sizeof(connection_params), 1.0);
        if (reply.status == REPLY_OK && reply.length >= 1 && reply.bytes[0] < 7) {
            // The response is the enum/bit position, while rates is compacted
            // to only the set bits. Find the matching entry rather than using
            // the enum as an array offset.
            for (size_t i = 0; i < capabilities->rate_count; i++) {
                if (capabilities->rates[i].wire_value == reply.bytes[0]) {
                    capabilities->current_hertz = capabilities->rates[i].hertz;
                    capabilities->current_valid = true;
                    break;
                }
            }
        }
        return true;
    }

    if (device_feature_index(device, FEATURE_ADJUSTABLE_REPORT_RATE, &unused_index)) {
        capabilities->feature_id = FEATURE_ADJUSTABLE_REPORT_RATE;
        const uint8_t params[3] = {0, 0, 0};
        Reply reply =
            device_call(device, FEATURE_ADJUSTABLE_REPORT_RATE, 0x00, params, sizeof(params), 1.0);
        if (reply.status != REPLY_OK || reply.length < 1) {
            return false;
        }
        capabilities->supported_mask = reply.bytes[0];
        capabilities->rate_count =
            report_rate_entries_from_mask(capabilities->feature_id, capabilities->supported_mask,
                                          capabilities->rates, MAX_REPORT_RATES);
        if (capabilities->rate_count == 0) {
            return false;
        }

        reply =
            device_call(device, FEATURE_ADJUSTABLE_REPORT_RATE, 0x10, params, sizeof(params), 1.0);
        if (reply.status == REPLY_OK && reply.length >= 1 && reply.bytes[0] >= 1 &&
            reply.bytes[0] <= 8) {
            capabilities->current_hertz = report_rate_hertz_from_interval(reply.bytes[0]);
            capabilities->current_valid =
                (capabilities->supported_mask & (uint16_t)(1u << (reply.bytes[0] - 1))) != 0;
            if (!capabilities->current_valid) {
                capabilities->current_hertz = 0;
            }
        }
        return true;
    }

    return false;
}

void print_report_rate_capabilities(const ReportRateCapabilities *capabilities) {
    printf("Report rate feature: 0x%04X\n", capabilities->feature_id);
    printf("Supported polling rates: ");
    for (size_t i = 0; i < capabilities->rate_count; i++) {
        if (i != 0) {
            printf(", ");
        }
        printf("%u", capabilities->rates[i].hertz);
    }
    printf("\n");
    if (capabilities->current_valid) {
        printf("Current polling rate: %u Hz\n", capabilities->current_hertz);
    } else {
        printf("Report rate error: current polling rate could not be read\n");
    }
}

bool parse_report_rate_hertz(const char *text, uint32_t *hertz) {
    if (text == NULL || hertz == NULL || *text == '\0') {
        return false;
    }
    errno = 0;
    char *end = NULL;
    unsigned long parsed = strtoul(text, &end, 10);
    if (errno != 0 || end == text || *end != '\0' || parsed == 0 || parsed > UINT32_MAX) {
        return false;
    }
    *hertz = (uint32_t)parsed;
    return true;
}

// The onboard profile format stores the report interval in milliseconds at
// byte zero. The first four 0x8061 values are the same 8/4/2/1 ms intervals;
// the 2000/4000/8000 Hz values are connection-level only and cannot be saved
// in this profile field without changing the profile format.
bool report_rate_profile_interval(Device *device, uint32_t requested_hertz, uint8_t *milliseconds) {
    if (device == NULL || milliseconds == NULL) {
        return false;
    }
    ReportRateCapabilities capabilities;
    if (!read_report_rate_capabilities(device, &capabilities)) {
        fprintf(stderr,
                "refusing to save profile polling rate: no readable HID++ report-rate feature\n");
        return false;
    }
    for (size_t i = 0; i < capabilities.rate_count; i++) {
        const ReportRateEntry entry = capabilities.rates[i];
        if (entry.hertz != requested_hertz) {
            continue;
        }
        if (capabilities.feature_id == FEATURE_ADJUSTABLE_REPORT_RATE && entry.wire_value >= 1 &&
            entry.wire_value <= 8) {
            *milliseconds = entry.wire_value;
            return true;
        }
        if (capabilities.feature_id == FEATURE_EXTENDED_REPORT_RATE && entry.wire_value <= 3) {
            static const uint8_t extended_intervals[] = {8, 4, 2, 1};
            *milliseconds = extended_intervals[entry.wire_value];
            return true;
        }
        fprintf(stderr,
                "refusing to save profile polling rate: %u Hz is not representable in the onboard "
                "profile format\n",
                requested_hertz);
        return false;
    }
    fprintf(
        stderr,
        "refusing to save profile polling rate: %u Hz is not supported on the active connection\n",
        requested_hertz);
    return false;
}

int run_set_report_rate(const Options *options) {
    uint32_t requested_hertz = 0;
    if (!parse_report_rate_hertz(options->positionals[0], &requested_hertz)) {
        fprintf(stderr, "set-report-rate requires a positive integer rate in Hz\n");
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

    ReportRateCapabilities capabilities;
    if (!read_report_rate_capabilities(device, &capabilities)) {
        fprintf(stderr, "report-rate feature 0x8061/0x8060 is unavailable or unreadable\n");
        hid_context_release(&context);
        return 1;
    }

    const ReportRateEntry *selected = NULL;
    for (size_t i = 0; i < capabilities.rate_count; i++) {
        if (capabilities.rates[i].hertz == requested_hertz) {
            selected = &capabilities.rates[i];
            break;
        }
    }
    if (selected == NULL) {
        fprintf(stderr,
                "refusing to set polling rate: %u Hz is not supported on the active connection\n",
                requested_hertz);
        hid_context_release(&context);
        return 1;
    }

    uint8_t params[3] = {selected->wire_value, 0, 0};
    uint8_t function = capabilities.feature_id == FEATURE_EXTENDED_REPORT_RATE ? 0x30 : 0x20;
    Reply reply =
        device_call(device, capabilities.feature_id, function, params, sizeof(params), 1.0);
    if (reply.status != REPLY_OK) {
        print_reply_error("set polling rate", reply);
        hid_context_release(&context);
        return 1;
    }

    ReportRateCapabilities verified;
    if (!read_report_rate_capabilities(device, &verified) || !verified.current_valid ||
        verified.current_hertz != requested_hertz) {
        fprintf(stderr, "polling-rate write was not verified by a current-rate read-back\n");
        hid_context_release(&context);
        return 1;
    }
    print_report_rate_capabilities(&verified);
    printf("Verified polling rate: %u Hz\n", verified.current_hertz);
    hid_context_release(&context);
    return 0;
}
