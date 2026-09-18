#ifndef LOPE_LOGITECH_ONBOARD_COMMANDS_SET_DPI_H
#define LOPE_LOGITECH_ONBOARD_COMMANDS_SET_DPI_H

#include "types.h"

bool dpi_value_in_list(const uint16_t *values, size_t count, uint16_t wanted);
int run_set_dpi(const Options *options);

#endif // LOPE_LOGITECH_ONBOARD_COMMANDS_SET_DPI_H
