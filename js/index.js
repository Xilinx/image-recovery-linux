var objPage;

function onPageLoad() {
	document.getElementById("upld_prgrs").style.visibility = "hidden";
	document.getElementById("upld_status").style.visibility = "hidden";

	var http = new XMLHttpRequest();
	http.open("GET", "cgi-bin/sysinfo_eeprom.sh", true);
	http.send();

	http.onload = function() {
		objPage = JSON.parse(this.responseText);

		var table = document.getElementById("sysboardtbl");
		table.rows[0].cells[1].innerHTML = objPage.SysBoardInfo.BoardName;
		table.rows[1].cells[1].innerHTML = objPage.SysBoardInfo.RevisionNo;
		table.rows[2].cells[1].innerHTML = objPage.SysBoardInfo.SerialNo;
		table.rows[3].cells[1].innerHTML = objPage.SysBoardInfo.PartNo;
		table.rows[4].cells[1].innerHTML = objPage.SysBoardInfo.UUID;

		table = document.getElementById("cctbl");
		table.rows[0].cells[1].innerHTML = objPage.CcInfo.BoardName;
		table.rows[1].cells[1].innerHTML = objPage.CcInfo.RevisionNo;
		table.rows[2].cells[1].innerHTML = objPage.CcInfo.SerialNo;
		table.rows[3].cells[1].innerHTML = objPage.CcInfo.PartNo;
		table.rows[4].cells[1].innerHTML = objPage.CcInfo.UUID;

		if (objPage.SysBoardInfo.BoardName.startsWith("SMK-")) {
			document.getElementById("recWICLabel_usb").style.display = "none";
			document.getElementById("recWICimg").disabled = true;
			document.getElementById("recWICimg_usb").disabled = true;
			document.getElementById("recWICimg").style.display = "none";
			document.getElementById("recWICimg_usb").style.display = "none";
		}

		updateBootImgStatus(objPage);
	}

	document.getElementById("upld_btn").addEventListener("CrcDone", onCrcComplete);
	document.getElementById("upld_btn").addEventListener("FlashEraseDone", initiateImgUpload);
	document.body.addEventListener('DOMContentLoaded', OpenTab(event, 'System Information'));
}

function onUsbTab() {
	var ele = document.getElementsByName('optradio');
	for (i = 0; i < ele.length; i++) {
		ele[i].checked = false;
		ele[i].value = "";
	}

	document.getElementById("recAimg_usb").checked = false;
	document.getElementById("recWICimg_usb").checked = false;
	document.getElementById("upld_prgrs_usb").style.visibility = "hidden";
	document.getElementById("upld_status_usb").style.visibility = "hidden";
}

function updateBootImgStatus(objBrd) {
	var http = new XMLHttpRequest();
	http.open("GET", "cgi-bin/bootstatus.sh", true);
	http.send();

	http.onload = function() {
		var obj = JSON.parse(this.responseText);
		var SysImgInfoTbl = document.getElementById("sysimginfotbl");

		if (obj.BankAStatus == true)
			SysImgInfoTbl.rows[0].cells[2].innerHTML = "Accepted";
		else
			SysImgInfoTbl.rows[0].cells[2].innerHTML = "Rejected";

		if (obj.BankBStatus == true)
			SysImgInfoTbl.rows[1].cells[1].innerHTML = "Accepted";
		else
			SysImgInfoTbl.rows[1].cells[1].innerHTML = "Rejected";

		if (obj.ActiveBank == "ImageA")
			SysImgInfoTbl.rows[2].cells[1].innerHTML = "Bank A";
		else
			SysImgInfoTbl.rows[2].cells[1].innerHTML = "Bank B";

		if (obj.PrevActiveBank == "ImageA")
			SysImgInfoTbl.rows[3].cells[1].innerHTML = "Bank A";
		else
			SysImgInfoTbl.rows[3].cells[1].innerHTML = "Bank B";

		document.getElementById("recAimg").checked = true;
	}
}

function onUploadStart(evt) {
	alert("Started");
}

function onUploadProgress(evt) {
	var progressBar = document.getElementById("upld_prgrs");

	if (evt.lengthComputable) {
		if (progressBar.value > 0) {
			document.getElementById('upld_status').value = "Uploading . . . . .";
		}
		progressBar.max = evt.total;
		progressBar.value = evt.loaded;

	}
}

function onUploadSuccess(evt) {
	document.getElementById('upld_status').value = "Verifying CRC32 . . . . .";
	initiateCrcValidation();
}

function onUploadFailed(evt) {
	var imgId = null;
	var imgFile = document.getElementById("img_file").files[0];

	if (document.getElementById("recAimg").checked)
		imgId = "FLASH";
	else if (document.getElementById("recWICimg").checked)
		imgId = "WIC"

	document.getElementById('upld_status').value = "Upload Failed . . . . .";
	alert("Failed to update image " + imgId);
	enableAllUsrInputs();
}

function onUploadCanceled(evt) {
	var imgId = null;
	var imgFile = document.getElementById("img_file").files[0];

	if (document.getElementById("recAimg").checked)
		imgId = "FLASH";
	else if (document.getElementById("recWICimg").checked)
		imgId = "WIC"

	document.getElementById('upld_status').value = "Upload Canceled . . . . .";
	alert("Canceled update image " + imgId + " operation");
	enableAllUsrInputs();
}

function disableAllUsrInputs() {
	document.getElementById("brws_btn").disabled = true;
	document.getElementById("upld_btn").disabled = true;
	document.getElementById("recAimg").disabled = true;
	document.getElementById("recAimg_usb").disabled = true;
	document.getElementById("recWICimg").disabled = true;
	document.getElementById("recWICimg_usb").disabled = true;
}

function disableAllUsrInputs_usb() {
	document.getElementById("recAimg_usb").disabled = true;
	document.getElementById("recWICimg_usb").disabled = true;
}

function enableAllUsrInputs() {
	document.getElementById("brws_btn").disabled = false;
	document.getElementById("upld_btn").disabled = false;
	document.getElementById("sbmt_btn").disabled = false;
	document.getElementById("recAimg").disabled = false;
	document.getElementById("recAimg_usb").disabled = false;
	document.getElementById("recWICimg").disabled = false;
	document.getElementById("recWICimg_usb").disabled = false;
}

function enableAllUsrInputs_usb() {
	document.getElementById("recAimg_usb").disabled = false;
	document.getElementById("recWICimg_usb").disabled = false;
}

function initiateImgUpload () {
	var imgId = null;
	var imgFile = document.getElementById("img_file").files[0];

	if (document.getElementById("recAimg").checked)
		imgId = "FLASH";
	else if (document.getElementById("recWICimg").checked)
		imgId = "WIC"

	var url = 'Image_' + imgId;
	var xhr = new XMLHttpRequest();
	var fd = new FormData();
	fd.append(url, imgFile);
	document.getElementById("upld_prgrs").style.visibility = "visible";
	document.getElementById('upld_status').value = "Erasing Flash . . . . .";
	document.getElementById("upld_prgrs").value = 0;
	xhr.upload.addEventListener("progress", onUploadProgress, false);
	xhr.addEventListener("load", onUploadSuccess, false);
	xhr.addEventListener("error", onUploadFailed, false);
	xhr.addEventListener("abort", onUploadCanceled, false);
	xhr.open("POST", "cgi-bin/eth_write.sh", true);
	xhr.send(fd);
}

function onUpload() {
	var imgId = null;
	var imgFile = document.getElementById("img_file").files[0];

	if (document.getElementById("recAimg").checked)
		imgId = "FLASH";
	else if (document.getElementById("recWICimg").checked)
		imgId = "WIC"

	var progressBar = document.getElementById("upld_prgrs");
	progressBar.value = 0;

	var imgFile = document.getElementById("img_file").files[0];
	extension = imgFile.name.split('.').pop() + '';
	if ((imgId == "FLASH") && (extension.toUpperCase() != "BIN")) {
		alert("Invalid file type for image " + imgId + ". File should be of .bin type.");
	}
	else if ((imgId == "WIC") && (extension.toUpperCase() != "WIC") && (extension.toUpperCase() != "XZ") && (extension.toUpperCase() != "BMAP")) {
		alert("Invalid file type for image " + imgId + ". File should be of .wic type.");
	}
	else {
		if (confirm("Are you sure you want to update "+ imgId +" image?")) {
			disableAllUsrInputs();
			document.getElementById("upld_status").style.visibility = "visible";
			document.getElementById('upld_status').value = "Calculating CRC32 . . . . .";
			document.getElementById("upld_prgrs").style.visibility = "visible";
			startCalcCrc32(imgFile);
		}
	}
}

function onBrws() {
	var imgFile = document.getElementById('img_file')
	imgFile.onchange = e => {
		var file = e.target.files[0];
		if (file) {
			document.getElementById("upld_btn").disabled = false;
			document.getElementById("fileName").setAttribute("fd", file);
			document.getElementById("fileName").value = file.name;
			var fileSize = 0;
			if (file.size >= 1073741824)
					fileSize = (Math.round(file.size * 100 / 1073741824) / 100).toString() + ' GB';
			else if (file.size >= 1048576)
					fileSize = (Math.round(file.size * 100 / 1048576) / 100).toString() + ' MB';
			else if (file.size >= 1024)
					fileSize = (Math.round(file.size * 100 / 1024) / 100).toString() + ' Kb';
			else
					fileSize = file.size + 'bytes';

			var divfileSize = document.getElementById('fileSize');
			divfileSize.value = fileSize;
			document.getElementById("upld_prgrs").value = 0;
			document.getElementById("upld_prgrs").style.visibility="hidden";
			document.getElementById("upld_status").style.visibility = "hidden";
		}
	}
	imgFile.click();
}

function onBrws_usb() {
	var xhr = new XMLHttpRequest();
	xhr.open("GET", "cgi-bin/usb_scan.sh", true);
	xhr.send();
	xhr.onload = function() {
		var imgFile = this.responseText;
		file = imgFile.split('\n')

		var table = document.getElementById("usb_files");
		var ele = document.getElementsByName('optradio');
		for (i = 0; i < ele.length; i++) {
			table.rows[i].cells[1].innerHTML = file[i];
			ele[i].value = file[i];
		}
	}
}

function onUpload_usb() {
	var imgId = null;
	var imgFile = null;
	var ele = document.getElementsByName('optradio');

	for (i = 0; i < ele.length; i++) {
		if (ele[i].checked){
			imgFile	= ele[i].value;
			break;
		}
	}

	if (document.getElementById("recAimg_usb").checked)
		imgId = "FLASH";
	else if (document.getElementById("recWICimg_usb").checked)
		imgId = "WIC";
	
	if(imgId == null){
		alert("Please select image to be recovered");
		return;
	}else if(imgFile == null) {
		alert("Please select image file to be updated");
		return;
	}

	var progressBar = document.getElementById("upld_prgrs_usb");
	progressBar.value = 0;
	
	extension = imgFile.split('.').pop() + '';
	if ((imgId == "FLASH") && (extension.toUpperCase() != "BIN")) {
		alert("Invalid file type for image " + imgId + ". File should be of .bin type.");
	}
	else if ((imgId == "WIC") && (extension.toUpperCase() != "WIC") && (extension.toUpperCase() != "XZ") && (extension.toUpperCase() != "BMAP")) {
		alert("Invalid file type for image " + imgId + ". File should be of .wic type.");
	}
	else {
		if (confirm("Are you sure you want to update "+ imgId +" image?")) {
			disableAllUsrInputs_usb();
			document.getElementById("upld_prgrs_usb").style.visibility = "visible";
			initiateImgUpload_usb(imgId, imgFile)
		}
	}
}

function initiateImgUpload_usb(pImgId, pImgFile) {
	var xhr = new XMLHttpRequest();
	var fd = new FormData();

	var url = 'Image_' + pImgId + ":" + pImgFile;
	fd.append(url, null);
	xhr.open("POST", "cgi-bin/usb_write.sh", true);
	xhr.send(fd);
}

function flashEraseStatus(imgId) {
	var xhr = new XMLHttpRequest();
	xhr.open("GET", "cgi-bin/erasestatus.sh", true);
	xhr.send();
	xhr.onload = function() {
		var obj = JSON.parse(this.responseText);
		var progress = parseInt(obj.Progress);
		document.getElementById("upld_prgrs").value = progress;
		if (progress < 100)
			flashEraseStatus();
		else if (progress >= 100) {
			const event = new CustomEvent('FlashEraseDone', { detail: imgId});
			document.getElementById("upld_btn").dispatchEvent(event);
		}
	}
}

function flashErase() {
	var imgId = null;
	var imgFile = document.getElementById("img_file").files[0];

	if (document.getElementById("recAimg").checked)
		imgId = "FLASH";
	else if (document.getElementById("recWICimg").checked)
		imgId = "WIC"

	var xhr = new XMLHttpRequest();
	xhr.open("GET", "flash_erase_img" + imgId, true);
	document.getElementById("upld_prgrs").style.visibility = "visible";
	document.getElementById('upld_status').value = "Erasing Flash . . . . .";
	document.getElementById("upld_prgrs").value = 0;
	document.getElementById("upld_prgrs").max = 100;
	xhr.send();
	xhr.onload = flashEraseStatus(imgId);
}

function onCrcComplete(evt) {
	ImgCrc = parseInt(evt.detail);
	flashErase();
}

function startCalcCrc32(file) {
	var crc = 0xFFFFFFFF;
	var fileSize   = file.size;
	var offset = 0;
	var chunkSize = 64 * 1024;

	function onLoadHandler(evt) {
		if (evt.target.error == null) {
			offset += evt.target.result.byteLength;
			feedData2Crc32Engine(evt.target.result)
		} else {
			alert("ERROR: File read failed during CRC32 calculation");
			return;
		}

		var progressBar = document.getElementById("upld_prgrs");
		if (offset >= fileSize) {
			crc = (crc ^ (-1)) >>> 0;
			progressBar.max = 0;
			const event = new CustomEvent('CrcDone', { detail: crc });
			document.getElementById("upld_btn").dispatchEvent(event);
		}
		else {
			progressBar.max = fileSize;
			progressBar.value = offset;
			readFileChunk(offset, chunkSize, file);
		}
	}

	function readFileChunk (_offset, length, _file) {
		var frd = new FileReader();
		var dataBlob = _file.slice(_offset, length + _offset);
		frd.onload = onLoadHandler;
		frd.readAsArrayBuffer(dataBlob);
	}

	function buildCrc32Table (){
		var n;
		var crcTable = [];

		for(var i = 0; i < 256; i++){
			n = i;
			for(var j = 0; j < 8; j++){
				n = ((n & 1) ? (0xEDB88320 ^ (n >>> 1)) : (n >>> 1));
			}
			crcTable[i] = n;
		}

		return crcTable;
	}

	function feedData2Crc32Engine (data) {
		var buf = new Int8Array(data)
		for (var i = 0; i < data.byteLength; i++ ) {
			crc = (crc >>> 8) ^ crcTable[(crc ^ buf[i]) & 0xFF];
		}
	};

	var crcTable = buildCrc32Table();
	readFileChunk(offset, chunkSize, file);
}

function initiateCrcValidation() {
	var obj = { img_name: document.getElementById("img_file").files[0].name, crc: ImgCrc }
	var http = new XMLHttpRequest();
	http.open("POST", "cgi-bin/validate_crc32.sh", true);
	var params = JSON.stringify(obj);
	http.send(params);

	http.onload = function() {
		var obj = JSON.parse(this.responseText);
		var imgId = null;
		var imgFile = document.getElementById("img_file").files[0];

		if (document.getElementById("recAimg").checked)
			imgId = "FLASH";
		else if (document.getElementById("recWICimg").checked)
			imgId = "WIC"

		split_file_name = imgFile.name.split('.');
		extension = split_file_name.pop() + '';
		ext_imgFile = split_file_name.slice(0, -1).join('.') + ".wic.xz";
		if (extension.toUpperCase() == "BMAP") {
			document.getElementById("img_file").files[0] = ext_imgFile;
			onBrws();
			ext_imgFile.click();
			onUpload();
		}

		if (extension.toUpperCase() != "BMAP") {
			if(obj.Status == "Success") {
				document.getElementById('upld_status').value = "Upload successful . . . . .";
				alert("Successfully updated "+ imgId +" image");
			} else {
				document.getElementById('upld_status').value = "Upload failed . . . . .";
				alert("CRC check failed after downloading image " + imgId);
			}
				updateBootImgStatus(objPage);
				enableAllUsrInputs();
		}
	}
}

function crc32Validate() {
	var http = new XMLHttpRequest();
	http.open("GET", "cgi-bin/crc32.sh", true);
	http.send();

	http.onload = function() {
		var res = this.responseText;
		if (res == 'ok\n') {
			document.getElementById('upld_status').value = "Upload successful . . . . .";
		}
		else {
			document.getElementById('upld_status').value = "Upload failed . . . . .";
		}
		enableAllUsrInputs();
	}
}

function OpenTab(evt, tabName) {
	var i, tabcontent, tablinks;
	tabcontent = document.getElementsByClassName("tabcontent");
	for (i = 0; i < tabcontent.length; i++) {
		tabcontent[i].style.display = "none";
	}

	tablinks = document.getElementsByClassName("tablinks");
	for (i = 0; i < tablinks.length; i++) {
		tablinks[i].className = tablinks[i].className.replace(" active", "");
	}

	if(tabName == "USB Recovery") {
		onUsbTab();
	}

	document.getElementById(tabName).style.display = "block";
	if(evt) evt.currentTarget.className += " active";
	else document.querySelector('button.tablinks').className += " active";
}
