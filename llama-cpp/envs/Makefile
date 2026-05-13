.DEFAULT_GOAL := help
SHELL := /usr/bin/env bash
.SHELLFLAGS := -e -o pipefail -c

REMOTE_HOST ?= spark-1822.local
HF_CACHE_HOST ?= /opt/hf/.cache/huggingface
LLAMACPP_CACHE_VOL ?= llama-cpp-cache

.PHONY: help list remote sync stale

help:  ## Show this help.
	@awk 'BEGIN{FS=":.*##"} /^[a-zA-Z_-]+:.*##/{printf "  \033[36m%-10s\033[0m %s\n",$$1,$$2}' $(MAKEFILE_LIST)
	@echo
	@echo "REMOTE_HOST=$(REMOTE_HOST)"
	@echo "HF_CACHE_HOST=$(HF_CACHE_HOST)"
	@echo "LLAMACPP_CACHE_VOL=$(LLAMACPP_CACHE_VOL)"

list:  ## List local variants under envs/.
	@ls *.env 2>/dev/null | sed 's/\.env$$//' | sort

remote:  ## Show GGUF files already on the remote host (llama-cpp-cache vol + HF cache).
	@echo "# in docker volume $(LLAMACPP_CACHE_VOL):"
	@ssh $(REMOTE_HOST) "docker run --rm -v $(LLAMACPP_CACHE_VOL):/d alpine sh -c 'ls /d/*.gguf 2>/dev/null'" \
	    | sed 's|.*/||; s|^|  |' || true
	@echo "# in $(HF_CACHE_HOST):"
	@ssh $(REMOTE_HOST) 'find $(HF_CACHE_HOST) -name "*.gguf" 2>/dev/null' \
	    | sed 's|^|  |' || true

# Synthesize a short variant name from a GGUF filename:
#   gpt-oss-safeguard-120b-MXFP4-00001-of-00002.gguf → gpt-oss-safeguard-120b
define gguf_shortname
$(shell echo "$(1)" | sed -e 's/\.gguf$$//' -e 's/-Q[0-9][A-Z_0-9]*//I' -e 's/-MXFP[0-9]\+//I' -e 's/-IQ[0-9][A-Z_0-9]*//I' -e 's/-0\?[0-9]\+-of-0\?[0-9]\+//' -e 's/\.0\?[0-9]\+-of-0\?[0-9]\+//' | tr 'A-Z' 'a-z')
endef

LLAMACPP_TAG_DEFAULT ?= server-cuda

sync:  ## Create a self-contained env file for each remote GGUF not yet present locally. Never overwrites; never downloads.
	@gguf_list=$$(ssh $(REMOTE_HOST) "docker run --rm -v $(LLAMACPP_CACHE_VOL):/d alpine sh -c 'ls /d/*.gguf 2>/dev/null'" | sed 's|.*/||' | sort -u); \
	hf_list=$$(ssh $(REMOTE_HOST) 'find $(HF_CACHE_HOST) -name "*.gguf" 2>/dev/null' | sort -u); \
	created=0; \
	for gguf in $$gguf_list; do \
	    short=$$(echo "$$gguf" | sed -e 's/\.gguf$$//' -e 's/-MXFP4.*//' -e 's/-Q[0-9].*//' -e 's/-IQ[0-9].*//' | tr 'A-Z' 'a-z'); \
	    file="$$short-hf.env"; \
	    if grep -lE "^MODEL_(PATH|URL)=.*$$gguf" *.env 2>/dev/null | head -1 >/dev/null; then \
	        echo "  covered ($$gguf)"; \
	    elif [[ -f "$$file" ]]; then \
	        echo "  name clash: $$file already exists but points elsewhere — leave alone, rename manually if needed"; \
	    else \
	        printf '+ create %s — MODEL_PATH=/root/.cache/llama.cpp/%s\n' "$$file" "$$gguf"; \
	        { \
	            echo "# $$gguf · in docker volume $(LLAMACPP_CACHE_VOL) on the remote host."; \
	            echo "# Self-contained — \`make up ENV=$$short-hf\` copies this to .env."; \
	            echo ""; \
	            echo "LLAMACPP_TAG=$(LLAMACPP_TAG_DEFAULT)"; \
	            echo "HF_CACHE_HOST=$(HF_CACHE_HOST)"; \
	            echo "HF_TOKEN="; \
	            echo ""; \
	            echo "MODEL_PATH=/root/.cache/llama.cpp/$$gguf"; \
	            echo "MODEL_ALIAS=$$short"; \
	            echo "CTX_SIZE=8192"; \
	            echo "N_GPU_LAYERS=999"; \
	        } > "$$file"; \
	        created=$$((created + 1)); \
	    fi; \
	done; \
	for fp in $$hf_list; do \
	    base=$$(basename "$$fp"); \
	    short=$$(echo "$$base" | sed -e 's/\.gguf$$//' -e 's/-MXFP4.*//' -e 's/-Q[0-9].*//' -e 's/-IQ[0-9].*//' | tr 'A-Z' 'a-z'); \
	    file="$$short-hfcache.env"; \
	    if grep -lE "^MODEL_PATH=.*$$base" *.env 2>/dev/null | head -1 >/dev/null; then \
	        echo "  covered ($$base)"; \
	    elif [[ -f "$$file" ]]; then \
	        echo "  name clash: $$file already exists but points elsewhere"; \
	    else \
	        in_container=$$(echo "$$fp" | sed 's|^$(HF_CACHE_HOST)|/root/.cache/huggingface|'); \
	        printf '+ create %s — MODEL_PATH=%s\n' "$$file" "$$in_container"; \
	        { \
	            echo "# $$base · in $(HF_CACHE_HOST) on the remote host."; \
	            echo "# Self-contained — \`make up ENV=$$short-hfcache\` copies this to .env."; \
	            echo ""; \
	            echo "LLAMACPP_TAG=$(LLAMACPP_TAG_DEFAULT)"; \
	            echo "HF_CACHE_HOST=$(HF_CACHE_HOST)"; \
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
	echo "synced — $$created new file(s)"

stale:  ## List local envs whose MODEL_PATH file isn't on the remote (only checks MODEL_PATH; URL/OLLAMA forms aren't validated).
	@gguf_vol=$$(ssh $(REMOTE_HOST) "docker run --rm -v $(LLAMACPP_CACHE_VOL):/d alpine sh -c 'ls /d/*.gguf 2>/dev/null'" | sort -u); \
	gguf_hf=$$(ssh $(REMOTE_HOST) 'find $(HF_CACHE_HOST) -name "*.gguf" 2>/dev/null' | sort -u); \
	for f in *.env; do \
	    [[ -f "$$f" ]] || continue; \
	    p=$$(grep -E '^MODEL_PATH=' "$$f" | head -1 | cut -d= -f2-); \
	    [[ -z "$$p" ]] && continue; \
	    host_path=$$(echo "$$p" | sed -e 's|^/root/.cache/llama.cpp/|/d/|' -e 's|^/root/.cache/huggingface|$(HF_CACHE_HOST)|'); \
	    case "$$p" in \
	        /root/.cache/llama.cpp/*) \
	            name=$$(basename "$$p"); \
	            if ! grep -qFx "/d/$$name" <<<"$$gguf_vol"; then echo "$$f — MODEL_PATH=$$p (not on remote)"; fi;; \
	        /root/.cache/huggingface/*) \
	            if ! grep -qFx "$$host_path" <<<"$$gguf_hf"; then echo "$$f — MODEL_PATH=$$p (not on remote)"; fi;; \
	    esac; \
	done
