#include "internal.h"

int test_hid_transport(void) {
    uint8_t frame[LONG_REPORT_BYTES];
    const uint8_t ping_params[3] = {0x00, 0x00, 0x5A};
    size_t frame_length =
        build_hidpp_frame(false, 0x01, 0x001B, ping_params, sizeof(ping_params), frame);
    if (frame_length != SHORT_REPORT_BYTES || frame[0] != REPORT_SHORT || frame[1] != 0x01 ||
        frame[2] != 0x00 || frame[3] != 0x1B || memcmp(frame + 4, ping_params, 3) != 0) {
        fprintf(stderr, "short HID++ frame self-test failed\n");
        return 1;
    }
    uint8_t long_params[16];
    for (size_t i = 0; i < sizeof(long_params); i++)
        long_params[i] = (uint8_t)i;
    frame_length = build_hidpp_frame(true, 0xFF, 0x127B, long_params, sizeof(long_params), frame);
    if (frame_length != LONG_REPORT_BYTES || frame[0] != REPORT_LONG || frame[1] != 0xFF ||
        frame[2] != 0x12 || frame[3] != 0x7B || memcmp(frame + 4, long_params, 16) != 0) {
        fprintf(stderr, "long HID++ frame self-test failed\n");
        return 1;
    }
    return 0;
}
