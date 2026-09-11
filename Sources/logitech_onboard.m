// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026
//
// logitech-onboard: a deliberately small, read-first Logitech HID++ utility for
// macOS. Protocol constants and layout knowledge are based on public Solaar,
// libratbag, lowtech, and omm.py research; see docs/PROTOCOL.md.

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/hid/IOHIDElement.h>
#include <IOKit/hid/IOHIDKeys.h>
#include <IOKit/hid/IOHIDManager.h>
#include <IOKit/hid/IOHIDLib.h>
#include <IOKit/IOKitLib.h>
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <pthread.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define LOGITECH_VID 0x046D
#define HIDPP_USAGE_PAGE 0xFF00
#define MOUSE_USAGE_PAGE 0x0001
#define MOUSE_USAGE 0x0002

#define REPORT_SHORT 0x10
#define REPORT_LONG 0x11
#define SHORT_REPORT_BYTES 7
#define LONG_REPORT_BYTES 20
#define MAX_REPORT_BYTES 64
#define MAX_SECTOR_BYTES 4096
#define MAX_FEATURES 128
#define MAX_DEVICES 64
#define MAX_HEADERS 32
#define MAX_DPI_VALUES 1024
#define SW_ID 0x0B

#define FEATURE_ROOT 0x0000
#define FEATURE_SET 0x0001
#define FEATURE_DEVICE_NAME 0x0005
#define FEATURE_ADJUSTABLE_DPI 0x2201
#define FEATURE_ONBOARD_PROFILES 0x8100

#define ONBOARD_GET_INFO 0x00
#define ONBOARD_READ_SECTOR 0x50
#define ONBOARD_START_WRITE 0x60
#define ONBOARD_WRITE_DATA 0x70
#define ONBOARD_END_WRITE 0x80

#define BACKUP_HEADER_BYTES 20
#define BACKUP_MAGIC "LOGIOB01"

typedef struct HidReportNode {
    uint32_t report_id;
    size_t length;
    uint8_t bytes[MAX_REPORT_BYTES];
    struct HidReportNode *next;
} HidReportNode;

typedef struct {
    IOHIDDeviceRef device;
    uint8_t *callback_buffer;
    CFRunLoopRef run_loop;
    pthread_mutex_t lock;
    HidReportNode *head;
    HidReportNode *tail;
    bool opened;
} HidChannel;

typedef struct {
    IOHIDDeviceRef device;
    uint32_t vendor_id;
    uint32_t product_id;
    uint32_t usage_page;
    uint32_t usage;
    uint64_t location_id;
    uint64_t registry_id;
    char product[256];
    char transport[128];
    bool is_vendor;
    bool is_mouse;
    HidChannel channel;
    bool channel_open;
} HidInterface;

typedef struct {
    IOHIDManagerRef manager;
    CFSetRef device_set;
    HidInterface *items;
    size_t count;
    bool manager_open;
} HidContext;

typedef struct {
    uint16_t id;
    uint8_t index;
    uint8_t version;
} Feature;

typedef struct {
    HidInterface *iface;
    uint8_t device_number;
    double protocol;
    Feature features[MAX_FEATURES];
    size_t feature_count;
    char name[256];
} Device;

typedef enum {
    REPLY_OK = 0,
    REPLY_TIMEOUT = 1,
    REPLY_HIDPP10_ERROR = 2,
    REPLY_HIDPP20_ERROR = 3,
    REPLY_IO_ERROR = 4,
    REPLY_PROTOCOL_ERROR = 5,
} ReplyStatus;

typedef struct {
    ReplyStatus status;
    uint8_t error_code;
    uint8_t bytes[MAX_REPORT_BYTES];
    size_t length;
} Reply;

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
} ProfileInfo;

typedef struct {
    uint16_t sector;
    uint8_t enabled;
} ProfileHeader;

typedef struct {
    ProfileInfo info;
    ProfileHeader headers[MAX_HEADERS];
    size_t header_count;
    size_t selected_header;
    uint8_t *data;
    size_t data_length;
    bool crc_ok;
    size_t button_offset;
    size_t valid_specs;
    size_t known_specs;
    bool layout_supported;
    size_t dpi_offset;
    size_t dpi_count;
    uint8_t dpi_default_index;
    uint8_t dpi_shift_index;
    bool dpi_layout_supported;
} Profile;

typedef struct {
    const char *command;
    const char *path;
    const char *target;
    const char *backup_path;
    int device_index;
    int slot;
    int profile;
    int button;
    int dpi_default;
    int dpi_shift;
    bool yes;
    const char *positionals[8];
    size_t positional_count;
} Options;

typedef struct {
    uint16_t sector;
    uint16_t size;
    uint16_t vendor_id;
    uint16_t product_id;
    uint8_t device_number;
    uint8_t profile_format;
    uint8_t *data;
} BackupPackage;

static volatile sig_atomic_t g_stop_watch = 0;

static void on_sigint(int signal_number) {
    (void)signal_number;
    g_stop_watch = 1;
}

static uint32_t number_property(IOHIDDeviceRef device, CFStringRef key) {
    CFTypeRef value = IOHIDDeviceGetProperty(device, key);
    if (value == NULL || CFGetTypeID(value) != CFNumberGetTypeID()) {
        return 0;
    }
    int32_t number = 0;
    if (!CFNumberGetValue((CFNumberRef)value, kCFNumberSInt32Type, &number)) {
        return 0;
    }
    return (uint32_t)number;
}

static uint64_t location_property(IOHIDDeviceRef device) {
    CFTypeRef value = IOHIDDeviceGetProperty(device, CFSTR(kIOHIDLocationIDKey));
    if (value == NULL || CFGetTypeID(value) != CFNumberGetTypeID()) {
        return 0;
    }
    int32_t number = 0;
    if (!CFNumberGetValue((CFNumberRef)value, kCFNumberSInt32Type, &number)) {
        return 0;
    }
    return (uint64_t)(uint32_t)number;
}

static uint64_t registry_id_property(IOHIDDeviceRef device) {
    io_service_t service = IOHIDDeviceGetService(device);
    if (service == IO_OBJECT_NULL) {
        return 0;
    }
    uint64_t registry_id = 0;
    if (IORegistryEntryGetRegistryEntryID(service, &registry_id) != KERN_SUCCESS) {
        return 0;
    }
    return registry_id;
}

static void string_property(IOHIDDeviceRef device, CFStringRef key, char *out, size_t out_size) {
    out[0] = '\0';
    CFTypeRef value = IOHIDDeviceGetProperty(device, key);
    if (value == NULL || CFGetTypeID(value) != CFStringGetTypeID()) {
        return;
    }
    CFStringGetCString((CFStringRef)value, out, (CFIndex)out_size, kCFStringEncodingUTF8);
}

static bool device_has_hidpp_reports(IOHIDDeviceRef device) {
    CFTypeRef descriptor_value = IOHIDDeviceGetProperty(device, CFSTR(kIOHIDReportDescriptorKey));
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

    // Keep an element-based fallback for devices whose driver does not expose
    // the raw report descriptor as an IOHIDDevice property.
    CFArrayRef elements = IOHIDDeviceCopyMatchingElements(device, NULL, kIOHIDOptionsTypeNone);
    if (elements == NULL) {
        return false;
    }
    bool found = false;
    CFIndex count = CFArrayGetCount(elements);
    for (CFIndex i = 0; i < count; i++) {
        IOHIDElementRef element = (IOHIDElementRef)CFArrayGetValueAtIndex(elements, i);
        if (element == NULL || IOHIDElementGetUsagePage(element) != HIDPP_USAGE_PAGE) {
            continue;
        }
        uint32_t report_id = IOHIDElementGetReportID(element);
        if (report_id == REPORT_SHORT || report_id == REPORT_LONG) {
            found = true;
            break;
        }
    }
    CFRelease(elements);
    return found;
}

static bool is_wireless_device_product(uint32_t product_id) {
    // Logitech wireless HID++ product IDs are in the 0x4000 range. Some
    // macOS HID stacks do not expose the vendor report descriptor for these
    // interfaces, so the product ID is the reliable fallback (notably for
    // the G604, PID 0x4085).
    return (product_id >= 0x4002 && product_id <= 0x4097) ||
           product_id == 0x4101 || product_id == 0x4102;
}

static void channel_report_callback(void *context,
                                    IOReturn result,
                                    void *sender,
                                    IOHIDReportType type,
                                    uint32_t report_id,
                                    uint8_t *report,
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

static int channel_open(HidChannel *channel, IOHIDDeviceRef device) {
    memset(channel, 0, sizeof(*channel));
    channel->device = device;
    channel->run_loop = CFRunLoopGetCurrent();
    pthread_mutex_init(&channel->lock, NULL);
    IOReturn result = IOHIDDeviceOpen(device, kIOHIDOptionsTypeNone);
    if (result != kIOReturnSuccess) {
        if (result == kIOReturnNotPermitted) {
            fprintf(stderr, "warning: macOS denied HID access to the Logitech interface; grant Input Monitoring to the terminal/app running this utility (0x%08X)\n", result);
        } else {
            fprintf(stderr, "warning: could not open a Logitech vendor HID interface (0x%08X)\n", result);
        }
        pthread_mutex_destroy(&channel->lock);
        return 0;
    }
    channel->callback_buffer = (uint8_t *)calloc(MAX_REPORT_BYTES, 1);
    if (channel->callback_buffer == NULL) {
        IOHIDDeviceClose(device, kIOHIDOptionsTypeNone);
        pthread_mutex_destroy(&channel->lock);
        return 0;
    }
    IOHIDDeviceRegisterInputReportCallback(device,
                                           channel->callback_buffer,
                                           MAX_REPORT_BYTES,
                                           channel_report_callback,
                                           channel);
    IOHIDDeviceScheduleWithRunLoop(device, channel->run_loop, kCFRunLoopDefaultMode);
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

static void channel_close(HidChannel *channel) {
    if (channel == NULL) {
        return;
    }
    if (channel->opened) {
        IOHIDDeviceUnscheduleFromRunLoop(channel->device, channel->run_loop, kCFRunLoopDefaultMode);
        IOHIDDeviceClose(channel->device, kIOHIDOptionsTypeNone);
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

static size_t build_hidpp_frame(bool use_long,
                                uint8_t device_number,
                                uint16_t request_id,
                                const uint8_t *params,
                                size_t params_length,
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

static Reply channel_request(HidChannel *channel,
                             uint8_t device_number,
                             uint16_t request_id,
                             const uint8_t *params,
                             size_t params_length,
                             bool prefer_long,
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
    size_t frame_length = build_hidpp_frame(use_long, device_number, request_id,
                                            params, params_length, frame);
    IOReturn result = IOHIDDeviceSetReport(channel->device,
                                           kIOHIDReportTypeOutput,
                                           use_long ? REPORT_LONG : REPORT_SHORT,
                                           frame,
                                           (CFIndex)frame_length);
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
        if (returned_device != device_number && returned_device != (uint8_t)(device_number ^ 0xFF)) {
            free(node);
            continue;
        }
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
            free(node);
            return reply;
        }
        free(node);
    }
}

static const char *reply_status_name(ReplyStatus status) {
    switch (status) {
        case REPLY_TIMEOUT: return "timeout";
        case REPLY_HIDPP10_ERROR: return "HID++ 1.0 error";
        case REPLY_HIDPP20_ERROR: return "HID++ 2.0 feature error";
        case REPLY_IO_ERROR: return "I/O error";
        case REPLY_PROTOCOL_ERROR: return "protocol error";
        case REPLY_OK: return "ok";
    }
    return "unknown";
}

static void print_reply_error(const char *operation, Reply reply) {
    if (reply.status == REPLY_OK) {
        return;
    }
    if (reply.status == REPLY_PROTOCOL_ERROR) {
        fprintf(stderr, "%s: %s\n", operation, reply_status_name(reply.status));
    } else {
        fprintf(stderr, "%s: %s (0x%02X)\n", operation, reply_status_name(reply.status), reply.error_code);
    }
}

static int device_feature_index(const Device *device, uint16_t feature_id, uint8_t *index) {
    for (size_t i = 0; i < device->feature_count; i++) {
        if (device->features[i].id == feature_id) {
            *index = device->features[i].index;
            return 1;
        }
    }
    return 0;
}

static Reply device_call_with_report(Device *device,
                                     uint16_t feature_id,
                                     uint8_t function,
                                     const uint8_t *params,
                                     size_t params_length,
                                     bool prefer_long,
                                     double timeout_seconds) {
    uint8_t feature_index = 0;
    Reply reply;
    memset(&reply, 0, sizeof(reply));
    if (!device_feature_index(device, feature_id, &feature_index)) {
        reply.status = REPLY_PROTOCOL_ERROR;
        return reply;
    }
    uint16_t request_id = (uint16_t)(((uint16_t)feature_index << 8) | (function & 0xF0) | SW_ID);
    return channel_request(&device->iface->channel,
                           device->device_number,
                           request_id,
                           params,
                           params_length,
                           prefer_long,
                           timeout_seconds);
}

static Reply device_call(Device *device,
                         uint16_t feature_id,
                         uint8_t function,
                         const uint8_t *params,
                         size_t params_length,
                         double timeout_seconds) {
    return device_call_with_report(device, feature_id, function, params,
                                   params_length, false, timeout_seconds);
}

static Reply device_call_long(Device *device,
                              uint16_t feature_id,
                              uint8_t function,
                              const uint8_t *params,
                              size_t params_length,
                              double timeout_seconds) {
    return device_call_with_report(device, feature_id, function, params,
                                   params_length, true, timeout_seconds);
}

static Reply raw_request(Device *device,
                         uint16_t request_id,
                         const uint8_t *params,
                         size_t params_length,
                         bool prefer_long,
                         double timeout_seconds) {
    return channel_request(&device->iface->channel,
                           device->device_number,
                           request_id,
                           params,
                           params_length,
                           prefer_long,
                           timeout_seconds);
}

static int ping_interface(HidInterface *iface, uint8_t device_number, double timeout, double *protocol) {
    uint8_t params[3] = {0, 0, 0x5A};
    Reply reply = channel_request(&iface->channel,
                                  device_number,
                                  (uint16_t)(0x0010 | SW_ID),
                                  params,
                                  sizeof(params),
                                  false,
                                  timeout);
    if (reply.status == REPLY_OK && reply.length >= 3 && reply.bytes[2] == 0x5A) {
        *protocol = (double)reply.bytes[0] + (double)reply.bytes[1] / 10.0;
        return 1;
    }
    // A HID++ 1.0 receiver answers the 2.0-style ping with invalid-sub-id.
    // It is useful to list that receiver, but it cannot edit a 0x8100 profile.
    if (reply.status == REPLY_HIDPP10_ERROR && reply.error_code == 0x01) {
        *protocol = 1.0;
        return 1;
    }
    return 0;
}

static int discover_features(Device *device) {
    Reply reply = raw_request(device, (uint16_t)(FEATURE_ROOT | SW_ID),
                              (const uint8_t[]){0x00, 0x01}, 2, false, 1.0);
    if (reply.status != REPLY_OK || reply.length < 1 || reply.bytes[0] == 0) {
        return 0;
    }
    uint8_t feature_set_index = reply.bytes[0];
    device->feature_count = 0;
    if (device->feature_count < MAX_FEATURES) {
        device->features[device->feature_count++] = (Feature){FEATURE_ROOT, 0, 0};
    }

    uint16_t count_request = (uint16_t)(((uint16_t)feature_set_index << 8) | SW_ID);
    reply = raw_request(device, count_request, NULL, 0, false, 1.0);
    if (reply.status != REPLY_OK || reply.length < 1) {
        return 0;
    }
    uint8_t count = reply.bytes[0];
    for (uint16_t i = 0; i <= count && i < 256; i++) {
        uint8_t item = (uint8_t)i;
        uint16_t request_id = (uint16_t)(((uint16_t)feature_set_index << 8) | 0x10 | SW_ID);
        reply = raw_request(device, request_id, &item, 1, false, 1.0);
        if (reply.status != REPLY_OK || reply.length < 4) {
            continue;
        }
        uint16_t feature_id = (uint16_t)(((uint16_t)reply.bytes[0] << 8) | reply.bytes[1]);
        bool duplicate = false;
        for (size_t j = 0; j < device->feature_count; j++) {
            if (device->features[j].id == feature_id) {
                duplicate = true;
                break;
            }
        }
        if (!duplicate && device->feature_count < MAX_FEATURES) {
            device->features[device->feature_count++] = (Feature){feature_id, item, reply.bytes[3]};
        }
    }
    return 1;
}

static int device_name(Device *device) {
    uint8_t unused_index = 0;
    if (!device_feature_index(device, FEATURE_DEVICE_NAME, &unused_index)) {
        return 0;
    }
    Reply reply = device_call(device, FEATURE_DEVICE_NAME, 0x00, NULL, 0, 1.0);
    if (reply.status != REPLY_OK || reply.length < 1) {
        return 0;
    }
    size_t wanted = reply.bytes[0];
    if (wanted >= sizeof(device->name)) {
        wanted = sizeof(device->name) - 1;
    }
    size_t copied = 0;
    while (copied < wanted) {
        uint8_t offset = (uint8_t)copied;
        reply = device_call(device, FEATURE_DEVICE_NAME, 0x10, &offset, 1, 1.0);
        if (reply.status != REPLY_OK || reply.length == 0) {
            return 0;
        }
        size_t take = reply.length;
        if (take > wanted - copied) {
            take = wanted - copied;
        }
        memcpy(device->name + copied, reply.bytes, take);
        copied += take;
    }
    device->name[copied] = '\0';
    while (copied > 0 && (device->name[copied - 1] == '\0' || device->name[copied - 1] == '\n')) {
        device->name[--copied] = '\0';
    }
    return copied > 0;
}

static void hid_context_release(HidContext *context) {
    if (context == NULL) {
        return;
    }
    for (size_t i = 0; i < context->count; i++) {
        if (context->items[i].channel_open) {
            channel_close(&context->items[i].channel);
        }
    }
    free(context->items);
    if (context->device_set != NULL) {
        CFRelease(context->device_set);
    }
    if (context->manager != NULL && context->manager_open) {
        IOHIDManagerClose(context->manager, kIOHIDOptionsTypeNone);
    }
    if (context->manager != NULL) {
        CFRelease(context->manager);
    }
    memset(context, 0, sizeof(*context));
}

static int compare_hid_interfaces(const void *left_pointer, const void *right_pointer) {
    const HidInterface *left = (const HidInterface *)left_pointer;
    const HidInterface *right = (const HidInterface *)right_pointer;
    if (left->location_id != right->location_id) {
        return left->location_id < right->location_id ? -1 : 1;
    }
    if (left->registry_id != right->registry_id) {
        return left->registry_id < right->registry_id ? -1 : 1;
    }
    if (left->product_id != right->product_id) {
        return left->product_id < right->product_id ? -1 : 1;
    }
    if (left->usage_page != right->usage_page) {
        return left->usage_page < right->usage_page ? -1 : 1;
    }
    if (left->usage != right->usage) {
        return left->usage < right->usage ? -1 : 1;
    }
    int product_result = strcmp(left->product, right->product);
    if (product_result != 0) {
        return product_result;
    }
    return strcmp(left->transport, right->transport);
}

static int hid_context_create(HidContext *context) {
    memset(context, 0, sizeof(*context));
    context->manager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    if (context->manager == NULL) {
        fprintf(stderr, "could not create macOS HID manager\n");
        return 0;
    }
    IOHIDManagerSetDeviceMatching(context->manager, NULL);
    // CopyDevices is the enumeration primitive and does not require opening
    // the manager. Opening it first can fail under macOS HID privacy
    // restrictions, even though the individual device is enumerable/openable.
    context->device_set = IOHIDManagerCopyDevices(context->manager);
    if (context->device_set == NULL) {
        fprintf(stderr, "could not enumerate macOS HID devices\n");
        hid_context_release(context);
        return 0;
    }
    CFIndex count = CFSetGetCount(context->device_set);
    if (count > 0) {
        IOHIDDeviceRef *devices = (IOHIDDeviceRef *)calloc((size_t)count, sizeof(*devices));
        if (devices == NULL) {
            hid_context_release(context);
            return 0;
        }
        CFSetGetValues(context->device_set, (const void **)devices);
        context->items = (HidInterface *)calloc((size_t)count, sizeof(*context->items));
        if (context->items == NULL) {
            free(devices);
            hid_context_release(context);
            return 0;
        }
        for (CFIndex i = 0; i < count; i++) {
            IOHIDDeviceRef device = devices[i];
            uint32_t vendor_id = number_property(device, CFSTR(kIOHIDVendorIDKey));
            if (vendor_id != LOGITECH_VID) {
                continue;
            }
            uint32_t page = number_property(device, CFSTR(kIOHIDPrimaryUsagePageKey));
            uint32_t usage = number_property(device, CFSTR(kIOHIDPrimaryUsageKey));
            uint32_t product_id = number_property(device, CFSTR(kIOHIDProductIDKey));
            // Some Logitech mice combine keyboard/mouse collections and
            // HID++ collections in one interface; the primary usage is not
            // always the vendor page. Inspect all parsed elements as well.
            bool vendor = page == HIDPP_USAGE_PAGE || device_has_hidpp_reports(device);
            bool mouse = page == MOUSE_USAGE_PAGE && usage == MOUSE_USAGE;
            if (!vendor && !mouse) {
                continue;
            }
            HidInterface *item = &context->items[context->count++];
            item->device = device;
            item->vendor_id = vendor_id;
            item->product_id = product_id;
            item->usage_page = page;
            item->usage = usage;
            item->location_id = location_property(device);
            item->registry_id = registry_id_property(device);
            item->is_vendor = vendor;
            item->is_mouse = mouse;
            string_property(device, CFSTR(kIOHIDProductKey), item->product, sizeof(item->product));
            string_property(device, CFSTR(kIOHIDTransportKey), item->transport, sizeof(item->transport));
        }
        free(devices);

        // IOHIDManagerCopyDevices returns a CFSet, whose iteration order is
        // intentionally unspecified. Every CLI invocation must nevertheless
        // agree on what `--device N` means, because the GUI lists devices in
        // one process and reads the selected device in another.
        qsort(context->items, context->count, sizeof(*context->items), compare_hid_interfaces);
    }
    return 1;
}

static int open_vendor_channels(HidContext *context) {
    for (size_t i = 0; i < context->count; i++) {
        HidInterface *iface = &context->items[i];
        if (!iface->is_vendor || iface->channel_open) {
            continue;
        }
        if (channel_open(&iface->channel, iface->device)) {
            iface->channel_open = true;
        }
    }
    return 1;
}

static int add_device(Device *devices, size_t *count, HidInterface *iface, uint8_t device_number, double protocol) {
    if (*count >= MAX_DEVICES) {
        return 0;
    }
    Device *device = &devices[(*count)++];
    memset(device, 0, sizeof(*device));
    device->iface = iface;
    device->device_number = device_number;
    device->protocol = protocol;
    if (protocol >= 2.0) {
        discover_features(device);
        device_name(device);
    }
    return 1;
}

static bool is_receiver_interface(const HidInterface *iface) {
    // Logitech USB receiver product IDs occupy the C5xx range. Direct USB
    // mice use a different product-ID range and should not be probed as if
    // they had receiver slots.
    return iface != NULL && iface->product_id >= 0xC500 && iface->product_id <= 0xC5FF;
}

static bool is_receiver_endpoint(const Device *device);
static bool is_mouse_device(const Device *device);

static int discover_devices(HidContext *context, int requested_slot, Device *devices, size_t *count) {
    *count = 0;
    open_vendor_channels(context);
    for (size_t i = 0; i < context->count; i++) {
        HidInterface *iface = &context->items[i];
        if (!iface->is_vendor || !iface->channel_open) {
            continue;
        }
        if (requested_slot >= 0) {
            double protocol = 0;
            if (ping_interface(iface, (uint8_t)requested_slot, requested_slot == 0xFF ? 1.0 : 0.35, &protocol)) {
                add_device(devices, count, iface, (uint8_t)requested_slot, protocol);
            }
            continue;
        }
        for (uint8_t slot = 1; slot <= 6; slot++) {
            double protocol = 0;
            if (ping_interface(iface, slot, 0.35, &protocol)) {
                add_device(devices, count, iface, slot, protocol);
            }
        }
        double protocol = 0;
        if (ping_interface(iface, 0xFF, 0.9, &protocol)) {
            add_device(devices, count, iface, 0xFF, protocol);
        }
    }
    return 1;
}

static const char *device_label(const Device *device) {
    if (device->name[0] != '\0') {
        return device->name;
    }
    if (device->iface->product[0] != '\0') {
        return device->iface->product;
    }
    return "Logitech HID++ device";
}

static bool text_contains_case_insensitive(const char *text, const char *needle) {
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

static bool is_receiver_endpoint(const Device *device) {
    if (device == NULL || device->device_number != 0xFF) {
        return false;
    }
    return is_receiver_interface(device->iface) ||
           text_contains_case_insensitive(device_label(device), "receiver") ||
           text_contains_case_insensitive(device->iface->product, "receiver") ||
           text_contains_case_insensitive(device_label(device), "unifying") ||
           text_contains_case_insensitive(device_label(device), "bolt");
}

static bool is_mouse_device(const Device *device) {
    if (device == NULL || is_receiver_endpoint(device)) {
        return false;
    }
    if (text_contains_case_insensitive(device_label(device), "keyboard") ||
        text_contains_case_insensitive(device_label(device), "keypad") ||
        text_contains_case_insensitive(device->iface->product, "keyboard") ||
        text_contains_case_insensitive(device->iface->product, "keypad")) {
        return false;
    }
    if (device->iface->is_mouse) {
        return true;
    }
    // A paired mouse may not have a standard mouse HID interface of its own;
    // these mouse-specific HID++ features still identify it as a mouse.
    if (device_feature_index(device, FEATURE_ONBOARD_PROFILES, &(uint8_t){0}) ||
        device_feature_index(device, FEATURE_ADJUSTABLE_DPI, &(uint8_t){0})) {
        return true;
    }
    // A paired HID++ slot is a real peripheral rather than the receiver
    // itself. Keep it visible when older firmware does not expose the
    // mouse-specific feature list; the name checks above still suppress
    // ordinary paired keyboards.
    return true;
}

static const char *device_connection(const Device *device) {
    if (device->device_number != 0xFF || is_wireless_device_product(device->iface->product_id)) {
        return "Receiver";
    }
    if (text_contains_case_insensitive(device->iface->transport, "bluetooth")) {
        return "Bluetooth";
    }
    return "Wired";
}

static uint16_t crc16_ccitt_false(const uint8_t *bytes, size_t length) {
    uint16_t crc = 0xFFFF;
    for (size_t i = 0; i < length; i++) {
        crc ^= (uint16_t)bytes[i] << 8;
        for (int bit = 0; bit < 8; bit++) {
            crc = (crc & 0x8000) ? (uint16_t)((crc << 1) ^ 0x1021) : (uint16_t)(crc << 1);
        }
    }
    return crc;
}

static bool sector_crc_ok(const uint8_t *bytes, size_t length) {
    if (length < 2) {
        return false;
    }
    uint16_t stored = (uint16_t)(((uint16_t)bytes[length - 2] << 8) | bytes[length - 1]);
    return crc16_ccitt_false(bytes, length - 2) == stored;
}

static void sector_put_crc(uint8_t *bytes, size_t length) {
    uint16_t crc = crc16_ccitt_false(bytes, length - 2);
    bytes[length - 2] = (uint8_t)(crc >> 8);
    bytes[length - 1] = (uint8_t)(crc & 0xFF);
}

static int get_profile_info(Device *device, ProfileInfo *info) {
    Reply reply = device_call(device, FEATURE_ONBOARD_PROFILES, ONBOARD_GET_INFO, NULL, 0, 2.0);
    if (reply.status != REPLY_OK) {
        print_reply_error("ONBOARD_PROFILES.getInfo", reply);
        return 0;
    }
    if (reply.length < 10) {
        fprintf(stderr, "ONBOARD_PROFILES.getInfo returned only %zu bytes\n", reply.length);
        return 0;
    }
    memset(info, 0, sizeof(*info));
    info->memory = reply.bytes[0];
    info->profile_format = reply.bytes[1];
    info->macro_format = reply.bytes[2];
    info->profile_count = reply.bytes[3];
    info->out_of_band = reply.bytes[4];
    info->button_count = reply.bytes[5];
    info->sector_count = reply.bytes[6];
    info->sector_size = (uint16_t)(((uint16_t)reply.bytes[7] << 8) | reply.bytes[8]);
    info->shift_flags = reply.bytes[9];
    if (info->sector_size < 32 || info->sector_size > MAX_SECTOR_BYTES || info->sector_size < 2) {
        fprintf(stderr, "device reported implausible onboard sector size %u\n", info->sector_size);
        return 0;
    }
    if (info->button_count == 0 || info->button_count > 64) {
        fprintf(stderr, "device reported implausible button count %u\n", info->button_count);
        return 0;
    }
    return 1;
}

static int read_sector(Device *device, uint16_t sector, size_t size, uint8_t *out) {
    if (size < 2 || size > MAX_SECTOR_BYTES) {
        return 0;
    }
    size_t copied = 0;
    while (copied < size) {
        size_t request_offset = copied;
        if (size - copied < 16) {
            request_offset = size - 16;
        }
        // readSector takes only the sector number and byte offset. The
        // length field belongs to startWrite (0x60), not to readSector
        // (0x50); appending two zero bytes can make some firmware return a
        // response that does not represent the requested sector.
        uint8_t params[4] = {
            (uint8_t)(sector >> 8), (uint8_t)(sector & 0xFF),
            (uint8_t)(request_offset >> 8), (uint8_t)(request_offset & 0xFF),
        };
        Reply reply = device_call(device, FEATURE_ONBOARD_PROFILES, ONBOARD_READ_SECTOR,
                                  params, sizeof(params), 2.0);
        if (reply.status != REPLY_OK || reply.length < 16) {
            print_reply_error("ONBOARD_PROFILES.readSector", reply);
            if (reply.status == REPLY_OK) {
                fprintf(stderr, "readSector returned only %zu bytes\n", reply.length);
            }
            return 0;
        }
        size_t from = copied > request_offset ? copied - request_offset : 0;
        size_t take = 16 - from;
        if (take > size - copied) {
            take = size - copied;
        }
        memcpy(out + copied, reply.bytes + from, take);
        copied += take;
    }
    return 1;
}

static int write_sector(Device *device, uint16_t sector, const uint8_t *bytes, size_t length) {
    if (length < 2 || length > MAX_SECTOR_BYTES) {
        return 0;
    }
    uint8_t start_params[6] = {
        (uint8_t)(sector >> 8), (uint8_t)(sector & 0xFF), 0, 0,
        (uint8_t)(length >> 8), (uint8_t)(length & 0xFF),
    };
    Reply reply = device_call(device, FEATURE_ONBOARD_PROFILES, ONBOARD_START_WRITE,
                              start_params, sizeof(start_params), 4.0);
    if (reply.status != REPLY_OK) {
        print_reply_error("ONBOARD_PROFILES.startWrite", reply);
        return 0;
    }
    size_t offset = 0;
    while (offset < length) {
        size_t take = length - offset;
        if (take > 16) {
            take = 16;
        }
        reply = device_call(device, FEATURE_ONBOARD_PROFILES, ONBOARD_WRITE_DATA,
                            bytes + offset, take, 4.0);
        if (reply.status != REPLY_OK) {
            print_reply_error("ONBOARD_PROFILES.writeData", reply);
            return 0;
        }
        offset += take;
    }
    reply = device_call(device, FEATURE_ONBOARD_PROFILES, ONBOARD_END_WRITE, NULL, 0, 4.0);
    if (reply.status != REPLY_OK) {
        print_reply_error("ONBOARD_PROFILES.endWrite", reply);
        return 0;
    }
    return 1;
}

static int read_profile_control(Device *device,
                                const ProfileInfo *info,
                                uint16_t *control_sector_out,
                                uint8_t *control) {
    uint16_t header_sector = 0;
    if (!read_sector(device, 0, info->sector_size, control)) {
        return 0;
    }
    bool all_zero = true;
    bool all_ff = true;
    for (size_t i = 0; i < 4 && i < info->sector_size; i++) {
        all_zero = all_zero && control[i] == 0x00;
        all_ff = all_ff && control[i] == 0xFF;
    }
    if (all_zero || all_ff) {
        header_sector = 1;
        if (!read_sector(device, header_sector, info->sector_size, control)) {
            return 0;
        }
    }
    if (control_sector_out != NULL) {
        *control_sector_out = header_sector;
    }
    return 1;
}

static int parse_profile_headers(const ProfileInfo *info,
                                 const uint8_t *control,
                                 ProfileHeader *headers,
                                 size_t *header_count) {
    *header_count = 0;
    size_t limit = info->sector_size - 2;
    for (size_t offset = 0; offset + 3 < limit && *header_count < MAX_HEADERS; offset += 4) {
        if (control[offset] == 0xFF && control[offset + 1] == 0xFF) {
            break;
        }
        uint16_t sector = (uint16_t)(((uint16_t)control[offset] << 8) | control[offset + 1]);
        if (sector == 0) {
            break;
        }
        headers[*header_count].sector = sector;
        headers[*header_count].enabled = control[offset + 2];
        (*header_count)++;
    }
    return *header_count > 0;
}

static int read_profile_headers(Device *device,
                                const ProfileInfo *info,
                                ProfileHeader *headers,
                                size_t *header_count) {
    uint8_t *control = (uint8_t *)malloc(info->sector_size);
    if (control == NULL) {
        return 0;
    }
    bool ok = read_profile_control(device, info, NULL, control) &&
              parse_profile_headers(info, control, headers, header_count);
    free(control);
    return ok;
}

static bool spec_is_disabled(const uint8_t spec[4]) {
    return spec[0] == 0xFF && spec[1] == 0xFF && spec[2] == 0xFF && spec[3] == 0xFF;
}

static bool spec_structurally_valid(const uint8_t spec[4]) {
    if (spec_is_disabled(spec)) {
        return true;
    }
    uint8_t behavior = spec[0] >> 4;
    if (behavior <= 0x02) {
        return true; // macro records are preserved but not edited by this tool
    }
    if (behavior == 0x08) {
        return spec[1] <= 0x03;
    }
    if (behavior == 0x09) {
        return spec[1] <= 0x11;
    }
    return false;
}

static bool spec_known(const uint8_t spec[4]) {
    if (spec_is_disabled(spec)) {
        return true;
    }
    uint8_t behavior = spec[0] >> 4;
    return behavior == 0x08 || behavior == 0x09;
}

static void detect_button_layout(Profile *profile) {
    profile->button_offset = 0;
    profile->valid_specs = 0;
    profile->known_specs = 0;
    profile->layout_supported = false;
    size_t count = profile->info.button_count;
    size_t expected = profile->info.profile_format >= 6 ? 48 : 32;
    size_t candidates[2] = {expected, expected == 32 ? 48 : 32};
    for (size_t c = 0; c < 2; c++) {
        size_t offset = candidates[c];
        if (offset + count * 4 > profile->data_length - 2) {
            continue;
        }
        size_t valid = 0;
        size_t known = 0;
        for (size_t i = 0; i < count; i++) {
            const uint8_t *spec = profile->data + offset + i * 4;
            valid += spec_structurally_valid(spec) ? 1 : 0;
            known += spec_known(spec) ? 1 : 0;
        }
        if (valid >= count - 1 && known >= 1) {
            profile->button_offset = offset;
            profile->valid_specs = valid;
            profile->known_specs = known;
            profile->layout_supported = c == 0;
            return;
        }
    }

    // Diagnostic-only scan. It helps explain a new device format in a dump,
    // but it is deliberately not enough to authorize a write.
    size_t best_offset = 0;
    size_t best_valid = 0;
    size_t best_known = 0;
    size_t best_count = 0;
    for (size_t offset = 0; offset + count * 4 <= profile->data_length - 2; offset++) {
        size_t valid = 0;
        size_t known = 0;
        for (size_t i = 0; i < count; i++) {
            const uint8_t *spec = profile->data + offset + i * 4;
            valid += spec_structurally_valid(spec) ? 1 : 0;
            known += spec_known(spec) ? 1 : 0;
        }
        if (known > best_known || (known == best_known && valid > best_valid)) {
            best_offset = offset;
            best_valid = valid;
            best_known = known;
            best_count = 1;
        } else if (known == best_known && valid == best_valid) {
            best_count++;
        }
    }
    if (best_count == 1 && best_valid >= count - 1 && best_known >= 1) {
        profile->button_offset = best_offset;
        profile->valid_specs = best_valid;
        profile->known_specs = best_known;
    }
}

static uint16_t read_le16(const uint8_t *bytes) {
    return (uint16_t)((uint16_t)bytes[0] | ((uint16_t)bytes[1] << 8));
}

static void write_le16(uint8_t *bytes, uint16_t value) {
    bytes[0] = (uint8_t)(value & 0xFF);
    bytes[1] = (uint8_t)(value >> 8);
}

static void detect_dpi_layout(Profile *profile) {
    profile->dpi_offset = 0;
    profile->dpi_count = 0;
    profile->dpi_default_index = 0;
    profile->dpi_shift_index = 0;
    profile->dpi_layout_supported = false;

    // Known format-4 sectors store one to five little-endian DPI stages at
    // offsets 3..12; unused stage slots are 0xFFFF. Bytes 1 and 2 select the
    // default and shift stages. Treat this as a validated format candidate,
    // never as a universal offset.
    if (profile->info.profile_format > 5 || profile->data_length < 15 ||
        profile->data_length - 2 < 13) {
        return;
    }
    uint16_t previous = 0;
    size_t count = 0;
    bool inactive = false;
    for (size_t i = 0; i < 5; i++) {
        uint16_t dpi = read_le16(profile->data + 3 + i * 2);
        if (dpi == UINT16_MAX) {
            inactive = true;
            continue;
        }
        if (inactive || dpi < 100 || (i > 0 && dpi <= previous)) {
            return;
        }
        previous = dpi;
        count++;
    }
    if (count == 0 || profile->data[1] >= count || profile->data[2] >= count) {
        return;
    }
    profile->dpi_offset = 3;
    profile->dpi_count = count;
    profile->dpi_default_index = profile->data[1];
    profile->dpi_shift_index = profile->data[2];
    profile->dpi_layout_supported = true;
}

static int adjustable_dpi_values(Device *device,
                                 uint16_t *values,
                                 size_t *value_count,
                                 size_t value_capacity,
                                 uint8_t *sensor_count_out,
                                 uint16_t *current_out) {
    if (!device_feature_index(device, FEATURE_ADJUSTABLE_DPI, &(uint8_t){0})) {
        return 0;
    }
    const uint8_t empty_params[3] = {0, 0, 0};
    Reply reply = device_call_long(device, FEATURE_ADJUSTABLE_DPI, 0x00,
                                   empty_params, sizeof(empty_params), 2.0);
    if (reply.status != REPLY_OK || reply.length < 1) {
        print_reply_error("ADJUSTABLE_DPI.getSensorCount", reply);
        return 0;
    }
    uint8_t sensor_count = reply.bytes[0];

    const uint8_t sensor_params[3] = {0, 0, 0};
    reply = device_call_long(device, FEATURE_ADJUSTABLE_DPI, 0x10,
                             sensor_params, sizeof(sensor_params), 2.0);
    if (reply.status != REPLY_OK || reply.length < 3) {
        print_reply_error("ADJUSTABLE_DPI.getSensorDpiList", reply);
        return 0;
    }
    size_t count = 0;
    uint16_t raw[8];
    size_t raw_count = 0;
    for (size_t offset = 1; offset + 1 < reply.length && raw_count < sizeof(raw) / sizeof(raw[0]); offset += 2) {
        uint16_t value = (uint16_t)(((uint16_t)reply.bytes[offset] << 8) | reply.bytes[offset + 1]);
        if (value == 0) {
            break;
        }
        raw[raw_count++] = value;
    }
    for (size_t i = 0; i < raw_count; i++) {
        uint16_t value = raw[i];
        if ((value >> 13) == 0x07) {
            if (count == 0 || i + 1 >= raw_count) {
                return 0;
            }
            uint16_t step = value & 0x1FFF;
            uint16_t end = raw[++i];
            if (step == 0 || end < values[count - 1]) {
                return 0;
            }
            uint32_t next = (uint32_t)values[count - 1] + step;
            while (next <= end) {
                if (count >= value_capacity) {
                    return 0;
                }
                values[count++] = (uint16_t)next;
                next += step;
            }
            if (count == 0 || values[count - 1] != end) {
                if (count >= value_capacity) {
                    return 0;
                }
                values[count++] = end;
            }
        } else {
            if (count >= value_capacity) {
                return 0;
            }
            values[count++] = value;
        }
    }
    if (count == 0) {
        return 0;
    }
    *value_count = count;
    if (sensor_count_out != NULL) {
        // A few gaming-mouse firmware revisions report zero from getSensorCount
        // while still exposing a valid sensor-0 DPI list. Treat a successful
        // sensor-0 list as one sensor; never infer additional sensors.
        *sensor_count_out = sensor_count == 0 ? 1 : sensor_count;
    }
    if (current_out != NULL) {
        reply = device_call_long(device, FEATURE_ADJUSTABLE_DPI, 0x20,
                                 sensor_params, sizeof(sensor_params), 2.0);
        if (reply.status != REPLY_OK || reply.length < 3) {
            print_reply_error("ADJUSTABLE_DPI.getSensorDpi", reply);
            return 0;
        }
        *current_out = (uint16_t)(((uint16_t)reply.bytes[1] << 8) | reply.bytes[2]);
    }
    return 1;
}

static int load_profile_with_headers(Device *device,
                                     const ProfileInfo *info,
                                     const ProfileHeader *headers,
                                     size_t header_count,
                                     int requested_profile,
                                     Profile *profile) {
    memset(profile, 0, sizeof(*profile));
    profile->info = *info;
    profile->header_count = header_count;
    if (header_count > MAX_HEADERS) {
        return 0;
    }
    memcpy(profile->headers, headers, header_count * sizeof(*headers));
    size_t selected = 0;
    if (requested_profile > 0) {
        if ((size_t)requested_profile > header_count) {
            fprintf(stderr, "profile %d is out of range 1..%zu\n", requested_profile, header_count);
            return 0;
        }
        selected = (size_t)requested_profile - 1;
    } else {
        bool found_enabled = false;
        for (size_t i = 0; i < header_count; i++) {
            if (headers[i].enabled != 0) {
                selected = i;
                found_enabled = true;
                break;
            }
        }
        if (!found_enabled) {
            selected = 0;
        }
    }
    profile->selected_header = selected;
    profile->data_length = info->sector_size;
    profile->data = (uint8_t *)malloc(profile->data_length);
    if (profile->data == NULL) {
        return 0;
    }
    if (!read_sector(device, headers[selected].sector, profile->data_length, profile->data)) {
        free(profile->data);
        profile->data = NULL;
        return 0;
    }
    profile->crc_ok = sector_crc_ok(profile->data, profile->data_length);
    detect_button_layout(profile);
    detect_dpi_layout(profile);
    return 1;
}

static int load_selected_profile(Device *device, int requested_profile, Profile *profile) {
    ProfileInfo info;
    if (!get_profile_info(device, &info)) {
        return 0;
    }
    ProfileHeader headers[MAX_HEADERS];
    size_t header_count = 0;
    if (!read_profile_headers(device, &info, headers, &header_count)) {
        fprintf(stderr, "could not find any onboard profile headers\n");
        return 0;
    }
    return load_profile_with_headers(device, &info, headers, header_count, requested_profile, profile);
}

static const char *function_name(uint8_t value) {
    static const char *names[] = {
        "no action", "tilt left", "tilt right", "next DPI", "previous DPI",
        "cycle DPI", "default DPI", "shift DPI", "next profile", "previous profile",
        "cycle profile", "G-shift", "battery status", "profile select", "mode switch",
        "host button", "scroll down", "scroll up",
    };
    return value <= 0x11 ? names[value] : "unknown function";
}

static const char *key_name(uint8_t code) {
    switch (code) {
        case 0x04: return "A";
        case 0x05: return "B";
        case 0x06: return "C";
        case 0x07: return "D";
        case 0x08: return "E";
        case 0x09: return "F";
        case 0x0A: return "G";
        case 0x0B: return "H";
        case 0x0C: return "I";
        case 0x0D: return "J";
        case 0x0E: return "K";
        case 0x0F: return "L";
        case 0x10: return "M";
        case 0x11: return "N";
        case 0x12: return "O";
        case 0x13: return "P";
        case 0x14: return "Q";
        case 0x15: return "R";
        case 0x16: return "S";
        case 0x17: return "T";
        case 0x18: return "U";
        case 0x19: return "V";
        case 0x1C: return "Y";
        case 0x1D: return "Z";
        case 0x28: return "Enter";
        case 0x29: return "Escape";
        case 0x2B: return "Tab";
        case 0x2C: return "Space";
        case 0x2F: return "[";
        case 0x30: return "]";
        case 0x3A: return "F1";
        case 0x3B: return "F2";
        case 0x3C: return "F3";
        case 0x3D: return "F4";
        case 0x3E: return "F5";
        case 0x3F: return "F6";
        case 0x40: return "F7";
        case 0x41: return "F8";
        case 0x42: return "F9";
        case 0x43: return "F10";
        case 0x44: return "F11";
        case 0x45: return "F12";
        case 0x68: return "F13";
        case 0x69: return "F14";
        case 0x6A: return "F15";
        case 0x6B: return "F16";
        case 0x6C: return "F17";
        case 0x6D: return "F18";
        case 0x6E: return "F19";
        case 0x6F: return "F20";
        case 0x70: return "F21";
        case 0x71: return "F22";
        case 0x72: return "F23";
        case 0x73: return "F24";
        default: return "unknown key";
    }
}

static void describe_spec(const uint8_t spec[4], char *out, size_t out_size) {
    if (spec_is_disabled(spec)) {
        snprintf(out, out_size, "disabled");
        return;
    }
    uint8_t behavior = spec[0] >> 4;
    if (behavior == 0x08) {
        if (spec[1] == 0x00) {
            snprintf(out, out_size, "no action");
        } else if (spec[1] == 0x01) {
            uint16_t mask = (uint16_t)(((uint16_t)spec[2] << 8) | spec[3]);
            const char *name = "mouse mask";
            switch (mask) {
                case 0x0001: name = "Left click"; break;
                case 0x0002: name = "Right click"; break;
                case 0x0004: name = "Middle click"; break;
                case 0x0008: name = "Back / rear thumb"; break;
                case 0x0010: name = "Forward"; break;
                case 0x0020: name = "Button 6"; break;
                case 0x0040: name = "Button 7"; break;
                case 0x0080: name = "Button 8"; break;
                default: break;
            }
            snprintf(out, out_size, "%s (mask 0x%04X)", name, mask);
        } else if (spec[1] == 0x02) {
            const char *modifier = "no modifier";
            if (spec[2] == 0x04) modifier = "Left Alt";
            else if (spec[2] == 0x01) modifier = "Left Ctrl";
            else if (spec[2] == 0x02) modifier = "Left Shift";
            else if (spec[2] == 0x08) modifier = "Left Command/GUI";
            else if (spec[2] != 0) modifier = "modifier bitmap";
            snprintf(out, out_size, "%s + %s (mod 0x%02X key 0x%02X)",
                     modifier, key_name(spec[3]), spec[2], spec[3]);
        } else if (spec[1] == 0x03) {
            uint16_t code = (uint16_t)(((uint16_t)spec[2] << 8) | spec[3]);
            snprintf(out, out_size, "consumer usage 0x%04X", code);
        } else {
            snprintf(out, out_size, "SEND type 0x%02X", spec[1]);
        }
        return;
    }
    if (behavior == 0x09) {
        snprintf(out, out_size, "%s", function_name(spec[1]));
        return;
    }
    if (behavior <= 0x02) {
        snprintf(out, out_size, "macro record (behavior 0x%X)", behavior);
        return;
    }
    snprintf(out, out_size, "unrecognized raw spec");
}

static bool spec_is_back(const uint8_t spec[4]) {
    return spec[0] == 0x80 && spec[1] == 0x01 && spec[2] == 0x00 && spec[3] == 0x08;
}

static void print_hex4(const uint8_t bytes[4]) {
    printf("%02X %02X %02X %02X", bytes[0], bytes[1], bytes[2], bytes[3]);
}

static void print_profile_summary(const Profile *profile, bool show_buttons) {
    printf("Profile %zu (sector 0x%04X, enabled=%s)\n",
           profile->selected_header + 1,
           profile->headers[profile->selected_header].sector,
           profile->headers[profile->selected_header].enabled ? "yes" : "no");
    printf("  format: 0x%02X, macro format: 0x%02X, profiles: %u, buttons: %u, sectors: %u, sector bytes: %u\n",
           profile->info.profile_format,
           profile->info.macro_format,
           profile->info.profile_count,
           profile->info.button_count,
           profile->info.sector_count,
           profile->info.sector_size);
    printf("  CRC: %s\n", profile->crc_ok ? "OK" : "INVALID");
    if (profile->dpi_layout_supported) {
        printf("  DPI stages: ");
        for (size_t i = 0; i < profile->dpi_count; i++) {
            if (i != 0) {
                printf(", ");
            }
            printf("%u", read_le16(profile->data + profile->dpi_offset + i * 2));
        }
        printf(" (default %u, shift %u)\n",
               profile->dpi_default_index + 1,
               profile->dpi_shift_index + 1);
    } else {
        printf("  DPI stages: not recognized; stage editing is disabled\n");
    }
    if (profile->button_offset != 0 || profile->layout_supported) {
        printf("  button array: offset %zu (%zu/%u structurally valid, %zu recognized)\n",
               profile->button_offset,
               profile->valid_specs,
               profile->info.button_count,
               profile->known_specs);
        if (!profile->layout_supported) {
            printf("  write safety: layout was only found diagnostically; writes are disabled\n");
        }
    } else {
        printf("  button array: not recognized; writes are disabled\n");
    }
    if (!show_buttons || (profile->button_offset == 0 && !profile->layout_supported)) {
        return;
    }
    int back_count = 0;
    int back_button = 0;
    for (size_t i = 0; i < profile->info.button_count; i++) {
        const uint8_t *spec = profile->data + profile->button_offset + i * 4;
        char description[160];
        describe_spec(spec, description, sizeof(description));
        printf("  button %zu: %-30s [", i + 1, description);
        print_hex4(spec);
        printf("]\n");
        if (spec_is_back(spec)) {
            back_count++;
            back_button = (int)i + 1;
        }
    }
    if (back_count == 1) {
        printf("  rear thumb mapping: profile button %d (unambiguous Back record)\n", back_button);
    } else if (back_count == 0) {
        printf("  rear thumb mapping: no current Back record; use watch and an explicit --button number\n");
    } else {
        printf("  rear thumb mapping: %d Back records; refusing to guess\n", back_count);
    }
}

static int find_rear_thumb_button(const Profile *profile) {
    if (!profile->layout_supported || !profile->crc_ok) {
        return 0;
    }
    int found = 0;
    for (size_t i = 0; i < profile->info.button_count; i++) {
        if (spec_is_back(profile->data + profile->button_offset + i * 4)) {
            if (found != 0) {
                return 0;
            }
            found = (int)i + 1;
        }
    }
    return found;
}

static void print_feature_list(const Device *device) {
    printf("  features: %zu\n", device->feature_count);
    for (size_t i = 0; i < device->feature_count; i++) {
        printf("    index %3u: 0x%04X v%u\n",
               device->features[i].index,
               device->features[i].id,
               device->features[i].version);
    }
}

static void print_device_line(const Device *device, size_t index) {
    printf("[%zu] %s  %s  (HID++ %.1f, product 0x%04X)\n",
           index, device_connection(device), device_label(device),
           device->protocol, device->iface->product_id);
}

static int write_all(int fd, const uint8_t *bytes, size_t length) {
    size_t written = 0;
    while (written < length) {
        ssize_t n = write(fd, bytes + written, length - written);
        if (n < 0 && errno == EINTR) {
            continue;
        }
        if (n <= 0) {
            return 0;
        }
        written += (size_t)n;
    }
    return 1;
}

static int read_all(int fd, uint8_t *bytes, size_t length) {
    size_t read_bytes = 0;
    while (read_bytes < length) {
        ssize_t n = read(fd, bytes + read_bytes, length - read_bytes);
        if (n < 0 && errno == EINTR) {
            continue;
        }
        if (n <= 0) {
            return 0;
        }
        read_bytes += (size_t)n;
    }
    return 1;
}

static void put_be16(uint8_t *bytes, uint16_t value) {
    bytes[0] = (uint8_t)(value >> 8);
    bytes[1] = (uint8_t)(value & 0xFF);
}

static uint16_t get_be16(const uint8_t *bytes) {
    return (uint16_t)(((uint16_t)bytes[0] << 8) | bytes[1]);
}

static int package_write(const char *path,
                         const Device *device,
                         const Profile *profile,
                         const uint8_t *data,
                         bool refuse_overwrite) {
    uint8_t header[BACKUP_HEADER_BYTES];
    memset(header, 0, sizeof(header));
    memcpy(header, BACKUP_MAGIC, 8);
    header[8] = 1;
    put_be16(header + 10, (uint16_t)device->iface->vendor_id);
    put_be16(header + 12, (uint16_t)device->iface->product_id);
    header[14] = device->device_number;
    header[15] = profile->info.profile_format;
    put_be16(header + 16, profile->headers[profile->selected_header].sector);
    put_be16(header + 18, (uint16_t)profile->data_length);

    int flags = O_WRONLY | O_CREAT | (refuse_overwrite ? O_EXCL : O_TRUNC);
    int fd = open(path, flags, 0600);
    if (fd < 0) {
        fprintf(stderr, "could not create %s: %s\n", path, strerror(errno));
        return 0;
    }
    int ok = write_all(fd, header, sizeof(header)) && write_all(fd, data, profile->data_length);
    if (close(fd) != 0) {
        ok = 0;
    }
    if (!ok) {
        fprintf(stderr, "could not finish writing %s: %s\n", path, strerror(errno));
        return 0;
    }
    return 1;
}

static int package_read(const char *path, BackupPackage *package) {
    memset(package, 0, sizeof(*package));
    int fd = open(path, O_RDONLY);
    if (fd < 0) {
        fprintf(stderr, "could not open backup %s: %s\n", path, strerror(errno));
        return 0;
    }
    uint8_t header[BACKUP_HEADER_BYTES];
    if (!read_all(fd, header, sizeof(header))) {
        fprintf(stderr, "backup %s is shorter than its header\n", path);
        close(fd);
        return 0;
    }
    if (memcmp(header, BACKUP_MAGIC, 8) != 0 || header[8] != 1) {
        fprintf(stderr, "backup %s is not a recognized Logitech onboard package\n", path);
        close(fd);
        return 0;
    }
    package->vendor_id = get_be16(header + 10);
    package->product_id = get_be16(header + 12);
    package->device_number = header[14];
    package->profile_format = header[15];
    package->sector = get_be16(header + 16);
    package->size = get_be16(header + 18);
    if (package->vendor_id != LOGITECH_VID || package->size < 32 || package->size > MAX_SECTOR_BYTES) {
        fprintf(stderr, "backup %s has invalid device or sector metadata\n", path);
        close(fd);
        return 0;
    }
    struct stat st;
    if (fstat(fd, &st) != 0 || st.st_size != (off_t)BACKUP_HEADER_BYTES + package->size) {
        fprintf(stderr, "backup %s has an unexpected file length\n", path);
        close(fd);
        return 0;
    }
    package->data = (uint8_t *)malloc(package->size);
    if (package->data == NULL || !read_all(fd, package->data, package->size)) {
        fprintf(stderr, "could not read backup data from %s\n", path);
        free(package->data);
        package->data = NULL;
        close(fd);
        return 0;
    }
    close(fd);
    if (!sector_crc_ok(package->data, package->size)) {
        fprintf(stderr, "backup %s has an invalid sector CRC\n", path);
        free(package->data);
        package->data = NULL;
        return 0;
    }
    return 1;
}

static void package_release(BackupPackage *package) {
    if (package != NULL) {
        free(package->data);
        memset(package, 0, sizeof(*package));
    }
}

static void default_backup_path(char *path, size_t path_size, const char *prefix) {
    time_t now = time(NULL);
    struct tm local_time;
    localtime_r(&now, &local_time);
    char stamp[64];
    strftime(stamp, sizeof(stamp), "%Y%m%d-%H%M%S", &local_time);
    snprintf(path, path_size, "%s-%s-%ld.bin", prefix, stamp, (long)getpid());
}

static int ensure_write_confirmation(const char *operation) {
    fprintf(stderr, "%s is preview-only by default. Add --yes after reviewing the output to permit the mouse write.\n",
            operation);
    return 0;
}

static int validate_profile_for_write(const Profile *profile) {
    if (!profile->crc_ok) {
        fprintf(stderr, "refusing to write: the current profile sector CRC is invalid\n");
        return 0;
    }
    if (!profile->layout_supported) {
        fprintf(stderr, "refusing to write: the reported profile format/layout was not validated\n");
        return 0;
    }
    if (profile->button_offset + (size_t)profile->info.button_count * 4 > profile->data_length - 2) {
        fprintf(stderr, "refusing to write: validated button array would exceed the sector\n");
        return 0;
    }
    if (profile->valid_specs < profile->info.button_count - 1) {
        fprintf(stderr, "refusing to write: too many unrecognized button records\n");
        return 0;
    }
    return 1;
}

static int run_list(void) {
    HidContext context;
    if (!hid_context_create(&context)) {
        return 1;
    }
    Device devices[MAX_DEVICES];
    size_t count = 0;
    discover_devices(&context, -1, devices, &count);
    size_t vendor_interfaces = 0;
    for (size_t i = 0; i < context.count; i++) {
        if (context.items[i].is_vendor) {
            vendor_interfaces++;
        }
    }
    printf("Logitech HID++ vendor interfaces: %zu\n", vendor_interfaces);
    size_t mouse_count = 0;
    for (size_t i = 0; i < count; i++) {
        if (!is_mouse_device(&devices[i])) {
            continue;
        }
        print_device_line(&devices[i], i);
        mouse_count++;
    }
    if (mouse_count == 0) {
        printf("No reachable Logitech mouse devices found.\n");
    }
    hid_context_release(&context);
    return 0;
}

static int select_device(Device *devices, size_t count, const Options *options, Device **selected) {
    if (count == 0) {
        fprintf(stderr, "no reachable Logitech HID++ device found\n");
        return 0;
    }
    if (options->device_index >= 0) {
        if ((size_t)options->device_index >= count) {
            fprintf(stderr, "device index %d is out of range 0..%zu\n", options->device_index, count - 1);
            return 0;
        }
        *selected = &devices[options->device_index];
        return 1;
    }
    for (size_t i = 0; i < count; i++) {
        if (devices[i].device_number != 0xFF && devices[i].protocol >= 2.0) {
            *selected = &devices[i];
            return 1;
        }
    }
    *selected = &devices[0];
    return 1;
}

static int run_info(const Options *options) {
    HidContext context;
    if (!hid_context_create(&context)) {
        return 1;
    }
    Device devices[MAX_DEVICES];
    size_t count = 0;
    discover_devices(&context, options->slot, devices, &count);
    Device *device = NULL;
    if (!select_device(devices, count, options, &device)) {
        hid_context_release(&context);
        return 1;
    }
    printf("Device: %s\n", device_label(device));
    printf("  vendor/product: 0x%04X / 0x%04X\n", device->iface->vendor_id, device->iface->product_id);
    printf("  connection: %s, device number: 0x%02X\n",
           device->device_number == 0xFF ? "direct or receiver" : "receiver",
           device->device_number);
    printf("  HID++ protocol: %.1f\n", device->protocol);
    print_feature_list(device);

    ProfileInfo profile_info;
    if (!device_feature_index(device, FEATURE_ONBOARD_PROFILES, &(uint8_t){0}) ||
        !get_profile_info(device, &profile_info)) {
        printf("  onboard profiles: unavailable (feature 0x8100 not usable)\n");
        hid_context_release(&context);
        return 0;
    }
    printf("  onboard descriptor: memory 0x%02X, format 0x%02X, macro format 0x%02X, shift flags 0x%02X\n",
           profile_info.memory, profile_info.profile_format, profile_info.macro_format, profile_info.shift_flags);
    printf("  onboard counts: profiles %u, buttons %u, sectors %u, sector size %u bytes\n",
           profile_info.profile_count, profile_info.button_count, profile_info.sector_count, profile_info.sector_size);
    ProfileHeader headers[MAX_HEADERS];
    size_t header_count = 0;
    if (read_profile_headers(device, &profile_info, headers, &header_count)) {
        printf("  profile headers:\n");
        for (size_t i = 0; i < header_count; i++) {
            printf("    profile %zu: sector 0x%04X, enabled=%s\n",
                   i + 1, headers[i].sector, headers[i].enabled ? "yes" : "no");
        }
        Profile profile;
        if (load_profile_with_headers(device, &profile_info, headers, header_count, options->profile, &profile)) {
            printf("  selected profile:\n");
            print_profile_summary(&profile, true);
            free(profile.data);
        }
    } else {
        printf("  profile headers: unavailable\n");
    }
    hid_context_release(&context);
    return 0;
}

static int run_profiles(const Options *options) {
    HidContext context;
    if (!hid_context_create(&context)) {
        return 1;
    }
    Device devices[MAX_DEVICES];
    size_t count = 0;
    discover_devices(&context, options->slot, devices, &count);
    Device *device = NULL;
    if (!select_device(devices, count, options, &device)) {
        hid_context_release(&context);
        return 1;
    }
    ProfileInfo info;
    if (!get_profile_info(device, &info)) {
        hid_context_release(&context);
        return 1;
    }
    ProfileHeader headers[MAX_HEADERS];
    size_t header_count = 0;
    if (!read_profile_headers(device, &info, headers, &header_count)) {
        fprintf(stderr, "could not find onboard profile headers\n");
        hid_context_release(&context);
        return 1;
    }
    size_t first = 0;
    size_t last = header_count;
    if (options->profile > 0) {
        if ((size_t)options->profile > header_count) {
            fprintf(stderr, "profile %d is out of range 1..%zu\n", options->profile, header_count);
            hid_context_release(&context);
            return 1;
        }
        first = (size_t)options->profile - 1;
        last = first + 1;
    }
    printf("Onboard profiles for %s:\n", device_label(device));
    for (size_t i = first; i < last; i++) {
        Profile profile;
        if (load_profile_with_headers(device, &info, headers, header_count, (int)i + 1, &profile)) {
            print_profile_summary(&profile, true);
            free(profile.data);
        }
    }
    hid_context_release(&context);
    return 0;
}

static void print_supported_dpi(const uint16_t *values, size_t count) {
    printf("Supported DPI: ");
    if (count >= 2) {
        uint16_t step = (uint16_t)(values[1] - values[0]);
        bool regular = step > 0;
        for (size_t i = 2; regular && i < count; i++) {
            regular = (uint16_t)(values[i] - values[i - 1]) == step;
        }
        if (regular) {
            printf("%u..%u (step %u)\n", values[0], values[count - 1], step);
            return;
        }
    }
    for (size_t i = 0; i < count; i++) {
        if (i != 0) {
            printf(", ");
        }
        printf("%u", values[i]);
    }
    printf("\n");
}

static int run_dpi(const Options *options) {
    HidContext context;
    if (!hid_context_create(&context)) {
        return 1;
    }
    Device devices[MAX_DEVICES];
    size_t count = 0;
    discover_devices(&context, options->slot, devices, &count);
    Device *device = NULL;
    if (!select_device(devices, count, options, &device)) {
        hid_context_release(&context);
        return 1;
    }
    uint16_t values[MAX_DPI_VALUES];
    size_t value_count = 0;
    uint8_t sensor_count = 0;
    uint16_t current = 0;
    if (!adjustable_dpi_values(device, values, &value_count, MAX_DPI_VALUES, &sensor_count, &current)) {
        fprintf(stderr, "adjustable DPI feature 0x2201 is unavailable or unreadable\n");
        hid_context_release(&context);
        return 1;
    }
    printf("Device: %s\n", device_label(device));
    printf("DPI sensors: %u\n", sensor_count);
    print_supported_dpi(values, value_count);
    printf("Current sensor 1 DPI: %u\n", current);

    Profile profile;
    if (load_selected_profile(device, options->profile, &profile)) {
        if (profile.dpi_layout_supported) {
            printf("Onboard profile %zu DPI stages: ", profile.selected_header + 1);
            for (size_t i = 0; i < profile.dpi_count; i++) {
                if (i != 0) {
                    printf(", ");
                }
                printf("%u", read_le16(profile.data + profile.dpi_offset + i * 2));
            }
            printf(" (default %u, shift %u)\n",
                   profile.dpi_default_index + 1,
                   profile.dpi_shift_index + 1);
        } else {
            printf("Onboard profile DPI layout: not recognized; stage editing is disabled\n");
        }
        free(profile.data);
    }
    hid_context_release(&context);
    return 0;
}

static int parse_dpi_values(const char *text, uint16_t values[5], size_t *count_out) {
    if (text == NULL) {
        return 0;
    }
    char copy[256];
    if (strlen(text) >= sizeof(copy)) {
        return 0;
    }
    strcpy(copy, text);
    char *save = NULL;
    char *part = strtok_r(copy, ",", &save);
    size_t count = 0;
    while (part != NULL && count < 5) {
        errno = 0;
        char *end = NULL;
        unsigned long value = strtoul(part, &end, 10);
        while (end != NULL && *end == ' ') {
            end++;
        }
        if (errno != 0 || end == part || *end != '\0' || value < 100 || value > UINT16_MAX) {
            return 0;
        }
        values[count++] = (uint16_t)value;
        part = strtok_r(NULL, ",", &save);
    }
    if (count == 0 || part != NULL) {
        return 0;
    }
    if (count_out != NULL) {
        *count_out = count;
    }
    return 1;
}

static bool dpi_value_in_list(const uint16_t *values, size_t count, uint16_t wanted) {
    for (size_t i = 0; i < count; i++) {
        if (values[i] == wanted) {
            return true;
        }
    }
    return false;
}

static int run_set_dpi(const Options *options) {
    if (options->positional_count != 1) {
        fprintf(stderr, "set-dpi requires one to five comma-separated values, e.g. 800,1600\n");
        return 1;
    }
    uint16_t requested[5];
    size_t requested_count = 0;
    if (!parse_dpi_values(options->positionals[0], requested, &requested_count)) {
        fprintf(stderr, "invalid DPI list; use one to five comma-separated values from 100 to 65535\n");
        return 1;
    }

    HidContext context;
    if (!hid_context_create(&context)) {
        return 1;
    }
    Device devices[MAX_DEVICES];
    size_t count = 0;
    discover_devices(&context, options->slot, devices, &count);
    Device *device = NULL;
    if (!select_device(devices, count, options, &device)) {
        hid_context_release(&context);
        return 1;
    }
    uint16_t supported[MAX_DPI_VALUES];
    size_t supported_count = 0;
    uint8_t sensor_count = 0;
    if (!adjustable_dpi_values(device, supported, &supported_count, MAX_DPI_VALUES, &sensor_count, NULL)) {
        fprintf(stderr, "adjustable DPI feature 0x2201 is unavailable or unreadable\n");
        hid_context_release(&context);
        return 1;
    }
    if (sensor_count != 1) {
        fprintf(stderr, "refusing to edit onboard DPI: this device reports %u sensors; only one-sensor layouts are supported\n", sensor_count);
        hid_context_release(&context);
        return 1;
    }
    for (size_t i = 0; i < requested_count; i++) {
        if (!dpi_value_in_list(supported, supported_count, requested[i])) {
            fprintf(stderr, "refusing to edit onboard DPI: %u is not reported as a supported sensor value\n", requested[i]);
            hid_context_release(&context);
            return 1;
        }
        if (i > 0 && requested[i] <= requested[i - 1]) {
            fprintf(stderr, "refusing to edit onboard DPI: stages must be strictly increasing\n");
            hid_context_release(&context);
            return 1;
        }
    }

    Profile profile;
    if (!load_selected_profile(device, options->profile, &profile)) {
        hid_context_release(&context);
        return 1;
    }
    if (options->profile == 0 && profile.header_count > 1) {
        fprintf(stderr, "refusing to choose a profile implicitly: this device has %zu profile slots. Use `--profile N`.\n",
                profile.header_count);
        free(profile.data);
        hid_context_release(&context);
        return 1;
    }
    if (!profile.crc_ok || !profile.dpi_layout_supported) {
        fprintf(stderr, "refusing to write: this profile's CRC or DPI layout was not validated\n");
        free(profile.data);
        hid_context_release(&context);
        return 1;
    }
    int default_index = options->dpi_default >= 0 ? options->dpi_default : profile.dpi_default_index + 1;
    int shift_index = options->dpi_shift >= 0 ? options->dpi_shift : profile.dpi_shift_index + 1;
    if (default_index < 1 || default_index > (int)requested_count ||
        shift_index < 1 || shift_index > (int)requested_count) {
        fprintf(stderr, "DPI indexes must be within the active stage count (1..%zu)\n", requested_count);
        free(profile.data);
        hid_context_release(&context);
        return 1;
    }
    printf("Device: %s, profile %d, sector 0x%04X\n", device_label(device),
           (int)profile.selected_header + 1, profile.headers[profile.selected_header].sector);
    printf("Planned DPI stages: ");
    for (size_t i = 0; i < requested_count; i++) {
        if (i != 0) {
            printf(", ");
        }
        printf("%u", requested[i]);
    }
    printf(" (active %zu of 5, default %d, shift %d)\n",
           requested_count, default_index, shift_index);
    if (!options->yes) {
        free(profile.data);
        hid_context_release(&context);
        return ensure_write_confirmation("set-dpi");
    }

    char backup_path[512];
    if (options->backup_path != NULL) {
        snprintf(backup_path, sizeof(backup_path), "%s", options->backup_path);
    } else {
        default_backup_path(backup_path, sizeof(backup_path), "logitech-onboard-dpi-backup");
    }
    if (!package_write(backup_path, device, &profile, profile.data, true)) {
        free(profile.data);
        hid_context_release(&context);
        return 1;
    }
    printf("Saved the original profile sector to %s\n", backup_path);
    uint8_t *new_data = (uint8_t *)malloc(profile.data_length);
    if (new_data == NULL) {
        fprintf(stderr, "out of memory while preparing the DPI update\n");
        free(profile.data);
        hid_context_release(&context);
        return 1;
    }
    memcpy(new_data, profile.data, profile.data_length);
    for (size_t i = 0; i < requested_count; i++) {
        write_le16(new_data + profile.dpi_offset + i * 2, requested[i]);
    }
    for (size_t i = requested_count; i < 5; i++) {
        write_le16(new_data + profile.dpi_offset + i * 2, UINT16_MAX);
    }
    new_data[1] = (uint8_t)(default_index - 1);
    new_data[2] = (uint8_t)(shift_index - 1);
    sector_put_crc(new_data, profile.data_length);
    bool written = write_sector(device, profile.headers[profile.selected_header].sector,
                                new_data, profile.data_length);
    uint8_t *readback = written ? (uint8_t *)malloc(profile.data_length) : NULL;
    bool verified = readback != NULL && read_sector(device, profile.headers[profile.selected_header].sector,
                                                    profile.data_length, readback) &&
                    sector_crc_ok(readback, profile.data_length) &&
                    memcmp(readback, new_data, profile.data_length) == 0;
    if (!verified) {
        fprintf(stderr, "DPI write/readback verification failed; restore from %s\n", backup_path);
        free(readback);
        free(new_data);
        free(profile.data);
        hid_context_release(&context);
        return 1;
    }
    printf("Verified: DPI profile readback CRC is OK and the complete sector matches.\n");
    free(readback);
    free(new_data);
    free(profile.data);
    hid_context_release(&context);
    return 0;
}

static int run_set_profile_state(const Options *options) {
    if (options->positional_count != 2) {
        fprintf(stderr, "set-profile-state syntax: set-profile-state N enable|disable\n");
        return 1;
    }
    char *end = NULL;
    errno = 0;
    long requested_profile = strtol(options->positionals[0], &end, 10);
    if (errno != 0 || end == options->positionals[0] || *end != '\0' ||
        requested_profile < 1 || requested_profile > MAX_HEADERS) {
        fprintf(stderr, "invalid profile number '%s'\n", options->positionals[0]);
        return 1;
    }
    bool enable = false;
    if (strcmp(options->positionals[1], "enable") == 0) {
        enable = true;
    } else if (strcmp(options->positionals[1], "disable") != 0) {
        fprintf(stderr, "profile state must be enable or disable\n");
        return 1;
    }

    HidContext context;
    if (!hid_context_create(&context)) {
        return 1;
    }
    Device devices[MAX_DEVICES];
    size_t device_count = 0;
    discover_devices(&context, options->slot, devices, &device_count);
    Device *device = NULL;
    if (!select_device(devices, device_count, options, &device)) {
        hid_context_release(&context);
        return 1;
    }

    ProfileInfo info;
    if (!get_profile_info(device, &info)) {
        hid_context_release(&context);
        return 1;
    }
    uint8_t *control = (uint8_t *)malloc(info.sector_size);
    if (control == NULL) {
        fprintf(stderr, "out of memory while reading the profile control sector\n");
        hid_context_release(&context);
        return 1;
    }
    uint16_t control_sector = 0;
    ProfileHeader headers[MAX_HEADERS];
    size_t header_count = 0;
    if (!read_profile_control(device, &info, &control_sector, control) ||
        !sector_crc_ok(control, info.sector_size) ||
        !parse_profile_headers(&info, control, headers, &header_count)) {
        fprintf(stderr, "refusing to edit profile state: the control sector or profile headers were not validated\n");
        free(control);
        hid_context_release(&context);
        return 1;
    }
    if (requested_profile > (long)header_count) {
        fprintf(stderr, "profile %ld is out of range; the device exposes %zu profile slots\n",
                requested_profile, header_count);
        free(control);
        hid_context_release(&context);
        return 1;
    }
    size_t selected = (size_t)requested_profile - 1;
    bool was_enabled = headers[selected].enabled != 0;
    if (was_enabled == enable) {
        printf("Profile %ld is already %s; no control-sector write is needed.\n",
               requested_profile, enable ? "enabled" : "disabled");
        free(control);
        hid_context_release(&context);
        return 0;
    }
    if (!enable) {
        size_t enabled_count = 0;
        for (size_t i = 0; i < header_count; i++) {
            enabled_count += headers[i].enabled != 0 ? 1 : 0;
        }
        if (enabled_count <= 1) {
            fprintf(stderr, "refusing to disable the last enabled onboard profile\n");
            free(control);
            hid_context_release(&context);
            return 1;
        }
    }

    printf("Device: %s, profile %ld, control sector 0x%04X\n",
           device_label(device), requested_profile, control_sector);
    printf("Planned profile state: %s -> %s\n",
           was_enabled ? "enabled" : "disabled", enable ? "enabled" : "disabled");
    char backup_path[512];
    if (options->backup_path != NULL) {
        snprintf(backup_path, sizeof(backup_path), "%s", options->backup_path);
    } else {
        default_backup_path(backup_path, sizeof(backup_path), "logitech-onboard-profile-state-backup");
    }
    printf("Backup: %s\n", backup_path);
    if (!options->yes) {
        free(control);
        hid_context_release(&context);
        return ensure_write_confirmation("set-profile-state");
    }

    Profile control_profile;
    memset(&control_profile, 0, sizeof(control_profile));
    control_profile.info = info;
    control_profile.headers[0].sector = control_sector;
    control_profile.headers[0].enabled = 1;
    control_profile.selected_header = 0;
    control_profile.data = control;
    control_profile.data_length = info.sector_size;
    control_profile.crc_ok = true;
    if (!package_write(backup_path, device, &control_profile, control, true)) {
        free(control);
        hid_context_release(&context);
        return 1;
    }
    printf("Saved the original profile control sector before writing.\n");
    uint8_t *new_control = (uint8_t *)malloc(info.sector_size);
    if (new_control == NULL) {
        fprintf(stderr, "out of memory while preparing the profile-state update\n");
        free(control);
        hid_context_release(&context);
        return 1;
    }
    memcpy(new_control, control, info.sector_size);
    size_t enabled_offset = selected * 4 + 2;
    if (enabled_offset >= info.sector_size - 2) {
        fprintf(stderr, "refusing to write: profile header is outside the validated control sector\n");
        free(new_control);
        free(control);
        hid_context_release(&context);
        return 1;
    }
    new_control[enabled_offset] = enable ? 1 : 0;
    sector_put_crc(new_control, info.sector_size);
    if (!sector_crc_ok(new_control, info.sector_size) ||
        !write_sector(device, control_sector, new_control, info.sector_size)) {
        fprintf(stderr, "profile-state write failed; restore from %s\n", backup_path);
        free(new_control);
        free(control);
        hid_context_release(&context);
        return 1;
    }
    uint8_t *readback = (uint8_t *)malloc(info.sector_size);
    bool verified = readback != NULL && read_sector(device, control_sector, info.sector_size, readback) &&
                    sector_crc_ok(readback, info.sector_size) &&
                    memcmp(readback, new_control, info.sector_size) == 0;
    if (!verified) {
        fprintf(stderr, "profile-state read-back verification failed; restore from %s\n", backup_path);
        free(readback);
        free(new_control);
        free(control);
        hid_context_release(&context);
        return 1;
    }
    printf("Verified: profile control-sector CRC is OK and the complete sector matches.\n");
    free(readback);
    free(new_control);
    free(control);
    hid_context_release(&context);
    return 0;
}

static int run_dump(const Options *options) {
    if (options->path == NULL) {
        fprintf(stderr, "dump requires an output path\n");
        return 1;
    }
    HidContext context;
    if (!hid_context_create(&context)) {
        return 1;
    }
    Device devices[MAX_DEVICES];
    size_t count = 0;
    discover_devices(&context, options->slot, devices, &count);
    Device *device = NULL;
    if (!select_device(devices, count, options, &device)) {
        hid_context_release(&context);
        return 1;
    }
    Profile profile;
    if (!load_selected_profile(device, options->profile, &profile)) {
        hid_context_release(&context);
        return 1;
    }
    if (!profile.crc_ok) {
        fprintf(stderr, "warning: dumping a sector with an invalid CRC; it cannot be used for restore until repaired by the vendor software\n");
    }
    int ok = package_write(options->path, device, &profile, profile.data, false);
    if (ok) {
        printf("dumped profile %zu sector 0x%04X (%zu bytes) to %s\n",
               profile.selected_header + 1,
               profile.headers[profile.selected_header].sector,
               profile.data_length,
               options->path);
    }
    free(profile.data);
    hid_context_release(&context);
    return ok ? 0 : 1;
}

static int parse_hex_byte(const char *text, uint8_t *value) {
    if (text == NULL || *text == '\0') {
        return 0;
    }
    char *end = NULL;
    errno = 0;
    unsigned long number = strtoul(text, &end, 16);
    if (errno != 0 || end == text || *end != '\0' || number > 0xFF) {
        return 0;
    }
    *value = (uint8_t)number;
    return 1;
}

static int parse_hex_word(const char *text, uint16_t *value) {
    if (text == NULL || *text == '\0') {
        return 0;
    }
    char *end = NULL;
    errno = 0;
    unsigned long number = strtoul(text, &end, 16);
    if (errno != 0 || end == text || *end != '\0' || number > 0xFFFF) {
        return 0;
    }
    *value = (uint16_t)number;
    return 1;
}

static int parse_target(const char *target, uint8_t spec[4]) {
    if (target == NULL) {
        return 0;
    }
    char lower[128];
    size_t length = strlen(target);
    if (length >= sizeof(lower)) {
        return 0;
    }
    for (size_t i = 0; i <= length; i++) {
        char c = target[i];
        if (c >= 'A' && c <= 'Z') {
            c = (char)(c - 'A' + 'a');
        }
        lower[i] = c;
    }
    uint16_t mouse_mask = 0;
    if (strcmp(lower, "left") == 0 || strcmp(lower, "left-click") == 0) mouse_mask = 0x0001;
    else if (strcmp(lower, "right") == 0 || strcmp(lower, "right-click") == 0) mouse_mask = 0x0002;
    else if (strcmp(lower, "middle") == 0 || strcmp(lower, "middle-click") == 0) mouse_mask = 0x0004;
    else if (strcmp(lower, "back") == 0) mouse_mask = 0x0008;
    else if (strcmp(lower, "forward") == 0) mouse_mask = 0x0010;
    else if (strcmp(lower, "button6") == 0) mouse_mask = 0x0020;
    else if (strcmp(lower, "button7") == 0) mouse_mask = 0x0040;
    else if (strcmp(lower, "button8") == 0) mouse_mask = 0x0080;
    if (mouse_mask != 0) {
        spec[0] = 0x80; spec[1] = 0x01;
        spec[2] = (uint8_t)(mouse_mask >> 8); spec[3] = (uint8_t)mouse_mask;
        return 1;
    }
    if (strcmp(lower, "alt-tab") == 0 || strcmp(lower, "alt+tab") == 0 || strcmp(lower, "alt_tab") == 0) {
        spec[0] = 0x80; spec[1] = 0x02; spec[2] = 0x04; spec[3] = 0x2B;
        return 1;
    }
    if (strcmp(lower, "dpi-up") == 0 || strcmp(lower, "next-dpi") == 0) {
        spec[0] = 0x90; spec[1] = 0x03; spec[2] = 0x00; spec[3] = 0x00;
        return 1;
    }
    if (strcmp(lower, "dpi-down") == 0 || strcmp(lower, "previous-dpi") == 0) {
        spec[0] = 0x90; spec[1] = 0x04; spec[2] = 0x00; spec[3] = 0x00;
        return 1;
    }
    if (strcmp(lower, "dpi-cycle") == 0 || strcmp(lower, "cycle-dpi") == 0) {
        spec[0] = 0x90; spec[1] = 0x05; spec[2] = 0x00; spec[3] = 0x00;
        return 1;
    }
    if (strcmp(lower, "dpi-default") == 0) {
        spec[0] = 0x90; spec[1] = 0x06; spec[2] = 0x00; spec[3] = 0x00;
        return 1;
    }
    if (strcmp(lower, "dpi-shift") == 0) {
        spec[0] = 0x90; spec[1] = 0x07; spec[2] = 0x00; spec[3] = 0x00;
        return 1;
    }
    if (strcmp(lower, "next-profile") == 0 || strcmp(lower, "previous-profile") == 0 ||
        strcmp(lower, "cycle-profile") == 0 || strcmp(lower, "g-shift") == 0) {
        uint8_t function = 0x00;
        if (strcmp(lower, "next-profile") == 0) function = 0x08;
        else if (strcmp(lower, "previous-profile") == 0) function = 0x09;
        else if (strcmp(lower, "cycle-profile") == 0) function = 0x0A;
        else function = 0x0B;
        spec[0] = 0x90; spec[1] = function; spec[2] = 0x00; spec[3] = 0x00;
        return 1;
    }
    if (strcmp(lower, "nav-back") == 0 || strcmp(lower, "cmd-[") == 0) {
        spec[0] = 0x80; spec[1] = 0x02; spec[2] = 0x08; spec[3] = 0x2F;
        return 1;
    }
    if (strcmp(lower, "nav-forward") == 0 || strcmp(lower, "cmd-]") == 0) {
        spec[0] = 0x80; spec[1] = 0x02; spec[2] = 0x08; spec[3] = 0x30;
        return 1;
    }
    if (strcmp(lower, "disable") == 0 || strcmp(lower, "none") == 0 || strcmp(lower, "off") == 0) {
        memset(spec, 0xFF, 4);
        return 1;
    }
    if (strncmp(lower, "key:", 4) == 0) {
        const char *colon = strchr(lower + 4, ':');
        if (colon == NULL) {
            return 0;
        }
        char modifier_text[16];
        char key_text[16];
        size_t modifier_length = (size_t)(colon - (lower + 4));
        if (modifier_length == 0 || modifier_length >= sizeof(modifier_text) || strlen(colon + 1) >= sizeof(key_text)) {
            return 0;
        }
        memcpy(modifier_text, lower + 4, modifier_length);
        modifier_text[modifier_length] = '\0';
        strcpy(key_text, colon + 1);
        uint8_t modifier = 0;
        uint8_t key = 0;
        if (!parse_hex_byte(modifier_text, &modifier) || !parse_hex_byte(key_text, &key)) {
            return 0;
        }
        spec[0] = 0x80; spec[1] = 0x02; spec[2] = modifier; spec[3] = key;
        return 1;
    }
    if (strncmp(lower, "consumer:", 9) == 0) {
        uint16_t consumer = 0;
        if (!parse_hex_word(lower + 9, &consumer)) {
            return 0;
        }
        spec[0] = 0x80; spec[1] = 0x03;
        spec[2] = (uint8_t)(consumer >> 8); spec[3] = (uint8_t)consumer;
        return 1;
    }
    if (strlen(lower) == 8) {
        for (int i = 0; i < 4; i++) {
            char pair[3] = {lower[i * 2], lower[i * 2 + 1], '\0'};
            if (!parse_hex_byte(pair, &spec[i])) {
                return 0;
            }
        }
        return 1;
    }
    return 0;
}

static int run_bind(const Options *options) {
    if (options->target == NULL) {
        fprintf(stderr, "bind requires a target such as alt-tab or key:04:2B\n");
        return 1;
    }
    uint8_t requested_spec[4];
    if (!parse_target(options->target, requested_spec)) {
        fprintf(stderr, "unrecognized target '%s'\n", options->target);
        return 1;
    }

    HidContext context;
    if (!hid_context_create(&context)) {
        return 1;
    }
    Device devices[MAX_DEVICES];
    size_t count = 0;
    discover_devices(&context, options->slot, devices, &count);
    Device *device = NULL;
    if (!select_device(devices, count, options, &device)) {
        hid_context_release(&context);
        return 1;
    }
    Profile profile;
    if (!load_selected_profile(device, options->profile, &profile)) {
        hid_context_release(&context);
        return 1;
    }
    if (options->profile == 0 && profile.header_count > 1) {
        fprintf(stderr, "refusing to choose a profile implicitly: this device has %zu profile slots. Use `--profile N` after reviewing `profiles`.\n",
                profile.header_count);
        free(profile.data);
        hid_context_release(&context);
        return 1;
    }
    if (!validate_profile_for_write(&profile)) {
        free(profile.data);
        hid_context_release(&context);
        return 1;
    }
    int button = options->button;
    if (button == 0) {
        button = find_rear_thumb_button(&profile);
        if (button == 0) {
            fprintf(stderr, "could not identify one rear-thumb profile record. Run `profiles` and `watch`, then use `--button N`.\n");
            free(profile.data);
            hid_context_release(&context);
            return 1;
        }
    }
    if (button < 1 || button > profile.info.button_count) {
        fprintf(stderr, "button %d is out of range 1..%u\n", button, profile.info.button_count);
        free(profile.data);
        hid_context_release(&context);
        return 1;
    }
    size_t offset = profile.button_offset + (size_t)(button - 1) * 4;
    uint8_t old_spec[4];
    memcpy(old_spec, profile.data + offset, 4);
    char old_description[160];
    char new_description[160];
    describe_spec(old_spec, old_description, sizeof(old_description));
    describe_spec(requested_spec, new_description, sizeof(new_description));
    printf("Device: %s, profile %d, sector 0x%04X\n", device_label(device), (int)profile.selected_header + 1,
           profile.headers[profile.selected_header].sector);
    printf("Planned change: button %d: %s -> %s\n", button, old_description, new_description);
    printf("Raw change: ");
    print_hex4(old_spec);
    printf(" -> ");
    print_hex4(requested_spec);
    printf("\n");
    if (memcmp(old_spec, requested_spec, 4) == 0) {
        printf("Nothing to do; the requested binding is already present.\n");
        free(profile.data);
        hid_context_release(&context);
        return 0;
    }
    char backup_path[512];
    if (options->backup_path != NULL) {
        snprintf(backup_path, sizeof(backup_path), "%s", options->backup_path);
    } else {
        default_backup_path(backup_path, sizeof(backup_path), "logitech-onboard-backup");
    }
    printf("Backup: %s\n", backup_path);
    if (!options->yes) {
        free(profile.data);
        hid_context_release(&context);
        return ensure_write_confirmation("bind");
    }
    if (!package_write(backup_path, device, &profile, profile.data, true)) {
        free(profile.data);
        hid_context_release(&context);
        return 1;
    }
    printf("Saved the original sector before writing.\n");

    uint8_t *new_data = (uint8_t *)malloc(profile.data_length);
    if (new_data == NULL) {
        fprintf(stderr, "out of memory while preparing the new sector\n");
        free(profile.data);
        hid_context_release(&context);
        return 1;
    }
    memcpy(new_data, profile.data, profile.data_length);
    memcpy(new_data + offset, requested_spec, 4);
    sector_put_crc(new_data, profile.data_length);
    if (!sector_crc_ok(new_data, profile.data_length)) {
        fprintf(stderr, "internal CRC verification failed; no mouse write was attempted\n");
        free(new_data);
        free(profile.data);
        hid_context_release(&context);
        return 1;
    }
    if (!write_sector(device, profile.headers[profile.selected_header].sector, new_data, profile.data_length)) {
        fprintf(stderr, "write failed; restore from %s if the device reports a partial change\n", backup_path);
        free(new_data);
        free(profile.data);
        hid_context_release(&context);
        return 1;
    }
    uint8_t *readback = (uint8_t *)malloc(profile.data_length);
    if (readback == NULL || !read_sector(device, profile.headers[profile.selected_header].sector,
                                         profile.data_length, readback)) {
        fprintf(stderr, "could not read back the sector; restore from %s\n", backup_path);
        free(readback);
        free(new_data);
        free(profile.data);
        hid_context_release(&context);
        return 1;
    }
    bool verified = sector_crc_ok(readback, profile.data_length) && memcmp(readback, new_data, profile.data_length) == 0;
    if (!verified) {
        fprintf(stderr, "read-back verification failed; restore from %s\n", backup_path);
        free(readback);
        free(new_data);
        free(profile.data);
        hid_context_release(&context);
        return 1;
    }
    printf("Verified: read-back CRC is OK and the complete sector matches.\n");
    printf("The mouse now stores %s on button %d.\n", new_description, button);
    free(readback);
    free(new_data);
    free(profile.data);
    hid_context_release(&context);
    return 0;
}

static int run_restore(const Options *options) {
    if (options->path == NULL) {
        fprintf(stderr, "restore requires a backup package path\n");
        return 1;
    }
    BackupPackage package;
    if (!package_read(options->path, &package)) {
        return 1;
    }
    HidContext context;
    if (!hid_context_create(&context)) {
        package_release(&package);
        return 1;
    }
    Device devices[MAX_DEVICES];
    size_t count = 0;
    discover_devices(&context, options->slot, devices, &count);
    Device *device = NULL;
    if (!select_device(devices, count, options, &device)) {
        hid_context_release(&context);
        package_release(&package);
        return 1;
    }
    if (package.product_id != 0 && package.product_id != device->iface->product_id) {
        fprintf(stderr, "refusing restore: backup product 0x%04X does not match connected product 0x%04X\n",
                package.product_id, device->iface->product_id);
        hid_context_release(&context);
        package_release(&package);
        return 1;
    }
    ProfileInfo info;
    if (!get_profile_info(device, &info)) {
        hid_context_release(&context);
        package_release(&package);
        return 1;
    }
    if (package.size != info.sector_size || package.profile_format != info.profile_format) {
        fprintf(stderr, "refusing restore: backup format/sector size (0x%02X/%u) does not match device (0x%02X/%u)\n",
                package.profile_format, package.size, info.profile_format, info.sector_size);
        hid_context_release(&context);
        package_release(&package);
        return 1;
    }
    uint8_t *control = (uint8_t *)malloc(info.sector_size);
    if (control == NULL) {
        hid_context_release(&context);
        package_release(&package);
        return 1;
    }
    uint16_t control_sector = 0;
    if (!read_profile_control(device, &info, &control_sector, control)) {
        free(control);
        hid_context_release(&context);
        package_release(&package);
        return 1;
    }
    ProfileHeader headers[MAX_HEADERS];
    size_t header_count = 0;
    size_t selected = 0;
    bool found = package.sector == control_sector;
    if (!found) {
        if (!parse_profile_headers(&info, control, headers, &header_count)) {
            free(control);
            hid_context_release(&context);
            package_release(&package);
            return 1;
        }
        for (size_t i = 0; i < header_count; i++) {
            if (headers[i].sector == package.sector) {
                selected = i;
                found = true;
                break;
            }
        }
    }
    if (!found) {
        fprintf(stderr, "refusing restore: sector 0x%04X is not present in the connected device's profile headers\n", package.sector);
        free(control);
        hid_context_release(&context);
        package_release(&package);
        return 1;
    }
    free(control);
    uint8_t *current = (uint8_t *)malloc(info.sector_size);
    if (current == NULL || !read_sector(device, package.sector, info.sector_size, current)) {
        fprintf(stderr, "could not read the current target sector before restore\n");
        free(current);
        hid_context_release(&context);
        package_release(&package);
        return 1;
    }
    printf("Restore target: %s, sector 0x%04X, %u bytes\n", device_label(device), package.sector, package.size);
    printf("Backup CRC: OK; current CRC: %s\n", sector_crc_ok(current, info.sector_size) ? "OK" : "INVALID");
    printf("The backup was made for device 0x%04X via device number 0x%02X; connected product is 0x%04X via 0x%02X.\n",
           package.product_id, package.device_number, device->iface->product_id, device->device_number);
    if (memcmp(current, package.data, package.size) == 0) {
        printf("Nothing to do; the connected sector already matches the backup.\n");
        free(current);
        hid_context_release(&context);
        package_release(&package);
        return 0;
    }
    if (!options->yes) {
        free(current);
        hid_context_release(&context);
        package_release(&package);
        return ensure_write_confirmation("restore");
    }

    Profile pre_restore;
    memset(&pre_restore, 0, sizeof(pre_restore));
    pre_restore.info = info;
    pre_restore.headers[0].sector = package.sector;
    pre_restore.headers[0].enabled = package.sector == control_sector ? 1 : headers[selected].enabled;
    pre_restore.selected_header = 0;
    pre_restore.data = current;
    pre_restore.data_length = info.sector_size;
    char pre_restore_path[512];
    snprintf(pre_restore_path, sizeof(pre_restore_path), "%s.pre-restore.bin", options->path);
    if (!package_write(pre_restore_path, device, &pre_restore, current, false)) {
        fprintf(stderr, "could not save the pre-restore sector; no mouse write was attempted\n");
        free(current);
        hid_context_release(&context);
        package_release(&package);
        return 1;
    }
    printf("Saved pre-restore state to %s\n", pre_restore_path);
    if (!write_sector(device, package.sector, package.data, package.size)) {
        fprintf(stderr, "restore write failed; pre-restore state is at %s\n", pre_restore_path);
        free(current);
        hid_context_release(&context);
        package_release(&package);
        return 1;
    }
    uint8_t *readback = (uint8_t *)malloc(package.size);
    bool readback_ok = readback != NULL && read_sector(device, package.sector, package.size, readback);
    bool verified = readback_ok && sector_crc_ok(readback, package.size) && memcmp(readback, package.data, package.size) == 0;
    if (!verified) {
        fprintf(stderr, "restore read-back verification failed; pre-restore state is at %s\n", pre_restore_path);
        free(readback);
        free(current);
        hid_context_release(&context);
        package_release(&package);
        return 1;
    }
    printf("Restored sector 0x%04X and verified an exact read-back match.\n", package.sector);
    free(readback);
    free(current);
    hid_context_release(&context);
    package_release(&package);
    return 0;
}

typedef struct {
    uint8_t *callback_buffer;
    uint8_t previous_buttons;
    bool have_previous;
    char label[256];
} WatchState;

static const char *mouse_button_name(uint8_t bit) {
    switch (bit) {
        case 0: return "Left";
        case 1: return "Right";
        case 2: return "Middle";
        case 3: return "Back / rear thumb";
        case 4: return "Forward";
        case 5: return "Button 6";
        case 6: return "Button 7";
        case 7: return "Button 8";
        default: return "unknown";
    }
}

static void watch_report_callback(void *context,
                                  IOReturn result,
                                  void *sender,
                                  IOHIDReportType type,
                                  uint32_t report_id,
                                  uint8_t *report,
                                  CFIndex report_length) {
    (void)result;
    (void)sender;
    (void)type;
    WatchState *state = (WatchState *)context;
    if (state == NULL || report == NULL || report_length < 1) {
        return;
    }
    // Standard HID mouse reports put the button bitmap before X/Y motion.
    // Numbered reports include their ID in the raw callback buffer on macOS;
    // unnumbered reports begin directly with the button bitmap.
    size_t button_offset = (report_id != 0 && report_length > 1 && report[0] == report_id) ? 1 : 0;
    uint8_t buttons = report[button_offset];
    if (!state->have_previous) {
        state->previous_buttons = buttons;
        state->have_previous = true;
        return;
    }
    uint8_t pressed = (uint8_t)((buttons ^ state->previous_buttons) & buttons);
    state->previous_buttons = buttons;
    for (uint8_t bit = 0; bit < 8; bit++) {
        if ((pressed & (uint8_t)(1u << bit)) != 0) {
            printf("[%s] press: HID button %u (%s), report 0x%02X\n",
                   state->label, bit + 1, mouse_button_name(bit), report_id);
            fflush(stdout);
        }
    }
}

static int run_watch(const Options *options) {
    HidContext context;
    if (!hid_context_create(&context)) {
        return 1;
    }
    size_t mouse_index = 0;
    HidInterface *mouse = NULL;
    for (size_t i = 0; i < context.count; i++) {
        if (!context.items[i].is_mouse) {
            continue;
        }
        if (options->device_index >= 0 && (int)mouse_index != options->device_index) {
            mouse_index++;
            continue;
        }
        mouse = &context.items[i];
        break;
    }
    if (mouse == NULL) {
        fprintf(stderr, "no Logitech standard mouse input interface found\n");
        hid_context_release(&context);
        return 1;
    }
    if (IOHIDDeviceOpen(mouse->device, kIOHIDOptionsTypeNone) != kIOReturnSuccess) {
        fprintf(stderr, "could not open the mouse input interface\n");
        hid_context_release(&context);
        return 1;
    }
    WatchState state;
    memset(&state, 0, sizeof(state));
    state.callback_buffer = (uint8_t *)calloc(MAX_REPORT_BYTES, 1);
    snprintf(state.label, sizeof(state.label), "%s", mouse->product[0] ? mouse->product : "Logitech mouse");
    if (state.callback_buffer == NULL) {
        IOHIDDeviceClose(mouse->device, kIOHIDOptionsTypeNone);
        hid_context_release(&context);
        return 1;
    }
    IOHIDDeviceRegisterInputReportCallback(mouse->device,
                                           state.callback_buffer,
                                           MAX_REPORT_BYTES,
                                           watch_report_callback,
                                           &state);
    IOHIDDeviceScheduleWithRunLoop(mouse->device, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    signal(SIGINT, on_sigint);
    printf("Watching %s. Press the rear thumb button once; Ctrl-C stops.\n", state.label);
    printf("A standard Logitech mouse report commonly identifies the rear thumb as HID button 4 / Back (bit 3).\n");
    while (!g_stop_watch) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.10, true);
    }
    IOHIDDeviceUnscheduleFromRunLoop(mouse->device, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    IOHIDDeviceClose(mouse->device, kIOHIDOptionsTypeNone);
    free(state.callback_buffer);
    hid_context_release(&context);
    g_stop_watch = 0;
    return 0;
}

static void print_usage(const char *program) {
    printf("Usage: %s [global options] command [arguments]\n\n", program);
    printf("Read-only commands:\n");
    printf("  list                                  enumerate Logitech HID++ devices\n");
    printf("  info                                  show capabilities and a selected profile\n");
    printf("  profiles                             inspect profile headers and button records\n");
    printf("  dpi                                  show supported/current and onboard DPI stages\n");
    printf("  dump FILE                            save active profile as a backup package\n");
    printf("  watch                                identify physical mouse button reports\n");
    printf("  self-test                            run local CRC/layout tests\n\n");
    printf("Write commands (preview-only unless --yes is supplied):\n");
    printf("  bind rear-thumb alt-tab              preview the rear thumb -> Left Alt+Tab change\n");
    printf("  bind --button N alt-tab              preview an explicit profile button change\n");
    printf("  set-dpi 800,1600                       preview a one-to-five-stage onboard DPI change\n");
    printf("  set-profile-state N enable|disable   preview enabling or disabling profile N\n");
    printf("  restore FILE                         preview restoring a backup package\n\n");
    printf("Global options:\n");
    printf("  --device N                           logical device index from list\n");
    printf("  --slot N|ff                          receiver slot 1..6 or direct 0xff\n");
    printf("  --profile N                          1-based profile number\n");
    printf("  --button N                           explicit profile button number for bind\n");
    printf("  --default N                          onboard default DPI stage, 1..5\n");
    printf("  --shift N                            onboard DPI-shift stage, 1..5\n");
    printf("  --backup FILE                        backup path for bind\n");
    printf("  --yes                                permit the requested mouse write\n");
    printf("  --help                               show this help\n");
}

static int parse_decimal(const char *text, int *value) {
    if (text == NULL || *text == '\0') {
        return 0;
    }
    char *end = NULL;
    errno = 0;
    long parsed = strtol(text, &end, 10);
    if (errno != 0 || end == text || *end != '\0' || parsed < 0 || parsed > 100000) {
        return 0;
    }
    *value = (int)parsed;
    return 1;
}

static int parse_slot(const char *text, int *slot) {
    if (strcmp(text, "ff") == 0 || strcmp(text, "FF") == 0 || strcmp(text, "0xff") == 0 || strcmp(text, "0xFF") == 0) {
        *slot = 0xFF;
        return 1;
    }
    int parsed = 0;
    if (!parse_decimal(text, &parsed) || parsed < 1 || parsed > 6) {
        return 0;
    }
    *slot = parsed;
    return 1;
}

static int parse_options(int argc, char **argv, Options *options) {
    memset(options, 0, sizeof(*options));
    options->device_index = -1;
    options->slot = -1;
    options->dpi_default = -1;
    options->dpi_shift = -1;
    for (int i = 1; i < argc; i++) {
        const char *arg = argv[i];
        if (strcmp(arg, "--help") == 0 || strcmp(arg, "-h") == 0) {
            print_usage(argv[0]);
            exit(0);
        }
        if (strcmp(arg, "--yes") == 0) {
            options->yes = true;
            continue;
        }
        if (strcmp(arg, "--device") == 0 || strcmp(arg, "--slot") == 0 ||
            strcmp(arg, "--profile") == 0 || strcmp(arg, "--button") == 0 ||
            strcmp(arg, "--backup") == 0 || strcmp(arg, "--default") == 0 ||
            strcmp(arg, "--shift") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "%s requires a value\n", arg);
                return 0;
            }
            const char *value = argv[++i];
            if (strcmp(arg, "--device") == 0) {
                if (!parse_decimal(value, &options->device_index)) {
                    fprintf(stderr, "invalid --device value '%s'\n", value);
                    return 0;
                }
            } else if (strcmp(arg, "--slot") == 0) {
                if (!parse_slot(value, &options->slot)) {
                    fprintf(stderr, "invalid --slot value '%s'\n", value);
                    return 0;
                }
            } else if (strcmp(arg, "--profile") == 0) {
                if (!parse_decimal(value, &options->profile) || options->profile < 1) {
                    fprintf(stderr, "invalid --profile value '%s'\n", value);
                    return 0;
                }
            } else if (strcmp(arg, "--button") == 0) {
                if (!parse_decimal(value, &options->button) || options->button < 1) {
                    fprintf(stderr, "invalid --button value '%s'\n", value);
                    return 0;
                }
            } else if (strcmp(arg, "--default") == 0) {
                if (!parse_decimal(value, &options->dpi_default) || options->dpi_default < 1 || options->dpi_default > 5) {
                    fprintf(stderr, "invalid --default value '%s'\n", value);
                    return 0;
                }
            } else if (strcmp(arg, "--shift") == 0) {
                if (!parse_decimal(value, &options->dpi_shift) || options->dpi_shift < 1 || options->dpi_shift > 5) {
                    fprintf(stderr, "invalid --shift value '%s'\n", value);
                    return 0;
                }
            } else {
                options->backup_path = value;
            }
            continue;
        }
        if (arg[0] == '-') {
            fprintf(stderr, "unknown option '%s'\n", arg);
            return 0;
        }
        if (options->command == NULL) {
            options->command = arg;
        } else if (options->positional_count < 8) {
            options->positionals[options->positional_count++] = arg;
        } else {
            fprintf(stderr, "too many command arguments\n");
            return 0;
        }
    }
    if (options->command == NULL) {
        options->command = "list";
    }
    if (options->device_index >= 0 && options->slot >= 0) {
        fprintf(stderr, "use either --device or --slot, not both\n");
        return 0;
    }
    if (strcmp(options->command, "dump") == 0 || strcmp(options->command, "restore") == 0) {
        if (options->positional_count != 1) {
            fprintf(stderr, "%s requires exactly one FILE argument\n", options->command);
            return 0;
        }
        options->path = options->positionals[0];
    } else if (strcmp(options->command, "bind") == 0) {
        if (options->positional_count == 2 && strcmp(options->positionals[0], "rear-thumb") == 0) {
            options->target = options->positionals[1];
        } else if (options->positional_count == 1) {
            options->target = options->positionals[0];
        } else {
            fprintf(stderr, "bind syntax: bind rear-thumb alt-tab or bind --button N alt-tab\n");
            return 0;
        }
    } else if (strcmp(options->command, "set-dpi") == 0) {
        if (options->positional_count != 1) {
            fprintf(stderr, "set-dpi requires one comma-separated list with one to five stages\n");
            return 0;
        }
    } else if (strcmp(options->command, "set-profile-state") == 0) {
        if (options->positional_count != 2) {
            fprintf(stderr, "set-profile-state syntax: set-profile-state N enable|disable\n");
            return 0;
        }
    } else if (options->positional_count != 0) {
        fprintf(stderr, "%s does not take positional arguments\n", options->command);
        return 0;
    }
    return 1;
}

static int run_self_test(void) {
    const uint8_t sample[] = "123456789";
    if (crc16_ccitt_false(sample, 9) != 0x29B1) {
        fprintf(stderr, "CRC self-test failed\n");
        return 1;
    }
    uint8_t frame[LONG_REPORT_BYTES];
    const uint8_t ping_params[3] = {0x00, 0x00, 0x5A};
    size_t frame_length = build_hidpp_frame(false, 0x01, 0x001B, ping_params, sizeof(ping_params), frame);
    if (frame_length != SHORT_REPORT_BYTES || frame[0] != REPORT_SHORT || frame[1] != 0x01 ||
        frame[2] != 0x00 || frame[3] != 0x1B || memcmp(frame + 4, ping_params, 3) != 0) {
        fprintf(stderr, "short HID++ frame self-test failed\n");
        return 1;
    }
    uint8_t long_params[16];
    for (size_t i = 0; i < sizeof(long_params); i++) long_params[i] = (uint8_t)i;
    frame_length = build_hidpp_frame(true, 0xFF, 0x127B, long_params, sizeof(long_params), frame);
    if (frame_length != LONG_REPORT_BYTES || frame[0] != REPORT_LONG || frame[1] != 0xFF ||
        frame[2] != 0x12 || frame[3] != 0x7B || memcmp(frame + 4, long_params, 16) != 0) {
        fprintf(stderr, "long HID++ frame self-test failed\n");
        return 1;
    }
    Profile profile;
    uint16_t parsed_dpi[5] = {0};
    size_t parsed_dpi_count = 0;
    bool dpi_parser_ok = parse_dpi_values("800,1600", parsed_dpi, &parsed_dpi_count) &&
                         parsed_dpi_count == 2 && parsed_dpi[0] == 800 && parsed_dpi[1] == 1600 &&
                         !parse_dpi_values("800,1200,1600,2400,3200,6400", parsed_dpi, &parsed_dpi_count);
    if (!dpi_parser_ok) {
        fprintf(stderr, "DPI parser self-test failed\n");
        return 1;
    }
    memset(&profile, 0, sizeof(profile));
    profile.info.profile_format = 5;
    profile.info.button_count = 5;
    profile.data_length = 255;
    profile.data = (uint8_t *)calloc(profile.data_length, 1);
    if (profile.data == NULL) {
        return 1;
    }
    uint8_t specs[5][4] = {
        {0x80, 0x01, 0x00, 0x01},
        {0x80, 0x01, 0x00, 0x02},
        {0x80, 0x01, 0x00, 0x04},
        {0x80, 0x01, 0x00, 0x08},
        {0x80, 0x01, 0x00, 0x10},
    };
    for (size_t i = 0; i < 5; i++) {
        memcpy(profile.data + 32 + i * 4, specs[i], 4);
    }
    uint16_t sample_dpi[5] = {800, 1200, 1600, 2400, 3200};
    for (size_t i = 0; i < 5; i++) {
        write_le16(profile.data + 3 + i * 2, sample_dpi[i]);
    }
    profile.data[1] = 2;
    profile.data[2] = 0;
    sector_put_crc(profile.data, profile.data_length);
    profile.crc_ok = sector_crc_ok(profile.data, profile.data_length);
    detect_button_layout(&profile);
    detect_dpi_layout(&profile);
    uint8_t alt_tab[4];
    bool target_ok = parse_target("alt-tab", alt_tab) && alt_tab[0] == 0x80 && alt_tab[1] == 0x02 &&
                     alt_tab[2] == 0x04 && alt_tab[3] == 0x2B;
    int rear = find_rear_thumb_button(&profile);
    bool passed = profile.crc_ok && profile.layout_supported && profile.button_offset == 32 &&
                  profile.dpi_layout_supported && profile.dpi_offset == 3 &&
                  read_le16(profile.data + profile.dpi_offset + 2 * 2) == 1600 &&
                  rear == 4 && target_ok;
    write_le16(profile.data + 3 + 2 * 2, UINT16_MAX);
    write_le16(profile.data + 3 + 3 * 2, UINT16_MAX);
    write_le16(profile.data + 3 + 4 * 2, UINT16_MAX);
    profile.data[1] = 0;
    profile.data[2] = 1;
    detect_dpi_layout(&profile);
    passed = passed && profile.dpi_layout_supported && profile.dpi_count == 2 &&
             profile.dpi_default_index == 0 && profile.dpi_shift_index == 1;
    free(profile.data);
    if (!passed) {
        fprintf(stderr, "profile/layout self-test failed\n");
        return 1;
    }

    Profile newer;
    memset(&newer, 0, sizeof(newer));
    newer.info.profile_format = 7;
    newer.info.button_count = 5;
    newer.data_length = 255;
    newer.data = (uint8_t *)calloc(newer.data_length, 1);
    if (newer.data == NULL) {
        return 1;
    }
    for (size_t i = 0; i < 5; i++) {
        memcpy(newer.data + 48 + i * 4, specs[i], 4);
    }
    sector_put_crc(newer.data, newer.data_length);
    newer.crc_ok = sector_crc_ok(newer.data, newer.data_length);
    detect_button_layout(&newer);
    bool newer_ok = newer.crc_ok && newer.layout_supported && newer.button_offset == 48 && find_rear_thumb_button(&newer) == 4;
    free(newer.data);
    if (!newer_ok) {
        fprintf(stderr, "newer profile layout self-test failed\n");
        return 1;
    }

    HidInterface dummy_interface;
    memset(&dummy_interface, 0, sizeof(dummy_interface));
    dummy_interface.vendor_id = LOGITECH_VID;
    dummy_interface.product_id = 0xC08B;
    Device dummy_device;
    memset(&dummy_device, 0, sizeof(dummy_device));
    dummy_device.iface = &dummy_interface;
    dummy_device.device_number = 0xFF;
    profile.headers[0].sector = 0x0123;
    profile.selected_header = 0;
    profile.info.profile_format = 5;
    profile.data_length = 255;
    profile.data = (uint8_t *)calloc(profile.data_length, 1);
    if (profile.data == NULL) {
        return 1;
    }
    sector_put_crc(profile.data, profile.data_length);
    char temp_path[] = "/tmp/logitech-onboard-selftest-XXXXXX";
    int temp_fd = mkstemp(temp_path);
    if (temp_fd < 0) {
        free(profile.data);
        return 1;
    }
    close(temp_fd);
    unlink(temp_path);
    bool package_ok = package_write(temp_path, &dummy_device, &profile, profile.data, true);
    BackupPackage package;
    if (package_ok) {
        package_ok = package_read(temp_path, &package);
    }
    if (package_ok) {
        package_ok = package.sector == 0x0123 && package.size == 255 &&
                     memcmp(package.data, profile.data, 255) == 0;
        package_release(&package);
    }
    unlink(temp_path);
    free(profile.data);
    if (!package_ok) {
        fprintf(stderr, "backup package self-test failed\n");
        return 1;
    }
    printf("self-test: CRC-16, format/layout detection, rear-thumb identification, and Alt+Tab encoding passed\n");
    return 0;
}

int main(int argc, char **argv) {
    Options options;
    if (!parse_options(argc, argv, &options)) {
        print_usage(argv[0]);
        return 2;
    }
    if (strcmp(options.command, "self-test") == 0) {
        return run_self_test();
    }
    if (strcmp(options.command, "list") == 0) return run_list();
    if (strcmp(options.command, "info") == 0) return run_info(&options);
    if (strcmp(options.command, "profiles") == 0) return run_profiles(&options);
    if (strcmp(options.command, "dpi") == 0) return run_dpi(&options);
    if (strcmp(options.command, "dump") == 0) return run_dump(&options);
    if (strcmp(options.command, "watch") == 0) return run_watch(&options);
    if (strcmp(options.command, "bind") == 0) return run_bind(&options);
    if (strcmp(options.command, "set-dpi") == 0) return run_set_dpi(&options);
    if (strcmp(options.command, "set-profile-state") == 0) return run_set_profile_state(&options);
    if (strcmp(options.command, "restore") == 0) return run_restore(&options);
    fprintf(stderr, "unknown command '%s'\n", options.command);
    print_usage(argv[0]);
    return 2;
}
