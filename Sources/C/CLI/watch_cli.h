#ifndef LOPE_LOGITECH_ONBOARD_WATCH_CLI_H
#define LOPE_LOGITECH_ONBOARD_WATCH_CLI_H

#include "types.h"

int run_watch(const Options *options);
const char *mouse_button_name(uint8_t bit);
void print_usage(const char *program);
int parse_decimal(const char *text, int *value);
int parse_slot(const char *text, int *slot);
int parse_options(int argc, char **argv, Options *options);

#endif // LOPE_LOGITECH_ONBOARD_WATCH_CLI_H
