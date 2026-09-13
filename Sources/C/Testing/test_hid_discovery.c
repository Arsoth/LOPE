#include "internal.h"
#include "test_doubles.h"

int test_hid_discovery(void) {
    Reply g603_pairing = {0};
    g603_pairing.status = REPLY_OK;
    g603_pairing.length = 8;
    g603_pairing.bytes[3] = 0x40;
    g603_pairing.bytes[4] = 0x6C;
    Reply unknown_pairing = g603_pairing;
    unknown_pairing.bytes[3] = 0x40;
    unknown_pairing.bytes[4] = 0x00;
    if (strcmp(receiver_pairing_model_name(g603_pairing), "G603 LIGHTSPEED") != 0 ||
        receiver_pairing_model_name(unknown_pairing) != NULL) {
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
    if (!discover_by_key_ok) {
        fprintf(stderr, "discover_device_by_key self-test failed\n");
        return 1;
    }

    return 0;
}
