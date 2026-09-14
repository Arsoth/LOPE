// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

#include "internal.h"

#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    Options options;
    if (!parse_options(argc, argv, &options)) {
        if (options.structured_output) {
            EngineBoundaryError error;
            engine_boundary_error_set(&error, ENGINE_BOUNDARY_ERROR_INVALID_REQUEST,
                                      "the structured command or one of its options was malformed; "
                                      "see stderr for details");
            engine_boundary_print_error(stdout, &error);
            return 2;
        }
        print_usage(argv[0]);
        return 2;
    }
    if (options.structured_output) {
        return engine_boundary_run(&options);
    }
    if (strcmp(options.command, "self-test") == 0) {
        return run_self_test();
    }
    if (strcmp(options.command, "list") == 0) return run_list();
    if (strcmp(options.command, "info") == 0) return run_info(&options);
    if (strcmp(options.command, "profiles") == 0) return run_profiles(&options);
    if (strcmp(options.command, "dpi") == 0) return run_dpi(&options);
    if (strcmp(options.command, "current-dpi") == 0) return run_current_dpi(&options);
    if (strcmp(options.command, "set-report-rate") == 0) return run_set_report_rate(&options);
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
