# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

"""EEPROM FRU parser and sysfs I/O handler"""

import errno
import fcntl
import glob
import os
import subprocess
import sys
import struct
import time
from pathlib import Path
from typing import Optional, Dict, List, Tuple

# Timestamp format constants
TIMESTAMP_FILE_FORMAT = '%Y%m%d_%H%M%S'  # For filenames
TIMESTAMP_DISPLAY_FORMAT = '%Y-%m-%d %H:%M:%S'  # For human-readable display


def validate_mac_address(mac: str) -> bool:
    """Validate MAC address format (centralized validation).

    Args:
        mac: MAC address string to validate

    Returns:
        True if valid, False otherwise
    """
    import re
    # Accepts both : and - separators, but they must be consistent
    pattern_colon = r'^[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}$'
    pattern_dash = r'^[0-9A-Fa-f]{2}-[0-9A-Fa-f]{2}-[0-9A-Fa-f]{2}-[0-9A-Fa-f]{2}-[0-9A-Fa-f]{2}-[0-9A-Fa-f]{2}$'
    return bool(re.match(pattern_colon, mac) or re.match(pattern_dash, mac))


class SimpleFruParser:
    """Minimal FRU parser focused on MAC address operations."""

    # Xilinx IANA ID
    XILINX_IANA = 0x10da

    # Multirecord type IDs
    MULTIRECORD_TYPE_OEM = 0xd2

    # Xilinx OEM record ID for DUT
    XILINX_DUT_MAC_ID = 0x31

    # Maximum number of MAC addresses per record
    MAX_MAC_ADDRESSES = 4

    def __init__(self, logger=None):
        self.raw_data = None
        self.header = None
        self.multirecord_offset = None
        self.multirecords = []
        self.logger = logger

    def _log(self, msg: str, level: str = 'error'):
        """Internal logging helper."""
        if self.logger:
            self.logger(msg, level)
        else:
            # Fallback to print if no logger provided
            prefix = '[WARNING]' if level == 'warning' else '[ERROR]'
            print(f"{prefix} {msg}", file=sys.stderr)

    def parse(self, data: bytes) -> bool:
        """Parse FRU EEPROM data."""
        try:
            self.raw_data = bytearray(data)

            # Parse common header (8 bytes)
            if len(data) < 8:
                return False

            self.header = {
                'format_version': data[0],
                'internal_use_offset': data[1] * 8,
                'chassis_info_offset': data[2] * 8,
                'board_info_offset': data[3] * 8,
                'product_info_offset': data[4] * 8,
                'multirecord_offset': data[5] * 8,
            }

            # Parse multirecord area if present
            self.multirecord_offset = self.header['multirecord_offset']
            if self.multirecord_offset > 0:
                # Validate offset is within EEPROM bounds
                if self.multirecord_offset >= len(data):
                    self._log(f"MultiRecord offset ({self.multirecord_offset}) exceeds EEPROM size ({len(data)})", 'warning')
                    return False
                self._parse_multirecords(data, self.multirecord_offset)

            return True
        except Exception as e:
            self._log(f"Error parsing FRU: {e}", 'error')
            return False

    def _parse_multirecords(self, data: bytes, offset: int):
        """Parse multirecord area."""
        self.multirecords = []
        pos = offset

        while pos < len(data):
            if pos + 5 > len(data):
                break

            # Multirecord header (5 bytes)
            rec_type = data[pos]
            rec_format = data[pos + 1]
            rec_len = data[pos + 2]
            rec_checksum = data[pos + 3]
            header_checksum = data[pos + 4]

            end_of_list = (rec_format & 0x80) != 0

            # Get payload
            payload_start = pos + 5
            payload_end = payload_start + rec_len

            if payload_end > len(data):
                break

            payload = data[payload_start:payload_end]

            # Store record
            record = {
                'type': rec_type,
                'format': rec_format,
                'offset': pos,
                'payload': payload,
                'length': rec_len,
            }

            # Parse Xilinx OEM records
            if rec_type == self.MULTIRECORD_TYPE_OEM and rec_len >= 4 and len(payload) >= 4:
                iana_id = struct.unpack('<I', payload[0:3] + b'\x00')[0]
                if iana_id == self.XILINX_IANA:
                    xilinx_rec_id = payload[3]
                    record['xilinx_iana'] = iana_id
                    record['xilinx_rec_id'] = xilinx_rec_id

                    # Parse MAC addresses (DUT only)
                    if xilinx_rec_id == self.XILINX_DUT_MAC_ID:
                        macs = self._parse_mac_payload(payload[4:])
                        record['mac_addresses'] = macs

            self.multirecords.append(record)

            # Move to next record with safety check against infinite loops
            if payload_end <= pos:
                # No progress made - corrupted data, break to prevent infinite loop
                break
            pos = payload_end

            if end_of_list:
                break

    def _parse_mac_payload(self, payload: bytes) -> Dict[str, str]:
        """Parse MAC addresses from payload."""
        macs = {}
        mac_idx = 0
        pos = 0

        # Each MAC is 6 bytes
        while pos + 6 <= len(payload) and mac_idx < self.MAX_MAC_ADDRESSES:
            mac_bytes = payload[pos:pos+6]
            # Check if MAC is non-zero
            if any(b != 0 for b in mac_bytes):
                mac_str = '-'.join(f'{b:02X}' for b in mac_bytes)
                macs[f'mac{mac_idx}'] = mac_str
            mac_idx += 1
            pos += 6

        return macs

    def get_mac_addresses(self, target: str = 'dut') -> Dict[str, str]:
        """Get DUT MAC addresses."""
        target_id = self.XILINX_DUT_MAC_ID

        for record in self.multirecords:
            if record.get('xilinx_rec_id') == target_id:
                return record.get('mac_addresses', {})

        return {}

    def set_mac_addresses(self, mac_dict: Dict[str, str], target: str = 'dut') -> tuple:
        """Update DUT MAC addresses and return new FRU image with modification range.

        Returns:
            Tuple of (full_eeprom_bytes, modified_offset, modified_length) where:
            - full_eeprom_bytes: Complete EEPROM image with changes applied
            - modified_offset: Byte offset where changes start
            - modified_length: Number of bytes that were modified
        """
        target_id = self.XILINX_DUT_MAC_ID

        mac_record = None
        for record in self.multirecords:
            if record.get('xilinx_rec_id') == target_id:
                mac_record = record
                break

        if mac_record is None:
            raise RuntimeError(
                f"No existing {target.upper()} MAC record found in EEPROM. "
                f"Cannot add new MAC records (not implemented)."
            )

        existing_macs = mac_record.get('mac_addresses', {})
        old_payload_len = mac_record['length']
        if old_payload_len < 4:
            raise RuntimeError(
                f"Invalid MAC record payload size: {old_payload_len} bytes. "
                f"Minimum required: 4 bytes (IANA + Record ID). "
                f"EEPROM may be corrupted."
            )

        original_mac_count = (old_payload_len - 4) // 6
        if original_mac_count < 0 or original_mac_count > self.MAX_MAC_ADDRESSES:
            raise RuntimeError(
                f"Invalid MAC count calculated: {original_mac_count}. "
                f"Payload size: {old_payload_len} bytes. "
                f"EEPROM may be corrupted."
            )

        for mac_key in mac_dict.keys():
            mac_idx = int(mac_key.replace('mac', ''))
            if mac_idx >= original_mac_count:
                raise ValueError(
                    f"Cannot set {mac_key}: EEPROM only contains {original_mac_count} MAC address(es) "
                    f"(mac0-mac{original_mac_count-1}). "
                    f"To add more MAC addresses, use --from-bin to restore an EEPROM image "
                    f"with the desired MAC count."
                )

        mac_bytes_list = []
        for i in range(original_mac_count):
            mac_key = f'mac{i}'
            if mac_key in mac_dict:
                mac_str = mac_dict[mac_key].replace(':', '-').upper()
                mac_parts = mac_str.split('-')

                # Validate MAC address format
                if len(mac_parts) != 6:
                    raise ValueError(
                        f"Invalid MAC address format for {mac_key}: {mac_dict[mac_key]}. "
                        f"Expected format: XX:XX:XX:XX:XX:XX or XX-XX-XX-XX-XX-XX"
                    )

                try:
                    mac_bytes = bytes([int(p, 16) for p in mac_parts])
                except ValueError as e:
                    raise ValueError(
                        f"Invalid MAC address format for {mac_key}: {mac_dict[mac_key]}. "
                        f"Each byte must be a valid hex value (00-FF)."
                    ) from e

                mac_bytes_list.append(mac_bytes)
            elif mac_key in existing_macs:
                existing_mac_str = existing_macs[mac_key].replace('-', ':')
                existing_parts = existing_mac_str.split(':')
                mac_bytes = bytes([int(p, 16) for p in existing_parts])
                mac_bytes_list.append(mac_bytes)
            else:
                mac_bytes_list.append(b'\x00' * 6)

        new_payload = struct.pack('<I', self.XILINX_IANA)[0:3]
        new_payload += bytes([target_id])
        for mac_bytes in mac_bytes_list:
            new_payload += mac_bytes

        old_payload_len = mac_record['length']
        new_payload_len = len(new_payload)
        if new_payload_len != old_payload_len:
            raise RuntimeError(
                f"Cannot update MAC record: payload size mismatch. "
                f"Expected {old_payload_len} bytes ({original_mac_count}-MAC format), "
                f"got {new_payload_len} bytes. "
                f"This indicates a bug in the MAC address update logic. "
                f"Use --from-bin to restore a known-good EEPROM image."
            )
        if new_payload_len > 255:
            raise ValueError(
                f"Payload too large: {new_payload_len} bytes (max 255). "
                f"Cannot update MAC addresses."
            )

        rec_offset = mac_record['offset']
        rec_type = self.raw_data[rec_offset]
        rec_format = self.raw_data[rec_offset + 1]
        self.raw_data[rec_offset + 2] = new_payload_len
        checksum = self._calculate_checksum(new_payload)
        self.raw_data[rec_offset + 3] = checksum
        header_sum = (rec_type + rec_format + new_payload_len + checksum) & 0xff
        header_checksum = (0x100 - header_sum) & 0xff
        self.raw_data[rec_offset + 4] = header_checksum
        payload_start = rec_offset + 5
        payload_end = payload_start + old_payload_len
        self.raw_data[payload_start:payload_end] = new_payload

        modified_offset = rec_offset + 2
        modified_length = 3 + new_payload_len
        return bytes(self.raw_data), modified_offset, modified_length

    def _calculate_checksum(self, data: bytes) -> int:
        """Calculate FRU checksum."""
        checksum = sum(data) & 0xff
        return (0x100 - checksum) & 0xff


class EepromSysfsHandler:
    """Handler for EEPROM operations via sysfs interface."""

    # Write configuration constants
    CHUNK_SIZE = 32  # 32-byte chunks for I2C compatibility
    WRITE_DELAY_MS = 10  # 10ms delay between writes for EEPROM write cycle
    MAX_EEPROM_SIZE = 64 * 1024  # Maximum EEPROM size (64KB) for safety

    def __init__(self, eeprom_path: str, verbose: bool = False):
        self.eeprom_path = Path(eeprom_path)
        self.verbose = verbose
        self._device_dir = self.eeprom_path.parent

    def log(self, msg: str, level: str = 'info'):
        """Simple logging."""
        if level == 'debug' and not self.verbose:
            return

        # Map log levels to prefixes
        levels = {
            'debug': '[DEBUG]',
            'info': '[INFO]',
            'warning': '[WARNING]',
            'error': '[ERROR]'
        }
        prefix = levels.get(level, '[INFO]')

        # Route warnings and errors to stderr, info/debug to stdout
        stream = sys.stderr if level in ('warning', 'error') else sys.stdout
        print(f"{prefix} {msg}", file=stream)

    def enable_eeprom_write(self) -> bool:
        """Enable EEPROM writes by disabling write protection via GPIO.

        Returns:
            True if successful or not needed, False on error
        """
        try:
            # Run: timeout 1 gpioset EEPROM_WC_B=0
            result = subprocess.run(
                ['timeout', '1', 'gpioset', 'EEPROM_WC_B=0'],
                capture_output=True,
                text=True
            )

            if result.returncode == 0:
                self.log("EEPROM write protection disabled via gpioset", 'info')
                return True
            elif result.returncode == 124:  # timeout exit code
                self.log("gpioset command timed out (GPIO is being held, this is normal)", 'debug')
                return True  # Consider timeout as success since GPIO might be held
            else:
                # Command failed - check if it's because GPIO doesn't exist
                error_output = (result.stderr + result.stdout).lower()
                gpio_not_found = any(phrase in error_output for phrase in [
                    'not found',
                    'no such',
                    'cannot find',
                    'does not exist',
                    'unknown line'
                ])

                if gpio_not_found:
                    # GPIO doesn't exist - not needed on this board
                    return True
                else:
                    self.log(f"Failed to disable write protection: {result.stderr.strip()}, attempting write anyway", 'warning')
                    return True  # Try to proceed anyway
        except FileNotFoundError:
            # gpioset not installed - not needed if board has no write protection
            return True
        except Exception as e:
            self.log(f"Error disabling write protection: {e}, attempting write anyway", 'warning')
            return True  # Proceed anyway

    def validate_eeprom_path(self) -> bool:
        """Validate that EEPROM path exists and is accessible."""
        if not self.eeprom_path.exists():
            self.log(f"EEPROM path does not exist: {self.eeprom_path}", 'error')
            self.log("Check that I2C drivers are loaded: modprobe i2c-dev at24", 'error')
        elif not self.eeprom_path.is_file():
            self.log(f"EEPROM path is not a file: {self.eeprom_path}", 'error')
        elif not os.access(self.eeprom_path, os.R_OK):
            self.log(f"EEPROM path is not readable: {self.eeprom_path}", 'error')
            self.log("You may need root privileges. Try running with sudo.", 'error')
        else:
            return True

        return False

    def read_eeprom(self) -> Optional[bytes]:
        """Read entire EEPROM content."""
        try:
            self.log(f"Reading EEPROM from {self.eeprom_path}", 'debug')
            with open(self.eeprom_path, 'rb') as f:
                # Read with size limit to prevent memory exhaustion
                data = f.read(self.MAX_EEPROM_SIZE + 1)

            # Check for empty EEPROM
            if len(data) == 0:
                self.log("EEPROM appears to be empty (0 bytes read)", 'error')
                return None

            # Check for oversized EEPROM
            if len(data) > self.MAX_EEPROM_SIZE:
                self.log(f"EEPROM size exceeds maximum ({self.MAX_EEPROM_SIZE} bytes)", 'error')
                self.log("This may indicate corrupted data or malicious content", 'error')
                return None

            self.log(f"Read {len(data)} bytes from EEPROM", 'debug')
            return data
        except PermissionError:
            self.log("Permission denied. Try running with sudo.", 'error')
            return None
        except Exception as e:
            self.log(f"Error reading EEPROM: {e}", 'error')
            return None

    def write_eeprom(self, data: bytes, offset: int = 0, length: int = None,
                     backup: bool = True, use_chunked_write: bool = True) -> bool:
        """Write data to EEPROM with optional partial write support.

        Args:
            data: Binary data to write (full EEPROM image)
            offset: Starting offset for partial write (default 0 = full write)
            length: Number of bytes to write (default None = write all from offset)
            backup: Create backup before writing (default True for safety)
            use_chunked_write: If True, write in small chunks with delays for I2C compatibility

        Returns:
            True if write succeeded, False otherwise

        Note:
            When offset=0 and length=None, writes entire data (backward compatible).
            For partial writes, only bytes data[offset:offset+length] are written to EEPROM.
        """
        backup_path = None
        if backup:
            backup_path = f'/tmp/eeprom_pre_write_{os.getpid()}.backup'
            self.log(f"Creating pre-write backup at {backup_path}", 'debug')
            if not self.backup_eeprom(backup_path=backup_path, fail_on_error=False):
                self.log("Warning: Failed to create pre-write backup, continuing anyway", 'warning')
                backup_path = None

        if length is None:
            length = len(data) - offset
        if offset < 0 or length < 0:
            self.log(f"Invalid offset ({offset}) or length ({length})", 'error')
            return False

        if offset + length > len(data):
            self.log(f"Write range exceeds data size: offset={offset}, length={length}, data_size={len(data)}", 'error')
            return False

        write_data = data[offset:offset+length]
        write_offset = offset
        if offset == 0 and length == len(data):
            self.log(f"Writing {len(write_data)} bytes to EEPROM (full write)", 'info')
        else:
            self.log(f"Writing {len(write_data)} bytes to EEPROM at offset {write_offset} (partial write)", 'info')

        try:
            # Attempt to disable write protection via GPIO
            self.enable_eeprom_write()

            if not os.access(self.eeprom_path, os.W_OK):
                self.log(f"EEPROM path is not writable: {self.eeprom_path}", 'error')
                self.log("You may need root privileges. Try running with sudo.", 'error')
                return False

            # For I2C EEPROMs, chunked writes with delays prevent timeouts
            if use_chunked_write:
                chunk_size = self.CHUNK_SIZE
                write_delay = self.WRITE_DELAY_MS / 1000.0  # Convert to seconds

                # Use file locking to prevent concurrent writes
                with open(self.eeprom_path, 'r+b') as f:
                    try:
                        # Acquire exclusive lock
                        fcntl.flock(f.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                    except IOError:
                        self.log("EEPROM is locked by another process", 'error')
                        return False

                    try:
                        bytes_written = 0
                        for chunk_offset in range(0, len(write_data), chunk_size):
                            chunk = write_data[chunk_offset:chunk_offset + chunk_size]
                            f.seek(write_offset + chunk_offset)
                            written = f.write(chunk)
                            bytes_written += written

                            if written != len(chunk):
                                self.log(f"Partial write at offset {write_offset + chunk_offset}", 'error')
                                if backup_path and os.path.exists(backup_path):
                                    self.log("Attempting to restore from backup...", 'error')
                                    try:
                                        with open(backup_path, 'rb') as backup_f:
                                            backup_data = backup_f.read()
                                            f.seek(0)
                                            f.write(backup_data)
                                            f.flush()
                                            os.fsync(f.fileno())
                                        self.log("Successfully restored from backup", 'info')
                                    except Exception as restore_err:
                                        self.log(f"Failed to restore backup: {restore_err}", 'error')
                                        self.log("EEPROM may be corrupted - manual recovery required", 'error')
                                return False

                            f.flush()
                            if (chunk_offset + chunk_size) % 512 == 0 or (chunk_offset + chunk_size) >= len(write_data):
                                os.fsync(f.fileno())

                            time.sleep(write_delay)

                            if len(write_data) >= 1024 and chunk_offset % 1024 == 0 and chunk_offset > 0:
                                progress = (chunk_offset / len(write_data)) * 100
                                self.log(f"Progress: {progress:.0f}%", 'info')

                        if bytes_written != len(write_data):
                            self.log(f"Warning: Only wrote {bytes_written} of {len(write_data)} bytes", 'error')
                            return False

                        if len(write_data) >= 512:
                            self.log("Finalizing write...", 'debug')
                        f.flush()
                        os.fsync(f.fileno())
                    finally:
                        fcntl.flock(f.fileno(), fcntl.LOCK_UN)

                self.log("Write complete", 'info')
            else:
                mode = 'r+b' if (offset != 0 or length != len(data)) else 'wb'
                with open(self.eeprom_path, mode) as f:
                    if mode == 'r+b':
                        f.seek(write_offset)
                    bytes_written = f.write(write_data)
                    if bytes_written != len(write_data):
                        self.log(f"Warning: Only wrote {bytes_written} of {len(write_data)} bytes", 'error')
                        return False
                    f.flush()
                    os.fsync(f.fileno())

                self.log(f"Wrote {len(write_data)} bytes to EEPROM", 'info')

            if backup_path and os.path.exists(backup_path):
                try:
                    os.remove(backup_path)
                    self.log("Removed temporary backup", 'debug')
                except Exception as e:
                    self.log(f"Warning: Could not remove backup {backup_path}: {e}", 'warning')

            return True
        except (PermissionError, OSError) as e:
            if isinstance(e, PermissionError) or (hasattr(e, 'errno') and e.errno in (errno.EACCES, 13)):
                self.log("Permission denied - may indicate write protection or insufficient privileges", 'error')
            elif hasattr(e, 'errno'):
                if e.errno == errno.EROFS or 'Read-only file system' in str(e):
                    self.log("EEPROM is write-protected (read-only). Try: sudo timeout 1 gpioset EEPROM_WC_B=0", 'error')
                elif e.errno in (errno.ETIMEDOUT, 110):
                    self.log("I2C timeout - Try: sudo timeout 1 gpioset EEPROM_WC_B=0", 'error')
                else:
                    self.log(f"OS error writing EEPROM: {e} (errno: {e.errno})", 'error')
            else:
                self.log(f"Error writing EEPROM: {e}", 'error')
            return False
        except Exception as e:
            self.log(f"Error writing EEPROM: {e}", 'error')
            return False

    def backup_eeprom(self, backup_path: str = None, prefix: str = 'eeprom', fail_on_error: bool = False) -> bool:
        """Create a backup of EEPROM content.

        Args:
            backup_path: Explicit path for backup, or None to auto-generate timestamped name
            prefix: Prefix for auto-generated filename (used only if backup_path is None)
            fail_on_error: If True, log critical error on failure

        Returns:
            True if backup succeeded, False otherwise
        """
        data = self.read_eeprom()
        if data is None:
            return False

        # Generate timestamped path if not provided
        if backup_path is None:
            timestamp = time.strftime(TIMESTAMP_FILE_FORMAT)
            backup_path = f'./{prefix}_{timestamp}.backup'

        try:
            with open(backup_path, 'wb') as f:
                f.write(data)
            self.log(f"EEPROM backed up to {backup_path}", 'info')
            return True
        except Exception as e:
            msg = f"Error writing backup: {e}"
            self.log(msg, 'error' if fail_on_error else 'warning')
            return False
            return False