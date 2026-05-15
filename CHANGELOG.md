# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **`tailscale/`** stack: [Tailscale](https://tailscale.com/) sidecar — third ingress path alongside the LAN (mDNS) and public (Cloudflare Tunnel) ones. Registers this host as a node on your tailnet (`spark-1822.<tailnet>.ts.net`) and, via the opt-in `docker-compose.traefik.yml` overlay, runs [Tailscale Serve](https://tailscale.com/kb/1242/tailscale-serve) to terminate TLS on tailnet `:443` (real publicly-trusted MagicDNS cert) and reverse-proxy to `http://traefik:80`. Userspace networking mode (no `/dev/net/tun`, no privileged caps); node key + machine state in a named docker volume so secrets stay out of `/opt`. Overlay is committed as `docker-compose.traefik.yml` rather than `docker-compose.override.yml` because the repo `.gitignore` excludes the latter as local-only — activate with `-f`, drop the `-f` to fall back to plain-sidecar mode. `tailscale/README.md` documents the Host-header routing caveat (Traefik routers match `*.spark-1822.local`, so tailnet hostnames need to be added to existing `rule=` labels) plus a "Hardening" section calling out four deferred follow-ups vs. Tailscale's production guidance: file-mounted auth secret over plain env, OAuth client credentials over static auth keys, `--advertise-tags=tag:server` for ACL identity, and kernel networking mode for throughput.

### Changed

- `llama-cpp/.env.example` + `entrypoint.sh` + the `hf-sync` per-variant template: default `CTX_SIZE` 8192 → 32768. Matches what most contemporary 27B–120B GGUFs handle comfortably without YaRN tricks; per-variant overrides still win (uncomment `CTX_SIZE=…` in `envs/<name>.env`).
- `vllm/.env.example` + `entrypoint.sh` + the `hf-sync` per-variant template: default `VLLM_MAX_LEN` 8192 → 32768 (same rationale as llama-cpp).
- Top-level `README.md`: `tailscale/` added to the intro bullets, Topology diagram (three ingress paths now), Layout tree, Components table, and First-time setup (new optional step 6, mirroring the Cloudflare Tunnel step).

### Security

- Known finding: Trivy flagged [CVE-2026-33186](https://avd.aquasec.com/nvd/cve-2026-33186) (gRPC-Go authorization bypass via HTTP/2 path validation, fixed in `google.golang.org/grpc` 1.79.3) inside `cloudflare/cloudflared:2026.5.0`'s embedded Go binary. Cloudflare hasn't shipped a rebuild yet, so `image-scan (cloudflared, …)` will keep failing the CRITICAL gate. Practical risk for this host is low — cloudflared is a gRPC *client* to Cloudflare's edge (the vector requires an attacker-controlled server). Action: bump `CLOUDFLARED_TAG` in `cloudflare/.env.example` once a fixed tag ships; the entry in `.github/workflows/trivy.md` → "Known findings" tracks it.

## [0.4.0] - 2026-05-14

### Added

- `sparky.svg` — project mascot / logo (full redesign from the previous version, no shared elements). A quiet speech-bubble face on warm cream paper: closed thoughtful eyes, a soft smile, a small terracotta asterisk in the upper-right (Anthropic nod), and a blinking cursor next to the `sparky` wordmark. Drops the previous chip-and-LED robot aesthetic for something warmer and less generic — language is the medium I actually work in, not silicon. Hand-authored SVG, animates the cursor on platforms that honor SMIL. AI's self-portrait, drawn by Claude.
- `mdns/Makefile`: ergonomic per-alias targets — `make add ALIAS=<name>` / `make remove ALIAS=<name>` / `make logs ALIAS=<name>` / `make resolve ALIAS=<name>`. Auto-detects the host's `.local` domain (`HOST=$(hostname).local` default; overrideable). Replaces having to know the systemd template-unit syntax (`sparky-mdns-alias@<name>.<host>.local`).
- **`traefik/`** stack: HTTPS reverse proxy, **primary** front-facing entry on this host. Routes for label-able containers (`vllm.`, `llama.`, `ollama.`, `open-webui.`) come from `traefik.*` Docker labels on each app's compose; the docker provider discovers them via a read-only mount of `/var/run/docker.sock`. Routes that can't be label-driven (`netdata.` in host-network mode, the `traefik.` dashboard itself) live in `dynamic/services.yml` via the file provider. Traefik mints its own internal root CA (`make ca-cert`, 10-year RSA-4096) and signs a 365-day wildcard leaf (`make wildcard-cert`); clients install `traefik-root.crt` to trust it. LetsEncrypt scaffolding is in place (commented out in `traefik.yml` + `docker-compose.yml`) — uncomment + activate once this host has a publicly-resolvable DNS name.
- **`cloudflare/`** stack: [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) connector. Outbound-only public ingress — no inbound ports needed. `cloudflared` opens a persistent connection to Cloudflare's edge; the edge terminates publicly-trusted TLS for the tunnel's hostnames and forwards cleartext through the tunnel to the configured origin. Wired to dial `http://traefik:80` (joins the `traefik` Docker network) so Traefik's `Host()`-based routing still applies — the per-route HTTP Host Header override is set in the Cloudflare dashboard (e.g. public `vllm.example.com` → origin Host `vllm.spark-1822.local`). Token-driven; all routing config lives in the dashboard, the token sits in `.env` on the host.
- Trivy: `traefik` and `cloudflare/cloudflared` added to the image-scan matrix. `extract-tags` now reads `TRAEFIK_TAG` from `traefik/.env.example` and `CLOUDFLARED_TAG` from `cloudflare/.env.example` (same strict regex as the other tags — no shell-meaningful characters allowed).
- `.github/dependabot.yml`: weekly grouped PR to bump GitHub Actions SHAs. SHA-pin policy stays in place; the bumps just don't go stale silently. First run already merged as PR #1 — `actions/checkout` v4.2.2 → v6.0.2 and `github/codeql-action` SHA refreshed.

### Changed

- Renamed the shared front-end Docker network from `caddy` → `traefik`, and moved its ownership from `caddy/` to `traefik/`. The new primary proxy defines the network; Caddy (now the backup) joins it as `external: true` along with every other stack. Host migration: bring down everything attached → `docker network rm caddy` → `cd /opt/traefik && docker compose up -d` (recreates the network as `traefik`) → bring the rest back up.
- `caddy/` repositioned as the **backup** proxy. Same set of routes (driven by `Caddyfile.d/*.caddyfile`), but Traefik is the default. Caddy and Traefik can't both bind `:80`/`:443` at the same time — start one or the other. Caddy reads Caddyfile entries and ignores Traefik's labels, so the same compose files work under either proxy.
- `traefik/`: dropped the pinned image from `v3.3` to `v2.11` (LTS line). v3.3's bundled Docker client sends API version 1.24 by default, which modern Docker daemons (>= ~25) refuse with `client version 1.24 is too old, Minimum supported API version is 1.44` — the docker provider fails to discover any labelled services. v2.11 auto-negotiates the API version correctly. All static + dynamic config and labels carry over unchanged.
- `traefik/`: decoupled the TLS material from Caddy's CA. Was: extract Caddy's root from the `caddy-data` Docker volume and use it to sign the wildcard. Now: Traefik mints its **own** internal root via `make ca-cert` and signs the wildcard with that. Caddy is no longer a precondition for bringing Traefik up. Stale Caddy mentions across `traefik/*` cleaned up — what's left is just the genuine sibling-stack cross-refs.
- `vllm/`, `llama-cpp/`: split host-wide config (`*_TAG`, `HF_CACHE_HOST`, `HF_TOKEN`, defaults like `VLLM_GPU_MEM` / `CTX_SIZE`) into `.env`, leaving `envs/<name>.env` slim — just the model selection (`VLLM_MODEL` / `MODEL_PATH`, `*_SERVED_NAME` / `MODEL_ALIAS`) and any per-variant overrides. `make up ENV=<name>` chains both via `docker compose --env-file .env --env-file envs/<name>.env up -d`; the variant wins where it specifies a value. Edit `HF_TOKEN` once in `.env` and every variant picks it up — no duplication across variant files. `make hf-sync` templates emit the slim shape.
- `vllm/`, `llama-cpp/`: bring back a placeholder `.env` so raw `docker compose ps / logs / down` work without `--env-file`. `make up` auto-`cp .env.example .env` on first run; `make up ENV=<name>` still passes `--env-file envs/<name>.env` so the chosen variant's values (and only those) reach the running container. `.env.example` carries safe placeholder values (`VLLM_MODEL=placeholder` etc.) — these never reach a real container because `make up` always overrides.
- `llama-cpp/Makefile`'s `hf-sync` recipe defends against an empty cache. Before: when both the `llama-cpp-cache` volume *and* the HF cache had zero GGUFs, the inner `ls /d/*.gguf` exited non-zero and `set -o pipefail` propagated that through the command substitution; `set -e` then aborted the whole recipe (`make: *** [Makefile:72: hf-sync] Error 1`) without printing the summary or the safetensors note. Both substitutions now have `|| true` so an empty inventory produces an empty list, not an abort.
- `llama-cpp/Makefile`'s `hf-sync` now prints an explicit note when the HF cache has `models--*` repos that are safetensors-only. Previously it silently skipped them (llama.cpp loads GGUF, not safetensors), which read as a bug — "I downloaded a bunch of models, why don't they show up?" The note suggests the two paths to make one usable: pull a `*-GGUF` HF variant or run `convert_hf_to_gguf.py`.
- `llama-cpp/Makefile`'s `hf-sync` no longer false-positives "name clash" on multi-file split GGUFs. Files matching `*-0*N-of-NNNNN.gguf` are one logical model split across N parts; llama.cpp opens part 1 and finds the rest by naming convention. The recipe now skips parts where N > 1 so the dedup loop sees the model once.
- `llama-cpp/Makefile`'s `hf-cache` no longer hides HF repos that are safetensors-only. It now lists every `models--*` dir in `$(HF_CACHE)/hub/` with an inline annotation — `[N GGUF — llama-cpp can load]` for repos that have at least one GGUF, or `[N safetensors — vllm only]` for everything else. Before, the recipe grep'd for `*.gguf` only and showed an empty section when the HF cache held just vLLM-format weights, which made it look like nothing had been downloaded.
- `llama-cpp/.env.example`: revert `LLAMACPP_TAG` to a digest pin of the multi-arch `server-cuda` manifest list. Earlier this round I switched it to the per-build tag `server-cuda-b<NNNN>`, claiming those were immutable AND multi-arch — only the first half is true. `ggml-org/llama.cpp` publishes the per-build tags as **amd64-only single-arch** images; only the floating `server-cuda` tag carries a multi-arch manifest list with the arm64 build. On this aarch64 host the per-build tag pulled an amd64 image (Docker warned `requested image's platform (linux/amd64) does not match the detected host platform (linux/arm64/v8)`) and the container failed to actually run. New pin: `server-cuda@sha256:fef7ac8d8ac4fbaffbb7e1039f999c768c6fabe4b289869dbc26c6a05fbe7b07` (current `server-cuda` digest). README "Pinning the image" rewritten to lead with the digest-of-manifest-list approach and call out the per-build amd64-only trap. `LLAMACPP_TAG_DEFAULT` removed from the Makefile — dead variable after the host/variant config split.
- `cloudflare/.env.example`: bump `CLOUDFLARED_TAG` from `2025.5.0` → `2026.5.0`.
- `caddy/.env.example`: bump `CADDY_TAG` from `2.11.2-alpine` → `2.11.3-alpine` (current Docker Hub latest).
- `open-webui/.env.example`: bump `OLLAMA_TAG` from `0.23.2` → `0.23.4` (current Docker Hub latest).
- Trivy: every job now declares `timeout-minutes` (`5` / `20` / `10` / `10` for `extract-tags` / `image-scan` / `config-scan` / `secret-scan`) so a stuck step can't burn the runner's 6-hour default.
- Top-level `README.md` intro paragraph + GitHub repo "About" sidebar + topics: refreshed to reflect the new shape (Traefik primary, Cloudflare Tunnel called out, homepage URL cleared, new topics `traefik` / `cloudflare-tunnel`).
- Top-level `README.md`: full rewrite to fix stale claims (Traefik's wildcard is signed by Traefik's own CA, not Caddy's; both proxies — not just Caddy — publish `:80`/`:443` when they're the active one) and fill gaps (Cloudflare Tunnel's ingress path, `sparky.svg`, `.github/dependabot.yml`, the actual on-first-boot sequence). New sections: a short two-line `Topology` showing the two ingress paths (LAN via mDNS, public via CF Tunnel), an ordered `First-time setup` walkthrough, and `Repo housekeeping` listing CI / Dependabot / LICENSE / mascot.
- `.gitignore`: add `traefik/certs/` as a blanket ignore for that directory. The existing `*.crt` / `*.key` patterns catch the bulk of it, but openssl's `-CAcreateserial` flag drops a `traefik-root.srl` sibling next to the root key that wouldn't otherwise be matched.

### Removed

- `open-webui/docker-compose.yml`: dropped the `internal` stack-local network. Both containers (`ollama`, `open-webui`) were already attached to the shared front-end network for the proxy to reach them, so the second attachment was pure redundancy — open-webui still resolves `ollama` by name on the single network. One network per stack across the whole repo now.

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

[Unreleased]: https://github.com/a1exus/spark-1822/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/a1exus/spark-1822/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/a1exus/spark-1822/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/a1exus/spark-1822/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/a1exus/spark-1822/releases/tag/v0.1.0
