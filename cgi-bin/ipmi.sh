#!/bin/sh
# Copyright (c) 2025 - 2026 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT
# ipmi-fru is a library, not executed directly

# Simplified IPMI FRU library using sysfs I2C EEPROMs

# Index for Area size in FRU area header
IPMI_FRU_AREA_HEADER_SIZE_IDX=1

# Map: FRU index → sysfs EEPROM path
declare -A IPMI_FRU_EEPROM_FILE=()

# Allocate a FRU index for a given EEPROM path
ipmi_fru_alloc() {
	local name="$1"
	local -n ret="$2"
	for (( ret = 0; ret < 32; ++ret )); do
		[ -z "${IPMI_FRU_EEPROM_FILE[$ret]+1}" ] && break
	done
	if [[ -f "$name" ]]; then
		IPMI_FRU_EEPROM_FILE["$ret"]="$name"
	else
		echo "Invalid EEPROM specification: $name" >&2
		return 1
	fi
}

# Free a previously allocated FRU index
ipmi_fru_free() {
	unset 'IPMI_FRU_EEPROM_FILE[$1]'
}

# Calculate checksum of a byte array (array of decimal bytes)
checksum() {
	local -n arr="$1"
	local sum=0
	for byte in "${arr[@]}"; do
		sum=$((sum + byte))
	done
	echo $((sum & 0xff))
}

# Read bytes from EEPROM at given offset and size
read_bytes() {
	local eeprom="${IPMI_FRU_EEPROM_FILE["$1"]-$1}"
	local offset="$2"
	local size="$3"

	dd if="$eeprom" bs=1 skip="$offset" count="$size" status=none 2>/dev/null | \
	hexdump -v -e '1/1 "%u "'
}

# Read and validate the FRU header (8 bytes)
read_header() {
	local eeprom="$1"
	local -n hdr="$2"

	read -r -a hdr <<< "$(read_bytes "$eeprom" 0 8)" || return 1
	(( hdr[0] == 1 )) || return 1

	local sum
	sum="$(checksum hdr)" || return 1
	(( sum == 0 )) || return 10
}

# Read and validate a FRU area (e.g., board area)
read_area() {
	local eeprom="$1"
	local offset="$2"
	local -n area="$3"
	local size="${4:-0}"

	offset=$((offset * 8))
	read -r -a area <<< "$(read_bytes "$eeprom" "$offset" 8)" || return
	(( area[0] == 1 )) || return
	if (( size == 0 )); then
		size=${area[$IPMI_FRU_AREA_HEADER_SIZE_IDX]}
	fi
	read -r -a area <<< "$(read_bytes "$eeprom" "$offset" $((size * 8)))" || return
	local sum
	sum="$(checksum area)" || return
	(( sum == 0 )) || return 10
}

# Decode and print the FRU board area fields and custom info
decode_board_area() {
	local eeprom="$1"
	local offset="$2"
	local -a board_bytes
	read_area "$eeprom" "$offset" board_bytes || return

	local idx=0
	idx=$((idx + 1)) # Skip version
	local area_len=${board_bytes[$((idx++))]}
	idx=$((idx + 1)) # Skip lang_code
	idx=$((idx + 3)) # Skip mfg_min_low, mfg_min_mid, mfg_min_high

	local end_offset=$((area_len * 8))
	local fields=( "Manufacturer" "Product Name" "Serial Number" "Part Number" "FRU File ID" )

	# Print standard board area fields
	for field in "${fields[@]}"; do
		(( idx >= end_offset )) && break
		local type_len=${board_bytes[$((idx++))]}
		((type_len == 0xC1)) && break
		local str_len=$((type_len & 0x3F))
		local value=""
		for ((i=0; i<str_len && idx<end_offset; i++)); do
			local byte=${board_bytes[$((idx++))]}
			if (( byte >= 32 && byte <= 126 )); then
				value+=$(printf "%b" "\\$(printf "%03o" "$byte")")
			fi
		done
		printf "FRU Board %-20s: %s\n" "$field" "$value"
	done

	# Print custom info fields (ASCII and HEX)
	while (( idx < end_offset )); do
		local type_len=${board_bytes[$((idx++))]}
		((type_len == 0xC1)) && break
		local len=$((type_len & 0x3F))
		(( idx + len > end_offset )) && break

		local value="" hexval="" ascii_only=1

		for ((i = 0; i < len && idx < end_offset; i++)); do
			local byte=${board_bytes[$((idx++))]}
			byte=$((byte & 0xFF))
			hexval+=$(printf "%02X" "$byte")

			if (( byte >= 32 && byte <= 126 )); then
				value+=$(printf "%b" "\\$(printf "%03o" "$byte")")
			else
				ascii_only=0
			fi
		done

		[[ -n "$value" && "$ascii_only" -eq 1 ]] && echo "FRU Board Custom Info: $value"
		[[ -n "$hexval" && "$len" -gt 4 ]] && echo "FRU Board Custom Info HEX: $hexval"
	done
}

return 0 2>/dev/null
