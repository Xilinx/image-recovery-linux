.. Copyright (c) 2025 - 2026 Advanced Micro Devices, Inc. All Rights Reserved.
.. SPDX-License-Identifier: MIT

.. _readme:

======================================================
AMD System Boot Image Recovery Tool (SBIRT)
======================================================

.. meta::
   :description: Linux-based web application for recovering and updating boot images on AMD embedded systems
   :keywords: AMD, boot recovery, image recovery, embedded systems, Linux

A Linux-based web application for recovering and updating boot images on AMD embedded systems.

.. contents:: Table of Contents
   :depth: 2
   :local:
   :backlinks: top

Overview
========

The AMD System Boot Image Recovery Tool (SBIRT) provides an intuitive web interface for managing
system firmware and image recovery through either Ethernet or USB connections. It supports both
Boot.bin A/B images and WIC (Wic Image Creator) images for eMMC/SD card recovery.

Features
========

The tool provides the following key features:

* **System Information Display**: View board details, boot status, and carrier card information
* **Ethernet Recovery**: Upload boot images and WIC images directly via network
* **USB Recovery**: Select and apply images from connected USB drives
* **Progress Tracking**: Real-time upload progress monitoring
* **BMAP Support**: Optimized flashing with block map files for WIC images
* **Dual Boot Bank**: Support for A/B boot partition management

Requirements
============

The following components are required to run SBIRT:

* Linux-based embedded system with web server (lighttpd/apache)
* CGI support enabled
* Modern web browser with JavaScript enabled
* Network connectivity (for Ethernet recovery)
* USB support (for USB recovery)

Installation
============

To install the application, run:

.. code-block:: bash

   make install DESTDIR=/path/to/destination

.. note::
   The default installation directory is ``/var/imgrcry_web``.

File Structure
==============

The project structure is organized as follows:

.. code-block:: text

   imgrcry/
   ├── index.html          # Main application page
   ├── help.html           # Help documentation
   ├── css/
   │   └── index.css       # Stylesheet
   ├── js/
   │   ├── index.js        # Application logic
   │   └── ufs_config.js   # UFS configuration constants
   ├── cgi-bin/            # CGI scripts for backend operations
   ├── image/              # Images and icons
   └── Makefile            # Installation script

Usage
=====

Getting Started
---------------

Follow these steps to use the recovery tool:

#. Access the web interface through your browser
#. View system information on the main page
#. Choose recovery method (Ethernet or USB)
#. Select the appropriate image file
#. Monitor the upload/recovery progress
#. Wait for confirmation before rebooting

.. tip::
   For detailed usage instructions, refer to the Help section in the application.

UFS Configuration
-----------------

In the GUI, selecting **Query Device** triggers backend script ``cgi-bin/ufs_configure.sh``
to read the current descriptor from the selected UFS device.

For manual CLI usage, run the following command to query the device and dump the current UFS
configuration descriptor to a binary file named ``ufsconfig`` (the descriptor is also printed on terminal):

.. code-block:: bash

      ufs-utils desc -t 1 -D ufsconfig -p /dev/bsg/ufs-bsg0

Logical Unit Configuration
~~~~~~~~~~~~~~~~~~~~~~~~~~

The table below summarizes the logical unit setup from the current descriptor values:

.. list-table::
      :header-rows: 1

      * - Logical Unit
         - LU Enable
         - Size
         - Memory Type
         - Boot LUN
         - Write Protect
         - Alloc Units (dNumAllocUnits)
      * - LU0
         - Yes
         - 20 GB
         - Normal (0x0)
         - Boot A (0x1)
         - None (0x0)
         - 0x1400
      * - LU1
         - Yes
         - 2-4 GB
         - Normal (0x0)
         - Boot B (0x0)
         - None (0x0)
         - 0x0100

.. note::
      After updating/writing UFS logical unit configuration, reboot Linux so the newly
      configured logical units/partitions are detected.

Uninstallation
==============

To remove the application, run:

.. code-block:: bash

   make clean DESTDIR=/path/to/destination

.. warning::
   This will remove all installed files from the system.
