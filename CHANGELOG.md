# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- `make up VARIANT=<name>` → `make up ENV=<name>` (and matching renames in docs / `envs/Makefile sync` templates). The Make variable name now lines up with what the files are: ".env" files.
- `.gitignore`: added `**/envs/*.env` so variant files become host-local artifacts. The committed templates are now just `envs/Makefile` and `envs/README.md`. Populate locally with `make sync` inside `envs/` (read-only against the remote; never downloads).
- `.gitignore`: added `hf` to the vendor/host-shipped block (the host's HuggingFace cache lives at `/opt/hf/` and shouldn't end up in this repo if anyone mirrors it locally).
- `llama-cpp/` + `vllm/` variant workflow: each `envs/<name>.env` is now **self-contained** (image pin + HF cache + HF token + model knobs in one file). `make up ENV=<name>` invokes `docker compose --env-file envs/<name>.env up -d` directly — no rolling `.env` is written. For management afterwards, pass the same `--env-file` to docker compose, or use plain `docker` against the container name. Drops the `make down`/`logs`/`ps` targets — `docker compose` / `docker` are the source of truth for those. `envs/Makefile sync` was updated to generate self-contained files.
- `llama-cpp/` and `vllm/` Makefiles: small best-practice hardening — `.SUFFIXES:` (disable built-in implicit rules), `.DELETE_ON_ERROR:`, `$(strip $(ENV))` to tolerate trailing whitespace, quoted env-file paths, and a `SERVICE` variable for the compose service name. No behavior change for existing inputs.

### Added

- "Supported model formats" sections in `llama-cpp/README.md` and `vllm/README.md`: spell out what each engine loads (GGUF vs HF safetensors) and what it doesn't, with upstream links for architecture and quantization compatibility.
- `vllm/envs/Makefile` and `llama-cpp/envs/Makefile`: `make list / remote / sync / stale` for keeping the local variant files aligned with what's already downloaded on `spark-1822.local`. Read-only against the remote; never overwrites; never downloads.
- **One-env-per-model-variant** layout for `llama-cpp/` and `vllm/`. Each stack now has an `envs/<name>.env` directory of **self-contained** variant files (image pin + HF cache + HF token + model knobs) plus a `Makefile` (`make list`, `make up ENV=<name>`). `make up` invokes `docker compose --env-file envs/<name>.env up -d` directly — no rolling `.env`. Management via plain `docker compose` (with the same `--env-file`) or `docker` against the container name.
- `llama-cpp/` and `vllm/`: bind the engine's OpenAI-compatible API to `127.0.0.1` on the host (`127.0.0.1:8080:8080` and `127.0.0.1:8000:8000`). External traffic continues to flow through Caddy on the shared `caddy` network — the loopback bind is for direct host-side curl/benchmarks. `HOST_PORT` overrideable per-variant.
- `llama-cpp/entrypoint.sh`: marked executable (`100755`). The script is bind-mounted at the container's entrypoint; without the exec bit on the host file, runc fails with "permission denied" on `docker compose up`.
- `open-webui` Caddy vhost moved from the bare `{$CADDY_DOMAIN}` to `open-webui.{$CADDY_DOMAIN}` — matches the per-service subdomain convention used by every other stack (`llama.`, `vllm.`, `ollama.`, `netdata.`). Requires a matching mDNS alias (`sudo systemctl enable --now 'sparky-mdns-alias@open-webui.spark-1822.local'`). Side effect: the bare `spark-1822.local` no longer routes to anything, so Caddy will return a clean 404 instead of the misleading 502 it served while open-webui was down.
- `llama-cpp/envs/`: HF-backed variants only — `gpt-oss-safeguard-120b-hf` (URL-pulled into `llama-cpp-cache`). HF-cache-backed variants can be added by pointing `MODEL_PATH` at a GGUF under `/root/.cache/huggingface/hub/.../`.
- `vllm/envs/`: variants track what's actually downloaded under `/opt/hf/.cache/huggingface/` on the host: `gpt-oss-120b`, `gpt-oss-20b`, `qwen3.5-27b-reasoning`, `qwen3.6-27b`.

### Removed

- `llama-cpp/envs/`: dropped the 8 Ollama-blob variant files (`gpt-oss-safeguard-20b`, `qwen3.6-35b`, `phi4-14b`, `gemma4-e4b`, `llama3.1-8b`, `deepseek-r1-8b`, `granite4.1-3b`, `tinyllama`). The `MODEL_OLLAMA` resolution in `entrypoint.sh`, the `/ollama:ro` mount, and the env pass-through stay so an Ollama-backed variant can be added back any time without code changes.
- **`vllm/`** stack (scaffolded; **not smoke-tested on GB10 yet**): [vLLM](https://github.com/vllm-project/vllm) inference server (image `vllm/vllm-openai:v0.20.2`, multi-arch arm64+amd64). OpenAI-compatible API fronted by Caddy at `https://vllm.${CADDY_DOMAIN}`. Shares the host's HuggingFace cache (`/opt/hf/.cache/huggingface`) with `llama-cpp/`. Complements `llama-cpp/` (vLLM for HF safetensors + high-throughput serving; llama.cpp for GGUF). `restart: "no"` for GPU exclusivity with Ollama / llama-cpp. Caveat: vLLM's published support matrix doesn't list compute capability 12.1 (GB10), so the first `docker compose up -d` may fail until upstream ships sm_120 kernels.
- Trivy: `vllm/vllm-openai` added to the image-scan matrix; new `vllm_tag` output from `extract-tags`.

### Changed

- Renamed the shared external Docker network from `web` to `caddy` — the name reflects what the network actually is (the path Caddy proxies over). Every stack's compose updated. Migration on the host: `docker network create caddy`, `docker compose up -d` each stack, `docker network rm web`.
- `llama-cpp/` switched to `restart: "no"` (was `unless-stopped`). The engine eagerly grabs ~65 GiB of VRAM and conflicts with Ollama; manual-start avoids racing each other on boot. The stack's README documents the switch-engine snippets. Same change applied to the (uncommitted) `vllm/` scaffold.
- `HF_CACHE_HOST` default moved from `/home/alexus/.cache/huggingface` to `/opt/hf/.cache/huggingface` — the host's existing system-wide HF cache (~77 GiB of models already there, including `openai/gpt-oss-120b`). `llama-cpp/` updated.

## [0.2.0] - 2026-05-12

### Added

- **`llama-cpp/`** stack: GPU-accelerated [llama.cpp](https://github.com/ggml-org/llama.cpp) server (image `ghcr.io/ggml-org/llama.cpp:server-cuda`, pinned by digest). aarch64+CUDA confirmed on GB10 (compute capability 12.1, 124 GiB VRAM). OpenAI-compatible API + web UI fronted by Caddy at `https://llama.${CADDY_DOMAIN}`. Default model is `gpt-oss-safeguard-120b` via HuggingFace auto-download — workaround for the Ollama pull bug (ollama/ollama#16121). New Caddy site block + mDNS alias.
- llama-cpp: read-only mounts of Ollama's blob store (`open-webui-ollama` external volume) and the host's HuggingFace CLI cache, plus a `MODEL_PATH` env var so `llama-server` can skip downloading and reuse any file from those caches.
- Direct Caddy-fronted access to the Ollama API at `https://ollama.${CADDY_DOMAIN}` (no auth, LAN-trust). The `ollama` container joins the shared `web` network in addition to `internal`. New `Caddyfile.d/ollama.caddyfile` + mDNS alias.
- `mdns/Makefile` with `install` / `uninstall` / `list` / `help` targets. Replaces the `install.sh` / `uninstall.sh` pair.
- `open-webui/README.md` and `.github/README.md` so each component documents itself.
- Dedicated `.github/workflows/trivy.md` with the full Trivy workflow doc; `.github/README.md` is now a thin workflow index.
- Trivy: relaxed `extract-tags` regex to allow `@:` so digest-pinned tags (`server-cuda@sha256:…`) are accepted; added `llama-cpp` to the image-scan matrix.

### Changed

- Slim top-level `README.md` to an overview + per-component links; per-stack details now live in each directory's `README.md`. Added a table-of-contents.
- Split `caddy/Caddyfile` into per-service files under `caddy/Caddyfile.d/<name>.caddyfile`, loaded via `import`. Adding a new app is now a single file drop + reload.
- `.gitignore`: added host-local `/opt` trees we don't manage in this repo (`containerd`, `MicronTechnology`, `nvidia`, `NVIDIA AI Workbench`).

### Removed

- HTTP basic auth in front of Netdata. The dashboard exposes read-only telemetry on a trusted LAN; one more password to manage was friction without meaningful security gain. Use Netdata Cloud (SSO/MFA) or an OAuth forward-auth proxy if you want real auth.

## [0.1.0] - 2026-05-12

### Added

- **open-webui** stack: Open WebUI + Ollama as two pinned containers, GPU reservation on `ollama` only, healthchecks, log rotation, `no-new-privileges`. Adapted from <https://build.nvidia.com/spark/open-webui/instructions> with split services, version-pinned images, and `.env`-managed config.
- **caddy** stack: HTTPS reverse proxy on `:80`/`:443` (+`:443/udp` for HTTP/3) with `tls internal` (Caddy local CA). Hostname is parameterized via `CADDY_DOMAIN`. Routes `${CADDY_DOMAIN}` → `open-webui` and `netdata.${CADDY_DOMAIN}` → Netdata with HTTP basic auth.
- **netdata** stack: real-time host + container observability with `network_mode: host` and `pid: host`, standard read-only bind mounts (`/proc`, `/sys`, `/`, `docker.sock`).
- **mdns** component: systemd template (`sparky-mdns-alias@.service`) that publishes subdomain mDNS aliases via `avahi-publish` so `netdata.spark-1822.local` (and any future `*.spark-1822.local`) resolves on the LAN.
- External shared Docker network `web`: only Caddy publishes host ports; every other service is reachable only through Caddy.
- **CI: Trivy** workflow (`.github/workflows/trivy.yml`): image CVE scans (HIGH+CRITICAL, fixed-only) for every pinned image, IaC config scan of the repo, secret scan. SARIF uploaded to Code Scanning. Pushes/PRs gate on any CRITICAL CVE or leaked secret; scheduled weekly runs are informational. Actions pinned by commit SHA.
- Top-level and per-stack READMEs (`README.md`, `caddy/README.md`, `mdns/README.md`, `netdata/README.md`).
- DGX Spark product link in the top-level README.

### Changed

- Image tags for every stack moved into the stack's `.env` (single source of truth, surfaced to CI via `.env.example`).
- Open WebUI: dropped the direct `0.0.0.0:8080` host publish; now reachable only via Caddy on HTTPS.
- `/opt/<stack>/` on the host is `root:root`; only `.env` is `root:docker 640` so the `docker`-group `alexus` user can read it (and run `docker compose` without sudo) while configs require sudo to edit.

### Security

- `WEBUI_SECRET_KEY` is required (compose refuses to start without it).
- Netdata fronted with Caddy HTTP basic auth (bcrypt hash stored in `caddy/.env`).
- `.gitignore` excludes `.env`, `*.crt`, `*.key`, and `docker-compose.override.yml`.
- All third-party GitHub Actions pinned by commit SHA.

[Unreleased]: https://github.com/a1exus/spark-1822/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/a1exus/spark-1822/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/a1exus/spark-1822/releases/tag/v0.1.0
