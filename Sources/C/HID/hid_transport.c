#include "hid_transport.h"

#include <IOKit/hid/IOHIDKeys.h>
#include <ctype.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

HidDeviceOpenFn hid_device_open_impl = IOHIDDeviceOpen;
HidDeviceCloseFn hid_device_close_impl = IOHIDDeviceClose;
HidDeviceRegisterInputReportCallbackFn hid_device_register_input_report_callback_impl =
    IOHIDDeviceRegisterInputReportCallback;
HidDeviceScheduleWithRunLoopFn hid_device_schedule_with_run_loop_impl =
    IOHIDDeviceScheduleWithRunLoop;
HidDeviceUnscheduleFromRunLoopFn hid_device_unschedule_from_run_loop_impl =
    IOHIDDeviceUnscheduleFromRunLoop;
HidDeviceSetReportFn hid_device_set_report_impl = IOHIDDeviceSetReport;
HidDeviceGetReportFn hid_device_get_report_impl = IOHIDDeviceGetReport;
HidDeviceGetPropertyFn hid_device_get_property_impl = IOHIDDeviceGetProperty;
HidDeviceGetServiceFn hid_device_get_service_impl = IOHIDDeviceGetService;
HidRegistryEntryGetIDFn hid_registry_entry_get_id_impl = IORegistryEntryGetRegistryEntryID;
HidDeviceCopyMatchingElementsFn hid_device_copy_matching_elements_impl =
    IOHIDDeviceCopyMatchingElements;
HidArrayGetCountFn hid_array_get_count_impl = CFArrayGetCount;
HidArrayGetValueAtIndexFn hid_array_get_value_at_index_impl = CFArrayGetValueAtIndex;
HidElementGetUsagePageFn hid_element_get_usage_page_impl = IOHIDElementGetUsagePage;
HidElementGetReportIDFn hid_element_get_report_id_impl = IOHIDElementGetReportID;
HidDebugFileOpenFn hid_debug_file_open_impl = fopen;

volatile sig_atomic_t g_stop_watch = 0;

bool hid_debug_enabled(void) {
    const char *value = getenv("LOGITECH_ONBOARD_DEBUG");
    return value != NULL && value[0] != '\0' && strcmp(value, "0") != 0;
}

void hid_debug_log(const char *format, ...) {
    if (!hid_debug_enabled()) {
        return;
    }
    va_list arguments;
    va_start(arguments, format);
    vfprintf(stderr, format, arguments);
    va_end(arguments);

    FILE *file = hid_debug_file_open_impl("/tmp/lomps-hid-debug.log", "a");
    if (file == NULL) {
        return;
    }
    va_start(arguments, format);
    vfprintf(file, format, arguments);
    va_end(arguments);
    fputc('\n', file);
    fclose(file);
}

void on_sigint(int signal_number) {
    (void)signal_number;
    g_stop_watch = 1;
}

uint32_t number_property(IOHIDDeviceRef device, CFStringRef key) {
    CFTypeRef value = hid_device_get_property_impl(device, key);
    if (value == NULL || CFGetTypeID(value) != CFNumberGetTypeID()) {
        return 0;
    }
    int32_t number = 0;
    if (!CFNumberGetValue((CFNumberRef)value, kCFNumberSInt32Type, &number)) {
        return 0;
    }
    return (uint32_t)number;
}

uint64_t location_property(IOHIDDeviceRef device) {
    CFTypeRef value = hid_device_get_property_impl(device, CFSTR(kIOHIDLocationIDKey));
    if (value == NULL || CFGetTypeID(value) != CFNumberGetTypeID()) {
        return 0;
    }
    int32_t number = 0;
    if (!CFNumberGetValue((CFNumberRef)value, kCFNumberSInt32Type, &number)) {
        return 0;
    }
    return (uint64_t)(uint32_t)number;
}

uint64_t registry_id_property(IOHIDDeviceRef device) {
    io_service_t service = hid_device_get_service_impl(device);
    if (service == IO_OBJECT_NULL) {
        return 0;
    }
    uint64_t registry_id = 0;
    if (hid_registry_entry_get_id_impl(service, &registry_id) != KERN_SUCCESS) {
        return 0;
    }
    return registry_id;
}

void string_property(IOHIDDeviceRef device, CFStringRef key, char *out, size_t out_size) {
    out[0] = '\0';
    CFTypeRef value = hid_device_get_property_impl(device, key);
    if (value == NULL || CFGetTypeID(value) != CFStringGetTypeID()) {
        return;
    }
    CFStringGetCString((CFStringRef)value, out, (CFIndex)out_size, kCFStringEncodingUTF8);
}

bool device_has_hidpp_reports(IOHIDDeviceRef device, bool inspect_protected_elements) {
    CFTypeRef descriptor_value =
        hid_device_get_property_impl(device, CFSTR(kIOHIDReportDescriptorKey));
    if (descriptor_value != NULL && CFGetTypeID(descriptor_value) == CFDataGetTypeID()) {
        const uint8_t *descriptor = CFDataGetBytePtr((CFDataRef)descriptor_value);
        CFIndex length = CFDataGetLength((CFDataRef)descriptor_value);
        bool has_vendor_page = false;
        bool has_short_report = false;
        bool has_long_report = false;
        for (CFIndex i = 0; i + 2 < length; i++) {
            // HID++ interfaces use vendor page 0xFF00 and numbered reports
            // 0x10/0x11. Checking the descriptor avoids relying on the
            // interface's misleading primary usage collection.
            if (descriptor[i] == 0x06 && descriptor[i + 1] == 0x00 && descriptor[i + 2] == 0xFF) {
                has_vendor_page = true;
            }
            if (i + 1 < length && descriptor[i] == 0x85) {
                if (descriptor[i + 1] == REPORT_SHORT) {
                    has_short_report = true;
                } else if (descriptor[i + 1] == REPORT_LONG) {
                    has_long_report = true;
                }
            }
        }
        if (has_vendor_page && has_short_report && has_long_report) {
            return true;
        }
    }

    // IOHIDDeviceCopyMatchingElements initializes a connection to the device.
    // For a protected wired interface, that connection can show macOS's
    // Keystroke Receiving prompt. Enumeration must stay passive until the user
    // explicitly requests Input Monitoring from the GUI.
    if (!inspect_protected_elements) {
        return false;
    }

    // Keep an element-based fallback for authorized devices whose driver does
    // not expose the raw report descriptor as an IOHIDDevice property.
    CFArrayRef elements =
        hid_device_copy_matching_elements_impl(device, NULL, kIOHIDOptionsTypeNone);
    if (elements == NULL) {
        return false;
    }
    bool found = false;
    CFIndex count = hid_array_get_count_impl(elements);
    for (CFIndex i = 0; i < count; i++) {
        IOHIDElementRef element = (IOHIDElementRef)hid_array_get_value_at_index_impl(elements, i);
        if (element == NULL || hid_element_get_usage_page_impl(element) != HIDPP_USAGE_PAGE) {
            continue;
        }
        uint32_t report_id = hid_element_get_report_id_impl(element);
        if (report_id == REPORT_SHORT || report_id == REPORT_LONG) {
            found = true;
            break;
        }
    }
    CFRelease(elements);
    return found;
}

bool is_wireless_device_product(uint32_t product_id) {
    // Logitech wireless HID++ product IDs are in the 0x4000 range. Some
    // macOS HID stacks do not expose the vendor report descriptor for these
    // interfaces, so the product ID is the reliable fallback (notably for
    // the G604, PID 0x4085).
    return (product_id >= 0x4002 && product_id <= 0x4097) || product_id == 0x4101 ||
           product_id == 0x4102;
}

bool is_receiver_product(uint32_t product_id) {
    return product_id >= 0xC500 && product_id <= 0xC5FF;
}

bool is_bluetooth_device_product(uint32_t product_id) {
    // Bluetooth HID++ model IDs are in the B0xx/B3xx ranges (for example,
    // the MX Master 3S uses B034).
    return (product_id >= 0xB000 && product_id <= 0xB3FF);
}

bool is_known_hidpp_product(uint32_t product_id) {
    return is_wireless_device_product(product_id) || is_receiver_product(product_id) ||
           is_bluetooth_device_product(product_id);
}

bool text_contains_case_insensitive(const char *text, const char *needle) {
    if (text == NULL || needle == NULL || *needle == '\0') {
        return false;
    }
    for (const char *start = text; *start != '\0'; start++) {
        const char *text_cursor = start;
        const char *needle_cursor = needle;
        while (*text_cursor != '\0' && *needle_cursor != '\0' &&
               tolower((unsigned char)*text_cursor) == tolower((unsigned char)*needle_cursor)) {
            text_cursor++;
            needle_cursor++;
        }
        if (*needle_cursor == '\0') {
            return true;
        }
    }
    return false;
}

static void channel_report_callback(void *context, IOReturn result, void *sender,
                                    IOHIDReportType type, uint32_t report_id, uint8_t *report,
                                    CFIndex report_length) {
    (void)result;
    (void)sender;
    (void)type;
    HidChannel *channel = (HidChannel *)context;
    if (channel == NULL || report == NULL || report_length <= 0) {
        return;
    }
    HidReportNode *node = (HidReportNode *)calloc(1, sizeof(*node));
    if (node == NULL) {
        return;
    }
    node->report_id = report_id;
    node->length = (size_t)report_length;
    if (node->length > MAX_REPORT_BYTES) {
        node->length = MAX_REPORT_BYTES;
    }
    memcpy(node->bytes, report, node->length);

    pthread_mutex_lock(&channel->lock);
    if (channel->tail == NULL) {
        channel->head = node;
    } else {
        channel->tail->next = node;
    }
    channel->tail = node;
    pthread_mutex_unlock(&channel->lock);
}

void hid_report_callback_for_test(void *context, IOReturn result, void *sender,
                                  IOHIDReportType type, uint32_t report_id, uint8_t *report,
                                  CFIndex report_length) {
    channel_report_callback(context, result, sender, type, report_id, report, report_length);
}

int channel_open(HidChannel *channel, IOHIDDeviceRef device) {
    memset(channel, 0, sizeof(*channel));
    channel->device = device;
    channel->run_loop = CFRunLoopGetCurrent();
    pthread_mutex_init(&channel->lock, NULL);
    IOReturn result = kIOReturnError;
    for (int attempt = 0; attempt < 3; attempt++) {
        result = hid_device_open_impl(device, kIOHIDOptionsTypeNone);
        hid_debug_log("hid-debug open product=0x%04X location=0x%llX attempt=%d result=0x%08X",
                      number_property(device, CFSTR(kIOHIDProductIDKey)),
                      (unsigned long long)location_property(device), attempt + 1, result);
        if (result == kIOReturnSuccess || result != kIOReturnNotPermitted || attempt == 2) {
            break;
        }
        // macOS can briefly reject a HID interface while another client is
        // releasing it. Give that handoff a moment before treating the
        // device as inaccessible.
        usleep(150000);
    }
    if (result != kIOReturnSuccess) {
        if (result == kIOReturnNotPermitted) {
            fprintf(stderr,
                    "warning: macOS denied HID access to the Logitech interface; grant Input "
                    "Monitoring to the terminal/app running this utility (0x%08X)\n",
                    result);
        } else {
            fprintf(stderr, "warning: could not open a Logitech vendor HID interface (0x%08X)\n",
                    result);
        }
        pthread_mutex_destroy(&channel->lock);
        return 0;
    }
    channel->callback_buffer = (uint8_t *)calloc(MAX_REPORT_BYTES, 1);
    if (channel->callback_buffer == NULL) {
        hid_device_close_impl(device, kIOHIDOptionsTypeNone);
        pthread_mutex_destroy(&channel->lock);
        return 0;
    }
    hid_device_register_input_report_callback_impl(
        device, channel->callback_buffer, MAX_REPORT_BYTES, channel_report_callback, channel);
    hid_device_schedule_with_run_loop_impl(device, channel->run_loop, kCFRunLoopDefaultMode);
    channel->opened = true;
    return 1;
}

static void channel_clear_queue(HidChannel *channel) {
    pthread_mutex_lock(&channel->lock);
    HidReportNode *node = channel->head;
    channel->head = NULL;
    channel->tail = NULL;
    pthread_mutex_unlock(&channel->lock);
    while (node != NULL) {
        HidReportNode *next = node->next;
        free(node);
        node = next;
    }
}

static HidReportNode *channel_take_report(HidChannel *channel) {
    pthread_mutex_lock(&channel->lock);
    HidReportNode *node = channel->head;
    if (node != NULL) {
        channel->head = node->next;
        if (channel->head == NULL) {
            channel->tail = NULL;
        }
    }
    pthread_mutex_unlock(&channel->lock);
    return node;
}

void channel_close(HidChannel *channel) {
    if (channel == NULL) {
        return;
    }
    if (channel->opened) {
        hid_device_unschedule_from_run_loop_impl(channel->device, channel->run_loop,
                                                 kCFRunLoopDefaultMode);
        hid_device_close_impl(channel->device, kIOHIDOptionsTypeNone);
    }
    channel_clear_queue(channel);
    free(channel->callback_buffer);
    channel->callback_buffer = NULL;
    pthread_mutex_destroy(&channel->lock);
    channel->opened = false;
}

static HidReportNode *wait_for_report(HidChannel *channel, double timeout_seconds) {
    CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent() + timeout_seconds;
    for (;;) {
        HidReportNode *node = channel_take_report(channel);
        if (node != NULL) {
            return node;
        }
        CFAbsoluteTime remaining = deadline - CFAbsoluteTimeGetCurrent();
        if (remaining <= 0) {
            return NULL;
        }
        CFTimeInterval slice = remaining > 0.05 ? 0.05 : remaining;
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, slice, true);
    }
}

size_t build_hidpp_frame(bool use_long, uint8_t device_number, uint16_t request_id,
                         const uint8_t *params, size_t params_length,
                         uint8_t frame[LONG_REPORT_BYTES]) {
    size_t frame_length = use_long ? LONG_REPORT_BYTES : SHORT_REPORT_BYTES;
    memset(frame, 0, LONG_REPORT_BYTES);
    frame[0] = use_long ? REPORT_LONG : REPORT_SHORT;
    frame[1] = device_number;
    frame[2] = (uint8_t)(request_id >> 8);
    frame[3] = (uint8_t)(request_id & 0xFF);
    if (params_length > 0) {
        memcpy(frame + 4, params, params_length);
    }
    return frame_length;
}

// channel_request_impl is a test seam: self-test overrides it to inject
// canned Reply values so device_call/raw_request's feature-resolution and
// retry logic can be exercised without real IOKit hardware. Production code
// always runs through channel_request_hardware.
Reply channel_request_hardware(HidChannel *channel, uint8_t device_number, uint16_t request_id,
                               const uint8_t *params, size_t params_length, bool prefer_long,
                               double timeout_seconds) {
    Reply reply;
    memset(&reply, 0, sizeof(reply));
    if (params_length > 16) {
        reply.status = REPLY_PROTOCOL_ERROR;
        return reply;
    }
    channel_clear_queue(channel);

    bool use_long = prefer_long || (params_length + 2 > 5);
    uint8_t frame[LONG_REPORT_BYTES];
    // Apple’s IOKit API takes the report ID separately, but its contract for
    // numbered reports also requires that ID to be the first byte of the
    // report buffer. This is the same convention used by macOS hidapi.
    size_t frame_length =
        build_hidpp_frame(use_long, device_number, request_id, params, params_length, frame);
    IOReturn result = hid_device_set_report_impl(channel->device, kIOHIDReportTypeOutput,
                                                 use_long ? REPORT_LONG : REPORT_SHORT, frame,
                                                 (CFIndex)frame_length);
    hid_debug_log(
        "hid-debug tx report=0x%02X device=0x%02X request=0x%04X length=%zu result=0x%08X",
        use_long ? REPORT_LONG : REPORT_SHORT, device_number, request_id, frame_length, result);
    if (result != kIOReturnSuccess) {
        reply.status = REPLY_IO_ERROR;
        return reply;
    }

    uint8_t wanted[2] = {(uint8_t)(request_id >> 8), (uint8_t)(request_id & 0xFF)};
    CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent() + timeout_seconds;
    for (;;) {
        CFAbsoluteTime remaining = deadline - CFAbsoluteTimeGetCurrent();
        if (remaining <= 0) {
            reply.status = REPLY_TIMEOUT;
            return reply;
        }
        HidReportNode *node = wait_for_report(channel, remaining);
        if (node == NULL) {
            reply.status = REPLY_TIMEOUT;
            return reply;
        }
        size_t offset = 0;
        // IOHID callbacks normally exclude the report ID. Accept callbacks
        // that include it as well, which is useful with a few virtual HID
        // layers and costs nothing for normal IOKit devices.
        if (node->length > 0 && (node->bytes[0] == REPORT_SHORT || node->bytes[0] == REPORT_LONG)) {
            offset = 1;
        }
        if (node->length <= offset + 1) {
            free(node);
            continue;
        }
        const uint8_t *wire = node->bytes + offset;
        size_t wire_length = node->length - offset;
        uint8_t returned_device = wire[0];
        bool wireless_direct_alias = device_number == 0xFF &&
                                     request_id == (uint16_t)(0x0010 | SW_ID) &&
                                     returned_device >= 1 && returned_device <= 6;
        if (returned_device != device_number &&
            returned_device != (uint8_t)(device_number ^ 0xFF) && !wireless_direct_alias) {
            free(node);
            continue;
        }
        reply.device_number = returned_device;
        const uint8_t *body = wire + 1;
        size_t body_length = wire_length - 1;
        if (body_length >= 4 && node->report_id == REPORT_SHORT && body[0] == 0x8F &&
            body[1] == wanted[0] && body[2] == wanted[1]) {
            reply.status = REPLY_HIDPP10_ERROR;
            reply.error_code = body[3];
            free(node);
            return reply;
        }
        if (body_length >= 4 && body[0] == 0xFF && body[1] == wanted[0] && body[2] == wanted[1]) {
            reply.status = REPLY_HIDPP20_ERROR;
            reply.error_code = body[3];
            free(node);
            return reply;
        }
        if (body_length >= 2 && body[0] == wanted[0] && body[1] == wanted[1]) {
            reply.length = body_length - 2;
            if (reply.length > sizeof(reply.bytes)) {
                reply.length = sizeof(reply.bytes);
            }
            memcpy(reply.bytes, body + 2, reply.length);
            reply.status = REPLY_OK;
            if (hid_debug_enabled()) {
                char line[512];
                int written = snprintf(
                    line, sizeof(line),
                    "hid-debug rx report=0x%02X device=0x%02X request=0x%04X length=%zu bytes=",
                    node->report_id, returned_device, request_id, reply.length);
                for (size_t i = 0; i < reply.length && i < 16 && written < (int)sizeof(line); i++) {
                    written += snprintf(line + written, sizeof(line) - (size_t)written, "%02X",
                                        reply.bytes[i]);
                }
                hid_debug_log("%s", line);
            }
            free(node);
            return reply;
        }
        free(node);
    }
}

ChannelRequestFn channel_request_impl = channel_request_hardware;

Reply channel_request(HidChannel *channel, uint8_t device_number, uint16_t request_id,
                      const uint8_t *params, size_t params_length, bool prefer_long,
                      double timeout_seconds) {
    return channel_request_impl(channel, device_number, request_id, params, params_length,
                                prefer_long, timeout_seconds);
}

bool is_receiver_routed_device(const Device *device) {
    return device != NULL && device->request_device_number != 0xFF && device->iface != NULL &&
           is_receiver_product(device->iface->product_id);
}

bool should_retry_short_report(Reply reply) {
    // A few Lightspeed mouse firmware revisions accept the receiver's
    // long-report probe but only answer a routed feature request on the
    // short HID++ path. The receiver can report this as a timeout, I/O error,
    // or either HID++ error family while the radio route is waking up, so give
    // the alternate framing one chance for every non-success response.
    return reply.status == REPLY_TIMEOUT || reply.status == REPLY_IO_ERROR ||
           reply.status == REPLY_HIDPP10_ERROR || reply.status == REPLY_HIDPP20_ERROR;
}

const char *reply_status_name(ReplyStatus status) {
    switch (status) {
    case REPLY_TIMEOUT:
        return "timeout";
    case REPLY_HIDPP10_ERROR:
        return "HID++ 1.0 error";
    case REPLY_HIDPP20_ERROR:
        return "HID++ 2.0 feature error";
    case REPLY_IO_ERROR:
        return "I/O error";
    case REPLY_PROTOCOL_ERROR:
        return "protocol error";
    case REPLY_OK:
        return "ok";
    }
    return "unknown";
}

void print_reply_error(const char *operation, Reply reply) {
    if (reply.status == REPLY_OK) {
        return;
    }
    if (reply.status == REPLY_PROTOCOL_ERROR) {
        fprintf(stderr, "%s: %s\n", operation, reply_status_name(reply.status));
    } else {
        fprintf(stderr, "%s: %s (0x%02X)\n", operation, reply_status_name(reply.status),
                reply.error_code);
    }
}

int device_feature_index(const Device *device, uint16_t feature_id, uint8_t *index) {
    for (size_t i = 0; i < device->feature_count; i++) {
        if (device->features[i].id == feature_id) {
            *index = device->features[i].index;
            return 1;
        }
    }
    return 0;
}

static Reply device_call_with_report(Device *device, uint16_t feature_id, uint8_t function,
                                     const uint8_t *params, size_t params_length, bool prefer_long,
                                     double timeout_seconds) {
    uint8_t feature_index = 0;
    Reply reply;
    memset(&reply, 0, sizeof(reply));
    if (!device_feature_index(device, feature_id, &feature_index)) {
        reply.status = REPLY_PROTOCOL_ERROR;
        return reply;
    }
    uint16_t request_id = (uint16_t)(((uint16_t)feature_index << 8) | (function & 0xF0) | SW_ID);
    bool use_long = prefer_long || device->prefer_long_reports;
    reply = channel_request(&device->iface->channel, device->request_device_number, request_id,
                            params, params_length, use_long, timeout_seconds);
    if (!prefer_long && use_long && is_receiver_routed_device(device) &&
        should_retry_short_report(reply)) {
        Reply short_reply =
            channel_request(&device->iface->channel, device->request_device_number, request_id,
                            params, params_length, false, timeout_seconds);
        if (short_reply.status != REPLY_TIMEOUT) {
            return short_reply;
        }
    }
    return reply;
}

bool channel_get_feature_report(HidChannel *channel, uint8_t report_id, uint8_t *report,
                                size_t capacity, size_t *length) {
    if (channel == NULL || !channel->opened || report == NULL || capacity == 0 ||
        capacity > MAX_FEATURE_REPORT_BYTES) {
        return false;
    }
    memset(report, 0, capacity);
    report[0] = report_id;
    CFIndex actual_length = (CFIndex)capacity;
    IOReturn result = hid_device_get_report_impl(channel->device, kIOHIDReportTypeFeature,
                                                 report_id, report, &actual_length);
    hid_debug_log("hid-debug feature-get report=0x%02X capacity=%zu length=%ld result=0x%08X",
                  report_id, capacity, (long)actual_length, result);
    if (result != kIOReturnSuccess || actual_length < 1) {
        return false;
    }
    if ((size_t)actual_length > capacity) {
        actual_length = (CFIndex)capacity;
    }
    if (length != NULL) {
        *length = (size_t)actual_length;
    }
    return true;
}

bool channel_set_feature_report(HidChannel *channel, uint8_t report_id, uint8_t *report,
                                size_t length) {
    if (channel == NULL || !channel->opened || report == NULL || length < 1 ||
        length > MAX_FEATURE_REPORT_BYTES) {
        return false;
    }
    report[0] = report_id;
    IOReturn result = hid_device_set_report_impl(channel->device, kIOHIDReportTypeFeature,
                                                 report_id, report, (CFIndex)length);
    hid_debug_log("hid-debug feature-set report=0x%02X length=%zu result=0x%08X", report_id, length,
                  result);
    return result == kIOReturnSuccess;
}

Reply device_call(Device *device, uint16_t feature_id, uint8_t function, const uint8_t *params,
                  size_t params_length, double timeout_seconds) {
    return device_call_with_report(device, feature_id, function, params, params_length, false,
                                   timeout_seconds);
}

Reply device_call_long(Device *device, uint16_t feature_id, uint8_t function, const uint8_t *params,
                       size_t params_length, double timeout_seconds) {
    return device_call_with_report(device, feature_id, function, params, params_length, true,
                                   timeout_seconds);
}

Reply raw_request(Device *device, uint16_t request_id, const uint8_t *params, size_t params_length,
                  bool prefer_long, double timeout_seconds) {
    bool use_long = prefer_long || device->prefer_long_reports;
    Reply reply = channel_request(&device->iface->channel, device->request_device_number,
                                  request_id, params, params_length, use_long, timeout_seconds);
    if (!prefer_long && use_long && is_receiver_routed_device(device) &&
        should_retry_short_report(reply)) {
        Reply short_reply =
            channel_request(&device->iface->channel, device->request_device_number, request_id,
                            params, params_length, false, timeout_seconds);
        if (short_reply.status != REPLY_TIMEOUT) {
            return short_reply;
        }
    }
    return reply;
}
