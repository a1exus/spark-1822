.DEFAULT_GOAL := help
SHELL := /usr/bin/env bash
.SHELLFLAGS := -e -o pipefail -c

ENV ?=
COMPOSE := docker compose -f docker-compose.yml

.PHONY: help list up down logs ps

help:  ## Show this help.
	@awk 'BEGIN{FS=":.*##"} /^[a-zA-Z_-]+:.*##/{printf "  \033[36m%-10s\033[0m %s\n",$$1,$$2}' $(MAKEFILE_LIST)
	@echo
	@echo "Usage:"
	@echo "  make list                       — show available envs"
	@echo "  make up ENV=<name>              — start vllm with that env"
	@echo "  make logs                       — tail vllm logs"
	@echo "  make down                       — stop vllm"

list:  ## List available env variants under envs/.
	@ls envs/*.env 2>/dev/null | sed 's|envs/||; s|\.env$$||' | sort

up:  ## Activate a variant (copies envs/<name>.env → .env) and start. Usage: make up ENV=<name>
	@if [[ -z "$(ENV)" ]]; then \
	    echo "usage: make up ENV=<name>" >&2; \
	    echo "available:" >&2; $(MAKE) -s list | sed 's/^/  /' >&2; \
	    exit 64; \
	fi
	@if [[ ! -f envs/$(ENV).env ]]; then \
	    echo "variant not found: envs/$(ENV).env" >&2; \
	    echo "available:" >&2; $(MAKE) -s list | sed 's/^/  /' >&2; \
	    exit 1; \
	fi
	cp envs/$(ENV).env .env
	$(COMPOSE) up -d

down:  ## Stop vllm (volumes preserved).
	$(COMPOSE) down

logs:  ## Tail vllm logs.
	$(COMPOSE) logs -f vllm

ps:  ## Show container status.
	$(COMPOSE) ps
