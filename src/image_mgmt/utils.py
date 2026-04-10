# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

"""Common utilities and helper functions"""

import os
import re
import sys
import struct
import subprocess
import tempfile
from typing import Any, List


def info_msg(message: str):
    """Print info message"""
    print(f"[INFO] {message}")


def success_msg(message: str):
    """Print success message"""
    print(f"[SUCCESS] {message}")


def error_msg(message: str):
    """Print error message to stderr"""
    print(f"[ERROR] {message}", file=sys.stderr)


def warning_msg(message: str):
    """Print warning message"""
    print(f"[WARNING] {message}")


def progress_msg(percentage: int, message: str, show_bar: bool = True):
    """Print progress message with progress bar"""
    if show_bar:
        bar_width = 40
        filled = int(bar_width * percentage / 100)
        bar = '#' * filled + '-' * (bar_width - filled)
        print(f"[{bar}] {percentage:3d}% - {message}")
    else:
        print(f"[PROGRESS] {message}")


def step_msg(step: str, total: str, message: str):
    """Print step message (e.g., Step 1/3: ...)"""
    print(f"[Step {step}/{total}] {message}")


# Bootgen Optional Data Field Constants
IHT_OFFSET_DEFAULT = 0xC4              # Image Header Table offset (default: Versal/ZynqMP)
IHT_OFFSET_VERSAL_2VE_2VM = 0x2D0      # Image Header Table offset for Versal_2VE_2VM
XIH_IHT_LEN = 0x80                     # Image Header Table length (128 bytes)
XLNX_IDENTIFIER_OFFSET = 0x14          # Boot header "XNLX" identifier offset
OPT_DATA_ID_VERSION = 0x21             # Optional data ID for version string
MAX_VERSION_LENGTH = 128               # Maximum version string length


def detect_platform():
    """Auto-detect platform type from device tree."""
    try:
        with open('/proc/device-tree/family', 'r') as f:
            family = f.read().strip().lower()

        # Check if it's Versal 2 variant (Versal_2VE_2VM)
        if 'versal_2ve_2vm' in family.replace('-', '_'):
            return 'versal_2ve_2vm'
    except (FileNotFoundError, PermissionError, IOError):
        pass

    # Default (covers Versal, ZynqMP, and any unknown platforms - uses 0xC4)
    return 'default'


def run_command(cmd: List[str], check: bool = True, capture_output: bool = True) -> subprocess.CompletedProcess:
    """Run a shell command and return the result."""
    try:
        result = subprocess.run(
            cmd,
            check=check,
            capture_output=capture_output,
            text=True
        )
        return result
    except subprocess.CalledProcessError as e:
        raise RuntimeError(f"Command failed: {' '.join(cmd)}\n{e.stderr}")


def check_root_privileges() -> bool:
    """Check if running with root privileges."""
    return os.geteuid() == 0


def read_binary_file(path, offset=0, count=None):
    """
    Read binary file from specific offset
    """
    try:
        with open(path, 'rb') as f:
            f.seek(offset)
            if count:
                return f.read(count)
            return f.read()
    except Exception as e:
        raise RuntimeError(f"Failed to read {path}: {e}")


def hexdump_value(data, offset=0, length=4, format_type='hex'):
    """
    Extract hex value from binary data
    """
    try:
        value_bytes = data[offset:offset + length]
        if format_type == 'int':
            return int.from_bytes(value_bytes, byteorder='little')
        else:
            return value_bytes.hex()
    except Exception as e:
        raise ValueError(f"Failed to extract hex value: {e}")


# MTD device lookup by partition name
_MTD_NAME_CACHE = None


def _parse_mtd_partitions():
    """
    Parse /proc/mtd and return a dictionary mapping partition names to device paths.
    Returns: dict of {partition_name: device_path}
    """
    mtd_map = {}
    try:
        with open('/proc/mtd', 'r') as f:
            lines = f.readlines()
            for line in lines[1:]:  # Skip header
                # Format: mtdX: size erasesize "name"
                parts = line.split()
                if len(parts) >= 4:
                    dev_num = parts[0].rstrip(':').replace('mtd', '')
                    name = ' '.join(parts[3:]).strip('"')
                    mtd_map[name] = f"/dev/mtd{dev_num}"
    except Exception:
        pass
    return mtd_map


def get_mtd_device(partition_name: str) -> str:
    """
    Get MTD device path by partition name.
    """
    global _MTD_NAME_CACHE

    # Load cache on first use
    if _MTD_NAME_CACHE is None:
        _MTD_NAME_CACHE = _parse_mtd_partitions()

    return _MTD_NAME_CACHE.get(partition_name)


# Public MTD device path accessors (dynamically resolved from /proc/mtd)
MTD_SELECTOR = get_mtd_device("Image Selector") or "/dev/mtd1"
MTD_RECOVERY = get_mtd_device("Image Recovery") or "/dev/mtd4"
MTD_METADATA = get_mtd_device("SystemReady-DT Update Metadata") or "/dev/mtd6"
MTD_METADATA_BACKUP = get_mtd_device("SystemReady-DT Update Metadata Backup") or "/dev/mtd7"
MTD_BANK_A = get_mtd_device("Bank A Space") or "/dev/mtd11"
MTD_BANK_B = get_mtd_device("Bank B Space") or "/dev/mtd14"

# EEPROM device path pattern
EEPROM_DEVICE_PATTERN = "/sys/bus/i2c/devices/*/eeprom"

# UFS device path pattern
UFS_DEVICE_PATTERN = r'^/dev/bsg/ufs-bsg[0-9]+$'


def print_progress(percentage: int, message: str):
    """Print progress update (wrapper for backward compatibility)"""
    progress_msg(percentage, message)


def extract_strings(data: bytes) -> List[str]:
    """Extract printable strings from binary data."""
    try:
        # Use strings command for better compatibility
        with tempfile.NamedTemporaryFile(delete=False, mode='wb') as tmp:
            tmp_file = tmp.name
            tmp.write(data)

        result = run_command(['strings', tmp_file], check=False)

        os.remove(tmp_file)

        if result.returncode == 0:
            return result.stdout.splitlines()

    except Exception:
        pass

    return []


def extract_version_from_strings(strings_list: List[str], version_type: str = 'default') -> str:
    """Extract version string from list of strings."""

    # Try bootfw pattern first (for active-bank)
    if version_type == 'active-bank':
        for line in strings_list:
            if re.search(r'amd-edf-.*-bootfw-v[0-9]', line):
                return line

    # Try Version= pattern
    for line in strings_list:
        if 'Version=' in line:
            # Remove everything up to and including first semicolon
            if ';' in line:
                line = line.split(';', 1)[1]
            # Clean up
            line = line.replace('Version=', '')
            line = line.replace(';', ' ')
            line = line.replace('SW_CRC', 'CRC')
            return line.strip()

    # Try simple version pattern (not for active-bank)
    if version_type != 'active-bank':
        for line in strings_list:
            # Match pattern like "1.2.3" or "1.2.3+git"
            match = re.match(r'^(\d+\.\d+(?:\+git)?)$', line.strip())
            if match:
                version = match.group(1)
                # Remove +git suffix
                version = version.replace('+git', '')
                return version

    return None


# Metadata Management Functions

def read_metadata():
    """Read metadata from MTD device"""
    try:
        with open(MTD_METADATA, 'rb') as f:
            return f.read(256)
    except Exception as e:
        raise RuntimeError(f"Failed to read MTD metadata: {e}")


def get_active_bank(metadata):
    """Get active bank from metadata"""
    # Active bank is at offset 0x8 (4 bytes, little-endian)
    active_bank = struct.unpack('<I', metadata[0x8:0xC])[0]
    return active_bank


def get_bank_status(metadata, bank):
    """Get status of specified bank (0=Bank A, 1=Bank B)"""
    # Bank A status at 0x18, Bank B status at 0x19
    status_offset = 0x18 if bank == 0 else 0x19
    return metadata[status_offset]


def calculate_and_update_crc32(metadata_file):
    """Calculate and update CRC32 for metadata file.

    This follows the same logic as cal_crc32.sh:
    - Extract bytes 4-123 (120 bytes) from metadata
    - Calculate CRC32
    - Write CRC32 as little-endian to first 4 bytes
    - Flash to both metadata and metadata backup partitions
    """
    import binascii

    info_msg("Calculating CRC32 for metadata")

    try:
        # Read metadata file
        with open(metadata_file, 'rb') as f:
            metadata = f.read()

        if len(metadata) < 124:
            raise RuntimeError("Metadata file too short")

        # Extract bytes for CRC calculation (skip first 4 bytes, read 120 bytes)
        crc_data = metadata[4:124]

        # Calculate CRC32
        crc32_value = binascii.crc32(crc_data) & 0xFFFFFFFF

        success_msg(f"Calculated CRC32: 0x{crc32_value:08x}")

        # Write CRC32 as little-endian to first 4 bytes
        with open(metadata_file, 'r+b') as f:
            f.seek(0)
            f.write(struct.pack('<I', crc32_value))

        success_msg("CRC32 updated in metadata file")

        # Erase both metadata partitions first
        for mtd_device, description in [(MTD_METADATA, "Metadata"),
                                         (MTD_METADATA_BACKUP, "Metadata Backup")]:
            info_msg(f"Erasing {description} partition {mtd_device}")
            result = run_command(['flash_eraseall', mtd_device], check=False)
            if result.returncode != 0:
                raise RuntimeError(f"Failed to erase {mtd_device}: {result.stderr}")

        # Flash updated metadata to both partitions
        for mtd_device, description in [(MTD_METADATA, "Metadata"),
                                         (MTD_METADATA_BACKUP, "Metadata Backup")]:
            info_msg(f"Flashing {description} to {mtd_device}")
            result = run_command(['flashcp', metadata_file, mtd_device], check=False)
            if result.returncode != 0:
                raise RuntimeError(f"Failed to flash metadata to {mtd_device}: {result.stderr}")
            success_msg(f"{description} flashed successfully")

        return True

    except Exception as e:
        raise RuntimeError(f"Failed to calculate/update CRC32: {e}")
