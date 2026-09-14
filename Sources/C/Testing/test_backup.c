#include "backup.h"
#include "g600.h"
#include "hid_types.h"
#include "profile_io.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static bool g_backup_read_eintr;
static bool g_backup_read_partial;
static int g_backup_read_fail_after;
static bool g_backup_write_eintr;
static bool g_backup_write_partial;
static int g_backup_write_fail_after;
static bool g_backup_close_fail;
static int g_backup_fstat_mode;

static ssize_t backup_read_double(int fd, void *bytes, size_t length) {
    if (g_backup_read_eintr) {
        g_backup_read_eintr = false;
        errno = EINTR;
        return -1;
    }
    if (g_backup_read_fail_after == 0) {
        g_backup_read_fail_after = -1;
        errno = EIO;
        return -1;
    }
    if (g_backup_read_fail_after > 0) {
        g_backup_read_fail_after--;
    }
    if (g_backup_read_partial && length > 1) {
        g_backup_read_partial = false;
        return read(fd, bytes, length / 2);
    }
    return read(fd, bytes, length);
}

static ssize_t backup_write_double(int fd, const void *bytes, size_t length) {
    if (g_backup_write_eintr) {
        g_backup_write_eintr = false;
        errno = EINTR;
        return -1;
    }
    if (g_backup_write_fail_after == 0) {
        g_backup_write_fail_after = -1;
        errno = EIO;
        return -1;
    }
    if (g_backup_write_fail_after > 0) {
        g_backup_write_fail_after--;
    }
    if (g_backup_write_partial && length > 1) {
        g_backup_write_partial = false;
        return write(fd, bytes, length / 2);
    }
    return write(fd, bytes, length);
}

static int backup_close_double(int fd) {
    int result = close(fd);
    if (g_backup_close_fail) {
        g_backup_close_fail = false;
        errno = EIO;
        return -1;
    }
    return result;
}

static int backup_fstat_double(int fd, struct stat *status) {
    if (g_backup_fstat_mode == 1) {
        g_backup_fstat_mode = 0;
        errno = EIO;
        return -1;
    }
    int result = fstat(fd, status);
    if (result == 0 && g_backup_fstat_mode == 2) {
        status->st_size++;
        g_backup_fstat_mode = 0;
    }
    return result;
}

static void reset_backup_seams(void) {
    backup_read_impl = (BackupReadFn)read;
    backup_write_impl = (BackupWriteFn)write;
    backup_close_impl = close;
    backup_fstat_impl = fstat;
    g_backup_read_eintr = false;
    g_backup_read_partial = false;
    g_backup_read_fail_after = -1;
    g_backup_write_eintr = false;
    g_backup_write_partial = false;
    g_backup_write_fail_after = -1;
    g_backup_close_fail = false;
    g_backup_fstat_mode = 0;
}

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
                     package.product_id == dummy_interface.product_id &&
                     memcmp(package.sectors[0].data, profile.data, 255) == 0;
        package_release(&package);
    }
    unlink(temp_path);

    HidInterface receiver_interface = dummy_interface;
    receiver_interface.product_id = 0xC539;
    Device receiver_device = dummy_device;
    receiver_device.iface = &receiver_interface;
    receiver_device.mouse_product_id = 0x4085;
    receiver_device.request_device_number = 1;
    char receiver_path[] = "/tmp/lomps-selftest-receiver-XXXXXX";
    int receiver_fd = mkstemp(receiver_path);
    bool receiver_identity_ok = receiver_fd >= 0;
    if (receiver_fd >= 0) {
        close(receiver_fd);
        unlink(receiver_path);
    }
    receiver_identity_ok = receiver_identity_ok && package_write(receiver_path, &receiver_device,
                                                                 &profile, profile.data, true);
    if (receiver_identity_ok) {
        receiver_identity_ok = package_read(receiver_path, &package);
    }
    if (receiver_identity_ok) {
        receiver_identity_ok = package.product_id == 0x4085 && package.device_number == 1;
        package_release(&package);
    }
    unlink(receiver_path);

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

    char seam_path[] = "/tmp/lomps-selftest-seams-XXXXXX";
    int seam_fd = mkstemp(seam_path);
    bool seam_ok = seam_fd >= 0;
    if (seam_fd >= 0) {
        close(seam_fd);
        unlink(seam_path);
    }
    backup_read_impl = backup_read_double;
    backup_write_impl = backup_write_double;
    backup_close_impl = backup_close_double;
    backup_fstat_impl = backup_fstat_double;
    g_backup_read_fail_after = -1;
    g_backup_write_eintr = true;
    g_backup_write_partial = true;
    g_backup_write_fail_after = -1;
    seam_ok =
        seam_ok && package_write_multi(seam_path, &dummy_device, 5, combined_sources, 2, true);
    if (seam_ok) {
        seam_ok = package_read(seam_path, &package) && package.sector_count == 2;
        if (package.sector_count > 0) {
            package_release(&package);
        }
    }
    unlink(seam_path);

    g_backup_write_eintr = false;
    g_backup_write_partial = false;
    g_backup_write_fail_after = 0;
    seam_ok =
        seam_ok && !package_write_multi(seam_path, &dummy_device, 5, combined_sources, 2, true);
    unlink(seam_path);
    g_backup_write_fail_after = -1;
    g_backup_close_fail = true;
    seam_ok =
        seam_ok && !package_write_multi(seam_path, &dummy_device, 5, combined_sources, 2, true);
    unlink(seam_path);
    seam_ok = seam_ok && !package_write_multi("/tmp", &dummy_device, 5, combined_sources, 2, true);
    reset_backup_seams();

    char read_seam_path[] = "/tmp/lomps-selftest-read-seams-XXXXXX";
    int read_seam_fd = mkstemp(read_seam_path);
    bool read_seam_ok = read_seam_fd >= 0;
    if (read_seam_fd >= 0) {
        close(read_seam_fd);
        unlink(read_seam_path);
    }
    read_seam_ok = read_seam_ok &&
                   package_write_multi(read_seam_path, &dummy_device, 5, combined_sources, 2, true);
    backup_read_impl = backup_read_double;
    backup_fstat_impl = backup_fstat_double;
    g_backup_read_eintr = true;
    g_backup_read_partial = true;
    g_backup_read_fail_after = -1;
    if (read_seam_ok) {
        read_seam_ok = package_read(read_seam_path, &package) && package.sector_count == 2;
        if (package.sector_count > 0) {
            package_release(&package);
        }
    }
    g_backup_read_eintr = false;
    g_backup_read_partial = false;
    g_backup_read_fail_after = 2;
    read_seam_ok = read_seam_ok && !package_read(read_seam_path, &package);
    g_backup_read_fail_after = -1;
    g_backup_fstat_mode = 1;
    read_seam_ok = read_seam_ok && !package_read(read_seam_path, &package);
    g_backup_fstat_mode = 2;
    read_seam_ok = read_seam_ok && !package_read(read_seam_path, &package);
    unlink(read_seam_path);
    reset_backup_seams();

    uint8_t legacy_package[BACKUP_HEADER_BYTES + 4 + 32] = {0};
    make_backup_header(legacy_package, LOGITECH_VID, 1);
    legacy_package[12] = (uint8_t)(G600_PRODUCT_ID >> 8);
    legacy_package[13] = (uint8_t)G600_PRODUCT_ID;
    legacy_package[15] = 0xFF;
    legacy_package[BACKUP_HEADER_BYTES + 2] = 0;
    legacy_package[BACKUP_HEADER_BYTES + 3] = 32;
    char legacy_path[] = "/tmp/lomps-selftest-legacy-XXXXXX";
    int legacy_fd = mkstemp(legacy_path);
    bool legacy_ok = legacy_fd >= 0;
    if (legacy_fd >= 0) {
        close(legacy_fd);
    }
    if (legacy_ok) {
        legacy_ok = write_test_file(legacy_path, legacy_package, sizeof(legacy_package)) &&
                    package_read(legacy_path, &package) && package.sector_count == 1;
        if (package.sector_count > 0) {
            package_release(&package);
        }
    }
    unlink(legacy_path);

    BackupPackage boundary_package;
    memset(&boundary_package, 0, sizeof(boundary_package));
    boundary_package.sector_count = MAX_BACKUP_SECTORS + 1;
    package_release(&boundary_package);
    if (!package_ok || !receiver_identity_ok || !combined_package_ok) {
        free(profile.data);
        fprintf(stderr, "backup package self-test failed\n");
        return 1;
    }
    if (!seam_ok || !read_seam_ok || !legacy_ok) {
        free(profile.data);
        fprintf(stderr, "backup I/O seam self-test failed\n");
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
