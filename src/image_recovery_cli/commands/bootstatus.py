#!/usr/bin/env python3
# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

"""Boot status information module"""

import re
import glob
from pathlib import Path
from typing import Any, Dict
from .. import utils


def read_mtd_crc(device: str) -> str:
    """Read CRC value from MTD device version string"""
    try:
        if not Path(device).exists():
            return "Not Available"

        data = utils.read_binary_file(device, count=4 * 1024 * 1024)
        strings_list = utils.extract_strings(data)

        for line in strings_list:
            if 'Version=' in line:
                match = re.search(r'SW_CRC=([0-9a-fA-F]+)', line, re.IGNORECASE)
                if match:
                    return match.group(1)
    except Exception:
        pass

    return "Not Available"


def _parse_uuid_from_hex(hex_bytes: list) -> str:
    """Convert hex bytes list to UUID format"""
    if len(hex_bytes) != 16 or not all('h' in b for b in hex_bytes):
        return None

    clean = ''.join(b.replace('h', '') for b in hex_bytes)
    return f"{clean[0:8]}-{clean[8:12]}-{clean[12:16]}-{clean[16:20]}-{clean[20:32]}".upper()


def get_fru_info() -> Dict[str, Any]:
    """Get FRU information including product name, revision, and UUID"""
    try:
        eeprom_files = glob.glob(utils.EEPROM_DEVICE_PATTERN)
        if not eeprom_files:
            return {'error': 'No EEPROM devices found'}

        result = utils.run_command(
            ['ipmi-fru', f'--fru-file={eeprom_files[0]}', '--interpret-oem-data'],
            check=False
        )

        if result.returncode != 0:
            return {'error': f'ipmi-fru command failed: {result.stderr}'}

        product_name = product_revision = uuid = None

        for line in result.stdout.split('\n'):
            line = line.strip()

            if 'FRU Board Product Name:' in line:
                product_name = line.split(':', 1)[1].strip()
            elif 'FRU Board Custom Info:' in line:
                custom_info = line.split(':', 1)[1].strip()

                # First simple custom info is the revision
                if not product_revision and len(custom_info) <= 10 and 'h' not in custom_info:
                    product_revision = custom_info
                # 16-byte hex sequence is the UUID
                elif not uuid:
                    uuid = _parse_uuid_from_hex(custom_info.split())

        return {
            'product_name': product_name or 'Not Available',
            'product_revision': product_revision or 'Not Available',
            'uuid': uuid or 'Not Available'
        }

    except FileNotFoundError:
        return {'error': 'ipmi-fru command not found. Install freeipmi package.'}
    except RuntimeError as e:
        return {'error': str(e)}
    except Exception as e:
        return {'error': f'Failed to get FRU information: {e}'}


def get_boot_status() -> Dict[str, Any]:
    """Get boot status and version information"""
    try:
        if not Path(utils.MTD_METADATA).exists():
            return {'error': f'MTD metadata device not found: {utils.MTD_METADATA}'}

        metadata = utils.read_binary_file(utils.MTD_METADATA, count=256)

        bank_a_status = utils.hexdump_value(metadata, offset=0x18, length=1)
        bank_b_status = utils.hexdump_value(metadata, offset=0x19, length=1)
        active_bank = utils.hexdump_value(metadata, offset=0x8, length=4, format_type='int')
        prev_active_bank = utils.hexdump_value(metadata, offset=0xC, length=4, format_type='int')

        return {
            'bank_a_status': 'active' if bank_a_status == 'fc' else 'inactive',
            'bank_b_status': 'active' if bank_b_status == 'fc' else 'inactive',
            'active_bank': 'A' if active_bank == 0 else 'B',
            'previous_bank': 'A' if prev_active_bank == 0 else 'B'
        }

    except Exception as e:
        return {'error': f'Failed to read boot status: {e}'}


def setup_parser(subparsers):
    """Setup argument parser for bootstatus command."""
    parser = subparsers.add_parser('bootstatus', help='Show boot status information')
    parser.set_defaults(func=run)
    return parser


def run(args):
    """Execute the bootstatus command"""
    # Get boot status
    boot_status = get_boot_status()
    if 'error' in boot_status:
        utils.error_msg(boot_status['error'])
        return 1

    # Display boot status
    print("\n" + "="*60)
    print("Boot Status")
    print("="*60)
    utils.info_msg(f"Bank A Status: {boot_status['bank_a_status']}")
    utils.info_msg(f"Bank B Status: {boot_status['bank_b_status']}")
    utils.success_msg(f"Active Bank: {boot_status['active_bank']}")
    utils.info_msg(f"Previous Bank: {boot_status['previous_bank']}")

    # Display CRC values
    print("\n" + "-"*60)
    print("Bank CRC Values")
    print("-"*60)
    utils.info_msg(f"Bank A CRC: {read_mtd_crc(utils.MTD_BANK_A)}")
    utils.info_msg(f"Bank B CRC: {read_mtd_crc(utils.MTD_BANK_B)}")

    # Display FRU information
    print("\n" + "-"*60)
    print("FRU Information")
    print("-"*60)
    fru_info = get_fru_info()
    if 'error' in fru_info:
        utils.warning_msg(fru_info['error'])
    else:
        utils.info_msg(f"Product Name: {fru_info['product_name']}")
        utils.info_msg(f"Product Revision: {fru_info['product_revision']}")
        utils.info_msg(f"UUID: {fru_info['uuid']}")
    print("="*60 + "\n")

    return 0
