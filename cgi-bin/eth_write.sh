#!/bin/sh
# Copyright (c) 2025 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

export CGIBASHOPTS_DIR=${PWD}
CGIBASHOPTS_TMP="$CGIBASHOPTS_DIR.tmp"

cat /dev/mtd5 > sys_mdata.bin
active_bank=$(hexdump -s 0x8 -n4 -e '"%x"' sys_mdata.bin)

if [ "${REQUEST_METHOD:-}" = POST ]; then
	echo $CGIBASHOPTS_DIR
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
					printf "\1" | (dd of=sys_mdata.bin bs=1 seek=8 count=1 conv=notrunc)
					printf "\0" | (dd of=sys_mdata.bin bs=1 seek=12 count=1 conv=notrunc)
					printf  "\xfc" | (dd of=sys_mdata.bin bs=1 seek=25 count=1 conv=notrunc)
					./cal_crc32.sh
				else
					echo "IMAGE A"  > ImageA.txt
					flash_eraseall /dev/mtd9
					flashcp $val /dev/mtd9
					printf "\0" | (dd of=sys_mdata.bin bs=1 seek=8 count=1 conv=notrunc)
					printf "\1" | (dd of=sys_mdata.bin bs=1 seek=12 count=1 conv=notrunc)
					printf  "\xfc" | (dd of=sys_mdata.bin bs=1 seek=24 count=1 conv=notrunc)
					./cal_crc32.sh
				fi
			else
				echo "IMAGE WIC" > ImageWIC.txt
				for dev in /dev/disk/by-path/*usb* /dev/disk/by-path/*mmc*; do
					real_dev=$(readlink -f "$dev")
					model=$(udevadm info --query=property --name="$real_dev" | grep '^ID_MODEL=' | cut -d= -f2)

					if echo "$model" | grep -Eqi 'SD|Combo|Reader'; then
						#echo "SD card found via USB hub: $dev -> $real_dev (Model: $model)"
						break
					else
						#echo "SD Card not found"
						echo "Content-type: text/html"
						echo ""
						break
					fi
				done
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
			fi
		fi
	    fi
	done
    fi
else
    s="${QUERY_STRING:-}"
fi
