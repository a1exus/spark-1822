.DEFAULT_GOAL := help
SHELL := /usr/bin/env bash
.SHELLFLAGS := -e -o pipefail -c

VARIANT ?=
COMPOSE := docker compose -f docker-compose.yml

.PHONY: help list up down logs ps

help:  ## Show this help.
	@awk 'BEGIN{FS=":.*##"} /^[a-zA-Z_-]+:.*##/{printf "  \033[36m%-10s\033[0m %s\n",$$1,$$2}' $(MAKEFILE_LIST)
	@echo
	@echo "Usage:"
	@echo "  make list                       — show available env variants"
	@echo "  make up VARIANT=<name>          — start llama-cpp with that variant"
	@echo "  make logs                       — tail llama-cpp logs"
	@echo "  make down                       — stop llama-cpp"

list:  ## List available env variants under envs/.
	@ls envs/*.env 2>/dev/null | sed 's|envs/||; s|\.env$$||' | sort

up:  ## Activate a variant (copies envs/<name>.env → .env) and start. Usage: make up VARIANT=<name>
	@if [[ -z "$(VARIANT)" ]]; then \
	    echo "usage: make up VARIANT=<name>" >&2; \
	    echo "available:" >&2; $(MAKE) -s list | sed 's/^/  /' >&2; \
	    exit 64; \
	fi
	@if [[ ! -f envs/$(VARIANT).env ]]; then \
	    echo "variant not found: envs/$(VARIANT).env" >&2; \
	    echo "available:" >&2; $(MAKE) -s list | sed 's/^/  /' >&2; \
	    exit 1; \
	fi
	cp envs/$(VARIANT).env .env
	$(COMPOSE) up -d

down:  ## Stop llama-cpp (volumes preserved).
	$(COMPOSE) down

logs:  ## Tail llama-cpp logs.
	$(COMPOSE) logs -f llama-cpp

ps:  ## Show container status.
	$(COMPOSE) ps
