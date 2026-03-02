# Copyright (c) 2025 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

localstatedir ?= /var
bindir ?= /usr/bin
APPSDIR = apps
IMGRCVRYDIR = $(localstatedir)/imgrcry_web
CGIDIR = $(IMGRCVRYDIR)/cgi-bin

INSTALLFILES := help.html index.html cgi-bin css image js

.PHONY: install clean

install:
	@echo "Installing files..."
	install -d $(DESTDIR)$(IMGRCVRYDIR)
	install -d $(DESTDIR)$(bindir)
	cp -rf $(INSTALLFILES) $(DESTDIR)$(IMGRCVRYDIR)
	sed 's|^CGI_DIR=.*|CGI_DIR="$(CGIDIR)"|' $(APPSDIR)/image-recovery > $(DESTDIR)$(bindir)/image-recovery
	chmod -R 755 $(DESTDIR)$(IMGRCVRYDIR)/cgi-bin
	chmod 755 $(DESTDIR)$(bindir)/image-recovery

clean:
	@echo "Removing installed files..."
	rm -rf $(DESTDIR)$(IMGRCVRYDIR) $(DESTDIR)$(bindir)/image-recovery
