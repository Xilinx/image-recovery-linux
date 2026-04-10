# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

"""Upload and flash boot.bin image to MTD device with dual-bank support"""

import os
import re
import sys
import struct
import tempfile
from .. import utils


def setup_parser(subparsers):
    """Setup argument parser for upload-boot command."""
    parser = subparsers.add_parser('upload-boot', help='Upload and flash boot.bin image')
    parser.add_argument('file', help='Path to boot.bin file')
    parser.set_defaults(func=run)
    return parser


def flash_boot_image(boot_file, target_mtd, target_name):
    """Flash boot image to MTD device"""
    utils.step_msg("2", "4", f"Flashing boot image to {target_name}")

    # Erase flash
    utils.progress_msg(40, "Erasing flash partition...")
    utils.info_msg(f"Erasing {target_mtd}")

    result = utils.run_command(['flash_eraseall', target_mtd], check=False)
    if result.returncode != 0:
        raise RuntimeError(f"Failed to erase {target_mtd}: {result.stderr}")

    utils.success_msg("Flash partition erased")

    # Write image
    utils.progress_msg(60, "Writing boot image to flash...")
    utils.info_msg(f"Writing image to {target_mtd} using flashcp")

    result = utils.run_command(['flashcp', boot_file, target_mtd], check=False)
    if result.returncode != 0:
        raise RuntimeError(f"Failed to write image to {target_mtd}: {result.stderr}")

    utils.success_msg("Boot image written successfully")
    return True


def update_metadata(metadata_file, active_bank):
    """Update metadata to switch active bank"""
    utils.step_msg("3", "4", "Updating boot metadata")
    utils.progress_msg(80, "Updating metadata to switch active bank...")

    # Determine new values based on active bank
    if active_bank == 0:
        # Currently Bank A, switching to Bank B
        new_active = 1
        new_prev = 0
        bank_status_offset = 25  # Bank B status at 0x19
    else:
        # Currently Bank B, switching to Bank A
        new_active = 0
        new_prev = 1
        bank_status_offset = 24  # Bank A status at 0x18

    # Update active bank (offset 0x8)
    with open(metadata_file, 'r+b') as f:
        f.seek(0x8)
        f.write(struct.pack('<I', new_active))

        # Update previous bank (offset 0xC)
        f.seek(0xC)
        f.write(struct.pack('<I', new_prev))

        # Update bank status to healthy (0xfc)
        f.seek(bank_status_offset)
        f.write(b'\xfc')

    utils.success_msg("Metadata updated successfully")


def extract_version_info(boot_file):
    """Extract version information from boot.bin"""
    try:
        with open(boot_file, 'rb') as f:
            data = f.read()
        strings_list = utils.extract_strings(data)
        return utils.extract_version_from_strings(strings_list, 'default')
    except Exception:
        pass
    return None


def extract_build_date(boot_file):
    """Extract build date from filename"""
    filename = os.path.basename(boot_file)
    # Look for 14-digit timestamp in filename
    match = re.search(r'(\d{14})', filename)
    if match:
        timestamp = match.group(1)
        # Format: YYYYMMDDHHmmss
        year = timestamp[0:4]
        month = timestamp[4:6]
        day = timestamp[6:8]
        hour = timestamp[8:10]
        minute = timestamp[10:12]
        second = timestamp[12:14]
        return f"{year}-{month}-{day} {hour}:{minute}:{second}"
    return None


def run(args):
    """Upload and flash boot.bin image"""
    # Require root
    if not utils.check_root_privileges():
        utils.error_msg("This command requires root privileges")
        return 1

    # Validate boot file
    if not os.path.exists(args.file):
        utils.error_msg(f"Boot file not found: {args.file}")
        return 1

    if not os.path.isfile(args.file):
        utils.error_msg(f"Not a file: {args.file}")
        return 1

    file_size = os.path.getsize(args.file)
    if file_size == 0:
        utils.error_msg("Boot file is empty")
        return 1

    print("\n" + "="*60)
    utils.info_msg(f"Boot file: {args.file}")
    utils.info_msg(f"File size: {file_size:,} bytes ({file_size / 1024 / 1024:.2f} MB)")
    print("="*60 + "\n")

    try:
        # Step 1: Read metadata
        utils.step_msg("1", "4", "Reading current boot metadata")
        utils.progress_msg(10, "Reading metadata...")
        utils.info_msg(f"Reading from {utils.MTD_METADATA}")
        metadata = utils.read_metadata()

        # Get active bank
        active_bank = utils.get_active_bank(metadata)
        bank_name = 'A' if active_bank == 0 else 'B'
        utils.success_msg(f"Current active bank: Bank {bank_name}")

        # Determine target MTD based on active bank (flash to inactive bank)
        if active_bank == 0:
            # Bank A is active, flash to Bank B
            target_mtd = utils.MTD_BANK_B
            target_bank = 'B'
            target_name = "Bank B (will become active after reboot)"
        else:
            # Bank B is active, flash to Bank A
            target_mtd = utils.MTD_BANK_A
            target_bank = 'A'
            target_name = "Bank A (will become active after reboot)"

        utils.info_msg(f"Target: {target_mtd} - {target_name}")
        utils.progress_msg(20, f"Preparing to flash Bank {target_bank}...")

        # Flash boot image
        flash_boot_image(args.file, target_mtd, target_name)

        # Save metadata to temp file for modification
        with tempfile.NamedTemporaryFile(mode='wb', delete=False, suffix='.bin') as tmp:
            metadata_file = tmp.name
            tmp.write(metadata)

        try:
            # Update metadata
            update_metadata(metadata_file, active_bank)

            # Calculate CRC32 and flash to both metadata partitions
            utils.step_msg("4", "4", "Finalizing boot configuration")
            utils.progress_msg(90, "Calculating and updating CRC32...")
            utils.calculate_and_update_crc32(metadata_file)

            # Extract version and build date
            version_info = extract_version_info(args.file)
            build_date = extract_build_date(args.file)

            # Completion
            utils.progress_msg(100, "Flash operation completed")
            print("\n" + "="*60)
            utils.success_msg(f"Boot image flashed successfully to Bank {target_bank}")

            if version_info:
                utils.info_msg(f"Version: {version_info}")

            if build_date:
                utils.info_msg(f"Build Date: {build_date}")

            print("="*60)
            utils.warning_msg("System will boot from the new bank on next reboot")
            print()

            return 0

        finally:
            # Cleanup temp metadata file
            if os.path.exists(metadata_file):
                os.remove(metadata_file)

    except Exception as e:
        utils.error_msg(str(e))
        return 1
