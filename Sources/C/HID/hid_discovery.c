#include "hid_discovery.h"
#include "hid_transport.h"

#include <IOKit/hid/IOHIDKeys.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

HidCheckAccessFn hid_check_access_impl = IOHIDCheckAccess;
HidManagerCreateFn hid_manager_create_impl = IOHIDManagerCreate;
HidManagerSetDeviceMatchingFn hid_manager_set_device_matching_impl = IOHIDManagerSetDeviceMatching;
HidManagerCopyDevicesFn hid_manager_copy_devices_impl = IOHIDManagerCopyDevices;
HidSetGetCountFn hid_set_get_count_impl = CFSetGetCount;
HidSetGetValuesFn hid_set_get_values_impl = CFSetGetValues;
HidManagerCloseFn hid_manager_close_impl = IOHIDManagerClose;
HidCFReleaseFn hid_cf_release_impl = CFRelease;

static int ping_interface(HidInterface *iface, uint8_t device_number, double timeout,
                          double *protocol, uint8_t *resolved_device_number) {
    uint8_t params[3] = {0, 0, 0x5A};
    // A receiver advertises long reports, but routed slot probes follow the
    // short HID++ 1.0 path.  Try short first for receiver slots and retain a
    // long fallback for devices that require it.
    bool receiver = iface != NULL && is_receiver_product(iface->product_id);
    bool modes[2] = {receiver ? false : iface->prefer_long_reports,
                     receiver ? iface->prefer_long_reports : false};
    size_t mode_count = modes[0] == modes[1] ? 1 : 2;
    for (size_t mode = 0; mode < mode_count; mode++) {
        Reply reply = channel_request(&iface->channel, device_number, (uint16_t)(0x0010 | SW_ID),
                                      params, sizeof(params), modes[mode], timeout);
        if (hid_debug_enabled()) {
            char line[512];
            int written =
                snprintf(line, sizeof(line),
                         "hid-debug ping product=0x%04X location=0x%llX slot=0x%02X mode=%s "
                         "status=%s error=0x%02X length=%zu reply-device=0x%02X",
                         iface->product_id, (unsigned long long)iface->location_id, device_number,
                         modes[mode] ? "long" : "short", reply_status_name(reply.status),
                         reply.error_code, reply.length, reply.device_number);
            if (reply.length > 0) {
                if (written < (int)sizeof(line)) {
                    written += snprintf(line + written, sizeof(line) - (size_t)written, " bytes=");
                }
                for (size_t i = 0; i < reply.length && i < 8 && written < (int)sizeof(line); i++) {
                    written += snprintf(line + written, sizeof(line) - (size_t)written, "%02X",
                                        reply.bytes[i]);
                }
            }
            hid_debug_log("%s", line);
        }
        if (reply.status == REPLY_OK && reply.length >= 3 && reply.bytes[2] == 0x5A) {
            *protocol = (double)reply.bytes[0] + (double)reply.bytes[1] / 10.0;
            if (resolved_device_number != NULL) {
                *resolved_device_number =
                    device_number == 0xFF && reply.device_number >= 1 && reply.device_number <= 6
                        ? reply.device_number
                        : device_number;
            }
            return 1;
        }
        // A HID++ 1.0 receiver answers the 2.0-style ping with
        // invalid-sub-id. It is useful to list that receiver, but it cannot
        // edit a 0x8100 profile.
        if (reply.status == REPLY_HIDPP10_ERROR && reply.error_code == 0x01) {
            *protocol = 1.0;
            if (resolved_device_number != NULL) {
                *resolved_device_number = device_number;
            }
            return 1;
        }
        // A failed long-report probe can still be a valid short-only device.
        // Do not issue a second request for protocol errors such as an empty
        // receiver slot; those are definitive.
        if (reply.status != REPLY_TIMEOUT && reply.status != REPLY_IO_ERROR) {
            break;
        }
    }
    return 0;
}

static Reply receiver_register_read(HidInterface *iface, uint16_t register_id, bool has_subregister,
                                    uint8_t subregister) {
    uint8_t params[1] = {subregister};
    return channel_request(&iface->channel, 0xFF, (uint16_t)(0x8100 | (register_id & 0x02FF)),
                           has_subregister ? params : NULL, has_subregister ? sizeof(params) : 0,
                           false, 1.0);
}

static void log_receiver_register_reply(const HidInterface *iface, uint16_t register_id,
                                        uint8_t subregister, Reply reply) {
    if (!hid_debug_enabled()) {
        return;
    }
    char line[512];
    int written =
        snprintf(line, sizeof(line),
                 "hid-debug receiver-register product=0x%04X location=0x%llX register=0x%04X "
                 "sub=0x%02X status=%s error=0x%02X length=%zu bytes=",
                 iface->product_id, (unsigned long long)iface->location_id, register_id,
                 subregister, reply_status_name(reply.status), reply.error_code, reply.length);
    for (size_t i = 0; i < reply.length && i < 16 && written < (int)sizeof(line); i++) {
        written += snprintf(line + written, sizeof(line) - (size_t)written, "%02X", reply.bytes[i]);
    }
    hid_debug_log("%s", line);
}

static bool receiver_pairing_reply_is_present(Reply reply) {
    // The pairing-information record contains the WPID at bytes 3..4 and
    // the device kind at byte 7. Empty slots return a HID++ 1.0 error.
    return reply.status == REPLY_OK && reply.length >= 8;
}

static int add_device(Device *devices, size_t *count, HidInterface *iface, uint8_t device_number,
                      uint8_t request_device_number, double protocol, bool inspect_features);

static bool is_receiver_interface(const HidInterface *iface);

static bool receiver_device_name(Device *device, uint8_t slot) {
    // The receiver name register can briefly time out while a sleeping
    // LIGHTSPEED mouse is waking. Retry the name read independently of the
    // slot ping so a transient receiver response does not become the visible
    // device identity.
    for (int attempt = 0; attempt < 3; attempt++) {
        Reply reply = receiver_register_read(device->iface, REGISTER_RECEIVER_INFO, true,
                                             (uint8_t)(RECEIVER_INFO_DEVICE_NAME + slot - 1));
        if (reply.status != REPLY_OK || reply.length < 2) {
            if (attempt < 2 && (reply.status == REPLY_TIMEOUT || reply.status == REPLY_IO_ERROR)) {
                usleep(50 * 1000);
                continue;
            }
            return false;
        }
        size_t length = reply.bytes[1];
        if (length > reply.length - 2) {
            length = reply.length - 2;
        }
        if (length >= sizeof(device->name)) {
            length = sizeof(device->name) - 1;
        }
        memcpy(device->name, reply.bytes + 2, length);
        device->name[length] = '\0';
        while (length > 0 &&
               (device->name[length - 1] == '\0' || device->name[length - 1] == '\n' ||
                device->name[length - 1] == '\r')) {
            device->name[--length] = '\0';
        }
        if (length > 0) {
            return true;
        }
        if (attempt < 2) {
            usleep(50 * 1000);
        }
    }
    return false;
}

const char *receiver_pairing_model_name(Reply pairing_reply) {
    // Lightspeed pairing information carries the mouse WPID at bytes 3..4.
    // These WPID mappings let the list retain the model identity when a mouse
    // is asleep and the receiver's codename register is transiently
    // unavailable. The values are the receiver pairing identifiers, not the
    // receiver's USB product ID.
    if (pairing_reply.status != REPLY_OK || pairing_reply.length < 5) {
        return NULL;
    }
    uint16_t wpid = (uint16_t)(((uint16_t)pairing_reply.bytes[3] << 8) | pairing_reply.bytes[4]);
    switch (wpid) {
    case 0x406C:
        return "G603 LIGHTSPEED";
    case 0x4070:
        return "G703 LIGHTSPEED";
    case 0x4085:
        return "G604 LIGHTSPEED";
    case 0x4093:
        return "PRO X SUPERLIGHT";
    case 0x40BD:
        return "PRO X 2 SUPERSTRIKE";
    default:
        return NULL;
    }
}

static void receiver_slot_name(Device *device, uint8_t slot, Reply pairing_reply) {
    if (device->name[0] == '\0' && receiver_device_name(device, slot)) {
        return;
    }
    if (device->name[0] != '\0') {
        return;
    }
    const char *fallback = receiver_pairing_model_name(pairing_reply);
    if (fallback != NULL) {
        snprintf(device->name, sizeof(device->name), "%s", fallback);
    }
}

static uint32_t receiver_pairing_product_id(Reply pairing_reply) {
    if (pairing_reply.status != REPLY_OK || pairing_reply.length < 5) {
        return 0;
    }
    return (uint32_t)(((uint32_t)pairing_reply.bytes[3] << 8) | pairing_reply.bytes[4]);
}

static void receiver_slot_identity(Device *device, uint8_t slot, Reply pairing_reply) {
    // The receiver interface remains the transport endpoint. The pairing
    // record is the only source for the paired mouse's model/product identity.
    device->mouse_product_id = receiver_pairing_product_id(pairing_reply);
    receiver_slot_name(device, slot, pairing_reply);
}

static bool add_receiver_slot_device(Device *devices, size_t *count, HidInterface *iface,
                                     uint8_t slot, Reply pairing_reply, bool inspect_features) {
    if (!receiver_pairing_reply_is_present(pairing_reply)) {
        return false;
    }
    size_t before = *count;
    // Pairing information is the authoritative presence signal. A routed
    // ping can legitimately return RESOURCE_ERROR while the receiver still
    // has a paired device, so do not require ping success to list it.
    add_device(devices, count, iface, slot, slot, 2.0, inspect_features);
    if (*count == before) {
        return false;
    }
    Device *device = &devices[*count - 1];
    receiver_slot_identity(device, slot, pairing_reply);
    return true;
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

void hid_context_release(HidContext *context) {
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
        hid_cf_release_impl(context->device_set);
    }
    if (context->manager != NULL && context->manager_open) {
        hid_manager_close_impl(context->manager, kIOHIDOptionsTypeNone);
    }
    if (context->manager != NULL) {
        hid_cf_release_impl(context->manager);
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

int hid_context_create_hardware(HidContext *context) {
    memset(context, 0, sizeof(*context));
    // IOHIDDeviceOpen uses the HID-specific Input Monitoring permission. Do
    // not request it during enumeration: the GUI presents the wired-device
    // instructions and lets the user open System Settings deliberately.
    IOHIDAccessType hid_access = hid_check_access_impl(kIOHIDRequestTypeListenEvent);
    if (hid_debug_enabled()) {
        hid_debug_log("hid-debug access=%d", hid_access);
    }
    context->manager = hid_manager_create_impl(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    if (context->manager == NULL) {
        fprintf(stderr, "could not create macOS HID manager\n");
        return 0;
    }
    hid_manager_set_device_matching_impl(context->manager, NULL);
    // CopyDevices is the enumeration primitive and does not require opening
    // the manager. Opening it first can fail under macOS HID privacy
    // restrictions, even though the individual device is enumerable/openable.
    context->device_set = hid_manager_copy_devices_impl(context->manager);
    if (context->device_set == NULL) {
        fprintf(stderr, "could not enumerate macOS HID devices\n");
        hid_context_release(context);
        return 0;
    }
    CFIndex count = hid_set_get_count_impl(context->device_set);
    if (count > 0) {
        IOHIDDeviceRef *devices = (IOHIDDeviceRef *)calloc((size_t)count, sizeof(*devices));
        if (devices == NULL) {
            hid_context_release(context);
            return 0;
        }
        hid_set_get_values_impl(context->device_set, (const void **)devices);
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
            // always the vendor page. Element inspection opens a protected
            // connection, so use that fallback only after access is granted.
            bool hidpp_reports =
                device_has_hidpp_reports(device, hid_access == kIOHIDAccessTypeGranted);
            // A receiver exposes separate mouse, keyboard, and vendor HID
            // interfaces with the same product ID. Do not let the known
            // receiver PID fallback turn the first two into HID++ channels;
            // the descriptor/usage-page check identifies the real vendor
            // interface. The fallback remains necessary for direct wireless
            // and Bluetooth devices whose HID++ descriptor is hidden by macOS.
            bool known_device_fallback =
                (is_known_hidpp_product(product_id) && !is_receiver_product(product_id)) ||
                product_id == 0xC24A;
            bool vendor = page == HIDPP_USAGE_PAGE || hidpp_reports || known_device_fallback;
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
            // Direct HID++ interfaces advertise both report sizes and need
            // the normal payload-size selection: short control calls such as
            // 0x8100.endWrite must remain short. Receiver-backed devices (or
            // known devices whose HID++ descriptor is hidden) keep the long
            // report preference because their routed path needs it.
            item->prefer_long_reports = is_receiver_product(product_id) ||
                                        (!hidpp_reports && is_known_hidpp_product(product_id));
            string_property(device, CFSTR(kIOHIDProductKey), item->product, sizeof(item->product));
            string_property(device, CFSTR(kIOHIDTransportKey), item->transport,
                            sizeof(item->transport));
            hid_debug_log("hid-debug interface product=0x%04X location=0x%llX registry=0x%llX "
                          "page=0x%04X usage=0x%04X vendor=%d mouse=%d hidpp=%d product-name=%s",
                          item->product_id, (unsigned long long)item->location_id,
                          (unsigned long long)item->registry_id, item->usage_page, item->usage,
                          item->is_vendor, item->is_mouse, hidpp_reports, item->product);
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

// hid_context_create_impl is a test seam: command self-tests can inject an
// empty context while still exercising their normal discovery/selection and
// cleanup paths without enumerating real macOS HID devices.
HidContextCreateFn hid_context_create_impl = hid_context_create_hardware;

int hid_context_create(HidContext *context) { return hid_context_create_impl(context); }

static bool is_receiver_interface(const HidInterface *iface);

static bool interface_needs_input_monitoring(const HidInterface *iface) {
    if (is_receiver_interface(iface)) {
        return false;
    }
    // Bluetooth and Logitech wireless product IDs can be queried without the
    // wired HID Input Monitoring permission. Direct USB vendor interfaces are
    // the path that must remain closed until the user grants access.
    return !text_contains_case_insensitive(iface->transport, "bluetooth") &&
           !is_wireless_device_product(iface->product_id) &&
           !is_bluetooth_device_product(iface->product_id);
}

int open_vendor_channels(HidContext *context) {
    bool input_monitoring_authorized =
        hid_check_access_impl(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted;
    for (size_t i = 0; i < context->count; i++) {
        HidInterface *iface = &context->items[i];
        if (!iface->is_vendor || iface->channel_open) {
            continue;
        }
        if (!input_monitoring_authorized && interface_needs_input_monitoring(iface)) {
            // Enumeration remains passive when access is missing. The
            // standard mouse collection is still enough for discover_devices
            // to expose the real wired device without causing macOS to ask for
            // permission as a side effect of IOHIDDeviceOpen.
            continue;
        }
        if (channel_open(&iface->channel, iface->device)) {
            iface->channel_open = true;
        }
    }
    return 1;
}

static int add_device(Device *devices, size_t *count, HidInterface *iface, uint8_t device_number,
                      uint8_t request_device_number, double protocol, bool inspect_features) {
    if (*count >= MAX_DEVICES) {
        return 0;
    }
    Device *device = &devices[(*count)++];
    memset(device, 0, sizeof(*device));
    device->iface = iface;
    device->mouse_product_id = is_receiver_interface(iface) ? 0 : iface->product_id;
    device->device_number = device_number;
    device->request_device_number = request_device_number;
    device->protocol = protocol;
    device->prefer_long_reports = iface->prefer_long_reports;
    if (inspect_features && protocol >= 2.0) {
        discover_features(device);
        device_name(device);
    }
    return 1;
}

static bool is_receiver_interface(const HidInterface *iface) {
    // Logitech USB receiver product IDs occupy the C5xx range. Direct USB
    // mice use a different product-ID range and should not be probed as if
    // they had receiver slots. A few macOS HID interfaces report product ID
    // zero, so retain the product-name fallback for those receivers.
    return iface != NULL && (is_receiver_product(iface->product_id) ||
                             text_contains_case_insensitive(iface->product, "receiver") ||
                             text_contains_case_insensitive(iface->product, "unifying") ||
                             text_contains_case_insensitive(iface->product, "bolt"));
}

static uint8_t receiver_slot_limit(const HidInterface *iface) {
    if (iface == NULL || !is_receiver_interface(iface)) {
        return 0;
    }
    // Lightspeed receivers expose one paired slot. Unifying and Bolt
    // receivers expose up to six. Unknown C5xx receivers retain the broad
    // limit so a new receiver is not silently omitted.
    switch (iface->product_id) {
    case 0xC539:
    case 0xC53A:
    case 0xC53D:
    case 0xC53F:
    case 0xC541:
    case 0xC545:
    case 0xC547:
    case 0xC54D:
        return 1;
    case 0xC52B:
    case 0xC532:
    case 0xC548:
        return 6;
    default:
        return 6;
    }
}

static bool interface_has_mouse_collection(const HidContext *context, const HidInterface *iface) {
    if (context == NULL || iface == NULL || is_receiver_interface(iface)) {
        return false;
    }
    if (iface->is_mouse) {
        return true;
    }
    // macOS commonly exposes a direct mouse's standard collection beside its
    // vendor HID++ collection. The vendor interface is the endpoint we can
    // query, but the matching standard collection is the evidence that the
    // endpoint belongs to a mouse rather than another Logitech HID++ device.
    for (size_t other = 0; other < context->count; other++) {
        const HidInterface *candidate = &context->items[other];
        if (candidate->is_mouse && candidate->location_id == iface->location_id &&
            candidate->product_id == iface->product_id) {
            return true;
        }
    }
    return false;
}

bool is_receiver_endpoint(const Device *device);
bool is_mouse_device(const Device *device);
bool is_duplicate_direct_mouse_endpoint(const Device *candidate, const Device *devices,
                                        size_t count);

void format_device_key(const Device *device, char *out, size_t out_size) {
    snprintf(out, out_size, "%" PRIx64 "-%" PRIx64 "-%02X", device->iface->location_id,
             device->iface->registry_id, device->request_device_number);
}

bool parse_device_key(const char *text, uint64_t *location_id, uint64_t *registry_id,
                      uint8_t *device_number) {
    unsigned long long parsed_location = 0;
    unsigned long long parsed_registry = 0;
    unsigned int parsed_device = 0;
    char trailing = '\0';
    if (text == NULL ||
        sscanf(text, "%llx-%llx-%x%c", &parsed_location, &parsed_registry, &parsed_device,
               &trailing) != 3 ||
        parsed_device > UINT8_MAX) {
        return false;
    }
    *location_id = (uint64_t)parsed_location;
    *registry_id = (uint64_t)parsed_registry;
    *device_number = (uint8_t)parsed_device;
    return true;
}

int discover_devices(HidContext *context, int requested_slot, Device *devices, size_t *count,
                     bool inspect_features) {
    *count = 0;
    open_vendor_channels(context);
    for (size_t i = 0; i < context->count; i++) {
        HidInterface *iface = &context->items[i];
        if (!iface->is_vendor) {
            continue;
        }
        bool has_mouse_collection = interface_has_mouse_collection(context, iface);
        // A standard mouse collection is enough to identify a direct mouse
        // even when macOS blocks its separate HID++ vendor channel. Keep it
        // in the device picker so the UI can accurately report that profiles
        // are unavailable, rather than silently dropping the mouse.
        if (!iface->channel_open) {
            if (has_mouse_collection && !is_receiver_interface(iface)) {
                iface->has_mouse_collection = true;
                add_device(devices, count, iface, 0xFF, 0xFF, 0.0, inspect_features);
            }
            continue;
        }
        // Preserve the same eligibility evidence for an accessible vendor
        // interface before the HID++ ping creates its Device record.
        if (has_mouse_collection) {
            iface->has_mouse_collection = true;
        }
        // G600 uses legacy numbered feature reports rather than HID++ 0x8100.
        // It has no HID++ ping response, so the product ID is the discovery
        // signal after the direct vendor channel has opened successfully.
        if (iface->product_id == 0xC24A && !is_receiver_interface(iface)) {
            add_device(devices, count, iface, 0xFF, 0xFF, 0.0, false);
            continue;
        }
        if (requested_slot >= 0) {
            bool receiver_slot = is_receiver_interface(iface) && requested_slot >= 1 &&
                                 requested_slot <= receiver_slot_limit(iface);
            Reply pairing_reply = {0};
            if (receiver_slot) {
                pairing_reply =
                    receiver_register_read(iface, REGISTER_RECEIVER_INFO, true,
                                           (uint8_t)(RECEIVER_INFO_PAIRING + requested_slot - 1));
            }
            double protocol = 0;
            uint8_t resolved_device_number = (uint8_t)requested_slot;
            if (ping_interface(iface, (uint8_t)requested_slot, 1.0, &protocol,
                               &resolved_device_number)) {
                size_t before = *count;
                add_device(devices, count, iface, resolved_device_number, (uint8_t)requested_slot,
                           protocol, inspect_features);
                if (receiver_slot && *count > before) {
                    receiver_slot_identity(&devices[*count - 1], (uint8_t)requested_slot,
                                           pairing_reply);
                }
            }
            continue;
        }
        if (is_receiver_interface(iface)) {
            for (uint8_t slot = 1; slot <= receiver_slot_limit(iface); slot++) {
                Reply pairing_reply =
                    receiver_register_read(iface, 0x02B5, true, (uint8_t)(0x20 + slot - 1));
                log_receiver_register_reply(iface, 0x02B5, (uint8_t)(0x20 + slot - 1),
                                            pairing_reply);
                bool pairing_present = receiver_pairing_reply_is_present(pairing_reply);
                // The pairing table identifies the slot, but the routed ping
                // still primes the LIGHTSPEED path before feature requests.
                // G603 firmware can otherwise be listed but fail its first
                // 0x8100 profile read after the fast startup path.
                double protocol = 0;
                uint8_t resolved_device_number = slot;
                if (ping_interface(iface, slot, 1.0, &protocol, &resolved_device_number)) {
                    // Empty receiver slots answer the compatibility ping with
                    // a HID++ 1.0 error. Do not expose those errors as mice;
                    // a real profile-capable slot must answer HID++ 2.0 unless
                    // the pairing table already confirmed it.
                    if (pairing_present || protocol >= 2.0) {
                        size_t before = *count;
                        // A paired receiver slot is a HID++ 2.0 peripheral
                        // even when its routed compatibility ping is answered
                        // by the receiver with a HID++ 1.0 error. Preserve the
                        // pairing-table fact so feature discovery still runs.
                        double device_protocol = pairing_present ? 2.0 : protocol;
                        add_device(devices, count, iface, resolved_device_number, slot,
                                   device_protocol, inspect_features);
                        if (*count > before) {
                            receiver_slot_identity(&devices[*count - 1], slot, pairing_reply);
                        }
                    }
                } else if (pairing_present) {
                    // Preserve the positive pairing-table result if the
                    // mouse is asleep; the profile-read retry can wake it.
                    add_receiver_slot_device(devices, count, iface, slot, pairing_reply,
                                             inspect_features);
                }
            }

            // The receiver endpoint itself is not a mouse and is filtered
            // from `list`; its broadcast ping only adds another avoidable HID
            // request after all receiver slots have already been checked.
            continue;
        }
        double protocol = 0;
        uint8_t resolved_device_number = 0xFF;
        if (ping_interface(iface, 0xFF, 1.0, &protocol, &resolved_device_number)) {
            // A receiver can echo a paired slot in response to the broadcast
            // ping. Keep that endpoint marked as FF so the receiver itself is
            // still filtered from the mouse list; slot discovery above owns
            // the paired mouse entry.
            uint8_t reported_device_number =
                is_receiver_interface(iface) ? 0xFF : resolved_device_number;
            add_device(devices, count, iface, reported_device_number, 0xFF, protocol,
                       inspect_features);
        } else if (iface->is_mouse && !is_receiver_interface(iface)) {
            // Bluetooth and some direct wireless mice expose a normal mouse
            // collection even when HID++ ping is unavailable. They remain
            // selectable, but profile operations will correctly fail later.
            add_device(devices, count, iface, 0xFF, 0xFF, 0.0, inspect_features);
        }
    }
    return 1;
}

int discover_device_by_key(HidContext *context, const char *key, Device *devices, size_t *count) {
    *count = 0;
    uint64_t location_id = 0;
    uint64_t registry_id = 0;
    uint8_t device_number = 0;
    if (!parse_device_key(key, &location_id, &registry_id, &device_number)) {
        fprintf(stderr, "invalid device key '%s'\n", key == NULL ? "" : key);
        return 0;
    }
    for (size_t i = 0; i < context->count; i++) {
        HidInterface *iface = &context->items[i];
        if (!iface->is_vendor || iface->location_id != location_id ||
            iface->registry_id != registry_id) {
            continue;
        }
        if (!iface->channel_open && interface_needs_input_monitoring(iface) &&
            hid_check_access_impl(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted) {
            // A cached wired device can reach this keyed profile-read path
            // during the initial refresh. Keep that background read passive;
            // the GUI's explicit permission action is the only place that may
            // request Input Monitoring.
            return 1;
        }
        if (!iface->channel_open && !channel_open(&iface->channel, iface->device)) {
            return 1;
        }
        iface->channel_open = true;
        if (iface->product_id == 0xC24A && !is_receiver_interface(iface)) {
            add_device(devices, count, iface, 0xFF, 0xFF, 0.0, false);
            return 1;
        }
        double protocol = 0;
        uint8_t resolved_device_number = device_number;
        if (is_receiver_interface(iface) && device_number >= 1 &&
            device_number <= receiver_slot_limit(iface)) {
            Reply pairing_reply = receiver_register_read(
                iface, 0x02B5, true, (uint8_t)(RECEIVER_INFO_PAIRING + device_number - 1));
            bool pairing_present = receiver_pairing_reply_is_present(pairing_reply);
            if (ping_interface(iface, device_number, 1.0, &protocol, &resolved_device_number)) {
                if (pairing_present || protocol >= 2.0 || is_receiver_interface(iface)) {
                    size_t before = *count;
                    // This key came from a paired receiver slot. A successful
                    // slot probe can still be answered as HID++ 1.0 by the
                    // receiver, so keep the paired peripheral's 2.0 model
                    // when preparing its feature table.
                    double device_protocol =
                        pairing_present || is_receiver_interface(iface) ? 2.0 : protocol;
                    add_device(devices, count, iface, resolved_device_number, device_number,
                               device_protocol, true);
                    if (*count > before) {
                        receiver_slot_identity(&devices[*count - 1], device_number, pairing_reply);
                    }
                }
                return 1;
            }
            if (pairing_present) {
                add_receiver_slot_device(devices, count, iface, device_number, pairing_reply, true);
            }
            return 1;
        }
        if (ping_interface(iface, device_number, 1.0, &protocol, &resolved_device_number)) {
            add_device(devices, count, iface, resolved_device_number, device_number, protocol,
                       true);
        } else if (device_number != 0xFF && !is_receiver_interface(iface) &&
                   ping_interface(iface, 0xFF, 1.0, &protocol, &resolved_device_number)) {
            // The direct wireless HID endpoint may report its paired receiver
            // slot in response to an FF ping, while requiring FF as the
            // destination for all later feature calls.
            add_device(devices, count, iface, resolved_device_number, 0xFF, protocol, true);
        }
        return 1;
    }
    return 1;
}

int discover_devices_for_options_hardware(HidContext *context, const Options *options,
                                          Device *devices, size_t *count) {
    if (options->device_key != NULL) {
        return discover_device_by_key(context, options->device_key, devices, count);
    }
    return discover_devices(context, options->slot, devices, count, true);
}

// discover_devices_for_options_impl is a test seam: self-test overrides it to
// hand back a canned Device list so command-layer logic (run_info, run_dpi,
// run_bind, ...) can be exercised without real IOKit hardware. It complements
// channel_request_impl (see the HID transport module), which mocks
// the HID++ calls those commands make once a device is selected.
DiscoverDevicesForOptionsFn discover_devices_for_options_impl =
    discover_devices_for_options_hardware;

int discover_devices_for_options(HidContext *context, const Options *options, Device *devices,
                                 size_t *count) {
    return discover_devices_for_options_impl(context, options, devices, count);
}

const char *device_label(const Device *device) {
    if (device->name[0] != '\0') {
        return device->name;
    }
    // A receiver-backed slot is the paired peripheral, not the USB receiver
    // interface. Never expose the interface's generic product string as the
    // mouse name when the model-specific name read was unavailable.
    if (device->device_number != 0xFF && is_receiver_interface(device->iface)) {
        return "Paired Logitech mouse";
    }
    if (device->iface->product[0] != '\0') {
        return device->iface->product;
    }
    return "Logitech HID++ device";
}

uint32_t device_mouse_product_id(const Device *device) {
    if (device == NULL || device->iface == NULL) {
        return 0;
    }
    if (device->mouse_product_id != 0) {
        return device->mouse_product_id;
    }
    // Preserve sensible behavior for direct Device fixtures and older callers
    // that construct a Device manually, but never fall back to a receiver PID.
    return is_receiver_interface(device->iface) ? 0 : device->iface->product_id;
}

bool is_receiver_endpoint(const Device *device) {
    if (device == NULL || device->iface == NULL || device->device_number != 0xFF) {
        return false;
    }
    return is_receiver_interface(device->iface) ||
           text_contains_case_insensitive(device_label(device), "receiver") ||
           text_contains_case_insensitive(device->iface->product, "receiver") ||
           text_contains_case_insensitive(device_label(device), "unifying") ||
           text_contains_case_insensitive(device_label(device), "bolt");
}

bool is_mouse_device(const Device *device) {
    if (device == NULL || device->iface == NULL || is_receiver_endpoint(device)) {
        return false;
    }
    if (text_contains_case_insensitive(device_label(device), "keyboard") ||
        text_contains_case_insensitive(device_label(device), "keypad") ||
        text_contains_case_insensitive(device->iface->product, "keyboard") ||
        text_contains_case_insensitive(device->iface->product, "keypad")) {
        return false;
    }
    if (device->iface->is_mouse || device->iface->has_mouse_collection) {
        return true;
    }
    // A paired mouse may not have a standard mouse HID interface of its own;
    // these mouse-specific HID++ features still identify it as a mouse.
    if (device_feature_index(device, FEATURE_ONBOARD_PROFILES, &(uint8_t){0}) ||
        device_feature_index(device, FEATURE_ADJUSTABLE_DPI, &(uint8_t){0})) {
        return true;
    }
    // Receiver-backed slots are identified by the receiver pairing record.
    // The paired WPID is retained separately from the receiver PID, so an
    // uninspected slot can still be listed without treating every arbitrary
    // HID++ endpoint as a mouse.
    if (device->request_device_number != 0xFF && is_receiver_interface(device->iface)) {
        return device->mouse_product_id != 0;
    }
    // Some direct wireless/Bluetooth interfaces hide their standard mouse
    // collection from macOS. Their Logitech model-ID range is the remaining
    // positive eligibility signal; unknown wired HID++ endpoints are not.
    return is_wireless_device_product(device->iface->product_id) ||
           is_bluetooth_device_product(device->iface->product_id) ||
           device->iface->product_id == 0xC24A;
}

bool is_duplicate_direct_mouse_endpoint(const Device *candidate, const Device *devices,
                                        size_t count) {
    if (candidate == NULL || devices == NULL || is_receiver_interface(candidate->iface) ||
        !is_wireless_device_product(candidate->iface->product_id)) {
        return false;
    }
    for (size_t i = 0; i < count; i++) {
        const Device *other = &devices[i];
        if (other == candidate || other->device_number == 0xFF ||
            !is_receiver_interface(other->iface)) {
            continue;
        }
        if (strcmp(device_label(candidate), device_label(other)) == 0) {
            return true;
        }
    }
    return false;
}

static const char *receiver_connection_type(const HidInterface *iface) {
    if (iface == NULL) {
        return NULL;
    }
    switch (iface->product_id) {
    case 0xC548:
        return "Bolt";
    case 0xC52B:
    case 0xC532:
        return "Unifying";
    case 0xC539:
    case 0xC53A:
    case 0xC53D:
    case 0xC53F:
    case 0xC541:
    case 0xC545:
    case 0xC547:
    case 0xC54D:
        return "LIGHTSPEED";
    case 0xC517:
        return "EX100";
    case 0xC518:
    case 0xC51A:
    case 0xC51B:
    case 0xC521:
    case 0xC525:
    case 0xC526:
    case 0xC52E:
    case 0xC52F:
    case 0xC531:
    case 0xC534:
    case 0xC535:
    case 0xC537:
        return "Nano";
    default:
        break;
    }
    // Product IDs are the reliable path, but retain a readable fallback for
    // newer receiver IDs that macOS exposes only by product name.
    if (text_contains_case_insensitive(iface->product, "bolt")) {
        return "Bolt";
    }
    if (text_contains_case_insensitive(iface->product, "unifying")) {
        return "Unifying";
    }
    if (text_contains_case_insensitive(iface->product, "lightspeed")) {
        return "LIGHTSPEED";
    }
    if (text_contains_case_insensitive(iface->product, "nano")) {
        return "Nano";
    }
    return is_receiver_interface(iface) ? "Receiver" : NULL;
}

const char *device_connection(const Device *device) {
    const char *receiver_type = receiver_connection_type(device->iface);
    if (receiver_type != NULL &&
        (device->device_number != 0xFF || is_receiver_interface(device->iface))) {
        return receiver_type;
    }
    if (text_contains_case_insensitive(device->iface->transport, "bluetooth") ||
        is_bluetooth_device_product(device->iface->product_id)) {
        return "Bluetooth";
    }
    if (is_wireless_device_product(device->iface->product_id)) {
        return "Wireless";
    }
    return "Wired";
}

int hid_discovery_compare_interfaces_for_test(const HidInterface *left, const HidInterface *right) {
    return compare_hid_interfaces(left, right);
}

int hid_discovery_ping_interface_for_test(HidInterface *iface, uint8_t device_number,
                                          double timeout, double *protocol,
                                          uint8_t *resolved_device_number) {
    return ping_interface(iface, device_number, timeout, protocol, resolved_device_number);
}

int hid_discovery_discover_features_for_test(Device *device) { return discover_features(device); }

int hid_discovery_device_name_for_test(Device *device) { return device_name(device); }

bool hid_discovery_receiver_device_name_for_test(Device *device, uint8_t slot) {
    return receiver_device_name(device, slot);
}

uint8_t hid_discovery_receiver_slot_limit_for_test(const HidInterface *iface) {
    return receiver_slot_limit(iface);
}

Reply hid_discovery_receiver_register_read_for_test(HidInterface *iface, uint16_t register_id,
                                                    bool has_subregister, uint8_t subregister) {
    return receiver_register_read(iface, register_id, has_subregister, subregister);
}

void hid_discovery_log_receiver_register_reply_for_test(const HidInterface *iface,
                                                        uint16_t register_id, uint8_t subregister,
                                                        Reply reply) {
    log_receiver_register_reply(iface, register_id, subregister, reply);
}

void hid_discovery_receiver_slot_name_for_test(Device *device, uint8_t slot, Reply pairing_reply) {
    receiver_slot_name(device, slot, pairing_reply);
}

bool hid_discovery_add_receiver_slot_device_for_test(Device *devices, size_t *count,
                                                     HidInterface *iface, uint8_t slot,
                                                     Reply pairing_reply, bool inspect_features) {
    return add_receiver_slot_device(devices, count, iface, slot, pairing_reply, inspect_features);
}

int hid_discovery_add_device_for_test(Device *devices, size_t *count, HidInterface *iface,
                                      uint8_t device_number, uint8_t request_device_number,
                                      double protocol, bool inspect_features) {
    return add_device(devices, count, iface, device_number, request_device_number, protocol,
                      inspect_features);
}

const char *hid_discovery_receiver_connection_type_for_test(const HidInterface *iface) {
    return receiver_connection_type(iface);
}
