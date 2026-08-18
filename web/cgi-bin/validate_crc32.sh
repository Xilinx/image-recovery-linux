#!/bin/sh
# Copyright (c) 2025 - 2026 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

# CGI script to validate CRC32 of uploaded image
# Expects JSON input: {"ImageName":"filename","Crc32":12345}

# Read JSON data from stdin
json_data=$(cat)

if [ -z "$json_data" ]; then
	echo "Content-type: application/json"
	echo ""
	echo '{ "Status":"Fail", "Error":"No input data" }'
	exit 1
fi

# Parse JSON to extract image name and expected CRC32
# Format: {"ImageName":"filename","Crc32":value}
img_filename=$(printf '%s' "$json_data" | sed -n 's/.*"ImageName"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
exp_crc32=$(printf '%s' "$json_data" | sed -n 's/.*"Crc32"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p')

# Validate image filename
if [ -z "$img_filename" ]; then
	echo "Content-type: application/json"
	echo ""
	echo '{ "Status":"Fail", "Error":"Invalid image name" }'
	exit 1
fi

# Check if file exists
if [ ! -f "$img_filename" ]; then
	echo "Content-type: application/json"
	echo ""
	echo '{ "Status":"Fail", "Error":"Image file not found" }'
	exit 1
fi

# Validate expected CRC32 value
if [ -z "$exp_crc32" ]; then
	echo "Content-type: application/json"
	echo ""
	echo '{ "Status":"Fail", "Error":"Invalid CRC32 value" }'
	exit 1
fi

# Calculate CRC32 of the file
str_crc32=$(crc32 "$img_filename" 2>/dev/null)
if [ -z "$str_crc32" ]; then
	echo "Content-type: application/json"
	echo ""
	echo '{ "Status":"Fail", "Error":"Failed to calculate CRC32" }'
	exit 1
fi

IFS=" "
set -- $str_crc32
cal_crc32=$((0x${1}))

# Validate numeric values
if ! [ "$cal_crc32" -ge 0 ] 2>/dev/null || ! [ "$exp_crc32" -ge 0 ] 2>/dev/null; then
	echo "Content-type: application/json"
	echo ""
	echo '{ "Status":"Fail", "Error":"Invalid CRC32 values" }'
	exit 1
fi

# Output JSON response
echo "Content-type: application/json"
echo ""

if [ "$cal_crc32" -eq "$exp_crc32" ]; then
	echo '{ "Status":"Success" }'
else
	echo "{ \"Status\":\"Fail\", \"Calculated\":$cal_crc32, \"Expected\":$exp_crc32 }"
fi

exit 0
