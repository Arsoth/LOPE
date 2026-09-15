#ifndef LOPE_LOGITECH_ONBOARD_REPORT_RATE_H
#define LOPE_LOGITECH_ONBOARD_REPORT_RATE_H

#include "types.h"

uint32_t report_rate_hertz_from_interval(uint8_t milliseconds);
size_t report_rate_entries_from_mask(uint16_t feature_id, uint16_t mask, ReportRateEntry *entries,
                                     size_t capacity);
uint8_t report_rate_connection_type(const Device *device);
bool read_report_rate_capabilities(Device *device, ReportRateCapabilities *capabilities);
void print_report_rate_capabilities(const ReportRateCapabilities *capabilities);
bool parse_report_rate_hertz(const char *text, uint32_t *hertz);
bool report_rate_profile_interval(Device *device, uint32_t requested_hertz, uint8_t *interval_ms);
int run_set_report_rate(const Options *options);

#endif // LOPE_LOGITECH_ONBOARD_REPORT_RATE_H
