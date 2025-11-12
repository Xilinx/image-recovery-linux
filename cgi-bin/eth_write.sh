#!/bin/sh
# Copyright (c) 2025 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

echo "Content-type: text/html"
echo ""
echo "<html><body><pre>"

CGIBASHOPTS_DIR="${PWD}"
CGIBASHOPTS_TMP="${CGIBASHOPTS_DIR}.tmp"
SCRIPT_DIR="$(dirname "$0")"
METADATA_FILE="sys_mdata.bin"

# Cleanup function
cleanup() {
	rm -f "$CGIBASHOPTS_TMP" "$METADATA_FILE"
}

trap cleanup EXIT

# Read current active bank from metadata
if ! cat /dev/mtd5 > "$METADATA_FILE" 2>/dev/null; then
	echo "FLASH_STATUS=FAIL"
	echo "FLASH_REASON=Failed to read MTD device"
	echo "</pre></body></html>"
	exit 1
fi

active_bank=$(hexdump -s 0x8 -n4 -e '"%x"' "$METADATA_FILE")

if [ "${REQUEST_METHOD:-}" = "POST" ]; then
	echo "Upload directory: $CGIBASHOPTS_DIR"

	if [[ ${CONTENT_TYPE:-} =~ ^multipart/form-data[\;,][[:space:]]*boundary=([^\;,]+) ]]; then
		OIFS="$IFS"
		IFS=$'\r'

		while read -r line; do
			if [[ $line =~ ^Content-Disposition:\ *form-data[\;,]\ *name=\"([^\"]+)\"(\;\ *filename=\"([^\"]+)\")? ]]; then
				var="${BASH_REMATCH[1]}"
				val="${BASH_REMATCH[3]}"
				[[ $val =~ [%+] ]] && val=$(urldecode "$val")
				type=""

				read -r line
				while [ -n "$line" ]; do
					if [[ $line =~ ^Content-Type:\ *text/plain ]]; then
						type="txt"
					elif [[ $line =~ ^Content-Type: ]]; then
						type="bin"
					fi
					read -r line
				done

				if [ "$type" = "bin" ]; then
					# Save binary file
					sed '{$d}' > "$CGIBASHOPTS_TMP"
					truncate -s $(($(stat -c '%s' "$CGIBASHOPTS_TMP") - 2)) "$CGIBASHOPTS_TMP"
					mv "$CGIBASHOPTS_TMP" "$CGIBASHOPTS_DIR/$val"

					if [ "$var" = "Image_FLASH" ]; then
						# Flash boot image to inactive bank
						if [ "$active_bank" = "0" ]; then
							echo "Flashing IMAGE B"

							if ! flash_eraseall /dev/mtd12 2>/dev/null; then
								echo "FLASH_STATUS=FAIL"
								echo "FLASH_REASON=Failed to erase /dev/mtd12"
								echo "</pre></body></html>"
								exit 1
							fi

							if ! flashcp "$val" /dev/mtd12 2>/dev/null; then
								echo "FLASH_STATUS=FAIL"
								echo "FLASH_REASON=Failed to write image to /dev/mtd12"
								echo "</pre></body></html>"
								exit 1
							fi

							# Update metadata: set active bank to B, previous to A
							printf "\x01" | dd of="$METADATA_FILE" bs=1 seek=8 count=1 conv=notrunc 2>/dev/null
							printf "\x00" | dd of="$METADATA_FILE" bs=1 seek=12 count=1 conv=notrunc 2>/dev/null
							printf "\xfc" | dd of="$METADATA_FILE" bs=1 seek=25 count=1 conv=notrunc 2>/dev/null
						else
							echo "Flashing IMAGE A"

							if ! flash_eraseall /dev/mtd9 2>/dev/null; then
								echo "FLASH_STATUS=FAIL"
								echo "FLASH_REASON=Failed to erase /dev/mtd9"
								echo "</pre></body></html>"
								exit 1
							fi

							if ! flashcp "$val" /dev/mtd9 2>/dev/null; then
								echo "FLASH_STATUS=FAIL"
								echo "FLASH_REASON=Failed to write image to /dev/mtd9"
								echo "</pre></body></html>"
								exit 1
							fi

							# Update metadata: set active bank to A, previous to B
							printf "\x00" | dd of="$METADATA_FILE" bs=1 seek=8 count=1 conv=notrunc 2>/dev/null
							printf "\x01" | dd of="$METADATA_FILE" bs=1 seek=12 count=1 conv=notrunc 2>/dev/null
							printf "\xfc" | dd of="$METADATA_FILE" bs=1 seek=24 count=1 conv=notrunc 2>/dev/null
						fi

						# Calculate CRC32 and update flash
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

						echo "FLASH_STATUS=SUCCESS"
						echo "FLASH_REASON=Boot image flashed successfully"

					else
						# Flash WIC image to storage device
						echo "Flashing WIC IMAGE"
						real_dev=""
						basefile=$(basename "$val")

						# Determine image type based on filename
						if echo "$basefile" | grep -qE '\.wic\.ufs\.xz$'; then
							image_type="ufs"
						else
							image_type="usb"
						fi

						# Find appropriate storage device
						for dev in /dev/disk/by-path/* /dev/mmcblk* /dev/sd*; do
							[ -e "$dev" ] || continue
							resolved=$(readlink -f "$dev")
							[ -b "$resolved" ] || continue

							udev_info=$(udevadm info --query=property --name="$resolved" 2>/dev/null)
							id_path=$(echo "$udev_info" | grep '^ID_PATH=' | cut -d= -f2)

							if [ "$image_type" = "ufs" ]; then
								if echo "$id_path" | grep -qi "ufs"; then
									real_dev="$resolved"
									break
								fi
							else
								if echo "$id_path" | grep -qi "usb"; then
									real_dev="$resolved"
									break
								elif echo "$id_path" | grep -qi "mmc"; then
									real_dev="$resolved"
									break
								fi
							fi
						done

						# Fallback to default eMMC if no device found
						if [ -z "$real_dev" ] && [ -b /dev/mmcblk0 ]; then
							real_dev="/dev/mmcblk0"
							echo "Fallback to default eMMC: $real_dev"
						fi

						if [ ! -b "$real_dev" ]; then
							echo "FLASH_STATUS=FAIL"
							echo "FLASH_REASON=No valid storage device found for flashing"
							echo "</pre></body></html>"
							exit 1
						fi

						echo "Target device: $real_dev"
						extension="${val##*.}"
						filename="${val%.*}"

						# Flash based on file extension
						if [ "$extension" = "xz" ]; then
							if [ -f "$filename.bmap" ]; then
								if ! xzcat "$val" | bmap-writer - "$filename.bmap" "$real_dev" 2>/dev/null; then
									echo "FLASH_STATUS=FAIL"
									echo "FLASH_REASON=Failed to flash compressed image with bmap"
									echo "</pre></body></html>"
									exit 1
								fi
							else
								if ! xzcat "$val" | dd of="$real_dev" bs=32M 2>/dev/null; then
									echo "FLASH_STATUS=FAIL"
									echo "FLASH_REASON=Failed to flash compressed image"
									echo "</pre></body></html>"
									exit 1
								fi
							fi
						elif [ "$extension" = "wic" ]; then
							if [ -f "$filename.wic.bmap" ]; then
								if ! bmap-writer "$val" "$filename.wic.bmap" "$real_dev" 2>/dev/null; then
									echo "FLASH_STATUS=FAIL"
									echo "FLASH_REASON=Failed to flash WIC image with bmap"
									echo "</pre></body></html>"
									exit 1
								fi
							else
								if ! dd if="$val" of="$real_dev" bs=32M 2>/dev/null; then
									echo "FLASH_STATUS=FAIL"
									echo "FLASH_REASON=Failed to flash WIC image"
									echo "</pre></body></html>"
									exit 1
								fi
							fi
						fi

						echo "FLASH_STATUS=SUCCESS"
						echo "FLASH_REASON=WIC image flashed successfully to $real_dev"
					fi

					# Clean up uploaded file
					#rm -f "$CGIBASHOPTS_DIR/$val"
				fi
			fi
		done
		IFS="$OIFS"
	fi
else
	echo "FLASH_STATUS=IDLE"
	echo "FLASH_REASON=No POST request received"
fi

echo "</pre></body></html>"
exit 0

