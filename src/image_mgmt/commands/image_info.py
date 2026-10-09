# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

"""Image-info command - reads metadata from flash or a local boot image."""

import json
import os
import struct
from .. import utils


def setup_parser(subparsers):
    """Setup argument parser for image-info command."""
    parser = subparsers.add_parser('image-info', help='Show image version information')
    source = parser.add_mutually_exclusive_group()
    source.add_argument('--type', choices=['recovery', 'selector', 'bank-a', 'bank-b', 'vivado', 'all'],
                        default=None, help='Flash version type to query (default: all)')
    source.add_argument('--file', metavar='boot.bin',
                        help='Extract and display version information from a local boot image')
    parser.set_defaults(func=run)
    return parser


def _optional_data_offsets(device_path, platform):
    """Return valid optional-data offsets, preferred platform layout first."""
    preferred = (utils.IHT_OFFSET_VERSAL_2VE_2VM
                 if platform == 'versal_2ve_2vm' else utils.IHT_OFFSET_DEFAULT)
    offsets = []
    for pointer_offset, iht_length in sorted(
            utils.IHT_LAYOUTS, key=lambda layout: layout[0] != preferred):
        try:
            iht_bytes = utils.read_binary_file(device_path, pointer_offset, 4)
            iht_offset = struct.unpack('<I', iht_bytes)[0]
            if (len(iht_bytes) != 4 or iht_offset in (0, 0xFFFFFFFF) or
                    iht_offset % 4 or iht_offset > 0xFFFFFFFF - iht_length):
                continue
            optional_data_offset = iht_offset + iht_length
            if (os.path.isfile(device_path) and
                    optional_data_offset + 4 > os.path.getsize(device_path)):
                continue
            if optional_data_offset not in offsets:
                offsets.append(optional_data_offset)
        except (OSError, RuntimeError, struct.error):
            continue
    return offsets


def _extract_vivado_version(value):
    """Extract Vivado version from the configured optional-data manifest."""
    try:
        metadata = json.loads(value.rstrip(b'\x00').decode('utf-8'))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return None

    def find_version(item):
        if isinstance(item, dict):
            version = item.get('vivado_version')
            if isinstance(version, str) and version.strip():
                return version.strip()
            for child in item.values():
                version = find_version(child)
                if version:
                    return version
        elif isinstance(item, list):
            for child in item:
                version = find_version(child)
                if version:
                    return version
        return None

    return find_version(metadata)


def extract_bootgen_version(device_path, platform='default', target_id=None,
                            allow_legacy_fallback=True, data_cache=None):
    """
    Extract a version string from Bootgen optional data fields.
    Platform is auto-detected from /proc/device-tree/family.
    """
    try:
        if platform == 'default':
            platform = utils.detect_platform()

        target_id = target_id if target_id is not None else utils.OPT_DATA_ID_VERSION
        legacy_version = None
        cache_key = (device_path, platform)
        if data_cache is not None and cache_key in data_cache:
            optional_data = data_cache[cache_key]
        else:
            optional_data = []
            for optional_data_offset in _optional_data_offsets(device_path, platform):
                try:
                    optional_data.append(utils.read_binary_file(
                        device_path, optional_data_offset,
                        utils.OPTIONAL_DATA_READ_SIZE))
                except RuntimeError:
                    continue
            if data_cache is not None:
                data_cache[cache_key] = optional_data

        for opt_data in optional_data:
            offset = 0
            while offset + 4 <= len(opt_data):
                data_id, length_words = struct.unpack_from('<HH', opt_data, offset)
                length_bytes = length_words * 4

                if data_id == 0 and length_words == 0:
                    offset += 4
                    continue
                if length_bytes < 4 or offset + length_bytes > len(opt_data):
                    break

                if (data_id == target_id or
                        (allow_legacy_fallback and
                         data_id == utils.OPT_DATA_ID_LEGACY_VERSION)):
                    value_end = offset + length_bytes - utils.OPTIONAL_DATA_CHECKSUM_SIZE
                    if value_end < offset + 4:
                        break
                    value = opt_data[offset + 4:value_end]
                    if data_id == utils.OPT_DATA_ID_VIVADO_VERSION:
                        value_str = _extract_vivado_version(value)
                    else:
                        value = value[:utils.MAX_VERSION_LENGTH]
                        value_str = value.split(b'\x00', 1)[0].decode(
                            'utf-8', errors='ignore').split('\n', 1)[0].strip()
                        value_str = ''.join(c for c in value_str if c.isprintable())
                        value_str = utils.clean_version_metadata(value_str)
                    if data_id == utils.OPT_DATA_ID_VERSION and value_str:
                        value_str = value_str.replace('+git', '')
                    if data_id == target_id and value_str:
                        return value_str
                    if value_str:
                        legacy_version = value_str

                offset += length_bytes

        return legacy_version

    except Exception as e:
        utils.error_msg(f"Failed to extract bootgen version from {device_path}: {e}")
        return None


def get_version(version_type, platform=None, data_cache=None, device_path=None):
    """Get version information from an MTD device or a local boot image."""
    platform = platform or utils.detect_platform()

    if version_type not in ('recovery', 'selector', 'bank-a', 'bank-b'):
        return (f"Error: Unknown version type: {version_type}", None)
    ver_type = 'bank' if version_type in ('bank-a', 'bank-b') else version_type

    if device_path is not None:
        device = device_path
        label = "Functional Description"
    elif version_type == 'recovery':
        device = utils.MTD_RECOVERY
        label = "Image Recovery"
    elif version_type == 'selector':
        device = utils.MTD_SELECTOR
        label = "Image Selector"
    elif version_type == 'bank-a':
        device = utils.MTD_BANK_A
        label = "Bank A image ver"
    elif version_type == 'bank-b':
        device = utils.MTD_BANK_B
        label = "Bank B image ver"

    if not os.path.exists(device):
        return (label, "Not Available")

    version = None

    if platform == 'zynqmp':
        version = utils.extract_version_from_offset(device)
    elif version_type in ('recovery', 'selector'):
        description = extract_bootgen_version(
            device, platform, utils.OPT_DATA_ID_DESCRIPTION,
            allow_legacy_fallback=False, data_cache=data_cache)
        component_version = extract_bootgen_version(
            device, platform, utils.OPT_DATA_ID_VERSION,
            allow_legacy_fallback=False, data_cache=data_cache)
        tools_version = extract_bootgen_version(
            device, platform, utils.OPT_DATA_ID_TOOLS_VERSION,
            allow_legacy_fallback=False, data_cache=data_cache)
        build_id = None
        if utils.ENABLE_BOOTGEN_BUILD_ID:
            build_id = extract_bootgen_version(
                device, platform, utils.OPT_DATA_ID_BUILD_ID,
                allow_legacy_fallback=False, data_cache=data_cache)
        version = '-'.join(value for value in (
            description, component_version, tools_version,
            build_id) if value)
    else:
        optional_data_id = {
            'bank-a': utils.OPT_DATA_ID_DESCRIPTION,
            'bank-b': utils.OPT_DATA_ID_DESCRIPTION,
        }[version_type]
        version = extract_bootgen_version(
            device, platform, optional_data_id, data_cache=data_cache)

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
    """Show image version information from flash or a local boot image."""
    if args.file is not None:
        try:
            if not os.path.isfile(args.file):
                raise ValueError("Path is not a regular file")
            with open(args.file, 'rb') as image:
                if not utils._has_valid_boot_header(image):
                    raise ValueError("Not a valid BOOT.BIN: boot header not found")
                image.seek(0x20)
                header = image.read(8)
            platform = ('zynqmp' if header == utils.BOOT_SYNC_WORD + utils.BOOT_XNLX_MAGIC
                        else 'versal')
        except (OSError, ValueError) as exc:
            utils.error_msg(f"Cannot read image {args.file}: {exc}")
            return 1
    else:
        platform = utils.detect_platform()

    query_type = args.type or 'all'
    if args.file is not None:
        types_to_query = ['bank-a']
    elif query_type == 'all':
        types_to_query = ['recovery', 'selector', 'bank-a', 'bank-b']
    elif query_type == 'vivado':
        types_to_query = ['bank-a', 'bank-b']
    else:
        types_to_query = [query_type]

    results = []
    if platform == 'zynqmp' and query_type == 'vivado':
        return 0

    bank_info = {
        'bank-a': (utils.MTD_BANK_A, "Bank A"),
        'bank-b': (utils.MTD_BANK_B, "Bank B"),
    }
    data_cache = {}

    for version_type in types_to_query:
        if query_type != 'vivado':
            label, version = get_version(
                version_type, platform, data_cache=data_cache, device_path=args.file)
            results.append((label, version))
        if platform != 'zynqmp' and version_type in ('bank-a', 'bank-b'):
            if args.file is not None:
                device = args.file
                vivado_label = "Vivado version"
                metadata_fields = [
                    ('Functional Version', utils.OPT_DATA_ID_VERSION),
                    ('Tools version', utils.OPT_DATA_ID_TOOLS_VERSION),
                ]
                if utils.ENABLE_BOOTGEN_BUILD_ID:
                    metadata_fields.append(('Build ID', utils.OPT_DATA_ID_BUILD_ID))
                for label, data_id in metadata_fields:
                    version = extract_bootgen_version(
                        device, platform, data_id,
                        allow_legacy_fallback=False, data_cache=data_cache)
                    if version:
                        results.append((label, version))
            else:
                device, bank_label = bank_info[version_type]
                vivado_label = f"{bank_label} Vivado version"
            vivado_version = extract_bootgen_version(
                device, platform, utils.OPT_DATA_ID_VIVADO_VERSION,
                allow_legacy_fallback=False, data_cache=data_cache)
            results.append((vivado_label,
                            vivado_version or "No Vivado version information found"))

    print("\n" + "="*60)
    print("Version Information")
    print("="*60)
    for label, version in results:
        utils.info_msg(f"{label}: {version}")
    print("="*60 + "\n")

    return 0
