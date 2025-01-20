#!/bin/sh

json_data=$(cat)

IFS=":"
set $json_data
raw_img_nm=$2
raw_crc_val=$3

IFS=","
set $raw_img_nm
str_img_nm=$1

IFS="\""
set $str_img_nm
str_crc32=$(crc32 $2)

IFS=" "
set $str_crc32
cal_crc32=$((0x${1}))

IFS="}"
set $raw_crc_val
exp_crc32=$1

echo "Content-type: text/html"
echo ""

if [ $cal_crc32 = $exp_crc32 ]; then
	echo '{ "Status":"Success" }'
else
	echo '{ "Status":"Fail" }'
fi
