#!/bin/sh
# Copyright (c) 2025 - 2026 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

echo "Content-type: text/html"
echo ""
echo "<html><body><pre>"

CGIBASHOPTS_DIR="${PWD}"
CGIBASHOPTS_TMP="${CGIBASHOPTS_DIR}.tmp"
SCRIPT_DIR="$(dirname "$0")"
METADATA_FILE="sys_mdata.bin"
USB_PATH_FILE="$CGIBASHOPTS_DIR/usb_boot_path.txt"

# Only set trap to clean up temp file and metadata, not uploaded files initially
trap 'rm -f "$CGIBASHOPTS_TMP" "$METADATA_FILE"' EXIT

if [ "${REQUEST_METHOD:-}" = "POST" ]; then
	# Get custom headers from HTTP request
	upload_type="${HTTP_X_UPLOAD_TYPE:-}"
	filename="${HTTP_X_FILENAME:-}"

	# Initialize variables
	file_path=""

	# Handle different upload types
	if [ "$upload_type" = "main" ]; then
		# Save boot file (Ethernet upload)
		saved_file="$CGIBASHOPTS_DIR/$filename"
		cat > "$saved_file"
		echo "UPLOAD_STATUS=SUCCESS"
		echo "</pre></body></html>"
		exit 0
	elif [ "$upload_type" = "usb-path" ]; then
		# Read USB file path
		read -r file_path
		file_path="${file_path%$'\r'}"  # Remove trailing CR

		if [ ! -f "$file_path" ]; then
			echo "FLASH_STATUS=FAIL"
			echo "FLASH_REASON=USB file not found: $file_path"
			echo "</pre></body></html>"
			exit 1
		fi
		# Save USB path for later flash operation
		echo "$file_path" > "$USB_PATH_FILE"
		echo "USB_PATH_SAVED=SUCCESS"
		echo "</pre></body></html>"
		exit 0
	elif [ "$upload_type" = "flash" ]; then
		# Get exact filename from headers
		boot_filename="${HTTP_X_BOOT_FILENAME:-}"
		# Construct full path
		if [ -n "$boot_filename" ]; then
			# Ethernet upload - use uploaded file
			file_path="$CGIBASHOPTS_DIR/$boot_filename"
			# Clean up uploaded files after flashing
			trap 'rm -f "$CGIBASHOPTS_TMP" "$METADATA_FILE" "$file_path" "$USB_PATH_FILE"' EXIT
		elif [ -f "$USB_PATH_FILE" ]; then
			# USB upload - read saved path
			file_path=$(cat "$USB_PATH_FILE")
			file_path="${file_path%$'\r'}"  # Remove trailing CR if present
			# Validate USB file still exists
			if [ ! -f "$file_path" ]; then
				echo "FLASH_STATUS=FAIL"
				echo "FLASH_REASON=USB file not found: $file_path"
				echo "</pre></body></html>"
				exit 1
			fi
			# Clean up only temp files, not USB file
			trap 'rm -f "$CGIBASHOPTS_TMP" "$METADATA_FILE" "$USB_PATH_FILE"' EXIT
		fi
	fi

	# Read current active bank from metadata
	if ! cat /dev/mtd5 > "$METADATA_FILE" 2>/dev/null; then
		echo "FLASH_STATUS=FAIL"
		echo "FLASH_REASON=Failed to read MTD device"
		echo "</pre></body></html>"
		exit 1
	fi

	active_bank=$(hexdump -s 0x8 -n4 -e '"%x"' "$METADATA_FILE")

	# Flash boot image
	if [ -n "$file_path" ]; then
		# Determine flash target based on active bank
		if [ "$active_bank" = "0" ]; then
			target_mtd="/dev/mtd12"
			target_name="IMAGE B"
			new_active="\x01"
			new_prev="\x00"
			seek_pos=25
		else
			target_mtd="/dev/mtd9"
			target_name="IMAGE A"
			new_active="\x00"
			new_prev="\x01"
			seek_pos=24
		fi

		echo "Flashing $target_name"

		# Erase and flash boot image with progress tracking
		echo "FLASH_PROGRESS=60"
		if ! flash_eraseall "$target_mtd" 2>/dev/null; then
			echo "FLASH_STATUS=FAIL"
			echo "FLASH_REASON=Failed to erase $target_mtd"
			echo "</pre></body></html>"
			exit 1
		fi

		echo "FLASH_PROGRESS=70"
		# Flash the image
		if ! flashcp "$file_path" "$target_mtd" 2>/dev/null; then
			echo "FLASH_STATUS=FAIL"
			echo "FLASH_REASON=Failed to write image to $target_mtd"
			echo "</pre></body></html>"
			exit 1
		fi
		echo "FLASH_PROGRESS=95"

		# Update metadata
		echo "FLASH_PROGRESS=96"
		printf '%b' "$new_active" | dd of="$METADATA_FILE" bs=1 seek=8 count=1 conv=notrunc 2>/dev/null
		printf '%b' "$new_prev" | dd of="$METADATA_FILE" bs=1 seek=12 count=1 conv=notrunc 2>/dev/null
		printf "\xfc" | dd of="$METADATA_FILE" bs=1 seek=$seek_pos count=1 conv=notrunc 2>/dev/null

		# Calculate CRC32 and update flash
		echo "FLASH_PROGRESS=98"
		if [ -x "$SCRIPT_DIR/cal_crc32.sh" ]; then
			if ! "$SCRIPT_DIR/cal_crc32.sh"; then
				echo "FLASH_STATUS=FAIL"
				echo "FLASH_REASON=Failed to calculate CRC32"
				echo "</pre></body></html>"
				exit 1
			fi
		else
			echo "FLASH_STATUS=FAIL"
			echo "FLASH_REASON=cal_crc32.sh not found"
			echo "</pre></body></html>"
			exit 1
		fi

		# Extract version string from BOOT.bin
		version_info=$(strings "$file_path" | grep -m1 'Version=' | head -n1 | sed 's/^[^;]*;//' | sed 's/Version=//; s/;/ /g; s/SW_CRC/CRC/')
		build_date=$(basename "$file_path" | grep -oE '[0-9]{14}' | head -n1)

		echo "FLASH_PROGRESS=100"
		echo "FLASH_STATUS=SUCCESS"
		echo "FLASH_REASON=Boot image flashed successfully"

		if [ -n "$version_info" ]; then
			echo "FLASH_VERSION=$version_info"
		fi

		if [ -n "$build_date" ]; then
			year=${build_date:0:4}
			month=${build_date:4:2}
			day=${build_date:6:2}
			hour=${build_date:8:2}
			minute=${build_date:10:2}
			second=${build_date:12:2}

			formatted_date="$year-$month-$day $hour:$minute:$second"
			echo "FLASH_BUILD_DATE=$formatted_date"
		fi
	else
		echo "FLASH_STATUS=FAIL"
		echo "FLASH_REASON=No boot file provided"
	fi
else
	echo "FLASH_STATUS=IDLE"
	echo "FLASH_REASON=No POST request received"
fi

echo "</pre></body></html>"
exit 0
