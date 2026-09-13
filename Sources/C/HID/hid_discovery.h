#ifndef LOPE_LOGITECH_ONBOARD_HID_DISCOVERY_H
#define LOPE_LOGITECH_ONBOARD_HID_DISCOVERY_H

#include "types.h"

typedef int (*DiscoverDevicesForOptionsFn)(HidContext *context, const Options *options,
                                           Device *devices, size_t *count);
typedef int (*HidContextCreateFn)(HidContext *context);

extern DiscoverDevicesForOptionsFn discover_devices_for_options_impl;
extern HidContextCreateFn hid_context_create_impl;

int hid_context_create(HidContext *context);
int hid_context_create_hardware(HidContext *context);
void hid_context_release(HidContext *context);
int open_vendor_channels(HidContext *context);

int discover_devices(HidContext *context, int requested_slot, Device *devices, size_t *count,
                     bool inspect_features);
int discover_device_by_key(HidContext *context, const char *key, Device *devices, size_t *count);
int discover_devices_for_options_hardware(HidContext *context, const Options *options,
                                          Device *devices, size_t *count);
int discover_devices_for_options(HidContext *context, const Options *options, Device *devices,
                                 size_t *count);

bool is_duplicate_direct_mouse_endpoint(const Device *candidate, const Device *devices,
                                        size_t count);
bool is_mouse_device(const Device *device);
const char *device_label(const Device *device);
const char *device_connection(const Device *device);
void format_device_key(const Device *device, char *out, size_t out_size);
bool parse_device_key(const char *text, uint64_t *location_id, uint64_t *registry_id,
                      uint8_t *device_number);

const char *receiver_pairing_model_name(Reply pairing_reply);
bool is_receiver_endpoint(const Device *device);

#endif // LOPE_LOGITECH_ONBOARD_HID_DISCOVERY_H
