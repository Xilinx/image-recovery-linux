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
					echo "IMAGE A"
					echo ${val[1]} > imageA.txt
					flash_eraseall /dev/mtd5
					flashcp ${val[1]} /dev/mtd5
				elif [ "${val[0]}" = "Image_B" ]; then
					echo "IMAGE B"
					echo ${val[1]} > imageB.txt
					flash_eraseall /dev/mtd7
					flashcp ${val[1]} /dev/mtd7
				else
					echo "IMAGE WIC"
					echo ${val[1]} > imageWIC.txt
					xzcat ${val[1]} | dd of=/dev/mmcblk0 bs=32M
				fi
			fi
		done
	fi
else
	s="${QUERY_STRING:-}"
fi
