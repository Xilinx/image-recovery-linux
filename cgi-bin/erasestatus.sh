#!/bin/sh
# Copyright (c) 2025 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

# CGI script to report flash erase progress status
# Returns JSON with progress percentage (0-100)

echo "Content-type: application/json"
echo ""
echo '{ "Progress":100 }'

exit 0