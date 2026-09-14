#ifndef LOPE_LOGITECH_ONBOARD_HID_TYPES_H
#define LOPE_LOGITECH_ONBOARD_HID_TYPES_H

#include "types.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/hid/IOHIDLib.h>
#include <IOKit/hid/IOHIDManager.h>
#include <pthread.h>

typedef struct HidReportNode {
    uint32_t report_id;
    size_t length;
    uint8_t bytes[MAX_REPORT_BYTES];
    struct HidReportNode *next;
} HidReportNode;

struct HidChannel {
    IOHIDDeviceRef device;
    uint8_t *callback_buffer;
    CFRunLoopRef run_loop;
    pthread_mutex_t lock;
    HidReportNode *head;
    HidReportNode *tail;
    bool opened;
};

struct HidInterface {
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
    // Receiver-backed HID++ devices may require the long report even when
    // the request payload would fit in a short report. This is detected from
    // the interface descriptor (or a known Logitech HID++ product ID).
    bool prefer_long_reports;
    HidChannel channel;
    bool channel_open;
};

struct HidContext {
    IOHIDManagerRef manager;
    CFSetRef device_set;
    HidInterface *items;
    size_t count;
    bool manager_open;
};

#endif // LOPE_LOGITECH_ONBOARD_HID_TYPES_H
