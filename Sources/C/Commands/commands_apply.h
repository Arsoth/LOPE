#ifndef LOPE_LOGITECH_ONBOARD_COMMANDS_APPLY_H
#define LOPE_LOGITECH_ONBOARD_COMMANDS_APPLY_H

#include "types.h"

typedef struct {
    uint16_t sector;
    const uint8_t *data;
    size_t length;
    const char *kind;
} BatchSector;

typedef bool (*BatchSectorWriter)(void *context, const BatchSector *sector);

bool parse_batch_raw_record(const char *text, uint8_t spec[4]);
bool parse_batch_button_change(const char *text, int *button, bool *gshift, uint8_t spec[4]);
bool parse_batch_rgb_change(const char *text, int *zone, uint8_t color[3]);
bool parse_batch_profile_state(const char *text, int *profile, bool *enabled);
bool batch_operation_id_is_safe(const char *operation_id);
bool make_batch_backup_path(const char *directory, const char *operation_id, char path[512]);
bool batch_sector_changed(const uint8_t *before, const uint8_t *after, size_t length);
size_t batch_affected_sector_count(bool profile_changed, bool control_changed);
bool execute_batch_sector_plan(const BatchSector *plan, size_t plan_count, BatchSectorWriter writer,
                               void *context, size_t *verified_count, size_t *failed_index);
void print_batch_recovery(const char *operation_id, size_t verified_count, const char *failed_kind,
                          uint16_t failed_sector, const char *backup_path, bool has_backup);
int run_apply(const Options *options);

#endif // LOPE_LOGITECH_ONBOARD_COMMANDS_APPLY_H
