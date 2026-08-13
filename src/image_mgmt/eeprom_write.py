# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

"""EEPROM write operations for DUT MAC addresses"""

import os
import sys
from typing import Dict

from . import utils
from .eeprom_core import EepromSysfsHandler, SimpleFruParser, validate_mac_address
from .eeprom_read import get_mac_addresses


def _create_timestamped_backup(handler: EepromSysfsHandler, prefix: str = 'eeprom', fail_on_error: bool = False) -> bool:
    """Create a timestamped backup of EEPROM.

    Args:
        handler: EEPROM handler instance
        prefix: Prefix for backup filename
        fail_on_error: If True, treat backup failure as fatal error

    Returns:
        True if backup succeeded, False otherwise
    """
    # Use consolidated backup method from handler
    success = handler.backup_eeprom(backup_path=None, prefix=prefix, fail_on_error=fail_on_error)

    if not success and not fail_on_error:
        utils.warning_msg("Backup failed, but continuing...")

    return success


def set_mac_addresses(handler: EepromSysfsHandler, target: str,
                     mac_dict: Dict[str, str], backup: bool = True) -> bool:
    """Set DUT MAC addresses in EEPROM.

    Args:
        handler: EEPROM handler instance
        target: Target type (always 'dut')
        mac_dict: Dictionary of MAC addresses {mac0: value, mac1: value, ...}
        backup: Create backup before writing

    Returns:
        True if successful, False otherwise
    """
    # Validate MAC addresses before proceeding using centralized validator
    for key, value in mac_dict.items():
        if not validate_mac_address(value):
            utils.error_msg(f"Invalid MAC address format for {key}: {value}")
            utils.info_msg("Expected format: XX:XX:XX:XX:XX:XX or XX-XX-XX-XX-XX-XX")
            return False

    # Create backup if requested
    if backup:
        if not _create_timestamped_backup(handler):
            utils.error_msg("Failed to create backup before writing")
            return False

    # Read current EEPROM
    data = handler.read_eeprom()
    if data is None:
        utils.error_msg("Failed to read EEPROM (may be empty or inaccessible)")
        return False

    # Parse FRU
    parser = SimpleFruParser()
    if not parser.parse(data):
        utils.error_msg("Failed to parse FRU data")
        return False

    try:
        new_data, write_offset, write_length = parser.set_mac_addresses(mac_dict, target)
    except (ValueError, RuntimeError) as e:
        utils.error_msg(f"Error updating MAC addresses: {e}")
        return False
    except Exception as e:
        utils.error_msg(f"Unexpected error updating MAC addresses: {e}")
        import traceback
        traceback.print_exc()
        return False

    utils.info_msg(f"Writing {write_length} bytes at offset {write_offset} (partial write)")
    if not handler.write_eeprom(new_data, offset=write_offset, length=write_length, backup=False):
        return False

    utils.success_msg(f"Successfully updated {target.upper()} MAC addresses")
    utils.info_msg("Verifying written MAC addresses...")

    verify_data = handler.read_eeprom()
    if verify_data is None:
        utils.warning_msg("Could not read EEPROM for verification")
        utils.info_msg("Write may have succeeded, but verification failed.")
        return False

    verify_parser = SimpleFruParser()
    if not verify_parser.parse(verify_data):
        utils.error_msg("Verification failed: Could not parse EEPROM data after write")
        utils.warning_msg("EEPROM may be corrupted. Restore from backup if needed.")
        return False

    verify_macs = verify_parser.get_mac_addresses(target)
    if not verify_macs:
        utils.error_msg("Verification failed: No MAC addresses found in EEPROM after write")
        utils.warning_msg("EEPROM may be corrupted. Restore from backup if needed.")
        return False

    verification_failed = False
    for key, expected_value in mac_dict.items():
        actual_value = verify_macs.get(key)
        if actual_value is None:
            utils.error_msg(f"Verification failed: {key} not found in EEPROM after write")
            verification_failed = True
        else:
            expected_normalized = expected_value.replace('-', ':').upper()
            actual_normalized = actual_value.replace('-', ':').upper()

            if expected_normalized != actual_normalized:
                utils.error_msg(f"Verification failed: {key} mismatch")
                utils.error_msg(f"  Expected: {expected_value}")
                utils.error_msg(f"  Actual:   {actual_value}")
                verification_failed = True

    if verification_failed:
        utils.error_msg("MAC address verification failed. EEPROM may be corrupted.")
        utils.error_msg("Recommendation: Restore from backup immediately!")
        return False

    utils.success_msg("Verification successful: All MAC addresses match expected values")
    get_mac_addresses(handler, target)

    return True


def import_mac_from_yaml(handler: EepromSysfsHandler, yaml_path: str,
                        backup: bool = True) -> bool:
    """Import DUT MAC addresses from YAML file and write to EEPROM.

    Args:
        handler: EEPROM handler instance
        yaml_path: Path to YAML file
        backup: Create backup before writing

    Returns:
        True if successful, False otherwise
    """
    # Validate file exists
    if not os.path.exists(yaml_path):
        utils.error_msg(f"YAML file not found: {yaml_path}")
        return False

    if not os.path.isfile(yaml_path):
        utils.error_msg(f"Path is not a file: {yaml_path}")
        return False

    # Read and parse YAML file (simple parser, no external dependencies)
    try:
        with open(yaml_path, 'r') as f:
            yaml_lines = f.readlines()
    except Exception as e:
        utils.error_msg(f"Error reading YAML file: {e}")
        return False

    has_target = False
    has_mac_lines = False
    for line in yaml_lines:
        stripped = line.strip()
        if stripped and not stripped.startswith('#'):
            if not line[0].isspace() and ':' in line:
                has_target = True
            elif line[0].isspace() and ':' in line:
                has_mac_lines = True

    if not has_target or not has_mac_lines:
        error_type = "no target section found" if not has_target else "no MAC address lines found"
        utils.error_msg(f"Invalid YAML structure - {error_type}")
        utils.info_msg("Expected format:")
        utils.info_msg("  dut:")
        utils.info_msg("    mac0: XX:XX:XX:XX:XX:XX")
        return False

    mac_data = {}
    current_target = None
    invalid_mac_count = 0

    for line in yaml_lines:
        line = line.rstrip()
        if not line or line.strip().startswith('#'):
            continue

        if len(line) > 0 and not line[0].isspace() and ':' in line:
            # Handle case where line might have trailing content after colon
            parts = line.split(':', 1)
            current_target = parts[0].strip()
            if current_target != 'dut':
                utils.warning_msg(f"Only 'dut' target is supported, skipping '{current_target}'")
                current_target = None
            else:
                mac_data[current_target] = {}
        elif current_target and len(line) > 0 and line[0].isspace() and ':' in line:
            # More robust parsing - handle different indentation
            stripped = line.strip()
            if not stripped:
                continue

            # Split on first colon only
            parts = stripped.split(':', 1)
            if len(parts) == 2:
                key = parts[0].strip()
                value = parts[1].strip().strip('"\'')

                # Skip empty values after quote stripping
                if not value:
                    continue

                if key in {'mac0', 'mac1', 'mac2', 'mac3'}:
                    if validate_mac_address(value):
                        mac_data[current_target][key] = value
                    else:
                        utils.warning_msg(f"Invalid MAC format for '{key}': {value}")
                        invalid_mac_count += 1
                elif key.startswith('mac'):
                    utils.warning_msg(f"Ignoring invalid MAC key '{key}' in YAML (valid: mac0-mac3)")

    # Check if any valid MACs were actually found (check inner dicts, not just outer dict)
    total_valid_macs = sum(len(mac_dict) for mac_dict in mac_data.values())

    if total_valid_macs == 0:
        if invalid_mac_count > 0:
            utils.error_msg(f"No valid MAC addresses found in YAML file ({invalid_mac_count} invalid MAC(s) were skipped)")
        else:
            utils.error_msg("No valid MAC addresses found in YAML file")
        return False

    # Warn if some MACs were invalid
    if invalid_mac_count > 0:
        utils.warning_msg(f"{invalid_mac_count} invalid MAC address(es) were skipped")
        utils.info_msg(f"Proceeding with {total_valid_macs} valid MAC address(es)")

    success = True
    backup_done = False
    total_written = 0

    for target, mac_dict in mac_data.items():
        if mac_dict:
            should_backup = backup and not backup_done
            if not set_mac_addresses(handler, target, mac_dict, backup=should_backup):
                utils.error_msg(f"Failed to write {target.upper()} MAC addresses")
                success = False
                break
            else:
                backup_done = True
                total_written += len(mac_dict)
    if success and total_written > 0:
        utils.info_msg(f"Successfully imported {total_written} MAC address(es) from YAML file")

    return success


def restore_from_bin(handler: EepromSysfsHandler, bin_path: str,
                    backup: bool = True) -> bool:
    """Restore entire EEPROM from binary backup file.

    Args:
        handler: EEPROM handler instance
        bin_path: Path to binary backup file
        backup: Create backup before writing

    Returns:
        True if successful, False otherwise
    """
    # Validate file exists
    if not os.path.exists(bin_path):
        utils.error_msg(f"Binary file not found: {bin_path}")
        return False

    if not os.path.isfile(bin_path):
        utils.error_msg(f"Path is not a file: {bin_path}")
        return False

    # Read binary file
    try:
        with open(bin_path, 'rb') as f:
            restore_data = f.read()
    except Exception as e:
        utils.error_msg(f"Error reading binary file: {e}")
        return False

    parser = SimpleFruParser()
    if not parser.parse(restore_data):
        utils.error_msg("Binary file does not contain valid FRU data")
        return False

    current_data = handler.read_eeprom()
    if current_data is None:
        utils.error_msg("Could not read current EEPROM for size validation")
        return False

    size_mismatch_confirmed = False

    if len(restore_data) != len(current_data):
        utils.warning_msg(f"Restore file size ({len(restore_data)} bytes) differs from EEPROM size ({len(current_data)} bytes)")
        if not sys.stdin.isatty():
            utils.error_msg("Size mismatch in non-interactive mode. Aborting for safety.")
            utils.info_msg("Run in interactive terminal or ensure file size matches EEPROM.")
            return False

        try:
            response = input("This may corrupt the EEPROM. Continue? [y/N]: ")
            if response.strip().lower() not in ['y', 'yes']:
                utils.info_msg("Restore cancelled.")
                return False
            size_mismatch_confirmed = True
        except (EOFError, KeyboardInterrupt):
            utils.info_msg("\nRestore cancelled.")
            return False

    if backup:
        if not _create_timestamped_backup(handler, fail_on_error=True):
            return False
    if not handler.write_eeprom(restore_data, backup=False):
        utils.error_msg("Failed to write EEPROM")
        return False

    utils.success_msg("Successfully restored EEPROM from binary file")
    utils.info_msg("Verifying restored data...")
    verify_data = handler.read_eeprom()
    if verify_data is None:
        utils.warning_msg("Could not read EEPROM for verification")
        utils.info_msg("Restore may have succeeded, but verification failed.")
    else:
        compare_length = min(len(restore_data), len(verify_data))
        verify_portion = verify_data[:compare_length]
        restore_portion = restore_data[:compare_length]

        if verify_portion != restore_portion:
            utils.error_msg("Verification failed! Restored data does not match source file.")
            utils.error_msg(f"Compared {compare_length} bytes, data mismatch detected")
            utils.error_msg("EEPROM may be corrupted.")
            utils.error_msg("Recommendation: Restore from backup immediately!")
            return False
        elif size_mismatch_confirmed:
            utils.success_msg(f"Verification successful: {compare_length} bytes written and verified")
            if len(restore_data) < len(verify_data):
                utils.info_msg(f"Note: Wrote {len(restore_data)} bytes to {len(verify_data)}-byte EEPROM (partial write as confirmed)")
            else:
                utils.warning_msg(f"Note: Restore file was {len(restore_data)} bytes, but EEPROM is only {len(verify_data)} bytes (data was truncated)")
        else:
            utils.success_msg("Verification successful: Data matches source file")

    get_mac_addresses(handler, 'dut')
    return True
