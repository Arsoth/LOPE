#ifndef LOPE_LOGITECH_ONBOARD_BACKUP_CODEC_H
#define LOPE_LOGITECH_ONBOARD_BACKUP_CODEC_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define BACKUP_CODEC_HEADER_BYTES 20
#define BACKUP_CODEC_MAGIC "LOGIOB02"
#define BACKUP_CODEC_MAX_SECTORS 32
#define BACKUP_CODEC_MIN_SECTOR_BYTES 32
#define BACKUP_CODEC_MAX_SECTOR_BYTES 4096

typedef struct {
    uint16_t vendor_id;
    uint16_t product_id;
    uint8_t device_number;
    uint8_t profile_format;
    size_t sector_count;
} BackupCodecHeader;

typedef struct {
    uint16_t sector;
    uint16_t size;
    const uint8_t *data;
} BackupCodecSector;

typedef struct {
    BackupCodecHeader header;
    BackupCodecSector sectors[BACKUP_CODEC_MAX_SECTORS];
} BackupCodecPackage;

bool backup_codec_parse_header(const uint8_t bytes[BACKUP_CODEC_HEADER_BYTES],
                               BackupCodecHeader *header);
bool backup_codec_parse_sector_table(const uint8_t *table, size_t table_length, size_t sector_count,
                                     BackupCodecSector *sectors, size_t *expected_length);
bool backup_codec_sector_crc_ok(const BackupCodecHeader *header, const BackupCodecSector *sector);

bool backup_codec_encode(const BackupCodecHeader *header, const BackupCodecSector *sectors,
                         size_t sector_count, uint8_t *out, size_t out_capacity,
                         size_t *out_length);
bool backup_codec_decode(const uint8_t *bytes, size_t length, BackupCodecPackage *package);

#endif // LOPE_LOGITECH_ONBOARD_BACKUP_CODEC_H
