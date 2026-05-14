.DEFAULT_GOAL := help
SHELL := /usr/bin/env bash
.SHELLFLAGS := -e -o pipefail -c

BIN  := /usr/local/bin/sparky-mdns-alias
UNIT := /etc/systemd/system/sparky-mdns-alias@.service

# Default host domain — `<alias>.<HOST>` is the full mDNS name we publish.
# Auto-detected from the host's short hostname; override on the command
# line if you need to publish under a different .local domain (rare).
# Uses `hostname -s` to get the short name (works portably across Linux/
# macOS — plain `hostname` on macOS already includes `.local`).
HOST ?= $(shell hostname -s).local
ALIAS ?=
ALIAS := $(strip $(ALIAS))

# Full systemd instance name for the given ALIAS.
INSTANCE = sparky-mdns-alias@$(ALIAS).$(HOST)

.PHONY: help install uninstall list add remove logs resolve

help:  ## Show this help.
	@awk 'BEGIN{FS=":.*##"} /^[a-zA-Z_-]+:.*##/{printf "  \033[36m%-12s\033[0m %s\n",$$1,$$2}' $(MAKEFILE_LIST)
	@echo
	@echo "Per-alias lifecycle (ALIAS=<name>, defaults to host: $(HOST)):"
	@echo "  make add    ALIAS=foo         — publish 'foo.$(HOST)'"
	@echo "  make remove ALIAS=foo         — stop + disable 'foo.$(HOST)'"
	@echo "  make logs   ALIAS=foo         — journalctl for 'foo.$(HOST)' (Ctrl-C to quit)"
	@echo "  make resolve ALIAS=foo        — avahi-resolve check from this host"
	@echo
	@echo "Inventory:"
	@echo "  make list                     — every currently-active alias"
	@echo
	@echo "Helper lifecycle:"
	@echo "  make install                  — install the script + systemd template unit"
	@echo "  make uninstall                — disable every alias + remove the helper"

install:  ## Install the script + systemd template unit (idempotent).
	sudo install -m 755 sparky-mdns-alias          $(BIN)
	sudo install -m 644 sparky-mdns-alias@.service $(UNIT)
	sudo systemctl daemon-reload
	@echo "installed. add an alias with: make add ALIAS=<name>"

uninstall:  ## Disable every active alias instance, remove the script + unit.
	@for i in $$(systemctl list-units --type=service --all --no-legend 'sparky-mdns-alias@*.service' 2>/dev/null | awk '{print $$1}' | sed 's/^●[[:space:]]*//' | sort -u); do \
	    echo "stopping $$i"; \
	    sudo systemctl disable --now "$$i" >/dev/null 2>&1 || true; \
	done
	sudo rm -f $(UNIT) $(BIN)
	sudo systemctl daemon-reload
	sudo systemctl reset-failed 'sparky-mdns-alias@*' 2>/dev/null || true
	@echo "uninstalled. re-run 'make install' to reinstall."

list:  ## Show every currently-active alias instance.
	@systemctl list-units --type=service --all --no-legend 'sparky-mdns-alias@*.service' | sort -u

add:  ## Publish a new mDNS alias. Usage: make add ALIAS=<name>
	@if [[ -z "$(ALIAS)" ]]; then \
	    echo "usage: make add ALIAS=<name>  (will publish <name>.$(HOST))" >&2; \
	    exit 64; \
	fi
	@if [[ ! -e "$(UNIT)" ]]; then \
	    echo "helper not installed — run 'make install' first" >&2; \
	    exit 1; \
	fi
	sudo systemctl enable --now '$(INSTANCE)'
	@echo "published $(ALIAS).$(HOST) — verify with: make resolve ALIAS=$(ALIAS)"

remove:  ## Stop and disable an mDNS alias. Usage: make remove ALIAS=<name>
	@if [[ -z "$(ALIAS)" ]]; then \
	    echo "usage: make remove ALIAS=<name>" >&2; \
	    exit 64; \
	fi
	sudo systemctl disable --now '$(INSTANCE)'
	sudo systemctl reset-failed '$(INSTANCE)' 2>/dev/null || true
	@echo "removed $(ALIAS).$(HOST)"

logs:  ## Tail journal for a given alias. Usage: make logs ALIAS=<name>
	@if [[ -z "$(ALIAS)" ]]; then \
	    echo "usage: make logs ALIAS=<name>" >&2; \
	    exit 64; \
	fi
	journalctl -u '$(INSTANCE)' -f --no-pager

resolve:  ## Resolve an alias via mDNS from this host. Usage: make resolve ALIAS=<name>
	@if [[ -z "$(ALIAS)" ]]; then \
	    echo "usage: make resolve ALIAS=<name>" >&2; \
	    exit 64; \
	fi
	@if ! command -v avahi-resolve >/dev/null; then \
	    echo "avahi-resolve not found (apt install avahi-utils)" >&2; \
	    exit 1; \
	fi
	avahi-resolve -n '$(ALIAS).$(HOST)'
