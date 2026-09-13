#ifndef LOPE_LOGITECH_ONBOARD_SELFTEST_MODULES_H
#define LOPE_LOGITECH_ONBOARD_SELFTEST_MODULES_H

// One self-test entry point per C module under Sources/C/, invoked in turn
// by run_self_test() (see selftest.c). Each returns 0 on success or 1 on
// failure, printing the specific failing case to stderr before returning,
// matching the CLI self-test's existing plain-function/nonzero-status
// convention (see docs/development-standards.md's testing conventions).

int test_hid_transport(void);
int test_hid_discovery(void);
int test_profile_io(void);
int test_profile_rendering(void);
int test_report_rate(void);
int test_g600(void);
int test_backup(void);
int test_commands_read(void);
int test_commands_mutate(void);
int test_commands_backup_bind(void);
int test_watch_cli(void);

#endif // LOPE_LOGITECH_ONBOARD_SELFTEST_MODULES_H
