#ifndef LOPE_LOGITECH_ONBOARD_PROFILE_RENDERING_H
#define LOPE_LOGITECH_ONBOARD_PROFILE_RENDERING_H

#include "types.h"

const char *function_name(uint8_t value);
const char *key_name(uint8_t code);
void describe_spec(const uint8_t spec[4], char *out, size_t out_size);
bool spec_is_back(const uint8_t spec[4]);
void print_hex4(const uint8_t bytes[4]);
void print_profile_summary(const Profile *profile, bool show_buttons);
int find_rear_thumb_button(const Profile *profile);
void print_feature_list(const Device *device);
void print_device_line(const Device *device, size_t index);

#endif // LOPE_LOGITECH_ONBOARD_PROFILE_RENDERING_H
