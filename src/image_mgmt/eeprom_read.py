# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

"""EEPROM read operations for DUT MAC addresses"""

import os
import sys
from datetime import datetime

from . import utils
from .eeprom_core import EepromSysfsHandler, SimpleFruParser, TIMESTAMP_DISPLAY_FORMAT


def _normalize_mac_format(mac: str, separator: str = ':') -> str:
    """Normalize MAC address format to use specified separator.

    Args:
        mac: MAC address string (can use : or - as separator)
        separator: Desired separator character (default ':')

    Returns:
        MAC address with specified separator
    """
    # Replace both : and - with the desired separator
    return mac.replace(':', separator).replace('-', separator)


def _build_yaml_content(target: str, mac_addresses: dict) -> str:
    """Build YAML content from MAC addresses.

    Args:
        target: Target type (e.g., 'dut')
        mac_addresses: Dictionary of MAC addresses

    Returns:
        YAML formatted string
    """
    yaml_content = f"# {target.upper()} MAC Address Backup\n"
    yaml_content += f"# Generated: {datetime.now().strftime(TIMESTAMP_DISPLAY_FORMAT)}\n\n"
    yaml_content += f"{target}:\n"
    for key, value in sorted(mac_addresses.items()):
        mac_colon = _normalize_mac_format(value, separator=':')
        yaml_content += f"  {key}: \"{mac_colon}\"\n"
    return yaml_content


def get_mac_addresses(handler: EepromSysfsHandler, target: str,
                     save_bin: str = None, save_yaml: str = None) -> bool:
    """Get and display DUT MAC addresses, optionally save binary/YAML backup.

    Args:
        handler: EEPROM handler instance
        target: Target type (always 'dut')
        save_bin: Path to save binary backup (optional)
        save_yaml: Path to save YAML backup (optional)

    Returns:
        True if successful, False otherwise
    """
    data = handler.read_eeprom()
    if data is None:
        return False

    parser = SimpleFruParser()
    if not parser.parse(data):
        utils.error_msg("Failed to parse FRU data")
        return False

    mac_addresses = parser.get_mac_addresses(target)

    if save_bin:
        try:
            with open(save_bin, 'wb') as f:
                f.write(data)
            utils.success_msg(f"Binary backup saved to: {os.path.abspath(save_bin)}")
        except Exception as e:
            utils.error_msg(f"Error saving binary backup: {e}")
            return False

    if save_yaml:
        if mac_addresses:
            yaml_content = _build_yaml_content(target, mac_addresses)
        else:
            yaml_content = f"# {target.upper()} MAC Address Backup\n"
            yaml_content += f"# Generated: {datetime.now().strftime(TIMESTAMP_DISPLAY_FORMAT)}\n\n"
            yaml_content += f"# No {target.upper()} MAC addresses found in EEPROM\n"
            yaml_content += f"{target}:\n"
            yaml_content += "  # No MAC addresses present\n"

        try:
            with open(save_yaml, 'w') as f:
                f.write(yaml_content)
            utils.success_msg(f"YAML backup saved to: {os.path.abspath(save_yaml)}")
        except Exception as e:
            utils.error_msg(f"Error saving YAML backup: {e}")
            return False

    if not mac_addresses:
        utils.info_msg(f"No {target.upper()} MAC addresses found in EEPROM")
        return True

    mac_count = len(mac_addresses)
    print(f"\n{target.upper()} MAC Addresses (Found {mac_count} MAC(s)):")

    for key, value in sorted(mac_addresses.items()):
        normalized = _normalize_mac_format(value, ':')
        print(f"  {key}: {normalized}")
    print()
    return True
