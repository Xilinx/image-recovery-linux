#!/bin/sh

if [ -r "/home/sharathk/temp/BOOT.BIN" ]; then
    echo "Path exist"
    echo "Content-type: text/html"
    echo ""

    dir=/home/sharathk/temp
    for files in "$dir"/*
    do
      echo "$files"
    done

else
    echo "Path not exist"
    echo "Content-type: text/html"
    echo ""
    echo 'ok'
fi


