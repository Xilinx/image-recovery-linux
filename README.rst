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
   │   └── index.js        # Application logic
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

Uninstallation
==============

To remove the application, run:

.. code-block:: bash

   make clean DESTDIR=/path/to/destination

.. warning::
   This will remove all installed files from the system.
