#include "backup_codec.h"

#include "profile_codec.h"

#include <stdio.h>
#include <string.h>

static void make_codec_sector(uint8_t *data, size_t length, uint8_t seed) {
    for (size_t i = 0; i + 2 < length; i++) {
        data[i] = (uint8_t)(seed + i);
    }
    profile_codec_sector_put_crc(data, length);
}

int test_backup_codec(void) {
    uint8_t first_data[32];
    uint8_t second_data[64];
    make_codec_sector(first_data, sizeof(first_data), 1);
    make_codec_sector(second_data, sizeof(second_data), 0x40);
    BackupCodecHeader header = {
        .vendor_id = 0x046D,
        .product_id = 0xC08B,
        .device_number = 0xFF,
        .profile_format = 5,
        .sector_count = 2,
    };
    BackupCodecSector sources[2] = {
        {.sector = 0x0123, .size = sizeof(first_data), .data = first_data},
        {.sector = 0x0000, .size = sizeof(second_data), .data = second_data},
    };
    uint8_t encoded[BACKUP_CODEC_HEADER_BYTES + 8 + sizeof(first_data) + sizeof(second_data)] = {0};
    size_t encoded_length = 0;
    bool encode_ok =
        backup_codec_encode(&header, sources, 2, encoded, sizeof(encoded), &encoded_length) &&
        encoded_length == sizeof(encoded) && memcmp(encoded, BACKUP_CODEC_MAGIC, 8) == 0;
    BackupCodecPackage package;
    bool decode_ok = backup_codec_decode(encoded, encoded_length, &package) &&
                     package.header.vendor_id == header.vendor_id &&
                     package.header.product_id == header.product_id &&
                     package.header.device_number == header.device_number &&
                     package.header.profile_format == header.profile_format &&
                     package.header.sector_count == 2 && package.sectors[0].sector == 0x0123 &&
                     package.sectors[0].size == sizeof(first_data) &&
                     memcmp(package.sectors[0].data, first_data, sizeof(first_data)) == 0 &&
                     package.sectors[1].sector == 0 &&
                     package.sectors[1].size == sizeof(second_data) &&
                     memcmp(package.sectors[1].data, second_data, sizeof(second_data)) == 0;
    if (!encode_ok || !decode_ok) {
        fprintf(stderr, "backup codec round-trip self-test failed\n");
        return 1;
    }

    BackupCodecHeader parsed_header;
    BackupCodecSector parsed_sectors[2];
    size_t expected_length = 0;
    bool parse_ok = backup_codec_parse_header(encoded, &parsed_header) &&
                    backup_codec_parse_sector_table(encoded + BACKUP_CODEC_HEADER_BYTES, 8, 2,
                                                    parsed_sectors, &expected_length) &&
                    expected_length == encoded_length && parsed_sectors[0].sector == 0x0123 &&
                    parsed_sectors[1].size == sizeof(second_data) &&
                    !backup_codec_parse_sector_table(encoded + BACKUP_CODEC_HEADER_BYTES, 7, 2,
                                                     parsed_sectors, &expected_length) &&
                    !backup_codec_parse_header(NULL, &parsed_header) &&
                    !backup_codec_parse_header(encoded, NULL);
    parse_ok = parse_ok && !backup_codec_decode(NULL, encoded_length, &package) &&
               !backup_codec_decode(encoded, encoded_length, NULL);
    if (!parse_ok) {
        fprintf(stderr, "backup codec header/table parsing self-test failed\n");
        return 1;
    }

    bool sector_ok = backup_codec_sector_crc_ok(&header, &sources[0]);
    BackupCodecSector bad_sector = sources[0];
    bad_sector.data = NULL;
    sector_ok = sector_ok && !backup_codec_sector_crc_ok(&header, &bad_sector) &&
                !backup_codec_sector_crc_ok(NULL, &sources[0]) &&
                !backup_codec_sector_crc_ok(&header, NULL);
    bad_sector.data = first_data;
    bad_sector.size = 31;
    sector_ok = sector_ok && !backup_codec_sector_crc_ok(&header, &bad_sector);
    bad_sector.size = BACKUP_CODEC_MAX_SECTOR_BYTES + 1;
    sector_ok = sector_ok && !backup_codec_sector_crc_ok(&header, &bad_sector);
    uint8_t bad_package[sizeof(encoded)];
    memcpy(bad_package, encoded, sizeof(bad_package));
    bad_package[sizeof(bad_package) - 1] ^= 1;
    sector_ok = sector_ok && !backup_codec_decode(bad_package, sizeof(bad_package), &package);
    if (!sector_ok) {
        fprintf(stderr, "backup codec CRC validation self-test failed\n");
        return 1;
    }

    uint8_t malformed[sizeof(encoded)];
    memcpy(malformed, encoded, sizeof(malformed));
    malformed[0] ^= 1;
    bool malformed_ok = !backup_codec_decode(malformed, sizeof(malformed), &package);
    malformed_ok = malformed_ok &&
                   !backup_codec_decode(encoded, BACKUP_CODEC_HEADER_BYTES - 1, &package) &&
                   !backup_codec_decode(encoded, BACKUP_CODEC_HEADER_BYTES, &package) &&
                   !backup_codec_decode(encoded, encoded_length - 1, &package);
    memcpy(malformed, encoded, sizeof(malformed));
    malformed[8] = 1;
    malformed_ok = malformed_ok && !backup_codec_decode(malformed, sizeof(malformed), &package);
    memcpy(malformed, encoded, sizeof(malformed));
    malformed[10] = 0x12;
    malformed[11] = 0x34;
    malformed_ok = malformed_ok && !backup_codec_decode(malformed, sizeof(malformed), &package);
    memcpy(malformed, encoded, sizeof(malformed));
    malformed[16] = 0;
    malformed[17] = 0;
    malformed_ok = malformed_ok && !backup_codec_decode(malformed, sizeof(malformed), &package);
    memcpy(malformed, encoded, sizeof(malformed));
    malformed[24] = 0x01;
    malformed[25] = 0x23;
    malformed_ok = malformed_ok && !backup_codec_decode(malformed, sizeof(malformed), &package);
    if (!malformed_ok) {
        fprintf(stderr, "backup codec malformed-package self-test failed\n");
        return 1;
    }

    uint8_t small_table[4] = {0, 1, 0, 31};
    uint8_t duplicate_table[8] = {0, 1, 0, 32, 0, 1, 0, 32};
    bool table_edges = !backup_codec_parse_sector_table(NULL, sizeof(small_table), 1,
                                                        parsed_sectors, &expected_length) &&
                       !backup_codec_parse_sector_table(small_table, sizeof(small_table), 1, NULL,
                                                        &expected_length) &&
                       !backup_codec_parse_sector_table(small_table, sizeof(small_table), 1,
                                                        parsed_sectors, NULL) &&
                       !backup_codec_parse_sector_table(small_table, sizeof(small_table), 0,
                                                        parsed_sectors, &expected_length) &&
                       !backup_codec_parse_sector_table(small_table, sizeof(small_table), 1,
                                                        parsed_sectors, &expected_length) &&
                       !backup_codec_parse_sector_table(duplicate_table, sizeof(duplicate_table), 2,
                                                        parsed_sectors, &expected_length) &&
                       !backup_codec_parse_sector_table(small_table, sizeof(small_table), 33,
                                                        parsed_sectors, &expected_length);
    if (!table_edges) {
        fprintf(stderr, "backup codec table-boundary self-test failed\n");
        return 1;
    }

    uint8_t output[sizeof(encoded)];
    size_t output_length = 0;
    BackupCodecSector invalid_source = {.sector = 1, .size = 31, .data = first_data};
    BackupCodecSector null_data_source = {.sector = 1, .size = 32, .data = NULL};
    BackupCodecSector oversized_encode_source = {
        .sector = 1, .size = BACKUP_CODEC_MAX_SECTOR_BYTES + 1, .data = first_data};
    bool encode_edges =
        !backup_codec_encode(NULL, sources, 2, output, sizeof(output), &output_length) &&
        !backup_codec_encode(&header, NULL, 2, output, sizeof(output), &output_length) &&
        !backup_codec_encode(&header, sources, 0, output, sizeof(output), &output_length) &&
        !backup_codec_encode(&header, sources, 2, output, sizeof(output) - 1, &output_length) &&
        !backup_codec_encode(&header, sources, 2, NULL, sizeof(output), &output_length) &&
        !backup_codec_encode(&header, sources, 2, output, sizeof(output), NULL) &&
        !backup_codec_encode(&header, &invalid_source, 1, output, sizeof(output), &output_length) &&
        !backup_codec_encode(&header, sources, 33, output, sizeof(output), &output_length) &&
        !backup_codec_encode(&header, &null_data_source, 1, output, sizeof(output),
                             &output_length) &&
        !backup_codec_encode(&header, &oversized_encode_source, 1, output, sizeof(output),
                             &output_length);
    if (!encode_edges) {
        fprintf(stderr, "backup codec encoding-boundary self-test failed\n");
        return 1;
    }

    BackupCodecHeader legacy_header = header;
    legacy_header.product_id = 0xC24A;
    legacy_header.profile_format = 0xFF;
    uint8_t legacy_data[32] = {0};
    BackupCodecSector legacy_sector = {
        .sector = 1, .size = sizeof(legacy_data), .data = legacy_data};
    bool legacy_ok = backup_codec_sector_crc_ok(&legacy_header, &legacy_sector);
    legacy_ok = legacy_ok && !backup_codec_sector_crc_ok(&header, &legacy_sector);
    if (!legacy_ok) {
        fprintf(stderr, "backup codec legacy validation self-test failed\n");
        return 1;
    }
    return 0;
}
