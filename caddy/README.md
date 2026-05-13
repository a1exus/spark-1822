# caddy

HTTPS reverse proxy for every other app on this host. Terminates TLS using [Caddy](https://caddyserver.com)'s internal CA (`tls internal`) and forwards traffic to the right service over the shared `caddy` Docker network.

Caddy is the only stack that publishes host ports (`80`, `443`, plus `443/udp` for HTTP/3). Every other service is unreachable from the LAN except through it.

## Files

```
caddy/
├── docker-compose.yml         # caddy service, joins external `caddy` network
├── Caddyfile                  # global options + snippets + import directive
├── Caddyfile.d/               # one file per service
│   ├── open-webui.caddyfile
│   ├── ollama.caddyfile
│   ├── netdata.caddyfile
│   └── llama-cpp.caddyfile
├── .env.example               # committed; copy to .env and customize
└── .env                       # not committed (gitignored)
```

Each service has its own `Caddyfile.d/<service>.caddyfile`. The top-level `Caddyfile` defines global options and shared snippets (e.g. `common_headers`, `default_log`) and ends with `import Caddyfile.d/*.caddyfile`. To add a service: drop a new `<name>.caddyfile` into `Caddyfile.d/` and reload Caddy — no other edits needed.

## Configure

```bash
cp .env.example .env
# Edit .env:
#   CADDY_TAG     — Caddy image tag (e.g. 2.11.2-alpine)
#   CADDY_DOMAIN  — hostname this Caddy answers to (must resolve to this host)
```

`CADDY_DOMAIN` is referenced in the Caddyfile as `{$CADDY_DOMAIN}`, so the same config works on any host without edits.

## Deploy

Prereq: the shared `caddy` network must exist (one-time, on the host):

```bash
docker network create caddy
```

Then:

```bash
docker compose up -d
docker compose ps
```

## Trust the root CA

`tls internal` means Caddy signs leaf certificates with its own private root. Browsers won't trust it until you install that root on each client.

Extract the root:

```bash
docker exec caddy cat /data/caddy/pki/authorities/local/root.crt > caddy-root.crt
```

Install it:

| Platform | Command / steps |
|---|---|
| macOS (CLI) | `sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain caddy-root.crt` |
| macOS (GUI) | Open `caddy-root.crt` → Keychain Access → System keychain → set the cert to "Always Trust". |
| iOS | AirDrop or email `caddy-root.crt` → Install profile → Settings → General → About → Certificate Trust Settings → enable full trust. |
| Linux (Debian/Ubuntu) | `sudo cp caddy-root.crt /usr/local/share/ca-certificates/caddy-root.crt && sudo update-ca-certificates` |
| Linux (Fedora/RHEL/CentOS) | `sudo cp caddy-root.crt /etc/pki/ca-trust/source/anchors/ && sudo update-ca-trust` |
| Linux (Arch) | `sudo trust anchor --store caddy-root.crt` |
| Windows (PowerShell, admin) | `Import-Certificate -FilePath caddy-root.crt -CertStoreLocation Cert:\LocalMachine\Root` |
| Windows (cmd, admin) | `certutil -addstore -f "ROOT" caddy-root.crt` |
| Windows (GUI) | Double-click `caddy-root.crt` → Install Certificate → Store Location: **Local Machine** → "Place all certificates in the following store" → Browse → **Trusted Root Certification Authorities**. |
| Firefox (any OS) | Firefox doesn't use the system store. Settings → Privacy & Security → Certificates → View Certificates → Authorities → Import. |
| Node.js apps (opencode, etc.) | Node bundles its own CA list and ignores the system store. Either export `NODE_EXTRA_CA_CERTS=$(pwd)/caddy-root.crt` (run from the directory holding the file) before launching, or on Node ≥22 set `NODE_USE_SYSTEM_CA=1` (then the OS install above applies). |

The root certificate is host-specific (gitignored as `*.crt`) and rotates only if the `caddy-data` volume is destroyed.

## Add a new app

1. Run the new app's stack with a service on the `caddy` network (no host port publish needed).
2. Create `Caddyfile.d/<name>.caddyfile`:

   ```caddyfile
   myapp.{$CADDY_DOMAIN} {
       tls internal
       encode zstd gzip
       import common_headers
       import default_log

       reverse_proxy myapp:8080
   }
   ```

3. Publish the subdomain on mDNS so clients can resolve it (skip if you're using a real DNS provider):

   ```bash
   sudo systemctl enable --now 'sparky-mdns-alias@myapp.spark-1822.local'
   ```

   See [`../mdns/`](../mdns/) for the alias service.

4. Reload Caddy with no downtime:

   ```bash
   docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile
   ```

For services that stream (SSE, WebSocket-like long polling, chat tokens), set `flush_interval -1` inside the `reverse_proxy` block — see `open-webui` in the current Caddyfile.

## Upgrade

Bump `CADDY_TAG` in `.env`, then:

```bash
docker compose pull
docker compose up -d
```

## Reload after Caddyfile edits

```bash
docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile
```

No container restart, no dropped connections. Caddy validates the new config before swapping it in.

## Logs

```bash
docker compose logs -f caddy
```

Access logs are emitted as structured JSON (default format) and routed via Caddy's `log` directive in the Caddyfile.

## Uninstall

```bash
docker compose down
docker volume rm caddy-data caddy-config   # destroys cert store + admin state
```

Destroying `caddy-data` regenerates the root CA on next start — every previously-trusted client will need the new root installed.

## See also

- Top-level [README](../README.md) for overall layout, conventions, and CI.
- Caddy docs: <https://caddyserver.com/docs/>
- `tls internal` reference: <https://caddyserver.com/docs/caddyfile/directives/tls#internal>
