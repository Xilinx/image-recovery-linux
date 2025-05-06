#!/bin/sh
# Copyright (c) 2025 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

export CGIBASHOPTS_DIR=${PWD}
CGIBASHOPTS_TMP="$CGIBASHOPTS_DIR.tmp"

cat /dev/mtd5 > sys_mdata.bin
active_bank=$(hexdump -s 0x8 -n4 -e '"%x"' sys_mdata.bin)

if [ "${REQUEST_METHOD:-}" = POST ]; then
	if [[ ${CONTENT_TYPE:-} =~ ^multipart/form-data[\;,][[:space:]]*boundary=([^\;,]+) ]]; then
		IFS=':'
		while read -r line; do
			if [[ $line =~ ^Content-Disposition:\ *form-data[\;,]\ *name=\"([^\"]+)\"(\;\ *filename=\"([^\"]+)\")? ]]; then
				read -ra val <<< "${BASH_REMATCH[1]}"
				if [ "${val[0]}" = "Image_FLASH" ]; then
					if [ $active_bank = 0 ]; then
						echo "IMAGE B"  > ImageB.txt
						flash_eraseall /dev/mtd12
						flashcp ${val[1]} /dev/mtd12
						printf "\1" | (dd of=sys_mdata.bin bs=1 seek=8 count=1 conv=notrunc)
						printf "\0" | (dd of=sys_mdata.bin bs=1 seek=12 count=1 conv=notrunc)
						printf  "\xfc" | (dd of=sys_mdata.bin bs=1 seek=25 count=1 conv=notrunc)
						./cal_crc32.sh
					else
						echo "IMAGE A"  > ImageA.txt
						flash_eraseall /dev/mtd9
						flashcp ${val[1]} /dev/mtd9
						printf "\0" | (dd of=sys_mdata.bin bs=1 seek=8 count=1 conv=notrunc)
						printf "\1" | (dd of=sys_mdata.bin bs=1 seek=12 count=1 conv=notrunc)
						printf  "\xfc" | (dd of=sys_mdata.bin bs=1 seek=24 count=1 conv=notrunc)
						./cal_crc32.sh
					fi
				else
					echo ${val[1]} > ImageWIC.txt
					for dev in /dev/disk/by-path/*usb*; do
						real_dev=$(readlink -f "$dev")
						model=$(udevadm info --query=property --name="$real_dev" | grep '^ID_MODEL=' | cut -d= -f2)

						if echo "$model" | grep -Eqi 'SD|Combo|Reader'; then
							#echo "SD card found via USB hub: $dev -> $real_dev (Model: $model)"
							break
						else
							#echo "SD Card not found"
							echo "Content-type: text/html"
							echo ""
							echo 'Fail'
							exit 1
						fi
					done
					extension="${val[1]##*.}"
					filename="${val[1]%.*}"
					if [ "$extension" = "bmap" ]; then
						if [ -f "$filename.xz" ]; then
							xzcat $filename.xz | bmap-writer - $filename.bmap $real_dev
						elif [ -f "$filename" ]; then
							bmap-writer $filename $filename.bmap $real_dev
						else
							echo "Content-type: text/html"
							echo ""
							echo 'Fail'
							exit 1
						fi
					elif [ "$extension" = "xz" ]; then
						xzcat $filename.xz | dd of=$real_dev bs=32M
					elif [ "$extension" = "wic" ]; then
						dd if=$filename.wic of=$real_dev
					fi
				fi
			fi
		done
	fi
	echo "Content-type: text/html"
	echo ""
	echo 'Success'
else
	s="${QUERY_STRING:-}"
fi
