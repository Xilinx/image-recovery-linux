#!/bin/sh
#
# Copyright (c) 2025 - 2026 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT
#
# UFS Device Configuration Script
# Configures UFS device logical units and writes configuration #

echo "Content-type: application/json"
echo ""

SCRIPT_DIR="$(dirname "$0")"

# Initialize logging variables
FINAL_STATUS=""
FINAL_MESSAGE=""
LOGGING_ENABLED=0

# Source logging utility
if [ -f "$SCRIPT_DIR/flash_logger.sh" ]; then
	. "$SCRIPT_DIR/flash_logger.sh"
fi

# Constants
readonly ALLOWED_DEVICE_PATTERN='^/dev/bsg/ufs-bsg[0-9]+$'

# Get request method (GET for query, POST for write)
REQUEST_METHOD="${REQUEST_METHOD:-GET}"

# Read POST data if POST request (must read ALL lines, not just one)
if [ "$REQUEST_METHOD" = "POST" ]; then
	# Normalize to a single line so simple regex parsing works reliably
	POST_DATA=$(cat | tr -d '\n\r')
fi

# Default UFS device path
UFS_DEVICE="/dev/bsg/ufs-bsg0"

# Create secure temp files
CONFIG_FILE=$(mktemp /tmp/ufsconfig.XXXXXX) || {
	echo '{"status":"error","message":"Failed to create temp file"}'
	exit 1
}

# Function to log messages
log_message() {
	echo "$1" >&2
	echo "$1" >> /tmp/ufs_debug.log
	if [ "$LOGGING_ENABLED" = "1" ]; then
		log_info "$1"
	fi
}

# Function to cleanup
cleanup() {
	# Cleanup temp files (debug file already saved earlier)
	rm -f "$CONFIG_FILE" "$CONFIG_FILE.hex"
	#rm -rf "$TEMP_DIR"
}

trap 'cleanup; [ "$LOGGING_ENABLED" = "1" ] && log_finalize "$FINAL_STATUS" "$FINAL_MESSAGE"' EXIT

# Function to parse JSON data (pure bash implementation)
parse_json() {
	local path="$1"
	local data="$POST_DATA"

    # Handle simple paths like .device
    if [[ $path =~ ^\.([a-zA-Z0-9_]+)$ ]]; then
	    local field="${BASH_REMATCH[1]}"
	    echo "$data" | sed -n 's/.*"'"$field"'":\s*"\([^"]*\)".*/\1/p'
	    # Handle array[index].field
    elif [[ $path =~ ^\.([a-zA-Z0-9_]+)\[([0-9]+)\]\.([a-zA-Z0-9_]+)$ ]]; then
	    local idx="${BASH_REMATCH[2]}"
	    local field="${BASH_REMATCH[3]}"

	# Use awk to extract the specific array element and field
	echo "$data" | awk -F'[{}]' -v idx="$idx" -v field="$field" '
	{
		# Split by {}, each even index after the first [ is an object
		count = 0
		for (i=1; i<=NF; i++) {
			if ($i ~ /^\s*"enabled"/) {
				if (count == idx) {
					# Found our object, extract the field
					obj = $i
					if (match(obj, "\"" field "\":[^,}]*")) {
						val = substr(obj, RSTART, RLENGTH)
						gsub(/.*:/, "", val)
						gsub(/[",]/, "", val)
						gsub(/^[ \t]+|[ \t]+$/, "", val)
						print val
						exit
					}
				}
				count++
			}
		}
	}'
	# Handle array length
elif [[ $path =~ ^\.([a-zA-Z0-9_]+)\s*\|\s*length$ ]]; then
	echo "8"
    fi
}

# Helper function to extract hex values from descriptor output
extract_hex_value() {
	local desc="$1"
	local field="$2"
	echo "$desc" | sed -n "s/.*${field}[[:space:]]*=[[:space:]]*\(0x[0-9a-fA-F]*\).*/\1/p" | head -n 1
}

# Function to escape string for JSON (pure bash implementation)
escape_json_string() {
	local str="$1"
	str=$(echo "$str" | sed 's/\x1b\[[0-9;]*[mGKHF]//g' | tr -d '\000-\010\013\014\016-\037')
	str="${str//\\/\\\\}"
	str="${str//\"/\\\"}"
	str="${str//$'\n'/\\n}"
	str="${str//$'\r'/\\r}"
	str="${str//$'\t'/\\t}"
	echo "\"$str\""
}

# Function to modify binary config file
modify_config_binary() {
	local offset=$1
	local value=$2
	local num_bytes=${3:-1}

    # Convert value to hex bytes
    local hex_value
    hex_value=$(printf "%0$((num_bytes*2))x" "$value")

    # Use dd to write bytes at offset in big-endian format
    local i
    for ((i=0; i<num_bytes; i++)); do
	    local byte_hex="${hex_value:$((i*2)):2}"
	    local current_offset=$((offset + i))
	    printf '%b' "\\x$byte_hex" | dd of="$CONFIG_FILE" bs=1 seek="$current_offset" count=1 conv=notrunc 2>/dev/null
    done
}

# Function to get UFS version
get_ufs_version() {
	local dev_desc
	dev_desc=$(ufs-utils desc -t 0 -p "$UFS_DEVICE" 2>&1)

	if [[ $dev_desc =~ wSpecVersion\ =\ 0x([0-9a-fA-F]+) ]]; then
		local spec_version="${BASH_REMATCH[1]}"
		local version_num=$((16#$spec_version))

	# Check if >= 3.1 (0x0310)
	if [ $version_num -ge 784 ]; then
		echo "3.1+"
	else
		echo "3.0-"
	fi
else
	echo "3.0-"  # Default to older version
	fi
}

# Function to calculate LU offset based on UFS version
get_lu_offset() {
	local lu_num=$1
	local ufs_version=$2
	local base_offset

	if [ "$ufs_version" = "3.1+" ]; then
		# UFS 3.1+ : Device descriptor (0x16 bytes) + LU descriptor size (0x1a bytes per LU)
		base_offset=$((0x16))
		echo $((base_offset + lu_num * 0x1a))
	else
		# UFS < 3.1 : Device descriptor (0x10 bytes) + LU descriptor size (0x14 bytes per LU)
		base_offset=$((0x10))
		echo $((base_offset + lu_num * 0x14))
	fi
}

# Function to write LU configuration
write_lu_config() {
	local lu_num=$1
	local enabled=$2
	local alloc_units=$3
	local boot_lun_id=$4
	local write_protect=$5
	local memory_type=$6
	local ufs_version=$7

	local lu_offset
	lu_offset=$(get_lu_offset "$lu_num" "$ufs_version")

    # Defensive: if LU is disabled, force allocation to zero
    if [ "$enabled" -eq 0 ]; then
	    alloc_units=0
    fi

    # Log only for enabled LUs
    if [ "$enabled" -eq 1 ]; then
	    log_message "LU$lu_num: $alloc_units units, boot=$boot_lun_id"
    fi

    # bLUEnable (offset + 0x0)
    modify_config_binary "$lu_offset" "$enabled" 1

    # bBootLunID (offset + 0x1)
    modify_config_binary $((lu_offset + 1)) "$boot_lun_id" 1

    # bLUWriteProtect (offset + 0x2)
    modify_config_binary $((lu_offset + 2)) "$write_protect" 1

    # bMemoryType (offset + 0x3)
    modify_config_binary $((lu_offset + 3)) "$memory_type" 1

    # dNumAllocUnits (offset + 0x4, 4 bytes big endian)
    modify_config_binary $((lu_offset + 4)) "$alloc_units" 4

}

# Function to query device configuration
query_device() {
	# Initialize logging for query operation
	if [ -f "$SCRIPT_DIR/flash_logger.sh" ]; then
		CURRENT_LOG_FILE=$(log_init "ufs_config_query" "ufs")
		if [ -n "$CURRENT_LOG_FILE" ] && [ -w "$CURRENT_LOG_FILE" ]; then
			LOGGING_ENABLED=1
			log_banner "UFS CONFIGURATION - QUERY"
			log_info "=== UFS Configuration Query Started ==="
		fi
	fi

    # Parse device from QUERY_STRING if provided (GET request)
    if [ -n "$QUERY_STRING" ]; then
	    local query_device="${QUERY_STRING#device=}"
	    query_device="${query_device%%&*}"  # Remove any additional params
	    query_device=$(echo "$query_device" | sed 's/%2F/\//g')  # Decode URL encoding
	    [ -n "$query_device" ] && UFS_DEVICE="$query_device"
    fi

    command -v ufs-utils &> /dev/null || { echo '{"status":"error","message":"Required tools not found: ufs-utils. Please install them."}'; exit 1; }
    [[ "$UFS_DEVICE" =~ $ALLOWED_DEVICE_PATTERN ]] && [ -e "$UFS_DEVICE" ] || { echo "{\"status\":\"error\",\"message\":\"Invalid or missing UFS device: $UFS_DEVICE\"}"; exit 1; }

    log_message "Querying UFS device: $UFS_DEVICE"

    # Query Device Descriptor (Type 0)
    local device_desc
    if ! device_desc=$(ufs-utils desc -t 0 -p "$UFS_DEVICE" 2>&1); then
	    if [ "$LOGGING_ENABLED" = "1" ]; then
		    log_error "Failed to query device descriptor"
	    fi
	    echo "{\"status\":\"error\",\"message\":\"Failed to query device descriptor\"}"
	    exit 1
    fi

    # Query Geometry Descriptor (Type 7)
    local geometry_desc
    if ! geometry_desc=$(ufs-utils desc -t 7 -p "$UFS_DEVICE" 2>&1); then
	    if [ "$LOGGING_ENABLED" = "1" ]; then
		    log_error "Failed to query geometry descriptor"
	    fi
	    echo "{\"status\":\"error\",\"message\":\"Failed to query geometry descriptor\"}"
	    exit 1
    fi

    # Query Configuration Descriptor (Type 1)
    local config_desc
    if ! config_desc=$(ufs-utils desc -t 1 -p "$UFS_DEVICE" 2>&1); then
	    if [ "$LOGGING_ENABLED" = "1" ]; then
		    log_error "Failed to query configuration descriptor"
	    fi
	    echo "{\"status\":\"error\",\"message\":\"Failed to query configuration descriptor\"}"
	    exit 1
    fi

    # Get UFS version from device descriptor
    local spec_version
    spec_version=$(echo "$device_desc" | sed -n 's/.*wSpecVersion[[:space:]]*=[[:space:]]*0x\([0-9a-fA-F]*\).*/\1/p' | head -n 1)
    local version_str="Unknown"
    if [ -n "$spec_version" ]; then
	    local major=$((16#${spec_version:0:2}))
	    local minor=$((16#${spec_version:2:2}))
	    version_str="$major.$minor"
    fi

    # Parse device descriptor fields (keep as hex strings for frontend)
    local boot_enable
    boot_enable=$(extract_hex_value "$device_desc" "bBootEnable")
    local boot_lun_id
    boot_lun_id=$(extract_hex_value "$device_desc" "bBootLunID")

    # Parse geometry descriptor (keep as hex strings)
    local segment_size
    segment_size=$(extract_hex_value "$geometry_desc" "dSegmentSize")
    local alloc_unit_size
    alloc_unit_size=$(extract_hex_value "$geometry_desc" "bAllocationUnitSize")
    local total_capacity
    total_capacity=$(extract_hex_value "$geometry_desc" "qTotalRawDeviceCapacity")

    # Build config object with LU0-LU7 structure
    local config_json="{"
    config_json="$config_json\"bBootEnable\":\"${boot_enable:-0x0}\","
    config_json="$config_json\"bBootLunID\":\"${boot_lun_id:-0x0}\","

    # Parse LUN configurations and build LU0-LU7 objects
    for lu in {0..7}; do
	    # Extract LU descriptor section (remove arbitrary limit)
	    local lu_section
	    lu_section=$(echo "$config_desc" | sed -n "/Config $lu Unit Descriptor:/,/Config $((lu+1)) Unit Descriptor:/p")

	    if [ -z "$lu_section" ]; then
		    log_message "Warning: No data found for LU$lu"
	    fi

	    local lu_enable
	    lu_enable=$(extract_hex_value "$lu_section" "bLUEnable")
	    local lu_boot_id
	    lu_boot_id=$(extract_hex_value "$lu_section" "bBootLunID")
	    local num_alloc
	    num_alloc=$(extract_hex_value "$lu_section" "dNumAllocUnits")
	    local mem_type
	    mem_type=$(extract_hex_value "$lu_section" "bMemoryType")
	    local write_protect
	    write_protect=$(extract_hex_value "$lu_section" "bLUWriteProtect")

	# Add LU object to config
	config_json="$config_json\"LU$lu\":{"
	config_json="$config_json\"bLUEnable\":\"${lu_enable:-0x0}\","
	config_json="$config_json\"bBootLunID\":\"${lu_boot_id:-0x0}\","
	config_json="$config_json\"dNumAllocUnits\":\"${num_alloc:-0x0}\","
	config_json="$config_json\"bMemoryType\":\"${mem_type:-0x0}\","
	config_json="$config_json\"bLUWriteProtect\":\"${write_protect:-0x0}\""
	config_json="$config_json},"
done
config_json="${config_json%,}}"  # Remove trailing comma

    # Build geometry object (hex strings)
    local geometry_json="{"
    geometry_json="$geometry_json\"qTotalRawDeviceCapacity\":\"${total_capacity:-0x0}\","
    geometry_json="$geometry_json\"dSegmentSize\":\"${segment_size:-0x2000}\","
    geometry_json="$geometry_json\"bAllocationUnitSize\":\"${alloc_unit_size:-0x1}\""
    geometry_json="$geometry_json}"

    # Escape raw output for JSON (pure bash implementation)
    local config_raw
    config_raw=$(escape_json_string "$config_desc")
    local geom_raw
    geom_raw=$(escape_json_string "$geometry_desc")

    # Build final JSON response matching ufs_query.sh format
    cat <<EOF
{
  "status": "success",
  "device": "$UFS_DEVICE",
  "version": "$version_str",
  "config": $config_json,
  "geometry": $geometry_json,
  "raw_config": $config_raw,
  "raw_geometry": $geom_raw
}
EOF
FINAL_STATUS="SUCCESS"
FINAL_MESSAGE="UFS configuration query completed"
exit 0
}

# Main execution for write
main() {
	# Initialize logging for write operation
	if [ -f "$SCRIPT_DIR/flash_logger.sh" ]; then
		CURRENT_LOG_FILE=$(log_init "ufs_config_write" "ufs")
		if [ -n "$CURRENT_LOG_FILE" ] && [ -w "$CURRENT_LOG_FILE" ]; then
			LOGGING_ENABLED=1
			log_banner "UFS CONFIGURATION - WRITE"
			log_info "=== UFS Configuration Write Started ==="
		fi
	fi

	command -v ufs-utils &> /dev/null || { echo '{"status":"error","message":"Required tools not found: ufs-utils. Please install them."}'; exit 1; }

	log_message "POST data length: ${#POST_DATA} bytes"

    # Parse device path from POST data
    local device
    device=$(parse_json '.device')
    [ -n "$device" ] && UFS_DEVICE="$device"

    [[ "$UFS_DEVICE" =~ $ALLOWED_DEVICE_PATTERN ]] && [ -e "$UFS_DEVICE" ] || { echo "{\"status\":\"error\",\"message\":\"Invalid or missing UFS device: $UFS_DEVICE\"}"; exit 1; }

    log_message "Configuring UFS device: $UFS_DEVICE"

    # Verify device is accessible
    if [ ! -r "$UFS_DEVICE" ]; then
	    if [ "$LOGGING_ENABLED" = "1" ]; then
		    log_error "Cannot read UFS device: $UFS_DEVICE"
	    fi
	    echo "{\"status\":\"error\",\"message\":\"Cannot read UFS device: $UFS_DEVICE. Check permissions or device path.\"}"
	    exit 1
    fi
    if [ ! -w "$UFS_DEVICE" ]; then
	    if [ "$LOGGING_ENABLED" = "1" ]; then
		    log_error "Cannot write to UFS device: $UFS_DEVICE"
	    fi
	    echo "{\"status\":\"error\",\"message\":\"Cannot write to UFS device: $UFS_DEVICE. Check permissions (may need root access).\"}"
	    exit 1
    fi

    # Get UFS version
    local ufs_version
    ufs_version=$(get_ufs_version)
    log_message "UFS Version: $ufs_version"

    # Read current configuration descriptor
    log_message "Reading current configuration..."
    local read_output
    read_output=$(ufs-utils desc -t 1 -D "$CONFIG_FILE" -p "$UFS_DEVICE" 2>&1)

    # Check if file was actually created with content (ignore exit code - ufs-utils may return non-zero even on success)
    if [ ! -f "$CONFIG_FILE" ] || [ ! -s "$CONFIG_FILE" ]; then
	    log_message "Read failed - file not created or empty"
	    if [ "$LOGGING_ENABLED" = "1" ]; then
		    log_error "Failed to read current configuration descriptor"
	    fi
	    local escaped_error
	    escaped_error=$(escape_json_string "$read_output")
	    echo "{\"status\":\"error\",\"message\":\"Failed to read current configuration descriptor\",\"details\":$escaped_error}"
	    exit 1
    fi

    log_message "Configuration read successfully to $CONFIG_FILE ($(stat -c%s "$CONFIG_FILE") bytes)"

    # CRITICAL: Enable bBootEnable in Device Descriptor (offset 0x3)
    # Without this, device rejects any boot LUN configuration
    log_message "Enabling bBootEnable in Device Descriptor"
    if ! printf '\x01' | dd of="$CONFIG_FILE" bs=1 seek=3 count=1 conv=notrunc 2>/dev/null; then
	    if [ "$LOGGING_ENABLED" = "1" ]; then
		    log_error "Failed to enable bBootEnable in configuration file"
	    fi
	    echo "{\"status\":\"error\",\"message\":\"Failed to enable bBootEnable in configuration file\"}"
	    exit 1
    fi

    # Parse and configure each LU
    local lu_count
    lu_count=$(parse_json '.luns | length')

    # Fallback: UFS always has 8 LUs
    if [ -z "$lu_count" ] || [ "$lu_count" -eq 0 ]; then
	    lu_count=8
	    log_message "Using default lu_count=8 (parse_json failed)"
    fi

    log_message "lu_count result: '$lu_count'"
    log_message "POST data for debug: ${POST_DATA:0:300}"
    log_message "Processing $lu_count LUs from JSON"

    for ((i=0; i<lu_count; i++)); do
	    log_message "=== LOOP ITERATION: i=$i of $lu_count ==="
	    local enabled
	    local alloc_units
	    local boot_lun_id
	    local write_protect
	    local memory_type

	    enabled=$(parse_json ".luns[$i].enabled")
	    alloc_units=$(parse_json ".luns[$i].allocUnits")
	    boot_lun_id=$(parse_json ".luns[$i].bootLunId")
	    write_protect=$(parse_json ".luns[$i].writeProtect")
	    memory_type=$(parse_json ".luns[$i].memoryType")

	    log_message "LU$i raw parsed: enabled='$enabled' alloc='$alloc_units' boot='$boot_lun_id'"

	# Convert boolean to 0/1
	[ "$enabled" = "true" ] && enabled=1 || enabled=0

	log_message "LU$i after conversion: enabled=$enabled alloc=$alloc_units"

	# Set defaults
	alloc_units=${alloc_units:-0}
	boot_lun_id=${boot_lun_id:-0}
	write_protect=${write_protect:-0}
	memory_type=${memory_type:-0}

	# For disabled LUs, force all config fields to zero to avoid stale/invalid configs
	if [ "$enabled" -eq 0 ]; then
		alloc_units=0
		boot_lun_id=0
		write_protect=0
		memory_type=0
	fi

	# Validate input ranges
	if [ "$memory_type" -gt 6 ] || [ "$memory_type" -lt 0 ]; then
		if [ "$LOGGING_ENABLED" = "1" ]; then
			log_error "Invalid memory type for LU$i: $memory_type"
		fi
		echo "{\"status\":\"error\",\"message\":\"Invalid memory type for LU$i: $memory_type (must be 0-6)\"}"
		exit 1
	fi
	if [ "$boot_lun_id" -gt 2 ] || [ "$boot_lun_id" -lt 0 ]; then
		if [ "$LOGGING_ENABLED" = "1" ]; then
			log_error "Invalid boot LUN ID for LU$i: $boot_lun_id"
		fi
		echo "{\"status\":\"error\",\"message\":\"Invalid boot LUN ID for LU$i: $boot_lun_id (must be 0-2)\"}"
		exit 1
	fi
	if [ "$write_protect" -gt 2 ] || [ "$write_protect" -lt 0 ]; then
		if [ "$LOGGING_ENABLED" = "1" ]; then
			log_error "Invalid write protect value for LU$i: $write_protect"
		fi
		echo "{\"status\":\"error\",\"message\":\"Invalid write protect value for LU$i: $write_protect (must be 0-2)\"}"
		exit 1
	fi

	write_lu_config "$i" "$enabled" "$alloc_units" "$boot_lun_id" "$write_protect" "$memory_type" "$ufs_version"
done

    # Capture hex dump of modified config for verification (BEFORE writing to device)
    local lu0_offset
    lu0_offset=$(get_lu_offset "0" "$ufs_version")
    local lu1_offset
    lu1_offset=$(get_lu_offset "1" "$ufs_version")

    # Save modified config to debug location BEFORE device write
    mkdir -p /tmp/ufs_debug
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)

    local debug_file="/tmp/ufs_debug/ufsconfig_modified_${timestamp}.bin"

    log_message "CONFIG_FILE is: $CONFIG_FILE"
    log_message "CONFIG_FILE exists: $([ -f "$CONFIG_FILE" ] && echo yes || echo no)"
    log_message "CONFIG_FILE size: $(stat -c%s "$CONFIG_FILE" 2>/dev/null || echo 0) bytes"

    if ! cp "$CONFIG_FILE" "$debug_file" 2>&1; then
	    log_message "ERROR: Failed to copy $CONFIG_FILE to $debug_file"
    else
	    log_message "Successfully copied to $debug_file"
    fi

    # Capture hex dumps for verification - use debug file since it's guaranteed to exist
    local lu0_hex
    lu0_hex=$(hexdump -C -s "$lu0_offset" -n 10 "$debug_file" 2>/dev/null | head -n 1 | cut -d'|' -f1 | cut -c11-)
    local lu1_hex
    lu1_hex=$(hexdump -C -s "$lu1_offset" -n 10 "$debug_file" 2>/dev/null | head -n 1 | cut -d'|' -f1 | cut -c11-)

    log_message "Modified config saved to: $debug_file"
    log_message "LU0 at 0x$(printf '%x' "$lu0_offset"): $lu0_hex"
    log_message "LU1 at 0x$(printf '%x' "$lu1_offset"): $lu1_hex"

    # Write configuration back to device
    log_message "Writing configuration to device..."
    local write_output
    write_output=$(ufs-utils desc -t 1 -w "$CONFIG_FILE" -p "$UFS_DEVICE" 2>&1)
    local write_status=$?

    if [ $write_status -ne 0 ]; then
	    log_message "Write failed with status $write_status: $write_output"
	    if [ "$LOGGING_ENABLED" = "1" ]; then
		    log_error "Write failed with status $write_status: $write_output"
	    fi
	    # Build simple error response without complex escaping
	    cat <<EOF
{"status":"error","message":"Failed to write configuration. Check server logs for details."}
EOF
exit 1
    fi

    # Success response with verification data
    log_message "Write successful"
    if [ "$LOGGING_ENABLED" = "1" ]; then
	    log_success "UFS configuration written successfully"
    fi

    # Escape hex dumps for JSON (remove problematic characters)
    local lu0_escaped
    lu0_escaped=$(echo "$lu0_hex" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | tr -d '\n\r')
    local lu1_escaped
    lu1_escaped=$(echo "$lu1_hex" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | tr -d '\n\r')

    printf '{"status":"success","message":"UFS configuration written successfully. Please reboot to apply changes.","device":"%s","verification":{"lu0_offset":"0x%x","lu0_hex":"%s","lu1_offset":"0x%x","lu1_hex":"%s","debug_file":"%s"}}' "$UFS_DEVICE" "$lu0_offset" "$lu0_escaped" "$lu1_offset" "$lu1_escaped" "$debug_file"
    FINAL_STATUS="SUCCESS"
    FINAL_MESSAGE="UFS configuration written successfully"
    exit 0
}

# Route based on request method
case "$REQUEST_METHOD" in
	GET)
		query_device
		;;
	POST)
		main
		;;
	*)
		echo "{\"status\":\"error\",\"message\":\"Method not allowed: $REQUEST_METHOD\"}"
		exit 1
		;;
esac
