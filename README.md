# sparky

<p align="center">
  <img src="sparky.svg" alt="sparky" width="220" height="260">
</p>

Configuration for the [NVIDIA DGX Spark](https://amzn.to/47ZeWqZ) workstation `spark-1822` — a single-box, self-hosted LLM setup:

- **vLLM** and **llama.cpp** for inference (HF safetensors and GGUF respectively, both GPU-accelerated on the GB10).
- **Open WebUI + Ollama** for the chat UI.
- **Traefik** (primary, docker-label-driven) or **Caddy** (backup, Caddyfile-driven) as the HTTPS reverse proxy in front of everything — pick one at a time.
- **Cloudflare Tunnel** for outbound-only public ingress (no inbound ports on the host).
- **Tailscale** sidecar for tailnet-only ingress (peer-to-peer over WireGuard; no public DNS, no public ports).
- **Netdata** for real-time observability.
- **mDNS** helper publishing `<sub>.spark-1822.local` aliases on the LAN.
- **Trivy** + **Dependabot** keep the supply chain honest in CI.

## Topology

Three ingress paths into the same backends:

```
LAN client      ──(mDNS *.spark-1822.local)──>  traefik :80/:443  ──>  backend
public client   ──(DNS, Cloudflare edge)──>  cloudflared ──>  traefik :80  ──>  backend
tailnet client  ──(MagicDNS, WireGuard)──>  tailscale :443  ──>  traefik :80  ──>  backend
```

Backends (`vllm`, `llama-cpp`, `open-webui`, `ollama`, `netdata`) all sit on a single shared Docker network named `traefik` — defined by the `traefik/` stack, joined as `external: true` by everyone else. The active proxy and both tunnel/sidecar connectors each attach to the same network and dial container names directly.

TLS comes from four different roots: Traefik and Caddy each mint their own internal CA (clients install the corresponding `*-root.crt` once); Cloudflare provides publicly-trusted certs at its edge for the tunnel hostnames; Tailscale auto-provisions publicly-trusted MagicDNS certs for the tailnet hostname.

## Layout

```
.
├── traefik/       # HTTPS reverse proxy — primary (docker-label-driven)
├── caddy/         # HTTPS reverse proxy — backup (Caddyfile-driven)
├── cloudflare/    # Cloudflare Tunnel connector — public ingress
├── tailscale/     # Tailscale sidecar — tailnet ingress
├── vllm/          # vLLM inference server (HF safetensors)
├── llama-cpp/     # llama.cpp inference server (GGUF)
├── open-webui/    # Open WebUI + Ollama (chat UI)
├── netdata/       # Real-time observability
├── mdns/          # Host-side mDNS aliases helper
├── .github/       # CI: Trivy workflow + Dependabot config
├── sparky.svg     # Project logo (AI self-portrait)
├── CHANGELOG.md
├── LICENSE
└── README.md
```

Each stack has its own `README.md` — start there for deploy / configure / upgrade details.

## Components

| Stack | Role | URL on LAN |
|---|---|---|
| [`traefik/`](traefik/) | HTTPS reverse proxy (primary), docker-label-driven, mints its own internal CA | publishes `:80`/`:443` |
| [`caddy/`](caddy/) | HTTPS reverse proxy (backup), Caddyfile-driven, mints its own internal CA | publishes `:80`/`:443` (pick caddy or traefik, not both) |
| [`cloudflare/`](cloudflare/) | Cloudflare Tunnel connector — outbound-only public ingress | configurable per-hostname in the CF dashboard |
| [`tailscale/`](tailscale/) | Tailscale sidecar — tailnet-only ingress over WireGuard, optional Serve overlay fronts `traefik` | `https://spark-1822.<tailnet>.ts.net` |
| [`vllm/`](vllm/) | vLLM inference server (HF safetensors), tool-calling enabled (`qwen3_xml`) | `https://vllm.spark-1822.local` |
| [`llama-cpp/`](llama-cpp/) | llama.cpp server (GGUF), OpenAI-compatible API + web UI | `https://llama.spark-1822.local` |
| [`open-webui/`](open-webui/) | Open WebUI + Ollama (GPU on Ollama only) | `https://open-webui.spark-1822.local`, `https://ollama.spark-1822.local` |
| [`netdata/`](netdata/) | Real-time host + container telemetry | `https://netdata.spark-1822.local` |
| [`mdns/`](mdns/) | Host systemd template publishing `<sub>.spark-1822.local` mDNS aliases | host-level |

## Host

| | |
|---|---|
| Hardware | [NVIDIA DGX Spark](https://amzn.to/47ZeWqZ) |
| Hostname | `spark-1822.local` |
| OS | Ubuntu (kernel `6.17.0-nvidia`), aarch64 |
| GPU | NVIDIA GB10 (compute capability 12.1, 124 GiB VRAM) |
| Docker | 29.x + Compose v2 |
| GPU runtime | `nvidia-container-toolkit` 1.19 (CDI mode) |

## First-time setup

On a fresh host, in order:

1. **Install the mDNS helper** (host-side; publishes `<sub>.spark-1822.local` aliases):

   ```bash
   cd /opt/mdns && make install
   ```

2. **Bring up the primary proxy** — this also creates the shared `traefik` Docker network everything else joins:

   ```bash
   cd /opt/traefik
   cp .env.example .env             # then set TRAEFIK_TAG
   make ca-cert                     # one-time: mint Traefik's internal root CA
   make wildcard-cert               # mint the wildcard leaf signed by that root
   docker compose up -d
   ```

   Install `traefik/certs/traefik-root.crt` on each client that should trust the host's LAN URLs (per-OS install table in [`traefik/README.md`](traefik/README.md)).

3. **Publish a mDNS alias for each subdomain** you'll expose:

   ```bash
   cd /opt/mdns
   for a in traefik vllm llama ollama open-webui netdata; do make add ALIAS=$a; done
   ```

4. **Bring up the services** — each one attaches to the `traefik` network and Traefik auto-routes via the `traefik.*` labels in its compose:

   ```bash
   cd /opt/open-webui && cp .env.example .env && docker compose up -d
   cd /opt/netdata    && cp .env.example .env && docker compose up -d
   cd /opt/vllm       && make up ENV=<variant>      # see vllm/envs/
   cd /opt/llama-cpp  && make up ENV=<variant>      # see llama-cpp/envs/
   ```

5. **(Optional) Public ingress via Cloudflare Tunnel** — only if you want internet-reachable URLs:

   ```bash
   cd /opt/cloudflare
   cp .env.example .env             # paste CLOUDFLARE_TUNNEL_TOKEN from the CF dashboard
   docker compose up -d
   ```

   Then configure Public Hostnames in the Cloudflare dashboard so they forward to `http://traefik:80` with the matching internal Host header (recipe in [`cloudflare/README.md`](cloudflare/README.md)).

6. **(Optional) Tailnet ingress via Tailscale** — only if you want this host reachable from your tailnet:

   ```bash
   cd /opt/tailscale
   cp .env.example .env             # paste TS_AUTHKEY from the Tailscale admin console
   docker compose up -d
   ```

   The node registers as `spark-1822.<tailnet>.ts.net` with a real publicly-trusted MagicDNS cert; Tailscale Serve wires `:443` on the tailnet to `http://traefik:80`. See [`tailscale/README.md`](tailscale/README.md) for the Host-header note (every Traefik router uses a `HostRegexp(`spark{x:.+}`)` matcher, so the tailnet hostname is accepted as-is — no per-route plumbing; rule-length priority picks which router answers the bare tailnet URL).

## Deploy workflow

`/opt` on the host **is** a checkout of this repo — every stack lives in place at `/opt/<name>/`. Edit locally, commit, push; then pull on the host:

```bash
ssh spark-1822.local 'sudo git -C /opt pull --ff-only'
```

After the pull, apply the change in the relevant stack (each stack's README has details):

- **Inference stacks** (`vllm/`, `llama-cpp/`) — `cd /opt/<stack> && make up ENV=<variant>` to (re)start with a variant.
- **Traefik** — routing changes via Docker labels or `dynamic/*.yml` files are hot-reloaded; `docker compose restart traefik` only if `traefik.yml` itself changed.
- **Caddy** — `docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile` for a hot reload after editing a `Caddyfile.d/*.caddyfile`.
- **Other stacks** — `cd /opt/<name> && docker compose up -d`.

Host-local files outside git stay put across pulls — each stack's `.env` (secrets), inference `envs/*.env` variants, TLS material (`*.crt`/`*.key`), and `*.bak` backups are all gitignored.

## Conventions

- **One reverse proxy at a time.** Traefik and Caddy both bind `:80`/`:443` — pick one. The other stack's compose files coexist on disk so switching is `docker compose down` + `docker compose up -d`. Services define `traefik.*` labels *and* sit in Caddy's `Caddyfile.d/`, so the same compose runs under either proxy.
- **Image tags pinned** to specific versions in `.env` files (single source of truth, validated by CI) — never `:latest`. Pin format depends on what the registry publishes: a plain immutable tag (`v2.11`, `v0.20.2`) when available; the digest of a multi-arch manifest list when a project only publishes the arm64 build under a floating tag (e.g. `ggml-org/llama.cpp`'s `server-cuda`, where the per-build tags are amd64-only).
- **Inference config split** by scope. `<stack>/.env` carries host-wide values (image pin, HF cache path, HF token, default knobs); `<stack>/envs/<name>.env` carries just the model selection plus per-variant overrides. `make up ENV=<name>` chains both via `docker compose --env-file .env --env-file envs/<name>.env up -d`. Both files are gitignored — the templates live next to them as `.env.example`.
- **Loopback ports on inference stacks.** `vllm/` and `llama-cpp/` additionally bind their API to `127.0.0.1` on the host for direct curl / benchmarking — LAN traffic still flows through the proxy.
- **Permissions.** `/opt/<stack>/` is `root:root`. The `.env` files are `root:docker 640` so the `docker`-group user reads them and runs compose without sudo. Editing configs requires `sudo`.
- **Supply chain.** Every third-party Docker image is pinned by tag (or digest where applicable) in `.env.example`. Every GitHub Action is pinned by commit SHA. Trivy scans push / PR / weekly cron; Dependabot keeps the SHA pins fresh with a weekly grouped PR.

## Repo housekeeping

- [`CHANGELOG.md`](CHANGELOG.md) — [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format, [SemVer](https://semver.org/spec/v2.0.0.html) versioning.
- [`.github/workflows/trivy.yml`](.github/workflows/trivy.yml) — image CVE scans (HIGH+CRITICAL, fixed-only), IaC config scan, filesystem secret scan. Doc: [`.github/workflows/trivy.md`](.github/workflows/trivy.md).
- [`.github/dependabot.yml`](.github/dependabot.yml) — weekly grouped PR to bump pinned GitHub Action SHAs.
- [`LICENSE`](LICENSE) — MIT.
- [`sparky.svg`](sparky.svg) — project mascot. Drawn by the AI that helped build this repo, as a self-portrait.
