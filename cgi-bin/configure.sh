#!/bin/sh
# Copyright (c) 2025 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

CONFG_FILE="update_confg.bin"
SCRIPT_DIR="$(dirname "$0")"

trap 'rm -f "CONFG_FILE"' EXIT

# Read current configuration from MTD device
if ! cat /dev/mtd3 > "$CONFG_FILE" 2>/dev/null; then
	echo "Error: Failed to read /dev/mtd3" >&2
	exit 1
fi

# Read configuration parameters from stdin
confg_boot=$(cat)
if [ -z "$confg_boot" ]; then
	echo "Error: No configuration parameters provided" >&2
	exit 1
fi

# Parse configuration parameters (format: param1_value1_param2_value2_...)
IFS="_"
set -- $confg_boot

# Validate we have enough parameters
if [ "$#" -lt 6 ]; then
	echo "Error: Insufficient parameters (expected at least 6)" >&2
	exit 1
fi

# Update Bank A bootable status (offset 18)
# Parameter $2 should be "true" or "false"
if [ "$2" = "true" ]; then
	if ! printf "\x01" | dd of="$CONFG_FILE" bs=1 seek=18 count=1 conv=notrunc 2>/dev/null; then
		echo "Error: Failed to write Bank A status" >&2
		exit 1
	fi
else
	if ! printf "\x00" | dd of="$CONFG_FILE" bs=1 seek=18 count=1 conv=notrunc 2>/dev/null; then
		echo "Error: Failed to write Bank A status" >&2
		exit 1
	fi
fi

# Update Bank B bootable status (offset 19)
# Parameter $4 should be "true" or "false"
if [ "$4" = "true" ]; then
	if ! printf "\x01" | dd of="$CONFG_FILE" bs=1 seek=19 count=1 conv=notrunc 2>/dev/null; then
		echo "Error: Failed to write Bank B status" >&2
		exit 1
	fi
else
	if ! printf "\x00" | dd of="$CONFG_FILE" bs=1 seek=19 count=1 conv=notrunc 2>/dev/null; then
		echo "Error: Failed to write Bank B status" >&2
		exit 1
	fi
fi

# Update requested boot image (offset 17)
# Parameter $6 should be "ImageA" or "ImageB"
if [ "$6" = "ImageA" ]; then
	if ! printf "\x00" | dd of="$CONFG_FILE" bs=1 seek=17 count=1 conv=notrunc 2>/dev/null; then
		echo "Error: Failed to write requested boot image" >&2
		exit 1
	fi
else
	if ! printf "\x01" | dd of="$CONFG_FILE" bs=1 seek=17 count=1 conv=notrunc 2>/dev/null; then
		echo "Error: Failed to write requested boot image" >&2
		exit 1
	fi
fi

# Calculate checksum and write to flash
if [ -x "$SCRIPT_DIR/checksum.sh" ]; then
	if ! "$SCRIPT_DIR/checksum.sh"; then
		echo "Error: checksum.sh failed" >&2
		exit 1
	fi
else
	echo "Error: checksum.sh not found or not executable" >&2
	exit 1
fi

exit 0
