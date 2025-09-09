#!/bin/sh
# Copyright (c) 2025 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

FILE=sys_mdata.bin

dd if="$FILE" of=extract_sys_mdata.bin bs=1 skip=4 count=120 2>/dev/null
crc32_raw_mdata=$(crc32 extract_sys_mdata.bin)

#Extract crc32 value
IFS=" "
set "$crc32_raw_mdata"
crc32_mdata=$1

printf -v crc32_mdata_bin "\\x%s\\x%s\\x%s\\x%s" "${crc32_mdata:6:2}" "${crc32_mdata:4:2}" "${crc32_mdata:2:2}" "${crc32_mdata:0:2}" 2>/dev/null

# Use '%b' to interpret backslash escapes safely
printf '%b' "$crc32_mdata_bin" | dd of="$FILE" bs=1 count=4 conv=notrunc 2>/dev/null

#Write the update Meta-data to flash partitions
flash_eraseall /dev/mtd5
flash_eraseall /dev/mtd6
flashcp $FILE /dev/mtd5
flashcp $FILE /dev/mtd6

rm "$FILE"
rm extract_sys_mdata.bin
