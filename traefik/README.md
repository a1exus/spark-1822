# traefik

HTTPS reverse proxy — front-facing entry point on this host. Publishes `:80` / `:443` and routes by Host header to whichever backend serves each subdomain.

## How routing works

Each app's `docker-compose.yml` carries `traefik.*` labels (router `rule`, `entryPoints`, `tls`, `loadbalancer.server.port`). Traefik's **docker provider** discovers them via the docker socket and wires up routers + services automatically — no central config file to edit when you add a new app. Anything that can't be label-driven (host-network containers like `netdata`; Traefik's own dashboard) lives in `dynamic/services.yml` and the **file provider** picks it up.

## Files

```
traefik/
├── docker-compose.yml         # traefik service, defines + owns the shared `traefik` network, mounts docker.sock:ro
├── traefik.yml                # static config — docker + file providers, entrypoints, api, log
├── dynamic/                   # file provider — hot-reloaded on edit
│   ├── services.yml           # routes for things the docker provider can't reach (netdata, dashboard)
│   └── tls.yml                # references the wildcard cert from certs/
├── wildcard.cnf               # OpenSSL config for `make wildcard-cert`
├── Makefile                   # `make ca-cert` (one-time) + `make wildcard-cert` (renew)
├── certs/                     # gitignored — traefik-root.{crt,key} + wildcard.{crt,key}
├── .env.example               # committed; copy to .env and customize
└── .env                       # not committed (gitignored)
```

## Configure

```bash
cp .env.example .env
# Edit .env:
#   TRAEFIK_TAG — Traefik image tag (default: v2.11 LTS)
```

## TLS — internal CA + wildcard

Traefik runs its own internal CA. Two steps the first time on a host:

```bash
make ca-cert         # one-time: mint certs/traefik-root.{crt,key} (10-year root)
make wildcard-cert   # mint certs/wildcard.{crt,key} signed by the root (365-day leaf)
```

Re-run `make wildcard-cert` to renew the leaf (override the validity with `CERT_DAYS=30 make wildcard-cert`). `make ca-cert` is a no-op if the root already exists — delete `certs/traefik-root.*` only when you want to rotate, and remember that every previously-trusting client will need the new root installed.

### Trust the root CA

Every client (your laptop, phone, container that talks back to this host) needs `certs/traefik-root.crt` in its trust store. Otherwise browsers warn and curl wants `-k`. Per-OS install steps:

| Platform | Command / steps |
|---|---|
| macOS (CLI) | `sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain traefik-root.crt` |
| macOS (GUI) | Open `traefik-root.crt` → Keychain Access → System keychain → set the cert to "Always Trust". |
| iOS | AirDrop or email `traefik-root.crt` → Install profile → Settings → General → About → Certificate Trust Settings → enable full trust. |
| Linux (Debian/Ubuntu) | `sudo cp traefik-root.crt /usr/local/share/ca-certificates/traefik-root.crt && sudo update-ca-certificates` |
| Linux (Fedora/RHEL/CentOS) | `sudo cp traefik-root.crt /etc/pki/ca-trust/source/anchors/ && sudo update-ca-trust` |
| Linux (Arch) | `sudo trust anchor --store traefik-root.crt` |
| Windows (PowerShell, admin) | `Import-Certificate -FilePath traefik-root.crt -CertStoreLocation Cert:\LocalMachine\Root` |
| Windows (cmd, admin) | `certutil -addstore -f "ROOT" traefik-root.crt` |
| Windows (GUI) | Double-click `traefik-root.crt` → Install Certificate → Local Machine → Trusted Root Certification Authorities. |
| Firefox (any OS) | Firefox doesn't use the system store. Settings → Privacy & Security → Certificates → View Certificates → Authorities → Import. |
| Node.js apps | Node bundles its own CA list and ignores the system store. Either export `NODE_EXTRA_CA_CERTS=$(pwd)/traefik-root.crt` before launching, or on Node ≥22 set `NODE_USE_SYSTEM_CA=1` (then the OS install above applies). |

The root and the leaf are both gitignored (`*.crt` / `*.key`). They're host-specific.

## Deploy

Prereq: TLS material exists (`make ca-cert && make wildcard-cert`). Then bring Traefik up — that creates the shared `traefik` Docker network:

```bash
cd /opt/traefik && docker compose up -d
docker compose ps
```

## What gets routed

All hosts use the wildcard cert:

| Host | Upstream |
|---|---|
| `https://llama.spark-1822.local` | `llama-cpp:8080` |
| `https://vllm.spark-1822.local` | `vllm:8000` |
| `https://ollama.spark-1822.local` | `ollama:11434` |
| `https://open-webui.spark-1822.local` | `open-webui:8080` |
| `https://netdata.spark-1822.local` | `host.docker.internal:19999` |
| `https://traefik.spark-1822.local` | Traefik's own dashboard + API |

Plain HTTP requests on `:80` are 308-redirected to HTTPS.

## Add an app

For a container on the `traefik` Docker network, just add labels to its `docker-compose.yml` and let the docker provider pick it up:

```yaml
services:
  myapp:
    # … usual config …
    networks:
      - traefik
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=traefik"
      - "traefik.http.routers.myapp.rule=HostRegexp(`myapp.spark{x:.+}`)"
      - "traefik.http.routers.myapp.entryPoints=websecure"
      - "traefik.http.routers.myapp.tls=true"
      - "traefik.http.services.myapp.loadbalancer.server.port=8080"
```

Publish the mDNS alias on the host (see [`../mdns/`](../mdns/)):

```bash
cd /opt/mdns && make add ALIAS=myapp
```

Bring the app up — Traefik picks up the labels live (docker provider has `watch: true`); no Traefik restart needed.

For containers that **can't** be label-discovered (host-network mode, external services), drop a router + service into `dynamic/services.yml` instead. The file provider has `watch: true` too.

## LetsEncrypt (publicly-trusted certs)

The wildcard cert above is signed by Traefik's own internal CA — fine for LAN clients that trust `traefik-root.crt`, but every other browser will warn. If you ever expose this host on a **publicly-resolvable domain** (e.g. `spark.example.com`), LE can issue real, publicly-trusted certs.

The scaffolding is already in place — three blocks to uncomment + edit, in order:

1. **`traefik.yml`** — uncomment the `certificatesResolvers.letsencrypt.acme` block, set your email, and pick one challenge (`http-01` if port 80 is reachable from the public internet; `dns-01` if your DNS provider has an API token and you want wildcards).
2. **`docker-compose.yml`** — uncomment the `- traefik-acme:/etc/traefik/acme` volume mount and the matching `traefik-acme:` named-volume block. (For `dns-01`, also add the provider's API token as an env var.)
3. **Per-route opt-in** — on whichever service should use LE, add the label:
   ```yaml
   - "traefik.http.routers.<name>.tls.certresolver=letsencrypt"
   ```
   Services without that label keep using the internal wildcard. Both cert sources coexist.

LE will not issue for `.local` names — that's why opt-in is per-route rather than the default.

## Logs

```bash
docker compose logs -f traefik
```

Access logs are emitted as structured JSON via Traefik's `accessLog` directive in `traefik.yml`.

## Upgrade

Bump `TRAEFIK_TAG` in `.env`, then:

```bash
docker compose pull
docker compose up -d
```

## Uninstall

```bash
docker compose down
docker volume rm traefik-certs 2>/dev/null || true
```

`certs/wildcard.{crt,key}` on disk persist until you `rm` them manually.

## See also

- Top-level [README](../README.md)
- [`mdns/`](../mdns/) — host-side mDNS aliases
- Traefik docs: <https://doc.traefik.io/traefik/>
