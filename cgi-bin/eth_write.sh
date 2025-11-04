#!/bin/sh
# Copyright (c) 2025 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

echo "Content-type: text/html"
echo ""

echo "<html><body><pre>"

export CGIBASHOPTS_DIR=${PWD}
CGIBASHOPTS_TMP="$CGIBASHOPTS_DIR.tmp"

cat /dev/mtd5 > sys_mdata.bin
active_bank=$(hexdump -s 0x8 -n4 -e '"%x"' sys_mdata.bin)

if [ "${REQUEST_METHOD:-}" = POST ]; then
	echo "Upload directory: $CGIBASHOPTS_DIR"
    if [[ ${CONTENT_TYPE:-} =~ ^multipart/form-data[\;,][[:space:]]*boundary=([^\;,]+) ]]; then
	OIFS="$IFS"; IFS=$'\r'
	while read -r line; do
	    if [[ $line =~ ^Content-Disposition:\ *form-data[\;,]\ *name=\"([^\"]+)\"(\;\ *filename=\"([^\"]+)\")? ]]; then
		var="${BASH_REMATCH[1]}"
		val="${BASH_REMATCH[3]}"
		[[ $val =~ [%+] ]] && val=$(urldecode "$val")
		type=
		read -r line
		while [ -n "$line" ]; do
		    if [[ $line =~ ^Content-Type:\ *text/plain ]]; then
			type=txt
		    elif [[ $line =~ ^Content-Type: ]]; then # any other type
			type=bin
		    fi
		    read -r line
		done
		if [ "$type" = bin ]; then # binary file upload
			sed '{$d}' >$CGIBASHOPTS_TMP
			truncate -s $(expr $(stat -c '%s' $CGIBASHOPTS_TMP) - 2) $CGIBASHOPTS_TMP
			mv $CGIBASHOPTS_TMP "$CGIBASHOPTS_DIR/$val"
			if [ "$var" = "Image_FLASH" ]; then
				if [ $active_bank = 0 ]; then
					echo "IMAGE B"  > ImageB.txt
					flash_eraseall /dev/mtd12
					flashcp $val /dev/mtd12
					if ! flashcp "$val" /dev/mtd12; then
						echo "FLASH_STATUS=FAIL"
						echo "FLASH_REASON=Failed to write image to /dev/mtd12"
						exit 1
					fi
					printf "\1" | (dd of=sys_mdata.bin bs=1 seek=8 count=1 conv=notrunc)
					printf "\0" | (dd of=sys_mdata.bin bs=1 seek=12 count=1 conv=notrunc)
					printf  "\xfc" | (dd of=sys_mdata.bin bs=1 seek=25 count=1 conv=notrunc)
					./cal_crc32.sh
				else
					echo "IMAGE A"  > ImageA.txt
					flash_eraseall /dev/mtd9
					flashcp $val /dev/mtd9
					if ! flashcp "$val" /dev/mtd9; then
						echo "FLASH_STATUS=FAIL"
						echo "FLASH_REASON=Failed to write image to /dev/mtd9"
						exit 1
					fi
					printf "\0" | (dd of=sys_mdata.bin bs=1 seek=8 count=1 conv=notrunc)
					printf "\1" | (dd of=sys_mdata.bin bs=1 seek=12 count=1 conv=notrunc)
					printf  "\xfc" | (dd of=sys_mdata.bin bs=1 seek=24 count=1 conv=notrunc)
					./cal_crc32.sh
				fi
				echo "FLASH_STATUS=SUCCESS"
				echo "FLASH_REASON=Boot image flashed successfully"
			else
				echo "IMAGE WIC" > ImageWIC.txt
				real_dev=""
				basefile=$(basename "$val")

				if echo "$basefile" | grep -qE '\.wic\.ufs\.xz$'; then
					image_type="ufs"
				else
					image_type="usb"
				fi
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
				if [ "$extension" = "xz" ]; then
					if [ -f "$filename.bmap" ]; then
						xzcat $val | bmap-writer - $filename.bmap $real_dev
					else
						xzcat $val | dd of=$real_dev bs=32M
					fi
				elif [ "$extension" = "wic" ]; then
					if [ -f "$filename.wic.bmap" ]; then
						bmap-writer $val $filename.wic.bmap $real_dev
					else
						dd if=$val of=$real_dev
						fi
					fi
					echo "FLASH_STATUS=SUCCESS"
					echo "FLASH_REASON=WIC image flashed successfully to $real_dev"
				fi
			fi
		fi
	done
fi
else
 	echo "FLASH_STATUS=IDLE"
	echo "FLASH_REASON=No POST request received"
fi
echo "</pre></body></html>"

