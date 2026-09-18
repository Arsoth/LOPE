#include "backup.h"
#include "backup_codec.h"
#include "hid_discovery.h"
#include "hid_types.h"
#include "profile_codec.h"
#include "profile_io.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

BackupReadFn backup_read_impl = (BackupReadFn)read;
BackupWriteFn backup_write_impl = (BackupWriteFn)write;
BackupCloseFn backup_close_impl = close;
BackupFstatFn backup_fstat_impl = fstat;

static int write_all(int fd, const uint8_t *bytes, size_t length) {
    size_t written = 0;
    while (written < length) {
        ssize_t n = backup_write_impl(fd, bytes + written, length - written);
        if (n < 0 && errno == EINTR) {
            continue;
        }
        if (n <= 0) {
            return 0;
        }
        written += (size_t)n;
    }
    return 1;
}

static int read_all(int fd, uint8_t *bytes, size_t length) {
    size_t read_bytes = 0;
    while (read_bytes < length) {
        ssize_t n = backup_read_impl(fd, bytes + read_bytes, length - read_bytes);
        if (n < 0 && errno == EINTR) {
            continue;
        }
        if (n <= 0) {
            return 0;
        }
        read_bytes += (size_t)n;
    }
    return 1;
}

int package_write(const char *path, const Device *device, const Profile *profile,
                  const uint8_t *data, bool refuse_overwrite) {
    BackupSectorSource sector = {.sector = profile->headers[profile->selected_header].sector,
                                 .size = profile->data_length,
                                 .data = data};
    return package_write_multi(path, device, profile->info.profile_format, &sector, 1,
                               refuse_overwrite);
}

int package_write_multi(const char *path, const Device *device, uint8_t profile_format,
                        const BackupSectorSource *sectors, size_t sector_count,
                        bool refuse_overwrite) {
    if (sector_count == 0 || sector_count > MAX_BACKUP_SECTORS) {
        fprintf(stderr, "cannot create a backup package with %zu sectors\n", sector_count);
        return 0;
    }
    BackupCodecHeader codec_header = {
        .vendor_id = (uint16_t)device->iface->vendor_id,
        .product_id = (uint16_t)device_mouse_product_id(device),
        .device_number = device->request_device_number,
        .profile_format = profile_format,
        .sector_count = sector_count,
    };
    BackupCodecSector codec_sectors[MAX_BACKUP_SECTORS];
    size_t encoded_length = BACKUP_CODEC_HEADER_BYTES + sector_count * 4;
    for (size_t i = 0; i < sector_count; i++) {
        if (sectors[i].data == NULL || sectors[i].size < 32 || sectors[i].size > MAX_SECTOR_BYTES) {
            fprintf(stderr, "cannot create a backup package with invalid sector %zu metadata\n",
                    i + 1);
            return 0;
        }
        codec_sectors[i] = (BackupCodecSector){
            .sector = sectors[i].sector,
            .size = sectors[i].size,
            .data = sectors[i].data,
        };
        encoded_length += sectors[i].size;
    }
    uint8_t *encoded = (uint8_t *)malloc(encoded_length);
    if (encoded == NULL) {
        fprintf(stderr, "could not encode backup package\n");
        return 0;
    }
    // Every failure condition backup_codec_encode checks (null pointers,
    // sector_count/size bounds, out_capacity) was already validated above
    // using the identical bounds, so it cannot fail here.
    backup_codec_encode(&codec_header, codec_sectors, sector_count, encoded, encoded_length,
                        &encoded_length);

    int flags = O_WRONLY | O_CREAT | (refuse_overwrite ? O_EXCL : O_TRUNC);
    int fd = open(path, flags, 0600);
    if (fd < 0) {
        fprintf(stderr, "could not create %s: %s\n", path, strerror(errno));
        free(encoded);
        return 0;
    }
    int ok = write_all(fd, encoded, encoded_length);
    if (backup_close_impl(fd) != 0) {
        ok = 0;
    }
    free(encoded);
    if (!ok) {
        fprintf(stderr, "could not finish writing %s: %s\n", path, strerror(errno));
        return 0;
    }
    return 1;
}

void package_release(BackupPackage *package);

int package_read(const char *path, BackupPackage *package) {
    memset(package, 0, sizeof(*package));
    int fd = open(path, O_RDONLY);
    if (fd < 0) {
        fprintf(stderr, "could not open backup %s: %s\n", path, strerror(errno));
        return 0;
    }
    uint8_t header[BACKUP_HEADER_BYTES];
    if (!read_all(fd, header, sizeof(header))) {
        fprintf(stderr, "backup %s is shorter than its header\n", path);
        backup_close_impl(fd);
        return 0;
    }
    BackupCodecHeader codec_header;
    if (!backup_codec_parse_header(header, &codec_header)) {
        fprintf(stderr, "backup %s is not a recognized Logitech onboard package\n", path);
        backup_close_impl(fd);
        return 0;
    }
    struct stat st;
    uint8_t table[MAX_BACKUP_SECTORS * 4];
    size_t table_length = codec_header.sector_count * 4;
    if (!read_all(fd, table, table_length)) {
        fprintf(stderr, "backup %s is shorter than its sector table\n", path);
        backup_close_impl(fd);
        return 0;
    }
    BackupCodecSector codec_sectors[MAX_BACKUP_SECTORS];
    size_t expected_length = 0;
    if (!backup_codec_parse_sector_table(table, table_length, codec_header.sector_count,
                                         codec_sectors, &expected_length)) {
        fprintf(stderr, "backup %s has invalid sector metadata\n", path);
        backup_close_impl(fd);
        return 0;
    }
    if (backup_fstat_impl(fd, &st) != 0 || st.st_size != (off_t)expected_length) {
        fprintf(stderr, "backup %s has an unexpected file length\n", path);
        backup_close_impl(fd);
        return 0;
    }
    package->vendor_id = codec_header.vendor_id;
    package->product_id = codec_header.product_id;
    package->device_number = codec_header.device_number;
    package->profile_format = codec_header.profile_format;
    package->sector_count = codec_header.sector_count;
    for (size_t i = 0; i < package->sector_count; i++) {
        package->sectors[i].sector = codec_sectors[i].sector;
        package->sectors[i].size = codec_sectors[i].size;
        package->sectors[i].data = (uint8_t *)malloc(package->sectors[i].size);
        if (package->sectors[i].data == NULL ||
            !read_all(fd, package->sectors[i].data, package->sectors[i].size)) {
            fprintf(stderr, "could not read sector %zu from backup %s\n", i + 1, path);
            backup_close_impl(fd);
            package_release(package);
            return 0;
        }
        BackupCodecSector sector = {
            .sector = package->sectors[i].sector,
            .size = package->sectors[i].size,
            .data = package->sectors[i].data,
        };
        if (!backup_codec_sector_crc_ok(&codec_header, &sector)) {
            fprintf(stderr, "backup %s has an invalid CRC in sector %zu\n", path, i + 1);
            backup_close_impl(fd);
            package_release(package);
            return 0;
        }
    }
    backup_close_impl(fd);
    return 1;
}

void package_release(BackupPackage *package) {
    if (package != NULL) {
        for (size_t i = 0; i < package->sector_count && i < MAX_BACKUP_SECTORS; i++) {
            free(package->sectors[i].data);
        }
        memset(package, 0, sizeof(*package));
    }
}

void default_backup_path(char *path, size_t path_size, const char *prefix) {
    time_t now = time(NULL);
    struct tm local_time;
    localtime_r(&now, &local_time);
    char stamp[64];
    strftime(stamp, sizeof(stamp), "%Y%m%d-%H%M%S", &local_time);
    snprintf(path, path_size, "%s-%s-%ld.bin", prefix, stamp, (long)getpid());
}

int ensure_write_confirmation(const char *operation) {
    fprintf(stderr,
            "%s is preview-only by default. Add --yes after reviewing the output to permit the "
            "mouse write.\n",
            operation);
    return 0;
}

int validate_profile_for_write(const Profile *profile) {
    if (!profile->crc_ok) {
        fprintf(stderr, "refusing to write: the current profile sector CRC is invalid\n");
        return 0;
    }
    if (!profile->layout_supported) {
        fprintf(stderr,
                "refusing to write: the reported profile format/layout was not validated\n");
        return 0;
    }
    if (!profile_codec_validate_profile_for_write(
            true, true, profile->data_length, profile->button_offset, profile->info.button_count,
            profile->valid_specs)) {
        if (profile->data_length < 2 || profile->button_offset > profile->data_length - 2 ||
            profile->info.button_count > (profile->data_length - 2 - profile->button_offset) / 4) {
            fprintf(stderr, "refusing to write: validated button array would exceed the sector\n");
        } else {
            fprintf(stderr, "refusing to write: too many unrecognized button records\n");
        }
        return 0;
    }
    return 1;
}
