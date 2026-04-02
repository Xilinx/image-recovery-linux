#!/bin/sh
# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

# CGI helper that surfaces version information for:
# - Image Recovery Application
# - Image Selector Application
# - Bank A and Bank B images

# Constants for bootgen optional data extraction
IHT_OFFSET_DEFAULT=196                  # 0xC4 - Image Header Table offset (default: Versal/ZynqMP)
IHT_OFFSET_VERSAL_2VE_2VM=720          # 0x2D0 - Image Header Table offset for Versal_2VE_2VM
XIH_IHT_LEN=128                        # 0x80 - Image Header Table length
OPT_DATA_ID_VERSION=33                 # 0x21 - Optional data ID for version string
MAX_VERSION_LENGTH=128                 # Maximum version string length

# Get MTD device path by partition name
get_mtd_device() {
	local partition_name="$1"
	local device_path

	if [ ! -f "/proc/mtd" ]; then
		return 1
	fi

	# Parse /proc/mtd and find matching partition
	# Format: mtdX: size erasesize "name"
	device_path=$(awk -v name="$partition_name" '
	NR > 1 {
	# Extract device number
	dev_num = $1
	sub(/:$/, "", dev_num)
	sub(/^mtd/, "", dev_num)

			# Extract partition name (everything after 3rd field, removing quotes)
			part_name = ""
			for (i = 4; i <= NF; i++) {
				if (i > 4) part_name = part_name " "
					part_name = part_name $i
				}
				gsub(/^"|"$/, "", part_name)

				if (part_name == name) {
					print "/dev/mtd" dev_num
					exit
				}
			}
			' /proc/mtd)

			echo "$device_path"
		}

# Auto-detect platform type from device tree
detect_platform() {
	if [ -f "/proc/device-tree/family" ]; then
		family=$(cat /proc/device-tree/family 2>/dev/null | tr -d '\0' | tr 'A-Z' 'a-z' | tr '-' '_')
		if echo "$family" | grep -q "versal_2ve_2vm"; then
			echo "versal_2ve_2vm"
			return
		fi
	fi
	echo "default"
}

# Extract version string from bootgen optional data fields
extract_bootgen_version() {
	local device="$1"
	local platform
	local iht_offset_addr
	local iht_bytes
	local iht_offset
	local opt_data_offset
	local opt_data_file
	local offset
	local data_id
	local length_words
	local length_bytes
	local version_start
	local version_end
	local version_str

	# Auto-detect platform
	platform=$(detect_platform)

	# Select IHT offset based on platform
	if [ "$platform" = "versal_2ve_2vm" ]; then
		iht_offset_addr=$IHT_OFFSET_VERSAL_2VE_2VM
	else
		iht_offset_addr=$IHT_OFFSET_DEFAULT
	fi

	# Step 1: Read IHT offset (4 bytes, little-endian)
	iht_bytes=$(dd if="$device" bs=1 skip="$iht_offset_addr" count=4 2>/dev/null | hexdump -v -e '1/4 "%u\n"')
	if [ -z "$iht_bytes" ]; then
		return 1
	fi
	iht_offset=$iht_bytes

	# Step 2: Calculate optional data offset (IHT offset + 0x80)
	opt_data_offset=$((iht_offset + XIH_IHT_LEN))

	# Step 3: Read optional data section (read up to 2KB)
	opt_data_file=$(mktemp)
	if ! dd if="$device" bs=1 skip="$opt_data_offset" count=2048 of="$opt_data_file" 2>/dev/null; then
		rm -f "$opt_data_file"
		return 1
	fi

	# Step 4: Search for optional data ID 0x21 (version string)
	offset=0
	while [ $offset -lt 2044 ]; do
		# Read optional data header (4 bytes: 2-byte ID + 2-byte length)
		data_id=$(dd if="$opt_data_file" bs=1 skip=$offset count=2 2>/dev/null | hexdump -v -e '1/2 "%u\n"')
		length_words=$(dd if="$opt_data_file" bs=1 skip=$((offset + 2)) count=2 2>/dev/null | hexdump -v -e '1/2 "%u\n"')

		if [ -z "$data_id" ] || [ -z "$length_words" ]; then
			break
		fi

		length_bytes=$((length_words * 4))

		# Sanity check - length includes the 4-byte header
		if [ $length_bytes -lt 4 ] || [ $length_bytes -gt 2048 ]; then
			break
		fi

		# Check if this is the version string entry
		if [ "$data_id" -eq "$OPT_DATA_ID_VERSION" ]; then
			# Version string starts 4 bytes after header
			version_start=$((offset + 4))
			version_end=$((version_start + MAX_VERSION_LENGTH))

			if [ $version_end -gt 2048 ]; then
				version_end=2048
			fi

			if [ $((version_end - version_start)) -gt $((length_bytes - 4)) ]; then
				version_end=$((version_start + length_bytes - 4))
			fi

			# Extract version string
			version_str=$(dd if="$opt_data_file" bs=1 skip=$version_start count=$((version_end - version_start)) 2>/dev/null | \
				strings | awk 'NR==1 {print; exit}')

			if [ -n "$version_str" ]; then
				echo "$version_str"
				return 0
			else
				return 1
			fi
			fi

		# Move to next optional data entry
		offset=$((offset + length_bytes))
	done

	rm -f "$opt_data_file"
	return 1
}

# Get version information from MTD device
get_version() {
	local type="$1"
	local label
	local device
	local partition_name
	local version

	# Determine device and label based on type
	case "$type" in
		recovery)
			partition_name="Image Recovery"
			label="Image Recovery Application"
			;;
		selector)
			partition_name="Image Selector"
			label="Image Selector Application"
			;;
		bank-a)
			partition_name="Bank A Space"
			label="Bank A image ver"
			;;
		bank-b)
			partition_name="Bank B Space"
			label="Bank B image ver"
			;;
		*)
			echo "Error: Unknown version type"
			return 1
			;;
	esac

	# Dynamically lookup MTD device by partition name
	device=$(get_mtd_device "$partition_name")

	if [ -z "$device" ]; then
		echo "$label: Not Available (partition '$partition_name' not found in /proc/mtd)"
		return 1
	fi

	if [ ! -e "$device" ]; then
		echo "$label: Not Available (device node $device does not exist)"
		return 1
	fi

	# Extract version from bootgen optional data
	version=$(extract_bootgen_version "$device")

	if [ -n "$version" ]; then
		echo "$label: $version"
		return 0
	else
		echo "$label: No version information found"
		return 1
	fi
}

# Main execution
# Output HTTP header for plain text
echo "Content-type: text/plain"
echo ""

# Output version information in plain text format
get_version recovery
get_version selector
get_version bank-a
get_version bank-b

exit 0