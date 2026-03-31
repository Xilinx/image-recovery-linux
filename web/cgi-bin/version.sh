#!/bin/sh
# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

# CGI helper that surfaces version information for:
# - Image Recovery Application
# - Image Selector Application
# - Active bank image

# To get version information from MTD devices
# Usage: get_version <type> [label]
get_version() {
	local type="$1"
	local label="$2"
	local device
	local ver
	local tmp_file
	local bank
	local bs_size

	case "$type" in
		recovery)
			device="/dev/mtd4"
			label="${label:-Image Recovery Application}"
			;;
		selector)
			device="/dev/mtd1"
			label="${label:-Image Selector Application}"
			;;
		active-bank)
			# Read active bank index from metadata
			if [ ! -e "/dev/mtd6" ]; then
				echo "Active bank image ver: Not Available"
				return 1
			fi

			tmp_file=$(mktemp)
			if ! dd if=/dev/mtd6 of="$tmp_file" bs=1 skip=8 count=4 2>/dev/null; then
				rm -f "$tmp_file"
				echo "Active bank image ver: Not Available"
				return 1
			fi

			bank=$(hexdump -s 0 -n4 -e '"%x"' "$tmp_file" 2>/dev/null)
			rm -f "$tmp_file"

			if [ -z "$bank" ]; then
				echo "Active bank image ver: Not Available"
				return 1
			fi

			if ! echo "$bank" | grep -qE '^[0-9a-fA-F]+$'; then
				echo "Active bank image ver: Not Available"
				return 1
			fi

			case "$((0x$bank))" in
				0) device="/dev/mtd10" ;;
				1) device="/dev/mtd13" ;;
				*)
					echo "Active bank image ver: Not Available"
					return 1
					;;
			esac

			label="Active bank image ver"
			;;
		*)
			echo "Error: Unknown version type"
			return 1
			;;
	esac

	if [ ! -e "$device" ]; then
		echo "$label: Not Available"
		return 1
	fi

	tmp_file=$(mktemp)
	if [ $? -ne 0 ]; then
		echo "$label: Not Available"
		return 1
	fi

	if [ "$type" = "active-bank" ]; then
		bs_size="1M"
	else
		bs_size="512k"
	fi

	if ! dd if="$device" of="$tmp_file" bs="$bs_size" count=1 2>/dev/null; then
		rm -f "$tmp_file"
		echo "$label: Not Available"
		return 1
	fi

	# Extract version: try bootfw pattern first for active-bank
	if [ "$type" = "active-bank" ]; then
		ver=$(strings "$tmp_file" | grep -E "amd-edf-.*-bootfw-v[0-9]" 2>/dev/null | head -n1)
	fi

	# Try Version= pattern
	if [ -z "$ver" ]; then
		ver=$(strings "$tmp_file" | grep -m1 'Version=' 2>/dev/null | sed 's/^[^;]*;//' | sed 's/Version=//; s/;/ /g; s/SW_CRC/CRC/')
	fi

	# Try simple version pattern (not for active-bank)
	if [ -z "$ver" ] && [ "$type" != "active-bank" ]; then
		ver=$(strings "$tmp_file" | grep -E '^[0-9]+\.[0-9]+(\+git)?$' 2>/dev/null | head -n1 | sed 's/+git$//')
	fi

	rm -f "$tmp_file"

	if [ -n "$ver" ]; then
		echo "$label: $ver"
		return 0
	else
		echo "$label: Not Available"
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
get_version active-bank

exit 0
