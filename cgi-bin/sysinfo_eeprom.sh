#!/bin/sh

cat /sys/bus/i2c/devices/1-0054/eeprom > sysinfo.bin
brdnm=$(hexdump -s 0x16 -n6 -e '"%c"' sysinfo.bin)
revnum=$(hexdump -s 0x44 -n8 -e '"%c"' sysinfo.bin)
srlnum=$(hexdump -s 0x27 -n16 -e '"%c"' sysinfo.bin)
prtnum=$(hexdump -s 0x38 -n9 -e '"%c"' sysinfo.bin)
uuid=$(hexdump -s 0x56 -n16 -e '"%X"' sysinfo.bin)
rm sysinfo.bin

echo "Content-type: text/html"
echo ""

echo '{"SysBoardInfo":{"BoardName":"'${brdnm}'","RevisionNo":"'${revnum}'","SerialNo":"'${srlnum}'","PartNo":"'${prtnum}'","UUID":"'${uuid^^}'"},"CcInfo":{"BoardName":"","RevisionNo":"","SerialNo":"","PartNo":"","UUID":""}}'