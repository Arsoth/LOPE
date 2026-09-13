#include "internal.h"

static bool write_test_file(const char *path, const uint8_t *bytes, size_t length) {
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd < 0) {
        return false;
    }
    ssize_t written = write(fd, bytes, length);
    int close_result = close(fd);
    return written == (ssize_t)length && close_result == 0;
}

static bool package_rejects_bytes(const char *path, const uint8_t *bytes, size_t length) {
    BackupPackage package;
    bool ok = write_test_file(path, bytes, length) && !package_read(path, &package);
    unlink(path);
    return ok;
}

static void make_backup_header(uint8_t header[BACKUP_HEADER_BYTES], uint16_t vendor_id,
                               uint16_t sector_count) {
    memset(header, 0, BACKUP_HEADER_BYTES);
    memcpy(header, BACKUP_MAGIC, 8);
    header[8] = 2;
    header[10] = (uint8_t)(vendor_id >> 8);
    header[11] = (uint8_t)vendor_id;
    header[16] = (uint8_t)(sector_count >> 8);
    header[17] = (uint8_t)sector_count;
}

int test_backup(void) {
    HidInterface dummy_interface;
    memset(&dummy_interface, 0, sizeof(dummy_interface));
    dummy_interface.vendor_id = LOGITECH_VID;
    dummy_interface.product_id = 0xC08B;
    Device dummy_device;
    memset(&dummy_device, 0, sizeof(dummy_device));
    dummy_device.iface = &dummy_interface;
    dummy_device.device_number = 0xFF;
    dummy_device.request_device_number = 0xFF;

    Profile profile;
    memset(&profile, 0, sizeof(profile));
    profile.headers[0].sector = 0x0123;
    profile.selected_header = 0;
    profile.info.profile_format = 5;
    profile.data_length = 255;
    profile.data = (uint8_t *)calloc(profile.data_length, 1);
    if (profile.data == NULL) {
        return 1;
    }
    sector_put_crc(profile.data, profile.data_length);
    char temp_path[] = "/tmp/lomps-selftest-XXXXXX";
    int temp_fd = mkstemp(temp_path);
    if (temp_fd < 0) {
        free(profile.data);
        return 1;
    }
    close(temp_fd);
    unlink(temp_path);
    bool package_ok = package_write(temp_path, &dummy_device, &profile, profile.data, true);
    BackupPackage package;
    if (package_ok) {
        package_ok = package_read(temp_path, &package);
    }
    if (package_ok) {
        package_ok = package.sector_count == 1 && package.sectors[0].sector == 0x0123 &&
                     package.sectors[0].size == 255 &&
                     memcmp(package.sectors[0].data, profile.data, 255) == 0;
        package_release(&package);
    }
    unlink(temp_path);

    uint8_t control_data[255] = {0};
    control_data[2] = 1;
    sector_put_crc(control_data, sizeof(control_data));
    BackupSectorSource combined_sources[2] = {
        {.sector = 0x0123, .size = 255, .data = profile.data},
        {.sector = 0x0000, .size = 255, .data = control_data}};
    char combined_path[] = "/tmp/lomps-selftest-combined-XXXXXX";
    int combined_fd = mkstemp(combined_path);
    if (combined_fd < 0) {
        free(profile.data);
        return 1;
    }
    close(combined_fd);
    unlink(combined_path);
    bool combined_package_ok =
        package_write_multi(combined_path, &dummy_device, 5, combined_sources, 2, true);
    if (combined_package_ok) {
        combined_package_ok = package_read(combined_path, &package);
    }
    if (combined_package_ok) {
        combined_package_ok = package.sector_count == 2 && package.sectors[0].sector == 0x0123 &&
                              package.sectors[1].sector == 0x0000 &&
                              memcmp(package.sectors[0].data, profile.data, 255) == 0 &&
                              memcmp(package.sectors[1].data, control_data, 255) == 0;
        package_release(&package);
    }
    unlink(combined_path);
    if (!package_ok || !combined_package_ok) {
        free(profile.data);
        fprintf(stderr, "backup package self-test failed\n");
        return 1;
    }

    char malformed_path[] = "/tmp/lomps-selftest-malformed-XXXXXX";
    int malformed_fd = mkstemp(malformed_path);
    if (malformed_fd < 0) {
        free(profile.data);
        return 1;
    }
    close(malformed_fd);
    uint8_t malformed_header[BACKUP_HEADER_BYTES];
    make_backup_header(malformed_header, LOGITECH_VID, 1);
    bool malformed_ok = package_rejects_bytes(malformed_path, malformed_header, 1);
    malformed_header[0] ^= 0xFF;
    malformed_ok = malformed_ok && package_rejects_bytes(malformed_path, malformed_header,
                                                         sizeof(malformed_header));
    make_backup_header(malformed_header, LOGITECH_VID, 1);
    malformed_header[8] = 1;
    malformed_ok = malformed_ok && package_rejects_bytes(malformed_path, malformed_header,
                                                         sizeof(malformed_header));
    make_backup_header(malformed_header, 0x1234, 1);
    malformed_ok = malformed_ok && package_rejects_bytes(malformed_path, malformed_header,
                                                         sizeof(malformed_header));
    make_backup_header(malformed_header, LOGITECH_VID, 0);
    malformed_ok = malformed_ok && package_rejects_bytes(malformed_path, malformed_header,
                                                         sizeof(malformed_header));
    make_backup_header(malformed_header, LOGITECH_VID, MAX_BACKUP_SECTORS + 1);
    malformed_ok = malformed_ok && package_rejects_bytes(malformed_path, malformed_header,
                                                         sizeof(malformed_header));

    make_backup_header(malformed_header, LOGITECH_VID, 1);
    uint8_t malformed_table[BACKUP_HEADER_BYTES + 4] = {0};
    memcpy(malformed_table, malformed_header, sizeof(malformed_header));
    malformed_ok = malformed_ok &&
                   package_rejects_bytes(malformed_path, malformed_table, sizeof(malformed_header));
    malformed_table[BACKUP_HEADER_BYTES + 2] = 31;
    malformed_ok = malformed_ok &&
                   package_rejects_bytes(malformed_path, malformed_table, sizeof(malformed_table));
    malformed_table[BACKUP_HEADER_BYTES + 2] = 0x10;
    malformed_table[BACKUP_HEADER_BYTES + 3] = 0x01;
    malformed_ok = malformed_ok &&
                   package_rejects_bytes(malformed_path, malformed_table, sizeof(malformed_table));

    uint8_t duplicate_package[BACKUP_HEADER_BYTES + 8 + 64] = {0};
    make_backup_header((uint8_t *)duplicate_package, LOGITECH_VID, 2);
    duplicate_package[BACKUP_HEADER_BYTES + 2] = 0;
    duplicate_package[BACKUP_HEADER_BYTES + 3] = 32;
    duplicate_package[BACKUP_HEADER_BYTES + 4] = 0;
    duplicate_package[BACKUP_HEADER_BYTES + 5] = 0x01;
    duplicate_package[BACKUP_HEADER_BYTES + 6] = 0;
    duplicate_package[BACKUP_HEADER_BYTES + 7] = 32;
    malformed_ok = malformed_ok && package_rejects_bytes(malformed_path, duplicate_package,
                                                         sizeof(duplicate_package));

    uint8_t invalid_crc_package[BACKUP_HEADER_BYTES + 4 + 32] = {0};
    make_backup_header((uint8_t *)invalid_crc_package, LOGITECH_VID, 1);
    invalid_crc_package[BACKUP_HEADER_BYTES + 2] = 0;
    invalid_crc_package[BACKUP_HEADER_BYTES + 3] = 32;
    invalid_crc_package[BACKUP_HEADER_BYTES + 4 + 31] = 0xFF;
    malformed_ok = malformed_ok && package_rejects_bytes(malformed_path, invalid_crc_package,
                                                         sizeof(invalid_crc_package));

    BackupSectorSource invalid_source = {.sector = 1, .size = 31, .data = profile.data};
    BackupSectorSource null_source = {.sector = 1, .size = 32, .data = NULL};
    BackupSectorSource oversized_source = {
        .sector = 1, .size = MAX_SECTOR_BYTES + 1, .data = profile.data};
    malformed_ok =
        malformed_ok && !package_write_multi(malformed_path, &dummy_device, 5, NULL, 0, true) &&
        !package_write_multi(malformed_path, &dummy_device, 5, &invalid_source, 1, true) &&
        !package_write_multi(malformed_path, &dummy_device, 5, &null_source, 1, true) &&
        !package_write_multi(malformed_path, &dummy_device, 5, &oversized_source, 1, true);
    package_release(NULL);
    unlink(malformed_path);

    Profile invalid_profile = profile;
    invalid_profile.crc_ok = false;
    bool validation_ok = !validate_profile_for_write(&invalid_profile);
    invalid_profile.crc_ok = true;
    invalid_profile.layout_supported = false;
    validation_ok = validation_ok && !validate_profile_for_write(&invalid_profile);
    invalid_profile.layout_supported = true;
    invalid_profile.data_length = 32;
    invalid_profile.info.button_count = 8;
    invalid_profile.button_offset = 16;
    validation_ok = validation_ok && !validate_profile_for_write(&invalid_profile);
    invalid_profile.data_length = 255;
    invalid_profile.info.button_count = 5;
    invalid_profile.button_offset = 32;
    invalid_profile.valid_specs = 0;
    validation_ok = validation_ok && !validate_profile_for_write(&invalid_profile);
    invalid_profile.valid_specs = 4;
    validation_ok = validation_ok && validate_profile_for_write(&invalid_profile);
    if (!malformed_ok || !validation_ok) {
        free(profile.data);
        fprintf(stderr, "backup validation self-test failed\n");
        return 1;
    }
    free(profile.data);
    return 0;
}
