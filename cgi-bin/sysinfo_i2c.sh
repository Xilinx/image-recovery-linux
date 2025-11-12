#!/bin/sh
# Copyright (c) 2025 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

# CGI script to read system board information via I2C

# Extract board name (offset 0x16, 6 bytes)
brdnm_raw=$(i2ctransfer -y 1 w2@0x54 0x0 0x16 r6 2>/dev/null | sed 's/0x/\\x/g' | sed 's/ //g')
if [ -z "$brdnm_raw" ]; then
	echo "Content-type: application/json"
	echo ""
	echo '{"error":"Failed to read board name from I2C"}'
	exit 1
fi
brdnm=$(printf "%b\n" "$brdnm_raw")

# Extract revision number (offset 0x44, 8 bytes)
revnum_raw=$(i2ctransfer -y 1 w2@0x54 0x0 0x44 r8 2>/dev/null | sed 's/0x/\\x/g' | sed 's/ //g')
if [ -z "$revnum_raw" ]; then
	echo "Content-type: application/json"
	echo ""
	echo '{"error":"Failed to read revision number from I2C"}'
	exit 1
fi
revnum=$(printf "%b\n" "$revnum_raw")

# Extract serial number (offset 0x27, 16 bytes)
srlnum_raw=$(i2ctransfer -y 1 w2@0x54 0x0 0x27 r16 2>/dev/null | sed 's/0x/\\x/g' | sed 's/ //g')
if [ -z "$srlnum_raw" ]; then
	echo "Content-type: application/json"
	echo ""
	echo '{"error":"Failed to read serial number from I2C"}'
	exit 1
fi
srlnum=$(printf "%b\n" "$srlnum_raw")

# Extract part number (offset 0x38, 9 bytes)
prtnum_raw=$(i2ctransfer -y 1 w2@0x54 0x0 0x38 r9 2>/dev/null | sed 's/0x/\\x/g' | sed 's/ //g')
if [ -z "$prtnum_raw" ]; then
	echo "Content-type: application/json"
	echo ""
	echo '{"error":"Failed to read part number from I2C"}'
	exit 1
fi
prtnum=$(printf "%b\n" "$prtnum_raw")

# Extract UUID (offset 0x56, 16 bytes)
uuid=$(i2ctransfer -y 1 w2@0x54 0x0 0x56 r16 2>/dev/null | sed 's/0x//g' | sed 's/ //g')
if [ -z "$uuid" ]; then
	echo "Content-type: application/json"
	echo ""
	echo '{"error":"Failed to read UUID from I2C"}'
	exit 1
fi

# Convert UUID to uppercase
uuid="${uuid^^}"

# Output JSON response
echo "Content-type: application/json"
echo ""
echo '{"SysBoardInfo":{"BoardName":"'"${brdnm}"'","RevisionNo":"'"${revnum}"'","SerialNo":"'"${srlnum}"'","PartNo":"'"${prtnum}"'","UUID":"'"${uuid}"'"},"CcInfo":{"BoardName":"","RevisionNo":"","SerialNo":"","PartNo":"","UUID":""}}'

exit 0