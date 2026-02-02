/*
* Copyright (c) 2025 - 2026 Advanced Micro Devices, Inc. All Rights Reserved.
* SPDX-License-Identifier: MIT
*/

// CONFIGURATION
const CONTENT_MAP = {
    'System Information': 'system-info-content',
    'Ethernet Recovery': 'ethernet-recovery-content',
    'USB Recovery': 'usb-recovery-content'
};

const FIELDS = {
    board: [
        { label: 'Name', id: 'BoardName' },
        { label: 'Revision', id: 'RevisionNo' },
        { label: 'Serial', id: 'SerialNo' },
        { label: 'Part', id: 'PartNo' },
        { label: 'UUID', id: 'UUID' }
    ],
    bootStatus: [
        { label: 'Bank A', id: 'bank-a' },
        { label: 'Bank B', id: 'bank-b' },
        { label: 'Active Bank', id: 'active-bank' },
        { label: 'Previous Active Bank', id: 'prev-active-bank' },
        { label: 'Bank A Version', id: 'bank-a-version' },
        { label: 'Bank B Version', id: 'bank-b-version' }
    ]
};

const USB_MODAL_TITLES = {
    boot: 'Select Boot Image from USB',
    wic: 'Select WIC Image from USB',
    bmap: 'Select BMAP File from USB'
};

class DOMManager {
    constructor() {
        this.elements = {};
        this.cacheElements();
    }

    cacheElements() {
        const getElement = id => document.getElementById(id);
        this.elements.sysBoardTbody = getElement('sysboard-tbody');
        this.elements.carrierTbody = getElement('carrier-tbody');
        this.elements.bootStatusTbody = getElement('boot-status-tbody');
        this.elements.carrierSection = getElement('carrier-card-section');
        this.elements.progress = {
            boot: {
                container: getElement('boot-image-progress-container'),
                fill: getElement('boot-image-progress-fill'),
                text: getElement('boot-image-progress-text')
            },
            wic: {
                container: getElement('wic-image-progress-container'),
                fill: getElement('wic-image-progress-fill'),
                text: getElement('wic-image-progress-text')
            },
            usbBoot: {
                container: getElement('usb-boot-image-progress-container'),
                fill: getElement('usb-boot-image-progress-fill'),
                text: getElement('usb-boot-image-progress-text')
            },
            usbWic: {
                container: getElement('usb-wic-image-progress-container'),
                fill: getElement('usb-wic-image-progress-fill'),
                text: getElement('usb-wic-image-progress-text')
            }
        };
        this.elements.modal = getElement('custom-modal');
        this.elements.modalTitle = getElement('modal-title');
        this.elements.modalBody = getElement('modal-body');
        this.elements.modalClose = getElement('modal-close');
        this.elements.modalOk = getElement('modal-ok-btn');
        this.elements.modal2 = getElement('custom-modal-2');
        this.elements.modal2Title = getElement('modal-2-title');
        this.elements.modal2Body = getElement('modal-2-body');
        this.elements.modal2Close = getElement('modal-2-close');
        this.elements.modal2Ok = getElement('modal-2-ok-btn');
    }

    get(path) {
        const parts = path.split('.');
        let current = this.elements;
        for (const part of parts) {
            current = current?.[part];
            if (!current) return null;
        }
        return current;
    }
}

class ProgressBarManager {
    constructor(domManager) {
        this.dom = domManager;
        this.progressMap = {
            'wic': 'wic',
            'usb-boot': 'usbBoot',
            'usb-wic': 'usbWic',
            'boot': 'boot'
        };
    }

    _getProgressKey(type) {
        return this.progressMap[type] || type;
    }

    update(type, percent) {
        const progressKey = this._getProgressKey(type);
        const progress = this.dom.get(`progress.${progressKey}`);
        if (!progress) return;
        if (progress.fill) progress.fill.style.width = `${percent}%`;
        if (progress.text) progress.text.textContent = `${percent}%`;
    }

    reset(type) {
        const progressKey = this._getProgressKey(type);
        const progress = this.dom.get(`progress.${progressKey}`);
        if (!progress) return;
        progress.container?.classList.add('hidden');
        if (progress.fill) progress.fill.style.width = '0%';
        if (progress.text) progress.text.textContent = '0%';
    }

    show(type) {
        const progressKey = this._getProgressKey(type);
        const progress = this.dom.get(`progress.${progressKey}`);
        if (progress?.container) {
            progress.container.classList.remove('hidden');
        }
    }

    setMessage(type, message) {
        const progress = this.dom.get(`progress.${type}`);
        if (progress?.text) {
            progress.text.textContent = message;
        }
    }
}

class ModalManager {
    constructor(domManager) {
        this.dom = domManager;
    }

    toggle(modalElement, show, onClose = null) {
        if (!modalElement) return;
        modalElement.classList.toggle('hidden', !show);
        modalElement.setAttribute('aria-hidden', !show);
        if (!show && onClose) onClose();
    }

    showModal(title, details, isSuccess = true, resetUSB = false, onClose = null) {
        const modal = this.dom.elements.modal;
        const modalTitle = this.dom.elements.modalTitle;
        const modalBody = this.dom.elements.modalBody;
        const modalClose = this.dom.elements.modalClose;
        const modalOk = this.dom.elements.modalOk;

        if (!modal || !modalTitle || !modalBody) return;

        modalTitle.textContent = title;

        const icon = isSuccess
            ? '<div class="modal-success-icon">✓</div>'
            : '<div class="modal-error-icon">✗</div>';

        const infoGrid = Object.entries(details)
            .map(([key, value]) =>
                `<div class="modal-info-label">${key}:</div><div class="modal-info-value">${value}</div>`
            ).join('');

        modalBody.innerHTML = `${icon}<div class="modal-info-grid">${infoGrid}</div>`;

        this.toggle(modal, true);

        const escHandler = (e) => {
            if (e.key === 'Escape') {
                closeModal();
            }
        };
        const closeModal = () => {
            this.toggle(modal, false);
            document.removeEventListener('keydown', escHandler);
            if (onClose) onClose(resetUSB);
        };

        modalClose.onclick = closeModal;
        modalOk.onclick = closeModal;
        modal.onclick = (e) => e.target === modal && closeModal();
        document.addEventListener('keydown', escHandler);
    }

    showUSBPickerModal(title, onSelect, onRefresh, onCancel) {
        const modal2 = this.dom.elements.modal2;
        const modal2Title = this.dom.elements.modal2Title;
        const modal2Body = this.dom.elements.modal2Body;
        const modal2Close = this.dom.elements.modal2Close;
        if (!modal2 || !modal2Title || !modal2Body) return;
        modal2Title.textContent = title;
        // Batch DOM queries
        const elements = {
            status: document.getElementById('usb-scan-status'),
            tableBody: document.getElementById('file-table-body'),
            folderTree: document.getElementById('folder-tree'),
            selectBtn: document.getElementById('modal-select-btn'),
            cancelBtn: document.getElementById('modal-cancel-btn'),
            refreshBtn: document.getElementById('modal-refresh-btn')
        };
        if (elements.status) {
            elements.status.textContent = 'Scanning USB devices...';
            elements.status.className = 'usb-status';
        }
        if (elements.tableBody) {
            elements.tableBody.innerHTML = '<tr class="empty-row"><td colspan="1" class="empty-message">Select a folder to view files</td></tr>';
        }
        if (elements.folderTree) elements.folderTree.innerHTML = '';
        this.toggle(modal2, true);
        if (elements.selectBtn) elements.selectBtn.disabled = true;
        const closeModal = () => {
            this.toggle(modal2, false);
        };
        modal2Close.onclick = () => {
            closeModal();
            if (onCancel) onCancel();
        };
        if (elements.cancelBtn) {
            elements.cancelBtn.onclick = () => {
                closeModal();
                if (onCancel) onCancel();
            };
        }
        if (elements.selectBtn) {
            elements.selectBtn.onclick = () => {
                if (onSelect) {
                    const shouldClose = onSelect();
                    if (shouldClose) closeModal();
                }
            };
        }
        if (elements.refreshBtn && onRefresh) {
            elements.refreshBtn.onclick = onRefresh;
        }
        const escHandler = (e) => {
            if (e.key === 'Escape') {
                closeModal();
                if (onCancel) onCancel();
                document.removeEventListener('keydown', escHandler);
            }
        };
        document.addEventListener('keydown', escHandler);
    }

    enableUSBSelectButton(enabled) {
        const modalSelectBtn = document.getElementById('modal-select-btn');
        if (modalSelectBtn) {
            modalSelectBtn.disabled = !enabled;
        }
    }
}

class SystemInfoManager {
    constructor(domManager) {
        this.dom = domManager;
    }

    initialize() {
        this.populateSystemTables();
        this.fetchSystemInfo();
        this.fetchBootStatus();
    }

    populateSystemTables() {
        const createTableRows = (tbody, fields, prefix = '') =>
            tbody.innerHTML = fields.map(field =>
                `<tr><td>${field.label} :</td><td id="${prefix}${field.id}"></td></tr>`
            ).join('');

        createTableRows(this.dom.elements.sysBoardTbody, FIELDS.board, 'board-');
        createTableRows(this.dom.elements.carrierTbody, FIELDS.board, 'carrier-');
        createTableRows(this.dom.elements.bootStatusTbody, FIELDS.bootStatus);
    }

    fetchJSON(url, description) {
        return fetch(url)
            .then(response => {
                if (!response.ok) throw new Error(`HTTP ${response.status}`);
                return response.json();
            })
            .catch(error => {
                console.error(`Failed to fetch ${description}:`, error);
                return null;
            });
    }

    fetchSystemInfo() {
        this.fetchJSON('cgi-bin/sysinfo_eeprom.sh', 'system information')
            .then(data => {
                if (!data) return;

                const updateFields = (prefix, source) => {
                    if (!source) return;
                    FIELDS.board.forEach(field => {
                        const element = document.getElementById(`${prefix}${field.id}`);
                        if (element) element.textContent = source[field.id] || 'N/A';
                    });
                };

                updateFields('board-', data.SysBoardInfo);
                if (data.CcInfo?.BoardName) {
                    updateFields('carrier-', data.CcInfo);
                    this.dom.elements.carrierSection?.classList.remove('hidden');
                }
            });
    }

    fetchBootStatus() {
        this.fetchJSON('cgi-bin/bootstatus.sh', 'boot status')
            .then(data => {
                if (!data || !this.dom.elements.bootStatusTbody) return;

                const isActiveImageA = data.ActiveBank === "ImageA";
                const cells = Array.from(this.dom.elements.bootStatusTbody.rows).map(row => row.cells[1]);

                if (cells.length >= 6) {
                    cells[0].textContent = data.BankAStatus ? "Accepted" : "Rejected";
                    cells[1].textContent = data.BankBStatus ? "Accepted" : "Rejected";
                    cells[2].textContent = isActiveImageA ? "Bank A" : "Bank B";
                    cells[3].textContent = data.PrevActiveBank === "ImageA" ? "Bank A" : "Bank B";
                    cells[4].textContent = isActiveImageA ? (data.version_active || '-') : (data.version_prev || '-');
                    cells[5].textContent = isActiveImageA ? (data.version_prev || '-') : (data.version_active || '-');
                }
            });
    }
}

class StorageDeviceManager {
    constructor() {
        this.devices = [];
        this.selectedDevice = {
            ethernet: null,
            usb: null
        };
    }

    async fetchDevices() {
        try {
            const response = await fetch('cgi-bin/detect_storage_device.sh');
            if (!response.ok) throw new Error('Failed to fetch devices');
            const devices = await response.json();
            this.devices = devices;
            return devices;
        } catch (error) {
            console.error('Error fetching storage devices:', error);
            return [];
        }
    }

    populateDropdown(selectElement, devices, selectedValue = null) {
        if (!selectElement) return;
        selectElement.innerHTML = '';
        if (!devices || devices.length === 0) {
            selectElement.innerHTML = '<option value="">No devices found</option>';
            selectElement.disabled = true;
            return;
        }
        selectElement.disabled = false;
        selectElement.innerHTML = '<option value="">Select a storage device...</option>';
        devices.forEach(device => {
            const option = document.createElement('option');
            option.value = device.device;
            const sizeGB = (device.size / (1024 * 1024 * 1024)).toFixed(2);
            const busType = device.bus.toUpperCase();
            const model = device.model !== 'unknown' ? `(${device.model})` : '';
            option.textContent = `${device.device} - ${busType} ${model} - ${sizeGB} GB`.replace(/  +/g, ' ').trim();
            option.selected = selectedValue === device.device;
            selectElement.appendChild(option);
        });
    }

    async refreshDeviceList(type) {
        const deviceType = type === 'usb' ? 'usb' : 'ethernet';
        const selectElement = document.getElementById(
            type === 'usb' ? 'usb-wic-storage-device' : 'wic-storage-device'
        );
        if (!selectElement) return;
        selectElement.innerHTML = '<option value="">Loading devices...</option>';
        selectElement.disabled = true;
        const devices = await this.fetchDevices();
        this.populateDropdown(selectElement, devices, this.selectedDevice[deviceType]);
    }

    setSelectedDevice(type, device) {
        const deviceType = type === 'usb' ? 'usb' : 'ethernet';
        this.selectedDevice[deviceType] = device;
    }

    getSelectedDevice(type) {
        const deviceType = type === 'usb' ? 'usb' : 'ethernet';
        return this.selectedDevice[deviceType];
    }
}

class FileHandlerManager {
    constructor(progressBarManager) {
        this.progressBar = progressBarManager;
    }

    formatFileSize(bytes) {
        if (!bytes) return '0 Bytes';
        const k = 1024;
        const sizes = ['Bytes', 'KB', 'MB', 'GB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return `${(bytes / Math.pow(k, i)).toFixed(2)} ${sizes[i]}`;
    }

    displayFileInfo(file, infoElement) {
        if (!file || !infoElement) return;
        infoElement.innerHTML = `<div class="file-details">File: ${file.name}<br>Size: ${this.formatFileSize(file.size)}</div>`;
    }

    validateFileExtension(file, inputElement, modalManager) {
        const acceptedExtensions = inputElement.getAttribute('accept');
        if (!acceptedExtensions) return true;

        const extensions = acceptedExtensions.split(',').map(ext => ext.trim().toLowerCase());
        const fileExtension = '.' + file.name.split('.').pop().toLowerCase();

        if (!extensions.includes(fileExtension)) {
            modalManager.showModal('Invalid File Type', {
                'File': file.name,
                'Error': `Only ${acceptedExtensions} files are allowed`,
                'Required': `Please select a file with ${acceptedExtensions} extension`
            }, false);
            return false;
        }
        return true;
    }

    clearFileSelection(input, info, btn, uploadBtn) {
        input?.value && (input.value = '');
        info?.innerHTML && (info.innerHTML = '');
        btn?.classList.remove('file-selected', 'active');
        uploadBtn?.classList.add('hidden');
    }

    clearBmapSelection() {
        const elements = {
            input: document.getElementById('bmap-file-input'),
            container: document.getElementById('bmap-file-container'),
            btn: document.getElementById('bmap-file-btn'),
            info: document.getElementById('bmap-file-info'),
            note: document.getElementById('bmap-note')
        };
        if (elements.input) elements.input.value = '';
        elements.container?.classList.add('hidden');
        elements.btn?.classList.remove('file-selected');
        if (elements.info) elements.info.innerHTML = '';
        if (elements.note) elements.note.innerHTML = '';
    }

    handleFileSelection(file, inputElement, infoElement, btn, uploadBtn, modalManager, isWicImage = false, type = 'ethernet') {
        if (!file) {
            this.clearFileSelection(inputElement, infoElement, btn, uploadBtn);
            return;
        }
        if (!this.validateFileExtension(file, inputElement, modalManager)) {
            this.clearFileSelection(inputElement, infoElement, btn, uploadBtn);
            return;
        }
        this.displayFileInfo(file, infoElement);
        btn.classList.add('file-selected');
        const shouldShowUpload = !isWicImage || (window.app?.storageDevice.getSelectedDevice(type));
        uploadBtn.classList.toggle('hidden', !shouldShowUpload);
    }

    toggleActiveButton(buttons, activeButton) {
        buttons.forEach(btn => btn?.classList.remove('active'));
        activeButton?.classList.add('active');
    }
}

class USBRecoveryManager {
    constructor(modalManager, fileHandlerManager) {
        this.modal = modalManager;
        this.fileHandler = fileHandlerManager;
        this.state = {
            selectedFile: null,
            selectedBmapFile: null,
            savedWicFile: null,
            allDevices: {}
        };
    }

    openFilePicker(type) {
        const title = USB_MODAL_TITLES[type] || 'Select File from USB';
        if (type === 'boot' || type === 'wic') {
            this.state.selectedBmapFile = null;
            this.state.savedWicFile = null;
            const bmapInfo = document.getElementById('usb-bmap-file-info');
            const bmapBtn = document.getElementById('usb-bmap-file-btn');
            const bmapNote = document.getElementById('usb-bmap-note');
            if (bmapInfo) bmapInfo.innerHTML = '';
            if (bmapBtn) bmapBtn.classList.remove('file-selected');
            if (bmapNote) bmapNote.innerHTML = '';
        } else if (type === 'bmap') {
            // Save current WIC file before opening bmap picker
            this.state.savedWicFile = this.state.selectedFile;
        }
        this.modal.showUSBPickerModal(
            title,
            () => this.handleFileSelect(type),
            () => this.scanUSBFiles(),
            () => this.resetUSBRecoveryButtons()
        );
        this.scanUSBFiles();
    }

    handleFileSelect(type) {
        if (!this.state.selectedFile) return false;
        const fileName = this.state.selectedFile.split('/').pop();
        const isBootImage = type === 'boot';
        const isBmapFile = type === 'bmap';
        if (isBmapFile) {
            // For bmap file: save it separately and restore the original WIC file path
            const bmapPath = this.state.selectedFile;
            this.state.selectedBmapFile = bmapPath;
            // Restore the WIC file path that was saved before opening bmap picker
            if (this.state.savedWicFile) {
                this.state.selectedFile = this.state.savedWicFile;
            }
            const bmapInfo = document.getElementById('usb-bmap-file-info');
            const bmapBtn = document.getElementById('usb-bmap-file-btn');
            const bmapNote = document.getElementById('usb-bmap-note');
            if (bmapInfo) {
                bmapInfo.innerHTML = `<div class="file-details">BMAP File: ${fileName}</div>`;
            }
            if (bmapBtn) bmapBtn.classList.add('file-selected');
            if (bmapNote) bmapNote.innerHTML = 'BMAP file selected from USB device';
        } else {
            const infoElement = document.getElementById(isBootImage ? 'usb-boot-image-info' : 'usb-wic-image-info');
            const uploadBtn = document.getElementById(isBootImage ? 'usb-boot-image-upload-btn' : 'usb-wic-image-upload-btn');
            if (infoElement) {
                infoElement.innerHTML = `<div class="file-details">File: ${fileName} | Path: ${this.state.selectedFile}</div>`;
            }
            // For boot images, show upload button immediately
            // For WIC images, only show if device is selected
            if (isBootImage) {
                if (uploadBtn) {
                    uploadBtn.classList.remove('hidden');
                    uploadBtn.disabled = false;
                    uploadBtn.textContent = 'Upload';
                }
            } else {
                // Check if device is selected for WIC images
                const deviceSelected = window.app && window.app.storageDevice.getSelectedDevice('usb');
                if (uploadBtn) {
                    if (deviceSelected) {
                        uploadBtn.classList.remove('hidden');
                        uploadBtn.disabled = false;
                        uploadBtn.textContent = 'Upload';
                    } else {
                        uploadBtn.classList.add('hidden');
                    }
                }
            }
            const bmapFileBtn = document.getElementById('usb-bmap-file-btn');
            const bmapNote = document.getElementById('usb-bmap-note');
            const bmapInfo = document.getElementById('usb-bmap-file-info');
            if (isBootImage) {
                if (bmapFileBtn) {
                    bmapFileBtn.classList.add('hidden');
                    bmapFileBtn.classList.remove('file-selected');
                }
                if (bmapNote) bmapNote.innerHTML = '';
                if (bmapInfo) bmapInfo.innerHTML = '';
                this.state.selectedBmapFile = null;
            } else {
                if (bmapFileBtn) bmapFileBtn.classList.remove('hidden');
                if (bmapNote) bmapNote.innerHTML = 'Note: Optionally select the .bmap file. If not provided, the system will check the WIC Image directory';
                // Show device selector for USB WIC images
                if (window.app) {
                    window.app.showDeviceSelector('usb');
                }
            }
        }
        return true;
    }

    scanUSBFiles() {
        const status = document.getElementById('usb-scan-status');
        if (!status) return;
        status.textContent = 'Scanning USB devices...';
        status.className = 'usb-status';
        fetch('cgi-bin/scan_usbdev.sh')
            .then(response => response.ok ? response.text() : Promise.reject(`HTTP error! status: ${response.status}`))
            .then(data => this.parseUSBFiles(data))
            .catch(error => {
                console.error('Error scanning USB:', error);
                status.textContent = 'Error: Failed to scan USB devices. Please check connection.';
            });
    }

    parseUSBFiles(data) {
        const status = document.getElementById('usb-scan-status');
        if (!status) return;
        const lines = data.trim().split('\n');
        const devices = {};
        let currentDevice = null;
        for (const line of lines) {
            const trimmedLine = line.trim();
            if (trimmedLine.startsWith('Device:')) {
                currentDevice = trimmedLine.replace('Device:', '').trim();
                devices[currentDevice] = { files: [], directories: [] };
            } else if (trimmedLine.startsWith('FILE:') && currentDevice) {
                devices[currentDevice].files.push(trimmedLine.replace('FILE:', '').trim());
            } else if (trimmedLine.startsWith('DIR:') && currentDevice) {
                devices[currentDevice].directories.push(trimmedLine.replace('DIR:', '').trim());
            }
        }
        const deviceCount = Object.keys(devices).length;
        if (deviceCount === 0) {
            status.textContent = 'No USB devices found. Please connect a USB drive.';
            return;
        }
        this.state.allDevices = {};
        for (const [deviceName, deviceData] of Object.entries(devices)) {
            this.state.allDevices[deviceName] = this.buildDirectoryTree(deviceName, deviceData.files, deviceData.directories);
        }
        status.textContent = `Found ${deviceCount} USB device(s)`;
        this.renderTwoPanelLayout(this.state.allDevices);
    }

    buildDirectoryTree(deviceName, files, directories) {
        const basePrefix = `usb_disk/${deviceName}`;
        const tree = { name: deviceName, type: 'device', children: {}, path: basePrefix };
        // Process directories first
        const basePrefixLen = basePrefix.length + 1;
        directories.forEach(dirPath => {
            const relativePath = dirPath.substring(basePrefixLen);
            const parts = relativePath.split('/');
            let current = tree.children;
            let currentPath = basePrefix;
            for (const part of parts) {
                currentPath += `/${part}`;
                if (!current[part]) {
                    current[part] = { name: part, type: 'directory', children: {}, path: currentPath };
                }
                current = current[part].children;
            }
        });
        // Process files
        files.forEach(filePath => {
            const lastSlashIdx = filePath.lastIndexOf('/');
            const fileName = filePath.substring(lastSlashIdx + 1);
            const dirPath = filePath.substring(0, lastSlashIdx);
            const relativePath = dirPath.substring(basePrefix.length);
            const parts = relativePath.split('/').filter(Boolean);
            let current = tree.children;
            for (const part of parts) {
                if (current[part]) current = current[part].children;
            }
            current[fileName] = { name: fileName, type: 'file', path: filePath };
        });
        return tree;
    }

    renderTwoPanelLayout(allDevices) {
        const folderTree = document.getElementById('folder-tree');
        const tableBody = document.getElementById('file-table-body');
        if (!folderTree || !tableBody) return;
        tableBody.innerHTML = '<tr class="empty-row"><td colspan="1" class="empty-message">Select a folder to view files</td></tr>';
        this.renderFolderTree(allDevices, folderTree);
    }

    renderFolderTree(allDevices, container) {
        const html = [];
        for (const [deviceName, tree] of Object.entries(allDevices)) {
            html.push(`
                <div class="tree-item device-item" data-path="${tree.path}" data-device="${deviceName}" data-expanded="false">
                    <span class="tree-expand">▶</span>
                    <span class="tree-label">${deviceName}</span>
                </div>
            `);
        }
        container.innerHTML = html.join('');
        this.addTreeItemListeners(allDevices);
    }

    addTreeItemListeners(allDevices) {
        document.querySelectorAll('.tree-item').forEach(item => {
            const expandIcon = item.querySelector('.tree-expand');
            if (expandIcon) {
                expandIcon.addEventListener('click', (e) => {
                    e.stopPropagation();
                    this.toggleTreeExpansion(item, allDevices);
                });
            }
            item.addEventListener('click', () => {
                document.querySelectorAll('.tree-item').forEach(t => t.classList.remove('selected'));
                item.classList.add('selected');
                const path = item.dataset.path;
                const deviceName = item.dataset.device;
                const tree = allDevices[deviceName];
                const node = this.findNodeByPath(tree, path);
                if (node) this.renderFilesForDirectory(node);
            });
        });
    }

    toggleTreeExpansion(item, allDevices) {
        const isExpanded = item.dataset.expanded === 'true';
        const path = item.dataset.path;
        const deviceName = item.dataset.device;
        const expandIcon = item.querySelector('.tree-expand');
        if (isExpanded) {
            item.dataset.expanded = 'false';
            if (expandIcon) expandIcon.textContent = '▶';
            let nextSibling = item.nextElementSibling;
            while (nextSibling && nextSibling.classList.contains('tree-item-child')) {
                const toRemove = nextSibling;
                nextSibling = nextSibling.nextElementSibling;
                toRemove.remove();
            }
        } else {
            item.dataset.expanded = 'true';
            if (expandIcon) expandIcon.textContent = '▼';
            const tree = allDevices[deviceName];
            const node = this.findNodeByPath(tree, path);
            if (node && node.children) {
                const childDirs = [];
                for (const [name, child] of Object.entries(node.children)) {
                    if (child.type === 'directory') {
                        childDirs.push({ name, child });
                    }
                }
                childDirs.reverse().forEach(({ name, child }) => {
                    const hasSubdirs = child.children && Object.values(child.children).some(c => c.type === 'directory');
                    const childItem = document.createElement('div');
                    childItem.className = 'tree-item tree-item-child';
                    childItem.dataset.path = child.path;
                    childItem.dataset.device = deviceName;
                    childItem.dataset.expanded = 'false';
                    childItem.style.paddingLeft = '30px';
                    childItem.innerHTML = `
                        ${hasSubdirs ? '<span class="tree-expand">▶</span>' : '<span class="tree-expand-placeholder"></span>'}
                        <span class="tree-label">${name}</span>
                    `;
                    item.parentNode.insertBefore(childItem, item.nextSibling);
                });
                this.addTreeItemListeners(allDevices);
            }
        }
    }

    findNodeByPath(tree, path) {
        if (tree.path === path) return tree;
        if (!tree.children) return null;
        for (const child of Object.values(tree.children)) {
            const found = this.findNodeByPath(child, path);
            if (found) return found;
        }
        return null;
    }

    renderFilesForDirectory(node) {
        const tableBody = document.getElementById('file-table-body');
        if (!tableBody || !node) return;
        const items = [];
        if (node.children) {
            for (const [name, child] of Object.entries(node.children)) {
                if (child.type === 'directory') {
                    items.push({ ...child, itemType: 'folder' });
                }
            }
            for (const [name, child] of Object.entries(node.children)) {
                if (child.type === 'file') {
                    items.push({ ...child, itemType: 'file' });
                }
            }
        }
        if (items.length === 0) {
            tableBody.innerHTML = '<tr class="empty-row"><td colspan="1" class="empty-message">This folder is empty</td></tr>';
            return;
        }
        const sortedItems = this.sortExplorerItems(items);
        tableBody.innerHTML = sortedItems.map(item => {
            const isFolder = item.itemType === 'folder';
            return `
                <tr class="file-row ${isFolder ? 'folder-row' : ''}" data-path="${item.path}" data-name="${item.name}" data-type="${item.itemType}">
                    <td class="cell-name">
                        <span class="file-name">${item.name}</span>
                    </td>
                </tr>
            `;
        }).join('');
        // Use event delegation instead of individual listeners
        if (!tableBody._hasRowDelegation) {
            tableBody.addEventListener('click', (e) => {
                const row = e.target.closest('.file-row');
                if (row) this.selectFileRow(row);
            });
            tableBody.addEventListener('dblclick', (e) => {
                const row = e.target.closest('.file-row');
                if (row) this.handleRowDoubleClick(row);
            });
            tableBody._hasRowDelegation = true;
        }
    }

    sortExplorerItems(items) {
        return items.sort((a, b) => {
            if (a.itemType !== b.itemType) {
                return a.itemType === 'folder' ? -1 : 1;
            }
            return a.name.localeCompare(b.name, undefined, { numeric: true, sensitivity: 'base' });
        });
    }

    selectFileRow(row) {
        document.querySelectorAll('.file-row').forEach(r => r.classList.remove('selected'));
        row.classList.add('selected');
        const filePath = row.dataset.path;
        const fileType = row.dataset.type;
        if (fileType === 'file') {
            this.state.selectedFile = filePath;
            this.modal.enableUSBSelectButton(true);
        } else {
            this.state.selectedFile = null;
            this.modal.enableUSBSelectButton(false);
        }
    }

    handleRowDoubleClick(row) {
        const fileType = row.dataset.type;
        const filePath = row.dataset.path;
        if (fileType === 'folder') {
            const deviceName = filePath.match(/usb_disk\/([^\/]+)/)[1];
            const tree = this.state.allDevices[deviceName];
            const node = this.findNodeByPath(tree, filePath);
            if (node) {
                this.renderFilesForDirectory(node);
                this.updateFolderTreeSelection(filePath);
            }
        } else {
            this.state.selectedFile = filePath;
            const modalSelectBtn = document.getElementById('modal-select-btn');
            if (modalSelectBtn) modalSelectBtn.click();
        }
    }

    updateFolderTreeSelection(path) {
        document.querySelectorAll('.tree-item').forEach(item => {
            if (item.dataset.path === path) {
                item.classList.add('selected');
            } else {
                item.classList.remove('selected');
            }
        });
    }

    resetUSBRecoveryButtons() {
        const elements = {
            usbBootImageBtn: document.getElementById('usb-boot-image-btn'),
            usbBootImageInfo: document.getElementById('usb-boot-image-info'),
            usbBootImageUploadBtn: document.getElementById('usb-boot-image-upload-btn'),
            usbWicImageBtn: document.getElementById('usb-wic-image-btn'),
            usbWicImageInfo: document.getElementById('usb-wic-image-info'),
            usbWicImageUploadBtn: document.getElementById('usb-wic-image-upload-btn'),
            usbBmapBtn: document.getElementById('usb-bmap-file-btn'),
            usbBmapInfo: document.getElementById('usb-bmap-file-info'),
            usbBmapNote: document.getElementById('usb-bmap-note')
        };

        elements.usbBootImageBtn?.classList.remove('active');
        elements.usbWicImageBtn?.classList.remove('active');
        if (elements.usbBootImageInfo) elements.usbBootImageInfo.innerHTML = '';
        if (elements.usbWicImageInfo) elements.usbWicImageInfo.innerHTML = '';
        elements.usbBootImageUploadBtn?.classList.add('hidden');
        elements.usbWicImageUploadBtn?.classList.add('hidden');
        elements.usbBmapBtn?.classList.add('hidden', 'file-selected');
        elements.usbBmapBtn?.classList.remove('file-selected');
        if (elements.usbBmapInfo) elements.usbBmapInfo.innerHTML = '';
        if (elements.usbBmapNote) elements.usbBmapNote.innerHTML = '';
        this.state.selectedFile = null;
        this.state.selectedBmapFile = null;
        this.state.savedWicFile = null;
        // Hide USB device selector
        if (window.app) {
            window.app.hideDeviceSelector('usb');
        }
    }
}

class UploadManager {
    constructor(progressBarManager, modalManager, systemInfoManager, app = null) {
        this.progressBar = progressBarManager;
        this.modal = modalManager;
        this.systemInfo = systemInfoManager;
        this.app = app;
        this.progressRegex = /FLASH_PROGRESS=(\d+)/g;
        this.responsePatterns = {
            status: /FLASH_STATUS=(\w+)/,
            reason: /FLASH_REASON=([^\n]+)/,
            version: /FLASH_VERSION=([^\n]+)/,
            buildDate: /FLASH_BUILD_DATE=([^\n]+)/,
            logFile: /FLASH_LOG=([^\n]+)/
        };
    }

    uploadImage(config) {
        const { file, type, bmapFile, btn, input, targetDevice } = config;

        const isUSB = typeof file === 'string';
        const isWic = type === 'wic';
        const scriptUrl = `cgi-bin/upload_${type === 'boot' ? 'bootbin' : 'wicimage'}.sh`;
        const validate = type === 'boot';
        const fileName = isUSB ? file.split('/').pop() : file.name;
        const prefix = `${isUSB ? 'usb-' : ''}${type}`;
        const getElement = (suffix) => document.getElementById(`${prefix}${suffix}`);
        const infoElement = getElement('-image-info');
        const uploadBtn = getElement('-image-upload-btn');

        this.progressBar.show(prefix);
        if (uploadBtn) {
            uploadBtn.disabled = true;
            uploadBtn.textContent = 'Uploading...';
        }

        const updateProgress = (percent) => this.progressBar.update(prefix, percent);

        const resetUpload = (fileHandler) => {
            this.progressBar.reset(prefix);
            if (uploadBtn) {
                uploadBtn.disabled = false;
                uploadBtn.textContent = 'Upload';
            }
            if (isUSB) {
                if (infoElement) infoElement.innerHTML = '';
                uploadBtn?.classList.add('hidden');
                if (isWic) this.app?.hideDeviceSelector('usb');
            } else {
                fileHandler.clearFileSelection(input, infoElement, btn, uploadBtn);
                if (isWic) {
                    fileHandler.clearBmapSelection();
                    this.app?.hideDeviceSelector('ethernet');
                }
            }
        };

        const sendFileToServer = (fileData, filename, fileType, device = null) =>
            new Promise((resolve, reject) => {
                const uploadXhr = new XMLHttpRequest();
                uploadXhr.open('POST', scriptUrl, true);
                uploadXhr.setRequestHeader('X-Upload-Type', fileType);
                uploadXhr.setRequestHeader('X-Filename', filename);
                uploadXhr.setRequestHeader('Content-Type', isUSB ? 'text/plain' : 'application/octet-stream');
                if (device) {
                    uploadXhr.setRequestHeader('X-Target-Device', device);
                }
                uploadXhr.onload = () => {
                    console.log('Upload Status Code:', uploadXhr.status);
                    // Check for HTTP 0 (Payload Too Large) for Ethernet uploads
                    if (!isUSB && uploadXhr.status === 0) {
                        reject(new Error('FILE_TOO_LARGE'));
                    } else if (uploadXhr.status >= 400) {
                        // Any other HTTP error
                        reject(new Error(`HTTP ${uploadXhr.status}: Upload failed`));
                    } else if (uploadXhr.status >= 200 && uploadXhr.status < 300) {
                        // Success status codes (200-299)
                        resolve(uploadXhr);
                    } else {
                        // Unexpected status code
                        reject(new Error(`Unexpected status: ${uploadXhr.status}`));
                    }
                };
                uploadXhr.onerror = () => {
                    console.log('Upload Error - Status Code:', uploadXhr.status || 0);
                    // Check if this is likely a file size issue (status 0 for Ethernet uploads)
                    if (!isUSB && (uploadXhr.status === 0 || !uploadXhr.status)) {
                        reject(new Error('FILE_TOO_LARGE'));
                    } else {
                        reject(new Error('File upload failed'));
                    }
                };
                uploadXhr.send(fileData);
            });

        const uploadedFiles = { main: '', bmap: '' };
        const uploadPromise = (async () => {
            if (isUSB) {
                // For USB, just send the file paths - progress comes entirely from server
                const uploadType = isWic ? 'usb-paths' : 'usb-path';
                const paths = (isWic && bmapFile) ? `${file}\n${bmapFile}` : file;
                await sendFileToServer(paths, '', uploadType, targetDevice);
                return;
            }
            // For Ethernet, upload the actual files
            uploadedFiles.main = file.name;
            await sendFileToServer(file, file.name, 'main', targetDevice);
            if (bmapFile) {
                uploadedFiles.bmap = bmapFile.name;
                await sendFileToServer(bmapFile, bmapFile.name, 'bmap', targetDevice);
            }
        })();

        uploadPromise.then(() => {
            const xhr = new XMLHttpRequest();
            let lastResponseLength = 0;

            xhr.upload.addEventListener('progress', (e) => {
                // Only show file upload progress for Ethernet (USB has no file to upload)
                if (!isUSB && e.lengthComputable) {
                    const uploadPercent = Math.round((e.loaded / e.total) * 60);
                    updateProgress(uploadPercent);
                }
            });

            xhr.addEventListener('readystatechange', () => {
                if (xhr.readyState >= 3) {
                    const newData = xhr.responseText.substring(lastResponseLength);
                    lastResponseLength = xhr.responseText.length;

                    this.progressRegex.lastIndex = 0;
                    for (const match of newData.matchAll(this.progressRegex)) {
                        const progress = parseInt(match[1], 10);
                        // For Ethernet: show server progress 60-100% (0-60% was upload)
                        // For USB: show all server progress 0-100% (no file upload phase)
                        const minProgress = isUSB ? 0 : 60;
                        if (progress >= minProgress && progress <= 100) {
                            updateProgress(progress);
                        }
                    }
                }
            });

            const parseResponse = (data) => {
                return {
                    status: data.match(this.responsePatterns.status)?.[1] || 'UNKNOWN',
                    reason: data.match(this.responsePatterns.reason)?.[1] || 'Unknown response',
                    version: data.match(this.responsePatterns.version)?.[1],
                    buildDate: data.match(this.responsePatterns.buildDate)?.[1],
                    logFile: data.match(this.responsePatterns.logFile)?.[1]
                };
            };

            xhr.addEventListener('load', () => {
                if (xhr.status === 200) {
                    const { status, reason, version, buildDate, logFile } = parseResponse(xhr.responseText);

                    if (status === 'SUCCESS') {
                        const details = {
                            'File': fileName,
                            'Status': reason,
                            ...(version && { 'Version': version }),
                            ...(buildDate && { 'Build Date': buildDate }),
                            ...(logFile && { 'Log File': logFile })
                        };

                        if (validate) {
                            this.progressBar.setMessage(prefix, 'Verifying CRC32...');

                            this.systemInfo.fetchJSON('cgi-bin/validate_crc32.sh', 'CRC32 validation')
                                .then((validationData) => {
                                    if (validationData) {
                                        this.systemInfo.fetchBootStatus();
                                        this.modal.showModal('Upload Successful', details, true, isUSB, (resetUSB) => {
                                            if (resetUSB && config.onReset) config.onReset();
                                        });
                                        resetUpload(config.fileHandler);
                                    } else {
                                        this.modal.showModal('Validation Failed', {
                                            'Status': 'Upload completed but CRC32 validation failed',
                                            'Action': 'Please try uploading again'
                                        }, false, isUSB);
                                        if (uploadBtn) {
                                            uploadBtn.disabled = false;
                                            uploadBtn.textContent = 'Upload';
                                        }
                                        this.progressBar.reset(prefix);
                                    }
                                });
                        } else {
                            this.modal.showModal('Upload Successful', details, true, isUSB, (resetUSB) => {
                                if (resetUSB && config.onReset) config.onReset();
                            });
                            resetUpload(config.fileHandler);
                        }
                    } else {
                        this.handleFailure('Upload Failed', {
                            'Status': status,
                            'Reason': reason
                        }, isUSB, config);
                    }
                } else {
                    this.handleFailure('Upload Failed', {
                        'Error': `HTTP error ${xhr.status}`,
                        'Details': 'Server returned an error response'
                    }, isUSB, config);
                }
            });

            xhr.addEventListener('error', () => {
                console.error('Upload error');
                this.handleFailure('Upload Failed', {
                    'Error': 'Network error',
                    'Details': 'Unable to connect to server'
                }, isUSB, config);
            });

            xhr.addEventListener('abort', () => {
                this.handleFailure('Upload Cancelled', {
                    'Status': 'Upload was cancelled by user'
                }, isUSB, config);
            });

            xhr.open('POST', scriptUrl, true);
            xhr.setRequestHeader('X-Upload-Type', 'flash');
            xhr.setRequestHeader('Content-Type', 'text/plain');
            if (!isUSB) {
                const headerName = isWic ? 'X-Main-Filename' : 'X-Boot-Filename';
                xhr.setRequestHeader(headerName, uploadedFiles.main);
                if (isWic && uploadedFiles.bmap) {
                    xhr.setRequestHeader('X-Bmap-Filename', uploadedFiles.bmap);
                }
            }
            // Send target device for all WIC uploads (both USB and Ethernet)
            if (isWic && config.targetDevice) {
                xhr.setRequestHeader('X-Target-Device', config.targetDevice);
            }
            xhr.send('FLASH');
        }).catch(error => {
            console.error('File upload error:', error);

            // Enhanced error handling for Ethernet uploads
            if (!isUSB) {
                if (error.message === 'FILE_TOO_LARGE') {
                    this.handleFailure('File Too Large', {
                        'Error': 'File exceeds maximum upload size',
                        'Details': 'The server rejected the file (HTTP 0). Please use a smaller file.',
                        'Suggestion': 'Maximum file size may be limited by server configuration'
                    }, isUSB, config);
                    return;
                }
                // Check for quota errors
                if (error.message && (
                    error.message.includes('quota') ||
                    error.message.includes('storage') ||
                    error.message.includes('disk') ||
                    error.message.includes('space')
                )) {
                    this.handleFailure('Storage Error', {
                        'Error': 'Insufficient storage space',
                        'Details': error.message,
                        'Suggestion': 'Free up space on the target device and try again'
                    }, isUSB, config);
                    return;
                }
            }

            // Default error handling
            this.handleFailure('Upload Failed', {
                'Error': 'File upload failed',
                'Details': error.message
            }, isUSB, config);
        });
    }

    handleFailure(title, details, isUSB, config) {
        this.modal.showModal(title, details, false, isUSB, (resetUSB) => {
            if (resetUSB) config.onReset?.();
        });
        if (!config.fileHandler) return;
        const prefix = `${isUSB ? 'usb-' : ''}${config.type}`;
        this.progressBar.reset(prefix);
        const uploadBtn = document.getElementById(`${prefix}-image-upload-btn`);
        if (uploadBtn) {
            uploadBtn.disabled = false;
            uploadBtn.textContent = 'Upload';
        }
        if (config.type === 'wic') {
            this.app?.hideDeviceSelector(isUSB ? 'usb' : 'ethernet');
        }
    }
}

class ImageRecoveryApp {
    constructor() {
        this.dom = new DOMManager();
        this.progressBar = new ProgressBarManager(this.dom);
        this.modal = new ModalManager(this.dom);
        this.systemInfo = new SystemInfoManager(this.dom);
        this.storageDevice = new StorageDeviceManager();
        this.fileHandler = new FileHandlerManager(this.progressBar);
        this.usbRecovery = new USBRecoveryManager(this.modal, this.fileHandler);
        this.uploadManager = new UploadManager(this.progressBar, this.modal, this.systemInfo, this);
    }

    init() {
        this.systemInfo.initialize();
        this.initializeButtons();
        this.initializeNavigation();
        this.initializeDeviceSelection();
    }

    initializeButtons() {
        const buttons = document.querySelectorAll('.action-btn');
        buttons.forEach(btn => {
            btn.addEventListener('click', () => {
                buttons.forEach(b => b.classList.remove('active'));
                btn.classList.add('active');
                this.handleActionButton(btn.textContent);
                this.resetAllRecoveryButtons();
            });
        });
    }

    handleActionButton(action) {
        document.querySelectorAll('.content-section').forEach(section => section.classList.add('hidden'));
        const contentId = CONTENT_MAP[action];
        if (contentId) document.getElementById(contentId)?.classList.remove('hidden');
    }

    resetAllRecoveryButtons() {
        // Batch all DOM queries
        const elements = {
            bootImageBtn: document.getElementById('boot-image-btn'),
            bootImageInput: document.getElementById('boot-image-input'),
            bootImageInfo: document.getElementById('boot-image-info'),
            bootImageUploadBtn: document.getElementById('boot-image-upload-btn'),
            wicImageBtn: document.getElementById('wic-image-btn'),
            wicImageInput: document.getElementById('wic-image-input'),
            wicImageInfo: document.getElementById('wic-image-info'),
            wicImageUploadBtn: document.getElementById('wic-image-upload-btn')
        };

        this.fileHandler.clearFileSelection(elements.bootImageInput, elements.bootImageInfo,
            elements.bootImageBtn, elements.bootImageUploadBtn);
        this.fileHandler.clearFileSelection(elements.wicImageInput, elements.wicImageInfo,
            elements.wicImageBtn, elements.wicImageUploadBtn);
        this.fileHandler.clearBmapSelection();
        // Reset progress bars in batch
        ['boot', 'wic', 'usb-boot', 'usb-wic'].forEach(type => this.progressBar.reset(type));
        this.hideDeviceSelector('ethernet');
        this.usbRecovery.resetUSBRecoveryButtons();
        this.hideDeviceSelector('usb');
    }

    initializeNavigation() {
        const getElement = id => document.getElementById(id);
        const bootImageBtn = getElement('boot-image-btn');
        const bootImageInput = getElement('boot-image-input');
        const bootImageInfo = getElement('boot-image-info');
        const bootImageUploadBtn = getElement('boot-image-upload-btn');
        const wicImageBtn = getElement('wic-image-btn');
        const wicImageInput = getElement('wic-image-input');
        const wicImageInfo = getElement('wic-image-info');
        const wicImageUploadBtn = getElement('wic-image-upload-btn');

        const ethBtns = [bootImageBtn, wicImageBtn].filter(btn => btn);

        this.setupFileRecoveryButton({
            btn: bootImageBtn,
            input: bootImageInput,
            info: bootImageInfo,
            uploadBtn: bootImageUploadBtn,
            otherInput: wicImageInput,
            otherInfo: wicImageInfo,
            otherBtn: wicImageBtn,
            otherUploadBtn: wicImageUploadBtn,
            buttons: ethBtns,
            uploadFn: (file, btn, input) => this.uploadBootImage(file, btn, input),
            showBmap: false
        });

        this.setupFileRecoveryButton({
            btn: wicImageBtn,
            input: wicImageInput,
            info: wicImageInfo,
            uploadBtn: wicImageUploadBtn,
            otherInput: bootImageInput,
            otherInfo: bootImageInfo,
            otherBtn: bootImageBtn,
            otherUploadBtn: bootImageUploadBtn,
            buttons: ethBtns,
            uploadFn: (file, btn, input) => this.uploadWicImage(file, btn, input),
            showBmap: true
        });

        const bmapFileBtn = getElement('bmap-file-btn');
        const bmapFileInput = getElement('bmap-file-input');
        const bmapFileInfo = getElement('bmap-file-info');
        if (bmapFileBtn && bmapFileInput && bmapFileInfo) {
            bmapFileBtn.addEventListener('click', () => bmapFileInput.click());
            bmapFileInput.addEventListener('change', (e) => {
                const bmapFile = e.target.files[0];
                if (bmapFile) {
                    this.fileHandler.displayFileInfo(bmapFile, bmapFileInfo);
                    bmapFileBtn.classList.add('file-selected');
                }
            });
        }

        const usbBootImageBtn = getElement('usb-boot-image-btn');
        const usbWicImageBtn = getElement('usb-wic-image-btn');
        const usbBmapFileBtn = getElement('usb-bmap-file-btn');
        const usbBtns = [usbBootImageBtn, usbWicImageBtn].filter(btn => btn);

        usbBootImageBtn?.addEventListener('click', () => {
            this.fileHandler.toggleActiveButton(usbBtns, usbBootImageBtn);
            this.hideDeviceSelector('usb');
            this.usbRecovery.openFilePicker('boot');
        });

        usbWicImageBtn?.addEventListener('click', () => {
            this.fileHandler.toggleActiveButton(usbBtns, usbWicImageBtn);
            this.usbRecovery.openFilePicker('wic');
        });

        usbBmapFileBtn?.addEventListener('click', () => {
            this.usbRecovery.openFilePicker('bmap');
        });

        getElement('usb-boot-image-upload-btn')?.addEventListener('click', () => this.uploadUSBBootImage());
        getElement('usb-wic-image-upload-btn')?.addEventListener('click', () => this.uploadUSBWicImage());
    }

    initializeDeviceSelection() {
        this.setupDeviceSelector('ethernet', 'wic-storage-device', 'refresh-wic-devices');
        this.setupDeviceSelector('usb', 'usb-wic-storage-device', 'refresh-usb-wic-devices');
    }

    setupDeviceSelector(type, selectId, refreshBtnId) {
        const deviceSelect = document.getElementById(selectId);
        const refreshBtn = document.getElementById(refreshBtnId);
        if (deviceSelect) {
            deviceSelect.addEventListener('change', (e) => {
                this.storageDevice.setSelectedDevice(type, e.target.value);
                // Update upload button visibility when device selection changes
                this.updateWicUploadButtonVisibility(type);
            });
        }
        if (refreshBtn) {
            refreshBtn.addEventListener('click', async () => {
                await this.storageDevice.refreshDeviceList(type);
                // Update upload button visibility after refresh
                this.updateWicUploadButtonVisibility(type);
            });
        }
    }

    updateWicUploadButtonVisibility(type) {
        const uploadBtnId = type === 'usb' ? 'usb-wic-image-upload-btn' : 'wic-image-upload-btn';
        const uploadBtn = document.getElementById(uploadBtnId);
        const deviceSelected = this.storageDevice.getSelectedDevice(type);
        if (uploadBtn) {
            // Check if a file is selected and a device is selected
            const fileSelected = type === 'usb'
                ? this.usbRecovery.state.selectedFile
                : document.getElementById('wic-image-input')?.files[0];
            if (fileSelected && deviceSelected) {
                uploadBtn.classList.remove('hidden');
            } else if (fileSelected && !deviceSelected) {
                uploadBtn.classList.add('hidden');
            }
        }
    }

    getDeviceSelector(type) {
        const selectorId = type === 'usb' ? 'usb-wic-device-selection' : 'wic-device-selection';
        return document.getElementById(selectorId);
    }

    async showDeviceSelector(type) {
        const selector = this.getDeviceSelector(type);
        if (selector) {
            selector.classList.remove('hidden');
            await this.storageDevice.refreshDeviceList(type);
            // Update upload button visibility after showing device selector
            this.updateWicUploadButtonVisibility(type);
        }
    }

    hideDeviceSelector(type) {
        const selector = this.getDeviceSelector(type);
        if (selector) {
            selector.classList.add('hidden');
            this.storageDevice.setSelectedDevice(type, null);
        }
    }

    setupFileRecoveryButton(config) {
        const { btn, input, info, uploadBtn, otherInput, otherInfo, otherBtn, otherUploadBtn, buttons, uploadFn, showBmap } = config;

        if (!btn || !input || !info || !uploadBtn) return;

        btn.addEventListener('click', () => {
            if (otherInput && otherInfo && otherBtn && otherUploadBtn) {
                this.fileHandler.clearFileSelection(otherInput, otherInfo, otherBtn, otherUploadBtn);
            }
            if (!showBmap) {
                this.fileHandler.clearBmapSelection();
                // Hide device selector when switching to boot image
                this.hideDeviceSelector('ethernet');
            }
            this.fileHandler.toggleActiveButton(buttons, btn);
            input.click();
        });

        input.addEventListener('change', (e) => {
            this.fileHandler.handleFileSelection(e.target.files[0], input, info, btn, uploadBtn, this.modal, showBmap, 'ethernet');
            if (showBmap && e.target.files[0]) {
                const bmapFileContainer = document.getElementById('bmap-file-container');
                const bmapNote = document.getElementById('bmap-note');
                bmapFileContainer?.classList.remove('hidden');
                if (bmapNote) {
                    bmapNote.innerHTML = 'Note: Optionally upload the .bmap file with matching name for faster flashing';
                }
                // Show device selector for WIC images
                this.showDeviceSelector('ethernet');
            } else if (!showBmap) {
                // Hide device selector for non-WIC images
                this.hideDeviceSelector('ethernet');
            }
        });

        uploadBtn.addEventListener('click', () => {
            const file = input.files[0];
            if (file) uploadFn(file, btn, input);
        });
    }

    uploadBootImage(file, btn, input) {
        this.uploadManager.uploadImage({file, type: 'boot', bmapFile: null,
            btn, input, fileHandler: this.fileHandler, targetDevice: null});
    }

    uploadWicImage(file, btn, input) {
        const bmapFileInput = document.getElementById('bmap-file-input');
        const bmapFile = bmapFileInput?.files[0];
        const targetDevice = this.storageDevice.getSelectedDevice('ethernet');
        this.uploadManager.uploadImage({file, type: 'wic', bmapFile, btn,
            input, fileHandler: this.fileHandler, targetDevice});
    }

    uploadUSBBootImage() {
        this.uploadManager.uploadImage({
            file: this.usbRecovery.state.selectedFile, type: 'boot', bmapFile: null, btn: null,
            input: null, onReset: () => this.usbRecovery.resetUSBRecoveryButtons(), targetDevice: null});
    }

    uploadUSBWicImage() {
        const bmapFile = this.usbRecovery.state.selectedBmapFile;
        const targetDevice = this.storageDevice.getSelectedDevice('usb');
        this.uploadManager.uploadImage({
            file: this.usbRecovery.state.selectedFile, type: 'wic', bmapFile, btn: null,
            input: null, onReset: () => this.usbRecovery.resetUSBRecoveryButtons(), targetDevice});
    }
}

document.addEventListener('DOMContentLoaded', () => {
    const app = new ImageRecoveryApp();
    window.app = app;
    app.init();
});
