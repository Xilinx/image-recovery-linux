#!/bin/sh
# Copyright (c) 2025 - 2026 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

# Flash Update Logger - Provides comprehensive logging for flash operations

# Log directory and file configuration
LOG_BASE_DIR="/var/log/image_recovery"
CURRENT_LOG_FILE=""

# Initialize logging for a new flash session
log_init() {
	local operation_type="$1"
	local recovery_type="$2"
	local preserve_mode="$3"
	local log_subdir

	# Create log directory if it doesn't exist, fallback to /tmp if /var/log fails
	if ! mkdir -p "$LOG_BASE_DIR" 2>/dev/null; then
		LOG_BASE_DIR="/tmp/image_recovery"
		mkdir -p "$LOG_BASE_DIR" 2>/dev/null
	fi

	# Create subdirectory for recovery type
	log_subdir="$LOG_BASE_DIR/${recovery_type}_recovery"
	mkdir -p "$log_subdir" 2>/dev/null

	# Generate log filename
	CURRENT_LOG_FILE="$log_subdir/${operation_type}.log"

	# If preserve mode and log exists, append to it (flash operations)
	if [ "$preserve_mode" = "preserve" ] && [ -f "$CURRENT_LOG_FILE" ]; then
		# Log exists from upload/selection, append to it
		echo "$CURRENT_LOG_FILE"
		return 0
	fi

	# Overwrite the log file (new upload/selection session)
	> "$CURRENT_LOG_FILE"

	# Return log file path
	echo "$CURRENT_LOG_FILE"
}

# Log a message with level
# level: INFO, WARN, ERROR, SUCCESS, PROGRESS
log_msg() {
	local level="$1"
	shift
	local message="$*"

	if [ -n "$CURRENT_LOG_FILE" ]; then
		echo "[$level] $message" >> "$CURRENT_LOG_FILE"
	fi
}

# Log info message
log_info() {
	log_msg "INFO" "$@"
}

# Log warning message
log_warn() {
	log_msg "WARN" "$@"
}

# Log error message
log_error() {
	log_msg "ERROR" "$@"
}

# Log success message
log_success() {
	log_msg "SUCCESS" "$@"
}

# Log progress update
log_progress() {
	log_msg "PROGRESS" "$@"
}

# Add a banner to separate different operations
log_banner() {
	local title="$1"

	if [ -n "$CURRENT_LOG_FILE" ]; then
		{
			echo ""
			echo "========================================================================"
			echo "  $title"
			echo "========================================================================"
		} >> "$CURRENT_LOG_FILE"
	fi
}

# Finalize log
log_finalize() {
	local final_status="$1"
	local final_message="$2"

	if [ -n "$CURRENT_LOG_FILE" ]; then
		echo "[FINAL] Status: $final_status - $final_message" >> "$CURRENT_LOG_FILE"
		chmod 644 "$CURRENT_LOG_FILE" 2>/dev/null
	fi
}
