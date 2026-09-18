#ifndef LOPE_LOGITECH_ONBOARD_COMMANDS_BACKUP_BIND_H
#define LOPE_LOGITECH_ONBOARD_COMMANDS_BACKUP_BIND_H

#include "types.h"

int run_dump(const Options *options);
int parse_hex_byte(const char *text, uint8_t *value);
int parse_hex_word(const char *text, uint16_t *value);
bool parse_target(const char *target, uint8_t spec[4]);
int run_bind(const Options *options);
int run_restore(const Options *options);

#endif // LOPE_LOGITECH_ONBOARD_COMMANDS_BACKUP_BIND_H
