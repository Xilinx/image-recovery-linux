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
XIH_IHT_LEN = 0x80                     # Versal Image Header Table length
XIH_IHT_LEN_VERSAL_2VE_2VM = 0x80      # Gen 2 also has a 128-byte IHT; IDs 1/2 follow
IHT_LAYOUTS = (
    (IHT_OFFSET_DEFAULT, XIH_IHT_LEN),
    (IHT_OFFSET_VERSAL_2VE_2VM, XIH_IHT_LEN_VERSAL_2VE_2VM),
)
OPTIONAL_DATA_READ_SIZE = 8192         # Include Gen 2 device data before version records
OPTIONAL_DATA_CHECKSUM_SIZE = 4

# Boot header magic identifiers - platform-specific offsets
BOOT_SYNC_WORD = b'\x66\x55\x99\xaa'   # Xilinx boot header sync word (0xAA995566 in LE)
BOOT_XNLX_MAGIC = b'XNLX'              # Xilinx identifier magic
BOOT_HEADER_OFFSETS = [
    (0x20, 0x24),  # ZynqMP: (sync_offset, xnlx_offset)
    (0x10, 0x14),  # Versal/versal_2ve_2vm : (sync_offset, xnlx_offset)
]

OPT_DATA_ID_DESCRIPTION = 0x21         # Component description
OPT_DATA_ID_VERSION = 0x22             # Component/application version
OPT_DATA_ID_TOOLS_VERSION = 0x23       # Xilinx tools release version
OPT_DATA_ID_BUILD_ID = 0x24            # Optional automation build ID
OPT_DATA_ID_VIVADO_VERSION = 0x25      # Component manifest containing Vivado version
OPT_DATA_ID_LEGACY_VERSION = 0x21      # Version ID used by older images
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


# Temporary workaround for ZynqMP multiboot register issue
def clear_multiboot_register() -> bool:
    """
    Clear the ZynqMP multiboot register by writing to firmware configuration register.

    Writes to address 0xffca0010 with mask 0xfffffff and value 0x0.
    This clears the multiboot register values.

    Returns:
        bool: True if successful, False otherwise
    """
    config_reg_path = '/sys/firmware/zynqmp/config_reg'

    # Multiboot register clearing via PMU config_reg is only applicable to ZynqMP
    if detect_platform() != 'zynqmp':
        return False

    if not os.path.exists(config_reg_path):
        return False

    # Write configuration: address mask value
    # Address: 0xffca0010 (multiboot register)
    # Mask: 0xfffffff (bits to modify)
    # Value: 0x0 (clear the register)
    config_data = "0xffca0010 0xfffffff 0x0\n"

    try:
        with open(config_reg_path, 'w') as f:
            f.write(config_data)
    except OSError as e:
        warning_msg(f"Failed to clear multiboot register: {e}")
        return False

    info_msg("Multiboot register cleared successfully")
    return True


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


def get_current_device_id() -> Optional[str]:
    """
    Read the device ID from /proc/device-tree/device_id.

    Returns:
        str: Device ID (e.g., 'xck24', 'xcve2802', 'xc2ve3858') or None if not found
    """
    try:
        with open('/proc/device-tree/device_id', 'r') as f:
            device_id = f.read().strip().rstrip('\x00').lower()
            return device_id if device_id else None
    except (FileNotFoundError, PermissionError, IOError):
        return None


def extract_device_id_from_boot_bin(file_path: str) -> List[str]:
    """
    Extract device identifiers from boot.bin file by searching for device ID patterns.

    Args:
        file_path: Path to the boot.bin file

    Returns:
        List of device IDs found in the boot.bin (e.g., ['xck24', 'xck26'])
    """
    device_ids = []
    device_id_patterns = [
        # Versal 2 family
        r'xc2ve\d+[a-z]*',    # e.g., xc2ve3858
        r'xc2vp\d+[a-z]*',    # e.g., xc2vp3602
        # Versal family
        r'xcvc\d+[a-z]*',     # e.g., xcvc1902
        r'xcvh\d+[a-z]*',     # e.g., xcvh1582
        r'xcvp\d+[a-z]*',     # e.g., xcvp1202, xcvp1802
        r'xcve\d+[a-z]*',     # e.g., xcve2802
        r'xcvr\d+[a-z]*',     # e.g., xcvr1602, xcvr1652
        r'xcvm\d+[a-z]*',     # e.g., xcvm1802
        # ZynqMP family
        r'xck\d+[a-z]*',      # e.g., xck24, xck26
        r'xczu\d+[a-z]*',     # e.g., xczu7ev, xczu9eg
    ]

    try:
        with open(file_path, 'rb') as f:
            # Read the boot.bin file
            data = f.read()

        # Extract printable strings from the binary
        strings_list = extract_strings(data)

        # Search for device ID patterns in strings
        for string in strings_list:
            string_lower = string.lower()
            for pattern in device_id_patterns:
                matches = re.findall(pattern, string_lower)
                for match in matches:
                    if match not in device_ids:
                        device_ids.append(match)

    except Exception as e:
        error_msg(f"Failed to extract device ID from boot.bin: {e}")

    return device_ids


def get_device_family(device_id: str) -> Optional[str]:
    """
    Determine the device family from a device ID.

    Args:
        device_id: Device ID string (e.g., 'xck24', 'xcve2802')

    Returns:
        str: Device family ('zynqmp', 'versal', 'versal-2ve-2vm') or None
    """
    if not device_id:
        return None

    device_id_lower = device_id.lower()

    if device_id_lower.startswith('xc2ve') or \
       device_id_lower.startswith('xc2vp'):
        return 'versal-2ve-2vm'

    if device_id_lower.startswith(('xcvc', 'xcvh', 'xcvp', 'xcve')) or \
       device_id_lower.startswith('xcvr') or \
       device_id_lower.startswith('xcvm'):
        return 'versal'

    if device_id_lower.startswith('xck') or \
       device_id_lower.startswith('xczu'):
        return 'zynqmp'

    return None


def check_hardware_compatibility(file_path: str) -> Tuple[bool, Optional[str]]:
    """
    Check if the boot.bin file is compatible with the current hardware platform.
    Performs exact device ID matching - boot.bin must be built for the specific
    hardware device.

    Args:
        file_path: Path to the boot.bin file

    Returns:
        tuple: (is_compatible, error_message) - error_message is None if compatible
    """
    current_device_id = get_current_device_id()

    if not current_device_id:
        warning_msg(
            "Could not read device ID from /proc/device-tree/device_id, "
            "skipping hardware compatibility check"
        )
        return True, None

    boot_device_ids = extract_device_id_from_boot_bin(file_path)

    if not boot_device_ids:
        return False, (
            "Cannot verify hardware compatibility: "
            "Could not extract device ID from boot.bin. "
            "Boot.bin may be corrupted or built without device metadata."
        )

    if current_device_id in boot_device_ids:
        info_msg(
            f"Hardware compatibility check passed: {current_device_id} "
            f"matches boot.bin device ID"
        )
        return True, None

    # Device ID mismatch - provide detailed error
    current_family = get_device_family(current_device_id)
    boot_families = [get_device_family(dev_id) for dev_id in boot_device_ids]
    boot_families_unique = ', '.join(sorted(set([f for f in boot_families if f])))
    boot_ids_str = ', '.join(boot_device_ids)

    return False, (
        f"Hardware compatibility mismatch: "
        f"Current device is '{current_device_id}' ({current_family}), "
        f"but boot.bin is for '{boot_ids_str}' ({boot_families_unique}). "
        f"This boot.bin cannot be flashed on this hardware - it may corrupt the boot process."
    )


def validate_boot_bin(file_path: str) -> Tuple[bool, Optional[str]]:
    """
    Validate if a file is a valid boot.bin by checking for Xilinx boot header
    and hardware compatibility.
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
            if not _has_valid_boot_header(f):
                # No valid pattern found
                return False, (
                    "Invalid boot.bin, boot.bin was corrupted boot image"
                )

        # Check hardware compatibility
        is_compatible, compatibility_error = check_hardware_compatibility(
            file_path
        )
        if not is_compatible:
            return False, compatibility_error

        return True, None

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
EEPROM_I2C_ADDRESS = '0054'


def find_eeprom_devices():
    """
    Find all available I2C EEPROM devices on the system.
    Searches for EEPROM at I2C address 0x0054 on all buses.

    Returns:
        list: List of EEPROM device paths (e.g., ['/sys/bus/i2c/devices/0-0054/eeprom'])
              Empty list if no EEPROM devices found
    """
    import glob

    i2c_base = '/sys/bus/i2c/devices'

    if not os.path.exists(i2c_base):
        return []

    # Search for EEPROM at address 0x0054 on all I2C buses
    pattern = f'{i2c_base}/*-{EEPROM_I2C_ADDRESS}/eeprom'
    devices = glob.glob(pattern)

    # Sort numerically by bus number to ensure correct ordering
    # (lexicographic sort would put bus 10 before bus 2)
    def extract_bus_number(path):
        match = re.search(r'/(\d+)-\w+/eeprom$', path)
        return int(match.group(1)) if match else 0

    return sorted(devices, key=extract_bus_number)


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
    # Sort numerically by device number to ensure correct ordering
    # (lexicographic sort would put ufs-bsg10 before ufs-bsg2)
    def extract_device_number(path):
        match = re.search(r'ufs-bsg(\d+)$', path)
        return int(match.group(1)) if match else 0

    return sorted(valid_devices, key=extract_device_number)


def prompt_device_selection(devices: List[str], device_type: str) -> Optional[str]:
    """
    Prompt user to select a device from a list.
    Auto-selects first device in non-interactive environments (no TTY) or when
    IMAGE_MGMT_AUTO_SELECT environment variable is set.

    Args:
        devices: List of device paths to choose from
        device_type: Type of device for display (e.g., 'UFS', 'EEPROM')

    Returns:
        Selected device path, or None if cancelled or no devices available
    """
    if not devices:
        return None

    # Single device - auto-select
    if len(devices) == 1:
        info_msg(f"Auto-selected {device_type} device (only one available): {devices[0]}")
        return devices[0]

    # Check for non-interactive mode (environment variable or no TTY)
    auto_select = os.getenv('IMAGE_MGMT_AUTO_SELECT', 'false').lower() in ('true', '1', 'yes')
    has_tty = sys.stdin.isatty()

    if auto_select or not has_tty:
        selected = devices[0]
        reason = "env variable set" if auto_select else "no TTY detected"
        info_msg(f"Auto-selected {device_type} device ({reason}): {selected}")
        return selected

    # Interactive mode - prompt user
    info_msg(f"Found {len(devices)} {device_type} devices:")
    print("  0. Exit/Cancel")
    for idx, device in enumerate(devices, 1):
        print(f"  {idx}. {device}")

    while True:
        try:
            choice = input(f"Select {device_type} device (enter number, 0 to exit): ").strip()
            if not choice:
                warning_msg("Please enter a number")
                continue

            device_num = int(choice)
            if device_num == 0:
                info_msg("Operation cancelled by user")
                return None
            elif 1 <= device_num <= len(devices):
                selected = devices[device_num - 1]
                success_msg(f"Selected: {selected}")
                return selected
            else:
                warning_msg(f"Invalid choice. Enter 1-{len(devices)} to select, or 0 to cancel")
        except ValueError:
            warning_msg("Please enter a valid number")
        except (EOFError, KeyboardInterrupt):
            info_msg("\nOperation cancelled by user")
            return None


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
