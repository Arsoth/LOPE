// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

// The implementation remains one translation unit so the low-level helpers
// can keep static linkage. The included chunks are ordered by dependency and
// grouped by responsibility for focused maintenance.

#include "logitech_onboard_types.inc"
#include "logitech_onboard_hid_transport.inc"
#include "logitech_onboard_hid_discovery.inc"
#include "logitech_onboard_profile_io.inc"
#include "logitech_onboard_profile_rendering.inc"
#include "logitech_onboard_backup.inc"
#include "logitech_onboard_commands_read.inc"
#include "logitech_onboard_commands_mutate.inc"
#include "logitech_onboard_commands_backup_bind.inc"
#include "logitech_onboard_watch_cli.inc"
#include "logitech_onboard_selftest.inc"

int main(int argc, char **argv) {
    Options options;
    if (!parse_options(argc, argv, &options)) {
        print_usage(argv[0]);
        return 2;
    }
    if (strcmp(options.command, "self-test") == 0) {
        return run_self_test();
    }
    if (strcmp(options.command, "list") == 0) return run_list();
    if (strcmp(options.command, "info") == 0) return run_info(&options);
    if (strcmp(options.command, "profiles") == 0) return run_profiles(&options);
    if (strcmp(options.command, "dpi") == 0) return run_dpi(&options);
    if (strcmp(options.command, "current-dpi") == 0) return run_current_dpi(&options);
    if (strcmp(options.command, "dump") == 0) return run_dump(&options);
    if (strcmp(options.command, "watch") == 0) return run_watch(&options);
    if (strcmp(options.command, "bind") == 0) return run_bind(&options);
    if (strcmp(options.command, "set-dpi") == 0) return run_set_dpi(&options);
    if (strcmp(options.command, "set-profile-state") == 0) return run_set_profile_state(&options);
    if (strcmp(options.command, "apply") == 0) return run_apply(&options);
    if (strcmp(options.command, "restore") == 0) return run_restore(&options);
    fprintf(stderr, "unknown command '%s'\n", options.command);
    print_usage(argv[0]);
    return 2;
}
