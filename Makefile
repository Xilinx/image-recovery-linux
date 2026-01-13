# Copyright (c) 2025 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

localstatedir ?= /var
IMGRCVRYDIR = $(localstatedir)/imgrcry_web

INSTALLFILES := help.html index.html cgi-bin css image js

.PHONY: install clean

install:
	@echo "Installing files..."
	install -d $(DESTDIR)$(IMGRCVRYDIR)
	cp -rf $(INSTALLFILES) $(DESTDIR)$(IMGRCVRYDIR)
	chmod -R 755 $(DESTDIR)$(IMGRCVRYDIR)/cgi-bin

clean:
	@echo "Removing installed files..."
	rm -rf $(DESTDIR)$(IMGRCVRYDIR)
