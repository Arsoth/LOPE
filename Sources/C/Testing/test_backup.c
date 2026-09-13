#include "internal.h"

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
    free(profile.data);
    if (!package_ok || !combined_package_ok) {
        fprintf(stderr, "backup package self-test failed\n");
        return 1;
    }
    return 0;
}
