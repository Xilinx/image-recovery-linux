/*
 * Copyright (c) 2025 - 2026 Advanced Micro Devices, Inc. All Rights Reserved.
 * SPDX-License-Identifier: MIT
 */

// UFS Configuration Manager
class UFSConfigManager {
	constructor() {
		// this.deviceInfo = null; // Unused: deviceInfo not referenced elsewhere
		this.geometry = null;
		this.config = null;
		this.luns = [];
		this.init();
	}

	init() {
		// Wait for DOM to be ready
		if (document.readyState === 'loading') {
			document.addEventListener('DOMContentLoaded', () => this.initEventListeners());
		} else {
			this.initEventListeners();
		}
	}

	initEventListeners() {
		// Query button to reload defaults
		const queryBtn = document.getElementById('ufs-query-btn');
		if (queryBtn) queryBtn.addEventListener('click', () => this.queryDevice());

		// Configuration write button
		const writeBtn = document.getElementById('ufs-write-config-btn');
		if (writeBtn) writeBtn.addEventListener('click', () => this.writeConfiguration());

		// Initialize LU table
		this.initLUTable();

		// User must manually query device to load configuration
		this.logMessage('Click "Query Device" to load current UFS configuration.');
	}

	initLUTable() {
		const tbody = document.getElementById('ufs-lu-table-body');
		if (!tbody) return;

		// Create 8 LU rows
		for (let i = 0; i < 8; i++) {
			const row = this.createLURow(i);
			tbody.appendChild(row);
		}

		// Add event listeners for size inputs
		tbody.querySelectorAll('.ufs-lu-size-input').forEach(input => {
			input.addEventListener('input', () => this.updateSummary());
		});

		tbody.querySelectorAll('.ufs-lu-enable-checkbox').forEach(checkbox => {
			checkbox.addEventListener('change', () => this.updateSummary());
		});
	}

	createLURow(luNum) {
		const row = document.createElement('tr');
		row.innerHTML = `
	    <td>LU${luNum}</td>
	    <td>
		<input type="checkbox" class="ufs-lu-enable-checkbox" data-lu="${luNum}" />
	    </td>
	    <td>
		<input type="number" class="ufs-lu-size-input" data-lu="${luNum}"
		       min="0" step="0.1" value="0" style="width: 80px;" />
	    </td>
	    <td>
		<select class="ufs-lu-memory-type" data-lu="${luNum}">
		    <option value="0" selected>Normal (0x0)</option>
		    <option value="3">Enhanced 1 (0x3)</option>
		    <option value="4">Enhanced 2 (0x4)</option>
		    <option value="5">Enhanced 3 (0x5)</option>
		    <option value="6">Enhanced 4 (0x6)</option>
		</select>
	    </td>
	    <td>
		<select class="ufs-lu-boot-id" data-lu="${luNum}">
		    <option value="0" selected>None</option>
		    <option value="1">Boot A (0x1)</option>
		    <option value="2">Boot B (0x2)</option>
		</select>
	    </td>
	    <td>
		<select class="ufs-lu-write-protect" data-lu="${luNum}">
		    <option value="0" selected>None</option>
		    <option value="1">Power On WP</option>
		    <option value="2">Permanent WP</option>
		</select>
	    </td>
	    <td class="ufs-lu-alloc-units" data-lu="${luNum}">0</td>
	`;
		return row;
	}

	async queryDevice() {
		const devicePath = document.getElementById('ufs-device-path')?.value || '/dev/bsg/ufs-bsg0';
		this.logMessage('Loading default values from device: ' + devicePath);

		try {
			const response = await fetch(`cgi-bin/ufs_configure.sh?device=${encodeURIComponent(devicePath)}`);

			if (!response.ok) {
				throw new Error(`HTTP ${response.status}: ${response.statusText}`);
			}

			const data = await response.json();

			if (data.status === 'error') {
				this.logMessage('Error: ' + data.message, 'error');
				return;
			}

			// this.deviceInfo = data; // Unused: deviceInfo not referenced elsewhere
			this.geometry = data.geometry;
			this.config = data.config;

			this.updateDeviceInfo();
			this.loadCurrentConfiguration();
			this.logMessage('Default values loaded successfully. You can now modify and save.');

		} catch (error) {
			this.logMessage('Error loading device defaults: ' + error.message, 'error');
			this.logMessage('Please check device path and try again.', 'error');
		}
	}

	updateDeviceInfo() {
		// Geometry data is stored for calculations, no UI elements to update
		if (!this.geometry) return;
	}

	loadCurrentConfiguration() {
		if (!this.config) return;

		// Load LU configurations
		for (let i = 0; i < 8; i++) {
			const luKey = `LU${i}`;
			if (this.config[luKey]) {
				const luConfig = this.config[luKey];
				const enabled = luConfig.bLUEnable === '0x1';
				const allocUnits = parseInt(luConfig.dNumAllocUnits || '0', 16);
				const sizeGB = this.allocUnitsToGB(allocUnits);

				const checkbox = document.querySelector(`.ufs-lu-enable-checkbox[data-lu="${i}"]`);
				const sizeInput = document.querySelector(`.ufs-lu-size-input[data-lu="${i}"]`);
				const bootIdSelect = document.querySelector(`.ufs-lu-boot-id[data-lu="${i}"]`);
				const memTypeSelect = document.querySelector(`.ufs-lu-memory-type[data-lu="${i}"]`);

				if (checkbox) checkbox.checked = enabled;
				if (sizeInput) sizeInput.value = sizeGB;
				if (bootIdSelect) bootIdSelect.value = parseInt(luConfig.bBootLunID || '0', 16);
				if (memTypeSelect) memTypeSelect.value = parseInt(luConfig.bMemoryType || '0', 16);
			}
		}

		this.updateSummary();
	}

	allocUnitsToGB(allocUnits) {
		if (!this.geometry || allocUnits === 0) return 0;

		const segmentSize = parseInt(this.geometry.dSegmentSize || '0x2000', 16);
		const allocUnitSize = parseInt(this.geometry.bAllocationUnitSize || '1', 16);
		const capacityAdjFactor = 1; // For normal memory type

		const sizeBytes = allocUnits * segmentSize * allocUnitSize * 512 / capacityAdjFactor;
		return (sizeBytes / (1024 * 1024 * 1024)).toFixed(2);
	}

	gbToAllocUnits(sizeGB, memoryType = 0) {
		if (!this.geometry || sizeGB === 0) return 0;

		const segmentSize = parseInt(this.geometry.dSegmentSize || '0x2000', 16);
		const allocUnitSize = parseInt(this.geometry.bAllocationUnitSize || '1', 16);

		// Get capacity adjustment factor based on memory type
		let capacityAdjFactor = 1;
		if (memoryType === 3 && this.geometry.wEnhanced1CapAdjFac) {
			capacityAdjFactor = parseInt(this.geometry.wEnhanced1CapAdjFac, 16) / 256;
		} else if (memoryType === 4 && this.geometry.wEnhanced2CapAdjFac) {
			capacityAdjFactor = parseInt(this.geometry.wEnhanced2CapAdjFac, 16) / 256;
		} else if (memoryType === 5 && this.geometry.wEnhanced3CapAdjFac) {
			capacityAdjFactor = parseInt(this.geometry.wEnhanced3CapAdjFac, 16) / 256;
		} else if (memoryType === 6 && this.geometry.wEnhanced4CapAdjFac) {
			capacityAdjFactor = parseInt(this.geometry.wEnhanced4CapAdjFac, 16) / 256;
		}

		const sizeBytes = sizeGB * 1024 * 1024 * 1024;
		const allocUnits = Math.ceil((sizeBytes * capacityAdjFactor) / (segmentSize * allocUnitSize * 512));

		return allocUnits;
	}

	updateSummary() {
		// Check if geometry is available
		if (!this.geometry) {
			const totalAllocatedEl = document.getElementById('ufs-total-allocated');
			if (totalAllocatedEl) totalAllocatedEl.textContent = '0 GB';
			return;
		}

		let totalAllocated = 0;
		const tbody = document.getElementById('ufs-lu-table-body');
		if (!tbody) return;

		for (let i = 0; i < 8; i++) {
			const checkbox = tbody.querySelector(`.ufs-lu-enable-checkbox[data-lu="${i}"]`);
			const sizeInput = tbody.querySelector(`.ufs-lu-size-input[data-lu="${i}"]`);
			const memTypeSelect = tbody.querySelector(`.ufs-lu-memory-type[data-lu="${i}"]`);
			const allocUnitsCell = tbody.querySelector(`.ufs-lu-alloc-units[data-lu="${i}"]`);

			if (checkbox?.checked && sizeInput) {
				const sizeGB = parseFloat(sizeInput.value) || 0;
				const memType = parseInt(memTypeSelect?.value || '0');
				const allocUnits = this.gbToAllocUnits(sizeGB, memType);

				totalAllocated += sizeGB;
				if (allocUnitsCell) {
					allocUnitsCell.textContent = allocUnits;
				}
			} else if (allocUnitsCell) {
				allocUnitsCell.textContent = '0';
			}
		}

		// Calculate total capacity
		// const totalRawCapacity = parseInt(this.geometry.qTotalRawDeviceCapacity || '0', 16);
		// const totalCapacityGB = totalRawCapacity * 512 / (1024 * 1024 * 1024); // Unused: Remaining not displayed
		// const remaining = totalCapacityGB - totalAllocated; // Unused: Remaining not displayed

		const totalAllocatedEl = document.getElementById('ufs-total-allocated');
		if (totalAllocatedEl) {
			totalAllocatedEl.textContent = `${totalAllocated.toFixed(2)} GB`;
		}
	}

	async writeConfiguration() {
		if (!this.geometry) {
			this.logMessage('Please query device first', 'error');
			return;
		}

		// Collect LU configurations first for validation
		const tbody = document.getElementById('ufs-lu-table-body');
		const lu0Checkbox = tbody.querySelector(`.ufs-lu-enable-checkbox[data-lu="0"]`);
		const lu0BootId = tbody.querySelector(`.ufs-lu-boot-id[data-lu="0"]`);

		// Validate LU0 configuration (minimum requirement)
		if (!lu0Checkbox?.checked) {
			this.logMessage('ERROR: LU0 must be enabled (minimum requirement for boot)', 'error');
			alert('⚠️ ERROR: LU0 must be enabled.\n\nMinimum requirement: LU0 must be enabled with Boot A configuration.');
			return;
		}

		// Warn if LU0 is not configured as Boot A
		if (parseInt(lu0BootId?.value || '0') !== 1) {
			const bootSetting = lu0BootId?.selectedOptions[0]?.text || 'None';
			if (!confirm(`⚠️ WARNING: LU0 should typically be configured as Boot A.\n\nCurrent Boot LUN setting: ${bootSetting}\n\nTypical configuration requires LU0 = Boot A (0x1).\n\nContinue anyway?`)) {
				this.logMessage('Write operation cancelled by user', 'info');
				return;
			}
		}

		// Confirmation dialog before modifying hardware
		if (!confirm('⚠️ WARNING: This will update UFS device configuration.\n\nChanges are written to hardware and may require a reboot.\n\nContinue?')) {
			this.logMessage('Write operation cancelled by user', 'info');
			return;
		}

		const devicePath = document.getElementById('ufs-device-path')?.value || '/dev/bsg/ufs-bsg0';

		// Collect LU configurations
		const luns = [];

		for (let i = 0; i < 8; i++) {
			const checkbox = tbody.querySelector(`.ufs-lu-enable-checkbox[data-lu="${i}"]`);
			const sizeInput = tbody.querySelector(`.ufs-lu-size-input[data-lu="${i}"]`);
			const memTypeSelect = tbody.querySelector(`.ufs-lu-memory-type[data-lu="${i}"]`);
			const bootIdSelect = tbody.querySelector(`.ufs-lu-boot-id[data-lu="${i}"]`);
			const wpSelect = tbody.querySelector(`.ufs-lu-write-protect[data-lu="${i}"]`);

			const enabled = checkbox?.checked || false;
			const sizeGB = parseFloat(sizeInput?.value || '0');
			const memType = parseInt(memTypeSelect?.value || '0');
			const allocUnits = this.gbToAllocUnits(sizeGB, memType);

			luns.push({
				enabled: enabled,
				allocUnits: allocUnits,
				bootLunId: parseInt(bootIdSelect?.value || '0'),
				writeProtect: parseInt(wpSelect?.value || '0'),
				memoryType: memType
			});
		}

		const configData = {
			device: devicePath,
			luns: luns
		};

		this.logMessage('Writing configuration to device...');
		this.logMessage(JSON.stringify(configData, null, 2));

		try {
			const response = await fetch('cgi-bin/ufs_configure.sh', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify(configData)
			});

			// Log raw response for debugging
			const responseText = await response.text();
			this.logMessage('Raw response: ' + responseText.substring(0, 200));

			let result;
			try {
				result = JSON.parse(responseText);
			} catch (parseError) {
				this.logMessage('JSON parse failed at position: ' + parseError.message, 'error');
				this.logMessage('Response excerpt: ' + responseText.substring(0, 300), 'error');
				return;
			}

			if (result.status === 'error') {
				this.logMessage('Error: ' + result.message, 'error');
				if (result.details) {
					this.logMessage('Details: ' + result.details, 'error');
				}
			} else {
				this.logMessage('Success: ' + result.message, 'success');

				const debugFile = result.verification?.debug_file;
				const modal = window.app?.modal;
				const details = {
					'Status': result.message || 'Configuration written successfully',
					...(result.device && { 'Device': result.device }),
					...(debugFile && { 'Config Binary': debugFile })
				};
				if (modal?.showModal) {
					modal.showModal('Configuration Updated', details, true);
				} else if (debugFile) {
					alert(`Configuration written successfully.\nConfig binary: ${debugFile}`);
				} else {
					alert('Configuration written successfully.');
				}
			}

		} catch (error) {
			this.logMessage('Error writing configuration: ' + error.message, 'error');
		}
	}

	logMessage(message, type = 'info') {
		const logOutput = document.getElementById('ufs-log-output');
		const timestamp = new Date().toLocaleTimeString();
		const prefix = type === 'error' ? '[ERROR]' : type === 'success' ? '[SUCCESS]' : '[INFO]';

		if (logOutput) {
			const logEntry = `${timestamp} ${prefix} ${message}\n`;
			logOutput.textContent += logEntry;
			logOutput.scrollTop = logOutput.scrollHeight;
		}

		console.log(`UFS Config ${prefix}:`, message);
	}
}

// Initialize UFS Config Manager when DOM is ready
if (document.readyState === 'loading') {
	document.addEventListener('DOMContentLoaded', () => {
		window.ufsConfigManager = new UFSConfigManager();
	});
} else {
	window.ufsConfigManager = new UFSConfigManager(); }
