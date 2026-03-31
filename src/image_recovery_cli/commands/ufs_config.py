# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

"""UFS device configuration command"""

import os
import re
import sys
import json
import shutil
import tempfile
from datetime import datetime
from .. import utils


def setup_parser(subparsers):
    """Setup argument parser for ufs-config command."""
    parser = subparsers.add_parser('ufs-config', help='Configure UFS device')
    parser.add_argument('--device', default='/dev/bsg/ufs-bsg0',
                        help='UFS device path (e.g., /dev/bsg/ufs-bsg0)')
    parser.add_argument('--query', nargs='?', const='ufs_config_query.json', metavar='OUTPUT_JSON',
                        help='Query current UFS configuration and save to JSON file (optional: specify output file path)')
    parser.add_argument('--write', metavar='CONFIG_JSON',
                        help='Write configuration from JSON file')
    parser.set_defaults(func=run)
    return parser


def run_ufs_utils(args):
    """Run ufs-utils command"""
    try:
        return utils.run_command(args, check=False)
    except FileNotFoundError:
        raise RuntimeError("ufs-utils not found. Install ufs-utils package.")


def extract_hex_value(desc_text, field_name):
    """Extract hex value from descriptor output"""
    pattern = rf'{field_name}\s*=\s*(0x[0-9a-fA-F]+)'
    match = re.search(pattern, desc_text)
    if match:
        return match.group(1)
    return None


def hex_to_dec(hex_str):
    """Convert hex string to decimal"""
    if not hex_str:
        return 0
    hex_str = hex_str.strip()
    return int(hex_str, 16) if hex_str.startswith('0x') else int(hex_str) if hex_str.isdigit() else 0


def get_ufs_version(device):
    """Get UFS version from device descriptor"""
    result = run_ufs_utils(['ufs-utils', 'desc', '-t', '0', '-p', device])
    if result.returncode != 0:
        return "3.0-"

    spec_version = extract_hex_value(result.stdout, 'wSpecVersion')
    if spec_version and hex_to_dec(spec_version) >= 784:  # 0x0310 = UFS 3.1
        return "3.1+"
    return "3.0-"


def get_lu_offset(lu_num, ufs_version):
    """Calculate LU offset based on UFS version"""
    if ufs_version == "3.1+":
        return 0x16 + lu_num * 0x1a  # UFS 3.1+: base 0x16, LU size 0x1a
    return 0x10 + lu_num * 0x14      # UFS 3.0: base 0x10, LU size 0x14


def modify_config_binary(config_file, offset, value, num_bytes=1):
    """Modify binary config file at specified offset"""
    try:
        with open(config_file, 'r+b') as f:
            f.seek(offset)
            f.write(value.to_bytes(num_bytes, byteorder='big'))
        return True
    except Exception as e:
        utils.error_msg(f"Error modifying config at offset {offset}: {e}")
        return False


def write_lu_config(config_file, lu_num, enabled, alloc_units, boot_lun_id,
                    write_protect, memory_type, ufs_version):
    """Write LU configuration to binary file"""
    lu_offset = get_lu_offset(lu_num, ufs_version)

    if not enabled:
        alloc_units = 0
    elif enabled:
        utils.info_msg(f"LU{lu_num}: {alloc_units} units, boot={boot_lun_id}")

    modify_config_binary(config_file, lu_offset, 1 if enabled else 0, 1)
    modify_config_binary(config_file, lu_offset + 1, boot_lun_id, 1)
    modify_config_binary(config_file, lu_offset + 2, write_protect, 1)
    modify_config_binary(config_file, lu_offset + 3, memory_type, 1)
    modify_config_binary(config_file, lu_offset + 4, alloc_units, 4)


def query_device(device):
    """Query UFS device configuration"""
    utils.info_msg(f"Querying UFS device: {device}")

    # Query Device Descriptor (Type 0)
    result = run_ufs_utils(['ufs-utils', 'desc', '-t', '0', '-p', device])
    if result.returncode != 0:
        utils.error_msg(f"Failed to query device descriptor: {result.stderr}")
        return None
    device_desc = result.stdout

    # Query Configuration Descriptor (Type 1)
    result = run_ufs_utils(['ufs-utils', 'desc', '-t', '1', '-p', device])
    if result.returncode != 0:
        utils.error_msg(f"Failed to query configuration descriptor: {result.stderr}")
        return None
    config_desc = result.stdout

    # Parse version
    spec_version = extract_hex_value(device_desc, 'wSpecVersion')
    version_str = "Unknown"
    if spec_version:
        version_num = hex_to_dec(spec_version)
        major = (version_num >> 8) & 0xFF
        minor = version_num & 0xFF
        version_str = f"{major}.{minor}"

    # Parse LUN configurations
    luns = []
    for lu in range(8):
        # Extract LU section from config descriptor
        pattern = rf'Config {lu} Unit Descriptor:(.*?)(?=Config {lu+1} Unit Descriptor:|$)'
        match = re.search(pattern, config_desc, re.DOTALL)

        if match:
            lu_section = match.group(1)

            lu_enable_hex = extract_hex_value(lu_section, 'bLUEnable')
            lu_boot_id_hex = extract_hex_value(lu_section, 'bBootLunID')
            num_alloc_hex = extract_hex_value(lu_section, 'dNumAllocUnits')
            mem_type_hex = extract_hex_value(lu_section, 'bMemoryType')
            write_protect_hex = extract_hex_value(lu_section, 'bLUWriteProtect')

            lu_enable = hex_to_dec(lu_enable_hex)

            lun_config = {
                'enabled': lu_enable == 1,
                'bootLunId': hex_to_dec(lu_boot_id_hex),
                'allocUnits': hex_to_dec(num_alloc_hex),
                'memoryType': hex_to_dec(mem_type_hex),
                'writeProtect': hex_to_dec(write_protect_hex)
            }
            luns.append(lun_config)
        else:
            # Default empty LU
            luns.append({
                'enabled': False,
                'bootLunId': 0,
                'allocUnits': 0,
                'memoryType': 0,
                'writeProtect': 0
            })

    return {
        'status': 'success',
        'device': device,
        'version': version_str,
        'luns': luns
    }


def write_device_config(device, config_data):
    """Write configuration to UFS device"""
    utils.info_msg(f"Configuring UFS device: {device}")

    # Get UFS version
    ufs_version = get_ufs_version(device)
    utils.info_msg(f"UFS Version: {ufs_version}")

    # Create temp file for configuration
    with tempfile.NamedTemporaryFile(mode='wb', delete=False, suffix='.bin') as tmp:
        config_file = tmp.name

    try:
        # Read current configuration descriptor to file
        utils.info_msg("Reading current configuration...")
        result = run_ufs_utils(['ufs-utils', 'desc', '-t', '1', '-D', config_file, '-p', device])

        if not os.path.exists(config_file) or os.path.getsize(config_file) == 0:
            utils.error_msg("Failed to read configuration descriptor")
            return False

        file_size = os.path.getsize(config_file)
        utils.success_msg(f"Configuration read successfully ({file_size} bytes)")

        # Enable bBootEnable in Device Descriptor (offset 0x3)
        utils.info_msg("Enabling bBootEnable in Device Descriptor")
        modify_config_binary(config_file, 0x3, 1, 1)

        # Parse and configure each LU
        luns = config_data.get('luns', [])
        utils.info_msg(f"Processing {len(luns)} LUs from configuration")

        for i, lun in enumerate(luns):
            enabled = lun.get('enabled', False)
            alloc_units = lun.get('allocUnits', 0)
            boot_lun_id = lun.get('bootLunId', 0)
            write_protect = lun.get('writeProtect', 0)
            memory_type = lun.get('memoryType', 0)

            # For disabled LUs, force all fields to zero
            if not enabled:
                alloc_units = 0
                boot_lun_id = 0
                write_protect = 0
                memory_type = 0

            # Validate input ranges
            if not 0 <= memory_type <= 6:
                utils.error_msg(f"Invalid memory type for LU{i}: {memory_type} (must be 0-6)")
                return False
            if not 0 <= boot_lun_id <= 2:
                utils.error_msg(f"Invalid boot LUN ID for LU{i}: {boot_lun_id} (must be 0-2)")
                return False
            if not 0 <= write_protect <= 2:
                utils.error_msg(f"Invalid write protect for LU{i}: {write_protect} (must be 0-2)")
                return False

            write_lu_config(config_file, i, enabled, alloc_units, boot_lun_id,
                          write_protect, memory_type, ufs_version)

        # Save debug copy
        debug_dir = "/tmp/ufs_debug"
        os.makedirs(debug_dir, exist_ok=True)
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        debug_file = f"{debug_dir}/ufsconfig_modified_{timestamp}.bin"
        shutil.copy2(config_file, debug_file)
        utils.info_msg(f"Modified config saved to: {debug_file}")

        # Write configuration back to device
        utils.info_msg("Writing configuration to device...")
        result = run_ufs_utils(['ufs-utils', 'desc', '-t', '1', '-w', config_file, '-p', device])

        if result.returncode != 0:
            utils.error_msg(f"Write failed: {result.stderr}")
            return False

        utils.success_msg("Configuration written successfully")
        utils.warning_msg("Please reboot to apply changes")
        return True

    finally:
        # Cleanup temp file
        if os.path.exists(config_file):
            os.remove(config_file)


def run(args):
    """Configure UFS device"""
    if os.geteuid() != 0:
        utils.error_msg("This command requires root privileges")
        return 1

    if not re.match(utils.UFS_DEVICE_PATTERN, args.device):
        utils.error_msg(f"Invalid device path: {args.device}")
        utils.info_msg("Expected format: /dev/bsg/ufs-bsg[0-9]+")
        return 1

    if not os.path.exists(args.device):
        utils.error_msg(f"Device not found: {args.device}")
        return 1

    try:
        if args.query:
            result = query_device(args.device)
            if result:
                # Save to JSON file
                try:
                    with open(args.query, 'w') as f:
                        json.dump(result, f, indent=2)
                    utils.success_msg(f"Query results saved to: {os.path.abspath(args.query)}")
                except Exception as e:
                    utils.error_msg(f"Error saving to file: {e}")
                    return 1
            return 0 if result else 1

        elif args.write:
            if not os.path.exists(args.write):
                utils.error_msg(f"Config file not found: {args.write}")
                return 1

            with open(args.write, 'r') as f:
                config_data = json.load(f)

            return 0 if write_device_config(args.device, config_data) else 1

        else:
            utils.error_msg("Must specify either --query or --write")
            return 1

    except Exception as e:
        utils.error_msg(str(e))
        return 1
