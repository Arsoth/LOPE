#include "internal.h"
#include "test_doubles.h"

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

    bool product_ok = is_wireless_device_product(0x4085) && is_receiver_product(0xC539) &&
                      is_bluetooth_device_product(0xB034) && is_known_hidpp_product(0x4102) &&
                      !is_known_hidpp_product(0x1234) &&
                      text_contains_case_insensitive("Lightspeed Receiver", "SPEED r") &&
                      !text_contains_case_insensitive(NULL, "receiver") &&
                      !text_contains_case_insensitive("receiver", NULL) &&
                      !text_contains_case_insensitive("receiver", "");
    bool status_names_ok =
        strcmp(reply_status_name(REPLY_TIMEOUT), "timeout") == 0 &&
        strcmp(reply_status_name(REPLY_HIDPP10_ERROR), "HID++ 1.0 error") == 0 &&
        strcmp(reply_status_name(REPLY_HIDPP20_ERROR), "HID++ 2.0 feature error") == 0 &&
        strcmp(reply_status_name(REPLY_IO_ERROR), "I/O error") == 0 &&
        strcmp(reply_status_name(REPLY_PROTOCOL_ERROR), "protocol error") == 0 &&
        strcmp(reply_status_name(REPLY_OK), "ok") == 0 &&
        strcmp(reply_status_name((ReplyStatus)99), "unknown") == 0;
    bool retry_ok = should_retry_short_report((Reply){.status = REPLY_TIMEOUT}) &&
                    should_retry_short_report((Reply){.status = REPLY_IO_ERROR}) &&
                    should_retry_short_report((Reply){.status = REPLY_HIDPP10_ERROR}) &&
                    should_retry_short_report((Reply){.status = REPLY_HIDPP20_ERROR}) &&
                    !should_retry_short_report((Reply){.status = REPLY_OK}) &&
                    !should_retry_short_report((Reply){.status = REPLY_PROTOCOL_ERROR});
    g_stop_watch = 0;
    on_sigint(SIGINT);
    bool signal_ok = g_stop_watch == 1;
    g_stop_watch = 0;

    HidChannel callback_channel;
    memset(&callback_channel, 0, sizeof(callback_channel));
    pthread_mutex_init(&callback_channel.lock, NULL);
    uint8_t callback_report[MAX_REPORT_BYTES];
    memset(callback_report, 0xA5, sizeof(callback_report));
    hid_report_callback_for_test(NULL, 0, NULL, 0, REPORT_SHORT, callback_report, 4);
    hid_report_callback_for_test(&callback_channel, 0, NULL, 0, REPORT_LONG, callback_report,
                                 MAX_REPORT_BYTES + 10);
    bool callback_ok = callback_channel.head != NULL && callback_channel.tail != NULL &&
                       callback_channel.head == callback_channel.tail &&
                       callback_channel.head->report_id == REPORT_LONG &&
                       callback_channel.head->length == MAX_REPORT_BYTES &&
                       callback_channel.head->bytes[0] == 0xA5;
    channel_close(&callback_channel);

    HidChannel unopened_channel;
    memset(&unopened_channel, 0, sizeof(unopened_channel));
    pthread_mutex_init(&unopened_channel.lock, NULL);
    uint8_t feature_report[MAX_FEATURE_REPORT_BYTES] = {0};
    size_t feature_length = 0;
    bool feature_args_ok =
        !channel_get_feature_report(NULL, 1, feature_report, 1, &feature_length) &&
        !channel_get_feature_report(&unopened_channel, 1, feature_report, 0, &feature_length) &&
        !channel_get_feature_report(&unopened_channel, 1, NULL, 1, &feature_length) &&
        !channel_get_feature_report(&unopened_channel, 1, feature_report,
                                    MAX_FEATURE_REPORT_BYTES + 1, &feature_length) &&
        !channel_set_feature_report(NULL, 1, feature_report, 1) &&
        !channel_set_feature_report(&unopened_channel, 1, feature_report, 0) &&
        !channel_set_feature_report(&unopened_channel, 1, NULL, 1) &&
        !channel_set_feature_report(&unopened_channel, 1, feature_report,
                                    MAX_FEATURE_REPORT_BYTES + 1);
    channel_close(&unopened_channel);

    HidInterface direct_interface = {0};
    direct_interface.product_id = 0x4085;
    Device direct_device = {.iface = &direct_interface,
                            .request_device_number = 0xFF,
                            .features = {{FEATURE_ROOT, 4, 1}},
                            .feature_count = 1};
    uint8_t feature_index = 0;
    bool feature_index_ok =
        device_feature_index(&direct_device, FEATURE_ROOT, &feature_index) && feature_index == 4 &&
        !device_feature_index(&direct_device, FEATURE_DEVICE_NAME, &feature_index);

    HidInterface receiver_interface = {0};
    receiver_interface.product_id = 0xC539;
    Device receiver_device = {.iface = &receiver_interface,
                              .request_device_number = 2,
                              .prefer_long_reports = true,
                              .features = {{FEATURE_ROOT, 4, 1}},
                              .feature_count = 1};
    Reply retry_replies[] = {{.status = REPLY_TIMEOUT},
                             {.status = REPLY_OK, .length = 1, .bytes = {7}}};
    ChannelRequestTestContext retry_context = {.replies = retry_replies, .reply_count = 2};
    g_channel_request_test_context = &retry_context;
    channel_request_impl = channel_request_test_double;
    Reply retried = device_call(&receiver_device, FEATURE_ROOT, 0x00, NULL, 0, 1.0);
    bool call_ok = retried.status == REPLY_OK && retried.bytes[0] == 7 && retry_context.calls == 2;

    Reply timeout_replies[] = {{.status = REPLY_TIMEOUT}, {.status = REPLY_TIMEOUT}};
    ChannelRequestTestContext timeout_context = {.replies = timeout_replies, .reply_count = 2};
    g_channel_request_test_context = &timeout_context;
    Reply retained = raw_request(&receiver_device, 0x001B, NULL, 0, false, 1.0);
    call_ok = call_ok && retained.status == REPLY_TIMEOUT && timeout_context.calls == 2;

    Reply long_reply = {.status = REPLY_OK, .length = 1, .bytes = {9}};
    ChannelRequestTestContext long_context = {.replies = &long_reply, .reply_count = 1};
    g_channel_request_test_context = &long_context;
    Reply explicit_long = device_call_long(&receiver_device, FEATURE_ROOT, 0x00, NULL, 0, 1.0);
    call_ok = call_ok && explicit_long.status == REPLY_OK && long_context.calls == 1;
    reset_hid_test_seams();

    if (!product_ok || !status_names_ok || !retry_ok || !signal_ok || !callback_ok ||
        !feature_args_ok || !feature_index_ok || !call_ok) {
        fprintf(stderr, "HID transport seam self-test failed\n");
        return 1;
    }
    return 0;
}
