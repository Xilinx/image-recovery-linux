#!/bin/sh

part=a

while true ; do
  #echo $part
  if [ -r "/dev/sd${part}1" ]; then
    #echo "USB device found"
    if [ ! -d ./usb_disk ]; then
        mkdir usb_disk

    fi
    if ! mountpoint -q ./usb_disk; then
        mount "/dev/sd${part}1" usb_disk
    fi

    echo "Content-type: text/html"
    echo ""
    dir=./usb_disk
    for files in "$dir"/*
    do
      echo "$files"
    done
    break
  fi
  part=$(echo "$part" | tr "0-9a-z" "1-9a-z_")
done

