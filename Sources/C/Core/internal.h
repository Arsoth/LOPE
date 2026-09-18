#ifndef LOPE_LOGITECH_ONBOARD_INTERNAL_H
#define LOPE_LOGITECH_ONBOARD_INTERNAL_H

// The executable entrypoint uses this aggregate to dispatch every command.
// Implementation and self-test modules include only the narrower headers they
// actually use.
#include "types.h"
#include "engine_boundary.h"
#include "hid_transport.h"
#include "hid_discovery.h"
#include "profile_io.h"
#include "profile_rendering.h"
#include "g600.h"
#include "report_rate.h"
#include "backup.h"
#include "commands_read.h"
#include "commands_set_dpi.h"
#include "commands_set_profile_state.h"
#include "commands_apply.h"
#include "commands_backup_bind.h"
#include "watch_cli.h"
#include "selftest.h"

#endif // LOPE_LOGITECH_ONBOARD_INTERNAL_H
