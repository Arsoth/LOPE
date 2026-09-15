#ifndef LOPE_LOGITECH_ONBOARD_BACKUP_H
#define LOPE_LOGITECH_ONBOARD_BACKUP_H

#include "types.h"

#include <sys/stat.h>
#include <sys/types.h>

typedef ssize_t (*BackupReadFn)(int fd, void *bytes, size_t length);
typedef ssize_t (*BackupWriteFn)(int fd, const void *bytes, size_t length);
typedef int (*BackupCloseFn)(int fd);
typedef int (*BackupFstatFn)(int fd, struct stat *status);

extern BackupReadFn backup_read_impl;
extern BackupWriteFn backup_write_impl;
extern BackupCloseFn backup_close_impl;
extern BackupFstatFn backup_fstat_impl;

int package_write(const char *path, const Device *device, const Profile *profile,
                  const uint8_t *data, bool refuse_overwrite);
int package_write_multi(const char *path, const Device *device, uint8_t profile_format,
                        const BackupSectorSource *sectors, size_t sector_count,
                        bool refuse_overwrite);
int package_read(const char *path, BackupPackage *package);
void package_release(BackupPackage *package);
void default_backup_path(char *path, size_t path_size, const char *prefix);
int ensure_write_confirmation(const char *operation);
int validate_profile_for_write(const Profile *profile);

#endif // LOPE_LOGITECH_ONBOARD_BACKUP_H
