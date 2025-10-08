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

base_dev=$(readlink -f "$real_dev")

# mounting the  available partitions.
if ! grep -q "usb_disk" /proc/mounts; then
	for part in $(ls ${base_dev}? 2>/dev/null); do
		[ -b "$part" ] || continue
		echo "Attempting to mount $part..."
		mount "$part" usb_disk && break
	done
fi

echo "Content-type: text/html"
echo ""
dir=./usb_disk
for files in "$dir"/*
do
	#filename=$(basename $files)
	echo "$files"
done
