#ifndef LOPE_LOGITECH_ONBOARD_PROFILE_IO_H
#define LOPE_LOGITECH_ONBOARD_PROFILE_IO_H

#include "types.h"

uint16_t crc16_ccitt_false(const uint8_t *bytes, size_t length);
bool sector_crc_ok(const uint8_t *bytes, size_t length);
void sector_put_crc(uint8_t *bytes, size_t length);

int get_profile_info(Device *device, ProfileInfo *info);
int read_sector(Device *device, uint16_t sector, size_t size, uint8_t *out);
int write_sector(Device *device, uint16_t sector, const uint8_t *bytes, size_t length);
bool verify_sector_readback(Device *device, uint16_t sector, const uint8_t *expected,
                            size_t length);

bool get_onboard_mode(Device *device, uint8_t *mode_out);
bool set_onboard_mode(Device *device, uint8_t mode);
bool ensure_onboard_mode_for_write(Device *device);
bool get_current_onboard_profile(Device *device, uint8_t *profile_index_out);
int current_onboard_profile_number(const Device *device, uint8_t raw_index);
bool set_current_onboard_dpi_index(Device *device, uint8_t index);
bool get_current_onboard_dpi_index(Device *device, uint8_t *index_out);
bool get_current_sensor_dpi(Device *device, uint8_t sensor_index, uint16_t *dpi_out);
bool live_dpi_matches(Device *device, uint16_t expected_dpi);
bool set_live_dpi_index_and_verify(Device *device, uint8_t desired_index, uint16_t expected_dpi);

bool profile_contains_dpi(const uint16_t *stages, size_t stage_count, uint16_t dpi);
void sync_active_profile_default_dpi(Device *device, int profile_number, int default_stage,
                                     uint16_t dpi);
bool recover_live_dpi_if_needed(Device *device, int profile_number, const uint16_t *stages,
                                size_t stage_count, int default_stage, uint16_t desired_dpi);

int read_profile_control(Device *device, const ProfileInfo *info, uint16_t *control_sector_out,
                         uint8_t *control, size_t control_length);
int parse_profile_headers(const ProfileInfo *info, const uint8_t *control, size_t control_length,
                          ProfileHeader *headers, size_t *header_count);
int read_profile_headers(Device *device, const ProfileInfo *info, ProfileHeader *headers,
                         size_t *header_count);
int load_profile_with_headers(Device *device, const ProfileInfo *info, const ProfileHeader *headers,
                              size_t header_count, int requested_profile, Profile *profile);
int load_profile_summary_with_headers(Device *device, const ProfileInfo *info,
                                      const ProfileHeader *headers, size_t header_count,
                                      int requested_profile, Profile *profile);
int load_selected_profile(Device *device, int requested_profile, Profile *profile);

bool spec_is_disabled(const uint8_t spec[4]);
bool spec_structurally_valid(const uint8_t spec[4]);
bool spec_known(const uint8_t spec[4]);
void detect_button_layout(Profile *profile);
bool is_g603_device(const Device *device);
bool profile_reports_gshift(const Profile *profile, const Device *device);
void detect_gshift_button_layout(Profile *profile, const Device *device);
uint16_t read_le16(const uint8_t *bytes);
void write_le16(uint8_t *bytes, uint16_t value);
void detect_dpi_layout(Profile *profile, const Device *device);
void detect_rgb_layout(Profile *profile);

bool write_rgb_zone_colors(uint8_t *data, const Profile *profile, const uint8_t zones[],
                           const uint8_t colors[][3], size_t count);
bool write_dpi_stage_table(uint8_t *data, const Profile *profile, const uint16_t *stages,
                           size_t stage_count);
int adjustable_dpi_values(Device *device, uint16_t *values, size_t *value_count,
                          size_t value_capacity, uint8_t *sensor_count_out, uint16_t *current_out);

#endif // LOPE_LOGITECH_ONBOARD_PROFILE_IO_H
