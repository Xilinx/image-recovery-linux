#!/bin/sh
# Copyright (c) 2025 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

brdnm=$(printf "$(i2ctransfer -y 1 w2@0x54 0x0 0x16 r6 | sed 's/0x/\\x/g' | sed 's/ //g')\n")
revnum=$(printf "$(i2ctransfer -y 1 w2@0x54 0x0 0x44 r8 | sed 's/0x/\\x/g' | sed 's/ //g')\n")
srlnum=$(printf "$(i2ctransfer -y 1 w2@0x54 0x0 0x27 r16 | sed 's/0x/\\x/g' | sed 's/ //g')\n")
prtnum=$(printf "$(i2ctransfer -y 1 w2@0x54 0x0 0x38 r9 | sed 's/0x/\\x/g' | sed 's/ //g')\n")
uuid=$(i2ctransfer -y 1 w2@0x54 0x0 0x56 r16 | sed 's/0x//g' | sed 's/ //g')

echo "Content-type: text/html"
echo ""

echo '{"SysBoardInfo":{"BoardName":"'${brdnm}'","RevisionNo":"'${revnum}'","SerialNo":"'${srlnum}'","PartNo":"'${prtnum}'","UUID":"'${uuid^^}'"},"CcInfo":{"BoardName":"","RevisionNo":"","SerialNo":"","PartNo":"","UUID":""}}'