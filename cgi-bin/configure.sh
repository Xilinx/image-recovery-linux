#!/bin/sh
# Copyright (c) 2025 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

cat /dev/mtd3 > update_confg.bin
confg_boot=$(cat)
IFS="_"
set "$confg_boot"
#echo $confg_boot > confg_boot.txt


if [ "$2" = true ]; then
	printf "\1" | (dd of=update_confg.bin bs=1 seek=18 count=1 conv=notrunc)
else
	printf "\0" | (dd of=update_confg.bin bs=1 seek=18 count=1 conv=notrunc)
fi

if [ "$4" = true ]; then
	printf "\1" | (dd of=update_confg.bin bs=1 seek=19 count=1 conv=notrunc)
else
	printf "\0" | (dd of=update_confg.bin bs=1 seek=19 count=1 conv=notrunc)
fi

if [ "$6" = ImageA ]; then
	printf "\0" | (dd of=update_confg.bin bs=1 seek=17 count=1 conv=notrunc)
else
	printf "\1" | (dd of=update_confg.bin bs=1 seek=17 count=1 conv=notrunc)
fi

./checksum.sh
