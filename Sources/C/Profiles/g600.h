#ifndef LOPE_LOGITECH_ONBOARD_G600_H
#define LOPE_LOGITECH_ONBOARD_G600_H

#include "types.h"

#define G600_PRODUCT_ID 0xC24A
#define G600_PROFILE_COUNT 3
#define G600_BUTTON_COUNT 20
#define G600_REPORT_BYTES 154
#define G600_NORMAL_BUTTON_OFFSET 31
#define G600_GSHIFT_BUTTON_OFFSET 94
#define G600_FIRST_PROFILE_REPORT 0xF3
#define G600_BACKUP_PROFILE_FORMAT 0xFF

typedef bool (*G600FeatureReportGetFn)(HidChannel *channel, uint8_t report_id, uint8_t *report,
                                       size_t capacity, size_t *length);
typedef bool (*G600FeatureReportSetFn)(HidChannel *channel, uint8_t report_id, uint8_t *report,
                                       size_t length);

// Test seam for the legacy feature-report transport. Production code leaves
// these pointed at the HID transport wrappers; self-tests replace them with
// deterministic fixture-backed functions.
extern G600FeatureReportGetFn g600_get_feature_report_impl;
extern G600FeatureReportSetFn g600_set_feature_report_impl;

bool is_g600_device(const Device *device);
bool g600_profile_report_id(int profile_number, uint8_t *report_id);
uint16_t g600_profile_sector(int profile_number);
bool g600_read_profile(Device *device, int profile_number, uint8_t report[G600_REPORT_BYTES]);
bool g600_write_profile(Device *device, int profile_number, uint8_t report[G600_REPORT_BYTES]);
void g600_native_to_spec(const uint8_t native[3], uint8_t spec[4]);
bool g600_spec_to_native(const uint8_t spec[4], uint8_t native[3]);
void g600_describe_native(const uint8_t native[3], char *out, size_t out_size);
void g600_print_hex4(const uint8_t bytes[4]);
void g600_print_profile_summary(int profile_number, const uint8_t report[G600_REPORT_BYTES],
                                bool show_buttons);
int run_g600_info(const Options *options, Device *device);
int run_g600_profiles(const Options *options, Device *device);
int run_g600_apply(const Options *options, Device *device, const int *requested_buttons,
                   const bool *requested_gshift, const uint8_t requested_specs[][4],
                   size_t requested_count, const char *operation_id);
int run_g600_dump(const Options *options, Device *device);
int run_g600_restore(const Options *options, Device *device, const BackupPackage *package);
bool g600_make_backup_path(const Options *options, const char *operation_id, char path[512]);

#endif // LOPE_LOGITECH_ONBOARD_G600_H
