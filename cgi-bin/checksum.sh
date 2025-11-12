#!/bin/sh
# Copyright (c) 2025 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

FILE="update_confg.bin"

# Check if input file exists
if [ ! -f "$FILE" ]; then
	echo "Error: File $FILE not found" >&2
	exit 1
fi

# Initialize sum to 0
sum=0

# Calculate sum of all 4-byte words except index 3 (offset 12)
for i in $(seq 0 7); do
	if [ "$i" -ne 3 ]; then
		value=$(hexdump -s $((i * 4)) -n4 -e '"0x%x"' "$FILE" 2>/dev/null)
		if [ -z "$value" ]; then
			echo "Error: Failed to read data at offset $((i * 4))" >&2
			exit 1
		fi
		sum=$(awk "BEGIN {print $sum+$value; exit}")
	fi
done

# Calculate checksum (0xFFFFFFFF - sum)
checksum=$((0xFFFFFFFF - sum))

# Convert checksum to little-endian binary format
if ! printf -v f '\\x%02x\\x%02x\\x%02x\\x%02x' \
	$((checksum & 255)) \
	$((checksum >> 8 & 255)) \
	$((checksum >> 16 & 255)) \
	$((checksum >> 24 & 255)) 2>/dev/null; then
	echo "Error: Failed to format checksum" >&2
	exit 1
fi

# Write checksum to offset 12 (4 bytes)
if ! printf "%s" "$f" | dd of="$FILE" bs=1 seek=12 count=4 conv=notrunc 2>/dev/null; then
	echo "Error: Failed to write checksum to file" >&2
	exit 1
fi

# Write the updated configuration to flash partitions
if ! flash_eraseall /dev/mtd3 2>/dev/null; then
	echo "Error: Failed to erase /dev/mtd3" >&2
	exit 1
fi

if ! flashcp "$FILE" /dev/mtd3 2>/dev/null; then
	echo "Error: Failed to flash /dev/mtd3" >&2
	exit 1
fi

if ! flash_eraseall /dev/mtd4 2>/dev/null; then
	echo "Error: Failed to erase /dev/mtd4" >&2
	exit 1
fi

if ! flashcp "$FILE" /dev/mtd4 2>/dev/null; then
	echo "Error: Failed to flash /dev/mtd4" >&2
	exit 1
fi

# Remove the configuration file
rm -f "$FILE"

exit 0
