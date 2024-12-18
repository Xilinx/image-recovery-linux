#!/bin/sh
# Author: (c) sharathk

export CGIBASHOPTS_DIR=${PWD}
CGIBASHOPTS_TMP="$CGIBASHOPTS_DIR.tmp"

if [ "${REQUEST_METHOD:-}" = POST ]; then
	if [[ ${CONTENT_TYPE:-} =~ ^multipart/form-data[\;,][[:space:]]*boundary=([^\;,]+) ]]; then
		IFS=':'
		while read -r line; do
			if [[ $line =~ ^Content-Disposition:\ *form-data[\;,]\ *name=\"([^\"]+)\"(\;\ *filename=\"([^\"]+)\")? ]]; then
				read -ra val <<< "${BASH_REMATCH[1]}"
				if [ "${val[0]}" = "Image_A" ]; then
					echo ${val[1]} > ImageA.txt
					flash_eraseall /dev/mtd9
					flashcp ${val[1]} /dev/mtd9
				elif [ "${val[0]}" = "Image_B" ]; then
					echo ${val[1]} > ImageB.txt
					flash_eraseall /dev/mtd12
					flashcp ${val[1]} /dev/mtd12
				elif [ "${val[0]}" = "Image_C" ]; then
					echo "SysRdy Mdata"  > SysRdyMdata.txt
					flash_eraseall /dev/mtd5
					flash_eraseall /dev/mtd6
					flashcp $val /dev/mtd5
					flashcp $val /dev/mtd6
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
