.DEFAULT_GOAL := help
SHELL := /usr/bin/env bash
.SHELLFLAGS := -e -o pipefail -c
.SUFFIXES:
.DELETE_ON_ERROR:

ENV ?=
ENV := $(strip $(ENV))
SERVICE := vllm
COMPOSE := docker compose -f docker-compose.yml
HF_CACHE ?= /opt/hf/.cache/huggingface

.PHONY: help list up hf-cache hf-sync

help:  ## Show this help.
	@awk 'BEGIN{FS=":.*##"} /^[a-zA-Z_-]+:.*##/{printf "  \033[36m%-12s\033[0m %s\n",$$1,$$2}' $(MAKEFILE_LIST)
	@echo
	@echo "Usage:"
	@echo "  make list                       — show available env variants"
	@echo "  make up ENV=<name>              — start $(SERVICE) with that env"
	@echo
	@echo "HF-cache maintenance:"
	@echo "  make hf-cache                   — list HF repos already downloaded in $(HF_CACHE)"
	@echo "  make hf-sync                    — reconcile envs against the cache (create / restore / orphan to .bak)"
	@echo
	@echo "For management, invoke docker compose directly. The compose file"
	@echo "uses required vars (e.g. \$${VLLM_TAG:?...}), so pass --env-file:"
	@echo "  docker compose --env-file envs/<name>.env logs -f $(SERVICE)"
	@echo "  docker compose --env-file envs/<name>.env ps"
	@echo "  docker compose --env-file envs/<name>.env down"
	@echo
	@echo "Or use plain docker against the container name (no env needed):"
	@echo "  docker logs -f $(SERVICE)"
	@echo "  docker stop $(SERVICE)"

list:  ## List available env variants under envs/.
	@ls envs/*.env 2>/dev/null | sed 's|envs/||; s|\.env$$||' | sort

up:  ## Start with the given variant. No .env is written. Usage: make up ENV=<name>
	@if [[ -z "$(ENV)" ]]; then \
	    echo "usage: make up ENV=<name>" >&2; \
	    echo "available:" >&2; $(MAKE) -s list | sed 's/^/  /' >&2; \
	    exit 64; \
	fi
	@if [[ ! -f "envs/$(ENV).env" ]]; then \
	    echo "variant not found: envs/$(ENV).env" >&2; \
	    echo "available:" >&2; $(MAKE) -s list | sed 's/^/  /' >&2; \
	    exit 1; \
	fi
	$(COMPOSE) --env-file "envs/$(ENV).env" up -d

hf-cache:  ## List HF repos already downloaded in this host's HF cache.
	@ls -d $(HF_CACHE)/hub/models--* 2>/dev/null \
	    | sed 's|.*/models--||; s|--|/|' | sort

hf-sync:  ## Reconcile envs against the HF cache: create new, restore from .bak, orphan to .bak.
	@cached=$$(ls -d $(HF_CACHE)/hub/models--* 2>/dev/null | sed 's|.*/models--||; s|--|/|'); \
	if [[ -z "$$cached" ]]; then echo "no models in $(HF_CACHE)/hub/"; exit 0; fi; \
	cd envs; \
	created=0; restored=0; orphaned=0; \
	while read -r repo; do \
	    [[ -z "$$repo" ]] && continue; \
	    short=$$(echo "$$repo" | cut -d/ -f2 | tr 'A-Z' 'a-z'); \
	    file="$$short.env"; \
	    if grep -lE "^VLLM_MODEL=$$repo[[:space:]]*\$$" *.env 2>/dev/null | head -1 >/dev/null; then \
	        :; \
	    elif [[ -f "$$file.bak" ]] && grep -qE "^VLLM_MODEL=$$repo[[:space:]]*\$$" "$$file.bak"; then \
	        printf '↩ restore %s ← %s.bak\n' "$$file" "$$file"; \
	        mv "$$file.bak" "$$file"; \
	        restored=$$((restored + 1)); \
	    elif [[ -f "$$file" ]]; then \
	        echo "  name clash: $$file already exists but points elsewhere — leave alone, rename manually if needed"; \
	    else \
	        printf '+ create  %s — %s\n' "$$file" "$$repo"; \
	        { \
	            echo "# $$repo · in $(HF_CACHE) on this host."; \
	            echo "# Self-contained — \`make up ENV=$$short\` uses this directly."; \
	            echo ""; \
	            echo "VLLM_TAG=v0.20.2"; \
	            echo "HF_CACHE_HOST=$(HF_CACHE)"; \
	            echo "HF_TOKEN="; \
	            echo ""; \
	            echo "VLLM_MODEL=$$repo"; \
	            echo "VLLM_SERVED_NAME=$$short"; \
	            echo "VLLM_GPU_MEM=0.9"; \
	            echo "VLLM_MAX_LEN=8192"; \
	        } > "$$file"; \
	        created=$$((created + 1)); \
	    fi; \
	done <<<"$$cached"; \
	for f in *.env; do \
	    [[ -f "$$f" ]] || continue; \
	    repo=$$(grep -E '^VLLM_MODEL=' "$$f" | head -1 | cut -d= -f2-); \
	    [[ -z "$$repo" ]] && continue; \
	    if ! grep -qFx "$$repo" <<<"$$cached"; then \
	        printf '→ orphan  %s → %s.bak\n' "$$f" "$$f"; \
	        mv "$$f" "$$f.bak"; \
	        orphaned=$$((orphaned + 1)); \
	    fi; \
	done; \
	echo "summary — $$created created, $$restored restored, $$orphaned orphaned"
