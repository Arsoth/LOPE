#include "hid_transport.h"
#include "test_doubles.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static IOReturn g_open_results[4];
static size_t g_open_result_count;
static size_t g_open_result_index;
static size_t g_open_calls;
static size_t g_close_calls;
static size_t g_register_calls;
static size_t g_schedule_calls;
static size_t g_unschedule_calls;

static IOReturn transport_open_double(IOHIDDeviceRef device, IOOptionBits options) {
    (void)device;
    (void)options;
    g_open_calls++;
    if (g_open_result_index < g_open_result_count) {
        return g_open_results[g_open_result_index++];
    }
    return kIOReturnError;
}

static IOReturn transport_close_double(IOHIDDeviceRef device, IOOptionBits options) {
    (void)device;
    (void)options;
    g_close_calls++;
    return kIOReturnSuccess;
}

static void transport_register_double(IOHIDDeviceRef device, uint8_t *report, CFIndex report_length,
                                      IOHIDReportCallback callback, void *context) {
    (void)device;
    (void)report;
    (void)report_length;
    (void)callback;
    (void)context;
    g_register_calls++;
}

static void transport_schedule_double(IOHIDDeviceRef device, CFRunLoopRef run_loop,
                                      CFStringRef mode) {
    (void)device;
    (void)run_loop;
    (void)mode;
    g_schedule_calls++;
}

static void transport_unschedule_double(IOHIDDeviceRef device, CFRunLoopRef run_loop,
                                        CFStringRef mode) {
    (void)device;
    (void)run_loop;
    (void)mode;
    g_unschedule_calls++;
}

static CFTypeRef g_property_value;

static CFTypeRef transport_property_double(IOHIDDeviceRef device, CFStringRef key) {
    (void)device;
    (void)key;
    return g_property_value;
}

static io_service_t g_service;
static kern_return_t g_registry_result;
static uint64_t g_registry_id;

static io_service_t transport_service_double(IOHIDDeviceRef device) {
    (void)device;
    return g_service;
}

static kern_return_t transport_registry_id_double(io_registry_entry_t service,
                                                  uint64_t *registry_id) {
    (void)service;
    *registry_id = g_registry_id;
    return g_registry_result;
}

static CFArrayRef g_elements;
static uint32_t g_element_usage_page;
static uint32_t g_element_report_id;

static CFArrayRef transport_elements_double(IOHIDDeviceRef device, CFDictionaryRef matching,
                                            IOOptionBits options) {
    (void)device;
    (void)matching;
    (void)options;
    return g_elements;
}

static uint32_t transport_element_usage_page_double(IOHIDElementRef element) {
    if (element == NULL) {
        return 0;
    }
    return element == (IOHIDElementRef)(uintptr_t)2 ? HIDPP_USAGE_PAGE : g_element_usage_page;
}

static uint32_t transport_element_report_id_double(IOHIDElementRef element) {
    if (element == (IOHIDElementRef)(uintptr_t)2) {
        return REPORT_SHORT;
    }
    if (element == (IOHIDElementRef)(uintptr_t)3) {
        return REPORT_SHORT;
    }
    if (element == (IOHIDElementRef)(uintptr_t)4) {
        return REPORT_LONG;
    }
    return g_element_report_id;
}

static IOReturn g_set_report_result;
static IOReturn transport_set_report_double(IOHIDDeviceRef device, IOHIDReportType type,
                                            CFIndex report_id, const uint8_t *report,
                                            CFIndex report_length);
static IOReturn g_get_report_result;
static CFIndex g_get_report_length;

static IOReturn transport_get_report_double(IOHIDDeviceRef device, IOHIDReportType type,
                                            CFIndex report_id, uint8_t *report,
                                            CFIndex *report_length) {
    (void)device;
    (void)type;
    (void)report_id;
    if (g_get_report_result == kIOReturnSuccess && *report_length > 1) {
        report[1] = 0xA5;
    }
    *report_length = g_get_report_length;
    return g_get_report_result;
}

typedef struct {
    uint32_t report_id;
    const uint8_t *bytes;
    size_t length;
} ResponseSpec;

static HidChannel *g_response_channel;
static const ResponseSpec *g_response_specs;
static size_t g_response_count;

static IOReturn transport_set_report_double(IOHIDDeviceRef device, IOHIDReportType type,
                                            CFIndex report_id, const uint8_t *report,
                                            CFIndex report_length) {
    (void)device;
    (void)type;
    (void)report_id;
    (void)report;
    (void)report_length;
    if (g_set_report_result != kIOReturnSuccess) {
        return g_set_report_result;
    }
    for (size_t i = 0; i < g_response_count; i++) {
        hid_report_callback_for_test(
            g_response_channel, kIOReturnSuccess, NULL, 0, g_response_specs[i].report_id,
            (uint8_t *)g_response_specs[i].bytes, (CFIndex)g_response_specs[i].length);
    }
    return kIOReturnSuccess;
}

static FILE *transport_debug_file_null(const char *path, const char *mode) {
    (void)path;
    (void)mode;
    return NULL;
}

static void reset_transport_io_seams(void) {
    hid_device_open_impl = IOHIDDeviceOpen;
    hid_device_close_impl = IOHIDDeviceClose;
    hid_device_register_input_report_callback_impl = IOHIDDeviceRegisterInputReportCallback;
    hid_device_schedule_with_run_loop_impl = IOHIDDeviceScheduleWithRunLoop;
    hid_device_unschedule_from_run_loop_impl = IOHIDDeviceUnscheduleFromRunLoop;
    hid_device_set_report_impl = IOHIDDeviceSetReport;
    hid_device_get_report_impl = IOHIDDeviceGetReport;
    hid_device_get_property_impl = IOHIDDeviceGetProperty;
    hid_device_get_service_impl = IOHIDDeviceGetService;
    hid_registry_entry_get_id_impl = IORegistryEntryGetRegistryEntryID;
    hid_device_copy_matching_elements_impl = IOHIDDeviceCopyMatchingElements;
    hid_array_get_count_impl = CFArrayGetCount;
    hid_array_get_value_at_index_impl = CFArrayGetValueAtIndex;
    hid_element_get_usage_page_impl = IOHIDElementGetUsagePage;
    hid_element_get_report_id_impl = IOHIDElementGetReportID;
    hid_debug_file_open_impl = fopen;
    g_property_value = NULL;
    g_elements = NULL;
    g_response_channel = NULL;
    g_response_specs = NULL;
    g_response_count = 0;
}

static void run_channel_request_case(HidChannel *channel, const ResponseSpec *specs,
                                     size_t spec_count, uint8_t device_number, uint16_t request_id,
                                     Reply *reply) {
    g_response_channel = channel;
    g_response_specs = specs;
    g_response_count = spec_count;
    *reply = channel_request_hardware(channel, device_number, request_id, NULL, 0, false, 1.0);
    g_response_channel = NULL;
    g_response_specs = NULL;
    g_response_count = 0;
}

int test_hid_transport(void) {
    setenv("LOGITECH_ONBOARD_DEBUG", "1", 1);
    bool debug_enabled_ok = hid_debug_enabled();
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
                      is_wireless_device_product(0x4101) && is_known_hidpp_product(0xB034) &&
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
    hid_debug_log("transport-debug %d", 1);
    unsetenv("LOGITECH_ONBOARD_DEBUG");
    bool debug_disabled_ok = !hid_debug_enabled();
    setenv("LOGITECH_ONBOARD_DEBUG", "", 1);
    bool debug_empty_ok = !hid_debug_enabled();
    setenv("LOGITECH_ONBOARD_DEBUG", "1", 1);
    hid_debug_file_open_impl = transport_debug_file_null;
    hid_debug_log("transport-debug no-file");
    hid_debug_file_open_impl = fopen;
    setenv("LOGITECH_ONBOARD_DEBUG", "0", 1);
    bool debug_zero_ok = !hid_debug_enabled();
    setenv("LOGITECH_ONBOARD_DEBUG", "1", 1);
    hid_debug_log("transport-debug disabled path");
    unsetenv("LOGITECH_ONBOARD_DEBUG");
    hid_debug_log("transport-debug quiet path");
    setenv("LOGITECH_ONBOARD_DEBUG", "1", 1);
    on_sigint(SIGINT);
    bool signal_ok = g_stop_watch == 1;
    g_stop_watch = 0;

    HidChannel callback_channel;
    memset(&callback_channel, 0, sizeof(callback_channel));
    pthread_mutex_init(&callback_channel.lock, NULL);
    uint8_t callback_report[MAX_REPORT_BYTES];
    memset(callback_report, 0xA5, sizeof(callback_report));
    hid_report_callback_for_test(NULL, 0, NULL, 0, REPORT_SHORT, callback_report, 4);
    hid_report_callback_for_test(&callback_channel, 0, NULL, 0, REPORT_SHORT, NULL, 4);
    hid_report_callback_for_test(&callback_channel, 0, NULL, 0, REPORT_SHORT, callback_report, 0);
    hid_report_callback_for_test(&callback_channel, 0, NULL, 0, REPORT_SHORT, callback_report, 4);
    hid_report_callback_for_test(&callback_channel, 0, NULL, 0, REPORT_LONG, callback_report,
                                 MAX_REPORT_BYTES + 10);
    bool callback_ok = callback_channel.head != NULL && callback_channel.tail != NULL &&
                       callback_channel.head != callback_channel.tail &&
                       callback_channel.tail->report_id == REPORT_LONG &&
                       callback_channel.tail->length == MAX_REPORT_BYTES &&
                       callback_channel.tail->bytes[0] == 0xA5;
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
    channel_close(NULL);

    IOHIDDeviceRef fake_device = (IOHIDDeviceRef)(uintptr_t)1;
    hid_device_get_property_impl = transport_property_double;
    int32_t property_number = 0x12345678;
    CFNumberRef property_number_ref =
        CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &property_number);
    g_property_value = property_number_ref;
    bool property_ok = number_property(fake_device, CFSTR(kIOHIDProductIDKey)) == 0x12345678 &&
                       location_property(fake_device) == 0x12345678;
    CFStringRef property_string =
        CFStringCreateWithCString(kCFAllocatorDefault, "Mock Logitech", kCFStringEncodingUTF8);
    g_property_value = property_string;
    char property_output[64];
    string_property(fake_device, CFSTR(kIOHIDProductKey), property_output, sizeof(property_output));
    property_ok = property_ok && strcmp(property_output, "Mock Logitech") == 0;
    g_property_value = NULL;
    property_output[0] = 'X';
    string_property(fake_device, CFSTR(kIOHIDProductKey), property_output, sizeof(property_output));
    property_ok = property_ok && property_output[0] == '\0' &&
                  number_property(fake_device, CFSTR(kIOHIDProductIDKey)) == 0;
    g_property_value = property_string;
    property_ok = property_ok && number_property(fake_device, CFSTR(kIOHIDProductIDKey)) == 0 &&
                  location_property(fake_device) == 0;

    hid_device_get_service_impl = transport_service_double;
    hid_registry_entry_get_id_impl = transport_registry_id_double;
    g_service = IO_OBJECT_NULL;
    property_ok = property_ok && registry_id_property(fake_device) == 0;
    g_service = (io_service_t)1;
    g_registry_result = KERN_FAILURE;
    property_ok = property_ok && registry_id_property(fake_device) == 0;
    g_registry_result = KERN_SUCCESS;
    g_registry_id = UINT64_C(0x123456789ABCDEF0);
    property_ok = property_ok && registry_id_property(fake_device) == g_registry_id;

    uint8_t valid_descriptor[] = {0x06, 0x00, 0xFF, 0x85, REPORT_SHORT, 0x85, REPORT_LONG, 0};
    CFDataRef descriptor =
        CFDataCreate(kCFAllocatorDefault, valid_descriptor, (CFIndex)sizeof(valid_descriptor));
    g_property_value = descriptor;
    hid_device_copy_matching_elements_impl = transport_elements_double;
    property_ok = property_ok && device_has_hidpp_reports(fake_device);
    uint8_t partial_descriptor[] = {0x06, 0x00, 0xFF, 0x85, REPORT_SHORT};
    CFDataRef partial =
        CFDataCreate(kCFAllocatorDefault, partial_descriptor, (CFIndex)sizeof(partial_descriptor));
    g_property_value = partial;
    hid_element_get_usage_page_impl = transport_element_usage_page_double;
    hid_element_get_report_id_impl = transport_element_report_id_double;
    const void *element_values[] = {NULL, (const void *)(uintptr_t)1, (const void *)(uintptr_t)2,
                                    (const void *)(uintptr_t)3, (const void *)(uintptr_t)4};
    g_elements = CFArrayCreate(kCFAllocatorDefault, element_values, 5, NULL);
    g_element_usage_page = 0x0001;
    property_ok = property_ok && device_has_hidpp_reports(fake_device);
    const void *no_element_values[] = {(const void *)(uintptr_t)1};
    CFArrayRef no_elements = CFArrayCreate(kCFAllocatorDefault, no_element_values, 1, NULL);
    g_elements = no_elements;
    property_ok = property_ok && !device_has_hidpp_reports(fake_device);
    const void *long_element_values[] = {(const void *)(uintptr_t)4};
    CFArrayRef long_elements = CFArrayCreate(kCFAllocatorDefault, long_element_values, 1, NULL);
    g_elements = long_elements;
    g_element_usage_page = HIDPP_USAGE_PAGE;
    property_ok = property_ok && device_has_hidpp_reports(fake_device);
    g_elements = NULL;
    property_ok = property_ok && !device_has_hidpp_reports(fake_device);
    g_property_value = NULL;

    hid_device_open_impl = transport_open_double;
    hid_device_close_impl = transport_close_double;
    hid_device_register_input_report_callback_impl = transport_register_double;
    hid_device_schedule_with_run_loop_impl = transport_schedule_double;
    hid_device_unschedule_from_run_loop_impl = transport_unschedule_double;
    hid_device_get_property_impl = transport_property_double;
    g_open_results[0] = kIOReturnNotPermitted;
    g_open_results[1] = kIOReturnSuccess;
    g_open_result_count = 2;
    g_open_result_index = 0;
    g_open_calls = 0;
    g_close_calls = 0;
    g_register_calls = 0;
    g_schedule_calls = 0;
    g_unschedule_calls = 0;
    HidChannel opened_channel;
    bool open_ok = channel_open(&opened_channel, fake_device) && opened_channel.opened &&
                   g_open_calls == 2 && g_register_calls == 1 && g_schedule_calls == 1;
    channel_close(&opened_channel);
    open_ok = open_ok && g_unschedule_calls == 1 && g_close_calls == 1;
    HidChannel failed_channel;
    g_open_results[0] = kIOReturnError;
    g_open_result_count = 1;
    g_open_result_index = 0;
    open_ok = open_ok && !channel_open(&failed_channel, fake_device);
    g_open_results[0] = kIOReturnNotPermitted;
    g_open_results[1] = kIOReturnNotPermitted;
    g_open_results[2] = kIOReturnNotPermitted;
    g_open_result_count = 3;
    g_open_result_index = 0;
    g_open_calls = 0;
    open_ok = open_ok && !channel_open(&failed_channel, fake_device) && g_open_calls == 3;

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
    Reply short_error_replies[] = {{.status = REPLY_HIDPP20_ERROR},
                                   {.status = REPLY_OK, .length = 1, .bytes = {8}}};
    ChannelRequestTestContext short_error_context = {.replies = short_error_replies,
                                                     .reply_count = 2};
    g_channel_request_test_context = &short_error_context;
    retried = device_call(&receiver_device, FEATURE_ROOT, 0x00, NULL, 0, 1.0);
    call_ok = call_ok && retried.status == REPLY_OK && retried.bytes[0] == 8;
    Reply raw_retry_replies[] = {{.status = REPLY_TIMEOUT},
                                 {.status = REPLY_OK, .length = 1, .bytes = {6}}};
    ChannelRequestTestContext raw_retry_context = {.replies = raw_retry_replies, .reply_count = 2};
    g_channel_request_test_context = &raw_retry_context;
    Reply raw_retried = raw_request(&receiver_device, 0x001B, NULL, 0, false, 1.0);
    call_ok = call_ok && raw_retried.status == REPLY_OK && raw_retried.bytes[0] == 6 &&
              raw_retry_context.calls == 2;
    Reply raw_long_reply = {.status = REPLY_OK, .length = 1, .bytes = {5}};
    ChannelRequestTestContext raw_long_context = {.replies = &raw_long_reply, .reply_count = 1};
    g_channel_request_test_context = &raw_long_context;
    raw_retried = raw_request(&receiver_device, 0x001B, NULL, 0, true, 1.0);
    call_ok = call_ok && raw_retried.status == REPLY_OK && raw_retried.bytes[0] == 5 &&
              raw_long_context.calls == 1;
    Reply missing_feature = device_call(&direct_device, FEATURE_DEVICE_NAME, 0x00, NULL, 0, 1.0);
    call_ok = call_ok && missing_feature.status == REPLY_PROTOCOL_ERROR;
    print_reply_error("transport protocol", missing_feature);
    print_reply_error("transport ok", (Reply){.status = REPLY_OK});
    print_reply_error("transport timeout", (Reply){.status = REPLY_TIMEOUT, .error_code = 4});

    HidChannel feature_channel;
    memset(&feature_channel, 0, sizeof(feature_channel));
    feature_channel.device = fake_device;
    feature_channel.opened = true;
    hid_device_get_report_impl = transport_get_report_double;
    g_get_report_result = kIOReturnSuccess;
    g_get_report_length = MAX_FEATURE_REPORT_BYTES + 10;
    size_t active_feature_length = 0;
    bool feature_ok = channel_get_feature_report(&feature_channel, REPORT_SHORT, feature_report,
                                                 sizeof(feature_report), &active_feature_length) &&
                      feature_report[0] == REPORT_SHORT &&
                      active_feature_length == sizeof(feature_report);
    feature_ok =
        feature_ok &&
        channel_get_feature_report(&feature_channel, REPORT_LONG, feature_report, 4, NULL) &&
        feature_report[0] == REPORT_LONG;
    g_get_report_result = kIOReturnError;
    feature_ok = feature_ok && !channel_get_feature_report(&feature_channel, REPORT_SHORT,
                                                           feature_report, 4, NULL);
    g_get_report_result = kIOReturnSuccess;
    g_get_report_length = 0;
    feature_ok =
        feature_ok && !channel_get_feature_report(&feature_channel, REPORT_SHORT, feature_report, 4,
                                                  &active_feature_length);
    g_get_report_length = 4;
    feature_ok = feature_ok &&
                 channel_get_feature_report(&feature_channel, REPORT_SHORT, feature_report, 4,
                                            &active_feature_length) &&
                 active_feature_length == 4;
    feature_ok =
        feature_ok && !channel_get_feature_report(&feature_channel, REPORT_SHORT, NULL, 4, NULL) &&
        !channel_get_feature_report(&feature_channel, REPORT_SHORT, feature_report, 0, NULL) &&
        !channel_get_feature_report(&feature_channel, REPORT_SHORT, feature_report,
                                    MAX_FEATURE_REPORT_BYTES + 1, NULL);
    hid_device_set_report_impl = transport_set_report_double;
    g_set_report_result = kIOReturnSuccess;
    feature_ok = feature_ok &&
                 channel_set_feature_report(&feature_channel, REPORT_LONG, feature_report, 4) &&
                 feature_report[0] == REPORT_LONG;
    g_set_report_result = kIOReturnError;
    feature_ok =
        feature_ok && !channel_set_feature_report(&feature_channel, REPORT_LONG, feature_report, 4);
    feature_channel.opened = false;
    pthread_mutex_init(&feature_channel.lock, NULL);
    channel_close(&feature_channel);

    HidChannel request_channel;
    memset(&request_channel, 0, sizeof(request_channel));
    pthread_mutex_init(&request_channel.lock, NULL);
    hid_device_set_report_impl = transport_set_report_double;
    g_set_report_result = kIOReturnSuccess;
    const uint8_t valid_reply[] = {1, 0x00, 0x1B, 0xAA};
    const uint8_t id_reply[] = {REPORT_SHORT, 1, 0x00, 0x1B, 0xBB};
    const uint8_t wrong_device[] = {9, 0x00, 0x1B, 0xCC};
    const uint8_t wrong_request[] = {1, 0x12, 0x34, 0xCC};
    const uint8_t too_short[] = {1};
    ResponseSpec valid_specs[] = {{REPORT_SHORT, too_short, sizeof(too_short)},
                                  {REPORT_SHORT, wrong_device, sizeof(wrong_device)},
                                  {REPORT_SHORT, wrong_request, sizeof(wrong_request)},
                                  {REPORT_SHORT, valid_reply, sizeof(valid_reply)}};
    Reply request_reply;
    run_channel_request_case(&request_channel, valid_specs, 4, 1, 0x001B, &request_reply);
    bool request_ok = request_reply.status == REPLY_OK && request_reply.length == 1 &&
                      request_reply.bytes[0] == 0xAA;
    ResponseSpec id_specs[] = {{REPORT_SHORT, id_reply, sizeof(id_reply)}};
    run_channel_request_case(&request_channel, id_specs, 1, 1, 0x001B, &request_reply);
    request_ok = request_ok && request_reply.status == REPLY_OK && request_reply.bytes[0] == 0xBB;
    const uint8_t hid10_error[] = {1, 0x8F, 0x00, 0x1B, 0x02};
    ResponseSpec hid10_specs[] = {{REPORT_SHORT, hid10_error, sizeof(hid10_error)}};
    run_channel_request_case(&request_channel, hid10_specs, 1, 1, 0x001B, &request_reply);
    request_ok =
        request_ok && request_reply.status == REPLY_HIDPP10_ERROR && request_reply.error_code == 2;
    const uint8_t hid20_error[] = {1, 0xFF, 0x00, 0x1B, 0x03};
    ResponseSpec hid20_specs[] = {{REPORT_LONG, hid20_error, sizeof(hid20_error)}};
    run_channel_request_case(&request_channel, hid20_specs, 1, 1, 0x001B, &request_reply);
    request_ok =
        request_ok && request_reply.status == REPLY_HIDPP20_ERROR && request_reply.error_code == 3;
    const uint8_t xor_reply[] = {0xFD, 0x00, 0x1B, 0xDD};
    ResponseSpec xor_specs[] = {{REPORT_LONG, xor_reply, sizeof(xor_reply)}};
    run_channel_request_case(&request_channel, xor_specs, 1, 2, 0x001B, &request_reply);
    request_ok = request_ok && request_reply.status == REPLY_OK && request_reply.bytes[0] == 0xDD;
    const uint8_t direct_alias_reply[] = {3, 0x00, 0x1B, 0xEE};
    ResponseSpec direct_alias_specs[] = {
        {REPORT_SHORT, direct_alias_reply, sizeof(direct_alias_reply)}};
    run_channel_request_case(&request_channel, direct_alias_specs, 1, 0xFF, 0x001B, &request_reply);
    request_ok = request_ok && request_reply.status == REPLY_OK && request_reply.device_number == 3;
    const uint8_t long_id_reply[] = {REPORT_LONG, 1, 0x00, 0x1B, 0xBC};
    ResponseSpec long_id_specs[] = {{REPORT_LONG, long_id_reply, sizeof(long_id_reply)}};
    run_channel_request_case(&request_channel, long_id_specs, 1, 1, 0x001B, &request_reply);
    request_ok = request_ok && request_reply.status == REPLY_OK && request_reply.bytes[0] == 0xBC;
    const uint8_t short_body_non_error[] = {1, 0x00, 0x1B, 0xCC, 0xDD};
    ResponseSpec short_body_non_error_specs[] = {
        {REPORT_SHORT, short_body_non_error, sizeof(short_body_non_error)}};
    run_channel_request_case(&request_channel, short_body_non_error_specs, 1, 1, 0x001B,
                             &request_reply);
    request_ok = request_ok && request_reply.status == REPLY_OK && request_reply.length == 2 &&
                 request_reply.bytes[0] == 0xCC;
    const uint8_t short_body_wrong_request[] = {1, 0x00, 0xCC, 0xDD};
    ResponseSpec short_body_wrong_request_specs[] = {
        {REPORT_SHORT, short_body_wrong_request, sizeof(short_body_wrong_request)}};
    run_channel_request_case(&request_channel, short_body_wrong_request_specs, 1, 1, 0x001B,
                             &request_reply);
    request_ok = request_ok && request_reply.status == REPLY_TIMEOUT;
    const uint8_t hid20_wrong_request[] = {1, 0xFF, 0x12, 0x34, 0xCC};
    ResponseSpec hid20_wrong_request_specs[] = {
        {REPORT_LONG, hid20_wrong_request, sizeof(hid20_wrong_request)}};
    run_channel_request_case(&request_channel, hid20_wrong_request_specs, 1, 1, 0x001B,
                             &request_reply);
    request_ok = request_ok && request_reply.status == REPLY_TIMEOUT;
    const uint8_t invalid_report_id[] = {1, 0x00, 0x1B, 0x01};
    ResponseSpec invalid_report_id_specs[] = {{7, invalid_report_id, sizeof(invalid_report_id)}};
    run_channel_request_case(&request_channel, invalid_report_id_specs, 1, 1, 0x001B,
                             &request_reply);
    request_ok = request_ok && request_reply.status == REPLY_OK && request_reply.bytes[0] == 0x01;
    const uint8_t non_ping_alias[] = {3, 0x12, 0x34, 0x01};
    ResponseSpec non_ping_alias_specs[] = {{REPORT_SHORT, non_ping_alias, sizeof(non_ping_alias)}};
    run_channel_request_case(&request_channel, non_ping_alias_specs, 1, 0xFF, 0x1234,
                             &request_reply);
    request_ok = request_ok && request_reply.status == REPLY_TIMEOUT;
    const uint8_t zero_alias[] = {0, 0x00, 0x1B, 0x01};
    ResponseSpec zero_alias_specs[] = {{REPORT_SHORT, zero_alias, sizeof(zero_alias)}};
    run_channel_request_case(&request_channel, zero_alias_specs, 1, 0xFF, 0x001B, &request_reply);
    request_ok = request_ok && request_reply.status == REPLY_OK && request_reply.bytes[0] == 0x01;
    const uint8_t out_of_range_alias[] = {7, 0x00, 0x1B, 0x01};
    ResponseSpec out_of_range_alias_specs[] = {
        {REPORT_SHORT, out_of_range_alias, sizeof(out_of_range_alias)}};
    run_channel_request_case(&request_channel, out_of_range_alias_specs, 1, 0xFF, 0x001B,
                             &request_reply);
    request_ok = request_ok && request_reply.status == REPLY_TIMEOUT;
    g_response_channel = &request_channel;
    g_response_specs = NULL;
    g_response_count = 0;
    const uint8_t direct_params[4] = {0, 1, 2, 3};
    request_reply = channel_request_hardware(&request_channel, 1, 0x001B, direct_params,
                                             sizeof(direct_params), false, 0.0);
    request_ok = request_ok && request_reply.status == REPLY_TIMEOUT;
    request_reply = channel_request_hardware(&request_channel, 1, 0x001B, NULL, 0, true, 0.0);
    request_ok = request_ok && request_reply.status == REPLY_TIMEOUT;
    request_reply = channel_request_hardware(&request_channel, 1, 0x001B, long_params,
                                             sizeof(long_params) + 1, false, 1.0);
    request_ok = request_ok && request_reply.status == REPLY_PROTOCOL_ERROR;
    request_reply = channel_request_hardware(&request_channel, 1, 0x001B, NULL, 0, false, 0.0);
    request_ok = request_ok && request_reply.status == REPLY_TIMEOUT;
    request_reply = channel_request_hardware(&request_channel, 1, 0x001B, NULL, 0, false, 0.06);
    request_ok = request_ok && request_reply.status == REPLY_TIMEOUT;
    g_set_report_result = kIOReturnError;
    request_reply = channel_request_hardware(&request_channel, 1, 0x001B, NULL, 0, false, 1.0);
    request_ok = request_ok && request_reply.status == REPLY_IO_ERROR;
    bool routed_ok = !is_receiver_routed_device(NULL) && !is_receiver_routed_device(&direct_device);
    Device no_iface_device = {.request_device_number = 1};
    routed_ok = routed_ok && !is_receiver_routed_device(&no_iface_device);
    HidInterface non_receiver_interface = {.product_id = 0x4085};
    Device non_receiver_device = {.iface = &non_receiver_interface, .request_device_number = 1};
    routed_ok = routed_ok && !is_receiver_routed_device(&non_receiver_device) &&
                is_receiver_routed_device(&receiver_device);
    g_response_channel = NULL;
    channel_close(&request_channel);
    reset_transport_io_seams();
    reset_hid_test_seams();

    if (!debug_enabled_ok || !debug_disabled_ok || !debug_empty_ok || !debug_zero_ok ||
        !product_ok || !status_names_ok || !retry_ok || !signal_ok || !callback_ok ||
        !feature_args_ok || !feature_index_ok || !call_ok || !property_ok || !open_ok ||
        !feature_ok || !request_ok || !routed_ok) {
        fprintf(
            stderr,
            "transport flags debug=%d disabled=%d zero=%d product=%d status=%d retry=%d signal=%d "
            "callback=%d args=%d index=%d call=%d property=%d open=%d feature=%d request=%d "
            "routed=%d\n",
            debug_enabled_ok, debug_disabled_ok, debug_zero_ok, product_ok, status_names_ok,
            retry_ok, signal_ok, callback_ok, feature_args_ok, feature_index_ok, call_ok,
            property_ok, open_ok, feature_ok, request_ok, routed_ok);
        fprintf(stderr, "HID transport seam self-test failed\n");
        return 1;
    }
    return 0;
}
