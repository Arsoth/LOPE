static int ping_interface(HidInterface *iface,
                          uint8_t device_number,
                          double timeout,
                          double *protocol,
                          uint8_t *resolved_device_number) {
    uint8_t params[3] = {0, 0, 0x5A};
    // A receiver advertises long reports, but routed slot probes follow the
    // short HID++ 1.0 path.  Try short first for receiver slots and retain a
    // long fallback for devices that require it.
    bool receiver = iface != NULL && is_receiver_product(iface->product_id);
    bool modes[2] = {
        receiver ? false : iface->prefer_long_reports,
        receiver ? iface->prefer_long_reports : false
    };
    size_t mode_count = modes[0] == modes[1] ? 1 : 2;
    for (size_t mode = 0; mode < mode_count; mode++) {
        Reply reply = channel_request(&iface->channel,
                                      device_number,
                                      (uint16_t)(0x0010 | SW_ID),
                                      params,
                                      sizeof(params),
                                      modes[mode],
                                      timeout);
        if (hid_debug_enabled()) {
            char line[512];
            int written = snprintf(line, sizeof(line),
                                   "hid-debug ping product=0x%04X location=0x%llX slot=0x%02X mode=%s status=%s error=0x%02X length=%zu reply-device=0x%02X",
                                   iface->product_id,
                                   (unsigned long long)iface->location_id,
                                   device_number,
                                   modes[mode] ? "long" : "short",
                                   reply_status_name(reply.status),
                                   reply.error_code,
                                   reply.length,
                                   reply.device_number);
            if (reply.length > 0) {
                if (written < (int)sizeof(line)) {
                    written += snprintf(line + written, sizeof(line) - (size_t)written, " bytes=");
                }
                for (size_t i = 0; i < reply.length && i < 8 && written < (int)sizeof(line); i++) {
                    written += snprintf(line + written, sizeof(line) - (size_t)written, "%02X", reply.bytes[i]);
                }
            }
            hid_debug_log("%s", line);
        }
        if (reply.status == REPLY_OK && reply.length >= 3 && reply.bytes[2] == 0x5A) {
            *protocol = (double)reply.bytes[0] + (double)reply.bytes[1] / 10.0;
            if (resolved_device_number != NULL) {
                *resolved_device_number = device_number == 0xFF &&
                                          reply.device_number >= 1 && reply.device_number <= 6
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

static Reply receiver_register_read(HidInterface *iface,
                                    uint16_t register_id,
                                    bool has_subregister,
                                    uint8_t subregister) {
    uint8_t params[1] = {subregister};
    return channel_request(&iface->channel,
                           0xFF,
                           (uint16_t)(0x8100 | (register_id & 0x02FF)),
                           has_subregister ? params : NULL,
                           has_subregister ? sizeof(params) : 0,
                           false,
                           1.0);
}

static void log_receiver_register_reply(const HidInterface *iface,
                                         uint16_t register_id,
                                         uint8_t subregister,
                                         Reply reply) {
    if (!hid_debug_enabled()) {
        return;
    }
    char line[512];
    int written = snprintf(line, sizeof(line),
                           "hid-debug receiver-register product=0x%04X location=0x%llX register=0x%04X sub=0x%02X status=%s error=0x%02X length=%zu bytes=",
                           iface->product_id,
                           (unsigned long long)iface->location_id,
                           register_id,
                           subregister,
                           reply_status_name(reply.status),
                           reply.error_code,
                           reply.length);
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

static int add_device(Device *devices,
                      size_t *count,
                      HidInterface *iface,
                      uint8_t device_number,
                      uint8_t request_device_number,
                      double protocol,
                      bool inspect_features);

static void receiver_device_name(Device *device, uint8_t slot) {
    Reply reply = receiver_register_read(device->iface,
                                         REGISTER_RECEIVER_INFO,
                                         true,
                                         (uint8_t)(RECEIVER_INFO_DEVICE_NAME + slot - 1));
    if (reply.status != REPLY_OK || reply.length < 2) {
        return;
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
    while (length > 0 && (device->name[length - 1] == '\0' ||
                          device->name[length - 1] == '\n' ||
                          device->name[length - 1] == '\r')) {
        device->name[--length] = '\0';
    }
}

static bool add_receiver_slot_device(Device *devices,
                                     size_t *count,
                                     HidInterface *iface,
                                     uint8_t slot,
                                     Reply pairing_reply,
                                     bool inspect_features) {
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
    if (device->name[0] == '\0') {
        receiver_device_name(device, slot);
    }
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
    // IOHIDDeviceOpen uses the HID-specific Input Monitoring permission.
    // The GUI previously requested only the CoreGraphics event-tap variant,
    // which can leave receiver interfaces denied even when the app appears
    // enabled in System Settings.
    IOHIDAccessType hid_access_before = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent);
    IOHIDAccessType hid_access_after = hid_access_before;
    bool hid_access_requested = false;
    if (hid_access_before != kIOHIDAccessTypeGranted) {
        hid_access_requested = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent);
        hid_access_after = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent);
    }
    if (hid_debug_enabled()) {
        hid_debug_log("hid-debug access before=%d requested=%d after=%d",
                      hid_access_before, hid_access_requested, hid_access_after);
    }
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
            bool hidpp_reports = device_has_hidpp_reports(device);
            // A receiver exposes separate mouse, keyboard, and vendor HID
            // interfaces with the same product ID. Do not let the known
            // receiver PID fallback turn the first two into HID++ channels;
            // the descriptor/usage-page check identifies the real vendor
            // interface. The fallback remains necessary for direct wireless
            // and Bluetooth devices whose HID++ descriptor is hidden by macOS.
            bool known_device_fallback = is_known_hidpp_product(product_id) &&
                                         !is_receiver_product(product_id);
            bool vendor = page == HIDPP_USAGE_PAGE || hidpp_reports ||
                          known_device_fallback;
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
            item->prefer_long_reports = hidpp_reports || is_known_hidpp_product(product_id);
            string_property(device, CFSTR(kIOHIDProductKey), item->product, sizeof(item->product));
            string_property(device, CFSTR(kIOHIDTransportKey), item->transport, sizeof(item->transport));
            hid_debug_log("hid-debug interface product=0x%04X location=0x%llX registry=0x%llX page=0x%04X usage=0x%04X vendor=%d mouse=%d hidpp=%d product-name=%s",
                          item->product_id,
                          (unsigned long long)item->location_id,
                          (unsigned long long)item->registry_id,
                          item->usage_page,
                          item->usage,
                          item->is_vendor,
                          item->is_mouse,
                          hidpp_reports,
                          item->product);
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

static int add_device(Device *devices,
                      size_t *count,
                      HidInterface *iface,
                      uint8_t device_number,
                      uint8_t request_device_number,
                      double protocol,
                      bool inspect_features) {
    if (*count >= MAX_DEVICES) {
        return 0;
    }
    Device *device = &devices[(*count)++];
    memset(device, 0, sizeof(*device));
    device->iface = iface;
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
    return iface != NULL &&
           (is_receiver_product(iface->product_id) ||
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

static bool is_receiver_endpoint(const Device *device);
static bool is_mouse_device(const Device *device);
static bool is_duplicate_direct_mouse_endpoint(const Device *candidate,
                                               const Device *devices,
                                               size_t count);

static void format_device_key(const Device *device, char *out, size_t out_size) {
    snprintf(out, out_size, "%" PRIx64 "-%" PRIx64 "-%02X",
             device->iface->location_id, device->iface->registry_id,
             device->request_device_number);
}

static bool parse_device_key(const char *text,
                             uint64_t *location_id,
                             uint64_t *registry_id,
                             uint8_t *device_number) {
    unsigned long long parsed_location = 0;
    unsigned long long parsed_registry = 0;
    unsigned int parsed_device = 0;
    char trailing = '\0';
    if (text == NULL ||
        sscanf(text, "%llx-%llx-%x%c",
               &parsed_location, &parsed_registry, &parsed_device, &trailing) != 3 ||
        parsed_device > UINT8_MAX) {
        return false;
    }
    *location_id = (uint64_t)parsed_location;
    *registry_id = (uint64_t)parsed_registry;
    *device_number = (uint8_t)parsed_device;
    return true;
}

static int discover_devices(HidContext *context,
                            int requested_slot,
                            Device *devices,
                            size_t *count,
                            bool inspect_features) {
    *count = 0;
    open_vendor_channels(context);
    for (size_t i = 0; i < context->count; i++) {
        HidInterface *iface = &context->items[i];
        if (!iface->is_vendor) {
            continue;
        }
        // A standard mouse collection is enough to identify a direct mouse
        // even when macOS blocks its separate HID++ vendor channel. Keep it
        // in the device picker so the UI can accurately report that profiles
        // are unavailable, rather than silently dropping the mouse.
        if (!iface->channel_open) {
            if (iface->is_mouse && !is_receiver_interface(iface)) {
                add_device(devices, count, iface, 0xFF, 0xFF, 0.0, inspect_features);
            }
            continue;
        }
        if (requested_slot >= 0) {
            double protocol = 0;
            uint8_t resolved_device_number = (uint8_t)requested_slot;
            if (ping_interface(iface, (uint8_t)requested_slot,
                               1.0,
                               &protocol, &resolved_device_number)) {
                add_device(devices, count, iface, resolved_device_number,
                           (uint8_t)requested_slot, protocol, inspect_features);
            }
            continue;
        }
        if (is_receiver_interface(iface)) {
            for (uint8_t slot = 1; slot <= receiver_slot_limit(iface); slot++) {
                Reply pairing_reply = receiver_register_read(iface, 0x02B5, true,
                                                              (uint8_t)(0x20 + slot - 1));
                log_receiver_register_reply(iface, 0x02B5,
                                            (uint8_t)(0x20 + slot - 1),
                                            pairing_reply);
                if (receiver_pairing_reply_is_present(pairing_reply)) {
                    // Pairing information is more reliable than a routed ping:
                    // a sleeping or busy mouse can return RESOURCE_ERROR even
                    // though it is paired and its HID++ endpoint is usable.
                    add_receiver_slot_device(devices, count, iface, slot,
                                             pairing_reply, inspect_features);
                    continue;
                }
                double protocol = 0;
                uint8_t resolved_device_number = slot;
                if (ping_interface(iface, slot, 1.0, &protocol, &resolved_device_number)) {
                    add_device(devices, count, iface, resolved_device_number, slot,
                               protocol, inspect_features);
                }
            }
        }
        double protocol = 0;
        uint8_t resolved_device_number = 0xFF;
        if (ping_interface(iface, 0xFF, 1.0, &protocol, &resolved_device_number)) {
            // A receiver can echo a paired slot in response to the broadcast
            // ping. Keep that endpoint marked as FF so the receiver itself is
            // still filtered from the mouse list; slot discovery above owns
            // the paired mouse entry.
            uint8_t reported_device_number = is_receiver_interface(iface)
                ? 0xFF
                : resolved_device_number;
            add_device(devices, count, iface, reported_device_number, 0xFF,
                       protocol, inspect_features);
        } else if (iface->is_mouse && !is_receiver_interface(iface)) {
            // Bluetooth and some direct wireless mice expose a normal mouse
            // collection even when HID++ ping is unavailable. They remain
            // selectable, but profile operations will correctly fail later.
            add_device(devices, count, iface, 0xFF, 0xFF, 0.0, inspect_features);
        }
    }
    return 1;
}

static int discover_device_by_key(HidContext *context,
                                  const char *key,
                                  Device *devices,
                                  size_t *count) {
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
        if (!iface->is_vendor ||
            iface->location_id != location_id ||
            iface->registry_id != registry_id) {
            continue;
        }
        if (!iface->channel_open && !channel_open(&iface->channel, iface->device)) {
            return 1;
        }
        iface->channel_open = true;
        double protocol = 0;
        uint8_t resolved_device_number = device_number;
        if (is_receiver_interface(iface) && device_number >= 1 &&
            device_number <= receiver_slot_limit(iface)) {
            Reply pairing_reply = receiver_register_read(
                iface, 0x02B5, true,
                (uint8_t)(RECEIVER_INFO_PAIRING + device_number - 1));
            if (receiver_pairing_reply_is_present(pairing_reply)) {
                // Match the list path: pairing presence is authoritative even
                // when a routed ping reports RESOURCE_ERROR for a sleeping
                // G603/G604.
                add_receiver_slot_device(devices, count, iface, device_number,
                                         pairing_reply, true);
                return 1;
            }
        }
        if (ping_interface(iface, device_number, 1.0, &protocol, &resolved_device_number)) {
            add_device(devices, count, iface, resolved_device_number, device_number,
                       protocol, true);
        } else if (device_number != 0xFF && !is_receiver_interface(iface) &&
                   ping_interface(iface, 0xFF, 1.0, &protocol, &resolved_device_number)) {
            // The direct wireless HID endpoint may report its paired receiver
            // slot in response to an FF ping, while requiring FF as the
            // destination for all later feature calls.
            add_device(devices, count, iface, resolved_device_number, 0xFF,
                       protocol, true);
        }
        return 1;
    }
    return 1;
}

static int discover_devices_for_options(HidContext *context,
                                         const Options *options,
                                         Device *devices,
                                         size_t *count) {
    if (options->device_key != NULL) {
        return discover_device_by_key(context, options->device_key, devices, count);
    }
    return discover_devices(context, options->slot, devices, count, true);
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

static bool is_duplicate_direct_mouse_endpoint(const Device *candidate,
                                               const Device *devices,
                                               size_t count) {
    if (candidate == NULL || devices == NULL ||
        is_receiver_interface(candidate->iface) ||
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

static const char *device_connection(const Device *device) {
    if (device->device_number != 0xFF || is_receiver_product(device->iface->product_id) ||
        is_wireless_device_product(device->iface->product_id)) {
        return "Receiver";
    }
    if (text_contains_case_insensitive(device->iface->transport, "bluetooth") ||
        is_bluetooth_device_product(device->iface->product_id)) {
        return "Bluetooth";
    }
    return "Wired";
}
