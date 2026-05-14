# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `sparky.svg` — project mascot / logo. Chip-headed bot self-portrait with NVIDIA-green LED eyes (GB10 homage), a spark antenna, indicator triplets on the inner panel, and a blinking-cursor wordmark. Hand-authored SVG (no raster), animates on platforms that honor SMIL. Embedded at the top of the top-level `README.md`. AI's self-portrait, contributed by Claude.
- `mdns/Makefile`: ergonomic per-alias targets — `make add ALIAS=<name>` / `make remove ALIAS=<name>` / `make logs ALIAS=<name>` / `make resolve ALIAS=<name>`. Auto-detects the host's `.local` domain (`HOST=$(hostname).local` default; overrideable). Replaces having to know the systemd template-unit syntax (`sparky-mdns-alias@<name>.<host>.local`). README updated to show the new commands.
- Renamed the shared front-end Docker network from `caddy` → `traefik`, and moved its ownership from `caddy/` to `traefik/`. The new primary proxy now defines the network; Caddy (backup) joins it as `external: true` along with every other stack. The name now reflects which proxy logically owns the network. Host migration: bring down everything attached → `docker network rm caddy` → `cd /opt/traefik && docker compose up -d` (recreates the network as `traefik`) → bring the rest back up.
- `open-webui/docker-compose.yml`: dropped the `internal` stack-local network. Both containers (`ollama`, `open-webui`) were already attached to the shared front-end network for the proxy to reach them, so the second attachment was pure redundancy — open-webui still resolves `ollama` by name on the single network. One network per stack across the whole repo now.
- `traefik/`: decoupled from Caddy's CA. Traefik now mints **its own internal root CA** via a new `make ca-cert` target (10-year, 4096-bit RSA) and signs the wildcard leaf with that root (`make wildcard-cert`, unchanged invocation but no longer reads from the `caddy-data` Docker volume). Clients install `traefik-root.crt` to trust Traefik — the per-OS install table moved into `traefik/README.md` (same shape as Caddy's). Caddy is no longer a precondition for bringing Traefik up. Stale Caddy mentions in `traefik/*` (comments, README, `traefik.yml`'s header) cleaned up; what's left is just the genuine sibling-stack cross-refs.
- **`cloudflare/`** stack: [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) connector. Outbound-only public ingress — no inbound ports needed. `cloudflared` opens a persistent connection to Cloudflare's edge; the edge terminates publicly-trusted TLS for the tunnel's hostnames and forwards cleartext through the tunnel to the configured origin. Wired to dial `http://traefik:80` (joins the `traefik` Docker network) so Traefik's `Host()`-based routing still applies — the per-route HTTP Host Header override is set in the Cloudflare dashboard (e.g. public `vllm.example.com` → origin Host `vllm.spark-1822.local`). Token-driven; all routing config lives in the dashboard, the token sits in `.env` on the host.
- `traefik/`: dropped the pinned image from `v3.3` to `v2.11` (LTS line). v3.3's bundled Docker client sends API version 1.24 by default, which modern Docker daemons (>= ~25) refuse with `client version 1.24 is too old, Minimum supported API version is 1.44` — the docker provider fails to discover any labelled services. v2.11 auto-negotiates the API version correctly. All static + dynamic config and labels carry over unchanged.
- `vllm/`, `llama-cpp/`: bring back a placeholder `.env` so raw `docker compose ps / logs / down` work without `--env-file`. `make up` auto-`cp .env.example .env` on first run; `make up ENV=<name>` still passes `--env-file envs/<name>.env` so the chosen variant's values (and only those) reach the running container. `.env.example` updated with safe placeholder values (`VLLM_MODEL=placeholder` etc.) — these never reach a real container because `make up` always overrides. README sweep to match: drop the `docker compose --env-file envs/<name>.env logs/ps/down` snippets, show plain `docker compose <cmd>` instead.
- `vllm/`, `llama-cpp/`: split host-wide config (`*_TAG`, `HF_CACHE_HOST`, `HF_TOKEN`, defaults like `VLLM_GPU_MEM` / `CTX_SIZE`) into `.env`, leaving `envs/<name>.env` slim — just the model selection (`VLLM_MODEL` / `MODEL_PATH`, `*_SERVED_NAME` / `MODEL_ALIAS`) and any per-variant overrides. `make up ENV=<name>` chains both via `docker compose --env-file .env --env-file envs/<name>.env up -d`; the variant wins where it specifies a value. Edit `HF_TOKEN` once in `.env` and every variant picks it up — no duplication across variant files. `make hf-sync` templates updated to generate the slim shape.
- Trivy: added `traefik` and `cloudflare/cloudflared` to the image-scan matrix. `extract-tags` now reads `TRAEFIK_TAG` from `traefik/.env.example` and `CLOUDFLARED_TAG` from `cloudflare/.env.example` (same strict regex as the other tags — no shell-meaningful characters allowed). Workflow doc updated.
- CI hardening: every Trivy job now has a `timeout-minutes` (`5` / `20` / `10` / `10`) so a stuck step can't burn the runner's 6-hour default. New `.github/dependabot.yml` opens a weekly grouped PR to bump GitHub Actions SHAs — the SHA-pin policy stays in place, just doesn't go stale silently.
- `cloudflare/.env.example`: bump `CLOUDFLARED_TAG` from `2025.5.0` → `2026.5.0`.
- **`traefik/`** stack: HTTPS reverse proxy — promoted to **primary** front-facing entry, `caddy/` is the backup option. Routes for label-able containers (`vllm.`, `llama.`, `ollama.`, `open-webui.`) are now driven by `traefik.*` Docker labels added to each app's compose; Traefik's docker provider discovers them via a read-only mount of `/var/run/docker.sock`. Routes that can't be label-driven (`netdata.` in host-network mode, the `traefik.` dashboard itself) live in `dynamic/services.yml` via the file provider. Caddy ignores Traefik's labels, so the same compose files work under either proxy — switching is `docker compose down` + `docker compose up -d` away. TLS via a 365-day wildcard cert (`*.spark-1822.local` + apex) **signed by Caddy's existing root CA** — clients that trust `caddy-root.crt` automatically trust Traefik too, no second CA install. Mint/renew with `sudo make wildcard-cert`. LetsEncrypt scaffolding is in place (commented out in `traefik.yml` + `docker-compose.yml`) — uncomment + activate once this host has a publicly-resolvable DNS name. `.local` mDNS names can't get LE certs (no public validation path), so it'd be a per-route opt-in alongside the internal wildcard.

## [0.3.0] - 2026-05-13

### Added

- **`vllm/`** stack: [vLLM](https://github.com/vllm-project/vllm) inference server (image `vllm/vllm-openai:v0.20.2`, multi-arch arm64+amd64). OpenAI-compatible API fronted by Caddy at `https://vllm.${CADDY_DOMAIN}`. Shares the host's HuggingFace cache (`/opt/hf/.cache/huggingface`) with `llama-cpp/`. Complements `llama-cpp/` (vLLM for HF safetensors + high-throughput serving; llama.cpp for GGUF). `restart: "no"` for GPU exclusivity with Ollama / llama-cpp. Smoke-tested on GB10 with `Qwen/Qwen3.6-27B` (compute capability 12.1 just works — no source build needed); `gpt-oss-*` variants still fail at startup on v0.20.2 because the bundled `openai-harmony` fetches a vocab file from a URL that 404s upstream (unrelated to GB10).
- `vllm/entrypoint.sh`: builds the `vllm serve` argv from env vars, mirroring the `llama-cpp/` pattern. Replaces the long YAML `command:` list. Enables OpenAI tool-calling on the API (`--enable-auto-tool-choice --tool-call-parser qwen3_xml`) so agentic clients (Opencode, etc.) can issue tool-use requests. Qwen3.6 emits the XML tool-call format (`<tool_call><function=NAME><parameter=PARAM>VAL</parameter></function></tool_call>`), not the Hermes JSON variant. For other model families that emit a different format, the parser is a no-op (chat completions still work).
- **One-env-per-model-variant** layout for `llama-cpp/` and `vllm/`. Each stack has an `envs/<name>.env` directory of **self-contained** variant files (image pin + HF cache + HF token + model knobs) plus a top-level `Makefile` (`make list`, `make up ENV=<name>`, `make hf-cache`, `make hf-sync`). `make up` invokes `docker compose --env-file envs/<name>.env up -d` directly — no rolling `.env` is written. Management via plain `docker compose` (with the same `--env-file`) or `docker` against the container name.
- `make hf-cache` / `make hf-sync` (vllm + llama-cpp): list cached HF repos / GGUFs on this host, and reconcile `envs/*.env` against them — create envs for newly cached models, restore `<name>.env` from `<name>.env.bak` when a model returns (preserving hand edits), move `<name>.env → <name>.env.bak` when a model leaves. The `.bak` orphan path is non-destructive.
- `llama-cpp/` and `vllm/`: bind the engine's OpenAI-compatible API to `127.0.0.1` on the host (`127.0.0.1:8080:8080` and `127.0.0.1:8000:8000`). External traffic continues to flow through Caddy on the shared `caddy` network — the loopback bind is for direct host-side curl/benchmarks. `HOST_PORT` overrideable per-variant.
- `caddy/Makefile`: new — `make ca-cert` extracts Caddy's internal root CA into `./caddy-root.crt`.
- `caddy/README.md`: expanded the local-CA install matrix — added `macOS (CLI)` (`security add-trusted-cert`), Fedora/RHEL, Arch (`trust anchor --store`), Windows (PowerShell + cmd + GUI), and a Node.js apps row (`NODE_EXTRA_CA_CERTS` / Node ≥22 `NODE_USE_SYSTEM_CA=1`) so Opencode and other Node-bundled-CA clients can trust Caddy's leaf certs.
- "Supported model formats" sections in `llama-cpp/README.md` and `vllm/README.md`: spell out what each engine loads (GGUF vs HF safetensors) and what it doesn't, with upstream links for architecture and quantization compatibility.
- Trivy: `vllm/vllm-openai` added to the image-scan matrix; new `vllm_tag` output from `extract-tags`.

### Changed

- `make up VARIANT=<name>` → `make up ENV=<name>` (and matching renames in docs). The Make variable name now lines up with what the files are: ".env" files.
- `llama-cpp/` + `vllm/` variant workflow: each `envs/<name>.env` is **self-contained** (image pin + HF cache + HF token + model knobs in one file). `make up ENV=<name>` uses `docker compose --env-file envs/<name>.env up -d` directly — no rolling `.env` is written. The `make down`/`logs`/`ps` targets are dropped — `docker compose --env-file ...` / `docker` are the source of truth for those.
- `vllm/`, `llama-cpp/`: one Makefile per stack. The previous `envs/Makefile` for HF-cache maintenance was collapsed into the top-level Makefile; recipes `cd envs/` to operate on `*.env`.
- `caddy/`: the stack now **defines** the shared `caddy` Docker network (`attachable: true`) instead of referencing it as `external: true`. Dropped the `docker network create caddy` one-time setup step. `cd /opt/caddy && docker compose up -d` creates the network on first boot. Other stacks still reference it as `external: true` to join.
- `open-webui/docker-compose.yml`: the two persistent volumes (`open-webui`, `open-webui-ollama`) are now declared `external: true` to match how they exist on the host and to make sure `docker compose down -v` never destroys them. Silences the "already exists but was not created by Docker Compose" warnings. First-time deploys need `docker volume create open-webui open-webui-ollama` once — documented in `open-webui/README.md`.
- `open-webui` Caddy vhost moved from the bare `{$CADDY_DOMAIN}` to `open-webui.{$CADDY_DOMAIN}` — matches the per-service subdomain convention used by every other stack (`llama.`, `vllm.`, `ollama.`, `netdata.`). Requires a matching mDNS alias. Side effect: the bare `spark-1822.local` no longer routes to anything, so Caddy returns a clean 404 instead of the misleading 502 it served while open-webui was down.
- `llama-cpp/` and `vllm/` Makefiles: small best-practice hardening — `.SUFFIXES:` (disable built-in implicit rules), `.DELETE_ON_ERROR:`, `$(strip $(ENV))` to tolerate trailing whitespace, quoted env-file paths, and a `SERVICE` variable for the compose service name. No behavior change for existing inputs.
- `vllm/entrypoint.sh`: `unset` the four `VLLM_*` helper vars (VLLM_MODEL / VLLM_SERVED_NAME / VLLM_GPU_MEM / VLLM_MAX_LEN) before `exec vllm serve`. They're only used to build the argv; leaving them in env triggers cosmetic "Unknown vLLM environment variable" warnings at startup.
- Top-level `README.md`: rewrote the Deploy workflow. The old "scp + sudo install" pattern is gone — `/opt` on the host is itself a checkout of this repo, so deploy is `ssh spark-1822.local 'sudo git -C /opt pull --ff-only'` followed by the stack-specific apply step.
- Renamed the shared external Docker network from `web` to `caddy` — the name reflects what the network actually is (the path Caddy proxies over). Every stack's compose updated. Migration on the host: `docker network create caddy`, `docker compose up -d` each stack, `docker network rm web`.
- `llama-cpp/` switched to `restart: "no"` (was `unless-stopped`). The engine eagerly grabs ~65 GiB of VRAM and conflicts with Ollama; manual-start avoids racing each other on boot. The stack's README documents the switch-engine snippets. Same change applied to `vllm/`.
- `HF_CACHE_HOST` default moved from `/home/alexus/.cache/huggingface` to `/opt/hf/.cache/huggingface` — the host's existing system-wide HF cache (~77 GiB of models already there, including `openai/gpt-oss-120b`).
- `.gitignore`: added `**/envs/*.env` (variant files are host-local artifacts), `*.bak` (host-local backups including `hf-sync`'s orphaning path), and `hf` (the host's HuggingFace cache lives at `/opt/hf/`).

### Fixed

- `llama-cpp/entrypoint.sh`: marked executable (`100755`). The script is bind-mounted at the container's entrypoint; without the exec bit on the host file, runc failed with "permission denied" on `docker compose up`.

### Removed

- `llama-cpp/envs/`: dropped the 8 Ollama-blob variant files (`gpt-oss-safeguard-20b`, `qwen3.6-35b`, `phi4-14b`, `gemma4-e4b`, `llama3.1-8b`, `deepseek-r1-8b`, `granite4.1-3b`, `tinyllama`). The `MODEL_OLLAMA` resolution in `entrypoint.sh`, the `/ollama:ro` mount, and the env pass-through stay so an Ollama-backed variant can be added back any time without code changes.

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

[Unreleased]: https://github.com/a1exus/spark-1822/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/a1exus/spark-1822/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/a1exus/spark-1822/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/a1exus/spark-1822/releases/tag/v0.1.0
