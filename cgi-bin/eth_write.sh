#!/bin/sh
# Author: (c) sharathk

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
				extension="${val##*.}"
				filename="${val%.*}"
				if [ "$extension" = "xz" ]; then
					if [ -f "$filename.bmap" ]; then
						xzcat $val | bmap-writer - $filename.bmap /dev/disk/by-path/platform-xhci-hcd.0.auto-usb-0:1.1:1.0-scsi-0:0:0:0
					else
						xzcat $val | dd of=/dev/disk/by-path/platform-xhci-hcd.0.auto-usb-0:1.1:1.0-scsi-0:0:0:0 bs=32M
					fi
				elif [ "$extension" = "wic" ]; then
					if [ -f "$filename.wic.bmap" ]; then
						bmap-writer $val $filename.wic.bmap /dev/disk/by-path/platform-xhci-hcd.0.auto-usb-0:1.1:1.0-scsi-0:0:0:0
					else
						dd if=$val of=/dev/disk/by-path/platform-xhci-hcd.0.auto-usb-0:1.1:1.0-scsi-0:0:0:0
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
