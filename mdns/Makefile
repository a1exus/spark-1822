.DEFAULT_GOAL := help
SHELL := /usr/bin/env bash
.SHELLFLAGS := -e -o pipefail -c

BIN  := /usr/local/bin/sparky-mdns-alias
UNIT := /etc/systemd/system/sparky-mdns-alias@.service

.PHONY: help install uninstall list

help:  ## Show this help.
	@awk 'BEGIN{FS=":.*##"} /^[a-zA-Z_-]+:.*##/{printf "  \033[36m%-12s\033[0m %s\n",$$1,$$2}' $(MAKEFILE_LIST)
	@echo
	@echo "Manage individual aliases:"
	@echo "  sudo systemctl enable  --now 'sparky-mdns-alias@<name>.<host>.local'"
	@echo "  sudo systemctl disable --now 'sparky-mdns-alias@<name>.<host>.local'"

install:  ## Install the script + systemd template unit (idempotent).
	sudo install -m 755 sparky-mdns-alias          $(BIN)
	sudo install -m 644 sparky-mdns-alias@.service $(UNIT)
	sudo systemctl daemon-reload
	@echo "installed. enable an alias with: sudo systemctl enable --now 'sparky-mdns-alias@<alias>'"

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
