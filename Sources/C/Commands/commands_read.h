#ifndef LOPE_LOGITECH_ONBOARD_COMMANDS_READ_H
#define LOPE_LOGITECH_ONBOARD_COMMANDS_READ_H

#include "types.h"

int run_list(void);
int select_device(Device *devices, size_t count, const Options *options, Device **selected);
int run_info(const Options *options);
int run_profiles(const Options *options);
void print_supported_dpi(const uint16_t *values, size_t count);
int run_dpi(const Options *options);
int run_current_dpi(const Options *options);
int parse_dpi_values(const char *text, uint16_t values[5], size_t *count_out);

#endif // LOPE_LOGITECH_ONBOARD_COMMANDS_READ_H
