// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

#ifndef LOPE_LOGITECH_ONBOARD_ENGINE_BOUNDARY_H
#define LOPE_LOGITECH_ONBOARD_ENGINE_BOUNDARY_H

#include "types.h"

#include <stdio.h>

// This is the version of the process-facing structured contract, not a
// protocol or backup-format version. A GUI must reject a response whose
// contract_version it does not understand.
#define LOPE_ENGINE_CONTRACT_VERSION 1
#define ENGINE_BOUNDARY_MAX_BUTTONS 255
#define ENGINE_BOUNDARY_MAX_SECTORS 2

typedef enum {
    ENGINE_BOUNDARY_ERROR_NONE = 0,
    ENGINE_BOUNDARY_ERROR_INVALID_REQUEST,
    ENGINE_BOUNDARY_ERROR_HID_CONTEXT,
    ENGINE_BOUNDARY_ERROR_DISCOVERY,
    ENGINE_BOUNDARY_ERROR_DEVICE_NOT_FOUND,
    ENGINE_BOUNDARY_ERROR_PROFILE_UNAVAILABLE,
    ENGINE_BOUNDARY_ERROR_DPI_UNAVAILABLE,
    ENGINE_BOUNDARY_ERROR_UNSUPPORTED,
    ENGINE_BOUNDARY_ERROR_OPERATION,
} EngineBoundaryErrorCode;

typedef struct {
    EngineBoundaryErrorCode code;
    char message[512];
} EngineBoundaryError;

typedef struct {
    size_t index;
    uint32_t vendor_id;
    uint32_t product_id;
    uint8_t device_number;
    uint8_t request_device_number;
    double protocol;
    char name[256];
    char connection[128];
    char device_key[64];
} EngineBoundaryDevice;

typedef struct {
    EngineBoundaryDevice devices[MAX_DEVICES];
    size_t count;
    size_t vendor_interface_count;
} EngineBoundaryDeviceList;

typedef struct {
    int number;
    uint16_t sector;
    bool enabled;
} EngineBoundaryProfileHeader;

typedef struct {
    int number;
    bool gshift;
    uint8_t raw[4];
    char description[160];
} EngineBoundaryButton;

typedef struct {
    int number;
    uint16_t sector;
    bool enabled;
    uint8_t memory;
    uint8_t format;
    uint8_t macro_format;
    uint8_t profile_capacity;
    uint8_t button_capacity;
    uint8_t sector_count;
    uint16_t sector_size;
    uint8_t shift_flags;
    bool crc_checked;
    bool crc_valid;
    bool button_layout_supported;
    bool gshift_layout_supported;
    bool dpi_layout_supported;
    bool rgb_layout_supported;
    EngineBoundaryButton buttons[ENGINE_BOUNDARY_MAX_BUTTONS * 2];
    size_t button_count;
    uint16_t dpi_stages[MAX_DPI_VALUES];
    size_t dpi_count;
    uint8_t dpi_default_stage;
    uint8_t dpi_shift_stage;
    struct {
        size_t number;
        bool present;
        uint8_t mode;
        uint8_t color[3];
    } rgb_zones[RGB_PROFILE_RECORD_COUNT];
    size_t rgb_zone_count;
} EngineBoundaryProfile;

typedef struct {
    bool requested;
    bool available;
    uint8_t sensor_count;
    uint16_t supported_values[MAX_DPI_VALUES];
    size_t supported_count;
    uint16_t current_sensor_dpi;
    char error[256];
} EngineBoundaryDPI;

typedef struct {
    bool requested;
    bool available;
    uint16_t feature_id;
    ReportRateEntry rates[MAX_REPORT_RATES];
    size_t rate_count;
    bool current_valid;
    uint32_t current_hertz;
    char error[256];
} EngineBoundaryReportRate;

typedef struct {
    bool has_device;
    EngineBoundaryDevice device;
    uint8_t profile_capacity;
    EngineBoundaryProfileHeader headers[MAX_HEADERS];
    size_t header_count;
    bool has_selected_profile;
    EngineBoundaryProfile selected_profile;
    EngineBoundaryDPI dpi;
    EngineBoundaryReportRate report_rate;
} EngineBoundaryProfiles;

typedef struct {
    bool has_device;
    EngineBoundaryDevice device;
    EngineBoundaryDPI dpi;
    bool has_onboard_profile;
    EngineBoundaryProfile onboard_profile;
    char onboard_profile_error[256];
} EngineBoundaryDPIResult;

typedef struct {
    char kind[16];
    uint16_t sector;
    size_t length;
} EngineBoundaryWriteSector;

typedef struct {
    char operation[16];
    char operation_id[96];
    bool has_device;
    EngineBoundaryDevice device;
    int profile;
    bool changed;
    bool dry_run;
    bool completed;
    EngineBoundaryWriteSector planned_sectors[ENGINE_BOUNDARY_MAX_SECTORS];
    size_t planned_count;
    bool has_backup;
    char backup_path[512];
    size_t verified_count;
} EngineBoundaryWriteResult;

void engine_boundary_error_clear(EngineBoundaryError *error);
void engine_boundary_error_set(EngineBoundaryError *error, EngineBoundaryErrorCode code,
                               const char *message);
const char *engine_boundary_error_code_name(EngineBoundaryErrorCode code);

// These operations own their HID context and return only typed, presentation-
// independent values. They never write to stdout. Low-level transport errors
// may still be emitted to stderr for diagnostics.
bool engine_boundary_list(const Options *options, EngineBoundaryDeviceList *result,
                          EngineBoundaryError *error);
bool engine_boundary_profiles(const Options *options, EngineBoundaryProfiles *result,
                              EngineBoundaryError *error);
bool engine_boundary_dpi(const Options *options, EngineBoundaryDPIResult *result,
                         EngineBoundaryError *error);
bool engine_boundary_current_dpi(const Options *options, EngineBoundaryDPIResult *result,
                                 EngineBoundaryError *error);

// The batch writer is implemented beside the existing write operation so the
// human CLI and the structured boundary execute the same validation, backup,
// write, and read-back path.
int engine_apply(const Options *options, EngineBoundaryWriteResult *result,
                 EngineBoundaryError *error);

// Shared typed projection helpers. Keeping these separate from the JSON
// writer makes the contract usable by a future in-process C caller too.
bool engine_boundary_device_from_device(const Device *device, size_t index,
                                        EngineBoundaryDevice *result);
bool engine_boundary_profile_from_profile(const Profile *profile, EngineBoundaryProfile *result,
                                          EngineBoundaryError *error);

// Dispatches the structured process contract and writes exactly one JSON
// document to stdout. Human-readable diagnostics remain on stderr.
int engine_boundary_run(const Options *options);

void engine_boundary_print_error(FILE *out, const EngineBoundaryError *error);
void engine_boundary_print_device_list_json(FILE *out, const EngineBoundaryDeviceList *result);
void engine_boundary_print_profiles_json(FILE *out, const EngineBoundaryProfiles *result);
void engine_boundary_print_dpi_json(FILE *out, const EngineBoundaryDPIResult *result,
                                    bool current_only);
void engine_boundary_print_write_json(FILE *out, const EngineBoundaryWriteResult *result);

#endif // LOPE_LOGITECH_ONBOARD_ENGINE_BOUNDARY_H
