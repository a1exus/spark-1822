# sparky

Configuration for the [NVIDIA DGX Spark](https://amzn.to/47ZeWqZ) workstation `spark-1822` (Ubuntu, aarch64, GB10 GPU).

## Contents

- [Layout](#layout)
- [Components](#components)
- [Host](#host)
- [One-time setup](#one-time-setup)
- [Deploy workflow](#deploy-workflow)
- [Conventions](#conventions)
- [Changelog](#changelog)

## Layout

```
.
├── caddy/         # HTTPS reverse proxy (terminates TLS, fronts all apps)
├── llama-cpp/     # llama.cpp server (GGUF, GPU on GB10 via CUDA)
├── mdns/          # systemd helper publishing subdomain mDNS aliases
├── netdata/       # Real-time host + container observability
├── open-webui/    # Open WebUI + Ollama (LLM chat UI)
├── vllm/          # vLLM inference server (HF safetensors)
├── .github/       # CI: Trivy security scanning
├── CHANGELOG.md
├── LICENSE
└── README.md
```

Each component has its own `README.md` — start there for deploy / configure / upgrade details.

## Components

| Dir | What | Access |
|---|---|---|
| [`caddy/`](caddy/) | HTTPS reverse proxy, Caddy local CA | publishes `:80`/`:443` |
| [`llama-cpp/`](llama-cpp/) | llama.cpp server (GGUF, OpenAI-compatible API + web UI) — model variants under `envs/` | `https://llama.spark-1822.local` |
| [`mdns/`](mdns/) | Host systemd template that publishes `<sub>.spark-1822.local` mDNS aliases | host-level |
| [`netdata/`](netdata/) | Real-time host + container telemetry | `https://netdata.spark-1822.local` |
| [`open-webui/`](open-webui/) | Open WebUI + Ollama, GPU on Ollama only | `https://open-webui.spark-1822.local` (UI), `https://ollama.spark-1822.local` (Ollama API) |
| [`vllm/`](vllm/) | vLLM inference server (HF safetensors) — model variants under `envs/`; OpenAI tool-calling enabled (`qwen3_xml` parser) | `https://vllm.spark-1822.local` |
| [`.github/`](.github/) | Trivy CI workflow (CVE / IaC / secret scans) | GitHub Actions |

## Host

| | |
|---|---|
| Hardware | [NVIDIA DGX Spark](https://amzn.to/47ZeWqZ) |
| Hostname | `spark-1822.local` |
| OS | Ubuntu (kernel `6.17.0-nvidia`), aarch64 |
| GPU | NVIDIA GB10 |
| Docker | 29.x + Compose v2 |
| GPU runtime | `nvidia-container-toolkit` 1.19 (CDI mode) |

## One-time setup

```bash
# On the host:
docker network create caddy              # shared external network — Caddy reaches every app on this
cd /opt/mdns && make install             # mDNS alias helper (see mdns/README.md)
```

Then deploy each stack per its own README, in order: `caddy/` first, then everything else.

## Deploy workflow

Files in this repo correspond to `/opt/<name>/` on the host. Edit here, then sync:

```bash
ssh spark-1822.local "rm -rf /tmp/<name>-stage && mkdir -p /tmp/<name>-stage"
scp <name>/* spark-1822.local:/tmp/<name>-stage/
ssh spark-1822.local "
  sudo install -o root -g root   -m 644 /tmp/<name>-stage/<file> /opt/<name>/<file>
  sudo install -o root -g docker -m 640 /tmp/<name>-stage/.env   /opt/<name>/.env
  docker compose -f /opt/<name>/docker-compose.yml up -d
"
```

## Conventions

- `.env` files contain secrets and are **never** committed (see `.gitignore`).
- Image tags are pinned to specific versions in `.env` (single source of truth) — no `:latest`.
- Inference stacks (`llama-cpp/`, `vllm/`) use a one-env-per-model-variant layout. Each `envs/<name>.env` (host-local; gitignored) is **self-contained** — image pin + HF cache + HF token + model knobs in one file. `make up ENV=<name>` invokes `docker compose --env-file envs/<name>.env up -d` directly — no rolling `.env` is written.
- Only Caddy publishes host ports on `0.0.0.0` (`80`, `443`); LAN traffic always reaches services through it. Inference stacks (`llama-cpp/`, `vllm/`) additionally bind their API to `127.0.0.1` on the host for direct curl/benchmarks (loopback only — not LAN-reachable).
- `/opt/<stack>/` on the host is owned `root:root`. The only exception is each stack's `.env`, which is `root:docker 640` so the `docker`-group `alexus` user can read it (and run `docker compose` without sudo). Editing configs always requires `sudo`.

## Changelog

See [`CHANGELOG.md`](CHANGELOG.md) — [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format, [SemVer](https://semver.org/spec/v2.0.0.html) versioning.
