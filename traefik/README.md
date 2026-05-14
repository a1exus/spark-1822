# traefik

HTTPS reverse proxy. Alternative to [`caddy/`](../caddy/) — same set of routes, but driven by [Traefik](https://traefik.io/). Caddy and Traefik can't run at the same time (both want host ports `:80` / `:443`); start one or the other.

## Why this exists

Sibling stack to `caddy/` for A/B-ing the two proxies on the exact same backends. Useful if you want Traefik's middleware ecosystem (rate-limiting, auth providers, header tweaks via Docker labels) or just to see how the same setup looks under a different proxy. The Caddy stack stays as-is; you switch.

## Files

```
traefik/
├── docker-compose.yml         # traefik service, joins external `caddy` network
├── traefik.yml                # static config (entrypoints, providers, api, log)
├── dynamic/                   # file provider — hot-reloaded on edit
│   ├── services.yml           # routers + backend services (one block per host)
│   └── tls.yml                # references the wildcard cert from certs/
├── wildcard.cnf               # OpenSSL config for `make wildcard-cert`
├── Makefile                   # `make wildcard-cert` (mint/renew the leaf)
├── certs/                     # gitignored — wildcard.crt + wildcard.key live here
├── .env.example               # committed; copy to .env and customize
└── .env                       # not committed (gitignored)
```

## Configure

```bash
cp .env.example .env
# Edit .env:
#   TRAEFIK_TAG — Traefik image tag (e.g. v3.3)
```

## Mint the TLS wildcard

Traefik serves a single wildcard cert (`*.spark-1822.local` + `spark-1822.local`) **signed by Caddy's existing root CA**. Any client that already trusts `caddy-root.crt` (see [`caddy/README.md`](../caddy/README.md)) automatically trusts Traefik's leaf too — no new CA install needed.

Prereq: Caddy has come up at least once on this host (the root CA lives in the persistent `caddy-data` Docker volume).

```bash
sudo make wildcard-cert
```

Re-run whenever the cert is about to expire (365-day default, override via `CERT_DAYS=30 sudo make wildcard-cert`).

## Deploy

Prereq: the shared `caddy` Docker network must exist. The `caddy/` stack defines it — bring `caddy/` up at least once if you've never started it. Then **stop Caddy** (you can't bind `:80` / `:443` from two stacks at once):

```bash
docker compose -f /opt/caddy/docker-compose.yml down
cd /opt/traefik && docker compose up -d
docker compose ps
```

To switch back to Caddy:

```bash
docker compose -f /opt/traefik/docker-compose.yml down
cd /opt/caddy && docker compose up -d
```

## What gets routed

All hosts use the wildcard cert; routes mirror Caddy's:

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

1. Bring its compose up on the `caddy` Docker network (no host-port publish needed).
2. Add a router + service block to `dynamic/services.yml`:

   ```yaml
   http:
     routers:
       myapp:
         rule: "Host(`myapp.spark-1822.local`)"
         entryPoints: [websecure]
         service: myapp
         tls: {}
     services:
       myapp:
         loadBalancer:
           servers:
             - url: "http://myapp:8080"
           passHostHeader: true
   ```

3. Publish the mDNS alias on the host (see [`../mdns/`](../mdns/)):

   ```bash
   cd /opt/mdns && make add ALIAS=myapp
   ```

Traefik's file provider has `watch: true`, so the change picks up without a restart.

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
- [`caddy/`](../caddy/) — the canonical / default reverse proxy
- [`mdns/`](../mdns/) — host-side mDNS aliases
- Traefik docs: <https://doc.traefik.io/traefik/>
