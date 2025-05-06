#!/bin/sh
# Copyright (c) 2025 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

#cat /dev/mtd3 > boot_status.bin

for i in `seq 0 7`
do
	if [ $i -ne 3 ]; then
		sum=$(awk "BEGIN {print $sum+$(hexdump -s $(( i*4 )) -n4 -e '"0x%x"' update_confg.bin); exit}")
	fi
done

#echo
#printf "Sum: 0x%X\n" $sum
checksum=$(( 0xFFFFFFFF-sum ))
#printf "Checksum: 0x%X\n" $checksum

printf -v f '\\x%02x\\x%02x\\x%02x\\x%02x' $((checksum&255)) $((checksum >> 8 & 255)) $((checksum >> 16 & 255)) $((checksum >> 24 & 255))
printf $f | (dd of=update_confg.bin bs=1 seek=12 count=4 conv=notrunc)

flash_eraseall /dev/mtd3
flashcp update_confg.bin /dev/mtd3

flash_eraseall /dev/mtd4
flashcp update_confg.bin /dev/mtd4

rm update_confg.bin
