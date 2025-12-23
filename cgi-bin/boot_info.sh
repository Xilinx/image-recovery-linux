#!/bin/sh
# Copyright (c) 2025 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

# This CGI helper surfaces the currently installed BOOT.bin version/build
# information for both active and previous banks so the UI can show it.

echo "Content-type: application/json"
echo ""

metadata_file=$(mktemp) || exit 1

cleanup() {
	rm -f "$metadata_file"
	[ -n "$snippet_file_active" ] && [ -f "$snippet_file_active" ] && rm -f "$snippet_file_active"
	[ -n "$snippet_file_prev" ] && [ -f "$snippet_file_prev" ] && rm -f "$snippet_file_prev"
}
trap cleanup EXIT

json_value() {
	if [ -z "$1" ]; then
		printf 'null'
	else
		escaped=$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')
		printf '"%s"' "$escaped"
	fi
}

emit_empty() {
	printf '{ "version_active": null, "version_prev": null }\n'
}

if ! cat /dev/mtd5 > "$metadata_file" 2>/dev/null; then
	emit_empty
	exit 0
fi

active_bank=$(hexdump -s 0x8 -n4 -e '"%x"' "$metadata_file")
active_bank=$((0x$active_bank))

case "$active_bank" in
	0) boot_dev_active="/dev/mtd9"; boot_dev_prev="/dev/mtd12" ;;
	1) boot_dev_active="/dev/mtd12"; boot_dev_prev="/dev/mtd9" ;;
	*) boot_dev_active=""; boot_dev_prev="" ;;
esac

if [ -z "$boot_dev_active" ] || [ ! -r "$boot_dev_active" ]; then
	emit_empty
	exit 0
fi

get_version() {
	local dev="$1"
	local snippet_file
	snippet_file=$(mktemp) || return
	if dd if="$dev" of="$snippet_file" bs=512k count=8 2>/dev/null; then
		# Remove everything up to and including the first semicolon
		strings "$snippet_file" | grep -m1 'Version=' | sed 's/^[^;]*;//'
	fi
	rm -f "$snippet_file"
}


version_active=$(get_version "$boot_dev_active")
version_prev=""
if [ -n "$boot_dev_prev" ] && [ -r "$boot_dev_prev" ]; then
	version_prev=$(get_version "$boot_dev_prev")
fi

printf '{ "version_active": %s, "version_prev": %s }\n' \
	"$(json_value "$version_active")" \
	"$(json_value "$version_prev")"
