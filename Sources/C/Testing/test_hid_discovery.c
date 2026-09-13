#include "internal.h"
#include "test_doubles.h"

typedef struct {
    uint32_t vendor_id;
    uint32_t usage_page;
    uint32_t usage;
    uint32_t product_id;
    uint32_t location_id;
    uint64_t registry_id;
    const char *product;
    const char *transport;
    CFDataRef descriptor;
} DiscoveryDeviceSpec;

static DiscoveryDeviceSpec *g_discovery_device_specs;
static size_t g_discovery_device_count;
static CFIndex g_discovery_set_count;
static int g_discovery_manager_mode;
static size_t g_discovery_manager_close_calls;
static size_t g_discovery_release_calls;
static IOReturn g_discovery_channel_open_result;

static DiscoveryDeviceSpec *discovery_spec_for_device(IOHIDDeviceRef device) {
    uintptr_t value = (uintptr_t)device;
    if (value == 0 || value > g_discovery_device_count) {
        return NULL;
    }
    return &g_discovery_device_specs[value - 1];
}

static CFTypeRef discovery_property_double(IOHIDDeviceRef device, CFStringRef key) {
    DiscoveryDeviceSpec *spec = discovery_spec_for_device(device);
    if (spec == NULL) {
        return NULL;
    }
    uint32_t number = 0;
    if (CFEqual(key, CFSTR(kIOHIDVendorIDKey))) {
        number = spec->vendor_id;
    } else if (CFEqual(key, CFSTR(kIOHIDPrimaryUsagePageKey))) {
        number = spec->usage_page;
    } else if (CFEqual(key, CFSTR(kIOHIDPrimaryUsageKey))) {
        number = spec->usage;
    } else if (CFEqual(key, CFSTR(kIOHIDProductIDKey))) {
        number = spec->product_id;
    } else if (CFEqual(key, CFSTR(kIOHIDLocationIDKey))) {
        number = spec->location_id;
    } else if (CFEqual(key, CFSTR(kIOHIDReportDescriptorKey))) {
        return spec->descriptor;
    } else if (CFEqual(key, CFSTR(kIOHIDProductKey))) {
        return spec->product == NULL ? NULL
                                     : CFStringCreateWithCString(kCFAllocatorDefault, spec->product,
                                                                 kCFStringEncodingUTF8);
    } else if (CFEqual(key, CFSTR(kIOHIDTransportKey))) {
        return spec->transport == NULL
                   ? NULL
                   : CFStringCreateWithCString(kCFAllocatorDefault, spec->transport,
                                               kCFStringEncodingUTF8);
    } else {
        return NULL;
    }
    int32_t signed_number = (int32_t)number;
    return CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &signed_number);
}

static io_service_t discovery_service_double(IOHIDDeviceRef device) {
    return discovery_spec_for_device(device) == NULL ? IO_OBJECT_NULL : (io_service_t)1;
}

static kern_return_t discovery_registry_id_double(io_registry_entry_t service,
                                                  uint64_t *registry_id) {
    (void)service;
    *registry_id = UINT64_C(0xABC00000) + g_discovery_manager_close_calls;
    return KERN_SUCCESS;
}

static CFArrayRef discovery_elements_double(IOHIDDeviceRef device, CFDictionaryRef matching,
                                            IOOptionBits options) {
    (void)device;
    (void)matching;
    (void)options;
    return NULL;
}

static IOHIDAccessType discovery_check_access_double(IOHIDRequestType request_type) {
    (void)request_type;
    return (IOHIDAccessType)0;
}

static IOHIDManagerRef discovery_manager_create_double(CFAllocatorRef allocator,
                                                       IOOptionBits options) {
    (void)allocator;
    (void)options;
    return g_discovery_manager_mode == 1 ? NULL : (IOHIDManagerRef)(uintptr_t)0x11;
}

static void discovery_manager_set_matching_double(IOHIDManagerRef manager,
                                                  CFDictionaryRef matching) {
    (void)manager;
    (void)matching;
}

static CFSetRef discovery_manager_copy_devices_double(IOHIDManagerRef manager) {
    (void)manager;
    return g_discovery_manager_mode == 2 ? NULL : (CFSetRef)(uintptr_t)0x22;
}

static CFIndex discovery_set_get_count_double(CFSetRef set) {
    (void)set;
    return g_discovery_set_count;
}

static void discovery_set_get_values_double(CFSetRef set, const void **values) {
    (void)set;
    for (size_t i = 0; i < g_discovery_device_count; i++) {
        values[i] = (const void *)(uintptr_t)(i + 1);
    }
}

static IOReturn discovery_manager_close_double(IOHIDManagerRef manager, IOOptionBits options) {
    (void)manager;
    (void)options;
    g_discovery_manager_close_calls++;
    return kIOReturnSuccess;
}

static void discovery_release_double(CFTypeRef value) {
    (void)value;
    g_discovery_release_calls++;
}

static IOReturn discovery_channel_open_double(IOHIDDeviceRef device, IOOptionBits options) {
    (void)device;
    (void)options;
    return g_discovery_channel_open_result;
}

static IOReturn discovery_channel_close_double(IOHIDDeviceRef device, IOOptionBits options) {
    (void)device;
    (void)options;
    return kIOReturnSuccess;
}

static void discovery_channel_callback_double(IOHIDDeviceRef device, uint8_t *report,
                                              CFIndex report_length, IOHIDReportCallback callback,
                                              void *context) {
    (void)device;
    (void)report;
    (void)report_length;
    (void)callback;
    (void)context;
}

static void discovery_channel_schedule_double(IOHIDDeviceRef device, CFRunLoopRef run_loop,
                                              CFStringRef mode) {
    (void)device;
    (void)run_loop;
    (void)mode;
}

static void reset_discovery_seams(void) {
    hid_check_access_impl = IOHIDCheckAccess;
    hid_manager_create_impl = IOHIDManagerCreate;
    hid_manager_set_device_matching_impl = IOHIDManagerSetDeviceMatching;
    hid_manager_copy_devices_impl = IOHIDManagerCopyDevices;
    hid_set_get_count_impl = CFSetGetCount;
    hid_set_get_values_impl = CFSetGetValues;
    hid_manager_close_impl = IOHIDManagerClose;
    hid_cf_release_impl = CFRelease;
    hid_device_open_impl = IOHIDDeviceOpen;
    hid_device_close_impl = IOHIDDeviceClose;
    hid_device_register_input_report_callback_impl = IOHIDDeviceRegisterInputReportCallback;
    hid_device_schedule_with_run_loop_impl = IOHIDDeviceScheduleWithRunLoop;
    hid_device_unschedule_from_run_loop_impl = IOHIDDeviceUnscheduleFromRunLoop;
    hid_device_set_report_impl = IOHIDDeviceSetReport;
    hid_device_get_report_impl = IOHIDDeviceGetReport;
    hid_device_get_property_impl = IOHIDDeviceGetProperty;
    hid_device_get_service_impl = IOHIDDeviceGetService;
    hid_registry_entry_get_id_impl = IORegistryEntryGetRegistryEntryID;
    hid_device_copy_matching_elements_impl = IOHIDDeviceCopyMatchingElements;
    hid_array_get_count_impl = CFArrayGetCount;
    hid_array_get_value_at_index_impl = CFArrayGetValueAtIndex;
    hid_element_get_usage_page_impl = IOHIDElementGetUsagePage;
    hid_element_get_report_id_impl = IOHIDElementGetReportID;
    hid_debug_file_open_impl = fopen;
}

int test_hid_discovery(void) {
    Reply g603_pairing = {0};
    g603_pairing.status = REPLY_OK;
    g603_pairing.length = 8;
    g603_pairing.bytes[3] = 0x40;
    g603_pairing.bytes[4] = 0x6C;
    Reply unknown_pairing = g603_pairing;
    unknown_pairing.bytes[3] = 0x40;
    unknown_pairing.bytes[4] = 0x00;
    Reply short_pairing = g603_pairing;
    short_pairing.length = 4;
    Reply error_pairing = g603_pairing;
    error_pairing.status = REPLY_TIMEOUT;
    if (strcmp(receiver_pairing_model_name(g603_pairing), "G603 LIGHTSPEED") != 0 ||
        receiver_pairing_model_name(unknown_pairing) != NULL ||
        receiver_pairing_model_name(short_pairing) != NULL ||
        receiver_pairing_model_name(error_pairing) != NULL) {
        fprintf(stderr, "receiver model-name fallback self-test failed\n");
        return 1;
    }

    HidInterface connection_interface = {0};
    Device connection_device = {0};
    connection_device.iface = &connection_interface;
    connection_device.device_number = 1;
    connection_interface.product_id = 0xC539;
    bool connection_types_ok = strcmp(device_connection(&connection_device), "LIGHTSPEED") == 0;
    connection_interface.product_id = 0xC548;
    connection_types_ok =
        connection_types_ok && strcmp(device_connection(&connection_device), "Bolt") == 0;
    connection_interface.product_id = 0xC52B;
    connection_types_ok =
        connection_types_ok && strcmp(device_connection(&connection_device), "Unifying") == 0;
    connection_interface.product_id = 0xC532;
    connection_types_ok =
        connection_types_ok && strcmp(device_connection(&connection_device), "Unifying") == 0;
    const uint32_t nano_ids[] = {0xC518, 0xC51A, 0xC51B, 0xC521, 0xC525, 0xC526,
                                 0xC52E, 0xC52F, 0xC531, 0xC534, 0xC535, 0xC537};
    for (size_t i = 0; i < sizeof(nano_ids) / sizeof(nano_ids[0]); i++) {
        connection_interface.product_id = nano_ids[i];
        connection_types_ok =
            connection_types_ok && strcmp(device_connection(&connection_device), "Nano") == 0;
    }
    connection_interface.product_id = 0xC517;
    connection_types_ok =
        connection_types_ok && strcmp(device_connection(&connection_device), "EX100") == 0;
    connection_interface.product_id = 0xC599;
    connection_types_ok =
        connection_types_ok && strcmp(device_connection(&connection_device), "Receiver") == 0;
    connection_interface.product_id = 0;
    snprintf(connection_interface.product, sizeof(connection_interface.product),
             "New Bolt Receiver");
    connection_types_ok =
        connection_types_ok && strcmp(device_connection(&connection_device), "Bolt") == 0;
    snprintf(connection_interface.product, sizeof(connection_interface.product),
             "New Unifying Receiver");
    connection_types_ok =
        connection_types_ok && strcmp(device_connection(&connection_device), "Unifying") == 0;
    snprintf(connection_interface.product, sizeof(connection_interface.product),
             "New LIGHTSPEED Receiver");
    connection_types_ok =
        connection_types_ok && strcmp(device_connection(&connection_device), "LIGHTSPEED") == 0;
    snprintf(connection_interface.product, sizeof(connection_interface.product),
             "New Nano Receiver");
    connection_types_ok =
        connection_types_ok && strcmp(device_connection(&connection_device), "Nano") == 0;
    connection_interface.product[0] = '\0';
    connection_interface.product_id = 0;
    connection_types_ok =
        connection_types_ok && hid_discovery_receiver_connection_type_for_test(NULL) == NULL &&
        hid_discovery_receiver_connection_type_for_test(&connection_interface) == NULL;
    snprintf(connection_interface.transport, sizeof(connection_interface.transport), "Bluetooth");
    connection_interface.product_id = 0xB034;
    connection_types_ok =
        connection_types_ok && strcmp(device_connection(&connection_device), "Bluetooth") == 0;
    connection_interface.transport[0] = '\0';
    connection_types_ok =
        connection_types_ok && strcmp(device_connection(&connection_device), "Bluetooth") == 0;
    connection_interface.product_id = 0x4085;
    connection_types_ok =
        connection_types_ok && strcmp(device_connection(&connection_device), "Wireless") == 0;
    connection_interface.product_id = 0x1234;
    connection_types_ok =
        connection_types_ok && strcmp(device_connection(&connection_device), "Wired") == 0;
    const uint32_t additional_lightspeed_ids[] = {0xC53A, 0xC53D, 0xC53F, 0xC541,
                                                  0xC545, 0xC547, 0xC54D};
    for (size_t i = 0; i < sizeof(additional_lightspeed_ids) / sizeof(additional_lightspeed_ids[0]);
         i++) {
        connection_interface.product_id = additional_lightspeed_ids[i];
        connection_types_ok =
            connection_types_ok &&
            strcmp(hid_discovery_receiver_connection_type_for_test(&connection_interface),
                   "LIGHTSPEED") == 0;
    }
    if (!connection_types_ok) {
        fprintf(stderr, "receiver connection-type self-test failed\n");
        return 1;
    }

    // discover_devices() is exercised directly (bypassing hid_context_create's
    // real IOKit enumeration) by hand-building a HidContext whose interfaces
    // are already marked channel_open, which makes open_vendor_channels()
    // skip them without touching real hardware; channel_request_impl still
    // supplies the HID++ ping/pairing replies.
    HidInterface discover_direct_interface = {0};
    discover_direct_interface.is_vendor = true;
    discover_direct_interface.channel_open = true;
    discover_direct_interface.product_id = 0xC099;

    HidInterface discover_g600_interface = {0};
    discover_g600_interface.is_vendor = true;
    discover_g600_interface.channel_open = true;
    discover_g600_interface.product_id = G600_PRODUCT_ID;

    HidContext discover_context;
    memset(&discover_context, 0, sizeof(discover_context));
    HidInterface discover_items[2] = {discover_direct_interface, discover_g600_interface};
    discover_context.items = discover_items;
    discover_context.count = 2;

    Reply discover_ping_ok_reply = {.status = REPLY_OK, .length = 3, .bytes = {0x02, 0x00, 0x5A}};
    ChannelRequestTestContext discover_ping_context = {
        .replies = &discover_ping_ok_reply, .reply_count = 1, .calls = 0};
    channel_request_impl = channel_request_test_double;
    g_channel_request_test_context = &discover_ping_context;

    Device discover_devices_out[MAX_DEVICES];
    size_t discover_count = 0;
    bool discover_ok =
        discover_devices(&discover_context, -1, discover_devices_out, &discover_count, false) &&
        discover_count == 2 && discover_devices_out[0].protocol == 2.0 &&
        discover_devices_out[0].device_number == 0xFF &&
        discover_devices_out[1].iface == &discover_items[1] &&
        discover_devices_out[1].device_number == 0xFF;

    Reply discover_ping_fail_reply = {.status = REPLY_TIMEOUT};
    ChannelRequestTestContext discover_ping_fail_context = {
        .replies = &discover_ping_fail_reply, .reply_count = 1, .calls = 0};
    g_channel_request_test_context = &discover_ping_fail_context;
    HidInterface discover_unresponsive_interface = {0};
    discover_unresponsive_interface.is_vendor = true;
    discover_unresponsive_interface.channel_open = true;
    discover_unresponsive_interface.product_id = 0xC099;
    HidContext discover_unresponsive_context;
    memset(&discover_unresponsive_context, 0, sizeof(discover_unresponsive_context));
    discover_unresponsive_context.items = &discover_unresponsive_interface;
    discover_unresponsive_context.count = 1;
    size_t discover_unresponsive_count = 0;
    Device discover_unresponsive_devices[MAX_DEVICES];
    discover_ok =
        discover_ok &&
        discover_devices(&discover_unresponsive_context, -1, discover_unresponsive_devices,
                         &discover_unresponsive_count, false) &&
        discover_unresponsive_count == 0;
    HidInterface discover_closed_direct_mouse = {
        .is_vendor = true, .channel_open = true, .is_mouse = true, .product_id = 0x4085};
    HidContext discover_closed_direct_context = {.items = &discover_closed_direct_mouse,
                                                 .count = 1};
    ChannelRequestTestContext discover_closed_direct_test = {.replies = &discover_ping_fail_reply,
                                                             .reply_count = 1};
    g_channel_request_test_context = &discover_closed_direct_test;
    size_t discover_closed_direct_count = 0;
    Device discover_closed_direct_devices[MAX_DEVICES];
    discover_ok =
        discover_ok &&
        discover_devices(&discover_closed_direct_context, -1, discover_closed_direct_devices,
                         &discover_closed_direct_count, false) &&
        discover_closed_direct_count == 1 && discover_closed_direct_devices[0].protocol == 0.0;
    if (!discover_ok) {
        fprintf(stderr, "discover_devices self-test failed\n");
        return 1;
    }

    Reply discover_key_ping_reply = {.status = REPLY_OK, .length = 3, .bytes = {0x02, 0x00, 0x5A}};
    ChannelRequestTestContext discover_key_context = {
        .replies = &discover_key_ping_reply, .reply_count = 1, .calls = 0};
    g_channel_request_test_context = &discover_key_context;
    HidInterface discover_key_interface = {0};
    discover_key_interface.is_vendor = true;
    discover_key_interface.channel_open = true;
    discover_key_interface.product_id = 0xC099;
    discover_key_interface.location_id = 0x1234;
    discover_key_interface.registry_id = 0x5678;
    HidContext discover_key_hid_context;
    memset(&discover_key_hid_context, 0, sizeof(discover_key_hid_context));
    discover_key_hid_context.items = &discover_key_interface;
    discover_key_hid_context.count = 1;
    Device discover_key_devices[MAX_DEVICES];
    size_t discover_key_count = 0;
    bool discover_by_key_ok = discover_device_by_key(&discover_key_hid_context, "1234-5678-ff",
                                                     discover_key_devices, &discover_key_count) &&
                              discover_key_count == 1 && discover_key_devices[0].protocol == 2.0;

    size_t discover_bad_key_count = 0;
    discover_by_key_ok = discover_by_key_ok &&
                         discover_device_by_key(&discover_key_hid_context, "not-a-key",
                                                discover_key_devices, &discover_bad_key_count) == 0;
    discover_by_key_ok = discover_by_key_ok &&
                         discover_device_by_key(&discover_key_hid_context, NULL,
                                                discover_key_devices, &discover_bad_key_count) == 0;
    HidInterface key_non_vendor = {.location_id = 0x1234, .registry_id = 0x5678};
    HidInterface key_wrong_location = {
        .is_vendor = true, .location_id = 0x9999, .registry_id = 0x5678};
    HidInterface key_wrong_registry = {
        .is_vendor = true, .location_id = 0x1234, .registry_id = 0x9999};
    HidInterface key_mismatch_items[] = {key_non_vendor, key_wrong_location, key_wrong_registry};
    HidContext key_mismatch_context = {
        .items = key_mismatch_items,
        .count = sizeof(key_mismatch_items) / sizeof(key_mismatch_items[0]),
    };
    discover_by_key_ok =
        discover_by_key_ok &&
        discover_device_by_key(&key_mismatch_context, "1234-5678-01", discover_key_devices,
                               &discover_bad_key_count) == 1 &&
        discover_bad_key_count == 0;
    if (!discover_by_key_ok) {
        fprintf(stderr, "discover_device_by_key self-test failed\n");
        return 1;
    }

    HidInterface receiver_interface = {0};
    receiver_interface.is_vendor = true;
    receiver_interface.channel_open = true;
    receiver_interface.product_id = 0xC539;
    snprintf(receiver_interface.product, sizeof(receiver_interface.product), "G603 receiver");
    HidContext receiver_context = {.items = &receiver_interface, .count = 1};
    Reply receiver_pairing = {
        .status = REPLY_OK, .length = 8, .bytes = {0, 0, 0, 0x40, 0x6C, 0, 0, 1}};
    Reply receiver_slot_replies[] = {
        receiver_pairing,          {.status = REPLY_TIMEOUT}, {.status = REPLY_TIMEOUT},
        {.status = REPLY_TIMEOUT}, {.status = REPLY_TIMEOUT},
    };
    ChannelRequestTestContext receiver_test_context = {
        .replies = receiver_slot_replies,
        .reply_count = sizeof(receiver_slot_replies) / sizeof(receiver_slot_replies[0]),
    };
    g_channel_request_test_context = &receiver_test_context;
    Device receiver_devices[MAX_DEVICES];
    size_t receiver_count = 0;
    bool receiver_ok =
        discover_devices(&receiver_context, -1, receiver_devices, &receiver_count, false) &&
        receiver_count == 1 && receiver_devices[0].device_number == 1 &&
        receiver_devices[0].request_device_number == 1 &&
        strcmp(device_label(&receiver_devices[0]), "G603 LIGHTSPEED") == 0 &&
        is_mouse_device(&receiver_devices[0]) && receiver_test_context.calls == 5;
    Device receiver_endpoint = {
        .iface = &receiver_interface, .device_number = 0xFF, .request_device_number = 0xFF};
    receiver_ok = receiver_ok && is_receiver_endpoint(&receiver_endpoint) &&
                  !is_mouse_device(&receiver_endpoint);

    Reply receiver_ping_reply = {.status = REPLY_OK, .length = 3, .bytes = {0x02, 0x00, 0x5A}};
    Reply receiver_present_replies[] = {receiver_pairing, receiver_ping_reply};
    ChannelRequestTestContext receiver_present_context = {
        .replies = receiver_present_replies,
        .reply_count = sizeof(receiver_present_replies) / sizeof(receiver_present_replies[0]),
    };
    g_channel_request_test_context = &receiver_present_context;
    receiver_count = 0;
    receiver_ok =
        receiver_ok &&
        discover_devices(&receiver_context, -1, receiver_devices, &receiver_count, false) &&
        receiver_count == 1 && receiver_devices[0].protocol == 2.0 &&
        strcmp(device_label(&receiver_devices[0]), "G603 LIGHTSPEED") == 0;

    Reply receiver_unpaired_replies[] = {error_pairing, receiver_ping_reply};
    ChannelRequestTestContext receiver_unpaired_context = {
        .replies = receiver_unpaired_replies,
        .reply_count = sizeof(receiver_unpaired_replies) / sizeof(receiver_unpaired_replies[0]),
    };
    g_channel_request_test_context = &receiver_unpaired_context;
    receiver_count = 0;
    receiver_ok =
        receiver_ok &&
        discover_devices(&receiver_context, -1, receiver_devices, &receiver_count, false) &&
        receiver_count == 1 && receiver_devices[0].protocol == 2.0;

    ChannelRequestTestContext receiver_empty_context = {.replies = &error_pairing,
                                                        .reply_count = 1};
    g_channel_request_test_context = &receiver_empty_context;
    receiver_count = 0;
    receiver_ok =
        receiver_ok &&
        discover_devices(&receiver_context, -1, receiver_devices, &receiver_count, false) &&
        receiver_count == 0;

    HidInterface non_vendor_interface = {0};
    HidContext non_vendor_context = {.items = &non_vendor_interface, .count = 1};
    receiver_ok =
        receiver_ok &&
        discover_devices(&non_vendor_context, -1, receiver_devices, &receiver_count, false) &&
        receiver_count == 0;

    Device unnamed_receiver = {.iface = &receiver_interface, .device_number = 1};
    Device unnamed_direct = {.iface = &discover_direct_interface, .device_number = 0xFF};
    snprintf(discover_direct_interface.product, sizeof(discover_direct_interface.product),
             "Direct Mouse");
    Device named_device = {.iface = &discover_direct_interface, .device_number = 0xFF};
    snprintf(named_device.name, sizeof(named_device.name), "Preferred Name");
    receiver_ok = receiver_ok &&
                  strcmp(device_label(&unnamed_receiver), "Paired Logitech mouse") == 0 &&
                  strcmp(device_label(&unnamed_direct), "Direct Mouse") == 0 &&
                  strcmp(device_label(&named_device), "Preferred Name") == 0;
    discover_direct_interface.product[0] = '\0';
    receiver_ok = receiver_ok &&
                  strcmp(device_label(&unnamed_direct), "Logitech HID++ device") == 0 &&
                  !is_receiver_endpoint(NULL) && !is_receiver_endpoint(&unnamed_direct);

    Device keyboard_device = {.iface = &discover_direct_interface, .device_number = 0xFF};
    snprintf(keyboard_device.name, sizeof(keyboard_device.name), "Office Keyboard");
    receiver_ok = receiver_ok && !is_mouse_device(NULL) && !is_mouse_device(&keyboard_device);
    keyboard_device.name[0] = '\0';
    snprintf(discover_direct_interface.product, sizeof(discover_direct_interface.product),
             "Keypad");
    receiver_ok = receiver_ok && !is_mouse_device(&keyboard_device);
    snprintf(discover_direct_interface.product, sizeof(discover_direct_interface.product),
             "Plain HID");
    discover_direct_interface.is_mouse = true;
    receiver_ok = receiver_ok && is_mouse_device(&keyboard_device);
    discover_direct_interface.is_mouse = false;
    keyboard_device.feature_count = 1;
    keyboard_device.features[0] = (Feature){FEATURE_ONBOARD_PROFILES, 1, 1};
    receiver_ok = receiver_ok && is_mouse_device(&keyboard_device);
    keyboard_device.feature_count = 0;
    receiver_ok = receiver_ok && is_mouse_device(&keyboard_device);
    snprintf(keyboard_device.name, sizeof(keyboard_device.name), "Mouse");
    snprintf(discover_direct_interface.product, sizeof(discover_direct_interface.product),
             "Keyboard");
    receiver_ok = receiver_ok && !is_mouse_device(&keyboard_device);
    snprintf(discover_direct_interface.product, sizeof(discover_direct_interface.product),
             "Keypad");
    receiver_ok = receiver_ok && !is_mouse_device(&keyboard_device);
    snprintf(discover_direct_interface.product, sizeof(discover_direct_interface.product),
             "Plain HID");
    keyboard_device.features[0] = (Feature){FEATURE_ADJUSTABLE_DPI, 2, 1};
    keyboard_device.feature_count = 1;
    receiver_ok = receiver_ok && is_mouse_device(&keyboard_device);

    HidInterface endpoint_text_interface = {0};
    Device endpoint_text_device = {.iface = &endpoint_text_interface, .device_number = 0xFF};
    snprintf(endpoint_text_device.name, sizeof(endpoint_text_device.name), "Receiver");
    receiver_ok = receiver_ok && is_receiver_endpoint(&endpoint_text_device);
    endpoint_text_device.name[0] = '\0';
    snprintf(endpoint_text_interface.product, sizeof(endpoint_text_interface.product), "Unifying");
    receiver_ok = receiver_ok && is_receiver_endpoint(&endpoint_text_device);
    snprintf(endpoint_text_interface.product, sizeof(endpoint_text_interface.product), "Bolt");
    receiver_ok = receiver_ok && is_receiver_endpoint(&endpoint_text_device);
    endpoint_text_interface.product[0] = '\0';
    endpoint_text_interface.product_id = 0x1234;
    snprintf(endpoint_text_device.name, sizeof(endpoint_text_device.name), "Unifying mouse");
    receiver_ok = receiver_ok && is_receiver_endpoint(&endpoint_text_device);
    snprintf(endpoint_text_device.name, sizeof(endpoint_text_device.name), "Bolt mouse");
    receiver_ok = receiver_ok && is_receiver_endpoint(&endpoint_text_device);
    connection_device.device_number = 0xFF;
    connection_interface.product_id = 0xC539;
    connection_types_ok =
        connection_types_ok && strcmp(device_connection(&connection_device), "LIGHTSPEED") == 0;
    connection_device.device_number = 1;

    discover_direct_interface.product_id = 0x4085;
    Device duplicate_candidate = {.iface = &discover_direct_interface, .device_number = 0xFF};
    HidInterface duplicate_receiver_iface = {.product_id = 0xC539};
    Device duplicate_receiver = {.iface = &duplicate_receiver_iface, .device_number = 1};
    snprintf(duplicate_candidate.name, sizeof(duplicate_candidate.name), "G604");
    snprintf(duplicate_receiver.name, sizeof(duplicate_receiver.name), "G604");
    Device duplicate_devices[] = {duplicate_candidate, duplicate_receiver};
    receiver_ok = receiver_ok && !is_duplicate_direct_mouse_endpoint(NULL, duplicate_devices, 2) &&
                  !is_duplicate_direct_mouse_endpoint(&duplicate_candidate, NULL, 2) &&
                  is_duplicate_direct_mouse_endpoint(&duplicate_candidate, duplicate_devices, 2);
    duplicate_devices[1].name[0] = '\0';
    receiver_ok = receiver_ok &&
                  !is_duplicate_direct_mouse_endpoint(&duplicate_candidate, duplicate_devices, 2);
    duplicate_devices[1].device_number = 0xFF;
    receiver_ok = receiver_ok &&
                  !is_duplicate_direct_mouse_endpoint(&duplicate_candidate, duplicate_devices, 2);
    duplicate_devices[1].device_number = 1;
    duplicate_receiver_iface.product_id = 0x1234;
    receiver_ok = receiver_ok &&
                  !is_duplicate_direct_mouse_endpoint(&duplicate_candidate, duplicate_devices, 2);
    duplicate_receiver_iface.product_id = 0xC539;
    duplicate_candidate.iface->product_id = 0x1234;
    receiver_ok = receiver_ok &&
                  !is_duplicate_direct_mouse_endpoint(&duplicate_candidate, duplicate_devices, 2);
    duplicate_candidate.iface->product_id = 0x4085;
    snprintf(duplicate_candidate.iface->product, sizeof(duplicate_candidate.iface->product),
             "Receiver");
    receiver_ok = receiver_ok &&
                  !is_duplicate_direct_mouse_endpoint(&duplicate_candidate, duplicate_devices, 2);
    duplicate_candidate.iface->product[0] = '\0';
    Device duplicate_pointer_devices[] = {duplicate_candidate, duplicate_receiver};
    receiver_ok = receiver_ok && is_duplicate_direct_mouse_endpoint(&duplicate_pointer_devices[0],
                                                                    duplicate_pointer_devices, 2);

    char device_key[64];
    format_device_key(&discover_key_devices[0], device_key, sizeof(device_key));
    uint64_t parsed_location = 0;
    uint64_t parsed_registry = 0;
    uint8_t parsed_number = 0;
    receiver_ok =
        receiver_ok && strcmp(device_key, "1234-5678-FF") == 0 &&
        parse_device_key(device_key, &parsed_location, &parsed_registry, &parsed_number) &&
        parsed_location == 0x1234 && parsed_registry == 0x5678 && parsed_number == 0xFF &&
        !parse_device_key("1234-5678-100", &parsed_location, &parsed_registry, &parsed_number) &&
        !parse_device_key(NULL, &parsed_location, &parsed_registry, &parsed_number);

    Reply register_reply = {.status = REPLY_OK, .length = 1, .bytes = {0xAA}};
    ChannelRequestTestContext register_context = {.replies = &register_reply, .reply_count = 1};
    g_channel_request_test_context = &register_context;
    Reply register_without_subregister = hid_discovery_receiver_register_read_for_test(
        &receiver_interface, REGISTER_RECEIVER_INFO, false, 0);
    receiver_ok = receiver_ok && register_without_subregister.status == REPLY_OK &&
                  register_context.calls == 1;
    unsetenv("LOGITECH_ONBOARD_DEBUG");
    hid_discovery_log_receiver_register_reply_for_test(&receiver_interface, REGISTER_RECEIVER_INFO,
                                                       0, register_reply);
    setenv("LOGITECH_ONBOARD_DEBUG", "1", 1);

    Device slot_name_device = {.iface = &receiver_interface};
    Reply slot_name_reply = {.status = REPLY_OK, .length = 6, .bytes = {0, 4, 'N', 'a', 'm', '\r'}};
    ChannelRequestTestContext slot_name_context = {.replies = &slot_name_reply, .reply_count = 1};
    g_channel_request_test_context = &slot_name_context;
    hid_discovery_receiver_slot_name_for_test(&slot_name_device, 1, unknown_pairing);
    receiver_ok = receiver_ok && strcmp(slot_name_device.name, "Nam") == 0;
    snprintf(slot_name_device.name, sizeof(slot_name_device.name), "Already named");
    hid_discovery_receiver_slot_name_for_test(&slot_name_device, 1, g603_pairing);
    receiver_ok = receiver_ok && strcmp(slot_name_device.name, "Already named") == 0;
    memset(slot_name_device.name, 0, sizeof(slot_name_device.name));
    Reply slot_name_error = {.status = REPLY_PROTOCOL_ERROR};
    slot_name_context.replies = &slot_name_error;
    slot_name_context.reply_count = 1;
    slot_name_context.calls = 0;
    hid_discovery_receiver_slot_name_for_test(&slot_name_device, 1, unknown_pairing);
    receiver_ok = receiver_ok && slot_name_device.name[0] == '\0';
    hid_discovery_receiver_slot_name_for_test(&slot_name_device, 1, g603_pairing);
    receiver_ok = receiver_ok && strcmp(slot_name_device.name, "G603 LIGHTSPEED") == 0;

    Device add_devices[MAX_DEVICES];
    size_t add_count = 0;
    receiver_ok =
        receiver_ok && !hid_discovery_add_receiver_slot_device_for_test(
                           add_devices, &add_count, &receiver_interface, 1, error_pairing, false);
    add_count = MAX_DEVICES;
    receiver_ok =
        receiver_ok && !hid_discovery_add_receiver_slot_device_for_test(
                           add_devices, &add_count, &receiver_interface, 1, g603_pairing, false);
    add_count = 0;
    receiver_ok = receiver_ok &&
                  hid_discovery_add_device_for_test(add_devices, &add_count, &receiver_interface, 1,
                                                    1, 1.0, false) &&
                  add_count == 1;
    add_count = MAX_DEVICES;
    receiver_ok =
        receiver_ok && !hid_discovery_add_device_for_test(add_devices, &add_count,
                                                          &receiver_interface, 1, 1, 1.0, false);

    HidInterface compare_left = {0};
    HidInterface compare_right = {0};
    compare_left.location_id = 1;
    compare_right.location_id = 2;
    bool helper_ok = hid_discovery_compare_interfaces_for_test(&compare_left, &compare_right) < 0 &&
                     hid_discovery_compare_interfaces_for_test(&compare_right, &compare_left) > 0;
    compare_left.location_id = compare_right.location_id = 1;
    compare_left.registry_id = 1;
    compare_right.registry_id = 2;
    helper_ok = helper_ok &&
                hid_discovery_compare_interfaces_for_test(&compare_left, &compare_right) < 0 &&
                hid_discovery_compare_interfaces_for_test(&compare_right, &compare_left) > 0;
    compare_left.registry_id = compare_right.registry_id = 1;
    compare_left.product_id = 1;
    compare_right.product_id = 2;
    helper_ok = helper_ok &&
                hid_discovery_compare_interfaces_for_test(&compare_left, &compare_right) < 0 &&
                hid_discovery_compare_interfaces_for_test(&compare_right, &compare_left) > 0;
    compare_left.product_id = compare_right.product_id = 1;
    compare_left.usage_page = 1;
    compare_right.usage_page = 2;
    helper_ok = helper_ok &&
                hid_discovery_compare_interfaces_for_test(&compare_left, &compare_right) < 0 &&
                hid_discovery_compare_interfaces_for_test(&compare_right, &compare_left) > 0;
    compare_left.usage_page = compare_right.usage_page = 1;
    compare_left.usage = 1;
    compare_right.usage = 2;
    helper_ok = helper_ok &&
                hid_discovery_compare_interfaces_for_test(&compare_left, &compare_right) < 0 &&
                hid_discovery_compare_interfaces_for_test(&compare_right, &compare_left) > 0;
    compare_left.usage = compare_right.usage = 1;
    snprintf(compare_left.product, sizeof(compare_left.product), "Alpha");
    snprintf(compare_right.product, sizeof(compare_right.product), "Beta");
    helper_ok = helper_ok &&
                hid_discovery_compare_interfaces_for_test(&compare_left, &compare_right) < 0 &&
                hid_discovery_compare_interfaces_for_test(&compare_right, &compare_left) > 0;
    snprintf(compare_right.product, sizeof(compare_right.product), "Alpha");
    snprintf(compare_left.transport, sizeof(compare_left.transport), "USB");
    snprintf(compare_right.transport, sizeof(compare_right.transport), "Bluetooth");
    helper_ok = helper_ok &&
                hid_discovery_compare_interfaces_for_test(&compare_left, &compare_right) > 0 &&
                hid_discovery_compare_interfaces_for_test(&compare_left, &compare_left) == 0;

    HidInterface slot_interface = {0};
    helper_ok = helper_ok && hid_discovery_receiver_slot_limit_for_test(NULL) == 0;
    helper_ok = helper_ok && hid_discovery_receiver_slot_limit_for_test(&slot_interface) == 0;
    slot_interface.product_id = 0xC539;
    helper_ok = helper_ok && hid_discovery_receiver_slot_limit_for_test(&slot_interface) == 1;
    slot_interface.product_id = 0xC53A;
    helper_ok = helper_ok && hid_discovery_receiver_slot_limit_for_test(&slot_interface) == 1;
    slot_interface.product_id = 0xC52B;
    helper_ok = helper_ok && hid_discovery_receiver_slot_limit_for_test(&slot_interface) == 6;
    slot_interface.product_id = 0xC532;
    helper_ok = helper_ok && hid_discovery_receiver_slot_limit_for_test(&slot_interface) == 6;
    slot_interface.product_id = 0xC548;
    helper_ok = helper_ok && hid_discovery_receiver_slot_limit_for_test(&slot_interface) == 6;
    slot_interface.product_id = 0xC599;
    helper_ok = helper_ok && hid_discovery_receiver_slot_limit_for_test(&slot_interface) == 6;
    slot_interface.product_id = 0;
    snprintf(slot_interface.product, sizeof(slot_interface.product), "Unifying");
    helper_ok = helper_ok && hid_discovery_receiver_slot_limit_for_test(&slot_interface) == 6;
    snprintf(slot_interface.product, sizeof(slot_interface.product), "Bolt");
    helper_ok = helper_ok && hid_discovery_receiver_slot_limit_for_test(&slot_interface) == 6;
    snprintf(slot_interface.product, sizeof(slot_interface.product), "Bolt receiver");
    helper_ok = helper_ok && hid_discovery_receiver_slot_limit_for_test(&slot_interface) == 6;
    const uint32_t additional_single_slot_ids[] = {0xC53D, 0xC53F, 0xC541, 0xC545, 0xC547, 0xC54D};
    for (size_t i = 0;
         i < sizeof(additional_single_slot_ids) / sizeof(additional_single_slot_ids[0]); i++) {
        slot_interface.product_id = additional_single_slot_ids[i];
        helper_ok = helper_ok && hid_discovery_receiver_slot_limit_for_test(&slot_interface) == 1;
    }

    HidInterface ping_interface = {.product_id = 0x4085, .prefer_long_reports = true};
    double ping_protocol = 0;
    uint8_t ping_device_number = 0;
    Reply ping_replies[] = {
        {.status = REPLY_TIMEOUT},
        {.status = REPLY_OK, .length = 3, .device_number = 3, .bytes = {0x02, 0x05, 0x5A}}};
    ChannelRequestTestContext ping_context = {.replies = ping_replies, .reply_count = 2};
    channel_request_impl = channel_request_test_double;
    g_channel_request_test_context = &ping_context;
    bool ping_ok = hid_discovery_ping_interface_for_test(&ping_interface, 0xFF, 1.0, &ping_protocol,
                                                         &ping_device_number) &&
                   ping_protocol == 2.5 && ping_device_number == 3 && ping_context.calls == 2;
    Reply ping_hid10 = {.status = REPLY_HIDPP10_ERROR, .error_code = 1};
    ChannelRequestTestContext ping_hid10_context = {.replies = &ping_hid10, .reply_count = 1};
    g_channel_request_test_context = &ping_hid10_context;
    ping_protocol = 0;
    ping_ok =
        ping_ok &&
        hid_discovery_ping_interface_for_test(&ping_interface, 2, 1.0, &ping_protocol, NULL) &&
        ping_protocol == 1.0;
    Reply ping_protocol_error = {.status = REPLY_PROTOCOL_ERROR};
    ChannelRequestTestContext ping_error_context = {.replies = &ping_protocol_error,
                                                    .reply_count = 1};
    g_channel_request_test_context = &ping_error_context;
    ping_ok = ping_ok && !hid_discovery_ping_interface_for_test(
                             &ping_interface, 2, 1.0, &ping_protocol, &ping_device_number);
    HidInterface receiver_ping_interface = {.product_id = 0xC539, .prefer_long_reports = true};
    Reply ping_bad_marker = {.status = REPLY_OK, .length = 3, .bytes = {0x02, 0x00, 0x00}};
    ChannelRequestTestContext ping_bad_marker_context = {.replies = &ping_bad_marker,
                                                         .reply_count = 1};
    g_channel_request_test_context = &ping_bad_marker_context;
    ping_ok = ping_ok && !hid_discovery_ping_interface_for_test(
                             &receiver_ping_interface, 1, 1.0, &ping_protocol, &ping_device_number);
    Reply ping_hid10_other = {.status = REPLY_HIDPP10_ERROR, .error_code = 2};
    ChannelRequestTestContext ping_hid10_other_context = {.replies = &ping_hid10_other,
                                                          .reply_count = 1};
    g_channel_request_test_context = &ping_hid10_other_context;
    ping_ok = ping_ok && !hid_discovery_ping_interface_for_test(
                             &ping_interface, 2, 1.0, &ping_protocol, &ping_device_number);
    Reply ping_direct_success = {.status = REPLY_OK, .length = 3, .bytes = {0x02, 0x00, 0x5A}};
    ChannelRequestTestContext ping_direct_success_context = {.replies = &ping_direct_success,
                                                             .reply_count = 1};
    g_channel_request_test_context = &ping_direct_success_context;
    ping_ok = ping_ok &&
              hid_discovery_ping_interface_for_test(&ping_interface, 2, 1.0, &ping_protocol, NULL);

    HidInterface name_interface = {.product_id = 0x4085};
    Device name_device = {.iface = &name_interface,
                          .request_device_number = 0xFF,
                          .features = {{FEATURE_DEVICE_NAME, 5, 1}},
                          .feature_count = 1};
    Reply name_replies[] = {{.status = REPLY_OK, .length = 1, .bytes = {4}},
                            {.status = REPLY_OK, .length = 2, .bytes = {'H', 'i'}},
                            {.status = REPLY_OK, .length = 3, .bytes = {'!', ' ', '\n'}}};
    ChannelRequestTestContext name_context = {.replies = name_replies, .reply_count = 3};
    g_channel_request_test_context = &name_context;
    bool name_ok =
        hid_discovery_device_name_for_test(&name_device) && strcmp(name_device.name, "Hi! ") == 0;
    name_device.feature_count = 0;
    name_ok = name_ok && !hid_discovery_device_name_for_test(&name_device);
    name_device.feature_count = 1;
    Reply name_initial_error = {.status = REPLY_TIMEOUT};
    ChannelRequestTestContext name_error_context = {.replies = &name_initial_error,
                                                    .reply_count = 1};
    g_channel_request_test_context = &name_error_context;
    name_ok = name_ok && !hid_discovery_device_name_for_test(&name_device);
    Reply name_chunk_error_replies[] = {{.status = REPLY_OK, .length = 1, .bytes = {2}},
                                        {.status = REPLY_TIMEOUT}};
    ChannelRequestTestContext name_chunk_error_context = {.replies = name_chunk_error_replies,
                                                          .reply_count = 2};
    g_channel_request_test_context = &name_chunk_error_context;
    name_ok = name_ok && !hid_discovery_device_name_for_test(&name_device);
    Device long_name_device = {.iface = &name_interface,
                               .request_device_number = 0xFF,
                               .features = {{FEATURE_DEVICE_NAME, 5, 1}},
                               .feature_count = 1};
    Reply long_name_replies[] = {{.status = REPLY_OK, .length = 1, .bytes = {255}},
                                 {.status = REPLY_OK, .length = 64}};
    ChannelRequestTestContext long_name_context = {.replies = long_name_replies, .reply_count = 2};
    g_channel_request_test_context = &long_name_context;
    name_ok = name_ok && !hid_discovery_device_name_for_test(&long_name_device);
    Reply nul_name_replies[] = {{.status = REPLY_OK, .length = 1, .bytes = {3}},
                                {.status = REPLY_OK, .length = 3, .bytes = {'X', 'Y', '\0'}}};
    ChannelRequestTestContext nul_name_context = {.replies = nul_name_replies, .reply_count = 2};
    g_channel_request_test_context = &nul_name_context;
    name_ok = name_ok && hid_discovery_device_name_for_test(&long_name_device) &&
              strcmp(long_name_device.name, "XY") == 0;
    Reply name_initial_empty = {.status = REPLY_OK, .length = 0};
    ChannelRequestTestContext name_initial_empty_context = {.replies = &name_initial_empty,
                                                            .reply_count = 1};
    g_channel_request_test_context = &name_initial_empty_context;
    name_ok = name_ok && !hid_discovery_device_name_for_test(&name_device);
    Reply name_chunk_empty_replies[] = {{.status = REPLY_OK, .length = 1, .bytes = {2}},
                                        {.status = REPLY_OK, .length = 0}};
    ChannelRequestTestContext name_chunk_empty_context = {.replies = name_chunk_empty_replies,
                                                          .reply_count = 2};
    g_channel_request_test_context = &name_chunk_empty_context;
    name_ok = name_ok && !hid_discovery_device_name_for_test(&name_device);

    Device feature_device = {.iface = &name_interface, .request_device_number = 0xFF};
    Reply feature_replies[] = {
        {.status = REPLY_OK, .length = 1, .bytes = {1}},
        {.status = REPLY_OK, .length = 1, .bytes = {2}},
        {.status = REPLY_OK, .length = 4, .bytes = {0x22, 0x01, 0, 4}},
        {.status = REPLY_OK, .length = 4, .bytes = {0x22, 0x01, 0, 5}},
        {.status = REPLY_TIMEOUT},
    };
    ChannelRequestTestContext feature_context = {.replies = feature_replies, .reply_count = 5};
    g_channel_request_test_context = &feature_context;
    bool feature_ok = hid_discovery_discover_features_for_test(&feature_device) &&
                      feature_device.feature_count == 2 &&
                      feature_device.features[1].id == 0x2201 && feature_context.calls == 5;
    Reply feature_count_error[] = {{.status = REPLY_OK, .length = 1, .bytes = {1}},
                                   {.status = REPLY_TIMEOUT}};
    feature_context.replies = feature_count_error;
    feature_context.reply_count = 2;
    feature_context.calls = 0;
    feature_ok = feature_ok && !hid_discovery_discover_features_for_test(&feature_device);
    Reply feature_root_short = {.status = REPLY_OK, .length = 0};
    feature_context.replies = &feature_root_short;
    feature_context.reply_count = 1;
    feature_context.calls = 0;
    feature_ok = feature_ok && !hid_discovery_discover_features_for_test(&feature_device);
    Reply feature_count_short[] = {{.status = REPLY_OK, .length = 1, .bytes = {1}},
                                   {.status = REPLY_OK, .length = 0}};
    feature_context.replies = feature_count_short;
    feature_context.reply_count = 2;
    feature_context.calls = 0;
    feature_ok = feature_ok && !hid_discovery_discover_features_for_test(&feature_device);
    Reply feature_item_short[] = {{.status = REPLY_OK, .length = 1, .bytes = {1}},
                                  {.status = REPLY_OK, .length = 1, .bytes = {1}},
                                  {.status = REPLY_OK, .length = 3, .bytes = {0x22, 0x01, 0}}};
    feature_context.replies = feature_item_short;
    feature_context.reply_count = 3;
    feature_context.calls = 0;
    feature_ok = feature_ok && hid_discovery_discover_features_for_test(&feature_device);
    Reply feature_root_zero = {.status = REPLY_OK, .length = 1, .bytes = {0}};
    feature_context.replies = &feature_root_zero;
    feature_context.reply_count = 1;
    feature_context.calls = 0;
    feature_ok = feature_ok && !hid_discovery_discover_features_for_test(&feature_device);

    HidInterface receiver_name_interface = {.product_id = 0xC539};
    Device receiver_name_device = {.iface = &receiver_name_interface};
    Reply receiver_name_replies[] = {
        {.status = REPLY_TIMEOUT},
        {.status = REPLY_IO_ERROR},
        {.status = REPLY_OK, .length = 6, .bytes = {0, 4, 'N', 'a', 'm', '\r'}},
    };
    ChannelRequestTestContext receiver_name_context = {.replies = receiver_name_replies,
                                                       .reply_count = 3};
    g_channel_request_test_context = &receiver_name_context;
    bool receiver_name_ok = hid_discovery_receiver_device_name_for_test(&receiver_name_device, 1) &&
                            strcmp(receiver_name_device.name, "Nam") == 0;
    Reply receiver_empty_replies[] = {
        {.status = REPLY_OK, .length = 2, .bytes = {0, 0}},
        {.status = REPLY_OK, .length = 2, .bytes = {0, 0}},
        {.status = REPLY_OK, .length = 2, .bytes = {0, 0}},
    };
    receiver_name_context.replies = receiver_empty_replies;
    receiver_name_context.reply_count = 3;
    receiver_name_context.calls = 0;
    memset(receiver_name_device.name, 0, sizeof(receiver_name_device.name));
    receiver_name_ok =
        receiver_name_ok && !hid_discovery_receiver_device_name_for_test(&receiver_name_device, 1);

    Reply terminal_name_errors[] = {
        {.status = REPLY_TIMEOUT}, {.status = REPLY_TIMEOUT}, {.status = REPLY_TIMEOUT}};
    receiver_name_context.replies = terminal_name_errors;
    receiver_name_context.reply_count = 3;
    receiver_name_context.calls = 0;
    receiver_name_ok =
        receiver_name_ok && !hid_discovery_receiver_device_name_for_test(&receiver_name_device, 1);

    Reply clamped_name_reply = {.status = REPLY_OK, .length = 2, .bytes = {0, 7}};
    receiver_name_context.replies = &clamped_name_reply;
    receiver_name_context.reply_count = 1;
    receiver_name_context.calls = 0;
    receiver_name_ok =
        receiver_name_ok && !hid_discovery_receiver_device_name_for_test(&receiver_name_device, 1);
    Reply newline_name_reply = {
        .status = REPLY_OK, .length = 6, .bytes = {0, 4, 'N', 'a', 'm', '\n'}};
    receiver_name_context.replies = &newline_name_reply;
    receiver_name_context.reply_count = 1;
    receiver_name_context.calls = 0;
    memset(receiver_name_device.name, 0, sizeof(receiver_name_device.name));
    receiver_name_ok = receiver_name_ok &&
                       hid_discovery_receiver_device_name_for_test(&receiver_name_device, 1) &&
                       strcmp(receiver_name_device.name, "Nam") == 0;
    Reply nul_receiver_name_reply = {
        .status = REPLY_OK, .length = 6, .bytes = {0, 4, 'N', 'a', 'm', '\0'}};
    receiver_name_context.replies = &nul_receiver_name_reply;
    receiver_name_context.calls = 0;
    memset(receiver_name_device.name, 0, sizeof(receiver_name_device.name));
    receiver_name_ok = receiver_name_ok &&
                       hid_discovery_receiver_device_name_for_test(&receiver_name_device, 1) &&
                       strcmp(receiver_name_device.name, "Nam") == 0;

    HidInterface closed_mouse = {.product_id = 0x4085, .is_vendor = true, .is_mouse = true};
    HidInterface closed_nonmouse = {.product_id = 0x4085, .is_vendor = true};
    HidContext closed_context = {.items = &closed_mouse, .count = 1};
    g_discovery_channel_open_result = kIOReturnError;
    hid_device_open_impl = discovery_channel_open_double;
    hid_device_close_impl = discovery_channel_close_double;
    hid_device_register_input_report_callback_impl = discovery_channel_callback_double;
    hid_device_schedule_with_run_loop_impl = discovery_channel_schedule_double;
    hid_device_unschedule_from_run_loop_impl = discovery_channel_schedule_double;
    hid_device_get_property_impl = discovery_property_double;
    Device closed_devices[MAX_DEVICES];
    size_t closed_count = 0;
    bool closed_ok = discover_devices(&closed_context, -1, closed_devices, &closed_count, false) &&
                     closed_count == 1 && closed_devices[0].protocol == 0.0;
    closed_context.items = &closed_nonmouse;
    closed_count = 0;
    closed_ok = closed_ok &&
                discover_devices(&closed_context, -1, closed_devices, &closed_count, false) &&
                closed_count == 0;

    HidInterface open_interface = {.product_id = 0x4085, .is_vendor = true};
    HidInterface already_open = {.product_id = 0x4085, .is_vendor = true, .channel_open = true};
    HidInterface not_vendor = {.product_id = 0x4085, .is_vendor = false};
    HidInterface open_items[] = {not_vendor, already_open, open_interface};
    HidContext open_context = {.items = open_items, .count = 3};
    g_discovery_channel_open_result = kIOReturnSuccess;
    bool open_channels_ok = open_vendor_channels(&open_context) && open_items[2].channel_open;
    if (open_items[2].channel_open) {
        channel_close(&open_items[2].channel);
        open_items[2].channel_open = false;
    }
    g_discovery_channel_open_result = kIOReturnError;
    open_channels_ok =
        open_channels_ok && open_vendor_channels(&open_context) && !open_items[2].channel_open;

    HidInterface direct_request_interface = {.product_id = 0x4085,
                                             .is_vendor = true,
                                             .channel_open = true,
                                             .location_id = 0x10,
                                             .registry_id = 0x20};
    HidContext direct_request_context = {.items = &direct_request_interface, .count = 1};
    Reply direct_request_reply = {.status = REPLY_OK, .length = 3, .bytes = {2, 0, 0x5A}};
    ChannelRequestTestContext direct_request_test = {.replies = &direct_request_reply,
                                                     .reply_count = 1};
    g_channel_request_test_context = &direct_request_test;
    Device direct_request_devices[MAX_DEVICES];
    size_t direct_request_count = 0;
    bool direct_request_ok = discover_devices(&direct_request_context, 2, direct_request_devices,
                                              &direct_request_count, false) &&
                             direct_request_count == 1 &&
                             direct_request_devices[0].device_number == 2;
    Reply direct_request_error = {.status = REPLY_PROTOCOL_ERROR};
    direct_request_test.replies = &direct_request_error;
    direct_request_test.calls = 0;
    direct_request_count = 0;
    direct_request_ok = direct_request_ok &&
                        discover_devices(&direct_request_context, 2, direct_request_devices,
                                         &direct_request_count, false) &&
                        direct_request_count == 0;

    Reply direct_key_replies[] = {{.status = REPLY_TIMEOUT},
                                  {.status = REPLY_OK, .length = 3, .bytes = {2, 0, 0x5A}}};
    ChannelRequestTestContext direct_key_test = {.replies = direct_key_replies, .reply_count = 2};
    g_channel_request_test_context = &direct_key_test;
    direct_request_count = 0;
    bool key_fallback_ok = discover_device_by_key(&direct_request_context, "10-20-02",
                                                  direct_request_devices, &direct_request_count) &&
                           direct_request_count == 1 &&
                           direct_request_devices[0].request_device_number == 0xFF;
    direct_request_count = 0;
    key_fallback_ok = key_fallback_ok &&
                      discover_device_by_key(&direct_request_context, "10-20-03",
                                             direct_request_devices, &direct_request_count) &&
                      direct_request_count == 0;
    HidContext empty_context = {0};
    direct_request_count = 0;
    key_fallback_ok = key_fallback_ok &&
                      discover_device_by_key(&empty_context, "10-20-02", direct_request_devices,
                                             &direct_request_count) &&
                      direct_request_count == 0;

    HidInterface key_receiver_interface = receiver_interface;
    key_receiver_interface.location_id = 0x30;
    key_receiver_interface.registry_id = 0x40;
    HidContext key_receiver_context = {.items = &key_receiver_interface, .count = 1};
    Reply key_receiver_unpaired[] = {{.status = REPLY_TIMEOUT}, {.status = REPLY_TIMEOUT}};
    ChannelRequestTestContext key_receiver_test = {.replies = key_receiver_unpaired,
                                                   .reply_count = 2};
    g_channel_request_test_context = &key_receiver_test;
    size_t receiver_key_count = 0;
    bool receiver_key_ok = discover_device_by_key(&key_receiver_context, "30-40-01",
                                                  direct_request_devices, &receiver_key_count) &&
                           receiver_key_count == 0;
    Reply key_receiver_invalid_slot = {.status = REPLY_PROTOCOL_ERROR};
    key_receiver_test.replies = &key_receiver_invalid_slot;
    key_receiver_test.reply_count = 1;
    key_receiver_test.calls = 0;
    receiver_key_count = 0;
    receiver_key_ok = receiver_key_ok &&
                      discover_device_by_key(&key_receiver_context, "30-40-00",
                                             direct_request_devices, &receiver_key_count) &&
                      receiver_key_count == 0;
    Reply key_receiver_success[] = {g603_pairing,
                                    {.status = REPLY_OK, .length = 3, .bytes = {2, 0, 0x5A}},
                                    {.status = REPLY_OK, .length = 1, .bytes = {0}},
                                    {.status = REPLY_OK, .length = 4, .bytes = {0, 2, 'O', 'K'}}};
    key_receiver_test.replies = key_receiver_success;
    key_receiver_test.reply_count = sizeof(key_receiver_success) / sizeof(key_receiver_success[0]);
    key_receiver_test.calls = 0;
    receiver_key_count = 0;
    receiver_key_ok = receiver_key_ok &&
                      discover_device_by_key(&key_receiver_context, "30-40-01",
                                             direct_request_devices, &receiver_key_count) &&
                      receiver_key_count == 1 && direct_request_devices[0].protocol == 2.0 &&
                      strcmp(direct_request_devices[0].name, "OK") == 0;
    Reply key_receiver_sleeping[] = {g603_pairing,
                                     {.status = REPLY_TIMEOUT},
                                     {.status = REPLY_OK, .length = 1, .bytes = {0}},
                                     {.status = REPLY_OK, .length = 4, .bytes = {0, 2, 'O', 'K'}}};
    key_receiver_test.replies = key_receiver_sleeping;
    key_receiver_test.reply_count =
        sizeof(key_receiver_sleeping) / sizeof(key_receiver_sleeping[0]);
    key_receiver_test.calls = 0;
    receiver_key_count = 0;
    receiver_key_ok = receiver_key_ok &&
                      discover_device_by_key(&key_receiver_context, "30-40-01",
                                             direct_request_devices, &receiver_key_count) &&
                      receiver_key_count == 1;
    Reply key_receiver_hid10[] = {{.status = REPLY_TIMEOUT},
                                  {.status = REPLY_HIDPP10_ERROR, .error_code = 1},
                                  {.status = REPLY_OK, .length = 1, .bytes = {0}},
                                  {.status = REPLY_OK, .length = 4, .bytes = {0, 2, 'O', 'K'}}};
    key_receiver_test.replies = key_receiver_hid10;
    key_receiver_test.reply_count = sizeof(key_receiver_hid10) / sizeof(key_receiver_hid10[0]);
    key_receiver_test.calls = 0;
    receiver_key_count = 0;
    receiver_key_ok = receiver_key_ok &&
                      discover_device_by_key(&key_receiver_context, "30-40-01",
                                             direct_request_devices, &receiver_key_count) &&
                      receiver_key_count == 1 && direct_request_devices[0].protocol == 2.0;

    Options hardware_options = {0};
    hardware_options.device_key = "10-20-02";
    Reply hardware_key_reply = {.status = REPLY_OK, .length = 3, .bytes = {2, 0, 0x5A}};
    ChannelRequestTestContext hardware_key_test = {.replies = &hardware_key_reply,
                                                   .reply_count = 1};
    g_channel_request_test_context = &hardware_key_test;
    size_t hardware_options_count = 0;
    bool options_hardware_ok =
        discover_devices_for_options_hardware(&direct_request_context, &hardware_options,
                                              direct_request_devices, &hardware_options_count) &&
        hardware_options_count == 1;
    memset(&hardware_options, 0, sizeof(hardware_options));
    hardware_options.slot = -1;
    hardware_options_count = 0;
    options_hardware_ok =
        options_hardware_ok &&
        discover_devices_for_options_hardware(&empty_context, &hardware_options,
                                              direct_request_devices, &hardware_options_count) &&
        hardware_options_count == 0;

    DiscoveryDeviceSpec enumeration_specs[] = {
        {0x1234, MOUSE_USAGE_PAGE, MOUSE_USAGE, 0x1234, 11, 11, "Other", "USB", NULL},
        {LOGITECH_VID, 0x0009, 0x0001, 0x9999, 12, 12, "Keyboard", "USB", NULL},
        {LOGITECH_VID, MOUSE_USAGE_PAGE, MOUSE_USAGE, 0x9999, 13, 13, "Travel Mouse", "Bluetooth",
         NULL},
        {LOGITECH_VID, 0, 0, 0x4085, 14, 14, "G604", "Bluetooth", NULL},
        {LOGITECH_VID, HIDPP_USAGE_PAGE, 1, 0xC539, 15, 15, "LIGHTSPEED Receiver", "USB", NULL},
        {LOGITECH_VID, HIDPP_USAGE_PAGE, 1, 0x1234, 16, 16, "Vendor Interface", "USB", NULL},
        {LOGITECH_VID, 0, 0, G600_PRODUCT_ID, 17, 17, "G600", "USB", NULL},
    };
    uint8_t enumeration_descriptor[] = {0x06, 0x00, 0xFF, 0x85, REPORT_SHORT, 0x85, REPORT_LONG, 0};
    enumeration_specs[4].descriptor = CFDataCreate(kCFAllocatorDefault, enumeration_descriptor,
                                                   (CFIndex)sizeof(enumeration_descriptor));
    g_discovery_device_specs = enumeration_specs;
    g_discovery_device_count = sizeof(enumeration_specs) / sizeof(enumeration_specs[0]);
    g_discovery_set_count = (CFIndex)g_discovery_device_count;
    g_discovery_manager_mode = 0;
    g_discovery_manager_close_calls = 0;
    g_discovery_release_calls = 0;
    hid_check_access_impl = discovery_check_access_double;
    hid_manager_create_impl = discovery_manager_create_double;
    hid_manager_set_device_matching_impl = discovery_manager_set_matching_double;
    hid_manager_copy_devices_impl = discovery_manager_copy_devices_double;
    hid_set_get_count_impl = discovery_set_get_count_double;
    hid_set_get_values_impl = discovery_set_get_values_double;
    hid_manager_close_impl = discovery_manager_close_double;
    hid_cf_release_impl = discovery_release_double;
    hid_device_get_property_impl = discovery_property_double;
    hid_device_get_service_impl = discovery_service_double;
    hid_registry_entry_get_id_impl = discovery_registry_id_double;
    hid_device_copy_matching_elements_impl = discovery_elements_double;
    HidContext hardware_context;
    bool hardware_ok =
        hid_context_create_hardware(&hardware_context) && hardware_context.count == 5 &&
        hardware_context.manager != NULL && hardware_context.device_set != NULL &&
        hardware_context.items[0].location_id == 13 && hardware_context.items[0].is_mouse &&
        hardware_context.items[1].product_id == 0x4085 &&
        hardware_context.items[1].prefer_long_reports &&
        hardware_context.items[2].product_id == 0xC539 &&
        hardware_context.items[2].prefer_long_reports &&
        hardware_context.items[4].product_id == G600_PRODUCT_ID;
    hid_context_release(&hardware_context);
    hardware_ok =
        hardware_ok && g_discovery_release_calls == 2 && g_discovery_manager_close_calls == 0;
    g_discovery_manager_mode = 1;
    HidContext manager_failure_context;
    hardware_ok = hardware_ok && !hid_context_create_hardware(&manager_failure_context);
    g_discovery_manager_mode = 2;
    hardware_ok = hardware_ok && !hid_context_create_hardware(&manager_failure_context) &&
                  g_discovery_release_calls == 3;
    g_discovery_manager_mode = 0;
    g_discovery_set_count = 0;
    hardware_ok = hardware_ok && hid_context_create_hardware(&manager_failure_context);
    hid_context_release(&manager_failure_context);
    hardware_ok = hardware_ok && g_discovery_release_calls == 5;

    HidContext release_context = {0};
    release_context.manager = (IOHIDManagerRef)(uintptr_t)0x11;
    release_context.device_set = (CFSetRef)(uintptr_t)0x22;
    release_context.manager_open = true;
    release_context.items = calloc(1, sizeof(*release_context.items));
    bool release_ok = release_context.items != NULL;
    if (release_ok) {
        release_context.count = 1;
        release_context.items[0].channel_open = true;
        release_context.items[0].channel.device = (IOHIDDeviceRef)(uintptr_t)1;
        release_context.items[0].channel.opened = true;
        release_context.items[0].channel.callback_buffer = calloc(MAX_REPORT_BYTES, 1);
        pthread_mutex_init(&release_context.items[0].channel.lock, NULL);
        hid_device_close_impl = discovery_channel_close_double;
        hid_device_unschedule_from_run_loop_impl = discovery_channel_schedule_double;
        size_t before_close = g_discovery_manager_close_calls;
        size_t before_release = g_discovery_release_calls;
        hid_context_release(&release_context);
        release_ok = release_context.manager == NULL && release_context.device_set == NULL &&
                     g_discovery_manager_close_calls == before_close + 1 &&
                     g_discovery_release_calls == before_release + 2;
    }
    hid_context_release(NULL);
    reset_discovery_seams();
    reset_hid_test_seams();
    if (!receiver_ok || !helper_ok || !ping_ok || !name_ok || !feature_ok || !receiver_name_ok ||
        !closed_ok || !open_channels_ok || !direct_request_ok || !key_fallback_ok ||
        !receiver_key_ok || !options_hardware_ok || !hardware_ok || !release_ok) {
        fprintf(stderr,
                "receiver discovery flags receiver=%d helper=%d ping=%d name=%d feature=%d "
                "receiver-name=%d closed=%d open=%d direct=%d key=%d receiver-key=%d options=%d "
                "hardware=%d release=%d\n",
                receiver_ok, helper_ok, ping_ok, name_ok, feature_ok, receiver_name_ok, closed_ok,
                open_channels_ok, direct_request_ok, key_fallback_ok, receiver_key_ok,
                options_hardware_ok, hardware_ok, release_ok);
        return 1;
    }

    return 0;
}
