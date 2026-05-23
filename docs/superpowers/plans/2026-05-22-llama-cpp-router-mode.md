# llama-cpp Router Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable llama.cpp router mode so a single `llama-server` container serves every GGUF in the host's HuggingFace CLI cache on demand, while keeping today's classic single-model mode working until verified.

**Architecture:** Router mode kicks in when no `MODEL_*` env vars are set; `llama-server` scans a flat symlink farm at `/models` (populated by `make hf-sync`), with per-model overrides in `/models/config.ini`. Auth via `LLAMA_API_KEY`. Classic mode (`MODEL_PATH` / `MODEL_OLLAMA` / `MODEL_URL`) untouched.

**Tech Stack:** Bash, Make, Python 3.11+ (`configparser` stdlib), Docker Compose, `jq`, `hf` CLI (HuggingFace).

**Spec:** [`docs/superpowers/specs/2026-05-22-llama-cpp-router-mode-design.md`](../specs/2026-05-22-llama-cpp-router-mode-design.md).

**Working directory:** All file edits happen in `/Users/alexus/opt/sparky/llama-cpp/` (the laptop checkout). Verification (Task 12) runs on the deployment host (spark-1822); commands are clearly marked.

---

## File map

```
llama-cpp/
├── docker-compose.yml              [MODIFY: +mount, +env vars]
├── entrypoint.sh                   [MODIFY: +router branch, +--api-key]
├── Makefile                        [MODIFY: loose up, +models, +hf-sync pass]
├── .env.example                    [MODIFY: +SYMLINK_FARM_HOST/MODELS_MAX/LLAMA_API_KEY/digest]
├── envs/README.md                  [MODIFY: legacy redirect]
├── README.md                       [MODIFY: router-mode section, demote classic]
└── scripts/                        [CREATE]
    ├── regen-config-ini.py         [CREATE: managed-fields config.ini regen]
    └── sync-router.sh              [CREATE: symlink farm + invokes regen]

README.md                           [MODIFY: service description]
```

Host-side, outside the repo (managed by `make hf-sync`):

```
/opt/hf/.cache/llama-cpp-models/    [CREATE at runtime — symlink farm]
├── config.ini                       [generated]
├── config.ini.orphans               [generated — removed-GGUF archive]
└── <model>.gguf → /root/.cache/huggingface/hub/...   [symlinks]
```

---

## Task 1: Re-resolve LLAMACPP_TAG, verify router-mode flags

**Files:**
- Modify: `llama-cpp/.env.example` (LLAMACPP_TAG line only)

> **Run on the deployment host (spark-1822).** Image pull + binary inspection need real Docker; can't be done from the laptop alone.

- [ ] **Step 1: Re-resolve the multi-arch digest for `server-cuda`**

```bash
ssh spark-1822
TOK=$(curl -s 'https://ghcr.io/token?service=ghcr.io&scope=repository:ggml-org/llama.cpp:pull' | jq -r .token)
curl -sI -H "Authorization: Bearer $TOK" \
    -H 'Accept: application/vnd.docker.distribution.manifest.list.v2+json' \
    'https://ghcr.io/v2/ggml-org/llama.cpp/manifests/server-cuda' \
    | grep -i docker-content-digest
```

Expected: a line like `docker-content-digest: sha256:<hex>`. Note the hex; you'll use it in step 4.

- [ ] **Step 2: Pull the new image**

```bash
DIGEST=sha256:<paste-from-step-1>
docker pull ghcr.io/ggml-org/llama.cpp:server-cuda@$DIGEST
```

Expected: pull completes; no `platform mismatch` warning. If you see `linux/amd64` warning, you grabbed the wrong digest — repeat step 1 making sure to include the `manifest.list.v2+json` Accept header.

- [ ] **Step 3: Verify router-mode flags exist in this build**

```bash
docker run --rm ghcr.io/ggml-org/llama.cpp:server-cuda@$DIGEST \
    /app/llama-server --help \
    | grep -E '(--models-dir|--models-max|--models-preset|--api-key)'
```

Expected: four lines, one per flag. If any is missing, the digest predates router mode — try a more recent tag (router mode landed 2025-12-11) by browsing <https://github.com/ggml-org/llama.cpp/pkgs/container/llama.cpp> and repeat step 1.

- [ ] **Step 4: Update `.env.example` with the new digest** *(on the laptop)*

Edit `llama-cpp/.env.example`. Replace the existing `LLAMACPP_TAG` line:

```diff
-LLAMACPP_TAG=server-cuda@sha256:a04923d31b4ca0d95bd772a4b80c9112f29121014df64d3d80a16a136ca19672
+LLAMACPP_TAG=server-cuda@sha256:<digest-from-step-1>
```

- [ ] **Step 5: Commit**

```bash
cd /Users/alexus/opt/sparky
git checkout -b llama-cpp-router-mode
git add llama-cpp/.env.example
git commit -m "llama-cpp: bump LLAMACPP_TAG to router-mode build"
```

---

## Task 2: docker-compose.yml — mount /models, add MODELS_MAX & LLAMA_API_KEY

**Files:**
- Modify: `llama-cpp/docker-compose.yml:39-46` (environment block), `llama-cpp/docker-compose.yml:27-38` (volumes block)

- [ ] **Step 1: Add the new environment passthroughs**

Edit `llama-cpp/docker-compose.yml`. In the `environment:` block, after the existing `N_GPU_LAYERS:` line, add two lines:

```yaml
      MODELS_MAX: ${MODELS_MAX:-2}
      LLAMA_API_KEY: ${LLAMA_API_KEY:-}
```

- [ ] **Step 2: Add the symlink-farm mount**

In the `volumes:` block, after the existing `HF_CACHE_HOST` mount line (the one ending in `:ro`), add:

```yaml
      # Symlink farm populated by `make hf-sync` on the host. Symlinks target
      # container-side absolute paths (under /root/.cache/huggingface) so they
      # resolve in-container; viewed on the host they'll appear broken.
      - ${SYMLINK_FARM_HOST:-/opt/hf/.cache/llama-cpp-models}:/models:ro
```

- [ ] **Step 3: Validate compose syntactically** *(on the host, or any machine with Docker)*

```bash
cd /Users/alexus/opt/sparky/llama-cpp
docker compose --env-file .env config 2>&1 | head -50
```

Expected: prints the resolved compose config with the two new env vars and the new mount. No errors.

If you're on the laptop without Docker installed, you can also `yq -p yaml docker-compose.yml > /dev/null` as a YAML-only sanity check (`brew install yq` if missing).

- [ ] **Step 4: Commit**

```bash
git add llama-cpp/docker-compose.yml
git commit -m "llama-cpp: mount /models + MODELS_MAX/LLAMA_API_KEY env (router mode)"
```

---

## Task 3: .env.example — add SYMLINK_FARM_HOST, MODELS_MAX, LLAMA_API_KEY

**Files:**
- Modify: `llama-cpp/.env.example` (append three new variables)

- [ ] **Step 1: Read the current file**

```bash
cat /Users/alexus/opt/sparky/llama-cpp/.env.example
```

Note the current shape so the new additions match its style.

- [ ] **Step 2: Append the three new variables**

Edit `llama-cpp/.env.example`. Append at the end of the file:

```bash

# --- Router mode (default when no MODEL_* is set) ---

# Host directory for the symlink farm — populated by `make hf-sync`,
# bind-mounted into the container at /models:ro. Router scans this directory.
SYMLINK_FARM_HOST=/opt/hf/.cache/llama-cpp-models

# Max models held resident in VRAM at once. LRU evicts the rest. Tune to:
#   MODELS_MAX × worst_case_resident_VRAM_GiB ≤ device_VRAM_GiB − headroom
# Default 2 because the 120b is ~65 GiB and the GB10 is 124 GiB total.
MODELS_MAX=2

# API key for the OpenAI-compat endpoint. Generate with `openssl rand -hex 32`.
# When non-empty, clients (OpenWebUI config, curl, scripts) must send
# `Authorization: Bearer $LLAMA_API_KEY`. Required for the Cloudflare Tunnel
# path (genuine internet exposure). Leave blank only for localhost-only testing.
LLAMA_API_KEY=
```

- [ ] **Step 3: Commit**

```bash
git add llama-cpp/.env.example
git commit -m "llama-cpp: document SYMLINK_FARM_HOST/MODELS_MAX/LLAMA_API_KEY"
```

---

## Task 4: entrypoint.sh — add router branch and --api-key support

**Files:**
- Modify: `llama-cpp/entrypoint.sh` (replace existing model-selection block + arg-build block)

- [ ] **Step 1: Replace `entrypoint.sh` contents**

The existing script picks one of `MODEL_PATH` / `MODEL_OLLAMA` / `MODEL_URL` and errors if none is set. The new flow adds a fourth path (router mode) when none is set. Replace the file's contents with:

```bash
#!/usr/bin/env bash
# llama-server launcher. Two modes:
#
#   Router mode (DEFAULT when no MODEL_* env var is set):
#     Serves every GGUF under /models (symlink farm populated by `make hf-sync`).
#     Per-model overrides live in /models/config.ini.
#
#   Classic single-model mode (one of these picks the model):
#     1. MODEL_PATH   — local file inside the container (any mounted dir).
#     2. MODEL_OLLAMA — Ollama model:tag — resolved against the mounted
#                       /ollama manifest store to the right blob path.
#     3. MODEL_URL    — remote URL (llama.cpp downloads + caches it).
#
# If LLAMA_API_KEY is non-empty (both modes): clients must send
#   Authorization: Bearer $LLAMA_API_KEY

set -euo pipefail

args=(
    --host "${LISTEN_HOST:-0.0.0.0}"
    --port "${LISTEN_PORT:-8080}"
)

# Resolve MODEL_OLLAMA → MODEL_PATH if set (and MODEL_PATH not already set).
if [[ -n "${MODEL_OLLAMA:-}" && -z "${MODEL_PATH:-}" ]]; then
    name="${MODEL_OLLAMA%:*}"
    tag="${MODEL_OLLAMA##*:}"
    manifest="/ollama/models/manifests/registry.ollama.ai/library/${name}/${tag}"
    if [[ ! -f "${manifest}" ]]; then
        echo "MODEL_OLLAMA=${MODEL_OLLAMA}: manifest not found at ${manifest}" >&2
        echo "available models:" >&2
        find /ollama/models/manifests/registry.ollama.ai/library -mindepth 2 -type f -printf '  %P\n' 2>/dev/null >&2 || true
        exit 1
    fi
    digest=$(awk -v RS='}' '
        /application\/vnd\.ollama\.image\.model/ {
            if (match($0, /sha256:[a-f0-9]+/)) {
                print substr($0, RSTART, RLENGTH); exit
            }
        }' "${manifest}")
    if [[ -z "${digest}" ]]; then
        echo "MODEL_OLLAMA=${MODEL_OLLAMA}: no model layer in manifest" >&2
        exit 1
    fi
    MODEL_PATH="/ollama/models/blobs/${digest/:/-}"
    echo "resolved MODEL_OLLAMA=${MODEL_OLLAMA} → MODEL_PATH=${MODEL_PATH}"
fi

if [[ -n "${MODEL_PATH:-}" ]]; then
    # ---- Classic: explicit local file ----
    if [[ ! -e "${MODEL_PATH}" ]]; then
        echo "MODEL_PATH=${MODEL_PATH} does not exist inside the container" >&2
        echo "available roots:" >&2
        echo "  /ollama/models/blobs/             — Ollama-cached GGUF blobs (sha256-named)" >&2
        echo "  /root/.cache/huggingface/hub/     — HuggingFace Hub cache snapshots" >&2
        echo "  /root/.cache/llama.cpp/           — llama.cpp's own download cache" >&2
        echo "  /models/                          — router-mode symlink farm" >&2
        exit 1
    fi
    args+=(
        --model "${MODEL_PATH}"
        --ctx-size "${CTX_SIZE:-32768}"
        --n-gpu-layers "${N_GPU_LAYERS:-999}"
        --alias "${MODEL_ALIAS:-llama-cpp}"
    )
elif [[ -n "${MODEL_URL:-}" ]]; then
    # ---- Classic: URL download ----
    args+=(
        --model-url "${MODEL_URL}"
        --ctx-size "${CTX_SIZE:-32768}"
        --n-gpu-layers "${N_GPU_LAYERS:-999}"
        --alias "${MODEL_ALIAS:-llama-cpp}"
    )
else
    # ---- Router mode (new default) ----
    if [[ ! -d /models ]]; then
        echo "router mode: /models bind mount missing — check SYMLINK_FARM_HOST in .env" >&2
        exit 1
    fi
    gguf_count=$(find /models -maxdepth 1 -name '*.gguf' 2>/dev/null | wc -l)
    if [[ "${gguf_count}" -eq 0 ]]; then
        echo "router mode warning: /models has no *.gguf entries — run \`make hf-sync\` on the host" >&2
    fi
    args+=(
        --models-dir /models
        --models-max "${MODELS_MAX:-2}"
    )
    if [[ -f /models/config.ini ]]; then
        args+=( --models-preset /models/config.ini )
    else
        echo "router mode warning: /models/config.ini missing — proceeding with built-in defaults" >&2
    fi
fi

# Auth (both modes). Treat blank as "no auth" so transition + local testing work.
if [[ -n "${LLAMA_API_KEY:-}" ]]; then
    args+=( --api-key "${LLAMA_API_KEY}" )
fi

echo "launching: llama-server ${args[*]}"
exec /app/llama-server "${args[@]}"
```

- [ ] **Step 2: Lint with `bash -n`**

```bash
bash -n /Users/alexus/opt/sparky/llama-cpp/entrypoint.sh
echo "exit: $?"
```

Expected: `exit: 0`. No output (clean parse).

- [ ] **Step 3: Verify the script still chmod-executes** (preserved by edit)

```bash
ls -l /Users/alexus/opt/sparky/llama-cpp/entrypoint.sh
```

Expected: `-rwxr-xr-x` (executable bit set). If not, `chmod +x` it.

- [ ] **Step 4: Smoke-check the router branch with shellcheck if installed** *(optional but recommended)*

```bash
command -v shellcheck && shellcheck /Users/alexus/opt/sparky/llama-cpp/entrypoint.sh || echo "shellcheck not installed; skipping"
```

Expected: no warnings, or `shellcheck not installed` (the existing script doesn't pass strict shellcheck for unrelated reasons; only investigate warnings new to your changes).

- [ ] **Step 5: Commit**

```bash
git add llama-cpp/entrypoint.sh
git commit -m "llama-cpp: router branch in entrypoint + --api-key passthrough"
```

---

## Task 5: Makefile — loosen `make up`, add `make models`

**Files:**
- Modify: `llama-cpp/Makefile` (`up` target, add `models` target)

- [ ] **Step 1: Replace the `up` target**

In `llama-cpp/Makefile`, find the existing `up:` target (around line 35-51) and replace it with:

```make
up:  ## Start. With ENV=<name>: classic single-model mode. Without: router mode (all GGUFs available).
	@if [[ -n "$(ENV)" && ! -f "envs/$(ENV).env" ]]; then \
	    echo "variant not found: envs/$(ENV).env" >&2; \
	    echo "available:" >&2; $(MAKE) -s list | sed 's/^/  /' >&2; \
	    exit 1; \
	fi
	@if [[ ! -f .env ]]; then \
	    echo "→ first-time setup: copying .env.example → .env (placeholder values"; \
	    echo "  so raw \`docker compose ps/logs/down\` work without --env-file)"; \
	    cp .env.example .env; \
	fi
	@if [[ -z "$(ENV)" ]]; then \
	    echo "→ router mode (no ENV): all GGUFs in /models will be served on demand"; \
	    $(COMPOSE) --env-file .env up -d; \
	else \
	    echo "→ classic mode: loading $(ENV) at startup"; \
	    $(COMPOSE) --env-file .env --env-file "envs/$(ENV).env" up -d; \
	fi
```

- [ ] **Step 2: Add the `models` target**

In `llama-cpp/Makefile`, after the `hf-cache:` target, add a new `models:` target:

```make
models:  ## Show /v1/models from the running container (router mode). Reads LLAMA_API_KEY from .env.
	@key=$$(grep -E '^LLAMA_API_KEY=' .env 2>/dev/null | head -1 | cut -d= -f2-); \
	if [[ -n "$$key" ]]; then \
	    auth_args=( -H "Authorization: Bearer $$key" ); \
	else \
	    auth_args=(); \
	fi; \
	curl -fsS "$${auth_args[@]}" http://127.0.0.1:8080/v1/models 2>/dev/null \
	    | jq . \
	    || { echo "could not reach http://127.0.0.1:8080/v1/models — is the container running and the key correct?" >&2; exit 1; }
```

- [ ] **Step 3: Update the `.PHONY` line**

In `llama-cpp/Makefile`, find the `.PHONY:` line (around line 13) and add `models` to it:

```make
.PHONY: help list up hf-cache hf-sync models
```

- [ ] **Step 4: Update the help-text echo block**

In `llama-cpp/Makefile`, find the `help:` recipe and add a line about `make models` and a line clarifying that `make up` now accepts an empty `ENV=`. Replace the help block's "Usage:" section with:

```make
	@echo "Usage:"
	@echo "  make list                       — show available env variants"
	@echo "  make up                         — start in router mode (all GGUFs available)"
	@echo "  make up ENV=<name>              — start in classic single-model mode"
	@echo
	@echo "GGUF-cache maintenance (llama-cpp-cache vol + HF cache):"
	@echo "  make hf-cache                   — list GGUF files in this host's caches"
	@echo "  make hf-sync                    — reconcile envs + router artifacts against the caches"
	@echo "  make models                     — show /v1/models from a running router-mode container"
```

- [ ] **Step 5: Validate Makefile syntax**

```bash
cd /Users/alexus/opt/sparky/llama-cpp
make -n up
make -n models
make -n help
```

Expected: `make -n up` prints router-mode message and the compose command without `--env-file envs/`; `make -n models` prints the curl command shell; `make -n help` prints the new usage block. No `make: ***` errors.

- [ ] **Step 6: Commit**

```bash
git add llama-cpp/Makefile
git commit -m "llama-cpp(make): loose up + new models target + help update"
```

---

## Task 6: scripts/regen-config-ini.py — managed-fields config.ini regenerator

**Files:**
- Create: `llama-cpp/scripts/regen-config-ini.py`

- [ ] **Step 1: Create the scripts/ directory and write the script**

```bash
mkdir -p /Users/alexus/opt/sparky/llama-cpp/scripts
```

Create `llama-cpp/scripts/regen-config-ini.py` with these contents:

```python
#!/usr/bin/env python3
"""Regenerate config.ini for llama.cpp router mode with managed-fields semantics.

Reads tab-separated GGUF inventory from stdin (one per line):
    <section-name>\t<container-model-path>\t<hf-alias>

Writes:
    <config-path>          active sections (one per current GGUF)
    <orphan-path>          removed-GGUF archive (restored verbatim if GGUF returns)

Managed-fields rules:
    - On each run, hf-sync owns the `model =` line of every active section.
    - All other keys are user-editable and preserved verbatim across runs.
    - A new section gets default `alias`, `ctx-size`, `n-gpu-layers` from CLI args.
    - When a GGUF disappears from the input, its section is moved to the
      orphan archive (kept verbatim). If the GGUF later returns, the archived
      section is restored as-is (preserving any user edits) — except `model`,
      which is rewritten from the current input.

Atomic writes: <path>.tmp + os.replace() so concurrent readers never see a
half-written file.
"""

from __future__ import annotations

import configparser
import os
import sys
from pathlib import Path


def _load(path: Path) -> configparser.ConfigParser:
    cp = configparser.ConfigParser()
    cp.optionxform = str  # preserve key case
    if path.exists():
        cp.read(path)
    return cp


def _write_atomic(cp: configparser.ConfigParser, path: Path, header: str) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w") as f:
        f.write(header)
        cp.write(f)
    os.replace(tmp, path)


def main() -> int:
    if len(sys.argv) != 5:
        print(
            f"usage: {sys.argv[0]} <config-path> <orphan-path> <ctx-default> <ngl-default>",
            file=sys.stderr,
        )
        return 64

    config_path = Path(sys.argv[1])
    orphan_path = Path(sys.argv[2])
    ctx_default = sys.argv[3]
    ngl_default = sys.argv[4]

    current: dict[str, tuple[str, str]] = {}
    for lineno, raw in enumerate(sys.stdin, 1):
        line = raw.rstrip("\n")
        if not line:
            continue
        parts = line.split("\t")
        if len(parts) != 3:
            print(
                f"stdin line {lineno}: expected 3 tab-separated fields, got {len(parts)}: {line!r}",
                file=sys.stderr,
            )
            return 2
        section, model, alias = parts
        current[section] = (model, alias)

    existing = _load(config_path)
    orphans = _load(orphan_path)

    new_config = configparser.ConfigParser()
    new_config.optionxform = str
    new_orphans = configparser.ConfigParser()
    new_orphans.optionxform = str

    for section, (model, alias) in current.items():
        if existing.has_section(section):
            new_config[section] = dict(existing.items(section))
            new_config[section]["model"] = model  # managed field
        elif orphans.has_section(section):
            new_config[section] = dict(orphans.items(section))
            new_config[section]["model"] = model
        else:
            new_config[section] = {
                "model": model,
                "alias": alias,
                "ctx-size": ctx_default,
                "n-gpu-layers": ngl_default,
            }

    for section in existing.sections():
        if section not in current:
            new_orphans[section] = dict(existing.items(section))
    for section in orphans.sections():
        if section not in current and not new_orphans.has_section(section):
            new_orphans[section] = dict(orphans.items(section))

    config_header = (
        "# Auto-generated by `make hf-sync`. Sections are managed:\n"
        "#   - hf-sync owns the `model` line (rewritten every run).\n"
        "#   - All other keys are user-editable and preserved across runs.\n"
        "#   - Removed GGUFs go to config.ini.orphans (restored if they return).\n\n"
    )
    orphan_header = (
        "# Orphan archive — sections for GGUFs no longer in the HF cache.\n"
        "# Restored verbatim if the GGUF returns. Edit freely.\n\n"
    )
    _write_atomic(new_config, config_path, config_header)
    _write_atomic(new_orphans, orphan_path, orphan_header)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x /Users/alexus/opt/sparky/llama-cpp/scripts/regen-config-ini.py
```

- [ ] **Step 3: Smoke test — fresh config**

Run this from anywhere; it uses a tmpdir.

```bash
cd "$(mktemp -d)"
printf 'gpt-oss-safeguard-120b\t/models/gpt-oss-safeguard-120b-MXFP4-00001-of-00002.gguf\tlmstudio-community/gpt-oss-safeguard-120b-GGUF:MXFP4\n' \
    | /Users/alexus/opt/sparky/llama-cpp/scripts/regen-config-ini.py ./config.ini ./config.ini.orphans 8192 999

echo "--- config.ini ---"
cat config.ini
echo "--- config.ini.orphans ---"
cat config.ini.orphans
```

Expected `config.ini`:

```ini
# Auto-generated by `make hf-sync`. Sections are managed:
#   - hf-sync owns the `model` line (rewritten every run).
#   - All other keys are user-editable and preserved across runs.
#   - Removed GGUFs go to config.ini.orphans (restored if they return).

[gpt-oss-safeguard-120b]
model = /models/gpt-oss-safeguard-120b-MXFP4-00001-of-00002.gguf
alias = lmstudio-community/gpt-oss-safeguard-120b-GGUF:MXFP4
ctx-size = 8192
n-gpu-layers = 999
```

Expected `config.ini.orphans`: just the header, no sections.

- [ ] **Step 4: Smoke test — preserve hand-edits**

```bash
# Same tmpdir as step 3
# Hand-edit ctx-size in the config we just wrote.
sed -i.bak 's/^ctx-size = 8192/ctx-size = 32768/' config.ini

# Re-run with same input.
printf 'gpt-oss-safeguard-120b\t/models/gpt-oss-safeguard-120b-MXFP4-00001-of-00002.gguf\tlmstudio-community/gpt-oss-safeguard-120b-GGUF:MXFP4\n' \
    | /Users/alexus/opt/sparky/llama-cpp/scripts/regen-config-ini.py ./config.ini ./config.ini.orphans 8192 999

grep -E '^ctx-size' config.ini
```

Expected: `ctx-size = 32768` (hand-edit preserved).

- [ ] **Step 5: Smoke test — orphan + restoration**

```bash
# Re-run with a *different* GGUF — old section should orphan.
printf 'qwen3-30b\t/models/qwen3-30b-Q4_K_M.gguf\tQwen/Qwen3-30B-GGUF:Q4_K_M\n' \
    | /Users/alexus/opt/sparky/llama-cpp/scripts/regen-config-ini.py ./config.ini ./config.ini.orphans 8192 999

echo "--- config.ini ---"
cat config.ini
echo "--- config.ini.orphans ---"
cat config.ini.orphans
```

Expected: `config.ini` has only `[qwen3-30b]`. `config.ini.orphans` contains `[gpt-oss-safeguard-120b]` with `ctx-size = 32768` (preserved).

Now restore:

```bash
printf 'gpt-oss-safeguard-120b\t/models/gpt-oss-safeguard-120b-MXFP4-00001-of-00002.gguf\tlmstudio-community/gpt-oss-safeguard-120b-GGUF:MXFP4\nqwen3-30b\t/models/qwen3-30b-Q4_K_M.gguf\tQwen/Qwen3-30B-GGUF:Q4_K_M\n' \
    | /Users/alexus/opt/sparky/llama-cpp/scripts/regen-config-ini.py ./config.ini ./config.ini.orphans 8192 999

grep -E '^(\[|ctx-size)' config.ini
```

Expected: two sections, and `[gpt-oss-safeguard-120b]`'s `ctx-size = 32768` is restored from the orphan archive.

- [ ] **Step 6: Cleanup tmpdir**

```bash
TMP_FROM_STEP3=$(pwd)   # if you're still in it
cd /Users/alexus/opt/sparky
rm -rf "$TMP_FROM_STEP3"
```

- [ ] **Step 7: Commit**

```bash
git add llama-cpp/scripts/regen-config-ini.py
git commit -m "llama-cpp(scripts): regen-config-ini.py (managed-fields router config)"
```

---

## Task 7: scripts/sync-router.sh — symlink farm + invokes regen-config-ini.py

**Files:**
- Create: `llama-cpp/scripts/sync-router.sh`

- [ ] **Step 1: Write the script**

Create `llama-cpp/scripts/sync-router.sh` with these contents:

```bash
#!/usr/bin/env bash
# Build the symlink farm for llama.cpp router mode, then regenerate config.ini.
# Idempotent. Called by `make hf-sync` (which exports the env vars below).
#
# Env (with defaults):
#   HF_CACHE        host HuggingFace cache dir (default /opt/hf/.cache/huggingface)
#   SYMLINK_FARM    host symlink farm dir (default /opt/hf/.cache/llama-cpp-models)
#   CTX_DEFAULT     default ctx-size for new config.ini sections (default 8192)
#   NGL_DEFAULT     default n-gpu-layers for new config.ini sections (default 999)

set -euo pipefail

HF_CACHE="${HF_CACHE:-/opt/hf/.cache/huggingface}"
SYMLINK_FARM="${SYMLINK_FARM:-/opt/hf/.cache/llama-cpp-models}"
CTX_DEFAULT="${CTX_DEFAULT:-8192}"
NGL_DEFAULT="${NGL_DEFAULT:-999}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGEN="$SCRIPT_DIR/regen-config-ini.py"

if [[ ! -x "$REGEN" ]]; then
    echo "sync-router: $REGEN not executable" >&2
    exit 1
fi
mkdir -p "$SYMLINK_FARM"

# Enumerate GGUFs in the HF cache. Output: <repo-id>\t<host-path>
list_ggufs() {
    if command -v hf >/dev/null 2>&1; then
        if hf cache scan --format json 2>/dev/null \
            | jq -re --arg cache "$HF_CACHE" '
                .repos[]
                | .repo_id as $repo
                | .revisions[]
                | .files[]
                | select(.path | endswith(".gguf"))
                | "\($repo)\t\(.path)"
            '; then
            return
        fi
    fi
    # Fallback: find walk; derive repo from path.
    find "$HF_CACHE/hub" -name "*.gguf" 2>/dev/null \
        | while read -r fp; do
            repo=$(echo "$fp" | sed -nE 's|.*/hub/models--([^/]+)/.*|\1|p' | sed 's|--|/|')
            [[ -n "$repo" ]] || continue
            printf '%s\t%s\n' "$repo" "$fp"
        done
}

declare -A seen=()
specs=""
created=0
unchanged=0
collisions=0

while IFS=$'\t' read -r repo host_path; do
    [[ -n "$host_path" ]] || continue
    base=$(basename "$host_path")
    container_path="${host_path/#$HF_CACHE/\/root\/.cache\/huggingface}"

    if [[ -n "${seen[$base]:-}" ]]; then
        echo "  collision: $base already linked from ${seen[$base]}; skipping $repo" >&2
        collisions=$((collisions + 1))
        continue
    fi
    seen[$base]=$repo

    section=$(echo "$base" \
        | sed -E 's/\.gguf$//; s/-0*[0-9]+-of-[0-9]+$//; s/-MXFP4.*//; s/-Q[0-9].*//; s/-IQ[0-9].*//; s/-F1[6]$//; s/-F32$//' \
        | tr '[:upper:]' '[:lower:]')

    quant=$(echo "$base" | grep -oE '(MXFP4|Q[0-9][_KMS0-9]*|IQ[0-9][_KMS0-9]*|F16|F32)' | head -1 || true)
    if [[ -n "$quant" ]]; then
        hf_alias="$repo:$quant"
    else
        hf_alias="$repo"
    fi

    target="$SYMLINK_FARM/$base"
    if [[ -L "$target" && "$(readlink "$target")" == "$container_path" ]]; then
        unchanged=$((unchanged + 1))
    else
        ln -sfn "$container_path" "$target"
        echo "+ symlink $base → $container_path"
        created=$((created + 1))
    fi

    # Only the first part of a multi-part split is the load entry point.
    part=$(echo "$base" | sed -nE 's/.*-0*([0-9]+)-of-[0-9]+\.gguf$/\1/p')
    if [[ -z "$part" || "$part" == "1" ]]; then
        specs+="$section"$'\t'"/models/$base"$'\t'"$hf_alias"$'\n'
    fi
done < <(list_ggufs)

orphaned=0
shopt -s nullglob
for link in "$SYMLINK_FARM"/*.gguf; do
    base=$(basename "$link")
    if [[ -z "${seen[$base]:-}" ]]; then
        echo "→ orphan symlink: $base"
        rm "$link"
        orphaned=$((orphaned + 1))
    fi
done

printf '%s' "$specs" | "$REGEN" \
    "$SYMLINK_FARM/config.ini" \
    "$SYMLINK_FARM/config.ini.orphans" \
    "$CTX_DEFAULT" \
    "$NGL_DEFAULT"

echo "router summary: $created symlinks created/updated, $unchanged unchanged, $orphaned orphaned, $collisions collisions"
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x /Users/alexus/opt/sparky/llama-cpp/scripts/sync-router.sh
```

- [ ] **Step 3: Lint**

```bash
bash -n /Users/alexus/opt/sparky/llama-cpp/scripts/sync-router.sh
command -v shellcheck && shellcheck /Users/alexus/opt/sparky/llama-cpp/scripts/sync-router.sh || echo "shellcheck not installed"
```

Expected: `bash -n` exits 0. If shellcheck is installed, it should report no critical issues (some style warnings are OK).

- [ ] **Step 4: Smoke test with a fake HF cache**

```bash
TMP=$(mktemp -d)
HF=$TMP/hf
FARM=$TMP/farm
mkdir -p "$HF/hub/models--lmstudio-community--gpt-oss-safeguard-120b-GGUF/snapshots/abc123" \
         "$HF/hub/models--Qwen--Qwen3-30B-GGUF/snapshots/def456"
touch "$HF/hub/models--lmstudio-community--gpt-oss-safeguard-120b-GGUF/snapshots/abc123/gpt-oss-safeguard-120b-MXFP4-00001-of-00002.gguf"
touch "$HF/hub/models--lmstudio-community--gpt-oss-safeguard-120b-GGUF/snapshots/abc123/gpt-oss-safeguard-120b-MXFP4-00002-of-00002.gguf"
touch "$HF/hub/models--Qwen--Qwen3-30B-GGUF/snapshots/def456/qwen3-30b-Q4_K_M.gguf"

HF_CACHE="$HF" SYMLINK_FARM="$FARM" /Users/alexus/opt/sparky/llama-cpp/scripts/sync-router.sh

echo "--- farm contents ---"
ls -la "$FARM"
echo "--- config.ini ---"
cat "$FARM/config.ini"
```

Expected farm contents: three `*.gguf` symlinks (both 120b parts, one Qwen) all pointing at paths starting with `/root/.cache/huggingface/...`. The two `.tmp` files should NOT remain (atomic move).

Expected `config.ini`: two `[section]` blocks (`gpt-oss-safeguard-120b` and `qwen3-30b`) — only the first part of the 120b split appears as a section (the second part is symlinked but not a separate model entry).

- [ ] **Step 5: Smoke test — re-run is idempotent**

```bash
HF_CACHE="$HF" SYMLINK_FARM="$FARM" /Users/alexus/opt/sparky/llama-cpp/scripts/sync-router.sh
```

Expected: summary line shows `0 symlinks created/updated, 3 unchanged, 0 orphaned, 0 collisions`. No diffs in `config.ini` (byte-identical aside from a possible tmp dance — diff if curious).

- [ ] **Step 6: Smoke test — orphan removal**

```bash
rm "$HF/hub/models--Qwen--Qwen3-30B-GGUF/snapshots/def456/qwen3-30b-Q4_K_M.gguf"
HF_CACHE="$HF" SYMLINK_FARM="$FARM" /Users/alexus/opt/sparky/llama-cpp/scripts/sync-router.sh

ls "$FARM"/*.gguf | wc -l
cat "$FARM/config.ini.orphans"
```

Expected: 2 symlinks left (the two 120b parts), 1 orphaned. Orphan archive contains `[qwen3-30b]`.

- [ ] **Step 7: Cleanup**

```bash
rm -rf "$TMP"
```

- [ ] **Step 8: Commit**

```bash
git add llama-cpp/scripts/sync-router.sh
git commit -m "llama-cpp(scripts): sync-router.sh (symlink farm + config.ini regen)"
```

---

## Task 8: Makefile — call sync-router.sh from hf-sync, annotate hf-cache

**Files:**
- Modify: `llama-cpp/Makefile` (`hf-sync` target, `hf-cache` target)

- [ ] **Step 1: Append the router pass to `hf-sync`**

In `llama-cpp/Makefile`, find the end of the existing `hf-sync:` recipe (after the closing `fi` and the `note: ...` block). At the very end of the recipe (after the existing summary echo), insert a new pass. Right before the line that begins `summary — ...`, leave it alone; after the existing `note: ...` block (the last `fi`), add:

```make
	@echo
	@echo "# router artifacts — symlink farm + config.ini"
	@HF_CACHE="$(HF_CACHE)" \
	    SYMLINK_FARM="$${SYMLINK_FARM_HOST:-/opt/hf/.cache/llama-cpp-models}" \
	    CTX_DEFAULT="$${CTX_SIZE:-8192}" \
	    NGL_DEFAULT="$${N_GPU_LAYERS:-999}" \
	    ./scripts/sync-router.sh
```

(The `$${...}` form lets Make pass the literal `${...}` through to the shell so the shell does the env-var defaulting from the calling shell's environment / .env loaded by `make`.)

- [ ] **Step 2: Annotate `hf-cache` with `[router]` flag**

In `llama-cpp/Makefile`, find the `hf-cache:` recipe. Modify the GGUF-counter loop to check the symlink farm too. Replace the body of the `hf-cache:` recipe with:

```make
	@echo "# in docker volume $(LLAMACPP_CACHE_VOL) — usable by llama-cpp:"
	@docker run --rm -v $(LLAMACPP_CACHE_VOL):/d alpine sh -c 'ls /d/*.gguf 2>/dev/null' \
	    | sed 's|.*/||; s|^|  |' || true
	@echo
	@echo "# in $(HF_CACHE) — populated by \`hf download\` / vllm; usable by llama-cpp only when GGUF is present:"
	@farm="$${SYMLINK_FARM_HOST:-/opt/hf/.cache/llama-cpp-models}"; \
	shopt -s nullglob; \
	for d in $(HF_CACHE)/hub/models--*/; do \
	    repo=$$(basename "$$d" | sed 's|^models--||; s|--|/|'); \
	    gg=$$(find "$$d" -name "*.gguf" 2>/dev/null | wc -l); \
	    st=$$(find "$$d" -name "*.safetensors" 2>/dev/null | wc -l); \
	    router_flag=""; \
	    if [[ $$gg -gt 0 && -d "$$farm" ]]; then \
	        for fp in $$(find "$$d" -name "*.gguf" 2>/dev/null); do \
	            if [[ -L "$$farm/$$(basename "$$fp")" ]]; then router_flag=" [router]"; break; fi; \
	        done; \
	    fi; \
	    if [[ $$gg -gt 0 ]]; then \
	        printf "  %-60s [%d GGUF — llama-cpp can load]%s\n" "$$repo" "$$gg" "$$router_flag"; \
	    else \
	        printf "  %-60s [%d safetensors — vllm only]\n" "$$repo" "$$st"; \
	    fi; \
	done
```

- [ ] **Step 3: Validate**

```bash
cd /Users/alexus/opt/sparky/llama-cpp
make -n hf-sync | tail -20
make -n hf-cache | tail -20
```

Expected: both targets parse; `make -n hf-sync` shows the `# router artifacts` line and the `sync-router.sh` invocation at the end.

- [ ] **Step 4: Commit**

```bash
git add llama-cpp/Makefile
git commit -m "llama-cpp(make): hf-sync gains router pass; hf-cache annotates [router]"
```

---

## Task 9: llama-cpp/README.md — router-mode section, demote classic to legacy

**Files:**
- Modify: `llama-cpp/README.md`

- [ ] **Step 1: Read the current README to understand structure**

Already familiar from the spec phase; the file has these top-level sections in order: intro, "Supported model formats", "Topology", "Files", "Configure" (with subsections incl "Pinning the image"), "Deploy", "Changing the model" (with subsections), "Upgrade", "Logs", "Uninstall", "See also".

- [ ] **Step 2: Insert a "Router mode (default)" section right after "Topology"**

Between the existing "Topology" section and the "Files" section, insert a new H2 (the block below uses 4-backtick outer fences so its nested triple-backtick code blocks render correctly — when you paste into README.md, drop the outermost 4-backtick fences and keep only the inner content):

````markdown
## Router mode (default)

When no `MODEL_*` env var is set, `llama-server` runs in **router mode**: it scans `/models` (a symlink farm populated by `make hf-sync`) and serves every GGUF it finds, loading on demand. Up to `MODELS_MAX` models stay resident in VRAM; LRU evicts the rest.

```bash
make up                       # router mode — all GGUFs available
make models                   # show /v1/models from the running container
curl -H "Authorization: Bearer $LLAMA_API_KEY" \
     https://llama.spark-1822.local/v1/models | jq .
```

A request specifies the model in the usual OpenAI-API way:

```bash
curl -k -H "Authorization: Bearer $LLAMA_API_KEY" \
     https://llama.spark-1822.local/v1/chat/completions \
     -H 'Content-Type: application/json' \
     -d '{"model":"gpt-oss-safeguard-120b","messages":[{"role":"user","content":"hi"}]}'
```

Each GGUF gets a short alias (`gpt-oss-safeguard-120b`) **and** an HF-style ID (`lmstudio-community/gpt-oss-safeguard-120b-GGUF:MXFP4`) — both work in the `model` field.

### Authentication

`LLAMA_API_KEY` in `.env` is required when the endpoint is reachable from anywhere other than `127.0.0.1`. Generate once at deploy:

```bash
echo "LLAMA_API_KEY=$(openssl rand -hex 32)" >> .env
```

Clients (OpenWebUI's `LITELLM_BASE_URL_API_KEY` or equivalent, curl scripts) must send `Authorization: Bearer $LLAMA_API_KEY`. If `LLAMA_API_KEY` is blank, the endpoint is open — useful for one-off local testing but **not** safe with the Cloudflare Tunnel path active.

### VRAM budget

The router has **no per-model VRAM accounting** — `MODELS_MAX` is a count, not a byte budget. Set it so the worst case fits:

```
MODELS_MAX × worst_case_resident_VRAM_GiB  ≤  device_VRAM_GiB − headroom
```

GB10 has 124 GiB; reserve ~8 GiB for headroom. Default `MODELS_MAX=2` is sized for the 120b at ~65 GiB resident. If you remove the 120b from the cache and only run smaller (≤30 GiB) models, bump to `4`.

### Tuning per model

Per-model overrides live in `<symlink-farm>/config.ini`, regenerated by `make hf-sync` and **preserves your hand-edits** (only `model =` is rewritten on each sync). Edit a section to override:

```ini
[gpt-oss-safeguard-120b]
model = /models/gpt-oss-safeguard-120b-MXFP4-00001-of-00002.gguf
alias = lmstudio-community/gpt-oss-safeguard-120b-GGUF:MXFP4
ctx-size = 8192            # default from .env; tune as needed
n-gpu-layers = 999
```

### Symlink farm

`make hf-sync` builds `${SYMLINK_FARM_HOST}` (default `/opt/hf/.cache/llama-cpp-models/`) with one symlink per GGUF in the HF cache. Symlinks target **container-side absolute paths** (`/root/.cache/huggingface/hub/...`), so they only resolve **inside the container**:

```bash
ls -L /opt/hf/.cache/llama-cpp-models/    # symlinks appear "broken" on the host — this is expected
docker exec llama-cpp ls -L /models/      # resolves fine in the container
```

### Limitations

- **Safetensors-only HF repos are invisible.** The 4 such repos in this host's cache (`openai/gpt-oss-120b`, `openai/gpt-oss-20b`, `Qwen/Qwen3.6-27B`, `Jackrong/Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled`) are not loadable by llama.cpp. Pull a GGUF variant from HF (look for `<author>/<repo>-GGUF`) or convert with `convert_hf_to_gguf.py` to make them appear.
- **Ollama blobs not in the router.** Reachable only via classic mode (`MODEL_OLLAMA=<name>:<tag>`).
- **URL-downloaded GGUFs not in the router.** Reachable only via classic mode (`MODEL_URL=<url>`).
- **One `--models-dir` only.** The router can't combine the HF cache and other sources in one scan.

````

- [ ] **Step 3: Demote the "Changing the model" section to "Classic single-model mode (legacy)"**

Find the H2 `## Changing the model`. Replace its heading with:

```markdown
## Classic single-model mode (legacy)

> Router mode (above) is the new default. This section documents the original workflow where one variant file picks exactly one model at start. Kept working during the trial; scheduled for removal once router mode is verified.
```

Leave the existing subsections (`### Adding a new variant from the HuggingFace CLI cache`, etc.) intact below this new intro.

- [ ] **Step 4: Update the "Files" tree**

Find the `## Files` H2 and its code-fenced tree. Replace the tree with (again, 4-backtick outer fence; drop it when pasting):

````markdown
```
llama-cpp/
├── docker-compose.yml
├── entrypoint.sh         # router branch + classic mode + --api-key passthrough
├── Makefile              # make up [ENV=…] / make hf-cache / make hf-sync / make models
├── scripts/
│   ├── regen-config-ini.py    # managed-fields config.ini regen
│   └── sync-router.sh         # builds symlink farm; invokes regen-config-ini.py
├── envs/                 # classic single-model mode only — see "Classic … (legacy)" below
│   ├── README.md
│   └── *.env             # auto-generated by `make hf-sync`
├── .env.example          # committed; copy to .env (`make up` auto-bootstraps)
└── .env                   # gitignored placeholder so raw `docker compose` works
```

Host-side, populated by `make hf-sync`:

```
${SYMLINK_FARM_HOST:-/opt/hf/.cache/llama-cpp-models}/
├── config.ini                                       # per-model overrides
├── config.ini.orphans                               # archive of removed GGUFs (restored if they return)
└── <model>.gguf → /root/.cache/huggingface/...      # symlinks
```
````

- [ ] **Step 5: Update the "Configure" section's two-layer description**

Find the `## Configure` H2 and its "Two layers:" intro. Add a third bullet (for `config.ini`) and a sentence about `LLAMA_API_KEY`. Replace the "Two layers:" block with:

```markdown
Three layers in router mode (two in classic mode — the third doesn't apply):

- **`.env`** (host-wide) — shared across every variant. `LLAMACPP_TAG` (image pin), `HF_CACHE_HOST`, `HF_TOKEN`, `SYMLINK_FARM_HOST`, `MODELS_MAX`, `LLAMA_API_KEY`, default `MODEL_ALIAS` / `CTX_SIZE` / `N_GPU_LAYERS`. Bootstrapped from `.env.example` by `make up` on first run; gitignored thereafter.
- **`envs/<name>.env`** (per-variant, classic mode only) — just the model selection: `MODEL_PATH` (or `MODEL_OLLAMA` / `MODEL_URL`), `MODEL_ALIAS`, and any per-variant overrides.
- **`${SYMLINK_FARM_HOST}/config.ini`** (per-model, router mode only) — auto-generated by `make hf-sync`; hand-edits are preserved (only `model =` is managed by hf-sync).
```

- [ ] **Step 6: Validate the markdown renders correctly**

```bash
cd /Users/alexus/opt/sparky/llama-cpp
# Optional: render check
command -v glow >/dev/null && glow -p README.md | head -200 || cat README.md | head -80
```

Expected: no broken code fences, table-of-contents-friendly structure.

- [ ] **Step 7: Commit**

```bash
git add llama-cpp/README.md
git commit -m "docs(llama-cpp): router mode is the default; classic demoted to legacy"
```

---

## Task 10: envs/README.md + repo-root README.md updates

**Files:**
- Modify: `llama-cpp/envs/README.md`
- Modify: `README.md` (repo root)

- [ ] **Step 1: Read envs/README.md**

```bash
cat /Users/alexus/opt/sparky/llama-cpp/envs/README.md
```

- [ ] **Step 2: Prepend the legacy notice**

Add at the very top of `llama-cpp/envs/README.md`:

```markdown
> **Note:** `envs/` is for **classic single-model mode** only. Router mode (the default) discovers models from the HF cache via the symlink farm at `${SYMLINK_FARM_HOST}/`. See [../README.md → Router mode](../README.md#router-mode-default). The contents below are kept working during the router-mode trial; they'll be removed (moved to `.bak`) once router mode is verified.

---

```

- [ ] **Step 3: Read root README.md**

```bash
cat /Users/alexus/opt/sparky/README.md | head -80
```

Look for the line describing the `llama-cpp` service.

- [ ] **Step 4: Update root README service description**

Find the line describing `llama-cpp` (typically a one-line entry in a services list / table). Update it to reference router mode. For example, if the current line is:

```markdown
- `llama-cpp/` — llama.cpp GPU-accelerated inference server for a single GGUF model.
```

Change to:

```markdown
- `llama-cpp/` — llama.cpp GPU-accelerated inference server. Router mode (default) serves every GGUF in the HF cache on demand; classic single-model mode also supported.
```

(Adjust to match the actual format used in the root README — match the indentation, bullet style, and surrounding language.)

- [ ] **Step 5: Commit**

```bash
git add llama-cpp/envs/README.md README.md
git commit -m "docs: env/ legacy note + root README router-mode mention"
```

---

## Task 11: Push branch and open PR

**Files:** none (git remote operations)

- [ ] **Step 1: Push the branch**

```bash
cd /Users/alexus/opt/sparky
git push -u origin llama-cpp-router-mode
```

- [ ] **Step 2: Open the PR**

```bash
gh pr create --title "llama-cpp: router mode (multi-model auto-discovery from HF cache)" \
    --body "$(cat <<'EOF'
## Summary
- Enables llama.cpp router mode so one container serves every locally-cached GGUF on demand
- Adds symlink farm + auto-generated `config.ini` populated by `make hf-sync`
- Requires `LLAMA_API_KEY` (industry standard for non-localhost OpenAI-compat endpoints)
- Coexists with classic single-model mode — flip with `make up ENV=<name>` to pin one model

Spec: `docs/superpowers/specs/2026-05-22-llama-cpp-router-mode-design.md`
Plan: `docs/superpowers/plans/2026-05-22-llama-cpp-router-mode.md`

## Test plan
- [ ] Image digest verified to expose `--models-dir`, `--models-max`, `--models-preset`, `--api-key`
- [ ] `make hf-sync` populates `/opt/hf/.cache/llama-cpp-models/` with symlinks + non-empty `config.ini`
- [ ] `make up` (no ENV) starts router mode; healthcheck green
- [ ] `make models` lists every GGUF in the cache with status `unloaded`
- [ ] On-demand load works; LRU eviction observed at `MODELS_MAX`
- [ ] Classic mode (`make up ENV=gpt-oss-safeguard-120b-hf`) still works as before
- [ ] OpenWebUI sees the model list and routes chats correctly
- [ ] `make hf-sync` is idempotent and preserves hand-edits to `config.ini`
- [ ] Atomic writes verified by hammering `make hf-sync` while server is up
- [ ] Auth: `curl` without header → 401; with header → 200

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: Note the PR URL**

The `gh pr create` command will print the URL. Save it for the verification step.

---

## Task 12: Verification on the deployment host

> **Run on spark-1822.** All steps here. The PR can stay open while verification runs — only merge after all 11 checks pass.

- [ ] **Step 1: Pull the branch onto the host**

```bash
ssh spark-1822
cd /opt/sparky    # adjust if the deployed path differs
git fetch origin
git checkout llama-cpp-router-mode
```

- [ ] **Step 2: Generate the API key**

```bash
cd llama-cpp
if ! grep -q '^LLAMA_API_KEY=.\+' .env 2>/dev/null; then
    echo "LLAMA_API_KEY=$(openssl rand -hex 32)" >> .env
fi
grep '^LLAMA_API_KEY=' .env
```

Expected: a non-empty 64-hex-char key.

- [ ] **Step 3: Verify the image has router-mode flags** *(re-runs Task 1 verification on this host)*

```bash
docker run --rm "ghcr.io/ggml-org/llama.cpp:$(grep '^LLAMACPP_TAG=' .env | cut -d= -f2)" \
    /app/llama-server --help \
    | grep -E '(--models-dir|--models-max|--models-preset|--api-key)' \
    | wc -l
```

Expected: `4`.

- [ ] **Step 4: Build the symlink farm**

```bash
docker compose -f /opt/open-webui/docker-compose.yml stop ollama   # free GPU
make hf-sync
```

Expected: existing env-file reconciliation runs as before, then a `# router artifacts` block prints `+ symlink ...` lines for every GGUF in the HF cache, then a summary line.

- [ ] **Step 5: Inspect the symlink farm**

```bash
ls -la /opt/hf/.cache/llama-cpp-models/
ls -L /opt/hf/.cache/llama-cpp-models/ 2>&1 | head -10
cat /opt/hf/.cache/llama-cpp-models/config.ini
```

Expected: one `*.gguf` symlink per cached GGUF + `config.ini` + `config.ini.orphans`. `ls -L` will show "broken" links — expected (targets resolve in-container only). `config.ini` has one `[section]` per first-part GGUF with `model =`, `alias =`, `ctx-size =`, `n-gpu-layers =`.

- [ ] **Step 6: Start the container in router mode**

```bash
make up
docker compose logs -f llama-cpp 2>&1 | head -30
```

Expected: log shows `launching: llama-server --host 0.0.0.0 --port 8080 --models-dir /models --models-max 2 --models-preset /models/config.ini --api-key <redacted>`. Healthcheck transitions to healthy within `start_period`.

- [ ] **Step 7: `/v1/models` lists everything (verification 4)**

```bash
make models
```

Expected: a JSON list with one entry per GGUF symlink, all with status `unloaded`.

- [ ] **Step 8: On-demand load works (verification 5)**

```bash
KEY=$(grep '^LLAMA_API_KEY=' .env | cut -d= -f2)
curl -fsS -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
    http://127.0.0.1:8080/v1/chat/completions \
    -d '{"model":"gpt-oss-safeguard-120b","messages":[{"role":"user","content":"say hi"}]}' \
    | jq -r '.choices[0].message.content'
```

Expected: first request loads the model (visible in `docker logs`), takes minutes for the 120b cold-load, returns a completion. Watch logs for the load progress.

- [ ] **Step 9: LRU eviction (verification 5 continued)**

Trigger a second model that, combined with the first, exceeds `MODELS_MAX=2`. With only the 120b loaded so far, request a smaller model:

```bash
# Find a smaller model in /v1/models output
SMALL_MODEL=$(curl -fsS -H "Authorization: Bearer $KEY" http://127.0.0.1:8080/v1/models | jq -r '.data[] | select(.id != "gpt-oss-safeguard-120b") | .id' | head -1)
echo "$SMALL_MODEL"

curl -fsS -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
    http://127.0.0.1:8080/v1/chat/completions \
    -d "{\"model\":\"$SMALL_MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}" | jq .
```

Expected: loads the second model (no eviction at MODELS_MAX=2 yet). Load a third — eviction visible in logs.

- [ ] **Step 10: Auth enforced (verification 11)**

```bash
curl -i http://127.0.0.1:8080/v1/models 2>&1 | head -5
```

Expected: HTTP/1.1 `401 Unauthorized` (no `Authorization` header).

```bash
curl -fsS -H "Authorization: Bearer $KEY" http://127.0.0.1:8080/v1/models | jq -r '.data | length'
```

Expected: a number > 0.

- [ ] **Step 11: Classic mode still works (verification 6)**

```bash
docker compose down
make up ENV=gpt-oss-safeguard-120b-hf
docker compose logs -f llama-cpp 2>&1 | head -20
```

Expected: log shows `--model ${MODEL_PATH}` (not `--models-dir`); container loads the single 120b at startup as today.

```bash
docker compose down
make up    # back to router mode
```

- [ ] **Step 12: OpenWebUI dropdown (verification 7) — if wired**

Open <https://llama.spark-1822.local> in a browser (or OpenWebUI's chat page). The model dropdown should list every GGUF; selecting one and chatting should route correctly. Confirm the OpenWebUI config has the `LLAMA_API_KEY` set in its outbound auth.

- [ ] **Step 13: Idempotency (verification 8)**

```bash
make hf-sync > /tmp/sync1.log
make hf-sync > /tmp/sync2.log
diff <(grep 'router summary' /tmp/sync1.log) <(grep 'router summary' /tmp/sync2.log)
md5sum /opt/hf/.cache/llama-cpp-models/config.ini
make hf-sync
md5sum /opt/hf/.cache/llama-cpp-models/config.ini
```

Expected: second `router summary` shows `0 created/updated, N unchanged, 0 orphaned`. Both md5sums identical.

- [ ] **Step 14: Preserve hand-edits (verification 9)**

```bash
# Pick any section, change ctx-size
sed -i.bak 's/^ctx-size = 8192$/ctx-size = 32768/' /opt/hf/.cache/llama-cpp-models/config.ini
make hf-sync
grep -A1 '^\[' /opt/hf/.cache/llama-cpp-models/config.ini | grep ctx-size
```

Expected: `ctx-size = 32768` survives. Reset with `mv /opt/hf/.cache/llama-cpp-models/config.ini.bak /opt/hf/.cache/llama-cpp-models/config.ini` if you want to leave the host clean.

- [ ] **Step 15: Atomic writes (verification 10)**

In one terminal:

```bash
while true; do curl -fsS -H "Authorization: Bearer $KEY" http://127.0.0.1:8080/v1/models > /dev/null || echo "FAIL at $(date)"; done
```

In another:

```bash
for i in $(seq 1 10); do make hf-sync; done
```

Expected: no `FAIL` lines in the first terminal during the 10 sync runs.

- [ ] **Step 16: Restore Ollama if you stopped it for this**

```bash
docker compose -f /opt/open-webui/docker-compose.yml up -d ollama
```

…only if you intend to swap back to Ollama. If you're staying on llama-cpp, leave it stopped.

- [ ] **Step 17: Approve and merge the PR**

If all 11 checks (steps 3, 5–10, 13–15, + 11 + 12 if wired) pass, merge the PR. Watch for one week of normal usage before considering the deprecation PR.

---

## Self-review checks (engineer)

Before declaring done:

1. **Spec coverage:** Every section of the spec maps to a task here.
   - Goal / Background → context for all tasks.
   - Decisions: coexist → Task 4 (entrypoint coexistence), Task 5 (loose `make up`); per-model knobs → Task 6 (config.ini regen) + Task 7 (sync wiring); hf-sync lifecycle → Task 8 (router pass).
   - Architecture (symlink farm + container-side paths) → Task 7.
   - Detailed design / entrypoint → Task 4.
   - Detailed design / docker-compose → Task 2.
   - Detailed design / .env.example → Task 3.
   - Detailed design / symlink farm → Task 7.
   - Detailed design / config.ini → Task 6.
   - Detailed design / Makefile → Tasks 5 + 8.
   - Image tag bump → Task 1.
   - Resolved choices (model ID hybrid, LLAMA_API_KEY, MODELS_MAX=2) → Tasks 2, 3, 4, 5, 6, 9.
   - Deprecation path → out of scope here (next PR).
   - Verification plan → Task 12 (mapped 1:1).
2. **No placeholders:** check.
3. **Type consistency:** function names (`load`, `write_atomic`, `main`) used consistently; env-var names (`LLAMA_API_KEY`, `SYMLINK_FARM_HOST`, `MODELS_MAX`) match across compose, .env.example, entrypoint, Makefile, README; section-name derivation regex appears once in `sync-router.sh` and is referenced by spec.
