#!/bin/sh
# Copyright (c) 2025 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

FILE="sys_mdata.bin"
EXTRACT_FILE="extract_sys_mdata.bin"

# Cleanup function
cleanup() {
	rm -f "$EXTRACT_FILE"
}

trap cleanup EXIT

# Check if input file exists
if [ ! -f "$FILE" ]; then
	echo "Error: File $FILE not found" >&2
	exit 1
fi

# Extract metadata for CRC calculation (skip first 4 bytes, read 120 bytes)
if ! dd if="$FILE" of="$EXTRACT_FILE" bs=1 skip=4 count=120 2>/dev/null; then
	echo "Error: Failed to extract metadata" >&2
	exit 1
fi

# Calculate CRC32
crc32_raw_mdata=$(crc32 "$EXTRACT_FILE")
if [ -z "$crc32_raw_mdata" ]; then
	echo "Error: Failed to calculate CRC32" >&2
	exit 1
fi

# Extract CRC32 value from output
IFS=" "
set -- $crc32_raw_mdata
crc32_mdata="$1"

# Convert CRC32 to little-endian binary format
if ! printf -v crc32_mdata_bin "\\x%s\\x%s\\x%s\\x%s" \
	"${crc32_mdata:6:2}" "${crc32_mdata:4:2}" "${crc32_mdata:2:2}" "${crc32_mdata:0:2}" 2>/dev/null; then
	echo "Error: Failed to format CRC32" >&2
	exit 1
fi

# Write CRC32 to the beginning of the file
if ! printf "%s" "$crc32_mdata_bin" | dd of="$FILE" bs=1 count=4 conv=notrunc 2>/dev/null; then
	echo "Error: Failed to write CRC32 to file" >&2
	exit 1
fi

# Write the updated metadata to flash partitions
if ! flash_eraseall /dev/mtd5 2>/dev/null; then
	echo "Error: Failed to erase /dev/mtd5" >&2
	exit 1
fi

if ! flash_eraseall /dev/mtd6 2>/dev/null; then
	echo "Error: Failed to erase /dev/mtd6" >&2
	exit 1
fi

if ! flashcp "$FILE" /dev/mtd5 2>/dev/null; then
	echo "Error: Failed to flash /dev/mtd5" >&2
	exit 1
fi

if ! flashcp "$FILE" /dev/mtd6 2>/dev/null; then
	echo "Error: Failed to flash /dev/mtd6" >&2
	exit 1
fi

# Remove the metadata file
rm -f "$FILE"

exit 0