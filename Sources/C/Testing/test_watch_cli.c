#include "hid_discovery.h"
#include "hid_transport.h"
#include "watch_cli.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int watch_context_create_failure(HidContext *context) {
    (void)context;
    return 0;
}

static int watch_context_create_empty(HidContext *context) {
    memset(context, 0, sizeof(*context));
    return 1;
}

static int watch_context_create_with_mouse(HidContext *context) {
    memset(context, 0, sizeof(*context));
    context->items = (HidInterface *)calloc(1, sizeof(HidInterface));
    if (context->items == NULL) {
        return 0;
    }
    context->count = 1;
    context->items[0].is_mouse = true;
    snprintf(context->items[0].product, sizeof(context->items[0].product), "Coverage mouse");
    return 1;
}

static int watch_context_create_with_nonmouse_and_mouse(HidContext *context) {
    memset(context, 0, sizeof(*context));
    context->items = (HidInterface *)calloc(2, sizeof(HidInterface));
    if (context->items == NULL) {
        return 0;
    }
    context->count = 2;
    context->items[0].is_mouse = false;
    context->items[1].is_mouse = true;
    snprintf(context->items[1].product, sizeof(context->items[1].product), "Coverage mouse");
    return 1;
}

static int watch_context_create_with_two_mice(HidContext *context) {
    memset(context, 0, sizeof(*context));
    context->items = (HidInterface *)calloc(2, sizeof(HidInterface));
    if (context->items == NULL) {
        return 0;
    }
    context->count = 2;
    context->items[0].is_mouse = true;
    context->items[1].is_mouse = true;
    snprintf(context->items[0].product, sizeof(context->items[0].product), "First mouse");
    return 1;
}

static IOReturn watch_device_open_failure(IOHIDDeviceRef device, IOOptionBits options) {
    (void)device;
    (void)options;
    return kIOReturnError;
}

static IOReturn watch_device_open_success(IOHIDDeviceRef device, IOOptionBits options) {
    (void)device;
    (void)options;
    return kIOReturnSuccess;
}

static IOReturn watch_device_close_noop(IOHIDDeviceRef device, IOOptionBits options) {
    (void)device;
    (void)options;
    return kIOReturnSuccess;
}

static void watch_register_input_report_noop(IOHIDDeviceRef device, uint8_t *report,
                                             CFIndex report_length, IOHIDReportCallback callback,
                                             void *context) {
    (void)device;
    (void)report;
    (void)report_length;
    (void)callback;
    (void)context;
}

static void watch_run_loop_schedule_noop(IOHIDDeviceRef device, CFRunLoopRef run_loop,
                                         CFRunLoopMode mode) {
    (void)device;
    (void)run_loop;
    (void)mode;
}

static CFRunLoopRunResult watch_run_loop_stop(CFRunLoopMode mode, CFTimeInterval seconds,
                                              Boolean return_after_source_handled) {
    (void)mode;
    (void)seconds;
    (void)return_after_source_handled;
    g_stop_watch = 1;
    return kCFRunLoopRunFinished;
}

static void *watch_buffer_allocate_failure(size_t count, size_t size) {
    (void)count;
    (void)size;
    return NULL;
}

int test_watch_cli(void) {
    bool mouse_button_name_ok = strcmp(mouse_button_name(0), "Left") == 0 &&
                                strcmp(mouse_button_name(1), "Right") == 0 &&
                                strcmp(mouse_button_name(2), "Middle") == 0 &&
                                strcmp(mouse_button_name(3), "Back / rear thumb") == 0 &&
                                strcmp(mouse_button_name(4), "Forward") == 0 &&
                                strcmp(mouse_button_name(5), "Button 6") == 0 &&
                                strcmp(mouse_button_name(6), "Button 7") == 0 &&
                                strcmp(mouse_button_name(7), "Button 8") == 0 &&
                                strcmp(mouse_button_name(9), "unknown") == 0;
    int decimal_value = 0;
    int slot_value = 0;
    bool decimal_slot_ok =
        parse_decimal("42", &decimal_value) && decimal_value == 42 &&
        !parse_decimal(NULL, &decimal_value) && !parse_decimal("", &decimal_value) &&
        !parse_decimal("-1", &decimal_value) && !parse_decimal("100001", &decimal_value) &&
        !parse_decimal("12x", &decimal_value) &&
        !parse_decimal("999999999999999999999999999999", &decimal_value) &&
        parse_slot("ff", &slot_value) && slot_value == 0xFF && parse_slot("FF", &slot_value) &&
        slot_value == 0xFF && parse_slot("0xff", &slot_value) && slot_value == 0xFF &&
        parse_slot("0xFF", &slot_value) && slot_value == 0xFF && parse_slot("3", &slot_value) &&
        slot_value == 3 && !parse_slot("0", &slot_value) && !parse_slot("7", &slot_value) &&
        !parse_slot("bad", &slot_value) && !parse_slot(NULL, &slot_value) && !parse_slot("3", NULL);
    if (!mouse_button_name_ok || !decimal_slot_ok) {
        fprintf(stderr, "mouse_button_name/parse_decimal/parse_slot self-test failed\n");
        return 1;
    }

    Options watch_options = {.device_index = -1};
    hid_context_create_impl = watch_context_create_failure;
    if (run_watch(&watch_options) != 1) {
        fprintf(stderr, "run_watch context-failure self-test failed\n");
        return 1;
    }
    hid_context_create_impl = watch_context_create_empty;
    if (run_watch(&watch_options) != 1) {
        fprintf(stderr, "run_watch no-mouse self-test failed\n");
        return 1;
    }
    hid_context_create_impl = watch_context_create_with_mouse;
    watch_device_open_impl = watch_device_open_failure;
    if (run_watch(&watch_options) != 1) {
        fprintf(stderr, "run_watch open-failure self-test failed\n");
        return 1;
    }
    watch_device_open_impl = watch_device_open_success;
    watch_device_close_impl = watch_device_close_noop;
    watch_buffer_allocate_impl = watch_buffer_allocate_failure;
    if (run_watch(&watch_options) != 1) {
        fprintf(stderr, "run_watch allocation-failure self-test failed\n");
        return 1;
    }
    watch_buffer_allocate_impl = calloc;
    watch_register_input_report_impl = watch_register_input_report_noop;
    watch_schedule_with_run_loop_impl = watch_run_loop_schedule_noop;
    watch_unschedule_from_run_loop_impl = watch_run_loop_schedule_noop;
    watch_run_loop_impl = watch_run_loop_stop;
    g_stop_watch = 0;
    if (run_watch(&watch_options) != 0) {
        fprintf(stderr, "run_watch success self-test failed\n");
        return 1;
    }

    hid_context_create_impl = watch_context_create_with_nonmouse_and_mouse;
    watch_options.device_index = -1;
    if (run_watch(&watch_options) != 0) {
        fprintf(stderr, "run_watch non-mouse-interface self-test failed\n");
        return 1;
    }

    hid_context_create_impl = watch_context_create_with_two_mice;
    watch_options.device_index = 1;
    if (run_watch(&watch_options) != 0) {
        fprintf(stderr, "run_watch indexed-mouse self-test failed\n");
        return 1;
    }
    hid_context_create_impl = hid_context_create_hardware;
    watch_device_open_impl = IOHIDDeviceOpen;
    watch_device_close_impl = IOHIDDeviceClose;
    watch_buffer_allocate_impl = calloc;
    watch_register_input_report_impl = IOHIDDeviceRegisterInputReportCallback;
    watch_schedule_with_run_loop_impl = IOHIDDeviceScheduleWithRunLoop;
    watch_unschedule_from_run_loop_impl = IOHIDDeviceUnscheduleFromRunLoop;
    watch_run_loop_impl = CFRunLoopRunInMode;

    typedef struct {
        uint8_t *callback_buffer;
        uint8_t previous_buttons;
        bool have_previous;
        char label[256];
    } WatchCallbackTestState;
    WatchCallbackTestState watch_state = {0};
    snprintf(watch_state.label, sizeof(watch_state.label), "test mouse");
    uint8_t numbered_report[] = {REPORT_SHORT, 0x01};
    uint8_t numbered_press[] = {REPORT_SHORT, 0x09};
    uint8_t unnumbered_press[] = {0x02};
    char callback_path[] = "/tmp/lomps-selftest-watch-callback-XXXXXX";
    int callback_fd = mkstemp(callback_path);
    int callback_saved_stdout = callback_fd >= 0 ? dup(fileno(stdout)) : -1;
    bool callback_ok =
        callback_fd >= 0 && callback_saved_stdout >= 0 && dup2(callback_fd, fileno(stdout)) >= 0;
    if (callback_fd >= 0) {
        close(callback_fd);
    }
    if (callback_ok) {
        watch_report_callback_for_test(NULL, 0, NULL, 0, 0, NULL, 0);
        watch_report_callback_for_test(&watch_state, 0, NULL, 0, 0, NULL, 1);
        watch_report_callback_for_test(&watch_state, 0, NULL, 0, 0, numbered_report, 0);
        watch_report_callback_for_test(&watch_state, 0, NULL, 0, REPORT_SHORT, numbered_report,
                                       (CFIndex)sizeof(numbered_report));
        watch_report_callback_for_test(&watch_state, 0, NULL, 0, REPORT_SHORT, numbered_press,
                                       (CFIndex)sizeof(numbered_press));
        watch_report_callback_for_test(&watch_state, 0, NULL, 0, REPORT_SHORT, numbered_press,
                                       (CFIndex)sizeof(numbered_press));
        uint8_t short_numbered_report[] = {0x07};
        watch_report_callback_for_test(&watch_state, 0, NULL, 0, REPORT_SHORT,
                                       short_numbered_report,
                                       (CFIndex)sizeof(short_numbered_report));
        uint8_t mismatched_id_report[] = {0x00, 0x04};
        watch_report_callback_for_test(&watch_state, 0, NULL, 0, REPORT_SHORT, mismatched_id_report,
                                       (CFIndex)sizeof(mismatched_id_report));
        watch_report_callback_for_test(&watch_state, 0, NULL, 0, 0, unnumbered_press,
                                       (CFIndex)sizeof(unnumbered_press));
        fflush(stdout);
    }
    if (callback_saved_stdout >= 0) {
        dup2(callback_saved_stdout, fileno(stdout));
        close(callback_saved_stdout);
        clearerr(stdout);
    }
    char callback_contents[2048] = {0};
    if (callback_ok) {
        FILE *callback_readback = fopen(callback_path, "r");
        if (callback_readback != NULL) {
            size_t callback_bytes =
                fread(callback_contents, 1, sizeof(callback_contents) - 1, callback_readback);
            callback_contents[callback_bytes] = '\0';
            fclose(callback_readback);
        } else {
            callback_ok = false;
        }
    }
    unlink(callback_path);
    callback_ok = callback_ok && callback_contents[0] != '\0' && watch_state.have_previous &&
                  watch_state.previous_buttons == 0x02;
    if (!callback_ok) {
        fprintf(stderr, "watch report callback self-test failed\n");
        return 1;
    }

    char usage_path[] = "/tmp/lomps-selftest-usage-XXXXXX";
    int usage_fd = mkstemp(usage_path);
    if (usage_fd < 0) {
        fprintf(stderr, "print_usage self-test failed to create temp file\n");
        return 1;
    }
    close(usage_fd);
    int usage_saved_stdout = dup(fileno(stdout));
    bool usage_ok = usage_saved_stdout >= 0 && freopen(usage_path, "w", stdout) != NULL;
    if (usage_ok) {
        print_usage("lope");
        fflush(stdout);
    }
    if (usage_saved_stdout >= 0) {
        dup2(usage_saved_stdout, fileno(stdout));
        close(usage_saved_stdout);
        clearerr(stdout);
    }
    char usage_contents[4096] = {0};
    if (usage_ok) {
        FILE *readback = fopen(usage_path, "r");
        if (readback != NULL) {
            size_t read_bytes = fread(usage_contents, 1, sizeof(usage_contents) - 1, readback);
            usage_contents[read_bytes] = '\0';
            fclose(readback);
        } else {
            usage_ok = false;
        }
    }
    unlink(usage_path);
    usage_ok = usage_ok && strstr(usage_contents, "lope") != NULL;
    if (!usage_ok) {
        fprintf(stderr, "print_usage self-test failed\n");
        return 1;
    }

    Options parsed;
    char *default_command_argv[] = {"lope"};
    bool parse_options_ok =
        parse_options(1, default_command_argv, &parsed) && strcmp(parsed.command, "list") == 0;

    char *flags_argv[] = {"lope",           "list",          "--yes",      "--headers-only",
                          "--summary-only", "--sensor-only", "--with-dpi", "--with-report-rate"};
    parse_options_ok = parse_options_ok && parse_options(8, flags_argv, &parsed) && parsed.yes &&
                       parsed.headers_only && parsed.summary_only && parsed.sensor_only &&
                       parsed.include_dpi && parsed.include_report_rate;

    char *json_argv[] = {"lope", "list", "--format", "json", "--json"};
    parse_options_ok =
        parse_options_ok && parse_options(5, json_argv, &parsed) && parsed.structured_output;

    char *format_missing_argv[] = {"lope", "list", "--format"};
    parse_options_ok = parse_options_ok && !parse_options(3, format_missing_argv, &parsed);

    char *format_invalid_argv[] = {"lope", "list", "--format", "text"};
    parse_options_ok = parse_options_ok && !parse_options(4, format_invalid_argv, &parsed);

    char *missing_value_argv[] = {"lope", "list", "--device"};
    parse_options_ok = parse_options_ok && !parse_options(3, missing_value_argv, &parsed);

    char *invalid_device_argv[] = {"lope", "list", "--device", "abc"};
    parse_options_ok = parse_options_ok && !parse_options(4, invalid_device_argv, &parsed);

    char *device_key_argv[] = {"lope", "list", "--device-key", "1-2-3"};
    parse_options_ok = parse_options_ok && parse_options(4, device_key_argv, &parsed) &&
                       strcmp(parsed.device_key, "1-2-3") == 0;

    char *invalid_slot_argv[] = {"lope", "list", "--slot", "99"};
    parse_options_ok = parse_options_ok && !parse_options(4, invalid_slot_argv, &parsed);

    char *invalid_profile_argv[] = {"lope", "info", "--profile", "0"};
    parse_options_ok = parse_options_ok && !parse_options(4, invalid_profile_argv, &parsed);

    char *invalid_button_argv[] = {"lope", "bind", "--button", "0", "alt-tab"};
    parse_options_ok = parse_options_ok && !parse_options(5, invalid_button_argv, &parsed);

    char *invalid_default_argv[] = {"lope", "set-dpi", "--default", "6", "800"};
    parse_options_ok = parse_options_ok && !parse_options(5, invalid_default_argv, &parsed);

    char *invalid_shift_argv[] = {"lope", "set-dpi", "--shift", "0", "800"};
    parse_options_ok = parse_options_ok && !parse_options(5, invalid_shift_argv, &parsed);

    char *shift_too_large_argv[] = {"lope", "set-dpi", "--shift", "6", "800"};
    parse_options_ok = parse_options_ok && !parse_options(5, shift_too_large_argv, &parsed);

    char *state_too_many_argv[(MAX_BATCH_PROFILE_CHANGES + 1) * 2 + 2];
    state_too_many_argv[0] = "lope";
    state_too_many_argv[1] = "apply";
    for (size_t i = 0; i < MAX_BATCH_PROFILE_CHANGES + 1; i++) {
        state_too_many_argv[2 + i * 2] = "--profile-state-change";
        state_too_many_argv[3 + i * 2] = "1:enable";
    }
    parse_options_ok =
        parse_options_ok && !parse_options((int)((MAX_BATCH_PROFILE_CHANGES + 1) * 2 + 2),
                                           state_too_many_argv, &parsed);

    char *dpi_report_rate_argv[] = {"lope",
                                    "apply",
                                    "--dpi",
                                    "800,1600",
                                    "--report-rate",
                                    "1000",
                                    "--backup-directory",
                                    "/tmp",
                                    "--operation-id",
                                    "op-1"};
    parse_options_ok =
        parse_options_ok && parse_options(10, dpi_report_rate_argv, &parsed) &&
        strcmp(parsed.dpi_values, "800,1600") == 0 && strcmp(parsed.report_rate, "1000") == 0 &&
        strcmp(parsed.backup_directory, "/tmp") == 0 && strcmp(parsed.operation_id, "op-1") == 0;

    char *backup_and_state_argv[] = {
        "lope", "apply", "--backup", "/tmp/backup.logiob", "--profile-state-change", "2:disable"};
    parse_options_ok = parse_options_ok && parse_options(6, backup_and_state_argv, &parsed) &&
                       strcmp(parsed.backup_path, "/tmp/backup.logiob") == 0 &&
                       parsed.profile_state_change_count == 1 &&
                       strcmp(parsed.profile_state_changes[0], "2:disable") == 0;

    char *too_many_button_changes_argv[(MAX_BATCH_BUTTON_CHANGES + 1) * 2 + 2];
    too_many_button_changes_argv[0] = "lope";
    too_many_button_changes_argv[1] = "apply";
    for (size_t i = 0; i < MAX_BATCH_BUTTON_CHANGES + 1; i++) {
        too_many_button_changes_argv[2 + i * 2] = "--button-change";
        too_many_button_changes_argv[3 + i * 2] = "normal:1:80010001";
    }
    parse_options_ok =
        parse_options_ok && !parse_options((int)((MAX_BATCH_BUTTON_CHANGES + 1) * 2 + 2),
                                           too_many_button_changes_argv, &parsed);

    char *too_many_rgb_changes_argv[(MAX_BATCH_RGB_CHANGES + 1) * 2 + 2];
    too_many_rgb_changes_argv[0] = "lope";
    too_many_rgb_changes_argv[1] = "apply";
    for (size_t i = 0; i < MAX_BATCH_RGB_CHANGES + 1; i++) {
        too_many_rgb_changes_argv[2 + i * 2] = "--rgb-change";
        too_many_rgb_changes_argv[3 + i * 2] = "1:AABBCC";
    }
    parse_options_ok =
        parse_options_ok && !parse_options((int)((MAX_BATCH_RGB_CHANGES + 1) * 2 + 2),
                                           too_many_rgb_changes_argv, &parsed);

    char *unknown_option_argv[] = {"lope", "list", "--bogus"};
    parse_options_ok = parse_options_ok && !parse_options(3, unknown_option_argv, &parsed);

    char *too_many_positionals_argv[] = {"lope", "unknown", "1", "2", "3", "4",
                                         "5",    "6",       "7", "8", "9"};
    parse_options_ok = parse_options_ok && !parse_options(11, too_many_positionals_argv, &parsed);

    char *device_and_key_argv[] = {"lope", "list", "--device", "1", "--device-key", "1-2-3"};
    parse_options_ok = parse_options_ok && !parse_options(6, device_and_key_argv, &parsed);

    char *device_and_slot_argv[] = {"lope", "list", "--device", "1", "--slot", "2"};
    parse_options_ok = parse_options_ok && !parse_options(6, device_and_slot_argv, &parsed);

    char *dump_missing_path_argv[] = {"lope", "dump"};
    parse_options_ok = parse_options_ok && !parse_options(2, dump_missing_path_argv, &parsed);

    char *dump_argv[] = {"lope", "dump", "/tmp/out.bin"};
    parse_options_ok = parse_options_ok && parse_options(3, dump_argv, &parsed) &&
                       strcmp(parsed.path, "/tmp/out.bin") == 0;

    char *restore_argv[] = {"lope", "restore", "/tmp/in.logiob"};
    parse_options_ok = parse_options_ok && parse_options(3, restore_argv, &parsed) &&
                       strcmp(parsed.path, "/tmp/in.logiob") == 0;

    char *bind_rear_thumb_argv[] = {"lope", "bind", "rear-thumb", "alt-tab"};
    parse_options_ok = parse_options_ok && parse_options(4, bind_rear_thumb_argv, &parsed) &&
                       strcmp(parsed.target, "alt-tab") == 0;

    char *bind_direct_argv[] = {"lope", "bind", "alt-tab"};
    parse_options_ok = parse_options_ok && parse_options(3, bind_direct_argv, &parsed) &&
                       strcmp(parsed.target, "alt-tab") == 0;

    char *bind_bad_argv[] = {"lope", "bind", "a", "b", "c"};
    parse_options_ok = parse_options_ok && !parse_options(5, bind_bad_argv, &parsed);

    char *set_dpi_bad_argv[] = {"lope", "set-dpi"};
    parse_options_ok = parse_options_ok && !parse_options(2, set_dpi_bad_argv, &parsed);

    char *set_profile_state_bad_argv[] = {"lope", "set-profile-state", "1"};
    parse_options_ok = parse_options_ok && !parse_options(3, set_profile_state_bad_argv, &parsed);

    char *set_report_rate_bad_argv[] = {"lope", "set-report-rate"};
    parse_options_ok = parse_options_ok && !parse_options(2, set_report_rate_bad_argv, &parsed);

    char *apply_positional_argv[] = {"lope", "apply", "extra"};
    parse_options_ok = parse_options_ok && !parse_options(3, apply_positional_argv, &parsed);

    char *unknown_command_positional_argv[] = {"lope", "totally-unknown-command", "extra"};
    parse_options_ok =
        parse_options_ok && !parse_options(3, unknown_command_positional_argv, &parsed);

    if (!parse_options_ok) {
        fprintf(stderr, "parse_options self-test failed\n");
        return 1;
    }

    return 0;
}
