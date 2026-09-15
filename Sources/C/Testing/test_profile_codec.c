#include "profile_codec.h"

#include <stdio.h>
#include <string.h>

int test_profile_codec(void) {
    const uint8_t sample[] = "123456789";
    if (profile_codec_crc16_ccitt_false(sample, 9) != 0x29B1) {
        fprintf(stderr, "profile codec CRC vector self-test failed\n");
        return 1;
    }

    uint8_t crc_sector[32] = {0};
    profile_codec_sector_put_crc(crc_sector, sizeof(crc_sector));
    bool crc_ok = profile_codec_sector_crc_ok(crc_sector, sizeof(crc_sector));
    crc_sector[0] = 1;
    crc_ok = crc_ok && !profile_codec_sector_crc_ok(crc_sector, sizeof(crc_sector));
    profile_codec_sector_put_crc(NULL, 0);
    crc_ok = crc_ok && !profile_codec_sector_crc_ok(NULL, 2) &&
             !profile_codec_sector_crc_ok(crc_sector, 1);
    if (!crc_ok) {
        fprintf(stderr, "profile codec CRC buffer self-test failed\n");
        return 1;
    }

    const uint8_t info_bytes[PROFILE_CODEC_INFO_BYTES] = {3, 5, 1, 2, 4, 5, 6, 0, 32, 7};
    ProfileCodecInfo info;
    bool info_ok = profile_codec_parse_info(info_bytes, sizeof(info_bytes), &info) &&
                   info.memory == 3 && info.profile_format == 5 && info.macro_format == 1 &&
                   info.profile_count == 2 && info.out_of_band == 4 && info.button_count == 5 &&
                   info.sector_count == 6 && info.sector_size == 32 && info.shift_flags == 7;
    uint8_t bad_info[PROFILE_CODEC_INFO_BYTES];
    memcpy(bad_info, info_bytes, sizeof(bad_info));
    bad_info[8] = 31;
    info_ok = info_ok && !profile_codec_parse_info(NULL, sizeof(info_bytes), &info) &&
              !profile_codec_parse_info(info_bytes, sizeof(info_bytes) - 1, &info) &&
              !profile_codec_parse_info(info_bytes, sizeof(info_bytes), NULL) &&
              !profile_codec_parse_info(bad_info, sizeof(bad_info), &info);
    bad_info[7] = 0x10;
    bad_info[8] = 1;
    info_ok = info_ok && !profile_codec_parse_info(bad_info, sizeof(bad_info), &info);
    bad_info[7] = 0;
    bad_info[8] = 32;
    bad_info[8] = 0xFF;
    bad_info[5] = 0;
    info_ok = info_ok && !profile_codec_parse_info(bad_info, sizeof(bad_info), &info);
    bad_info[5] = 65;
    info_ok = info_ok && !profile_codec_parse_info(bad_info, sizeof(bad_info), &info);
    if (!info_ok) {
        fprintf(stderr, "profile codec info parsing self-test failed\n");
        return 1;
    }

    uint8_t control[132] = {0};
    control[0] = 0x01;
    control[1] = 0x23;
    control[2] = 1;
    control[4] = 0x02;
    control[5] = 0x00;
    ProfileCodecHeader headers[PROFILE_CODEC_MAX_HEADERS];
    size_t header_count = 99;
    bool headers_ok =
        profile_codec_parse_headers(255, control, sizeof(control), headers, &header_count) &&
        header_count == 2 && headers[0].sector == 0x0123 && headers[0].enabled == 1 &&
        headers[1].sector == 0x0200 && headers[1].enabled == 0;
    uint8_t empty_control[4] = {0xFF, 0xFF, 0, 0};
    headers_ok = headers_ok &&
                 !profile_codec_parse_headers(255, empty_control, sizeof(empty_control), headers,
                                              &header_count) &&
                 header_count == 0 &&
                 !profile_codec_parse_headers(255, control, sizeof(control), NULL, &header_count) &&
                 !profile_codec_parse_headers(255, control, sizeof(control), headers, NULL) &&
                 !profile_codec_parse_headers(255, NULL, sizeof(control), headers, &header_count);
    uint8_t one_byte_control[1] = {0};
    headers_ok =
        headers_ok && !profile_codec_parse_headers(0, one_byte_control, sizeof(one_byte_control),
                                                   headers, &header_count);
    if (!headers_ok) {
        fprintf(stderr, "profile codec header parsing self-test failed\n");
        return 1;
    }

    const uint8_t disabled[4] = {0xFF, 0xFF, 0xFF, 0xFF};
    const uint8_t macro[4] = {0x20, 0, 0, 0};
    const uint8_t mouse[4] = {0x80, 0x03, 0, 0};
    const uint8_t invalid_mouse[4] = {0x80, 0x04, 0, 0};
    const uint8_t function[4] = {0x90, 0x11, 0, 0};
    const uint8_t invalid_function[4] = {0x90, 0x12, 0, 0};
    const uint8_t unknown[4] = {0x30, 0, 0, 0};
    bool specs_ok = profile_codec_spec_is_disabled(disabled) &&
                    profile_codec_spec_structurally_valid(disabled) &&
                    profile_codec_spec_structurally_valid(macro) &&
                    profile_codec_spec_structurally_valid(mouse) &&
                    !profile_codec_spec_structurally_valid(invalid_mouse) &&
                    profile_codec_spec_structurally_valid(function) &&
                    !profile_codec_spec_structurally_valid(invalid_function) &&
                    !profile_codec_spec_structurally_valid(unknown) &&
                    profile_codec_spec_known(disabled) && profile_codec_spec_known(mouse) &&
                    profile_codec_spec_known(function) && !profile_codec_spec_known(macro) &&
                    !profile_codec_spec_known(unknown) && !profile_codec_spec_known(NULL) &&
                    !profile_codec_spec_structurally_valid(NULL) &&
                    !profile_codec_spec_is_disabled(NULL);
    if (!specs_ok) {
        fprintf(stderr, "profile codec button-record self-test failed\n");
        return 1;
    }

    uint8_t profile_data[255] = {0};
    memcpy(profile_data + 32, mouse, sizeof(mouse));
    memcpy(profile_data + 36, disabled, sizeof(disabled));
    ProfileCodecButtonLayout button_layout;
    profile_codec_detect_button_layout(profile_data, sizeof(profile_data), 5, 2, &button_layout);
    bool layout_ok = button_layout.supported && button_layout.offset == 32 &&
                     button_layout.valid_specs == 2 && button_layout.known_specs == 2;
    profile_codec_detect_button_layout(NULL, sizeof(profile_data), 5, 2, &button_layout);
    layout_ok = layout_ok && !button_layout.supported;
    profile_codec_detect_button_layout(profile_data, 1, 5, 2, &button_layout);
    layout_ok = layout_ok && !button_layout.supported;
    profile_codec_detect_button_layout(profile_data, sizeof(profile_data), 5, 0, &button_layout);
    layout_ok = layout_ok && !button_layout.supported;
    profile_codec_detect_button_layout(profile_data, sizeof(profile_data), 5, 2, NULL);
    profile_codec_detect_button_layout(profile_data, 2, 5, 1, &button_layout);
    layout_ok = layout_ok && !button_layout.supported;
    profile_codec_detect_gshift_button_layout(profile_data, sizeof(profile_data), 2, 32, false,
                                              &button_layout);
    layout_ok = layout_ok && !button_layout.supported;
    memcpy(profile_data + 96, function, sizeof(function));
    memcpy(profile_data + 100, disabled, sizeof(disabled));
    profile_codec_detect_gshift_button_layout(profile_data, sizeof(profile_data), 2, 32, true,
                                              &button_layout);
    layout_ok = layout_ok && button_layout.supported && button_layout.offset == 96;
    profile_codec_detect_gshift_button_layout(profile_data, sizeof(profile_data), 2, SIZE_MAX, true,
                                              &button_layout);
    layout_ok = layout_ok && !button_layout.supported;
    profile_codec_detect_gshift_button_layout(profile_data, SIZE_MAX, 2, SIZE_MAX - 32, true,
                                              &button_layout);
    layout_ok = layout_ok && !button_layout.supported;
    profile_codec_detect_gshift_button_layout(NULL, sizeof(profile_data), 2, 32, true,
                                              &button_layout);
    profile_codec_detect_gshift_button_layout(profile_data, 1, 2, 32, true, &button_layout);
    profile_codec_detect_gshift_button_layout(profile_data, sizeof(profile_data), 0, 32, true,
                                              &button_layout);
    profile_codec_detect_gshift_button_layout(profile_data, sizeof(profile_data), 2, 32, true,
                                              NULL);
    if (!layout_ok) {
        fprintf(stderr, "profile codec layout detection self-test failed\n");
        return 1;
    }

    uint8_t dpi_data[255] = {0};
    dpi_data[1] = 1;
    dpi_data[2] = 0;
    const uint16_t dpis[] = {800, 1600, 0, 0, 0};
    for (size_t i = 0; i < 5; i++) {
        profile_codec_write_le16(dpi_data + 3 + i * 2, dpis[i]);
    }
    ProfileCodecDpiLayout dpi_layout;
    profile_codec_detect_dpi_layout(dpi_data, sizeof(dpi_data), 5, true, &dpi_layout);
    bool dpi_ok = dpi_layout.supported && dpi_layout.offset == 3 && dpi_layout.count == 2 &&
                  dpi_layout.default_index == 1 && dpi_layout.shift_index == 0 &&
                  dpi_layout.unused_value == 0;
    profile_codec_write_le16(dpi_data + 7, UINT16_MAX);
    profile_codec_write_le16(dpi_data + 9, UINT16_MAX);
    profile_codec_write_le16(dpi_data + 11, UINT16_MAX);
    profile_codec_detect_dpi_layout(dpi_data, sizeof(dpi_data), 5, false, &dpi_layout);
    dpi_ok = dpi_ok && dpi_layout.supported && dpi_layout.unused_value == UINT16_MAX &&
             profile_codec_read_le16(dpi_data + 3) == 800;
    profile_codec_write_le16(dpi_data + 7, 700);
    profile_codec_detect_dpi_layout(dpi_data, sizeof(dpi_data), 5, false, &dpi_layout);
    dpi_ok = dpi_ok && !dpi_layout.supported;
    profile_codec_detect_dpi_layout(NULL, sizeof(dpi_data), 5, false, &dpi_layout);
    dpi_ok = dpi_ok && !dpi_layout.supported;
    profile_codec_detect_dpi_layout(dpi_data, sizeof(dpi_data), 6, false, &dpi_layout);
    dpi_ok = dpi_ok && !dpi_layout.supported;
    profile_codec_detect_dpi_layout(dpi_data, 14, 5, false, &dpi_layout);
    dpi_ok = dpi_ok && !dpi_layout.supported;
    profile_codec_detect_dpi_layout(dpi_data, sizeof(dpi_data), 5, false, NULL);
    uint8_t empty_dpi_data[255] = {0};
    profile_codec_detect_dpi_layout(empty_dpi_data, sizeof(empty_dpi_data), 5, false, &dpi_layout);
    dpi_ok = dpi_ok && !dpi_layout.supported;
    if (!dpi_ok) {
        fprintf(stderr, "profile codec DPI self-test failed\n");
        return 1;
    }

    uint8_t rgb_data[255];
    memset(rgb_data, 0xFF, sizeof(rgb_data));
    rgb_data[PROFILE_CODEC_RGB_BASE_OFFSET] = 1;
    ProfileCodecRgbLayout rgb_layout;
    profile_codec_detect_rgb_layout(rgb_data, sizeof(rgb_data), 5, &rgb_layout);
    bool rgb_ok = rgb_layout.supported && rgb_layout.offset == PROFILE_CODEC_RGB_BASE_OFFSET &&
                  rgb_layout.zone_count == 1 && rgb_layout.zone_present[0];
    const uint8_t rgb_zone = 0;
    const uint8_t rgb_color[1][3] = {{0xAA, 0xBB, 0xCC}};
    rgb_ok = rgb_ok &&
             profile_codec_write_rgb_zone_colors(rgb_data, sizeof(rgb_data), rgb_layout.offset,
                                                 rgb_layout.zone_count, rgb_layout.zone_present,
                                                 &rgb_zone, rgb_color, 1) &&
             memcmp(rgb_data + PROFILE_CODEC_RGB_BASE_OFFSET + 1, rgb_color[0], 3) == 0;
    uint8_t duplicate_zones[2] = {0, 0};
    rgb_ok = rgb_ok &&
             !profile_codec_write_rgb_zone_colors(rgb_data, sizeof(rgb_data), rgb_layout.offset,
                                                  rgb_layout.zone_count, rgb_layout.zone_present,
                                                  duplicate_zones, rgb_color, 2) &&
             !profile_codec_write_rgb_zone_colors(NULL, sizeof(rgb_data), rgb_layout.offset,
                                                  rgb_layout.zone_count, rgb_layout.zone_present,
                                                  &rgb_zone, rgb_color, 1);
    rgb_ok = rgb_ok &&
             !profile_codec_write_rgb_zone_colors(rgb_data, sizeof(rgb_data), rgb_layout.offset,
                                                  rgb_layout.zone_count, NULL, &rgb_zone, rgb_color,
                                                  1) &&
             !profile_codec_write_rgb_zone_colors(rgb_data, sizeof(rgb_data), rgb_layout.offset,
                                                  rgb_layout.zone_count, rgb_layout.zone_present,
                                                  &rgb_zone, rgb_color, 0);
    rgb_data[PROFILE_CODEC_RGB_BASE_OFFSET] = 2;
    profile_codec_detect_rgb_layout(rgb_data, sizeof(rgb_data), 5, &rgb_layout);
    rgb_ok = rgb_ok && !rgb_layout.supported;
    profile_codec_detect_rgb_layout(rgb_data, sizeof(rgb_data), 3, &rgb_layout);
    rgb_ok = rgb_ok && !rgb_layout.supported;
    profile_codec_detect_rgb_layout(rgb_data, 253, 5, &rgb_layout);
    rgb_ok = rgb_ok && !rgb_layout.supported;
    profile_codec_detect_rgb_layout(rgb_data, sizeof(rgb_data), 5, NULL);
    if (!rgb_ok) {
        fprintf(stderr, "profile codec RGB self-test failed\n");
        return 1;
    }

    uint16_t compacted[] = {800, 1600, 3200, 6400};
    uint8_t table[10] = {0};
    bool write_ok = profile_codec_write_dpi_stage_table(table, sizeof(table), 0, 0, compacted, 4);
    write_ok = write_ok && profile_codec_read_le16(table + 6) == 6400 &&
               profile_codec_read_le16(table + 8) == 0 &&
               !profile_codec_write_dpi_stage_table(table, sizeof(table), 0, 0, compacted, 6) &&
               !profile_codec_write_dpi_stage_table(NULL, sizeof(table), 0, 0, compacted, 1) &&
               !profile_codec_write_dpi_stage_table(table, sizeof(table), 0, 0, NULL, 1) &&
               !profile_codec_write_dpi_stage_table(table, sizeof(table), 0, 0, compacted, 0) &&
               !profile_codec_write_dpi_stage_table(table, sizeof(table), 1, 0, compacted, 1) &&
               !profile_codec_write_dpi_stage_table(table, 9, 0, 0, compacted, 1);
    bool writable = profile_codec_validate_profile_for_write(true, true, 255, 32, 5, 4) &&
                    !profile_codec_validate_profile_for_write(false, true, 255, 32, 5, 4) &&
                    !profile_codec_validate_profile_for_write(true, false, 255, 32, 5, 4) &&
                    !profile_codec_validate_profile_for_write(true, true, 1, 32, 5, 4) &&
                    !profile_codec_validate_profile_for_write(true, true, 255, SIZE_MAX, 5, 4) &&
                    !profile_codec_validate_profile_for_write(true, true, 255, 32, 5, 2);
    if (!write_ok || !writable) {
        fprintf(stderr, "profile codec encoding/validation self-test failed\n");
        return 1;
    }
    return 0;
}
