#!/bin/bash
# Author: (c) sharathk

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
						echo ${val[1]} > BP9.txt
						printf "\1" | (dd of=sys_mdata.bin bs=1 seek=8 count=1 conv=notrunc)
						printf "\0" | (dd of=sys_mdata.bin bs=1 seek=12 count=1 conv=notrunc)
						printf  "\xfc" | (dd of=sys_mdata.bin bs=1 seek=25 count=1 conv=notrunc)
						echo ${val[1]} > BP10.txt
						./cal_crc32.sh
						echo ${val[1]} > BP11.txt
					else
						echo "IMAGE A"  > ImageA.txt
						flash_eraseall /dev/mtd9
						flashcp ${val[1]} /dev/mtd9
						echo ${val[1]} > BP12.txt
						printf "\0" | (dd of=sys_mdata.bin bs=1 seek=8 count=1 conv=notrunc)
						printf "\1" | (dd of=sys_mdata.bin bs=1 seek=12 count=1 conv=notrunc)
						printf  "\xfc" | (dd of=sys_mdata.bin bs=1 seek=24 count=1 conv=notrunc)
						echo ${val[1]} > BP13.txt
						./cal_crc32.sh
						echo ${val[1]} > BP14.txt
					fi
				else
					echo ${val[1]} > ImageWIC.txt
					#xzcat ${val[1]} | dd of=/dev/mmcblk0 bs=32M
					extension="${{val[1]}##*.}"
					filename="${{val[1]}%.*}"
					echo $extension > BP1.txt
					echo $filename > BP2.txt
					if [ "$extension" = "xz" ]; then
						echo $extension > BP3.txt
						if [ -f "$filename.bmap" ]; then
							echo ${val[1]} > BP4.txt
							#xzcat ${val[1]} | bmap-writer - $filename.bmap /dev/disk/by-path/platform-xhci-hcd.0.auto-usb-0:1.1:1.0-scsi-0:0:0:0
						else
							echo ${val[1]} > BP5.txt
							#xzcat ${val[1]} | dd of=/dev/disk/by-path/platform-xhci-hcd.0.auto-usb-0:1.1:1.0-scsi-0:0:0:0 bs=32M
						fi
					elif [ "$extension" = "wic" ]; then
						echo $extension > BP6.txt
						if [ -f "$filename.wic.bmap" ]; then
							echo ${val[1]} > BP7.txt
							#bmap-writer ${val[1]} $filename.wic.bmap /dev/disk/by-path/platform-xhci-hcd.0.auto-usb-0:1.1:1.0-scsi-0:0:0:0
						else
							echo ${val[1]} > BP8.txt
							#dd if=${val[1]} of=/dev/disk/by-path/platform-xhci-hcd.0.auto-usb-0:1.1:1.0-scsi-0:0:0:0
						fi
					fi
				fi
			fi
		done
	fi
else
	s="${QUERY_STRING:-}"
fi
