#ifndef LOPE_LOGITECH_ONBOARD_HID_TRANSPORT_H
#define LOPE_LOGITECH_ONBOARD_HID_TRANSPORT_H

#include "types.h"

extern volatile sig_atomic_t g_stop_watch;

typedef Reply (*ChannelRequestFn)(HidChannel *channel, uint8_t device_number, uint16_t request_id,
                                  const uint8_t *params, size_t params_length, bool prefer_long,
                                  double timeout_seconds);

extern ChannelRequestFn channel_request_impl;

void on_sigint(int signal_number);

bool hid_debug_enabled(void);
void hid_debug_log(const char *format, ...);

uint32_t number_property(IOHIDDeviceRef device, CFStringRef key);
uint64_t location_property(IOHIDDeviceRef device);
uint64_t registry_id_property(IOHIDDeviceRef device);
void string_property(IOHIDDeviceRef device, CFStringRef key, char *out, size_t out_size);
bool device_has_hidpp_reports(IOHIDDeviceRef device);

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
