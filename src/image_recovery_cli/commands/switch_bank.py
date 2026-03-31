# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

"""Switch active bank command - manually select Bank A or Bank B as active"""

import os
import sys
import struct
import tempfile
from .. import utils


def setup_parser(subparsers):
    """Setup argument parser for switch-bank command."""
    parser = subparsers.add_parser('switch-bank', help='Switch active boot bank')
    parser.add_argument('bank', choices=['a', 'b', 'A', 'B', '0', '1'],
                        help='Target bank to activate (a/A/0 for Bank A, b/B/1 for Bank B)')
    parser.set_defaults(func=run)
    return parser


def update_metadata(metadata_file, target_bank):
    """Update metadata to switch to target bank"""
    target_name = 'A' if target_bank == 0 else 'B'
    utils.info_msg(f"Updating metadata to switch to Bank {target_name}")

    # Read current metadata
    with open(metadata_file, 'rb') as f:
        metadata = f.read()

    # Check target bank status
    target_status = utils.get_bank_status(metadata, target_bank)
    utils.info_msg(f"Target bank status: 0x{target_status:02x}")

    # Bank status: 0xfc = healthy, 0xfd = warning, 0xfe = critical
    if target_status not in [0xfc, 0xfd]:
        raise RuntimeError(
            f"Target bank status is unhealthy (0x{target_status:02x})."
        )

    # Determine current active bank
    current_bank = utils.get_active_bank(metadata)

    # Check if already active
    if current_bank == target_bank:
        utils.warning_msg(f"Bank {target_name} is already active")
        return False  # No change needed

    # Determine new values
    new_active = target_bank
    new_prev = current_bank
    bank_status_offset = 0x19 if target_bank == 1 else 0x18

    # Update active bank (offset 0x8)
    with open(metadata_file, 'r+b') as f:
        f.seek(0x8)
        f.write(struct.pack('<I', new_active))

        # Update previous bank (offset 0xC)
        f.seek(0xC)
        f.write(struct.pack('<I', new_prev))

        # Update target bank status to healthy (0xfc)
        f.seek(bank_status_offset)
        f.write(b'\xfc')

    utils.success_msg("Metadata updated successfully")
    return True  # Change made


def run(args):
    """Switch active bank"""
    # Require root
    if not utils.check_root_privileges():
        utils.error_msg("This command requires root privileges")
        return 1

    # Parse bank argument
    bank_arg = args.bank.lower()
    if bank_arg in ['a', '0']:
        target_bank = 0
        target_name = "Bank A"
    else:
        target_bank = 1
        target_name = "Bank B"

    print("\n" + "="*60)
    utils.info_msg(f"Switching to {target_name}")
    print("="*60 + "\n")

    try:
        # Read current metadata
        utils.info_msg(f"Reading metadata from {utils.MTD_METADATA}")
        metadata = utils.read_metadata()

        # Get active bank
        current_bank = utils.get_active_bank(metadata)
        current_name = "Bank A" if current_bank == 0 else "Bank B"
        utils.success_msg(f"Current active bank: {current_name}")

        # Check if already active
        if current_bank == target_bank:
            utils.warning_msg(f"{target_name} is already the active bank")
            print("="*60 + "\n")
            return 0

        # Save metadata to temp file for modification
        with tempfile.NamedTemporaryFile(mode='wb', delete=False, suffix='.bin') as tmp:
            metadata_file = tmp.name
            tmp.write(metadata)

        try:
            # Update metadata
            changed = update_metadata(metadata_file, target_bank)

            if not changed:
                return 0

            # Calculate CRC32 and flash to both metadata partitions
            utils.calculate_and_update_crc32(metadata_file)

            print("\n" + "="*60)
            utils.success_msg(f"Active bank switched to {target_name}")
            utils.warning_msg("The system will boot from the selected bank on next reboot")
            print("="*60 + "\n")

            return 0

        finally:
            # Cleanup temp metadata file
            if os.path.exists(metadata_file):
                os.remove(metadata_file)

    except Exception as e:
        utils.error_msg(str(e))
        return 1
