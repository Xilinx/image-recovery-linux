#!/bin/sh
# Copyright (c) 2025 - 2026 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

# CGI helper that surfaces boot status and BOOT.bin version information
# for both active and previous banks

# Create temporary files
metadata_file=$(mktemp) || exit 1

trap 'rm -f "$metadata_file"' EXIT

# Helper function to escape JSON values
json_value() {
	if [ -z "$1" ]; then
		printf 'null'
	else
		escaped=$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')
		printf '"%s"' "$escaped"
	fi
}

# Read metadata from MTD device
if ! cat /dev/mtd5 > "$metadata_file" 2>/dev/null; then
	echo '{ "error": "Failed to read MTD5 device" }'
	exit 1
fi

# Extract boot status information
bankA_status=$(hexdump -s 0x18 -n1 -e '"%x"' "$metadata_file")
bankB_status=$(hexdump -s 0x19 -n1 -e '"%x"' "$metadata_file")
active_bank=$(hexdump -s 0x8 -n4 -e '"%x"' "$metadata_file")
prev_active_bank=$(hexdump -s 0xC -n4 -e '"%x"' "$metadata_file")

# Determine bank A status
if [ "$bankA_status" = "fc" ]; then
	bankA_st=true
else
	bankA_st=false
fi

# Determine bank B status
if [ "$bankB_status" = "fc" ]; then
	bankB_st=true
else
	bankB_st=false
fi

# Determine active bank
active_bank_num=$((0x$active_bank))
if [ "$active_bank_num" = "0" ]; then
	active_bnk="ImageA"
else
	active_bnk="ImageB"
fi

# Determine previous active bank
prev_active_bank_num=$((0x$prev_active_bank))
if [ "$prev_active_bank_num" = "0" ]; then
	prev_active_bnk="ImageA"
else
	prev_active_bnk="ImageB"
fi

# Determine boot device paths based on active bank
case "$active_bank_num" in
	0) boot_dev_active="/dev/mtd9"; boot_dev_prev="/dev/mtd12" ;;
	1) boot_dev_active="/dev/mtd12"; boot_dev_prev="/dev/mtd9" ;;
	*) boot_dev_active=""; boot_dev_prev="" ;;
esac

# Function to extract version from boot device
get_version() {
	local dev="$1"
	local snippet_file
	snippet_file=$(mktemp) || return
	if dd if="$dev" of="$snippet_file" bs=512k count=8 2>/dev/null; then
		# Remove everything up to and including the first semicolon
		# Then extract the Version= field
		strings "$snippet_file" | grep -m1 'Version='| sed 's/^[^;]*;//' | sed 's/Version=//; s/;/ /g; s/SW_CRC/CRC/'
	fi
	rm -f "$snippet_file"
}

# Get version information
version_active=""
version_prev=""
if [ -n "$boot_dev_active" ] && [ -r "$boot_dev_active" ]; then
	version_active=$(get_version "$boot_dev_active")
fi
if [ -n "$boot_dev_prev" ] && [ -r "$boot_dev_prev" ]; then
	version_prev=$(get_version "$boot_dev_prev")
fi

# Output combined JSON response
printf "Content-type: application/json\n"
printf "\n"
printf '{ "BankAStatus": %s, "BankBStatus": %s, "ActiveBank": "%s", "PrevActiveBank": "%s", "version_active": %s, "version_prev": %s }\n' \
	"$bankA_st" \
	"$bankB_st" \
	"$active_bnk" \
	"$prev_active_bnk" \
	"$(json_value "$version_active")" \
	"$(json_value "$version_prev")"

exit 0
