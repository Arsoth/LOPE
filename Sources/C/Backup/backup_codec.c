#include "backup_codec.h"

#include "profile_codec.h"

#include <string.h>

static uint16_t backup_codec_get_be16(const uint8_t *bytes) {
    return (uint16_t)(((uint16_t)bytes[0] << 8) | bytes[1]);
}

static void backup_codec_put_be16(uint8_t *bytes, uint16_t value) {
    bytes[0] = (uint8_t)(value >> 8);
    bytes[1] = (uint8_t)(value & 0xFF);
}

bool backup_codec_parse_header(const uint8_t bytes[BACKUP_CODEC_HEADER_BYTES],
                               BackupCodecHeader *header) {
    if (bytes == NULL || header == NULL || memcmp(bytes, BACKUP_CODEC_MAGIC, 8) != 0 ||
        bytes[8] != 2) {
        return false;
    }
    BackupCodecHeader parsed = {
        .vendor_id = backup_codec_get_be16(bytes + 10),
        .product_id = backup_codec_get_be16(bytes + 12),
        .device_number = bytes[14],
        .profile_format = bytes[15],
        .sector_count = backup_codec_get_be16(bytes + 16),
    };
    if (parsed.vendor_id != 0x046D || parsed.sector_count == 0 ||
        parsed.sector_count > BACKUP_CODEC_MAX_SECTORS) {
        return false;
    }
    *header = parsed;
    return true;
}

bool backup_codec_parse_sector_table(const uint8_t *table, size_t table_length, size_t sector_count,
                                     BackupCodecSector *sectors, size_t *expected_length) {
    if (table == NULL || sectors == NULL || expected_length == NULL || sector_count == 0 ||
        sector_count > BACKUP_CODEC_MAX_SECTORS || table_length != sector_count * 4) {
        return false;
    }
    size_t total = BACKUP_CODEC_HEADER_BYTES + table_length;
    for (size_t i = 0; i < sector_count; i++) {
        BackupCodecSector parsed = {
            .sector = backup_codec_get_be16(table + i * 4),
            .size = backup_codec_get_be16(table + i * 4 + 2),
            .data = NULL,
        };
        if (parsed.size < BACKUP_CODEC_MIN_SECTOR_BYTES ||
            parsed.size > BACKUP_CODEC_MAX_SECTOR_BYTES) {
            return false;
        }
        for (size_t previous = 0; previous < i; previous++) {
            if (sectors[previous].sector == parsed.sector) {
                return false;
            }
        }
        sectors[i] = parsed;
        total += parsed.size;
    }
    *expected_length = total;
    return true;
}

bool backup_codec_sector_crc_ok(const BackupCodecHeader *header, const BackupCodecSector *sector) {
    if (header == NULL || sector == NULL) {
        return false;
    }
    if (sector->data == NULL) {
        return false;
    }
    if (sector->size < BACKUP_CODEC_MIN_SECTOR_BYTES ||
        sector->size > BACKUP_CODEC_MAX_SECTOR_BYTES) {
        return false;
    }
    bool legacy_g600 = header->profile_format == 0xFF && header->product_id == 0xC24A;
    return legacy_g600 || profile_codec_sector_crc_ok(sector->data, sector->size);
}

bool backup_codec_encode(const BackupCodecHeader *header, const BackupCodecSector *sectors,
                         size_t sector_count, uint8_t *out, size_t out_capacity,
                         size_t *out_length) {
    if (header == NULL || sectors == NULL || out == NULL || out_length == NULL ||
        sector_count == 0 || sector_count > BACKUP_CODEC_MAX_SECTORS) {
        return false;
    }

    size_t table_length = sector_count * 4;
    size_t total = BACKUP_CODEC_HEADER_BYTES + table_length;
    for (size_t i = 0; i < sector_count; i++) {
        if (sectors[i].data == NULL || sectors[i].size < BACKUP_CODEC_MIN_SECTOR_BYTES ||
            sectors[i].size > BACKUP_CODEC_MAX_SECTOR_BYTES) {
            return false;
        }
        total += sectors[i].size;
    }
    if (out_capacity < total) {
        return false;
    }

    memset(out, 0, BACKUP_CODEC_HEADER_BYTES + table_length);
    memcpy(out, BACKUP_CODEC_MAGIC, 8);
    out[8] = 2;
    backup_codec_put_be16(out + 10, header->vendor_id);
    backup_codec_put_be16(out + 12, header->product_id);
    out[14] = header->device_number;
    out[15] = header->profile_format;
    backup_codec_put_be16(out + 16, (uint16_t)sector_count);
    for (size_t i = 0; i < sector_count; i++) {
        uint8_t *entry = out + BACKUP_CODEC_HEADER_BYTES + i * 4;
        backup_codec_put_be16(entry, sectors[i].sector);
        backup_codec_put_be16(entry + 2, sectors[i].size);
    }

    // Sector payloads follow the complete header and table in source order.
    size_t data_offset = BACKUP_CODEC_HEADER_BYTES + table_length;
    for (size_t i = 0; i < sector_count; i++) {
        memcpy(out + data_offset, sectors[i].data, sectors[i].size);
        data_offset += sectors[i].size;
    }
    *out_length = data_offset;
    return true;
}

bool backup_codec_decode(const uint8_t *bytes, size_t length, BackupCodecPackage *package) {
    if (bytes == NULL || package == NULL) {
        return false;
    }
    memset(package, 0, sizeof(*package));
    BackupCodecHeader header;
    if (length < BACKUP_CODEC_HEADER_BYTES || !backup_codec_parse_header(bytes, &header)) {
        return false;
    }
    size_t table_length = header.sector_count * 4;
    if (length < BACKUP_CODEC_HEADER_BYTES + table_length) {
        return false;
    }
    size_t expected_length = 0;
    if (!backup_codec_parse_sector_table(bytes + BACKUP_CODEC_HEADER_BYTES, table_length,
                                         header.sector_count, package->sectors, &expected_length) ||
        length != expected_length) {
        memset(package, 0, sizeof(*package));
        return false;
    }
    package->header = header;
    size_t data_offset = BACKUP_CODEC_HEADER_BYTES + table_length;
    for (size_t i = 0; i < header.sector_count; i++) {
        package->sectors[i].data = bytes + data_offset;
        if (!backup_codec_sector_crc_ok(&header, &package->sectors[i])) {
            memset(package, 0, sizeof(*package));
            return false;
        }
        data_offset += package->sectors[i].size;
    }
    return true;
}
