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

static int package_write(const char *path,
                         const Device *device,
                         const Profile *profile,
                         const uint8_t *data,
                         bool refuse_overwrite) {
    uint8_t header[BACKUP_HEADER_BYTES];
    memset(header, 0, sizeof(header));
    memcpy(header, BACKUP_MAGIC, 8);
    header[8] = 1;
    put_be16(header + 10, (uint16_t)device->iface->vendor_id);
    put_be16(header + 12, (uint16_t)device->iface->product_id);
    header[14] = device->request_device_number;
    header[15] = profile->info.profile_format;
    put_be16(header + 16, profile->headers[profile->selected_header].sector);
    put_be16(header + 18, (uint16_t)profile->data_length);

    int flags = O_WRONLY | O_CREAT | (refuse_overwrite ? O_EXCL : O_TRUNC);
    int fd = open(path, flags, 0600);
    if (fd < 0) {
        fprintf(stderr, "could not create %s: %s\n", path, strerror(errno));
        return 0;
    }
    int ok = write_all(fd, header, sizeof(header)) && write_all(fd, data, profile->data_length);
    if (close(fd) != 0) {
        ok = 0;
    }
    if (!ok) {
        fprintf(stderr, "could not finish writing %s: %s\n", path, strerror(errno));
        return 0;
    }
    return 1;
}

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
    if (memcmp(header, BACKUP_MAGIC, 8) != 0 || header[8] != 1) {
        fprintf(stderr, "backup %s is not a recognized Logitech onboard package\n", path);
        close(fd);
        return 0;
    }
    package->vendor_id = get_be16(header + 10);
    package->product_id = get_be16(header + 12);
    package->device_number = header[14];
    package->profile_format = header[15];
    package->sector = get_be16(header + 16);
    package->size = get_be16(header + 18);
    if (package->vendor_id != LOGITECH_VID || package->size < 32 || package->size > MAX_SECTOR_BYTES) {
        fprintf(stderr, "backup %s has invalid device or sector metadata\n", path);
        close(fd);
        return 0;
    }
    struct stat st;
    if (fstat(fd, &st) != 0 || st.st_size != (off_t)BACKUP_HEADER_BYTES + package->size) {
        fprintf(stderr, "backup %s has an unexpected file length\n", path);
        close(fd);
        return 0;
    }
    package->data = (uint8_t *)malloc(package->size);
    if (package->data == NULL || !read_all(fd, package->data, package->size)) {
        fprintf(stderr, "could not read backup data from %s\n", path);
        free(package->data);
        package->data = NULL;
        close(fd);
        return 0;
    }
    close(fd);
    if (!sector_crc_ok(package->data, package->size)) {
        fprintf(stderr, "backup %s has an invalid sector CRC\n", path);
        free(package->data);
        package->data = NULL;
        return 0;
    }
    return 1;
}

static void package_release(BackupPackage *package) {
    if (package != NULL) {
        free(package->data);
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

