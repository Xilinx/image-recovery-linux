#!/bin/sh
# Copyright (c) 2025 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

usb_part=1

for dev in /dev/disk/by-path/*usb*; do
	real_dev=$(readlink -f "$dev")
	model=$(udevadm info --query=property --name="$real_dev" | grep '^ID_MODEL=' | cut -d= -f2)

	# Match common USB stick patterns (adjust as needed)
	if echo "$model" | grep -Eqi 'SanDisk|Cruzer|Kingston|Flash|USB|Toshiba|TransMemory|Transcend|JetFlash|JFV'; then
		#echo "USB stick found: $dev -> $real_dev (Model: $model)"
		break
	fi
done

if ! echo "$model" | grep -Eqi 'SanDisk|Cruzer|Kingston|Flash|USB'; then
	echo "Content-type: text/html"
	echo ""
	echo "USB stick not found"
	exit 1
fi

if [ ! -d ./usb_disk ]; then
	mkdir usb_disk
fi

# Check if device is already mounted at the mount point
if ! grep -q "usb_disk" /proc/mounts; then
    #echo "Mounting to usb_disk..."
    mount $real_dev${usb_part} usb_disk
fi

echo "Content-type: text/html"
echo ""
dir=./usb_disk
for files in "$dir"/*
do
	#filename=$(basename $files)
	echo "$files"
done
