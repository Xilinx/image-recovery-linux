#!/bin/sh
# Copyright (c) 2025 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

SYSINFO_FILE="sysinfo.bin"

# Cleanup function
cleanup() {
	rm -f "$SYSINFO_FILE"
}

trap cleanup EXIT

# Read EEPROM data
EEPROM_PATH=""
for eeprom in /sys/bus/i2c/devices/*/eeprom; do
	if [ -f "$eeprom" ]; then
		EEPROM_PATH="$eeprom"
		break
	fi
done

if [ -z "$EEPROM_PATH" ]; then
	echo "Content-type: application/json"
	echo ""
	echo '{"error":"EEPROM not found"}'
	exit 1
fi

if ! cat "$EEPROM_PATH" > "$SYSINFO_FILE" 2>/dev/null; then
	echo "Content-type: application/json"
	echo ""
	echo '{"error":"Failed to read EEPROM"}'
	exit 1
fi

# Extract system board information
brdnm=$(hexdump -s 0x16 -n6 -e '8/1 "%c"' "$SYSINFO_FILE" | tr -d '\000' | tr -cd 'A-Za-z0-9 ._-')
revnum=$(hexdump -s 0x44 -n8 -e '8/1 "%c"' "$SYSINFO_FILE" | tr -d '\000' | tr -cd 'A-Za-z0-9 ._-')
srlnum=$(hexdump -s 0x27 -n16 -e '8/1 "%c"' "$SYSINFO_FILE" | tr -d '\000' | tr -cd 'A-Za-z0-9 ._-')
prtnum=$(hexdump -s 0x38 -n9 -e '8/1 "%c"' "$SYSINFO_FILE" | tr -d '\000' | tr -cd 'A-Za-z0-9 ._-')
uuid=$(hexdump -s 0x56 -n16 -e '8/1 "%X"' "$SYSINFO_FILE" | tr -d '\000' | tr -cd 'A-Za-z0-9 ._-')

# Convert UUID to uppercase
uuid="${uuid^^}"

# Output JSON response
echo "Content-type: application/json"
echo ""
echo '{"SysBoardInfo":{"BoardName":"'"${brdnm}"'","RevisionNo":"'"${revnum}"'","SerialNo":"'"${srlnum}"'","PartNo":"'"${prtnum}"'","UUID":"'"${uuid}"'"},"CcInfo":{"BoardName":"","RevisionNo":"","SerialNo":"","PartNo":"","UUID":""}}'

exit 0
