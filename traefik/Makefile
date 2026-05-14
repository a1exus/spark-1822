.DEFAULT_GOAL := help
SHELL := /usr/bin/env bash
.SHELLFLAGS := -e -o pipefail -c
.SUFFIXES:
.DELETE_ON_ERROR:

CA_DAYS   ?= 3650        # 10 years for the root
CERT_DAYS ?= 365         # 1 year for the leaf (the wildcard)

.PHONY: help ca-cert wildcard-cert

help:  ## Show this help.
	@awk 'BEGIN{FS=":.*##"} /^[a-zA-Z_-]+:.*##/{printf "  \033[36m%-15s\033[0m %s\n",$$1,$$2}' $(MAKEFILE_LIST)
	@echo
	@echo "First-time setup on this host:"
	@echo "  make ca-cert            # mint Traefik's own internal root CA (one-time)"
	@echo "  make wildcard-cert      # mint the wildcard leaf signed by that root"
	@echo "  docker compose up -d    # bring Traefik up"
	@echo
	@echo "After ca-cert, install certs/traefik-root.crt on each client (README has per-OS steps)."

ca-cert:  ## Mint Traefik's own internal root CA. Long-lived; install certs/traefik-root.crt on each client.
	@mkdir -p certs
	@if [[ -e certs/traefik-root.crt && -e certs/traefik-root.key ]]; then \
	    echo "Traefik root CA already exists in certs/ — leaving alone."; \
	    echo "  (delete certs/traefik-root.* and re-run to rotate;"; \
	    echo "   every previously-trusting client will need the new root installed.)"; \
	    echo; \
	    openssl x509 -in certs/traefik-root.crt -noout -subject -issuer -dates | sed 's/^/  /'; \
	    exit 0; \
	fi
	@echo "→ generating root private key (4096-bit RSA)"
	@openssl genrsa -out certs/traefik-root.key 4096 2>/dev/null
	@echo "→ self-signing root certificate (valid $(CA_DAYS) days)"
	@openssl req -x509 -new -nodes -key certs/traefik-root.key -sha256 \
	    -days $(CA_DAYS) -out certs/traefik-root.crt \
	    -subj "/CN=sparky Traefik Local Root/O=sparky" \
	    -addext "basicConstraints=critical, CA:TRUE" \
	    -addext "keyUsage=critical, keyCertSign, cRLSign" 2>/dev/null
	@chmod 600 certs/traefik-root.key
	@echo
	@echo "✓ wrote certs/traefik-root.crt + certs/traefik-root.key"
	@openssl x509 -in certs/traefik-root.crt -noout -subject -issuer -dates | sed 's/^/  /'
	@echo
	@echo "  Install certs/traefik-root.crt on each client that needs to trust Traefik."
	@echo "  Per-OS steps: see traefik/README.md (mirrors the caddy-root.crt install table)."

wildcard-cert:  ## Mint the wildcard leaf cert signed by Traefik's root. Re-run to renew.
	@if [[ ! -e certs/traefik-root.crt || ! -e certs/traefik-root.key ]]; then \
	    echo "Traefik root CA not found — run 'make ca-cert' first." >&2; \
	    exit 1; \
	fi
	@mkdir -p certs
	@tmp=$$(mktemp -d) && trap "rm -rf $$tmp" EXIT && { \
	    echo "→ generating wildcard private key"; \
	    openssl genrsa -out certs/wildcard.key 2048 2>/dev/null; \
	    echo "→ generating CSR"; \
	    openssl req -new -key certs/wildcard.key -out "$$tmp/wildcard.csr" \
	        -config wildcard.cnf 2>/dev/null; \
	    echo "→ signing with Traefik's root (valid $(CERT_DAYS) days)"; \
	    openssl x509 -req -in "$$tmp/wildcard.csr" \
	        -CA certs/traefik-root.crt -CAkey certs/traefik-root.key -CAcreateserial \
	        -out certs/wildcard.crt -days $(CERT_DAYS) -sha256 \
	        -extfile wildcard.cnf -extensions v3_req 2>/dev/null; \
	    chmod 600 certs/wildcard.key; \
	    echo; \
	    echo "✓ wrote certs/wildcard.crt + certs/wildcard.key"; \
	    openssl x509 -in certs/wildcard.crt -noout -subject -issuer -dates | sed 's/^/  /'; \
	}
