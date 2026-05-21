# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

"""Version command - reads version information from MTD devices"""

import os
import struct
from .. import utils


def setup_parser(subparsers):
    """Setup argument parser for version command."""
    parser = subparsers.add_parser('version', help='Show version information')
    parser.add_argument('--type', choices=['recovery', 'selector', 'bank-a', 'bank-b', 'all'],
                        default='all', help='Version type to query')
    parser.set_defaults(func=run)
    return parser


def extract_bootgen_version(device_path, platform='default'):
    """
    Extract version string from bootgen optional data fields.
    Platform is auto-detected from /proc/device-tree/family.
    """
    try:
        # Auto-detect platform
        if platform == 'default':
            platform = utils.detect_platform()

        # Select IHT offset based on platform
        # versal_2ve_2vm uses 0x2D0, default (Versal/ZynqMP) uses 0xC4
        iht_offset_addr = utils.IHT_OFFSET_VERSAL_2VE_2VM if platform == 'versal_2ve_2vm' else utils.IHT_OFFSET_DEFAULT

        # Step 1: Read IHT offset (4 bytes, little-endian)
        # For Versal: at 0xC4, for Versal2: at 0x2D0
        iht_bytes = utils.read_binary_file(device_path, iht_offset_addr, 4)
        iht_offset = struct.unpack('<I', iht_bytes)[0]

        # Step 2: Calculate optional data offset (IHT offset + 0x80)
        opt_data_offset = iht_offset + utils.XIH_IHT_LEN

        # Step 3: Read optional data section (read up to 2KB)
        opt_data = utils.read_binary_file(device_path, opt_data_offset, 2048)

        # Step 4: Search for optional data ID 0x21 (version string)
        offset = 0
        while offset < len(opt_data) - 4:
            # Read optional data header (4 bytes: 2-byte ID + 2-byte length)
            # Format: [ID (2 bytes, LE)][Length in words (2 bytes, LE)]
            data_id = struct.unpack('<H', opt_data[offset:offset+2])[0]
            length_words = struct.unpack('<H', opt_data[offset+2:offset+4])[0]
            length_bytes = length_words * 4

            # Sanity check - length includes the 4-byte header
            if length_bytes < 4 or length_bytes > 2048:
                break

            # Check if this is the version string entry
            if data_id == utils.OPT_DATA_ID_VERSION:
                # Version string starts 4 bytes after header
                version_start = offset + 4
                version_end = version_start + min(utils.MAX_VERSION_LENGTH, length_bytes - 4)

                if version_end > len(opt_data):
                    version_end = len(opt_data)

                # Extract and decode version string (null-terminated)
                version_bytes = opt_data[version_start:version_end]
                version_str = version_bytes.split(b'\x00')[0].decode('utf-8', errors='ignore')

                # Split on newline and take first line to remove garbage
                version_str = version_str.split('\n')[0].strip()

                # Remove any non-printable characters
                version_str = ''.join(c for c in version_str if c.isprintable())

                return utils.clean_version_metadata(version_str)

            # Move to next optional data entry
            # Length includes the header, so just add length_bytes
            offset += length_bytes

        return None

    except Exception as e:
        utils.error_msg(f"Failed to extract bootgen version from {device_path}: {e}")
        return None


def get_version(version_type):
    """Get version information from MTD device"""
    platform = utils.detect_platform()

    # Determine device and label based on type
    if version_type == 'recovery':
        device = utils.MTD_RECOVERY
        label = "Image Recovery Application"
        ver_type = 'recovery'
    elif version_type == 'selector':
        device = utils.MTD_SELECTOR
        label = "Image Selector Application"
        ver_type = 'selector'
    elif version_type == 'bank-a':
        device = utils.MTD_BANK_A
        label = "Bank A image ver"
        ver_type = 'bank'
    elif version_type == 'bank-b':
        device = utils.MTD_BANK_B
        label = "Bank B image ver"
        ver_type = 'bank'
    else:
        return (f"Error: Unknown version type: {version_type}", None)

    # Check if device exists
    if not os.path.exists(device):
        return (label, "Not Available")

    version = None

    if platform == 'zynqmp':
        version = utils.extract_version_from_offset(device)
    else:
        # Modern platforms: use optional data extraction
        version = extract_bootgen_version(device, platform)

    if not version:
        try:
            data = utils.read_binary_file(device, offset=0, count=2097152)
            strings_list = utils.extract_strings(data)
            version = utils.extract_version_from_strings(strings_list, version_type=ver_type)
        except Exception as e:
            utils.error_msg(f"Failed to extract version from strings for {device}: {e}")

    if version:
        return (label, version)
    else:
        return (label, "No version information found")


def run(args):
    """Show version information from MTD devices"""

    types_to_query = []

    if args.type == 'all':
        types_to_query = ['recovery', 'selector', 'bank-a', 'bank-b']
    else:
        types_to_query = [args.type]

    results = []

    for version_type in types_to_query:
        label, version = get_version(version_type)
        results.append((label, version))

    print("\n" + "="*60)
    print("Version Information")
    print("="*60)
    for label, version in results:
        utils.info_msg(f"{label}: {version}")
    print("="*60 + "\n")

    return 0
