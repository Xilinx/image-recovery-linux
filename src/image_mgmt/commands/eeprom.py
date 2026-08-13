# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

"""EEPROM command - manage EEPROM MAC addresses and data"""

import os
import sys
from datetime import datetime

from .. import eeprom_core, eeprom_read, eeprom_write, utils

# Import timestamp constant for consistent formatting
from ..eeprom_core import TIMESTAMP_FILE_FORMAT


def setup_parser(subparsers):
    """Setup argument parser for eeprom command."""
    parser = subparsers.add_parser('eeprom',
                                   help='Manage EEPROM MAC addresses',
                                   epilog='Examples:\n'
                                          '  sudo image-mgmt eeprom check-wp\n'
                                          '  sudo image-mgmt eeprom get-mac\n'
                                          '  sudo image-mgmt eeprom set-mac mac0=00:0A:35:AA:BB:CC\n'
                                          '  sudo image-mgmt eeprom --device /sys/bus/i2c/devices/2-0054/eeprom get-mac\n'
                                          '  sudo image-mgmt eeprom -v get-mac  # Verbose mode',
                                   formatter_class=lambda prog: __import__('argparse').RawDescriptionHelpFormatter(prog, max_help_position=35))

    parser.add_argument('--device', default=None,
                        help='Path to EEPROM sysfs device. '
                             'Example: --device /sys/bus/i2c/devices/2-0054/eeprom get-mac. '
                             'If omitted, will auto-detect and prompt for selection if multiple devices found.')

    eeprom_subparsers = parser.add_subparsers(dest='eeprom_command', help='EEPROM operations')
    eeprom_subparsers.add_parser('check-wp', help='Check write protection status')
    get_parser = eeprom_subparsers.add_parser('get-mac',
                                              help='Get DUT MAC addresses (auto-saves .bin and .yaml)')
    get_parser.add_argument('--no-backup', action='store_true',
                           help='Skip automatic backup (only display MAC addresses)')

    set_parser = eeprom_subparsers.add_parser('set-mac',
                                              help='Set DUT MAC addresses in EEPROM',
                                              description='Set one or more DUT MAC addresses (mac0-mac3)')
    set_parser.add_argument('mac_addresses', nargs='*', metavar='MAC=VALUE',
                           help='MAC addresses to set (e.g., mac0=00:0A:35:1D:5B:90 mac1=00:0A:35:1D:5B:91). '
                                'Run without arguments to see current values.')
    set_parser.add_argument('--from-yaml', metavar='FILE',
                           help='Import MAC addresses from YAML file')
    set_parser.add_argument('--from-bin', metavar='FILE',
                           help='Restore entire EEPROM from binary backup file')
    set_parser.add_argument('--no-backup', action='store_true',
                           help='Skip automatic backup before writing')

    parser.add_argument('-v', '--verbose', action='store_true',
                       help='Enable verbose output (shows debug messages). '
                            'Example: image-mgmt eeprom -v get-mac')

    parser.set_defaults(func=run, parser=parser)
    return parser


def run(args):
    """Main entry point for eeprom command."""
    if not args.eeprom_command:
        args.parser.print_help()
        return 0

    if os.geteuid() != 0:
        utils.error_msg("This command requires root privileges")
        return 1

    if args.device is None:
        devices = utils.find_eeprom_devices()
        if not devices:
            utils.error_msg("No EEPROM devices found on I2C buses")
            utils.info_msg(f"Searched for EEPROM at I2C address {utils.EEPROM_I2C_ADDRESS} on all buses")
            utils.info_msg("You can specify device manually with: --device /sys/bus/i2c/devices/BUS-ADDR/eeprom")
            return 1

        args.device = utils.prompt_device_selection(devices, "EEPROM")
        if args.device is None:
            utils.error_msg("Device selection cancelled by user")
            return 1

    if not os.path.exists(args.device):
        utils.error_msg(f"EEPROM device not found: {args.device}")
        return 1

    args.eeprom_path = args.device
    if args.eeprom_command == 'check-wp':
        return cmd_check_wp(args)
    elif args.eeprom_command == 'get-mac':
        return cmd_get_mac(args)
    elif args.eeprom_command == 'set-mac':
        return cmd_set_mac(args)
    else:
        utils.error_msg(f"Unknown EEPROM command: {args.eeprom_command}")
        return 1


def cmd_get_mac(args):
    """Get DUT MAC addresses and auto-save timestamped .bin and .yaml files."""
    handler = eeprom_core.EepromSysfsHandler(args.eeprom_path, verbose=args.verbose)

    if not handler.validate_eeprom_path():
        return 1

    bin_file = None
    yaml_file = None

    if not args.no_backup:
        backup_dir = "/tmp/eeprom_backup"
        os.makedirs(backup_dir, exist_ok=True)
        timestamp = datetime.now().strftime(TIMESTAMP_FILE_FORMAT)
        bin_file = f"{backup_dir}/eeprom_{timestamp}.bin"
        yaml_file = f"{backup_dir}/eeprom_{timestamp}.yaml"

    if eeprom_read.get_mac_addresses(handler, 'dut',
                                     save_bin=bin_file,
                                     save_yaml=yaml_file):
        return 0
    return 1


def cmd_set_mac(args):
    """Set DUT MAC addresses from CLI args or YAML file."""
    handler = eeprom_core.EepromSysfsHandler(args.eeprom_path, verbose=args.verbose)

    if not handler.validate_eeprom_path():
        return 1

    if args.from_bin:
        if args.mac_addresses or args.from_yaml:
            utils.error_msg("Cannot specify --from-bin with other options")
            return 1

        if eeprom_write.restore_from_bin(handler, args.from_bin,
                                        backup=not args.no_backup):
            return 0
        return 1

    if args.from_yaml:
        if args.mac_addresses:
            utils.error_msg("Cannot specify both --from-yaml and MAC addresses")
            return 1

        if eeprom_write.import_mac_from_yaml(handler, args.from_yaml,
                                            backup=not args.no_backup):
            return 0
        return 1

    if not args.mac_addresses:
        print("\nCurrent MAC addresses in EEPROM:")
        if eeprom_read.get_mac_addresses(handler, 'dut'):
            print("\nUsage:")
            print("  Set: sudo image-mgmt eeprom set-mac mac0=XX:XX:XX:XX:XX:XX [mac1=...] [mac2=...] [mac3=...]")
            print("  Import YAML: sudo image-mgmt eeprom set-mac --from-yaml <file.yaml>")
            print("  Restore binary: sudo image-mgmt eeprom set-mac --from-bin <file.bin>")
            print("\nNote: You can only modify MAC addresses that exist in your board's EEPROM.")
            print("      To add more MACs, restore an EEPROM image with the desired MAC count.")
        return 1

    mac_dict = {}
    valid_keys = {'mac0', 'mac1', 'mac2', 'mac3'}

    for mac_spec in args.mac_addresses:
        if '=' not in mac_spec:
            utils.error_msg(f"Invalid MAC specification '{mac_spec}' (format: macN=XX:XX:XX:XX:XX:XX)")
            return 1

        key, value = mac_spec.split('=', 1)

        # Validate MAC key
        if key not in valid_keys:
            utils.error_msg(f"Invalid MAC key '{key}' (valid: {', '.join(sorted(valid_keys))})")
            return 1

        # Detect duplicate keys
        if key in mac_dict:
            utils.error_msg(f"Duplicate MAC key '{key}' specified")
            return 1

        mac_dict[key] = value

    if eeprom_write.set_mac_addresses(handler, 'dut', mac_dict,
                                     backup=not args.no_backup):
        return 0
    return 1


def cmd_check_wp(args):
    """Check EEPROM write protection status."""
    handler = eeprom_core.EepromSysfsHandler(args.eeprom_path, verbose=args.verbose)

    if not handler.validate_eeprom_path():
        return 1

    print("\nEEPROM Write Protection Status:")
    print("="*60)
    print(f"EEPROM Device: {handler.eeprom_path}")

    # Check file permissions
    try:
        writable = os.access(handler.eeprom_path, os.W_OK)
        print(f"File System Writable: {writable}")
    except Exception as e:
        print(f"File System Writable: <error: {e}>")

    print("="*60)
    print("\nTo disable write protection, run:")
    print("  sudo timeout 1 gpioset EEPROM_WC_B=0")
    print("\nNote: The write command will attempt this automatically.")
    return 0
