# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/a1exus/spark-1822/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/a1exus/spark-1822/releases/tag/v0.1.0
