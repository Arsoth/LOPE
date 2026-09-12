typedef struct {
    uint8_t *callback_buffer;
    uint8_t previous_buttons;
    bool have_previous;
    char label[256];
} WatchState;

static const char *mouse_button_name(uint8_t bit) {
    switch (bit) {
    case 0:
        return "Left";
    case 1:
        return "Right";
    case 2:
        return "Middle";
    case 3:
        return "Back / rear thumb";
    case 4:
        return "Forward";
    case 5:
        return "Button 6";
    case 6:
        return "Button 7";
    case 7:
        return "Button 8";
    default:
        return "unknown";
    }
}

static void watch_report_callback(void *context, IOReturn result, void *sender,
                                  IOHIDReportType type, uint32_t report_id, uint8_t *report,
                                  CFIndex report_length) {
    (void)result;
    (void)sender;
    (void)type;
    WatchState *state = (WatchState *)context;
    if (state == NULL || report == NULL || report_length < 1) {
        return;
    }
    // Standard HID mouse reports put the button bitmap before X/Y motion.
    // Numbered reports include their ID in the raw callback buffer on macOS;
    // unnumbered reports begin directly with the button bitmap.
    size_t button_offset = (report_id != 0 && report_length > 1 && report[0] == report_id) ? 1 : 0;
    uint8_t buttons = report[button_offset];
    if (!state->have_previous) {
        state->previous_buttons = buttons;
        state->have_previous = true;
        return;
    }
    uint8_t pressed = (uint8_t)((buttons ^ state->previous_buttons) & buttons);
    state->previous_buttons = buttons;
    for (uint8_t bit = 0; bit < 8; bit++) {
        if ((pressed & (uint8_t)(1u << bit)) != 0) {
            printf("[%s] press: HID button %u (%s), report 0x%02X\n", state->label, bit + 1,
                   mouse_button_name(bit), report_id);
            fflush(stdout);
        }
    }
}

static int run_watch(const Options *options) {
    HidContext context;
    if (!hid_context_create(&context)) {
        return 1;
    }
    size_t mouse_index = 0;
    HidInterface *mouse = NULL;
    for (size_t i = 0; i < context.count; i++) {
        if (!context.items[i].is_mouse) {
            continue;
        }
        if (options->device_index >= 0 && (int)mouse_index != options->device_index) {
            mouse_index++;
            continue;
        }
        mouse = &context.items[i];
        break;
    }
    if (mouse == NULL) {
        fprintf(stderr, "no Logitech standard mouse input interface found\n");
        hid_context_release(&context);
        return 1;
    }
    if (IOHIDDeviceOpen(mouse->device, kIOHIDOptionsTypeNone) != kIOReturnSuccess) {
        fprintf(stderr, "could not open the mouse input interface\n");
        hid_context_release(&context);
        return 1;
    }
    WatchState state;
    memset(&state, 0, sizeof(state));
    state.callback_buffer = (uint8_t *)calloc(MAX_REPORT_BYTES, 1);
    snprintf(state.label, sizeof(state.label), "%s",
             mouse->product[0] ? mouse->product : "Logitech mouse");
    if (state.callback_buffer == NULL) {
        IOHIDDeviceClose(mouse->device, kIOHIDOptionsTypeNone);
        hid_context_release(&context);
        return 1;
    }
    IOHIDDeviceRegisterInputReportCallback(mouse->device, state.callback_buffer, MAX_REPORT_BYTES,
                                           watch_report_callback, &state);
    IOHIDDeviceScheduleWithRunLoop(mouse->device, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    signal(SIGINT, on_sigint);
    printf("Watching %s. Press the rear thumb button once; Ctrl-C stops.\n", state.label);
    printf("A standard Logitech mouse report commonly identifies the rear thumb as HID button 4 / "
           "Back (bit 3).\n");
    while (!g_stop_watch) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.10, true);
    }
    IOHIDDeviceUnscheduleFromRunLoop(mouse->device, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    IOHIDDeviceClose(mouse->device, kIOHIDOptionsTypeNone);
    free(state.callback_buffer);
    hid_context_release(&context);
    g_stop_watch = 0;
    return 0;
}

static void print_usage(const char *program) {
    printf("Usage: %s [global options] command [arguments]\n\n", program);
    printf("Read-only commands:\n");
    printf("  list                                  enumerate Logitech HID++ devices\n");
    printf("  info                                  show capabilities and a selected profile\n");
    printf("  profiles                             inspect profile headers and button records\n");
    printf(
        "  dpi                                  show supported/current and onboard DPI stages\n");
    printf("  current-dpi                          read only the current sensor 1 DPI\n");
    printf("  set-report-rate HZ                   set and verify the active polling rate\n");
    printf("  dump FILE                            save active profile as a backup package\n");
    printf("  watch                                identify physical mouse button reports\n");
    printf("  self-test                            run local CRC/layout tests\n\n");
    printf("Write commands (preview-only unless --yes is supplied):\n");
    printf(
        "  bind rear-thumb alt-tab              preview the rear thumb -> Left Alt+Tab change\n");
    printf("  bind --button N alt-tab              preview an explicit profile button change\n");
    printf("  set-dpi 800,1600                       preview a one-to-five-stage onboard DPI "
           "change\n");
    printf("  set-profile-state N enable|disable   preview enabling or disabling profile N\n");
    printf("  apply                                 apply a single GUI save operation\n");
    printf("  restore FILE                         preview restoring a backup package\n\n");
    printf("Global options:\n");
    printf("  --device N                           logical device index from list\n");
    printf("  --slot N|ff                          receiver slot 1..6 or direct 0xff\n");
    printf("  --profile N                          1-based profile number\n");
    printf("  --summary-only                       read only the selected profile prefix\n");
    printf("  --with-dpi                           include sensor and onboard DPI data\n");
    printf("  --with-report-rate                   include active-connection polling-rate data\n");
    printf("  --button N                           explicit profile button number for bind\n");
    printf("  --default N                          onboard default DPI stage, 1..5\n");
    printf("  --shift N                            onboard DPI-shift stage, 1..5\n");
    printf("  --backup FILE                        backup path for bind\n");
    printf("  --button-change normal:N:RAW         batch normal-layer record (apply; RAW is 8 hex "
           "digits)\n");
    printf("  --button-change gshift:N:RAW         batch G-Shift-layer record (apply)\n");
    printf(
        "  --rgb-change N:RRGGBB                batch RGB zone color (apply; zone is 1-based)\n");
    printf("  --dpi VALUES                         batch DPI stages, comma-separated\n");
    printf("  --report-rate HZ                     batch profile polling rate (apply)\n");
    printf("  --profile-state-change N:STATE       batch profile state (enable or disable)\n");
    printf("  --backup-directory DIR               directory for an apply operation's backups\n");
    printf("  --operation-id ID                    stable ID shared by all apply backups\n");
    printf("  --yes                                permit the requested mouse write\n");
    printf("  --help                               show this help\n");
}

static int parse_decimal(const char *text, int *value) {
    if (text == NULL || *text == '\0') {
        return 0;
    }
    char *end = NULL;
    errno = 0;
    long parsed = strtol(text, &end, 10);
    if (errno != 0 || end == text || *end != '\0' || parsed < 0 || parsed > 100000) {
        return 0;
    }
    *value = (int)parsed;
    return 1;
}

static int parse_slot(const char *text, int *slot) {
    if (strcmp(text, "ff") == 0 || strcmp(text, "FF") == 0 || strcmp(text, "0xff") == 0 ||
        strcmp(text, "0xFF") == 0) {
        *slot = 0xFF;
        return 1;
    }
    int parsed = 0;
    if (!parse_decimal(text, &parsed) || parsed < 1 || parsed > 6) {
        return 0;
    }
    *slot = parsed;
    return 1;
}

static int parse_options(int argc, char **argv, Options *options) {
    memset(options, 0, sizeof(*options));
    options->device_index = -1;
    options->slot = -1;
    options->dpi_default = -1;
    options->dpi_shift = -1;
    for (int i = 1; i < argc; i++) {
        const char *arg = argv[i];
        if (strcmp(arg, "--help") == 0 || strcmp(arg, "-h") == 0) {
            print_usage(argv[0]);
            exit(0);
        }
        if (strcmp(arg, "--yes") == 0) {
            options->yes = true;
            continue;
        }
        if (strcmp(arg, "--headers-only") == 0) {
            options->headers_only = true;
            continue;
        }
        if (strcmp(arg, "--summary-only") == 0) {
            options->summary_only = true;
            continue;
        }
        if (strcmp(arg, "--sensor-only") == 0) {
            options->sensor_only = true;
            continue;
        }
        if (strcmp(arg, "--with-dpi") == 0) {
            options->include_dpi = true;
            continue;
        }
        if (strcmp(arg, "--with-report-rate") == 0) {
            options->include_report_rate = true;
            continue;
        }
        if (strcmp(arg, "--device") == 0 || strcmp(arg, "--device-key") == 0 ||
            strcmp(arg, "--slot") == 0 || strcmp(arg, "--profile") == 0 ||
            strcmp(arg, "--button") == 0 || strcmp(arg, "--backup") == 0 ||
            strcmp(arg, "--default") == 0 || strcmp(arg, "--shift") == 0 ||
            strcmp(arg, "--dpi") == 0 || strcmp(arg, "--report-rate") == 0 ||
            strcmp(arg, "--button-change") == 0 || strcmp(arg, "--rgb-change") == 0 ||
            strcmp(arg, "--profile-state-change") == 0 || strcmp(arg, "--backup-directory") == 0 ||
            strcmp(arg, "--operation-id") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "%s requires a value\n", arg);
                return 0;
            }
            const char *value = argv[++i];
            if (strcmp(arg, "--device") == 0) {
                if (!parse_decimal(value, &options->device_index)) {
                    fprintf(stderr, "invalid --device value '%s'\n", value);
                    return 0;
                }
            } else if (strcmp(arg, "--device-key") == 0) {
                options->device_key = value;
            } else if (strcmp(arg, "--slot") == 0) {
                if (!parse_slot(value, &options->slot)) {
                    fprintf(stderr, "invalid --slot value '%s'\n", value);
                    return 0;
                }
            } else if (strcmp(arg, "--profile") == 0) {
                if (!parse_decimal(value, &options->profile) || options->profile < 1) {
                    fprintf(stderr, "invalid --profile value '%s'\n", value);
                    return 0;
                }
            } else if (strcmp(arg, "--button") == 0) {
                if (!parse_decimal(value, &options->button) || options->button < 1) {
                    fprintf(stderr, "invalid --button value '%s'\n", value);
                    return 0;
                }
            } else if (strcmp(arg, "--default") == 0) {
                if (!parse_decimal(value, &options->dpi_default) || options->dpi_default < 1 ||
                    options->dpi_default > 5) {
                    fprintf(stderr, "invalid --default value '%s'\n", value);
                    return 0;
                }
            } else if (strcmp(arg, "--shift") == 0) {
                if (!parse_decimal(value, &options->dpi_shift) || options->dpi_shift < 1 ||
                    options->dpi_shift > 5) {
                    fprintf(stderr, "invalid --shift value '%s'\n", value);
                    return 0;
                }
            } else if (strcmp(arg, "--dpi") == 0) {
                options->dpi_values = value;
            } else if (strcmp(arg, "--report-rate") == 0) {
                options->report_rate = value;
            } else if (strcmp(arg, "--button-change") == 0) {
                if (options->button_change_count >= MAX_BATCH_BUTTON_CHANGES) {
                    fprintf(stderr, "too many --button-change values\n");
                    return 0;
                }
                options->button_changes[options->button_change_count++] = value;
            } else if (strcmp(arg, "--rgb-change") == 0) {
                if (options->rgb_change_count >= MAX_BATCH_RGB_CHANGES) {
                    fprintf(stderr, "too many --rgb-change values\n");
                    return 0;
                }
                options->rgb_changes[options->rgb_change_count++] = value;
            } else if (strcmp(arg, "--profile-state-change") == 0) {
                if (options->profile_state_change_count >= MAX_BATCH_PROFILE_CHANGES) {
                    fprintf(stderr, "too many --profile-state-change values\n");
                    return 0;
                }
                options->profile_state_changes[options->profile_state_change_count++] = value;
            } else if (strcmp(arg, "--backup-directory") == 0) {
                options->backup_directory = value;
            } else if (strcmp(arg, "--operation-id") == 0) {
                options->operation_id = value;
            } else {
                options->backup_path = value;
            }
            continue;
        }
        if (arg[0] == '-') {
            fprintf(stderr, "unknown option '%s'\n", arg);
            return 0;
        }
        if (options->command == NULL) {
            options->command = arg;
        } else if (options->positional_count < 8) {
            options->positionals[options->positional_count++] = arg;
        } else {
            fprintf(stderr, "too many command arguments\n");
            return 0;
        }
    }
    if (options->command == NULL) {
        options->command = "list";
    }
    if (options->device_index >= 0 && options->device_key != NULL) {
        fprintf(stderr, "use either --device or --device-key, not both\n");
        return 0;
    }
    if ((options->device_index >= 0 || options->device_key != NULL) && options->slot >= 0) {
        fprintf(stderr, "use a device selector or --slot, not both\n");
        return 0;
    }
    if (strcmp(options->command, "dump") == 0 || strcmp(options->command, "restore") == 0) {
        if (options->positional_count != 1) {
            fprintf(stderr, "%s requires exactly one FILE argument\n", options->command);
            return 0;
        }
        options->path = options->positionals[0];
    } else if (strcmp(options->command, "bind") == 0) {
        if (options->positional_count == 2 && strcmp(options->positionals[0], "rear-thumb") == 0) {
            options->target = options->positionals[1];
        } else if (options->positional_count == 1) {
            options->target = options->positionals[0];
        } else {
            fprintf(stderr, "bind syntax: bind rear-thumb alt-tab or bind --button N alt-tab\n");
            return 0;
        }
    } else if (strcmp(options->command, "set-dpi") == 0) {
        if (options->positional_count != 1) {
            fprintf(stderr, "set-dpi requires one comma-separated list with one to five stages\n");
            return 0;
        }
    } else if (strcmp(options->command, "set-profile-state") == 0) {
        if (options->positional_count != 2) {
            fprintf(stderr, "set-profile-state syntax: set-profile-state N enable|disable\n");
            return 0;
        }
    } else if (strcmp(options->command, "set-report-rate") == 0) {
        if (options->positional_count != 1) {
            fprintf(stderr, "set-report-rate syntax: set-report-rate HZ\n");
            return 0;
        }
    } else if (strcmp(options->command, "apply") == 0) {
        if (options->positional_count != 0) {
            fprintf(stderr, "apply does not take positional arguments\n");
            return 0;
        }
    } else if (options->positional_count != 0) {
        fprintf(stderr, "%s does not take positional arguments\n", options->command);
        return 0;
    }
    return 1;
}
