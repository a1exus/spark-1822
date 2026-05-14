.DEFAULT_GOAL := help
SHELL := /usr/bin/env bash
.SHELLFLAGS := -e -o pipefail -c
.SUFFIXES:
.DELETE_ON_ERROR:

CADDY_DATA_VOLUME ?= caddy-data
CERT_DAYS ?= 365

.PHONY: help wildcard-cert

help:  ## Show this help.
	@awk 'BEGIN{FS=":.*##"} /^[a-zA-Z_-]+:.*##/{printf "  \033[36m%-15s\033[0m %s\n",$$1,$$2}' $(MAKEFILE_LIST)
	@echo
	@echo "First-time setup on this host:"
	@echo "  sudo make wildcard-cert   # mint wildcard cert signed by Caddy's root CA"
	@echo "  docker compose up -d      # bring Traefik up (Caddy must be stopped — both want :80/:443)"

wildcard-cert:  ## Mint a wildcard cert (*.spark-1822.local) signed by Caddy's existing root CA. Re-run to renew.
	@mkdir -p certs
	@tmp=$$(mktemp -d) && trap "rm -rf $$tmp" EXIT && { \
	    echo "→ extracting Caddy's root CA from docker volume $(CADDY_DATA_VOLUME)"; \
	    docker run --rm -v $(CADDY_DATA_VOLUME):/d:ro -v "$$tmp:/out" alpine sh -c \
	        'cp /d/caddy/pki/authorities/local/root.crt /out/root.crt && \
	         cp /d/caddy/pki/authorities/local/root.key /out/root.key' \
	        || { echo "error: couldn't read $(CADDY_DATA_VOLUME) — has caddy come up at least once?" >&2; exit 1; }; \
	    echo "→ generating wildcard private key"; \
	    openssl genrsa -out certs/wildcard.key 2048 2>/dev/null; \
	    echo "→ generating CSR"; \
	    openssl req -new -key certs/wildcard.key -out "$$tmp/wildcard.csr" \
	        -config wildcard.cnf 2>/dev/null; \
	    echo "→ signing with Caddy's root (valid $(CERT_DAYS) days)"; \
	    openssl x509 -req -in "$$tmp/wildcard.csr" \
	        -CA "$$tmp/root.crt" -CAkey "$$tmp/root.key" -CAcreateserial \
	        -out certs/wildcard.crt -days $(CERT_DAYS) -sha256 \
	        -extfile wildcard.cnf -extensions v3_req 2>/dev/null; \
	    chmod 600 certs/wildcard.key; \
	    echo; \
	    echo "✓ wrote certs/wildcard.crt + certs/wildcard.key"; \
	    openssl x509 -in certs/wildcard.crt -noout -subject -issuer -dates | sed 's/^/  /'; \
	    echo; \
	    echo "  Issued by Caddy's root — clients that already trust caddy-root.crt"; \
	    echo "  will trust Traefik's leaf too. No new CA install needed."; \
	}
