#!/bin/sh

cat /dev/mtd5 > sys_mdata.bin
bankA_status=$(hexdump -s 0x18 -n1 -e '"%x"' sys_mdata.bin)
bankB_status=$(hexdump -s 0x19 -n1 -e '"%x"' sys_mdata.bin)
active_bank=$(hexdump -s 0x8 -n4 -e '"%x"' sys_mdata.bin)
prev_active_bank=$(hexdump -s 0xC -n4 -e '"%x"' sys_mdata.bin)
rm sys_mdata.bin

if [ $bankA_status = fc ]; then
	bankA_st=true
else
	bankA_st=false
fi

if [ $bankB_status = fc ]; then
	bankB_st=true
else
	bankB_st=false
fi

if [ $active_bank = 0 ]; then
	active_bnk="ImageA"
else
	active_bnk="ImageB"
fi

if [ $prev_active_bank = 0 ]; then
	prev_active_bnk="ImageA"
else
	prev_active_bnk="ImageB"
fi



echo "Content-type: text/html"
echo ""

echo '{ "BankAStatus":'${bankA_st}', "BankBStatus":'${bankB_st}', "ActiveBank":"'${active_bnk}'", "PrevActiveBank":"'${prev_active_bnk}'" }'

