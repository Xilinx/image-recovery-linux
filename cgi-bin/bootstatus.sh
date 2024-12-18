#!/bin/sh

cat /dev/mtd5 > boot_status.bin
last_boot=$(hexdump -s 0xC -n4 -e '"%x"' boot_status.bin)
requested_boot=$(hexdump -s 0x8 -n4 -e '"%x"' boot_status.bin)
imageA_bootable=$(hexdump -s 0x18 -n1 -e '"%x"' boot_status.bin)
imageB_bootable=$(hexdump -s 0x19 -n1 -e '"%x"' boot_status.bin)
rm boot_status.bin

if [ $last_boot = 0 ]; then
	lst_bt="ImageA"
else
	lst_bt="ImageB"
fi

if [ $requested_boot = 0 ]; then
	req_bt="ImageA"
else
	req_bt="ImageB"
fi

if [ $imageA_bootable = fc ]; then
	imga_btbl=true
else
	imga_btbl=false
fi

if [ $imageB_bootable = fc ]; then
	imgb_btbl=true
else
	imgb_btbl=false
fi


echo "Content-type: text/html"
echo ""

echo '{ "ImgABootable":'${imga_btbl}', "ImgBBootable":'${imgb_btbl}', "ReqBootImg":"'${req_bt}'", "LastBootImg":"'${lst_bt}'" }'

