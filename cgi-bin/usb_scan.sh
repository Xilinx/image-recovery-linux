#!/bin/sh
# Copyright (c) 2025 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

# CGI script to scan and mount USB/UFS devices, then list files

USB_MOUNT_DIR="usb_disk"
real_dev=""

for dev in /dev/disk/by-path/*usb* /dev/sd*; do
    [ -b "$dev" ] || continue

    BUS=$(udevadm info --query=property --name="$dev" 2>/dev/null | grep '^ID_BUS=' | cut -d= -f2)
    ID_PATH=$(udevadm info --query=property --name="$dev" 2>/dev/null | grep '^ID_PATH=' | cut -d= -f2)

    case "$BUS" in
        usb)
            echo "$dev is USB storage"
            real_dev="$dev"
            ;;
        mmc)
            echo "$dev is SD/MMC card"
            ;;
        scsi)
            if echo "$ID_PATH" | grep -qi "ufs"; then
                echo "$dev is UFS storage"
                real_dev="$dev"
            else
                echo "$dev is generic SCSI storage"
            fi
            ;;
        *)
            echo "$dev: unknown device"
            ;;
    esac
done

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
