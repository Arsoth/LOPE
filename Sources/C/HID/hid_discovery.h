#ifndef LOPE_LOGITECH_ONBOARD_HID_DISCOVERY_H
#define LOPE_LOGITECH_ONBOARD_HID_DISCOVERY_H

#include "types.h"

typedef IOHIDAccessType (*HidCheckAccessFn)(IOHIDRequestType request_type);
typedef IOHIDManagerRef (*HidManagerCreateFn)(CFAllocatorRef allocator, IOOptionBits options);
typedef void (*HidManagerSetDeviceMatchingFn)(IOHIDManagerRef manager, CFDictionaryRef matching);
typedef CFSetRef (*HidManagerCopyDevicesFn)(IOHIDManagerRef manager);
typedef CFIndex (*HidSetGetCountFn)(CFSetRef set);
typedef void (*HidSetGetValuesFn)(CFSetRef set, const void **values);
typedef IOReturn (*HidManagerCloseFn)(IOHIDManagerRef manager, IOOptionBits options);
typedef void (*HidCFReleaseFn)(CFTypeRef value);

extern HidCheckAccessFn hid_check_access_impl;
extern HidManagerCreateFn hid_manager_create_impl;
extern HidManagerSetDeviceMatchingFn hid_manager_set_device_matching_impl;
extern HidManagerCopyDevicesFn hid_manager_copy_devices_impl;
extern HidSetGetCountFn hid_set_get_count_impl;
extern HidSetGetValuesFn hid_set_get_values_impl;
extern HidManagerCloseFn hid_manager_close_impl;
extern HidCFReleaseFn hid_cf_release_impl;

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

// Test-only entry points for deterministic coverage of static discovery
// helpers that otherwise require a live HID manager or receiver.
int hid_discovery_compare_interfaces_for_test(const HidInterface *left, const HidInterface *right);
int hid_discovery_ping_interface_for_test(HidInterface *iface, uint8_t device_number,
                                          double timeout, double *protocol,
                                          uint8_t *resolved_device_number);
int hid_discovery_discover_features_for_test(Device *device);
int hid_discovery_device_name_for_test(Device *device);
bool hid_discovery_receiver_device_name_for_test(Device *device, uint8_t slot);
uint8_t hid_discovery_receiver_slot_limit_for_test(const HidInterface *iface);
Reply hid_discovery_receiver_register_read_for_test(HidInterface *iface, uint16_t register_id,
                                                    bool has_subregister, uint8_t subregister);
void hid_discovery_log_receiver_register_reply_for_test(const HidInterface *iface,
                                                        uint16_t register_id, uint8_t subregister,
                                                        Reply reply);
void hid_discovery_receiver_slot_name_for_test(Device *device, uint8_t slot, Reply pairing_reply);
bool hid_discovery_add_receiver_slot_device_for_test(Device *devices, size_t *count,
                                                     HidInterface *iface, uint8_t slot,
                                                     Reply pairing_reply, bool inspect_features);
int hid_discovery_add_device_for_test(Device *devices, size_t *count, HidInterface *iface,
                                      uint8_t device_number, uint8_t request_device_number,
                                      double protocol, bool inspect_features);
const char *hid_discovery_receiver_connection_type_for_test(const HidInterface *iface);

#endif // LOPE_LOGITECH_ONBOARD_HID_DISCOVERY_H
