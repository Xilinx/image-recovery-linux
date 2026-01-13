#!/bin/sh
# Copyright (c) 2025 - 2026 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

echo "Content-type: application/json"
echo ""

# Find all available storage devices
devices_json="["
first=true

for dev in /dev/disk/by-path/* /dev/mmcblk* /dev/sd*; do
    [ -e "$dev" ] || continue
    resolved=$(readlink -f "$dev")
    [ -b "$resolved" ] || continue

    # Skip if we've already seen this device
    if echo "$seen_devices" | grep -q "$resolved"; then
        continue
    fi
    seen_devices="$seen_devices $resolved"

    # Get device information
    udev_info=$(udevadm info --query=property --name="$resolved" 2>/dev/null)
    id_path=$(echo "$udev_info" | grep '^ID_PATH=' | cut -d= -f2)
    id_model=$(echo "$udev_info" | grep '^ID_MODEL=' | cut -d= -f2)
    id_serial=$(echo "$udev_info" | grep '^ID_SERIAL_SHORT=' | cut -d= -f2)
    devtype=$(echo "$udev_info" | grep '^DEVTYPE=' | cut -d= -f2)
    # Skip partitions, only show disks
    [ "$devtype" = "partition" ] && continue
    # Get size in bytes
    size=""
    if [ -f "/sys/block/$(basename "$resolved")/size" ]; then
        size=$(cat "/sys/block/$(basename "$resolved")/size")
        size=$((size * 512))  # Convert sectors to bytes
    fi

    # Determine bus type
    bus_type="unknown"
    if echo "$id_path" | grep -qi "ufs"; then
        bus_type="ufs"
    elif echo "$id_path" | grep -qi "usb"; then
        bus_type="usb"
    elif echo "$id_path" | grep -qi "mmc"; then
        bus_type="mmc"
    fi

    # Add comma separator for subsequent entries
    if [ "$first" = true ]; then
        first=false
    else
        devices_json="$devices_json,"
    fi

    # Build JSON entry
    devices_json="$devices_json{\"device\":\"$resolved\",\"bus\":\"$bus_type\",\"model\":\"${id_model:-unknown}\",\"serial\":\"${id_serial:-unknown}\",\"size\":${size:-0},\"devtype\":\"${devtype:-disk}\"}"
done

devices_json="$devices_json]"

# Return JSON response
echo "$devices_json"
exit 0