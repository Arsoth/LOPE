#ifndef LOPE_LOGITECH_ONBOARD_WATCH_CLI_H
#define LOPE_LOGITECH_ONBOARD_WATCH_CLI_H

#include "hid_types.h"

typedef IOReturn (*WatchDeviceOpenFn)(IOHIDDeviceRef device, IOOptionBits options);
typedef IOReturn (*WatchDeviceCloseFn)(IOHIDDeviceRef device, IOOptionBits options);
typedef void *(*WatchBufferAllocateFn)(size_t count, size_t size);
typedef void (*WatchRegisterInputReportFn)(IOHIDDeviceRef device, uint8_t *report,
                                           CFIndex report_length, IOHIDReportCallback callback,
                                           void *context);
typedef void (*WatchRunLoopScheduleFn)(IOHIDDeviceRef device, CFRunLoopRef run_loop,
                                       CFRunLoopMode mode);
typedef CFRunLoopRunResult (*WatchRunLoopFn)(CFRunLoopMode mode, CFTimeInterval seconds,
                                             Boolean return_after_source_handled);

extern WatchDeviceOpenFn watch_device_open_impl;
extern WatchDeviceCloseFn watch_device_close_impl;
extern WatchBufferAllocateFn watch_buffer_allocate_impl;
extern WatchRegisterInputReportFn watch_register_input_report_impl;
extern WatchRunLoopScheduleFn watch_schedule_with_run_loop_impl;
extern WatchRunLoopScheduleFn watch_unschedule_from_run_loop_impl;
extern WatchRunLoopFn watch_run_loop_impl;

int run_watch(const Options *options);
void watch_report_callback_for_test(void *context, IOReturn result, void *sender,
                                    IOHIDReportType type, uint32_t report_id, uint8_t *report,
                                    CFIndex report_length);
const char *mouse_button_name(uint8_t bit);
void print_usage(const char *program);
int parse_decimal(const char *text, int *value);
int parse_slot(const char *text, int *slot);
int parse_options(int argc, char **argv, Options *options);

#endif // LOPE_LOGITECH_ONBOARD_WATCH_CLI_H
