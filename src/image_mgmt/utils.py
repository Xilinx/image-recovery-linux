# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

"""Common utilities and helper functions"""

import os
import re
import sys
import struct
import subprocess
import tempfile
from typing import Any, List, Optional, Tuple


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

# Boot header magic identifiers - platform-specific offsets
BOOT_SYNC_WORD = b'\x66\x55\x99\xaa'   # Xilinx boot header sync word (0xAA995566 in LE)
BOOT_XNLX_MAGIC = b'XNLX'              # Xilinx identifier magic
BOOT_HEADER_OFFSETS = [
    (0x20, 0x24),  # ZynqMP: (sync_offset, xnlx_offset)
    (0x10, 0x14),  # Versal/versal_2ve_2vm : (sync_offset, xnlx_offset)
]

OPT_DATA_ID_VERSION = 0x21             # Optional data ID for version string
MAX_VERSION_LENGTH = 128               # Maximum version string length
VERSION_STRING_OFFSET = 0x70
VERSION_STRING_SIZE = 0x24


def detect_platform():
    """Auto-detect platform type from device tree."""
    try:
        with open('/proc/device-tree/family', 'r') as f:
            family = f.read().strip().lower()

        # Check if it's Versal 2 variant (Versal_2VE_2VM)
        if 'versal_2ve_2vm' in family.replace('-', '_'):
            return 'versal_2ve_2vm'

        if 'zynqmp' in family:
            return 'zynqmp'

        if 'versal' in family:
            return 'versal'
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


def _has_valid_boot_header(f) -> bool:
    """
    Check if an open file object contains a valid Xilinx boot header.
    Supports both ZynqMP and Versal/versal_2ve_2vm header formats.

    Args:
        f: Open file object (binary mode) positioned anywhere

    Returns:
        bool: True if a valid boot header is found, False otherwise
    """
    # Try each known header offset pattern
    for sync_offset, xnlx_offset in BOOT_HEADER_OFFSETS:
        # Check sync word
        f.seek(sync_offset)
        sync_bytes = f.read(len(BOOT_SYNC_WORD))

        if len(sync_bytes) < len(BOOT_SYNC_WORD):
            continue  # Try next pattern

        # Check XNLX magic
        f.seek(xnlx_offset)
        xnlx_bytes = f.read(len(BOOT_XNLX_MAGIC))

        if len(xnlx_bytes) < len(BOOT_XNLX_MAGIC):
            continue  # Try next pattern

        # If both match, it's a valid boot header
        if sync_bytes == BOOT_SYNC_WORD and xnlx_bytes == BOOT_XNLX_MAGIC:
            return True

    return False


def validate_boot_bin(file_path: str) -> Tuple[bool, Optional[str]]:
    """
    Validate if a file is a valid boot.bin by checking for Xilinx boot header.
    Supports both ZynqMP and Versal/versal_2ve_2vm  header formats.

    Args:
        file_path: Path to the boot.bin file to validate

    Returns:
        tuple: (is_valid, error_message) - error_message is None if valid
    """
    try:
        # Check file size
        file_size = os.path.getsize(file_path)
        if file_size < 40:  # Minimum size to contain any header variant
            return False, "File too small to be a valid boot.bin (minimum 40 bytes required)"

        with open(file_path, 'rb') as f:
            if _has_valid_boot_header(f):
                return True, None

            # No valid pattern found
            return False, "Invalid boot.bin, boot.bin was corrupted boot image"

    except Exception as e:
        return False, f"Failed to validate boot.bin: {e}"


def validate_bank_image(mtd_device: str) -> Tuple[bool, Optional[str]]:
    """
    Validate if an MTD bank contains a valid boot image by checking for Xilinx boot header.
    Supports both ZynqMP and Versal/versal_2ve_2vm  header formats.

    Args:
        mtd_device: Path to the MTD device (e.g., /dev/mtd11 for Bank A)

    Returns:
        tuple: (is_valid, error_message) - error_message is None if valid
    """
    try:
        with open(mtd_device, 'rb') as f:
            if _has_valid_boot_header(f):
                return True, None

            # Check if bank is empty by scanning first 4KB
            f.seek(0)
            check_size = 4096  # 4KB should be sufficient and efficient
            leading_region = f.read(check_size)

            if len(leading_region) > 0:
                # Bank is empty only if the entire leading region is uniformly erased (0xFF) or zero (0x00)
                is_all_erased = all(b == 0xFF for b in leading_region)
                is_all_zero = all(b == 0x00 for b in leading_region)

                if is_all_erased or is_all_zero:
                    return False, "Bank is empty (contains no boot image)"

            # Not empty but no valid header found
            return False, "Bank contains corrupted or invalid boot image"

    except FileNotFoundError:
        return False, f"MTD device not found: {mtd_device}"
    except PermissionError:
        return False, f"Permission denied reading {mtd_device}"
    except Exception as e:
        return False, f"Failed to validate bank: {e}"


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


def find_ufs_devices():
    """
    Find all available UFS BSG devices on the system.

    Returns:
        list: List of UFS device paths (e.g., ['/dev/bsg/ufs-bsg0'])
              Empty list if no UFS devices found
    """
    import glob

    ufs_devices = glob.glob('/dev/bsg/ufs-bsg*')
    valid_devices = [
        device for device in ufs_devices
        if re.match(UFS_DEVICE_PATTERN, device)
    ]
    # Sort to ensure consistent ordering
    return sorted(valid_devices)


def get_default_ufs_device():
    """
    Get the default UFS device to use.

    Returns:
        str: Path to default UFS device, or None if no UFS devices found
    """
    devices = find_ufs_devices()
    return devices[0] if devices else None


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


def clean_version_metadata(version_str: str) -> str:
    """Remove metadata markers and cleanup version string."""
    if not version_str:
        return None

    # Handle Version= prefix - split on semicolon first, then remove prefix
    if 'Version=' in version_str:
        if ';' in version_str:
            version_str = version_str.split(';', 1)[1]
        version_str = version_str.replace('Version=', '')

    # Remove metadata fields (CRC=, SW_HDR_SHA256=, etc.)
    tokens = version_str.split()
    clean_tokens = []
    for token in tokens:
        if '=' in token:
            break
        if token.upper() in ['CRC', 'SW_CRC', 'SHA256', 'SW_HDR_SHA256', 'CHECKSUM']:
            break
        clean_tokens.append(token)

    version_str = ' '.join(clean_tokens).strip()
    return version_str if version_str else None


def extract_version_from_offset(device_path: str, offset: int = VERSION_STRING_OFFSET,
                                 size: int = VERSION_STRING_SIZE) -> str:
    """Extract version string from fixed offset in boot image."""
    try:
        data = read_binary_file(device_path, offset=offset, count=size)

        if not data or len(data) < size:
            return None

        null_idx = data.find(b'\x00')
        if null_idx > 0:
            version_str = data[:null_idx].decode('utf-8', errors='ignore').strip()
        else:
            version_str = data.decode('utf-8', errors='ignore').strip()

        if version_str and all(c.isprintable() or c.isspace() for c in version_str):
            version_str = ' '.join(version_str.split())
            return version_str if version_str else None

        return None
    except Exception as e:
        error_msg(f"Failed to extract version from {device_path} at offset {offset:#x}: {e}")
        return None


def extract_version_from_strings(strings_list: List[str], version_type: str = 'default') -> str:
    """Extract version string from list of strings."""
    for line in strings_list:
        line_stripped = line.strip()

        if len(line_stripped) < 3:
            continue

        line_cleaned = ''.join(c if c.isprintable() or c.isspace() else '' for c in line_stripped).strip()
        if not line_cleaned or len(line_cleaned) < 3:
            continue

        if 'Version=' in line_cleaned:
            version = clean_version_metadata(line_cleaned)
            if version:
                return version

        match = re.search(r'^(.+)-v(\d+(?:\.\d+)*)$', line_cleaned, re.IGNORECASE)
        if match:
            full_string = match.group(0)
            if '-' in full_string and len(full_string) > 5:
                return full_string

        match = re.search(r'(\S+-(?:imgrcvry|bootfw|recovery|selector)-v\d+(?:\.\d+)?)', line_cleaned, re.IGNORECASE)
        if match:
            return match.group(1)

        if '-v' in line_cleaned.lower() and len(line_cleaned) > 10:
            if line_cleaned.count('-') >= 3:
                return line_cleaned

        if version_type != 'active-bank':
            match = re.match(r'^(\d+\.\d+(?:\.\d+)?(?:\+git)?)$', line_cleaned)
            if match:
                version = match.group(1).replace('+git', '')
                return version

        if version_type != 'active-bank':
            match = re.search(r'/usr/src/debug/[^/\s]+/(\d{4}\.\d+(?:\+git)?)/', line_cleaned)
            if match:
                return match.group(1).replace('+git', '')

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
