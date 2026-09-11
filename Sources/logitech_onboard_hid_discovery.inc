static int ping_interface(HidInterface *iface,
                          uint8_t device_number,
                          double timeout,
                          double *protocol,
                          uint8_t *resolved_device_number) {
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
        if (resolved_device_number != NULL) {
            *resolved_device_number = device_number == 0xFF &&
                                      reply.device_number >= 1 && reply.device_number <= 6
                ? reply.device_number
                : device_number;
        }
        return 1;
    }
    // A HID++ 1.0 receiver answers the 2.0-style ping with invalid-sub-id.
    // It is useful to list that receiver, but it cannot edit a 0x8100 profile.
    if (reply.status == REPLY_HIDPP10_ERROR && reply.error_code == 0x01) {
        *protocol = 1.0;
        if (resolved_device_number != NULL) {
            *resolved_device_number = device_number;
        }
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
            bool vendor = page == HIDPP_USAGE_PAGE || device_has_hidpp_reports(device) ||
                          is_known_hidpp_product(product_id);
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

static int add_device(Device *devices,
                      size_t *count,
                      HidInterface *iface,
                      uint8_t device_number,
                      uint8_t request_device_number,
                      double protocol) {
    if (*count >= MAX_DEVICES) {
        return 0;
    }
    Device *device = &devices[(*count)++];
    memset(device, 0, sizeof(*device));
    device->iface = iface;
    device->device_number = device_number;
    device->request_device_number = request_device_number;
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
    // they had receiver slots. A few macOS HID interfaces report product ID
    // zero, so retain the product-name fallback for those receivers.
    return iface != NULL &&
           (is_receiver_product(iface->product_id) ||
            text_contains_case_insensitive(iface->product, "receiver") ||
            text_contains_case_insensitive(iface->product, "unifying") ||
            text_contains_case_insensitive(iface->product, "bolt"));
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

static int discover_devices(HidContext *context, int requested_slot, Device *devices, size_t *count) {
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
                add_device(devices, count, iface, 0xFF, 0xFF, 0.0);
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
                           (uint8_t)requested_slot, protocol);
            }
            continue;
        }
        if (is_receiver_interface(iface)) {
            for (uint8_t slot = 1; slot <= 6; slot++) {
                double protocol = 0;
                uint8_t resolved_device_number = slot;
                if (ping_interface(iface, slot, 1.0, &protocol, &resolved_device_number)) {
                    add_device(devices, count, iface, resolved_device_number, slot, protocol);
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
            add_device(devices, count, iface, reported_device_number, 0xFF, protocol);
        } else if (iface->is_mouse && !is_receiver_interface(iface)) {
            // Bluetooth and some direct wireless mice expose a normal mouse
            // collection even when HID++ ping is unavailable. They remain
            // selectable, but profile operations will correctly fail later.
            add_device(devices, count, iface, 0xFF, 0xFF, 0.0);
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
    open_vendor_channels(context);
    for (size_t i = 0; i < context->count; i++) {
        HidInterface *iface = &context->items[i];
        if (!iface->is_vendor || !iface->channel_open ||
            iface->location_id != location_id ||
            iface->registry_id != registry_id) {
            continue;
        }
        double protocol = 0;
        uint8_t resolved_device_number = device_number;
        if (ping_interface(iface, device_number, 1.0, &protocol, &resolved_device_number)) {
            add_device(devices, count, iface, resolved_device_number, device_number, protocol);
        } else if (device_number != 0xFF && !is_receiver_interface(iface) &&
                   ping_interface(iface, 0xFF, 1.0, &protocol, &resolved_device_number)) {
            // The direct wireless HID endpoint may report its paired receiver
            // slot in response to an FF ping, while requiring FF as the
            // destination for all later feature calls.
            add_device(devices, count, iface, resolved_device_number, 0xFF, protocol);
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
    return discover_devices(context, options->slot, devices, count);
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

