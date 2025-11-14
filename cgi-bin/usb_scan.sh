#!/bin/sh
# Copyright (c) 2025 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

# CGI script to scan and mount USB/UFS devices, then list files

USB_MOUNT_DIR="usb_disk"
USB_DEV_PATTERNS='SanDisk|Cruzer|Kingston|Flash|USB|Toshiba|TransMemory|Transcend|JetFlash|JFV'
UFS_DEV_PATTERNS='MICRON|MT064GBCAV1U31AA'
real_dev=""

# Search for USB device
for dev in /dev/disk/by-path/*usb*; do
	[ -b "$dev" ] || continue
	model=$(udevadm info --query=property --name="$dev" 2>/dev/null | grep '^ID_MODEL=' | cut -d= -f2)
	if echo "$model" | grep -Eqi "$USB_DEV_PATTERNS"; then
		real_dev="$dev"
		break
	fi
done

# If no USB found, search for UFS device
if [ -z "$real_dev" ]; then
	for dev in /dev/sd*; do
		[ -b "$dev" ] || continue
		model=$(udevadm info --query=property --name="$dev" 2>/dev/null | grep '^ID_MODEL=' | cut -d= -f2)
		if echo "$model" | grep -Eqi "$UFS_DEV_PATTERNS"; then
			real_dev="$dev"
			break
		fi
	done
fi

# Check if device was found
if [ -z "$real_dev" ]; then
	echo "Content-type: text/plain"
	echo ""
	echo "USB/UFS device not found"
	exit 1
fi

# Create mount directory if it doesn't exist
if [ ! -d "$USB_MOUNT_DIR" ]; then
	if ! mkdir -p "$USB_MOUNT_DIR" 2>/dev/null; then
		echo "Content-type: text/plain"
		echo ""
		echo "Failed to create mount directory"
		exit 1
	fi
fi

base_dev=$(readlink -f "$real_dev")

# Mount available partitions if not already mounted
if ! grep -q "$USB_MOUNT_DIR" /proc/mounts 2>/dev/null; then
	mounted=0
	for part in "${base_dev}"[0-9]* "${base_dev}p"[0-9]*; do
		[ -b "$part" ] || continue
		if mount "$part" "$USB_MOUNT_DIR" 2>/dev/null; then
			mounted=1
			break
		fi
	done

	#Fallback: try mounting the whole device if no partitions
    if [ "$mounted" -eq 0 ]; then
        if mount "$base_dev" "$USB_MOUNT_DIR" 2>/dev/null; then
            mounted=1
        fi
    fi

	if [ "$mounted" -eq 0 ]; then
		echo "Content-type: text/plain"
		echo ""
		echo "Failed to mount any partition from $base_dev"
		exit 1
	fi
fi

# Output file list
echo "Content-type: text/plain"
echo ""

if [ -d "$USB_MOUNT_DIR" ]; then
	for file in "$USB_MOUNT_DIR"/*; do
		if [ -e "$file" ]; then
			echo "$file"
		fi
	done
else
	echo "Mount directory not accessible"
	exit 1
fi

exit 0
