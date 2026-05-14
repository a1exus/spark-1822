.DEFAULT_GOAL := help
SHELL := /usr/bin/env bash
.SHELLFLAGS := -e -o pipefail -c
.SUFFIXES:
.DELETE_ON_ERROR:

ENV ?=
ENV := $(strip $(ENV))
SERVICE := llama-cpp
COMPOSE := docker compose -f docker-compose.yml
HF_CACHE ?= /opt/hf/.cache/huggingface
LLAMACPP_CACHE_VOL ?= llama-cpp-cache
LLAMACPP_TAG_DEFAULT ?= server-cuda

.PHONY: help list up hf-cache hf-sync

help:  ## Show this help.
	@awk 'BEGIN{FS=":.*##"} /^[a-zA-Z_-]+:.*##/{printf "  \033[36m%-12s\033[0m %s\n",$$1,$$2}' $(MAKEFILE_LIST)
	@echo
	@echo "Usage:"
	@echo "  make list                       — show available env variants"
	@echo "  make up ENV=<name>              — start $(SERVICE) with that env"
	@echo
	@echo "GGUF-cache maintenance (llama-cpp-cache vol + HF cache):"
	@echo "  make hf-cache                   — list GGUF files in this host's caches"
	@echo "  make hf-sync                    — reconcile envs against the caches (create / restore / orphan to .bak)"
	@echo
	@echo "For management, raw docker compose works once .env exists"
	@echo "(make up creates it on first run from .env.example):"
	@echo "  docker compose logs -f $(SERVICE)"
	@echo "  docker compose ps"
	@echo "  docker compose down"

list:  ## List available env variants under envs/.
	@ls envs/*.env 2>/dev/null | sed 's|envs/||; s|\.env$$||' | sort

up:  ## Start with the given variant. Usage: make up ENV=<name>
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
	@if [[ ! -f .env ]]; then \
	    echo "→ first-time setup: copying .env.example → .env (placeholder values"; \
	    echo "  so raw \`docker compose ps/logs/down\` work without --env-file)"; \
	    cp .env.example .env; \
	fi
	$(COMPOSE) --env-file "envs/$(ENV).env" up -d

hf-cache:  ## List GGUF files in this host's caches (llama-cpp-cache vol + HF cache).
	@echo "# in docker volume $(LLAMACPP_CACHE_VOL):"
	@docker run --rm -v $(LLAMACPP_CACHE_VOL):/d alpine sh -c 'ls /d/*.gguf 2>/dev/null' \
	    | sed 's|.*/||; s|^|  |' || true
	@echo "# in $(HF_CACHE):"
	@find $(HF_CACHE) -name "*.gguf" 2>/dev/null \
	    | sed 's|^|  |' || true

hf-sync:  ## Reconcile envs against this host's GGUF inventory: create new, restore from .bak, orphan to .bak.
	@gguf_vol=$$(docker run --rm -v $(LLAMACPP_CACHE_VOL):/d alpine sh -c 'ls /d/*.gguf 2>/dev/null' | sed 's|.*/||' | sort -u); \
	gguf_hf=$$(find $(HF_CACHE) -name "*.gguf" 2>/dev/null | sort -u); \
	cd envs; \
	created=0; restored=0; orphaned=0; \
	for gguf in $$gguf_vol; do \
	    short=$$(echo "$$gguf" | sed -e 's/\.gguf$$//' -e 's/-MXFP4.*//' -e 's/-Q[0-9].*//' -e 's/-IQ[0-9].*//' | tr 'A-Z' 'a-z'); \
	    file="$$short-hf.env"; \
	    in_container="/root/.cache/llama.cpp/$$gguf"; \
	    if grep -lE "^MODEL_(PATH|URL)=.*$$gguf" *.env 2>/dev/null | head -1 >/dev/null; then \
	        :; \
	    elif [[ -f "$$file.bak" ]] && grep -qE "^MODEL_(PATH|URL)=.*$$gguf" "$$file.bak"; then \
	        printf '↩ restore %s ← %s.bak\n' "$$file" "$$file"; \
	        mv "$$file.bak" "$$file"; \
	        restored=$$((restored + 1)); \
	    elif [[ -f "$$file" ]]; then \
	        echo "  name clash: $$file already exists but points elsewhere — leave alone, rename manually if needed"; \
	    else \
	        printf '+ create  %s — MODEL_PATH=%s\n' "$$file" "$$in_container"; \
	        { \
	            echo "# $$gguf · in docker volume $(LLAMACPP_CACHE_VOL) on this host."; \
	            echo "# Self-contained — \`make up ENV=$$short-hf\` uses this directly."; \
	            echo ""; \
	            echo "LLAMACPP_TAG=$(LLAMACPP_TAG_DEFAULT)"; \
	            echo "HF_CACHE_HOST=$(HF_CACHE)"; \
	            echo "HF_TOKEN="; \
	            echo ""; \
	            echo "MODEL_PATH=$$in_container"; \
	            echo "MODEL_ALIAS=$$short"; \
	            echo "CTX_SIZE=8192"; \
	            echo "N_GPU_LAYERS=999"; \
	        } > "$$file"; \
	        created=$$((created + 1)); \
	    fi; \
	done; \
	for fp in $$gguf_hf; do \
	    base=$$(basename "$$fp"); \
	    short=$$(echo "$$base" | sed -e 's/\.gguf$$//' -e 's/-MXFP4.*//' -e 's/-Q[0-9].*//' -e 's/-IQ[0-9].*//' | tr 'A-Z' 'a-z'); \
	    file="$$short-hfcache.env"; \
	    in_container=$$(echo "$$fp" | sed 's|^$(HF_CACHE)|/root/.cache/huggingface|'); \
	    if grep -lE "^MODEL_PATH=.*$$base" *.env 2>/dev/null | head -1 >/dev/null; then \
	        :; \
	    elif [[ -f "$$file.bak" ]] && grep -qE "^MODEL_PATH=.*$$base" "$$file.bak"; then \
	        printf '↩ restore %s ← %s.bak\n' "$$file" "$$file"; \
	        mv "$$file.bak" "$$file"; \
	        restored=$$((restored + 1)); \
	    elif [[ -f "$$file" ]]; then \
	        echo "  name clash: $$file already exists but points elsewhere"; \
	    else \
	        printf '+ create  %s — MODEL_PATH=%s\n' "$$file" "$$in_container"; \
	        { \
	            echo "# $$base · in $(HF_CACHE) on this host."; \
	            echo "# Self-contained — \`make up ENV=$$short-hfcache\` uses this directly."; \
	            echo ""; \
	            echo "LLAMACPP_TAG=$(LLAMACPP_TAG_DEFAULT)"; \
	            echo "HF_CACHE_HOST=$(HF_CACHE)"; \
	            echo "HF_TOKEN="; \
	            echo ""; \
	            echo "MODEL_PATH=$$in_container"; \
	            echo "MODEL_ALIAS=$$short"; \
	            echo "CTX_SIZE=8192"; \
	            echo "N_GPU_LAYERS=999"; \
	        } > "$$file"; \
	        created=$$((created + 1)); \
	    fi; \
	done; \
	for f in *.env; do \
	    [[ -f "$$f" ]] || continue; \
	    p=$$(grep -E '^MODEL_PATH=' "$$f" | head -1 | cut -d= -f2-); \
	    [[ -z "$$p" ]] && continue; \
	    case "$$p" in \
	        /root/.cache/llama.cpp/*) \
	            name=$$(basename "$$p"); \
	            if ! grep -qFx "$$name" <<<"$$gguf_vol"; then \
	                printf '→ orphan  %s → %s.bak\n' "$$f" "$$f"; \
	                mv "$$f" "$$f.bak"; \
	                orphaned=$$((orphaned + 1)); \
	            fi;; \
	        /root/.cache/huggingface/*) \
	            host_path=$$(echo "$$p" | sed 's|^/root/.cache/huggingface|$(HF_CACHE)|'); \
	            if ! grep -qFx "$$host_path" <<<"$$gguf_hf"; then \
	                printf '→ orphan  %s → %s.bak\n' "$$f" "$$f"; \
	                mv "$$f" "$$f.bak"; \
	                orphaned=$$((orphaned + 1)); \
	            fi;; \
	    esac; \
	done; \
	echo "summary — $$created created, $$restored restored, $$orphaned orphaned"
