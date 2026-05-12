# sparky

Configuration for the [NVIDIA DGX Spark](https://amzn.to/47ZeWqZ) workstation `spark-1822` (Ubuntu, aarch64, GB10 GPU).

## Layout

```
.
├── caddy/               # HTTPS reverse proxy (terminates TLS, fronts all apps)
├── mdns/                # systemd helper publishing subdomain mDNS aliases
├── netdata/             # Real-time host + container observability
├── open-webui/          # Open WebUI + Ollama docker-compose stack
└── README.md
```

Each top-level dir corresponds to `/opt/<name>/` on the host. Workflow: edit here, `scp` to a `/tmp/<name>-stage/` directory on the host, then `sudo install -m … /tmp/<name>-stage/* /opt/<name>/` and run the stack. `/opt/<name>/` is `root:root`; `.env` is `root:docker 640` so the day-to-day `alexus` user (member of the `docker` group) can run `docker compose` without sudo while not being able to edit configs casually.

App stacks share an external Docker network named `web`. Caddy is the only stack that publishes host ports (`80`, `443`). All other services stay internal and are reachable only through Caddy.

```bash
# One-time, on the host:
docker network create web
```

## Host

| | |
|---|---|
| Hostname | `spark-1822.local` |
| OS | Ubuntu (kernel `6.17.0-nvidia`), aarch64 |
| GPU | NVIDIA GB10 |
| Docker | 29.x + Compose v2 |
| GPU runtime | `nvidia-container-toolkit` 1.19 (CDI mode) |

## caddy

HTTPS reverse proxy in front of every app on this host. Issues certificates from its own internal CA (`tls internal`) — clients need Caddy's root CA installed once to avoid browser warnings.

### Deploy

```bash
cd /opt/caddy
cp .env.example .env
# Edit .env — set CADDY_DOMAIN to the hostname this box answers to
# (e.g., spark-1822.local for mDNS, or your own DNS name).
docker compose up -d
docker compose ps
```

After first start, extract the root CA and install it on each client device:

```bash
# On the host:
docker exec caddy cat /data/caddy/pki/authorities/local/root.crt > ~/caddy-root.crt
# Then copy ~/caddy-root.crt to clients and install:
#   macOS:   double-click → Keychain Access → set "Always Trust"
#   iOS:     AirDrop + Settings → General → VPN & Device Management → Install
#   Linux:   sudo cp caddy-root.crt /usr/local/share/ca-certificates/ && sudo update-ca-certificates
```

After trust is established, browse to `https://${CADDY_DOMAIN}`.

The hostname is parameterized via the `CADDY_DOMAIN` env var (set in `caddy/.env`), so the same Caddyfile works on any host. To add a new app, add a site block to `Caddyfile`:

```
myapp.{$CADDY_DOMAIN} {
    tls internal
    reverse_proxy myapp:8080
}
```

Then `docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile` (no downtime).

## mdns

Small systemd template service that publishes subdomain mDNS aliases (e.g. `netdata.spark-1822.local` → host IP) via Avahi. Required so Caddy's subdomain site blocks resolve on the LAN — mDNS only registers the exact hostname by default.

See [`mdns/README.md`](mdns/README.md) for install and usage.

## netdata

Real-time host + container monitoring with [Netdata](https://www.netdata.cloud/). Agent runs with `network_mode: host` + `pid: host`; UI is fronted by Caddy at `https://netdata.${CADDY_DOMAIN}` with HTTP basic auth.

See [`netdata/README.md`](netdata/README.md) for deployment and basic-auth setup.

## open-webui

Self-hosted [Open WebUI](https://github.com/open-webui/open-webui) backed by [Ollama](https://github.com/ollama/ollama). Two-container stack: `ollama` (GPU, internal-only) + `open-webui` (UI, internal-only — exposed via Caddy).

Adapted from NVIDIA's official playbook: <https://build.nvidia.com/spark/open-webui/instructions>. Diverges in four ways: services are split (instead of the bundled `:ollama` image), images are version-pinned via `.env`, secrets live in `.env`, and the UI is fronted by Caddy on HTTPS instead of being published directly on `:8080`.

### Deploy

```bash
# On the host, first time:
cd /opt/open-webui
cp .env.example .env
# Edit .env — set WEBUI_SECRET_KEY (openssl rand -hex 32)
docker compose up -d
docker compose ps
```

Open WebUI is then reachable at `https://${CADDY_DOMAIN}` (through Caddy). The first user to register becomes admin; after that, set `ENABLE_SIGNUP=false` in `.env` and re-run `docker compose up -d` to lock it down.

### Pull models

```bash
docker compose exec ollama ollama pull llama3.2
docker compose exec ollama ollama list
```

Browse the [Ollama library](https://ollama.com/library) for more.

### Upgrade

Bump the pinned tags in `docker-compose.yml`, then:

```bash
docker compose pull
docker compose up -d
```

### Logs & status

```bash
docker compose logs -f open-webui
docker compose logs -f ollama
docker compose ps
```

### Uninstall

```bash
docker compose down
docker volume rm open-webui open-webui-ollama   # destroys data and models
```

## Changelog

See [`CHANGELOG.md`](CHANGELOG.md) — [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format, [SemVer](https://semver.org/spec/v2.0.0.html) versioning.

## Conventions

- `.env` files contain secrets and are **never** committed (see `.gitignore`).
- Image tags are pinned to specific versions in `.env` (single source of truth) — no `:latest`.
- Only Caddy publishes host ports (`80`, `443`); every other service is reachable only on the internal compose network or the shared `web` network.
- `/opt/<stack>/` on the host is owned `root:root`. The only exception is each stack's `.env`, which is `root:docker 640` so the `docker`-group `alexus` user can read it (and therefore run `docker compose` without sudo). Editing configs always requires `sudo`.

## CI: Trivy security scanning

`.github/workflows/trivy.yml` runs on push to `main`, PRs, and a weekly schedule (Mon 06:00 UTC). It performs:

- **Image scans** — CVE scan of the pinned `ollama/ollama` and `open-webui` images (HIGH+CRITICAL, fixed-only). Tags are read from `open-webui/.env.example`.
- **IaC scan** — Trivy config check against `open-webui/` (compose misconfig).
- **Secret scan** — filesystem scan for accidentally-committed secrets.

All findings are uploaded as SARIF to the repo's [Security tab](https://github.com/a1exus/spark-1822/security/code-scanning). PRs/pushes fail on any CRITICAL CVE or any leaked secret; the scheduled run never fails (informational, so upstream-only CVEs don't break the green badge between version bumps).

Actions are pinned by commit SHA per security best practice.
