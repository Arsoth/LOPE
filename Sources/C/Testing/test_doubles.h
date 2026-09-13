#ifndef LOPE_LOGITECH_ONBOARD_TEST_DOUBLES_H
#define LOPE_LOGITECH_ONBOARD_TEST_DOUBLES_H

#include "internal.h"

// Shared self-test mocking seams, used by the per-module self-tests under
// Sources/C/Testing/ to exercise command/profile/discovery logic without
// real IOKit hardware. See hid_transport.h's channel_request_impl and
// hid_discovery.h's discover_devices_for_options_impl for the production
// seams these doubles are installed into.

typedef struct {
    const Reply *replies;
    size_t reply_count;
    size_t calls;
} ChannelRequestTestContext;

extern ChannelRequestTestContext *g_channel_request_test_context;

Reply channel_request_test_double(HidChannel *channel, uint8_t device_number, uint16_t request_id,
                                  const uint8_t *params, size_t params_length, bool prefer_long,
                                  double timeout_seconds);

typedef struct {
    const Device *devices;
    size_t count;
    int result;
} DiscoverDevicesTestContext;

extern DiscoverDevicesTestContext *g_discover_devices_test_context;

int discover_devices_for_options_test_double(HidContext *context, const Options *options,
                                             Device *devices, size_t *count);

// Mirrors read_sector's chunking exactly (see the profile I/O module) so a
// full sector buffer can be turned into the sequence of 16-byte
// ONBOARD_READ_SECTOR replies that function expects. Returns the number of
// replies written, or 0 if capacity is too small.
size_t build_sector_read_replies(const uint8_t *sector, size_t size, Reply *out, size_t capacity);

// Restores both seams to their hardware implementations and clears the
// mock contexts. Call once after all self-tests have run.
void reset_hid_test_seams(void);

// Builds a 255-byte profile-format-5 onboard sector with a fully populated
// button layout (offset 32 normal / 96 G-Shift), 5 DPI stages, and 2 RGB
// zones, with a valid CRC. Several self-tests (profile_io, profile_rendering,
// commands_set_dpi, commands_apply, commands_backup_bind) exercise their own
// module against this same canned sector.
void build_mock_onboard_sector(uint8_t sector[255]);

// Builds a 132-byte control sector selecting sector 0x0123 as profile 1.
void build_mock_control_sector(uint8_t control[132]);

// Builds a 255-byte control sector (matching k_mock_get_info_reply's
// reported sector size) with two profile headers: profile 1 in sector
// 0x0123 (enabled) and profile 2 in sector 0x0200 (disabled), with a valid
// CRC. Used by the commands_set_profile_state and commands_apply self-tests,
// which both need a control sector sized to the full sector rather than the
// smaller header-only read commands_set_dpi's tests exercise.
void build_mock_control_sector_two_profiles(uint8_t control[255]);

// Canned FEATURE_ONBOARD_PROFILES getInfo reply (5-profile capacity,
// sector 0x0100 base) used to satisfy load_selected_profile's info read.
extern const Reply k_mock_get_info_reply;

// Canned single-byte-status replies reused across several self-tests: a
// generic acknowledgement (startWrite/writeData/endWrite), an
// already-onboard mode query, and a host-mode query that requires switching
// to onboard mode before a write can proceed.
extern const Reply k_mock_generic_ok_reply;
extern const Reply k_mock_onboard_mode_reply;
extern const Reply k_mock_host_mode_reply;

#endif // LOPE_LOGITECH_ONBOARD_TEST_DOUBLES_H
