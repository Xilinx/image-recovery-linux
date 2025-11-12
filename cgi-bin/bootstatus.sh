#!/bin/sh
# Copyright (c) 2025 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

# Create temporary file for metadata
temp_file=$(mktemp) || exit 1
trap 'rm -f "$temp_file"' EXIT

# Read metadata from MTD device
if ! cat /dev/mtd5 > "$temp_file" 2>/dev/null; then
	echo "Content-type: application/json"
	echo ""
	echo '{ "error": "Failed to read MTD5 device" }'
	exit 1
fi

# Extract boot status information
bankA_status=$(hexdump -s 0x18 -n1 -e '"%x"' "$temp_file")
bankB_status=$(hexdump -s 0x19 -n1 -e '"%x"' "$temp_file")
active_bank=$(hexdump -s 0x8 -n4 -e '"%x"' "$temp_file")
prev_active_bank=$(hexdump -s 0xC -n4 -e '"%x"' "$temp_file")

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
if [ "$active_bank" = "0" ]; then
	active_bnk="ImageA"
else
	active_bnk="ImageB"
fi

# Determine previous active bank
if [ "$prev_active_bank" = "0" ]; then
	prev_active_bnk="ImageA"
else
	prev_active_bnk="ImageB"
fi

# Output JSON response
echo "Content-type: application/json"
echo ""
echo '{ "BankAStatus":'${bankA_st}', "BankBStatus":'${bankB_st}', "ActiveBank":"'${active_bnk}'", "PrevActiveBank":"'${prev_active_bnk}'" }'

