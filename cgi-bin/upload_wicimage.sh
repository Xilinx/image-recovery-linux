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

# Only set trap to clean up temp file, not uploaded files
trap 'rm -f "$CGIBASHOPTS_TMP"' EXIT

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
		# Save main file (Ethernet upload)
		saved_file="$CGIBASHOPTS_DIR/$filename"
		cat > "$saved_file"
		echo "UPLOAD_STATUS=SUCCESS"
		echo "</pre></body></html>"
		exit 0
	elif [ "$upload_type" = "bmap" ]; then
		# Save bmap file (Ethernet upload)
		saved_file="$CGIBASHOPTS_DIR/$filename"
		cat > "$saved_file"
		echo "UPLOAD_STATUS=SUCCESS"
		echo "</pre></body></html>"
		exit 0
	elif [ "$upload_type" = "usb-paths" ]; then
		# Read USB file paths
		read -r main_file
		main_file="${main_file%$'\r'}"  # Remove trailing CR
		read -r bmap_file
		bmap_file="${bmap_file%$'\r'}"  # Remove trailing CR

		if [ ! -f "$main_file" ]; then
			echo "FLASH_STATUS=FAIL"
			echo "FLASH_REASON=USB file not found: $main_file"
			echo "</pre></body></html>"
			exit 1
		fi
		if [ -n "$bmap_file" ] && [ ! -f "$bmap_file" ]; then
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
		echo "USB_PATHS_SAVED=SUCCESS"
		echo "</pre></body></html>"
		exit 0
	elif [ "$upload_type" = "flash" ]; then
		# Get exact filenames from headers
		main_filename="${HTTP_X_MAIN_FILENAME:-}"
		bmap_filename="${HTTP_X_BMAP_FILENAME:-}"
		echo "FLASH_PROGRESS=10"

		# Construct full paths
		if [ -n "$main_filename" ]; then
			# Ethernet upload - use uploaded file
			main_file="$CGIBASHOPTS_DIR/$main_filename"
			if [ -n "$bmap_filename" ]; then
				bmap_file="$CGIBASHOPTS_DIR/$bmap_filename"
			fi
			# Clean up uploaded files after flashing (success or failure)
			trap 'rm -f "$CGIBASHOPTS_TMP" "$main_file" "$bmap_file" "$USB_MAIN_PATH_FILE" "$USB_BMAP_PATH_FILE"' EXIT
		elif [ -f "$USB_MAIN_PATH_FILE" ]; then
			# USB upload - read saved paths
			main_file=$(cat "$USB_MAIN_PATH_FILE")
			main_file="${main_file%$'\r'}"  # Remove trailing CR if present
			# Validate USB main file still exists
			if [ ! -f "$main_file" ]; then
				echo "FLASH_STATUS=FAIL"
				echo "FLASH_REASON=USB file not found: $main_file"
				echo "</pre></body></html>"
				exit 1
			fi
			# Check for bmap file
			if [ -f "$USB_BMAP_PATH_FILE" ]; then
				bmap_file=$(cat "$USB_BMAP_PATH_FILE")
				bmap_file="${bmap_file%$'\r'}"  # Remove trailing CR if present
				# Validate USB bmap file still exists
				if [ ! -f "$bmap_file" ]; then
					echo "FLASH_STATUS=FAIL"
					echo "FLASH_REASON=USB BMAP file not found: $bmap_file"
					echo "</pre></body></html>"
					exit 1
				fi
			fi
			# Clean up only temp files and path files, not USB files
			trap 'rm -f "$CGIBASHOPTS_TMP" "$USB_MAIN_PATH_FILE" "$USB_BMAP_PATH_FILE"' EXIT
		fi
	fi

	# Flash WIC image to storage device
	if [ -n "$main_file" ]; then
		extension="${main_file##*.}"
		filename="${main_file%.*}"
		echo "FLASH_PROGRESS=20"

		# Validate target device is provided
		if [ -z "$target_device" ]; then
			echo "FLASH_STATUS=FAIL"
			echo "FLASH_REASON=No storage device selected. Please select a target device."
			echo "</pre></body></html>"
			exit 1
		fi

		# Validate target device exists and is a block device
		if [ ! -b "$target_device" ]; then
			echo "FLASH_STATUS=FAIL"
			echo "FLASH_REASON=Invalid storage device: $target_device"
			echo "</pre></body></html>"
			exit 1
		fi

		real_dev="$target_device"
		echo "FLASH_INFO=Target device: $real_dev"
		echo "FLASH_PROGRESS=30"

		# Unmount all partitions on the target device before flashing
		echo "FLASH_INFO=Unmounting device partitions..."
		for partition in "${real_dev}"*; do
			if mountpoint -q "$partition" 2>/dev/null || grep -q "^$partition " /proc/mounts 2>/dev/null; then
				umount "$partition" 2>/dev/null || umount -l "$partition" 2>/dev/null
			fi
		done
		# Also try to unmount the main device itself
		if mountpoint -q "$real_dev" 2>/dev/null || grep -q "^$real_dev " /proc/mounts 2>/dev/null; then
			umount "$real_dev" 2>/dev/null || umount -l "$real_dev" 2>/dev/null
		fi
		echo "FLASH_PROGRESS=40"

		# Determine bmap file to use (uploaded or in directory)
		bmap_to_use=""
		if [ -n "$bmap_file" ] && [ -f "$bmap_file" ]; then
			bmap_to_use="$bmap_file"
		elif [ "$extension" = "xz" ] && [ -f "$filename.bmap" ]; then
			bmap_to_use="$filename.bmap"
		elif [ "$extension" = "wic" ] && [ -f "$filename.wic.bmap" ]; then
			bmap_to_use="$filename.wic.bmap"
		fi
		echo "FLASH_PROGRESS=50"

		# Flash based on file extension
		if [ "$extension" = "xz" ]; then
			if [ -n "$bmap_to_use" ]; then
				xzcat "$main_file" | bmap-writer - "$bmap_to_use" "$real_dev" 2>/dev/null || {
					echo "FLASH_STATUS=FAIL"
					echo "FLASH_REASON=Failed to flash compressed image with bmap"
					echo "</pre></body></html>"
					exit 1
				}
			else
				xzcat "$main_file" | dd of="$real_dev" bs=32M 2>/dev/null || {
					echo "FLASH_STATUS=FAIL"
					echo "FLASH_REASON=Failed to flash compressed image"
					echo "</pre></body></html>"
					exit 1
				}
			fi
		elif [ "$extension" = "wic" ]; then
			if [ -n "$bmap_to_use" ]; then
				bmap-writer "$main_file" "$real_dev" "$bmap_to_use" 2>/dev/null || {
					echo "FLASH_STATUS=FAIL"
					echo "FLASH_REASON=Failed to flash WIC image with bmap"
					echo "</pre></body></html>"
					exit 1
				}
			else
				dd if="$main_file" of="$real_dev" bs=32M 2>/dev/null || {
					echo "FLASH_STATUS=FAIL"
					echo "FLASH_REASON=Failed to flash WIC image"
					echo "</pre></body></html>"
					exit 1
				}
			fi
		else
			echo "FLASH_STATUS=FAIL"
			echo "FLASH_REASON=Unsupported file format: .$extension (only .xz and .wic are supported)"
			echo "</pre></body></html>"
			exit 1
		fi
		echo "FLASH_PROGRESS=95"

		echo "FLASH_PROGRESS=98"
		echo "FLASH_STATUS=SUCCESS"
		echo "FLASH_REASON=WIC image flashed successfully to $real_dev"
		if fw_printenv >/dev/null 2>&1; then
			fw_setenv BOOT_ORDER "A B"
			fw_setenv BOOT_A_LEFT 3
		fi
	else
		echo "FLASH_STATUS=FAIL"
		echo "FLASH_REASON=No main file provided"
	fi
else
	echo "FLASH_STATUS=IDLE"
	echo "FLASH_REASON=No POST request received"
fi

echo "</pre></body></html>"
exit 0
