#!/bin/sh
 
for i in {2..3}
do 
	#echo "/dev/disk/by-path/platform-xhci-hcd.0.auto-usb-0:1.${i}:1.0-scsi-0:0:0:0"
	if [ -L "/dev/disk/by-path/platform-xhci-hcd.0.auto-usb-0:1.${i}:1.0-scsi-0:0:0:0" ]; then
		#echo "USB device found on $i"
		if [ ! -d ./usb_disk ]; then
			mkdir usb_disk
		fi
		if ! mountpoint -q ./usb_disk; then
			mount /dev/disk/by-path/platform-xhci-hcd.0.auto-usb-0:1.${i}:1.0-scsi-0:0:0:0-part1 usb_disk
		fi

		echo "Content-type: text/html"
		echo ""
		dir=./usb_disk
		for files in "$dir"/*
		do
			filename=$(basename $files)
			echo "$filename"
		done
		break
	fi
done