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

        # Handle EEPROM device selection (single or multiple)
        selected_eeprom = utils.prompt_device_selection(eeprom_files, "EEPROM")
        if selected_eeprom is None:
            return {'error': 'Operation cancelled by user'}

        result = utils.run_command(
            ['ipmi-fru', f'--fru-file={selected_eeprom}', '--interpret-oem-data'],
            check=False
        )

        output = (result.stdout + '\n' + result.stderr).strip()
        if result.returncode != 0:
            details = output or f'exit code {result.returncode}'
            return {'error': f'ipmi-fru failed: {details}'}

        fru_errors = []
        board_decode_failed = False
        other_areas = ('product info area', 'multirecord', 'multi-record', 'multi record', 'oem')
        for line in output.splitlines():
            line = line.strip()
            if line.startswith('FRU Error:'):
                detail = line.split(':', 1)[1].strip() or 'Unspecified FRU decode error'
                if detail not in fru_errors:
                    fru_errors.append(detail)
                if not detail.lower().startswith(other_areas):
                    board_decode_failed = True
        if board_decode_failed:
            return {'error': 'Failed to decode FRU information: ' + '; '.join(fru_errors)}

        product_name = product_revision = uuid = None
        board_info_present = False

        for line in result.stdout.split('\n'):
            line = line.strip()
            if line.startswith('FRU Board ') and ':' in line:
                board_info_present = True

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

        if not board_info_present:
            return {'error': 'No FRU board information returned by ipmi-fru.'}

        info = {
            'product_name': product_name or 'Not Available',
            'product_revision': product_revision or 'Not Available',
            'uuid': uuid or 'Not Available'
        }
        if fru_errors:
            info['warnings'] = fru_errors
        return info

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

        def get_bank_status_str(status_hex):
            if status_hex == 'fc':
                return 'Bootable (Accepted - All images valid)'
            elif status_hex == 'fe':
                return 'Bootable (Valid - Some images unaccepted)'
            elif status_hex == 'ff':
                return 'Non-bootable (Invalid - One or more images corrupted or partially overwritten)'
            else:
                return 'Non-bootable (Unknown status)'

        return {
            'bank_a_status': get_bank_status_str(bank_a_status),
            'bank_b_status': get_bank_status_str(bank_b_status),
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
    platform = utils.detect_platform()
    if platform != 'zynqmp':
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
        for warning in fru_info.get('warnings', []):
            utils.warning_msg(f'FRU decode warning: {warning}')
    print("="*60 + "\n")

    return 0
