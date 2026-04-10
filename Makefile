# Copyright (c) 2025 - 2026 Advanced Micro Devices, Inc. All Rights Reserved.
# SPDX-License-Identifier: MIT

localstatedir ?= /var
bindir ?= /usr/bin
pythondir ?= /usr/lib/python3/site-packages
BINDIR = bin
WEBDIR = web
IMGRCVRYDIR = $(localstatedir)/imgrcry_web
CGIDIR = $(IMGRCVRYDIR)/cgi-bin

INSTALLFILES := $(WEBDIR)/help.html $(WEBDIR)/index.html $(WEBDIR)/cgi-bin $(WEBDIR)/css $(WEBDIR)/images $(WEBDIR)/js

.PHONY: install clean install-python install-web

install: install-web

install-python:
	@echo "Installing Python utility..."
	@if command -v pip3 >/dev/null 2>&1; then \
		echo "Using pip for installation..."; \
		python3 -m pip install --root=$(DESTDIR) --prefix=/usr .; \
	else \
		echo "Warning: pip not found, falling back to setup.py"; \
		python3 setup.py install --root=$(DESTDIR) --prefix=/usr; \
	fi

install-web:
	@echo "Installing web files..."
	install -d $(DESTDIR)$(IMGRCVRYDIR)
	install -d $(DESTDIR)$(bindir)
	cp -rf $(INSTALLFILES) $(DESTDIR)$(IMGRCVRYDIR)
	# Install CGI-based shell script
	sed 's|^CGI_DIR=.*|CGI_DIR="$(CGIDIR)"|' $(BINDIR)/image-recovery-web > $(DESTDIR)$(bindir)/image-recovery-web
	chmod 755 $(DESTDIR)$(bindir)/image-recovery-web
	chmod -R 755 $(DESTDIR)$(IMGRCVRYDIR)/cgi-bin

clean:
	@echo "Removing installed files..."
	rm -rf $(DESTDIR)$(IMGRCVRYDIR) $(DESTDIR)$(bindir)/image-recovery-web
	rm -rf $(DESTDIR)$(bindir)/image-mgmt
	rm -rf build/ dist/ *.egg-info src/*.egg-info/
