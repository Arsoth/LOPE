#include "profile_io.h"
#include "profile_rendering.h"
#include "test_doubles.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int test_profile_rendering(void) {
    char spec_description[160];
    uint8_t disabled_spec[4] = {0xFF, 0xFF, 0xFF, 0xFF};
    describe_spec(disabled_spec, spec_description, sizeof(spec_description));
    bool describe_spec_ok = strcmp(spec_description, "disabled") == 0;

    uint8_t no_action_spec[4] = {0x80, 0x00, 0x00, 0x00};
    describe_spec(no_action_spec, spec_description, sizeof(spec_description));
    describe_spec_ok = describe_spec_ok && strcmp(spec_description, "no action") == 0;

    uint8_t mouse_mask_spec[4] = {0x80, 0x01, 0x00, 0x08};
    describe_spec(mouse_mask_spec, spec_description, sizeof(spec_description));
    describe_spec_ok =
        describe_spec_ok && strstr(spec_description, "Back / rear thumb (mask 0x0008)") != NULL;

    uint8_t unknown_mask_spec[4] = {0x80, 0x01, 0x01, 0x00};
    describe_spec(unknown_mask_spec, spec_description, sizeof(spec_description));
    describe_spec_ok =
        describe_spec_ok && strstr(spec_description, "mouse mask (mask 0x0100)") != NULL;

    uint8_t key_alt_spec[4] = {0x80, 0x02, 0x04, 0x04};
    describe_spec(key_alt_spec, spec_description, sizeof(spec_description));
    describe_spec_ok = describe_spec_ok && strstr(spec_description, "Left Alt + A") != NULL;

    uint8_t key_ctrl_spec[4] = {0x80, 0x02, 0x01, 0x04};
    describe_spec(key_ctrl_spec, spec_description, sizeof(spec_description));
    describe_spec_ok = describe_spec_ok && strstr(spec_description, "Left Ctrl + A") != NULL;

    uint8_t key_shift_spec[4] = {0x80, 0x02, 0x02, 0x04};
    describe_spec(key_shift_spec, spec_description, sizeof(spec_description));
    describe_spec_ok = describe_spec_ok && strstr(spec_description, "Left Shift + A") != NULL;

    uint8_t key_gui_spec[4] = {0x80, 0x02, 0x08, 0x04};
    describe_spec(key_gui_spec, spec_description, sizeof(spec_description));
    describe_spec_ok = describe_spec_ok && strstr(spec_description, "Left Command/GUI + A") != NULL;

    uint8_t key_bitmap_spec[4] = {0x80, 0x02, 0x10, 0x04};
    describe_spec(key_bitmap_spec, spec_description, sizeof(spec_description));
    describe_spec_ok = describe_spec_ok && strstr(spec_description, "modifier bitmap + A") != NULL;

    uint8_t key_none_spec[4] = {0x80, 0x02, 0x00, 0x04};
    describe_spec(key_none_spec, spec_description, sizeof(spec_description));
    describe_spec_ok = describe_spec_ok && strstr(spec_description, "no modifier + A") != NULL;

    uint8_t consumer_spec[4] = {0x80, 0x03, 0x00, 0xE9};
    describe_spec(consumer_spec, spec_description, sizeof(spec_description));
    describe_spec_ok =
        describe_spec_ok && strstr(spec_description, "consumer usage 0x00E9") != NULL;

    uint8_t send_unknown_spec[4] = {0x80, 0x04, 0x00, 0x00};
    describe_spec(send_unknown_spec, spec_description, sizeof(spec_description));
    describe_spec_ok = describe_spec_ok && strstr(spec_description, "SEND type 0x04") != NULL;

    uint8_t function_spec[4] = {0x90, 0x08, 0x00, 0x00};
    describe_spec(function_spec, spec_description, sizeof(spec_description));
    describe_spec_ok = describe_spec_ok && strcmp(spec_description, "next profile") == 0 &&
                       strcmp(function_name(0x00), "no action") == 0 &&
                       strcmp(function_name(0x11), "scroll up") == 0 &&
                       strcmp(function_name(0x12), "unknown function") == 0;

    uint8_t macro_spec[4] = {0x10, 0x00, 0x00, 0x00};
    describe_spec(macro_spec, spec_description, sizeof(spec_description));
    describe_spec_ok =
        describe_spec_ok && strstr(spec_description, "macro record (behavior 0x1)") != NULL;

    uint8_t unrecognized_spec[4] = {0x30, 0x00, 0x00, 0x00};
    describe_spec(unrecognized_spec, spec_description, sizeof(spec_description));
    describe_spec_ok = describe_spec_ok && strcmp(spec_description, "unrecognized raw spec") == 0;

    describe_spec_ok = describe_spec_ok && strcmp(key_name(0x04), "A") == 0 &&
                       strcmp(key_name(0xFF), "unknown key") == 0 &&
                       spec_is_back(mouse_mask_spec) && !spec_is_back(no_action_spec);
    const struct {
        uint8_t code;
        const char *name;
    } key_cases[] = {
        {0x04, "A"},      {0x05, "B"},   {0x06, "C"},     {0x07, "D"},   {0x08, "E"},
        {0x09, "F"},      {0x0A, "G"},   {0x0B, "H"},     {0x0C, "I"},   {0x0D, "J"},
        {0x0E, "K"},      {0x0F, "L"},   {0x10, "M"},     {0x11, "N"},   {0x12, "O"},
        {0x13, "P"},      {0x14, "Q"},   {0x15, "R"},     {0x16, "S"},   {0x17, "T"},
        {0x18, "U"},      {0x19, "V"},   {0x1C, "Y"},     {0x1D, "Z"},   {0x28, "Enter"},
        {0x29, "Escape"}, {0x2B, "Tab"}, {0x2C, "Space"}, {0x2F, "["},   {0x30, "]"},
        {0x3A, "F1"},     {0x3B, "F2"},  {0x3C, "F3"},    {0x3D, "F4"},  {0x3E, "F5"},
        {0x3F, "F6"},     {0x40, "F7"},  {0x41, "F8"},    {0x42, "F9"},  {0x43, "F10"},
        {0x44, "F11"},    {0x45, "F12"}, {0x68, "F13"},   {0x69, "F14"}, {0x6A, "F15"},
        {0x6B, "F16"},    {0x6C, "F17"}, {0x6D, "F18"},   {0x6E, "F19"}, {0x6F, "F20"},
        {0x70, "F21"},    {0x71, "F22"}, {0x72, "F23"},   {0x73, "F24"},
    };
    for (size_t i = 0; i < sizeof(key_cases) / sizeof(key_cases[0]); i++) {
        describe_spec_ok =
            describe_spec_ok && strcmp(key_name(key_cases[i].code), key_cases[i].name) == 0;
    }
    const struct {
        uint8_t code;
        const char *name;
    } modifier_key_cases[] = {
        {0xE0, "Left Control"},  {0xE1, "Left Shift"},  {0xE2, "Left Alt"},  {0xE3, "Left GUI"},
        {0xE4, "Right Control"}, {0xE5, "Right Shift"}, {0xE6, "Right Alt"}, {0xE7, "Right GUI"},
    };
    for (size_t i = 0; i < sizeof(modifier_key_cases) / sizeof(modifier_key_cases[0]); i++) {
        describe_spec_ok = describe_spec_ok && strcmp(key_name(modifier_key_cases[i].code),
                                                      modifier_key_cases[i].name) == 0;
    }
    for (uint8_t function = 0; function <= 0x11; function++) {
        describe_spec_ok = describe_spec_ok &&
                           strcmp(function_name(function), function == 0x00   ? "no action"
                                                           : function == 0x01 ? "tilt left"
                                                           : function == 0x02 ? "tilt right"
                                                           : function == 0x03 ? "next DPI"
                                                           : function == 0x04 ? "previous DPI"
                                                           : function == 0x05 ? "cycle DPI"
                                                           : function == 0x06 ? "default DPI"
                                                           : function == 0x07 ? "shift DPI"
                                                           : function == 0x08 ? "next profile"
                                                           : function == 0x09 ? "previous profile"
                                                           : function == 0x0A ? "cycle profile"
                                                           : function == 0x0B ? "G-shift"
                                                           : function == 0x0C ? "battery status"
                                                           : function == 0x0D ? "profile select"
                                                           : function == 0x0E ? "mode switch"
                                                           : function == 0x0F ? "host button"
                                                           : function == 0x10 ? "scroll down"
                                                                              : "scroll up") == 0;
    }
    const uint8_t mouse_masks[] = {0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80};
    for (size_t i = 0; i < sizeof(mouse_masks); i++) {
        uint8_t mask_spec[4] = {0x80, 0x01, 0x00, mouse_masks[i]};
        describe_spec(mask_spec, spec_description, sizeof(spec_description));
        describe_spec_ok = describe_spec_ok && strstr(spec_description, "mask") != NULL;
    }
    uint8_t send_known_spec[4] = {0x80, 0x03, 0x12, 0x34};
    uint8_t macro_zero_spec[4] = {0x00, 0, 0, 0};
    uint8_t macro_two_spec[4] = {0x2F, 0, 0, 0};
    uint8_t raw_spec[4] = {0x30, 0, 0, 0};
    describe_spec(send_known_spec, spec_description, sizeof(spec_description));
    describe_spec_ok =
        describe_spec_ok && strstr(spec_description, "consumer usage 0x1234") != NULL;
    describe_spec(macro_zero_spec, spec_description, sizeof(spec_description));
    describe_spec_ok = describe_spec_ok && strstr(spec_description, "behavior 0") != NULL;
    describe_spec(macro_two_spec, spec_description, sizeof(spec_description));
    describe_spec_ok = describe_spec_ok && strstr(spec_description, "behavior 0x2") != NULL;
    describe_spec(raw_spec, spec_description, sizeof(spec_description));
    describe_spec_ok = describe_spec_ok && strcmp(spec_description, "unrecognized raw spec") == 0;
    if (!describe_spec_ok) {
        fprintf(stderr, "describe_spec/function_name/key_name self-test failed\n");
        return 1;
    }

    char render_path[] = "/tmp/lomps-selftest-render-XXXXXX";
    int render_fd = mkstemp(render_path);
    if (render_fd < 0) {
        fprintf(stderr,
                "print_feature_list/print_device_line self-test failed to create temp file\n");
        return 1;
    }
    close(render_fd);
    HidInterface render_interface = {0};
    render_interface.product_id = 0xC099;
    Device render_device = {0};
    render_device.iface = &render_interface;
    render_device.protocol = 4.2;
    render_device.feature_count = 2;
    render_device.features[0] = (Feature){.id = FEATURE_ROOT, .index = 0, .version = 1};
    render_device.features[1] = (Feature){.id = FEATURE_ONBOARD_PROFILES, .index = 5, .version = 2};
    int render_saved_stdout = dup(fileno(stdout));
    bool render_ok = render_saved_stdout >= 0 && freopen(render_path, "w", stdout) != NULL;
    if (render_ok) {
        print_feature_list(&render_device);
        print_device_line(&render_device, 0);
        print_hex4(mouse_mask_spec);
        fflush(stdout);
    }
    if (render_saved_stdout >= 0) {
        dup2(render_saved_stdout, fileno(stdout));
        close(render_saved_stdout);
        clearerr(stdout);
    }
    char render_contents[1024] = {0};
    if (render_ok) {
        FILE *readback = fopen(render_path, "r");
        if (readback != NULL) {
            size_t read_bytes = fread(render_contents, 1, sizeof(render_contents) - 1, readback);
            render_contents[read_bytes] = '\0';
            fclose(readback);
        } else {
            render_ok = false;
        }
    }
    unlink(render_path);
    render_ok = render_ok && strstr(render_contents, "features: 2") != NULL &&
                strstr(render_contents, "index   0: 0x0000 v1") != NULL &&
                strstr(render_contents, "index   5: 0x8100 v2") != NULL &&
                strstr(render_contents, "HID++ 4.2, product 0xC099") != NULL &&
                strstr(render_contents, "80 01 00 08") != NULL;
    if (!render_ok) {
        fprintf(stderr, "print_feature_list/print_device_line self-test failed\n");
        return 1;
    }

    uint8_t mock_sector[255];
    build_mock_onboard_sector(mock_sector);

    Profile summary_profile;
    memset(&summary_profile, 0, sizeof(summary_profile));
    summary_profile.info.profile_format = 5;
    summary_profile.info.button_count = 5;
    summary_profile.info.shift_flags = 0x02;
    summary_profile.data = mock_sector;
    summary_profile.data_length = sizeof(mock_sector);
    summary_profile.crc_ok = sector_crc_ok(mock_sector, sizeof(mock_sector));
    summary_profile.crc_checked = true;
    summary_profile.headers[0].sector = 0x0123;
    summary_profile.headers[0].enabled = 1;
    summary_profile.selected_header = 0;
    detect_button_layout(&summary_profile);
    detect_gshift_button_layout(&summary_profile, NULL);
    detect_dpi_layout(&summary_profile, NULL);
    detect_rgb_layout(&summary_profile);

    char summary_path[] = "/tmp/lomps-selftest-summary-XXXXXX";
    int summary_fd = mkstemp(summary_path);
    if (summary_fd < 0) {
        fprintf(stderr, "print_profile_summary self-test failed to create temp file\n");
        return 1;
    }
    close(summary_fd);
    int summary_saved_stdout = dup(fileno(stdout));
    bool summary_ok = summary_saved_stdout >= 0 && freopen(summary_path, "w", stdout) != NULL;
    if (summary_ok) {
        print_profile_summary(&summary_profile, true);
        fflush(stdout);
    }
    if (summary_saved_stdout >= 0) {
        dup2(summary_saved_stdout, fileno(stdout));
        close(summary_saved_stdout);
        clearerr(stdout);
    }
    char summary_contents[4096] = {0};
    if (summary_ok) {
        FILE *readback = fopen(summary_path, "r");
        if (readback != NULL) {
            size_t read_bytes = fread(summary_contents, 1, sizeof(summary_contents) - 1, readback);
            summary_contents[read_bytes] = '\0';
            fclose(readback);
        } else {
            summary_ok = false;
        }
    }
    unlink(summary_path);
    summary_ok = summary_ok &&
                 strstr(summary_contents, "Profile 1 (sector 0x0123, enabled=yes)") != NULL &&
                 strstr(summary_contents, "CRC: OK") != NULL &&
                 strstr(summary_contents, "DPI stages: 800, 1200, 1600, 2400, 3200") != NULL &&
                 strstr(summary_contents, "RGB zones: 2") != NULL &&
                 strstr(summary_contents, "RGB zone 1: 102030 (mode 0x01)") != NULL &&
                 strstr(summary_contents, "RGB zone 2: 405060 (mode 0x01)") != NULL &&
                 strstr(summary_contents, "button array: offset 32") != NULL &&
                 strstr(summary_contents, "G-Shift layout: supported") != NULL &&
                 strstr(summary_contents, "button 1: Left click") != NULL &&
                 strstr(summary_contents, "G-Shift button 1:") != NULL &&
                 strstr(summary_contents, "rear thumb mapping:") != NULL;
    if (!summary_ok) {
        fprintf(stderr, "print_profile_summary self-test failed\n");
        return 1;
    }

    Profile summary_no_crc_profile = summary_profile;
    summary_no_crc_profile.crc_checked = false;
    char summary_no_crc_path[] = "/tmp/lomps-selftest-summary-nocrc-XXXXXX";
    int summary_no_crc_fd = mkstemp(summary_no_crc_path);
    if (summary_no_crc_fd < 0) {
        fprintf(stderr, "print_profile_summary NOT_READ self-test failed to create temp file\n");
        return 1;
    }
    close(summary_no_crc_fd);
    int summary_no_crc_saved_stdout = dup(fileno(stdout));
    bool summary_no_crc_ok =
        summary_no_crc_saved_stdout >= 0 && freopen(summary_no_crc_path, "w", stdout) != NULL;
    if (summary_no_crc_ok) {
        print_profile_summary(&summary_no_crc_profile, false);
        fflush(stdout);
    }
    if (summary_no_crc_saved_stdout >= 0) {
        dup2(summary_no_crc_saved_stdout, fileno(stdout));
        close(summary_no_crc_saved_stdout);
        clearerr(stdout);
    }
    char summary_no_crc_contents[1024] = {0};
    if (summary_no_crc_ok) {
        FILE *readback = fopen(summary_no_crc_path, "r");
        if (readback != NULL) {
            size_t read_bytes =
                fread(summary_no_crc_contents, 1, sizeof(summary_no_crc_contents) - 1, readback);
            summary_no_crc_contents[read_bytes] = '\0';
            fclose(readback);
        } else {
            summary_no_crc_ok = false;
        }
    }
    unlink(summary_no_crc_path);
    summary_no_crc_ok =
        summary_no_crc_ok && strstr(summary_no_crc_contents, "CRC: NOT_READ") != NULL;
    if (!summary_no_crc_ok) {
        fprintf(stderr, "print_profile_summary NOT_READ self-test failed\n");
        return 1;
    }

    uint8_t edge_data[64] = {0};
    Profile edge_profile = {0};
    edge_profile.info.profile_format = 7;
    edge_profile.info.profile_count = 1;
    edge_profile.info.button_count = 1;
    edge_profile.info.sector_count = 1;
    edge_profile.info.sector_size = sizeof(edge_data);
    edge_profile.headers[0].sector = 0x0042;
    edge_profile.selected_header = 0;
    edge_profile.data = edge_data;
    edge_profile.data_length = sizeof(edge_data);
    edge_profile.crc_checked = true;
    char edge_path[] = "/tmp/lomps-selftest-summary-edge-XXXXXX";
    int edge_fd = mkstemp(edge_path);
    if (edge_fd < 0) {
        fprintf(stderr, "print_profile_summary edge-case self-test failed to create temp file\n");
        return 1;
    }
    close(edge_fd);
    int edge_saved_stdout = dup(fileno(stdout));
    bool edge_ok = edge_saved_stdout >= 0 && freopen(edge_path, "w", stdout) != NULL;
    if (edge_ok) {
        print_profile_summary(&edge_profile, true);
        fflush(stdout);
    }
    if (edge_saved_stdout >= 0) {
        dup2(edge_saved_stdout, fileno(stdout));
        close(edge_saved_stdout);
        clearerr(stdout);
    }
    char edge_contents[2048] = {0};
    if (edge_ok) {
        FILE *readback = fopen(edge_path, "r");
        if (readback != NULL) {
            size_t read_bytes = fread(edge_contents, 1, sizeof(edge_contents) - 1, readback);
            edge_contents[read_bytes] = '\0';
            fclose(readback);
        } else {
            edge_ok = false;
        }
    }
    unlink(edge_path);
    edge_ok = edge_ok && strstr(edge_contents, "CRC: INVALID") != NULL &&
              strstr(edge_contents, "DPI stages: not recognized") != NULL &&
              strstr(edge_contents, "RGB zones: not recognized") != NULL &&
              strstr(edge_contents, "button array: not recognized") != NULL;

    uint8_t rear_data[8] = {0};
    Profile rear_profile = {0};
    rear_profile.info.button_count = 2;
    rear_profile.data = rear_data;
    rear_profile.data_length = sizeof(rear_data);
    rear_profile.layout_supported = true;
    rear_profile.crc_ok = true;
    rear_profile.button_offset = 0;
    memset(rear_data, 0xFF, sizeof(rear_data));
    bool rear_edge_ok = find_rear_thumb_button(&rear_profile) == 0;
    memcpy(rear_data + 4, mouse_mask_spec, sizeof(mouse_mask_spec));
    rear_edge_ok = rear_edge_ok && find_rear_thumb_button(&rear_profile) == 2;
    memcpy(rear_data, mouse_mask_spec, sizeof(mouse_mask_spec));
    rear_edge_ok = rear_edge_ok && find_rear_thumb_button(&rear_profile) == 0;
    rear_profile.crc_ok = false;
    rear_edge_ok = rear_edge_ok && find_rear_thumb_button(&rear_profile) == 0;
    if (!edge_ok || !rear_edge_ok) {
        fprintf(stderr, "profile rendering edge-case self-test failed\n");
        return 1;
    }

    return 0;
}
