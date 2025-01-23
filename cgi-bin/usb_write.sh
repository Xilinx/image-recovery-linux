#!/bin/sh
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
					xzcat ${val[1]} | dd of=/dev/mmcblk0 bs=32M
				fi
			fi
		done
	fi
else
	s="${QUERY_STRING:-}"
fi
