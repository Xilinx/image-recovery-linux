#!/bin/sh
# Copyright (c) 2025 - 2026 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

# CGI script to scan and mount USB/UFS devices, then list files

USB_MOUNT_DIR="usb_disk"
real_devs=""

for dev in /dev/disk/by-path/*usb* /dev/sd*; do
    [ -b "$dev" ] || continue

    BUS=$(udevadm info --query=property --name="$dev" 2>/dev/null | grep '^ID_BUS=' | cut -d= -f2)
    ID_PATH=$(udevadm info --query=property --name="$dev" 2>/dev/null | grep '^ID_PATH=' | cut -d= -f2)
    resolved_dev=$(readlink -f "$dev")

    case "$BUS" in
        usb)
            echo "$dev is USB storage"
            # Add to list if not already present
            if ! echo "$real_devs" | grep -q "$resolved_dev"; then
                real_devs="$real_devs $resolved_dev"
            fi
            ;;
        mmc)
            echo "$dev is SD/MMC card"
            ;;
        scsi)
            if echo "$ID_PATH" | grep -qi "ufs"; then
                echo "$dev is UFS storage"
                # Add to list if not already present
                if ! echo "$real_devs" | grep -q "$resolved_dev"; then
                    real_devs="$real_devs $resolved_dev"
                fi
            else
                echo "$dev is generic SCSI storage"
            fi
            ;;
        *)
            echo "$dev: unknown device"
            ;;
    esac
done

echo "Detected devices: $real_devs"
# Check if device was found
if [ -z "$real_devs" ]; then
	echo "Content-type: text/plain"
	echo ""
	echo "USB/UFS device not found"
	exit 1
fi

# Create base mount directory if it doesn't exist
if [ ! -d "$USB_MOUNT_DIR" ]; then
	if ! mkdir -p "$USB_MOUNT_DIR" 2>/dev/null; then
		echo "Content-type: text/plain"
		echo ""
		echo "Failed to create mount directory"
		exit 1
	fi
fi

mounted_count=0

# Process each unique device found
for base_dev in $real_devs; do
    echo "Processing device: $base_dev"

    # Get device name (e.g., sda from /dev/sda)
    dev_name=$(basename "$base_dev")
    dev_mount_dir="$USB_MOUNT_DIR/$dev_name"

    # Create device-specific mount directory
    if [ ! -d "$dev_mount_dir" ]; then
        if ! mkdir -p "$dev_mount_dir" 2>/dev/null; then
            echo "Failed to create mount directory for $dev_name"
            continue
        fi
    fi

    # Check if this device is already mounted at this location
    if grep -q "$dev_mount_dir" /proc/mounts 2>/dev/null; then
        echo "$dev_name already mounted at $dev_mount_dir"
        mounted_count=$((mounted_count + 1))
        continue
    fi

    # Try to mount the device directly
    if mount "$base_dev" "$dev_mount_dir" 2>/dev/null; then
        echo "Mounted $base_dev to $dev_mount_dir"
        mounted_count=$((mounted_count + 1))
    else
        # Clean up mount directory if mount failed
        rmdir "$dev_mount_dir" 2>/dev/null
        echo "Failed to mount $dev_name"
    fi
done

# Check if at least one mount was successful
if [ "$mounted_count" -eq 0 ]; then
    echo "Content-type: text/plain"
    echo ""
    echo "Failed to mount any device"
    exit 1
fi

# Output file list with directory structure
echo "Content-type: text/plain"
echo ""

if [ -d "$USB_MOUNT_DIR" ]; then
	for dev_dir in "$USB_MOUNT_DIR"/*; do
		if [ -d "$dev_dir" ]; then
			echo "Device: $(basename "$dev_dir")"
			# Recursively list all files and directories
			find "$dev_dir" -mindepth 1 | while read -r item; do
				if [ -e "$item" ]; then
					if [ -d "$item" ]; then
						echo "DIR: $item"
					else
						echo "FILE: $item"
					fi
				fi
			done
		fi
	done
else
	echo "Mount directory not accessible"
	exit 1
fi

exit 0
