#!/bin/sh
# Copyright (c) 2025 - 2026 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

echo "Content-type: text/html"
echo ""
echo "<html><body><pre>"

CGIBASHOPTS_DIR="${PWD}"
CGIBASHOPTS_TMP="${CGIBASHOPTS_DIR}.tmp"
USB_MAIN_PATH_FILE="$CGIBASHOPTS_DIR/usb_wic_main_path.txt"
USB_BMAP_PATH_FILE="$CGIBASHOPTS_DIR/usb_wic_bmap_path.txt"
SCRIPT_DIR="$(dirname "$0")"

# Initialize logging variables
FINAL_STATUS=""
FINAL_MESSAGE=""
LOGGING_ENABLED=0

# Source logging utility
if [ -f "$SCRIPT_DIR/flash_logger.sh" ]; then
	. "$SCRIPT_DIR/flash_logger.sh"
fi

# Only set trap to clean up temp file, not uploaded files
trap 'rm -f "$CGIBASHOPTS_TMP"; [ "$LOGGING_ENABLED" = "1" ] && log_finalize "$FINAL_STATUS" "$FINAL_MESSAGE"' EXIT

if [ "${REQUEST_METHOD:-}" = "POST" ]; then
	# Get custom headers from HTTP request
	upload_type="${HTTP_X_UPLOAD_TYPE:-}"
	filename="${HTTP_X_FILENAME:-}"
	target_device="${HTTP_X_TARGET_DEVICE:-}"

	# Initialize variables
	main_file=""
	bmap_file=""

	# Handle different upload types
	if [ "$upload_type" = "main" ]; then
		# Initialize logging for upload
		CURRENT_LOG_FILE=$(log_init "wic" "ethernet")
		if [ -n "$CURRENT_LOG_FILE" ] && [ -w "$CURRENT_LOG_FILE" ]; then
			LOGGING_ENABLED=1
		fi
		log_banner "ETHERNET RECOVERY - WIC MAIN FILE UPLOAD"
		log_info "=== WIC Main File Upload Started ==="
		log_info "Filename: $filename"
		# Save main file (Ethernet upload)
		saved_file="$CGIBASHOPTS_DIR/$filename"
		log_info "Receiving WIC file via HTTP POST"
		log_info "Target path: $saved_file"

		if cat > "$saved_file"; then
			log_success "WIC main file uploaded successfully"
			FINAL_STATUS="SUCCESS"
			FINAL_MESSAGE="WIC file uploaded: $filename"
			echo "UPLOAD_STATUS=SUCCESS"
		else
			log_error "Failed to save WIC file"
			FINAL_STATUS="FAIL"
			FINAL_MESSAGE="WIC upload failed"
			echo "UPLOAD_STATUS=FAIL"
		fi
		echo "</pre></body></html>"
		exit 0
	elif [ "$upload_type" = "bmap" ]; then
		# Initialize logging for bmap upload
		CURRENT_LOG_FILE=$(log_init "wic" "ethernet" "preserve")
		if [ -n "$CURRENT_LOG_FILE" ] && [ -w "$CURRENT_LOG_FILE" ]; then
			LOGGING_ENABLED=1
		fi
		log_banner "ETHERNET RECOVERY - WIC BMAP FILE UPLOAD"
		log_info "=== WIC BMAP File Upload Started ==="
		log_info "Filename: $filename"
		# Save bmap file (Ethernet upload)
		saved_file="$CGIBASHOPTS_DIR/$filename"
		log_info "Receiving BMAP file via HTTP POST"
		log_info "Target path: $saved_file"
		if cat > "$saved_file"; then
			log_success "BMAP file uploaded successfully"
			FINAL_STATUS="SUCCESS"
			FINAL_MESSAGE="BMAP file uploaded: $filename"
			echo "UPLOAD_STATUS=SUCCESS"
		else
			log_error "Failed to save BMAP file"
			FINAL_STATUS="FAIL"
			FINAL_MESSAGE="BMAP upload failed"
			echo "UPLOAD_STATUS=FAIL"
		fi
		echo "</pre></body></html>"
		exit 0
	elif [ "$upload_type" = "usb-paths" ]; then
		# Initialize logging for USB selection
		CURRENT_LOG_FILE=$(log_init "wic" "usb")
		if [ -n "$CURRENT_LOG_FILE" ] && [ -w "$CURRENT_LOG_FILE" ]; then
			LOGGING_ENABLED=1
		fi
		log_banner "USB RECOVERY - WIC FILE SELECTION"
		log_info "=== USB WIC File Selection ==="
		# Read USB file paths
		read -r main_file
		main_file="${main_file%$'\r'}"  # Remove trailing CR
		read -r bmap_file
		bmap_file="${bmap_file%$'\r'}"  # Remove trailing CR
		log_info "Selected WIC file: $main_file"
		log_info "Selected BMAP file: $bmap_file"

		if [ ! -f "$main_file" ]; then
			log_error "USB WIC file not found: $main_file"
			FINAL_STATUS="FAIL"
			FINAL_MESSAGE="USB file not found"
			echo "FLASH_STATUS=FAIL"
			echo "FLASH_REASON=USB file not found: $main_file"
			echo "</pre></body></html>"
			exit 1
		fi
		if [ -n "$bmap_file" ] && [ ! -f "$bmap_file" ]; then
			log_error "USB BMAP file not found: $bmap_file"
			FINAL_STATUS="FAIL"
			FINAL_MESSAGE="USB BMAP file not found"
			echo "FLASH_STATUS=FAIL"
			echo "FLASH_REASON=USB BMAP file not found: $bmap_file"
			echo "</pre></body></html>"
			exit 1
		fi
		# Save USB paths for later flash operation
		echo "$main_file" > "$USB_MAIN_PATH_FILE"
		if [ -n "$bmap_file" ]; then
			echo "$bmap_file" > "$USB_BMAP_PATH_FILE"
		else
			rm -f "$USB_BMAP_PATH_FILE"
		fi
		log_success "USB files validated and paths saved"
		FINAL_STATUS="SUCCESS"
		FINAL_MESSAGE="USB files selected"
		echo "USB_PATHS_SAVED=SUCCESS"
		echo "</pre></body></html>"
		exit 0
	elif [ "$upload_type" = "flash" ]; then
		# Get exact filenames from headers
		main_filename="${HTTP_X_MAIN_FILENAME:-}"
		bmap_filename="${HTTP_X_BMAP_FILENAME:-}"
		# Determine recovery type (ethernet or usb)
		if [ -n "$main_filename" ]; then
			recovery_type="ethernet"
		elif [ -f "$USB_MAIN_PATH_FILE" ]; then
			recovery_type="usb"
		else
			recovery_type="unknown"
		fi
		# Initialize logging for flash operation (preserve recent upload log)
		CURRENT_LOG_FILE=$(log_init "wic" "$recovery_type" "preserve")
		if [ -n "$CURRENT_LOG_FILE" ] && [ -w "$CURRENT_LOG_FILE" ]; then
			LOGGING_ENABLED=1
		fi
		log_banner "WIC IMAGE FLASH OPERATION"
		log_info "=== WIC Image Flash Operation Started ==="
		log_info "Main filename: $main_filename"
		log_info "BMAP filename: $bmap_filename"
		log_info "Target device: $target_device"
		echo "FLASH_PROGRESS=10"
		log_progress "Flash initialized (10%)"

		# Construct full paths
		if [ -n "$main_filename" ]; then
			# Ethernet upload - use uploaded file
			main_file="$CGIBASHOPTS_DIR/$main_filename"
			log_info "Using Ethernet uploaded WIC file: $main_file"
			if [ -n "$bmap_filename" ]; then
				bmap_file="$CGIBASHOPTS_DIR/$bmap_filename"
				log_info "Using Ethernet uploaded BMAP: $bmap_file"
			fi
			# Clean up uploaded files after flashing (success or failure)
			trap 'rm -f "$CGIBASHOPTS_TMP" "$main_file" "$bmap_file" "$USB_MAIN_PATH_FILE" "$USB_BMAP_PATH_FILE"; [ "$LOGGING_ENABLED" = "1" ] && log_finalize "$FINAL_STATUS" "$FINAL_MESSAGE"' EXIT
		elif [ -f "$USB_MAIN_PATH_FILE" ]; then
			# USB upload - read saved paths
			main_file=$(cat "$USB_MAIN_PATH_FILE")
			main_file="${main_file%$'\r'}"  # Remove trailing CR if present
			log_info "Using USB WIC file: $main_file"
			# Validate USB main file still exists
			if [ ! -f "$main_file" ]; then
				log_error "USB file not found: $main_file"
				FINAL_STATUS="FAIL"
				FINAL_MESSAGE="USB file not found"
				echo "FLASH_STATUS=FAIL"
				echo "FLASH_REASON=USB file not found: $main_file"
				echo "</pre></body></html>"
				exit 1
			fi
			# Check for bmap file
			if [ -f "$USB_BMAP_PATH_FILE" ]; then
				bmap_file=$(cat "$USB_BMAP_PATH_FILE")
				bmap_file="${bmap_file%$'\r'}"  # Remove trailing CR if present
				log_info "Using USB BMAP file: $bmap_file"
				# Validate USB bmap file still exists
				if [ ! -f "$bmap_file" ]; then
					log_error "USB BMAP file not found: $bmap_file"
					FINAL_STATUS="FAIL"
					FINAL_MESSAGE="USB BMAP file not found"
					echo "FLASH_STATUS=FAIL"
					echo "FLASH_REASON=USB BMAP file not found: $bmap_file"
					echo "</pre></body></html>"
					exit 1
				fi
			fi
			# Clean up only temp files and path files, not USB files
			trap 'rm -f "$CGIBASHOPTS_TMP" "$USB_MAIN_PATH_FILE" "$USB_BMAP_PATH_FILE"; [ "$LOGGING_ENABLED" = "1" ] && log_finalize "$FINAL_STATUS" "$FINAL_MESSAGE"' EXIT
		fi
	fi

	# Flash WIC image to storage device
	if [ -n "$main_file" ]; then
		extension="${main_file##*.}"
		filename="${main_file%.*}"
		log_info "File extension: $extension"
		echo "FLASH_PROGRESS=20"
		log_progress "File validated (20%)"

		# Validate target device is provided
		if [ -z "$target_device" ]; then
			log_error "No storage device selected"
			FINAL_STATUS="FAIL"
			FINAL_MESSAGE="No storage device selected"
			echo "FLASH_STATUS=FAIL"
			echo "FLASH_REASON=No storage device selected. Please select a target device."
			echo "</pre></body></html>"
			exit 1
		fi

		# Validate target device exists and is a block device
		if [ ! -b "$target_device" ]; then
			log_error "Invalid storage device: $target_device"
			FINAL_STATUS="FAIL"
			FINAL_MESSAGE="Invalid storage device"
			echo "FLASH_STATUS=FAIL"
			echo "FLASH_REASON=Invalid storage device: $target_device"
			echo "</pre></body></html>"
			exit 1
		fi

		real_dev="$target_device"
		log_info "Target device validated: $real_dev"
		echo "FLASH_INFO=Target device: $real_dev"
		echo "FLASH_PROGRESS=30"
		log_progress "Device validated (30%)"

		# Unmount all partitions on the target device before flashing
		echo "FLASH_INFO=Unmounting device partitions..."
		log_info "Unmounting all partitions on $real_dev"
		for partition in "${real_dev}"*; do
			if mountpoint -q "$partition" 2>/dev/null || grep -q "^$partition " /proc/mounts 2>/dev/null; then
				log_info "Unmounting partition: $partition"
				umount "$partition" 2>/dev/null || umount -l "$partition" 2>/dev/null
			fi
		done
		# Also try to unmount the main device itself
		if mountpoint -q "$real_dev" 2>/dev/null || grep -q "^$real_dev " /proc/mounts 2>/dev/null; then
			log_info "Unmounting main device: $real_dev"
			umount "$real_dev" 2>/dev/null || umount -l "$real_dev" 2>/dev/null
		fi
		log_success "Partitions unmounted"
		echo "FLASH_PROGRESS=40"
		log_progress "Partitions unmounted (40%)"

		# Determine bmap file to use (uploaded or in directory)
		bmap_to_use=""
		if [ -n "$bmap_file" ] && [ -f "$bmap_file" ]; then
			bmap_to_use="$bmap_file"
			log_info "Using uploaded BMAP file: $bmap_to_use"
		elif [ "$extension" = "xz" ] && [ -f "$filename.bmap" ]; then
			bmap_to_use="$filename.bmap"
			log_info "Using auto-detected BMAP file: $bmap_to_use"
		elif [ "$extension" = "wic" ] && [ -f "$filename.wic.bmap" ]; then
			bmap_to_use="$filename.wic.bmap"
			log_info "Using auto-detected BMAP file: $bmap_to_use"
		else
			log_info "No BMAP file available, using direct write"
		fi
		echo "FLASH_PROGRESS=50"
		log_progress "Flash method determined (50%)"

		# Flash based on file extension
		flash_failed=0
		if [ "$extension" = "xz" ]; then
			if [ -n "$bmap_to_use" ]; then
				log_info "Flashing .xz image with BMAP acceleration"
				log_info "Command: xzcat '$main_file' | bmap-writer - '$bmap_to_use' '$real_dev'"
				if [ -n "$CURRENT_LOG_FILE" ] && [ -w "$CURRENT_LOG_FILE" ]; then
					xzcat "$main_file" | bmap-writer - "$bmap_to_use" "$real_dev" >>"$CURRENT_LOG_FILE" 2>&1 || flash_failed=1
				else
					xzcat "$main_file" | bmap-writer - "$bmap_to_use" "$real_dev" >/dev/null 2>&1 || flash_failed=1
				fi
				if [ "$flash_failed" = "1" ]; then
					log_error "Failed to flash compressed image with bmap"
					FINAL_STATUS="FAIL"
					FINAL_MESSAGE="Failed to flash compressed image with bmap"
					echo "FLASH_STATUS=FAIL"
					echo "FLASH_REASON=Failed to flash compressed image with bmap"
					echo "</pre></body></html>"
					exit 1
				fi
			else
				log_info "Flashing .xz image with direct write (no BMAP)"
				log_info "Command: xzcat '$main_file' | dd of='$real_dev' bs=32M"
				if [ -n "$CURRENT_LOG_FILE" ] && [ -w "$CURRENT_LOG_FILE" ]; then
					xzcat "$main_file" | dd of="$real_dev" bs=32M >>"$CURRENT_LOG_FILE" 2>&1 || flash_failed=1
				else
					xzcat "$main_file" | dd of="$real_dev" bs=32M >/dev/null 2>&1 || flash_failed=1
				fi
				if [ "$flash_failed" = "1" ]; then
					log_error "Failed to flash compressed image"
					FINAL_STATUS="FAIL"
					FINAL_MESSAGE="Failed to flash compressed image"
					echo "FLASH_STATUS=FAIL"
					echo "FLASH_REASON=Failed to flash compressed image"
					echo "</pre></body></html>"
					exit 1
				fi
			fi
		elif [ "$extension" = "wic" ]; then
			if [ -n "$bmap_to_use" ]; then
				log_info "Flashing .wic image with BMAP acceleration"
				log_info "Command: bmap-writer '$main_file' '$real_dev' '$bmap_to_use'"
				if [ -n "$CURRENT_LOG_FILE" ] && [ -w "$CURRENT_LOG_FILE" ]; then
					bmap-writer "$main_file" "$real_dev" "$bmap_to_use" >>"$CURRENT_LOG_FILE" 2>&1 || flash_failed=1
				else
					bmap-writer "$main_file" "$real_dev" "$bmap_to_use" >/dev/null 2>&1 || flash_failed=1
				fi
				if [ "$flash_failed" = "1" ]; then
					log_error "Failed to flash WIC image with bmap"
					FINAL_STATUS="FAIL"
					FINAL_MESSAGE="Failed to flash WIC image with bmap"
					echo "FLASH_STATUS=FAIL"
					echo "FLASH_REASON=Failed to flash WIC image with bmap"
					echo "</pre></body></html>"
					exit 1
				fi
			else
				log_info "Flashing .wic image with direct write (no BMAP)"
				log_info "Command: dd if='$main_file' of='$real_dev' bs=32M"
				if [ -n "$CURRENT_LOG_FILE" ] && [ -w "$CURRENT_LOG_FILE" ]; then
					dd if="$main_file" of="$real_dev" bs=32M >>"$CURRENT_LOG_FILE" 2>&1 || flash_failed=1
				else
					dd if="$main_file" of="$real_dev" bs=32M >/dev/null 2>&1 || flash_failed=1
				fi
				if [ "$flash_failed" = "1" ]; then
					log_error "Failed to flash WIC image"
					FINAL_STATUS="FAIL"
					FINAL_MESSAGE="Failed to flash WIC image"
					echo "FLASH_STATUS=FAIL"
					echo "FLASH_REASON=Failed to flash WIC image"
					echo "</pre></body></html>"
					exit 1
				fi
			fi
		else
			log_error "Unsupported file format: .$extension"
			FINAL_STATUS="FAIL"
			FINAL_MESSAGE="Unsupported file format: .$extension"
			echo "FLASH_STATUS=FAIL"
			echo "FLASH_REASON=Unsupported file format: .$extension (only .xz and .wic are supported)"
			echo "</pre></body></html>"
			exit 1
		fi
		# flash_end=$(date +%s)
		# flash_duration=$((flash_end - flash_start))
		log_success "Image flashed successfully"
		echo "FLASH_PROGRESS=95"
		log_progress "Image flashed (95%)"

		echo "FLASH_PROGRESS=98"
		log_progress "Updating U-Boot environment (98%)"
		if fw_printenv >/dev/null 2>&1; then
			log_info "Updating U-Boot environment variables"
			fw_setenv BOOT_ORDER "A B"
			fw_setenv BOOT_A_LEFT 3
			log_success "U-Boot environment updated"
		else
			log_warn "fw_printenv not available, skipping U-Boot update"
		fi
		log_success "WIC image flashed successfully to $real_dev"
		FINAL_STATUS="SUCCESS"
		FINAL_MESSAGE="WIC image flashed successfully to $real_dev"
		log_info "Final status set: $FINAL_STATUS"
		log_info "Final message set: $FINAL_MESSAGE"
		echo "FLASH_STATUS=SUCCESS"
		echo "FLASH_REASON=WIC image flashed successfully to $real_dev"
		echo "FLASH_LOG=$CURRENT_LOG_FILE"
		echo "FLASH_PROGRESS=100"
	else
		log_error "No main file provided for flashing"
		FINAL_STATUS="FAIL"
		FINAL_MESSAGE="No main file provided"
		echo "FLASH_STATUS=FAIL"
		echo "FLASH_REASON=No main file provided"
		echo "FLASH_LOG=$CURRENT_LOG_FILE"
	fi
else
	echo "FLASH_STATUS=IDLE"
	echo "FLASH_REASON=No POST request received"
fi

echo "</pre></body></html>"
exit 0
