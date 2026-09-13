#include "test_doubles.h"

ChannelRequestTestContext *g_channel_request_test_context = NULL;

Reply channel_request_test_double(HidChannel *channel, uint8_t device_number, uint16_t request_id,
                                  const uint8_t *params, size_t params_length, bool prefer_long,
                                  double timeout_seconds) {
    (void)channel;
    (void)device_number;
    (void)request_id;
    (void)params;
    (void)params_length;
    (void)prefer_long;
    (void)timeout_seconds;
    ChannelRequestTestContext *test = g_channel_request_test_context;
    if (test == NULL || test->calls >= test->reply_count) {
        Reply timeout_reply;
        memset(&timeout_reply, 0, sizeof(timeout_reply));
        timeout_reply.status = REPLY_TIMEOUT;
        return timeout_reply;
    }
    return test->replies[test->calls++];
}

DiscoverDevicesTestContext *g_discover_devices_test_context = NULL;

int discover_devices_for_options_test_double(HidContext *context, const Options *options,
                                             Device *devices, size_t *count) {
    (void)context;
    (void)options;
    if (g_discover_devices_test_context == NULL) {
        *count = 0;
        return 0;
    }
    *count = g_discover_devices_test_context->count;
    for (size_t i = 0; i < *count; i++) {
        devices[i] = g_discover_devices_test_context->devices[i];
    }
    return g_discover_devices_test_context->result;
}

size_t build_sector_read_replies(const uint8_t *sector, size_t size, Reply *out, size_t capacity) {
    size_t count = 0;
    size_t copied = 0;
    while (copied < size) {
        size_t request_offset = copied;
        if (size - copied < 16) {
            request_offset = size - 16;
        }
        if (count >= capacity) {
            return 0;
        }
        Reply chunk;
        memset(&chunk, 0, sizeof(chunk));
        chunk.status = REPLY_OK;
        chunk.length = 16;
        memcpy(chunk.bytes, sector + request_offset, 16);
        out[count++] = chunk;
        size_t from = copied > request_offset ? copied - request_offset : 0;
        size_t take = 16 - from;
        if (take > size - copied) {
            take = size - copied;
        }
        copied += take;
    }
    return count;
}

void reset_hid_test_seams(void) {
    discover_devices_for_options_impl = discover_devices_for_options_hardware;
    g_discover_devices_test_context = NULL;
    channel_request_impl = channel_request_hardware;
    g_channel_request_test_context = NULL;
}

void build_mock_onboard_sector(uint8_t sector[255]) {
    memset(sector, 0, 255);
    uint8_t button_specs[5][4] = {
        {0x80, 0x01, 0x00, 0x01}, {0x80, 0x01, 0x00, 0x02}, {0x80, 0x01, 0x00, 0x04},
        {0x80, 0x01, 0x00, 0x08}, {0x80, 0x01, 0x00, 0x10},
    };
    uint8_t gshift_specs[5][4] = {
        {0x80, 0x01, 0x00, 0x10}, {0x80, 0x01, 0x00, 0x20}, {0x80, 0x01, 0x00, 0x40},
        {0x80, 0x01, 0x00, 0x80}, {0x80, 0x01, 0x01, 0x00},
    };
    for (size_t i = 0; i < 5; i++) {
        memcpy(sector + 32 + i * 4, button_specs[i], 4);
        memcpy(sector + 96 + i * 4, gshift_specs[i], 4);
    }
    uint16_t dpi[5] = {800, 1200, 1600, 2400, 3200};
    for (size_t i = 0; i < 5; i++) {
        write_le16(sector + 3 + i * 2, dpi[i]);
    }
    for (size_t i = 0; i < RGB_PROFILE_RECORD_COUNT; i++) {
        memset(sector + RGB_PROFILE_BASE_OFFSET + i * RGB_PROFILE_RECORD_BYTES, 0xFF,
               RGB_PROFILE_RECORD_BYTES);
    }
    sector[RGB_PROFILE_BASE_OFFSET] = 0x01;
    sector[RGB_PROFILE_BASE_OFFSET + 1] = 0x10;
    sector[RGB_PROFILE_BASE_OFFSET + 2] = 0x20;
    sector[RGB_PROFILE_BASE_OFFSET + 3] = 0x30;
    sector[RGB_PROFILE_BASE_OFFSET + RGB_PROFILE_RECORD_BYTES] = 0x01;
    sector[RGB_PROFILE_BASE_OFFSET + RGB_PROFILE_RECORD_BYTES + 1] = 0x40;
    sector[RGB_PROFILE_BASE_OFFSET + RGB_PROFILE_RECORD_BYTES + 2] = 0x50;
    sector[RGB_PROFILE_BASE_OFFSET + RGB_PROFILE_RECORD_BYTES + 3] = 0x60;
    sector[1] = 2;
    sector[2] = 0;
    sector_put_crc(sector, 255);
}

void build_mock_control_sector(uint8_t control[132]) {
    memset(control, 0, 132);
    control[0] = 0x01;
    control[1] = 0x23;
    control[2] = 0x01;
    control[3] = 0x00;
}

const Reply k_mock_get_info_reply = {
    .status = REPLY_OK,
    .length = 10,
    .bytes = {0x00, 0x05, 0x00, 0x01, 0x00, 0x05, 0x01, 0x00, 0xFF, 0x02}};
