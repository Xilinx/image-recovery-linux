#!/bin/sh
# Author: (c) sharathk

export CGIBASHOPTS_DIR=${PWD}
CGIBASHOPTS_TMP="$CGIBASHOPTS_DIR.tmp"

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
			if [ "$var" = "Image_A" ]; then
				echo "IMAGE A"  > imageA.txt
				flash_eraseall /dev/mtd5
				flashcp $val /dev/mtd5
			elif [ "$var" = "Image_B" ]; then
				echo "IMAGE B"  > imageB.txt
				flash_eraseall /dev/mtd7
				flashcp $val /dev/mtd7
			else
				echo "IMAGE WIC" > imageWIC.txt
				xzcat $val | dd of=/dev/mmcblk0 bs=32M
			fi
		fi
	    fi
	done
    fi
else
    s="${QUERY_STRING:-}"
fi
