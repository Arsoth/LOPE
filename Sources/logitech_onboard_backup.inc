static int write_all(int fd, const uint8_t *bytes, size_t length) {
    size_t written = 0;
    while (written < length) {
        ssize_t n = write(fd, bytes + written, length - written);
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
        ssize_t n = read(fd, bytes + read_bytes, length - read_bytes);
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

static void put_be16(uint8_t *bytes, uint16_t value) {
    bytes[0] = (uint8_t)(value >> 8);
    bytes[1] = (uint8_t)(value & 0xFF);
}

static uint16_t get_be16(const uint8_t *bytes) {
    return (uint16_t)(((uint16_t)bytes[0] << 8) | bytes[1]);
}

static int package_write_multi(const char *path,
                               const Device *device,
                               uint8_t profile_format,
                               const BackupSectorSource *sectors,
                               size_t sector_count,
                               bool refuse_overwrite);

static int package_write(const char *path,
                         const Device *device,
                         const Profile *profile,
                         const uint8_t *data,
                         bool refuse_overwrite) {
    BackupSectorSource sector = {
        .sector = profile->headers[profile->selected_header].sector,
        .size = profile->data_length,
        .data = data
    };
    return package_write_multi(path, device, profile->info.profile_format,
                               &sector, 1, refuse_overwrite);
}

static int package_write_multi(const char *path,
                               const Device *device,
                               uint8_t profile_format,
                               const BackupSectorSource *sectors,
                               size_t sector_count,
                               bool refuse_overwrite) {
    if (sector_count == 0 || sector_count > MAX_BACKUP_SECTORS) {
        fprintf(stderr, "cannot create a backup package with %zu sectors\n", sector_count);
        return 0;
    }
    uint8_t header[BACKUP_HEADER_BYTES];
    memset(header, 0, sizeof(header));
    memcpy(header, BACKUP_MAGIC, 8);
    header[8] = 2;
    put_be16(header + 10, (uint16_t)device->iface->vendor_id);
    put_be16(header + 12, (uint16_t)device->iface->product_id);
    header[14] = device->request_device_number;
    header[15] = profile_format;
    put_be16(header + 16, (uint16_t)sector_count);

    uint8_t table[MAX_BACKUP_SECTORS * 4];
    memset(table, 0, sizeof(table));
    size_t table_length = sector_count * 4;
    for (size_t i = 0; i < sector_count; i++) {
        if (sectors[i].data == NULL || sectors[i].size < 32 ||
            sectors[i].size > MAX_SECTOR_BYTES) {
            fprintf(stderr, "cannot create a backup package with invalid sector %zu metadata\n", i + 1);
            return 0;
        }
        put_be16(table + i * 4, sectors[i].sector);
        put_be16(table + i * 4 + 2, (uint16_t)sectors[i].size);
    }

    int flags = O_WRONLY | O_CREAT | (refuse_overwrite ? O_EXCL : O_TRUNC);
    int fd = open(path, flags, 0600);
    if (fd < 0) {
        fprintf(stderr, "could not create %s: %s\n", path, strerror(errno));
        return 0;
    }
    int ok = write_all(fd, header, sizeof(header)) && write_all(fd, table, table_length);
    for (size_t i = 0; ok && i < sector_count; i++) {
        ok = write_all(fd, sectors[i].data, sectors[i].size);
    }
    if (close(fd) != 0) {
        ok = 0;
    }
    if (!ok) {
        fprintf(stderr, "could not finish writing %s: %s\n", path, strerror(errno));
        return 0;
    }
    return 1;
}

static void package_release(BackupPackage *package);

static int package_read(const char *path, BackupPackage *package) {
    memset(package, 0, sizeof(*package));
    int fd = open(path, O_RDONLY);
    if (fd < 0) {
        fprintf(stderr, "could not open backup %s: %s\n", path, strerror(errno));
        return 0;
    }
    uint8_t header[BACKUP_HEADER_BYTES];
    if (!read_all(fd, header, sizeof(header))) {
        fprintf(stderr, "backup %s is shorter than its header\n", path);
        close(fd);
        return 0;
    }
    if (memcmp(header, BACKUP_MAGIC, 8) != 0 || header[8] != 2) {
        fprintf(stderr, "backup %s is not a recognized Logitech onboard package\n", path);
        close(fd);
        return 0;
    }
    package->vendor_id = get_be16(header + 10);
    package->product_id = get_be16(header + 12);
    package->device_number = header[14];
    package->profile_format = header[15];
    if (package->vendor_id != LOGITECH_VID) {
        fprintf(stderr, "backup %s has invalid device or sector metadata\n", path);
        close(fd);
        return 0;
    }
    struct stat st;
    size_t sector_count = get_be16(header + 16);
    if (sector_count == 0 || sector_count > MAX_BACKUP_SECTORS) {
        fprintf(stderr, "backup %s has an invalid sector count\n", path);
        close(fd);
        return 0;
    }
    uint8_t table[MAX_BACKUP_SECTORS * 4];
    size_t table_length = sector_count * 4;
    if (!read_all(fd, table, table_length)) {
        fprintf(stderr, "backup %s is shorter than its sector table\n", path);
        close(fd);
        return 0;
    }
    off_t expected_length = BACKUP_HEADER_BYTES + (off_t)table_length;
    for (size_t i = 0; i < sector_count; i++) {
        package->sectors[i].sector = get_be16(table + i * 4);
        package->sectors[i].size = get_be16(table + i * 4 + 2);
        if (package->sectors[i].size < 32 || package->sectors[i].size > MAX_SECTOR_BYTES) {
            fprintf(stderr, "backup %s has invalid sector %zu metadata\n", path, i + 1);
            close(fd);
            package_release(package);
            return 0;
        }
        for (size_t previous = 0; previous < i; previous++) {
            if (package->sectors[previous].sector == package->sectors[i].sector) {
                fprintf(stderr, "backup %s contains duplicate sector 0x%04X\n", path, package->sectors[i].sector);
                close(fd);
                package_release(package);
                return 0;
            }
        }
        expected_length += package->sectors[i].size;
    }
    if (fstat(fd, &st) != 0 || st.st_size != expected_length) {
        fprintf(stderr, "backup %s has an unexpected file length\n", path);
        close(fd);
        package_release(package);
        return 0;
    }
    package->sector_count = sector_count;
    for (size_t i = 0; i < sector_count; i++) {
        package->sectors[i].data = (uint8_t *)malloc(package->sectors[i].size);
        if (package->sectors[i].data == NULL ||
            !read_all(fd, package->sectors[i].data, package->sectors[i].size)) {
            fprintf(stderr, "could not read sector %zu from backup %s\n", i + 1, path);
            close(fd);
            package_release(package);
            return 0;
        }
        if (!sector_crc_ok(package->sectors[i].data, package->sectors[i].size)) {
            fprintf(stderr, "backup %s has an invalid CRC in sector %zu\n", path, i + 1);
            close(fd);
            package_release(package);
            return 0;
        }
    }
    close(fd);
    return 1;
}

static void package_release(BackupPackage *package) {
    if (package != NULL) {
        for (size_t i = 0; i < package->sector_count && i < MAX_BACKUP_SECTORS; i++) {
            free(package->sectors[i].data);
        }
        memset(package, 0, sizeof(*package));
    }
}

static void default_backup_path(char *path, size_t path_size, const char *prefix) {
    time_t now = time(NULL);
    struct tm local_time;
    localtime_r(&now, &local_time);
    char stamp[64];
    strftime(stamp, sizeof(stamp), "%Y%m%d-%H%M%S", &local_time);
    snprintf(path, path_size, "%s-%s-%ld.bin", prefix, stamp, (long)getpid());
}

static int ensure_write_confirmation(const char *operation) {
    fprintf(stderr, "%s is preview-only by default. Add --yes after reviewing the output to permit the mouse write.\n",
            operation);
    return 0;
}

static int validate_profile_for_write(const Profile *profile) {
    if (!profile->crc_ok) {
        fprintf(stderr, "refusing to write: the current profile sector CRC is invalid\n");
        return 0;
    }
    if (!profile->layout_supported) {
        fprintf(stderr, "refusing to write: the reported profile format/layout was not validated\n");
        return 0;
    }
    if (profile->button_offset + (size_t)profile->info.button_count * 4 > profile->data_length - 2) {
        fprintf(stderr, "refusing to write: validated button array would exceed the sector\n");
        return 0;
    }
    if (profile->valid_specs < profile->info.button_count - 1) {
        fprintf(stderr, "refusing to write: too many unrecognized button records\n");
        return 0;
    }
    return 1;
}
