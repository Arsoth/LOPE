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
#include <IOKit/hidsystem/IOHIDLib.h>
#include <IOKit/IOKitLib.h>
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <pthread.h>
#include <signal.h>
#include <stdarg.h>
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

// HID++ 1.0 receiver registers used to enumerate paired devices.
#define REGISTER_RECEIVER_CONNECTION 0x0002
#define REGISTER_RECEIVER_INFO 0x02B5
#define RECEIVER_INFO_INFORMATION 0x03
#define RECEIVER_INFO_PAIRING 0x20
#define RECEIVER_INFO_DEVICE_NAME 0x40

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
    // Receiver-backed HID++ devices may require the long report even when
    // the request payload would fit in a short report. This is detected from
    // the interface descriptor (or a known Logitech HID++ product ID).
    bool prefer_long_reports;
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
    // device_number is the address returned by discovery and is useful for
    // identifying receiver slots. request_device_number is the address that
    // must be used for subsequent HID++ calls; a direct wireless endpoint can
    // report a slot alias while still requiring 0xFF for commands.
    uint8_t device_number;
    uint8_t request_device_number;
    double protocol;
    bool prefer_long_reports;
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
    uint8_t device_number;
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
    bool crc_checked;
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
    const char *device_key;
    int slot;
    int profile;
    bool headers_only;
    bool summary_only;
    bool sensor_only;
    bool include_dpi;
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
