#ifndef LOPE_LOGITECH_ONBOARD_PROFILE_CODEC_H
#define LOPE_LOGITECH_ONBOARD_PROFILE_CODEC_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define PROFILE_CODEC_INFO_BYTES 10
#define PROFILE_CODEC_MAX_HEADERS 32
#define PROFILE_CODEC_MAX_SECTOR_BYTES 4096
#define PROFILE_CODEC_RGB_BASE_OFFSET 208
#define PROFILE_CODEC_RGB_RECORD_BYTES 11
#define PROFILE_CODEC_RGB_COLOR_OFFSET 1
#define PROFILE_CODEC_RGB_RECORD_COUNT 4

typedef struct {
    uint8_t memory;
    uint8_t profile_format;
    uint8_t macro_format;
    uint8_t profile_count;
    uint8_t out_of_band;
    uint8_t button_count;
    uint8_t sector_count;
    uint16_t sector_size;
    uint8_t shift_flags;
} ProfileCodecInfo;

typedef struct {
    uint16_t sector;
    uint8_t enabled;
} ProfileCodecHeader;

typedef struct {
    size_t offset;
    size_t valid_specs;
    size_t known_specs;
    bool supported;
} ProfileCodecButtonLayout;

typedef struct {
    size_t offset;
    size_t count;
    uint8_t default_index;
    uint8_t shift_index;
    uint16_t unused_value;
    bool supported;
} ProfileCodecDpiLayout;

typedef struct {
    size_t offset;
    size_t zone_count;
    bool zone_present[PROFILE_CODEC_RGB_RECORD_COUNT];
    bool supported;
} ProfileCodecRgbLayout;

bool profile_codec_parse_info(const uint8_t *bytes, size_t length, ProfileCodecInfo *info);
bool profile_codec_parse_headers(uint16_t sector_size, const uint8_t *control,
                                 size_t control_length, ProfileCodecHeader *headers,
                                 size_t *header_count);

uint16_t profile_codec_crc16_ccitt_false(const uint8_t *bytes, size_t length);
bool profile_codec_sector_crc_ok(const uint8_t *bytes, size_t length);
void profile_codec_sector_put_crc(uint8_t *bytes, size_t length);

bool profile_codec_spec_is_disabled(const uint8_t spec[4]);
bool profile_codec_spec_structurally_valid(const uint8_t spec[4]);
bool profile_codec_spec_known(const uint8_t spec[4]);

uint16_t profile_codec_read_le16(const uint8_t *bytes);
void profile_codec_write_le16(uint8_t *bytes, uint16_t value);

void profile_codec_detect_button_layout(const uint8_t *data, size_t data_length,
                                        uint8_t profile_format, uint8_t button_count,
                                        ProfileCodecButtonLayout *layout);
void profile_codec_detect_gshift_button_layout(const uint8_t *data, size_t data_length,
                                               uint8_t button_count, size_t button_offset,
                                               bool candidate, ProfileCodecButtonLayout *layout);
void profile_codec_detect_dpi_layout(const uint8_t *data, size_t data_length,
                                     uint8_t profile_format, bool zero_terminated,
                                     ProfileCodecDpiLayout *layout);
void profile_codec_detect_rgb_layout(const uint8_t *data, size_t data_length,
                                     uint8_t profile_format, ProfileCodecRgbLayout *layout);

bool profile_codec_write_rgb_zone_colors(uint8_t *data, size_t data_length, size_t rgb_offset,
                                         size_t rgb_zone_count,
                                         const bool zone_present[PROFILE_CODEC_RGB_RECORD_COUNT],
                                         const uint8_t zones[], const uint8_t colors[][3],
                                         size_t count);
bool profile_codec_write_rgb_zone_modes(uint8_t *data, size_t data_length, size_t rgb_offset,
                                        size_t rgb_zone_count,
                                        const bool zone_present[PROFILE_CODEC_RGB_RECORD_COUNT],
                                        const uint8_t zones[], const uint8_t modes[], size_t count);
bool profile_codec_write_dpi_stage_table(uint8_t *data, size_t data_length, size_t dpi_offset,
                                         uint16_t unused_value, const uint16_t *stages,
                                         size_t count);

bool profile_codec_validate_profile_for_write(bool crc_ok, bool layout_supported,
                                              size_t data_length, size_t button_offset,
                                              uint8_t button_count, size_t valid_specs);

#endif // LOPE_LOGITECH_ONBOARD_PROFILE_CODEC_H
