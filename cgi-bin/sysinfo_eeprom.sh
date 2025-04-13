#!/bin/sh

cat /sys/bus/i2c/devices/*/eeprom > sysinfo.bin
brdnm=$(hexdump -s 0x16 -n6 -e '8/1 "%c"' sysinfo.bin | tr -d '\000')
revnum=$(hexdump -s 0x44 -n8 -e '8/1 "%c"' sysinfo.bin | tr -d '\000')
srlnum=$(hexdump -s 0x27 -n16 -e '8/1 "%c"' sysinfo.bin | tr -d '\000')
prtnum=$(hexdump -s 0x38 -n9 -e '8/1 "%c"' sysinfo.bin | tr -d '\000')
uuid=$(hexdump -s 0x56 -n16 -e '8/1 "%X"' sysinfo.bin | tr -d '\000')
rm sysinfo.bin

echo "Content-type: text/html"
echo ""

echo '{"SysBoardInfo":{"BoardName":"'${brdnm}'","RevisionNo":"'${revnum}'","SerialNo":"'${srlnum}'","PartNo":"'${prtnum}'","UUID":"'${uuid^^}'"},"CcInfo":{"BoardName":"","RevisionNo":"","SerialNo":"","PartNo":"","UUID":""}}'