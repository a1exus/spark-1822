.DEFAULT_GOAL := help
SHELL := /usr/bin/env bash
.SHELLFLAGS := -e -o pipefail -c
.SUFFIXES:
.DELETE_ON_ERROR:

.PHONY: help ca-cert

help:  ## Show this help.
	@awk 'BEGIN{FS=":.*##"} /^[a-zA-Z_-]+:.*##/{printf "  \033[36m%-10s\033[0m %s\n",$$1,$$2}' $(MAKEFILE_LIST)

ca-cert:  ## Extract Caddy's internal root CA to ./caddy-root.crt.
	docker exec caddy cat /data/caddy/pki/authorities/local/root.crt > caddy-root.crt
	@echo "wrote $$(pwd)/caddy-root.crt — see README for per-OS install steps"
