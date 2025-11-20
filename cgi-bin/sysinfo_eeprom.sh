#!/bin/sh
# Copyright (c) 2025 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

# Helper: Convert hex string (no spaces) to ASCII
hex_to_ascii() {
	local hex="$1"
	local out=""
	for ((i=0; i<${#hex}; i+=2)); do
		out+=$(printf "\\x${hex:$i:2}")
	done
	echo -n "$out"
}

# Load IPMI utilities
if ! source ./ipmi.sh; then
	echo "Content-type: application/json"
	echo ""
	echo '{"error":"Failed to source ipmi.sh"}'
	exit 1
fi

# Find the first available EEPROM if not hardcoded
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

# Allocate FRU index
if ! ipmi_fru_alloc "$EEPROM_PATH" eeprom_idx; then
	echo "Content-type: application/json"
	echo ""
	echo '{"error":"Failed to allocate FRU"}'
	exit 1
fi

# Read header and decode board area
declare -a header=()
if ! read_header "$eeprom_idx" header; then
	echo "Content-type: application/json"
	echo ""
	echo '{"error":"Failed to read FRU header"}'
	ipmi_fru_free "$eeprom_idx"
	exit 1
fi

board_offset=${header[$IPMI_FRU_COMMON_HEADER_BOARD_OFFSET_IDX]}
decode_output=$(decode_board_area "$eeprom_idx" "$board_offset")
ipmi_fru_free "$eeprom_idx"

# Extract main board fields
brdnm=$(echo "$decode_output" | grep -E "FRU Board Product Name" | cut -d':' -f2- | xargs)
srlnum=$(echo "$decode_output" | grep -E "FRU Board Serial Number" | cut -d':' -f2- | xargs)
prtnum=$(echo "$decode_output" | grep -E "FRU Board Part Number" | cut -d':' -f2- | xargs)

# Extract Revision Number
revnum=$(echo "$decode_output" | grep "FRU Board Custom Info:" | grep -v "HEX" | while IFS=: read -r _ val; do
val=$(echo "$val" | xargs)
[ -n "$val" ] && echo "$val" && break
done)

if [ -z "$revnum" ]; then
	hexrev=$(echo "$decode_output" | grep "FRU Board Custom Info HEX:" | head -n 1 | cut -d':' -f2- | xargs)
	if [ -n "$hexrev" ]; then
		revnum=$(hex_to_ascii "$hexrev" | tr -cd 'A-Za-z0-9._-')
	fi
fi

# Extract UUID (last HEX custom info, clean format)
uuid_hex=$(echo "$decode_output" | grep "FRU Board Custom Info HEX:" | tail -n 1 | cut -d':' -f2-)
uuid=$(echo "$uuid_hex" | tr -d ' ' | tr -d 'hH' | tr -cd '0-9a-fA-F' | tr 'a-f' 'A-F')

# Output JSON response
echo "Content-type: application/json"
echo ""
echo '{"SysBoardInfo":{"BoardName":"'"${brdnm}"'","RevisionNo":"'"${revnum}"'","SerialNo":"'"${srlnum}"'","PartNo":"'"${prtnum}"'","UUID":"'"${uuid}"'"},"CcInfo":{"BoardName":"","RevisionNo":"","SerialNo":"","PartNo":"","UUID":""}}'

exit 0
