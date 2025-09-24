#!/bin/sh
# Copyright (c) 2025 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

usb_part=1
usb_dev='SanDisk|Cruzer|Kingston|Flash|USB|Toshiba|TransMemory|Transcend|JetFlash|JFV'
ufs_dev='MICRON|MT064GBCAV1U31AA'


for dev in /dev/disk/by-path/*usb*; do
	[ -b "$dev" ] || continue
	model=$(udevadm info --query=property --name="$dev" | grep '^ID_MODEL=' | cut -d= -f2)
	if echo "$model" | grep -Eqi "$usb_dev"; then
		real_dev="$dev"
		echo "Detected USB device: $real_dev ($model)"
		break
	fi
done

if [ -z "$real_dev" ]; then
	for dev in /dev/sd*; do
		[ -b "$dev" ] || continue
		model=$(udevadm info --query=property --name="$dev" | grep '^ID_MODEL=' | cut -d= -f2)
		if echo "$model" | grep -Eqi "$ufs_dev"; then
			real_dev="$dev"
			echo "Detected UFS device: $real_dev ($model)"
			break
		fi
	done
fi


if [ -z "$real_dev" ]; then
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
