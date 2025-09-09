#!/bin/sh
# Copyright (c) 2025 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

echo "Content-type: text/html"
echo ""

echo "<html><body><pre>"

export CGIBASHOPTS_DIR="${PWD}"
CGIBASHOPTS_TMP="$CGIBASHOPTS_DIR.tmp"

cat /dev/mtd5 > sys_mdata.bin
active_bank=$(hexdump -s 0x8 -n4 -e '"%x"' sys_mdata.bin)

if [ "${REQUEST_METHOD:-}" = POST ]; then
	echo "Upload directory: $CGIBASHOPTS_DIR"
	if [[ ${CONTENT_TYPE:-} =~ ^multipart/form-data[\;,][[:space:]]*boundary=([^\;,]+) ]]; then
		IFS=':'
		while read -r line; do
			if [[ $line =~ ^Content-Disposition:\ *form-data[\;,]\ *name=\"([^\"]+)\"(\;\ *filename=\"([^\"]+)\")? ]]; then
				read -ra val <<< "${BASH_REMATCH[1]}"
				if [ "${val[0]}" = "Image_FLASH" ]; then
					if [ "$active_bank" = 0 ]; then
						echo "IMAGE B"  > ImageB.txt
						flash_eraseall /dev/mtd12
						flashcp "${val[1]}" /dev/mtd12
						printf "\1" | (dd of=sys_mdata.bin bs=1 seek=8 count=1 conv=notrunc)
						printf "\0" | (dd of=sys_mdata.bin bs=1 seek=12 count=1 conv=notrunc)
						printf  "\xfc" | (dd of=sys_mdata.bin bs=1 seek=25 count=1 conv=notrunc)
						./cal_crc32.sh
					else
						echo "IMAGE A"  > ImageA.txt
						flash_eraseall /dev/mtd9
						flashcp "${val[1]}" /dev/mtd9
						printf "\0" | (dd of=sys_mdata.bin bs=1 seek=8 count=1 conv=notrunc)
						printf "\1" | (dd of=sys_mdata.bin bs=1 seek=12 count=1 conv=notrunc)
						printf  "\xfc" | (dd of=sys_mdata.bin bs=1 seek=24 count=1 conv=notrunc)
						./cal_crc32.sh
					fi
					   echo "FLASH_STATUS=SUCCESS"
					   echo "FLASH_REASON=Boot image flashed successfully"
				   else
					echo "${val[1]}" > ImageWIC.txt
					real_dev=""
					for dev in /dev/disk/by-path/*usb* /dev/disk/by-path/*mmc*; do
						[ -e "$dev" ] || continue
							resolved=$(readlink -f "$dev")
							if [ ! -b "$resolved" ]; then
								continue
							fi
						 model=$(udevadm info --query=property --name="$resolved" 2>/dev/null | grep '^ID_MODEL=' | cut -d= -f2 || echo "")
							if echo "$model" | grep -Eqi 'SD|Combo|Reader|MMC|eMMC'; then
							real_dev="$resolved"
							break
							fi
						done
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
					extension="${val[1]##*.}"
					filename="${val[1]%.*}"
					if [ "$extension" = "bmap" ]; then
						if [ -f "$filename.xz" ]; then
							xzcat "$filename.xz" | bmap-writer - "$filename.bmap" "$real_dev"
						elif [ -f "$filename" ]; then
							bmap-writer "$filename" "$filename.bmap" "$real_dev"
						else
							echo "Content-type: text/html"
							echo ""
							echo 'Fail'
							exit 1
						fi
					elif [ "$extension" = "xz" ]; then
						xzcat "$filename.xz" | dd of="$real_dev" bs=32M
					elif [ "$extension" = "wic" ]; then
						dd if="$filename.wic" of="$real_dev"
						fi
					fi 
					echo "FLASH_STATUS=SUCCESS"
					echo "FLASH_REASON=WIC image flashed successfully to $real_dev"
				fi
			done
		fi
else
    echo "FLASH_STATUS=IDLE"
    echo "FLASH_REASON=No POST request received"
fi
echo "</pre></body></html>"

