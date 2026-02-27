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

# Initialize logging variables
FINAL_STATUS=""
FINAL_MESSAGE=""
LOGGING_ENABLED=0

# Source logging utility
if [ -f "$SCRIPT_DIR/flash_logger.sh" ]; then
	. "$SCRIPT_DIR/flash_logger.sh"
fi

# Only set trap to clean up temp file and metadata, not uploaded files initially
trap 'rm -f "$CGIBASHOPTS_TMP" "$METADATA_FILE"; [ "$LOGGING_ENABLED" = "1" ] && log_finalize "$FINAL_STATUS" "$FINAL_MESSAGE"' EXIT

if [ "${REQUEST_METHOD:-}" = "POST" ]; then
	# Get custom headers from HTTP request
	upload_type="${HTTP_X_UPLOAD_TYPE:-}"
	filename="${HTTP_X_FILENAME:-}"

	# Initialize variables
	file_path=""

	# Handle different upload types
	if [ "$upload_type" = "main" ]; then
		# Initialize logging for upload
		CURRENT_LOG_FILE=$(log_init "boot" "ethernet")
		if [ -n "$CURRENT_LOG_FILE" ] && [ -w "$CURRENT_LOG_FILE" ]; then
			LOGGING_ENABLED=1
		fi
		log_banner "ETHERNET RECOVERY - BOOT FILE UPLOAD"
		log_info "=== Boot File Upload Started ==="
		log_info "Filename: $filename"

		# Save boot file (Ethernet upload)
		saved_file="$CGIBASHOPTS_DIR/$filename"
		log_info "Receiving file via HTTP POST"
		log_info "Target path: $saved_file"

		if cat > "$saved_file"; then
			log_success "Boot file uploaded successfully"
			FINAL_STATUS="SUCCESS"
			FINAL_MESSAGE="Boot file uploaded: $filename"
			echo "UPLOAD_STATUS=SUCCESS"
		else
			log_error "Failed to save uploaded file"
			FINAL_STATUS="FAIL"
			FINAL_MESSAGE="Upload failed"
			echo "UPLOAD_STATUS=FAIL"
		fi
		echo "</pre></body></html>"
		exit 0
	elif [ "$upload_type" = "usb-path" ]; then
		# Initialize logging for USB selection
		CURRENT_LOG_FILE=$(log_init "boot" "usb")
		if [ -n "$CURRENT_LOG_FILE" ] && [ -w "$CURRENT_LOG_FILE" ]; then
			LOGGING_ENABLED=1
		fi
		log_banner "USB RECOVERY - BOOT FILE SELECTION"
		log_info "=== USB Boot File Selection ==="

		# Read USB file path
		read -r file_path
		file_path="${file_path%$'\r'}"  # Remove trailing CR
		log_info "Selected USB file: $file_path"

		if [ ! -f "$file_path" ]; then
			log_error "USB file not found: $file_path"
			FINAL_STATUS="FAIL"
			FINAL_MESSAGE="USB file not found"
			echo "FLASH_STATUS=FAIL"
			echo "FLASH_REASON=USB file not found: $file_path"
			echo "</pre></body></html>"
			exit 1
		fi

		# Save USB path for later flash operation
		echo "$file_path" > "$USB_PATH_FILE"
		log_success "USB file validated and path saved"
		FINAL_STATUS="SUCCESS"
		FINAL_MESSAGE="USB file selected: $file_path"
		echo "USB_PATH_SAVED=SUCCESS"
		echo "</pre></body></html>"
		exit 0
	elif [ "$upload_type" = "flash" ]; then
		# Get exact filename from headers
		boot_filename="${HTTP_X_BOOT_FILENAME:-}"
		# Determine recovery type (ethernet or usb)
		if [ -n "$boot_filename" ]; then
			recovery_type="ethernet"
		elif [ -f "$USB_PATH_FILE" ]; then
			recovery_type="usb"
		else
			recovery_type="unknown"
		fi
		# Initialize logging for flash operation (preserve recent upload log)
		CURRENT_LOG_FILE=$(log_init "boot" "$recovery_type" "preserve")
		if [ -n "$CURRENT_LOG_FILE" ] && [ -w "$CURRENT_LOG_FILE" ]; then
			LOGGING_ENABLED=1
		fi
		log_banner "BOOT IMAGE FLASH OPERATION"
		log_info "=== Boot Image Flash Operation Started ==="
		log_info "Boot filename from header: $boot_filename"

		# Construct full path
		if [ -n "$boot_filename" ]; then
			# Ethernet upload - use uploaded file
			file_path="$CGIBASHOPTS_DIR/$boot_filename"
			log_info "Using Ethernet uploaded file: $file_path"
			# Clean up uploaded files after flashing
			trap 'rm -f "$CGIBASHOPTS_TMP" "$METADATA_FILE" "$file_path" "$USB_PATH_FILE"; [ "$LOGGING_ENABLED" = "1" ] && log_finalize "$FINAL_STATUS" "$FINAL_MESSAGE"' EXIT
		elif [ -f "$USB_PATH_FILE" ]; then
			# USB upload - read saved path
			file_path=$(cat "$USB_PATH_FILE")
			file_path="${file_path%$'\r'}"  # Remove trailing CR if present
			log_info "Using USB file: $file_path"
			# Validate USB file still exists
			if [ ! -f "$file_path" ]; then
				log_error "USB file not found: $file_path"
				FINAL_STATUS="FAIL"
				FINAL_MESSAGE="USB file not found: $file_path"
				echo "FLASH_STATUS=FAIL"
				echo "FLASH_REASON=USB file not found: $file_path"
				echo "</pre></body></html>"
				exit 1
			fi
			# Clean up only temp files, not USB file
			trap 'rm -f "$CGIBASHOPTS_TMP" "$METADATA_FILE" "$USB_PATH_FILE"; [ "$LOGGING_ENABLED" = "1" ] && log_finalize "$FINAL_STATUS" "$FINAL_MESSAGE"' EXIT
		fi
	fi

	# Read current active bank from metadata
	log_info "Reading metadata from /dev/mtd5"
	if ! cat /dev/mtd5 > "$METADATA_FILE" 2>/dev/null; then
		log_error "Failed to read MTD device /dev/mtd5"
		FINAL_STATUS="FAIL"
		FINAL_MESSAGE="Failed to read MTD device"
		echo "FLASH_STATUS=FAIL"
		echo "FLASH_REASON=Failed to read MTD device"
		echo "</pre></body></html>"
		exit 1
	fi

	active_bank=$(hexdump -s 0x8 -n4 -e '"%x"' "$METADATA_FILE")
	log_info "Current active bank: $active_bank"

	# Flash boot image
	log_info "Starting flash operation - File: $file_path"
	# Determine flash target based on active bank
	if [ "$active_bank" = "0" ]; then
		target_mtd="/dev/mtd12"
		target_name="IMAGE B"
		new_active="\x01"
		new_prev="\x00"
		seek_pos=25
		log_info "Flashing to inactive bank B (will become active)"
	else
		target_mtd="/dev/mtd9"
		target_name="IMAGE A"
		new_active="\x00"
		new_prev="\x01"
		seek_pos=24
		log_info "Flashing to inactive bank A (will become active)"
	fi
	log_info "Target MTD: $target_mtd, Target name: $target_name"
	echo "Flashing $target_name"

	# Erase and flash boot image with progress tracking
	flash_failed=0
	echo "FLASH_PROGRESS=60"
	log_progress "Erasing flash (60%)"
	log_info "Erasing $target_mtd"
	if ! flash_eraseall "$target_mtd"; then
		log_error "Failed to erase $target_mtd"
		FINAL_STATUS="FAIL"
		FINAL_MESSAGE="Failed to erase $target_mtd"
		echo "FLASH_STATUS=FAIL"
		echo "FLASH_REASON=Failed to erase $target_mtd"
		echo "</pre></body></html>"
		exit 1
	fi
	log_success "Flash erased successfully"

	echo "FLASH_PROGRESS=70"
	log_progress "Writing image (70%)"
	# Flash the image
	log_info "Writing image to $target_mtd using flashcp"
	# Log output if logging is enabled, show errors to user
	if [ -n "$CURRENT_LOG_FILE" ] && [ -w "$CURRENT_LOG_FILE" ]; then
		flashcp "$file_path" "$target_mtd" 2>&1 | tee -a "$CURRENT_LOG_FILE" >&2 || flash_failed=1
	else
		flashcp "$file_path" "$target_mtd" 2>&1 || flash_failed=1
	fi
	if [ "$flash_failed" = "1" ]; then
		log_error "Failed to write image to $target_mtd"
		FINAL_STATUS="FAIL"
		FINAL_MESSAGE="Failed to write image to $target_mtd"
		echo "FLASH_STATUS=FAIL"
		echo "FLASH_REASON=Failed to write image to $target_mtd"
		echo "</pre></body></html>"
		exit 1
	fi

	log_success "Image written successfully"
	echo "FLASH_PROGRESS=95"
	log_progress "Updating metadata (95%)"

	# Update metadata
	echo "FLASH_PROGRESS=96"
	log_info "Updating metadata to switch active bank"
	printf '%b' "$new_active" | dd of="$METADATA_FILE" bs=1 seek=8 count=1 conv=notrunc 2>>"$CURRENT_LOG_FILE"
	printf '%b' "$new_prev" | dd of="$METADATA_FILE" bs=1 seek=12 count=1 conv=notrunc 2>>"$CURRENT_LOG_FILE"
	printf "\xfc" | dd of="$METADATA_FILE" bs=1 seek=$seek_pos count=1 conv=notrunc 2>>"$CURRENT_LOG_FILE"
	log_success "Metadata updated successfully"

	# Calculate CRC32 and update flash
	echo "FLASH_PROGRESS=98"
	log_info "Calculating and updating CRC32"
	if [ -x "$SCRIPT_DIR/cal_crc32.sh" ]; then
		if ! "$SCRIPT_DIR/cal_crc32.sh" >>"$CURRENT_LOG_FILE" 2>&1; then
			log_error "Failed to calculate CRC32"
			FINAL_STATUS="FAIL"
			FINAL_MESSAGE="Failed to calculate CRC32"
			echo "FLASH_STATUS=FAIL"
			echo "FLASH_REASON=Failed to calculate CRC32"
			echo "</pre></body></html>"
			exit 1
		fi
		log_success "CRC32 calculated and updated"
	else
		log_error "cal_crc32.sh not found at $SCRIPT_DIR/cal_crc32.sh"
		FINAL_STATUS="FAIL"
		FINAL_MESSAGE="cal_crc32.sh not found"
		echo "FLASH_STATUS=FAIL"
		echo "FLASH_REASON=cal_crc32.sh not found"
		echo "</pre></body></html>"
		exit 1
	fi

	# Extract version string from BOOT.bin
	log_info "Extracting version information"
	version_info=$(strings "$file_path" | grep -m1 'Version=' | head -n1 | sed 's/^[^;]*;//' | sed 's/Version=//; s/;/ /g; s/SW_CRC/CRC/')
	build_date=$(basename "$file_path" | grep -oE '[0-9]{14}' | head -n1)

	echo "FLASH_PROGRESS=100"
	log_progress "Flash complete (100%)"
	log_success "Boot image flashed successfully to $target_name"

	FINAL_STATUS="SUCCESS"
	FINAL_MESSAGE="Boot image flashed successfully to $target_name"
	log_info "Final status set: $FINAL_STATUS"
	log_info "Final message set: $FINAL_MESSAGE"

	echo "FLASH_STATUS=SUCCESS"
	echo "FLASH_REASON=Boot image flashed successfully"
	echo "FLASH_LOG=$CURRENT_LOG_FILE"

	if [ -n "$version_info" ]; then
		echo "FLASH_VERSION=$version_info"
		log_info "Version: $version_info"
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
		log_info "Build Date: $formatted_date"
	fi
else
	echo "FLASH_STATUS=IDLE"
	echo "FLASH_REASON=No POST request received"
fi

echo "</pre></body></html>"
exit 0
