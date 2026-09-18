#ifndef LOPE_LOGITECH_ONBOARD_HID_TRANSPORT_H
#define LOPE_LOGITECH_ONBOARD_HID_TRANSPORT_H

#include "hid_types.h"

#include <signal.h>
#include <stdio.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/hid/IOHIDElement.h>

extern volatile sig_atomic_t g_stop_watch;

typedef IOReturn (*HidDeviceOpenFn)(IOHIDDeviceRef device, IOOptionBits options);
typedef IOReturn (*HidDeviceCloseFn)(IOHIDDeviceRef device, IOOptionBits options);
typedef void (*HidDeviceRegisterInputReportCallbackFn)(IOHIDDeviceRef device, uint8_t *report,
                                                       CFIndex report_length,
                                                       IOHIDReportCallback callback, void *context);
typedef void (*HidDeviceScheduleWithRunLoopFn)(IOHIDDeviceRef device, CFRunLoopRef run_loop,
                                               CFStringRef mode);
typedef void (*HidDeviceUnscheduleFromRunLoopFn)(IOHIDDeviceRef device, CFRunLoopRef run_loop,
                                                 CFStringRef mode);
typedef IOReturn (*HidDeviceSetReportFn)(IOHIDDeviceRef device, IOHIDReportType type,
                                         CFIndex report_id, const uint8_t *report,
                                         CFIndex report_length);
typedef IOReturn (*HidDeviceGetReportFn)(IOHIDDeviceRef device, IOHIDReportType type,
                                         CFIndex report_id, uint8_t *report,
                                         CFIndex *report_length);
typedef CFTypeRef (*HidDeviceGetPropertyFn)(IOHIDDeviceRef device, CFStringRef key);
typedef io_service_t (*HidDeviceGetServiceFn)(IOHIDDeviceRef device);
typedef kern_return_t (*HidRegistryEntryGetIDFn)(io_registry_entry_t service,
                                                 uint64_t *registry_id);
typedef CFArrayRef (*HidDeviceCopyMatchingElementsFn)(IOHIDDeviceRef device,
                                                      CFDictionaryRef matching,
                                                      IOOptionBits options);
typedef CFIndex (*HidArrayGetCountFn)(CFArrayRef array);
typedef const void *(*HidArrayGetValueAtIndexFn)(CFArrayRef array, CFIndex index);
typedef uint32_t (*HidElementGetUsagePageFn)(IOHIDElementRef element);
typedef uint32_t (*HidElementGetReportIDFn)(IOHIDElementRef element);
typedef FILE *(*HidDebugFileOpenFn)(const char *path, const char *mode);

extern HidDeviceOpenFn hid_device_open_impl;
extern HidDeviceCloseFn hid_device_close_impl;
extern HidDeviceRegisterInputReportCallbackFn hid_device_register_input_report_callback_impl;
extern HidDeviceScheduleWithRunLoopFn hid_device_schedule_with_run_loop_impl;
extern HidDeviceUnscheduleFromRunLoopFn hid_device_unschedule_from_run_loop_impl;
extern HidDeviceSetReportFn hid_device_set_report_impl;
extern HidDeviceGetReportFn hid_device_get_report_impl;
extern HidDeviceGetPropertyFn hid_device_get_property_impl;
extern HidDeviceGetServiceFn hid_device_get_service_impl;
extern HidRegistryEntryGetIDFn hid_registry_entry_get_id_impl;
extern HidDeviceCopyMatchingElementsFn hid_device_copy_matching_elements_impl;
extern HidArrayGetCountFn hid_array_get_count_impl;
extern HidArrayGetValueAtIndexFn hid_array_get_value_at_index_impl;
extern HidElementGetUsagePageFn hid_element_get_usage_page_impl;
extern HidElementGetReportIDFn hid_element_get_report_id_impl;
extern HidDebugFileOpenFn hid_debug_file_open_impl;

typedef Reply (*ChannelRequestFn)(HidChannel *channel, uint8_t device_number, uint16_t request_id,
                                  const uint8_t *params, size_t params_length, bool prefer_long,
                                  double timeout_seconds);

extern ChannelRequestFn channel_request_impl;

void on_sigint(int signal_number);
void hid_report_callback_for_test(void *context, IOReturn result, void *sender,
                                  IOHIDReportType type, uint32_t report_id, uint8_t *report,
                                  CFIndex report_length);

bool hid_debug_enabled(void);
void hid_debug_log(const char *format, ...);

uint32_t number_property(IOHIDDeviceRef device, CFStringRef key);
uint64_t location_property(IOHIDDeviceRef device);
uint64_t registry_id_property(IOHIDDeviceRef device);
void string_property(IOHIDDeviceRef device, CFStringRef key, char *out, size_t out_size);
bool device_has_hidpp_reports(IOHIDDeviceRef device, bool inspect_protected_elements);

bool is_wireless_device_product(uint32_t product_id);
bool is_receiver_product(uint32_t product_id);
bool is_bluetooth_device_product(uint32_t product_id);
bool is_known_hidpp_product(uint32_t product_id);
bool text_contains_case_insensitive(const char *text, const char *needle);

int channel_open(HidChannel *channel, IOHIDDeviceRef device);
void channel_close(HidChannel *channel);
Reply channel_request_hardware(HidChannel *channel, uint8_t device_number, uint16_t request_id,
                               const uint8_t *params, size_t params_length, bool prefer_long,
                               double timeout_seconds);
Reply channel_request(HidChannel *channel, uint8_t device_number, uint16_t request_id,
                      const uint8_t *params, size_t params_length, bool prefer_long,
                      double timeout_seconds);

size_t build_hidpp_frame(bool use_long, uint8_t device_number, uint16_t request_id,
                         const uint8_t *params, size_t params_length, uint8_t *frame);

bool is_receiver_routed_device(const Device *device);
bool should_retry_short_report(Reply reply);
const char *reply_status_name(ReplyStatus status);
void print_reply_error(const char *operation, Reply reply);
int device_feature_index(const Device *device, uint16_t feature_id, uint8_t *index);

bool channel_get_feature_report(HidChannel *channel, uint8_t report_id, uint8_t *report,
                                size_t capacity, size_t *length);
bool channel_set_feature_report(HidChannel *channel, uint8_t report_id, uint8_t *report,
                                size_t length);
Reply device_call(Device *device, uint16_t feature_id, uint8_t function, const uint8_t *params,
                  size_t params_length, double timeout_seconds);
Reply device_call_long(Device *device, uint16_t feature_id, uint8_t function, const uint8_t *params,
                       size_t params_length, double timeout_seconds);
Reply raw_request(Device *device, uint16_t request_id, const uint8_t *params, size_t params_length,
                  bool prefer_long, double timeout_seconds);

#endif // LOPE_LOGITECH_ONBOARD_HID_TRANSPORT_H
