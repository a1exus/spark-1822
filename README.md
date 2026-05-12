# sparky

Configuration for the [NVIDIA DGX Spark](https://amzn.to/47ZeWqZ) workstation `spark-1822` (Ubuntu, aarch64, GB10 GPU).

## Layout

```
.
├── caddy/               # HTTPS reverse proxy (terminates TLS, fronts all apps)
├── open-webui/          # Open WebUI + Ollama docker-compose stack
└── README.md
```

Each top-level dir corresponds to `/opt/<name>/` on the host. Workflow: edit here, `scp` to the host (or sync via your tool of choice), then `docker compose up -d` on the host.

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

After trust is established, browse to `https://spark-1822.local`.

To add a new app to Caddy, add a site block to `Caddyfile`:

```
myapp.spark-1822.local {
    tls internal
    reverse_proxy myapp:8080
}
```

Then `docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile` (no downtime).

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

Open WebUI is then reachable at `https://spark-1822.local` (through Caddy). The first user to register becomes admin; after that, set `ENABLE_SIGNUP=false` in `.env` and re-run `docker compose up -d` to lock it down.

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

## Conventions

- `.env` files contain secrets and are **never** committed (see `.gitignore`).
- Image tags are pinned to specific versions in `.env` (single source of truth) — no `:latest`.
- Only Caddy publishes host ports (`80`, `443`); every other service is reachable only on the internal compose network or the shared `web` network.

## CI: Trivy security scanning

`.github/workflows/trivy.yml` runs on push to `main`, PRs, and a weekly schedule (Mon 06:00 UTC). It performs:

- **Image scans** — CVE scan of the pinned `ollama/ollama` and `open-webui` images (HIGH+CRITICAL, fixed-only). Tags are read from `open-webui/.env.example`.
- **IaC scan** — Trivy config check against `open-webui/` (compose misconfig).
- **Secret scan** — filesystem scan for accidentally-committed secrets.

All findings are uploaded as SARIF to the repo's [Security tab](https://github.com/a1exus/spark-1822/security/code-scanning). PRs/pushes fail on any CRITICAL CVE or any leaked secret; the scheduled run never fails (informational, so upstream-only CVEs don't break the green badge between version bumps).

Actions are pinned by commit SHA per security best practice.
