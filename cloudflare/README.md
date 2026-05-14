# cloudflare

[Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) connector. Exposes select services on this host to the public internet **without opening any inbound ports**. `cloudflared` makes an outbound persistent connection to Cloudflare's edge; Cloudflare receives traffic on your public hostnames and forwards it through the tunnel to whichever origin you wire up in the dashboard (typically `traefik`, which then routes by `Host()` to the right backend).

## Files

```
cloudflare/
├── docker-compose.yml       # cloudflared service, joins external `traefik` network
├── .env.example             # committed; copy to .env and fill in the token
└── .env                     # not committed (gitignored)
```

## Configure

### 1. Create the tunnel in the Cloudflare dashboard

1. Cloudflare → **Zero Trust** → **Networks** → **Tunnels** → **Create a tunnel**.
2. Pick **Cloudflared** as the connector type, give the tunnel a name (e.g. `sparky`).
3. On the **Install connector** step, choose **Docker**. Copy the long base64 **token** from the displayed `docker run` command.

### 2. Drop the token into `.env`

```bash
cp .env.example .env
# Edit .env:
#   CLOUDFLARED_TAG          — pin the cloudflared image (see hub.docker.com/r/cloudflare/cloudflared/tags)
#   CLOUDFLARE_TUNNEL_TOKEN  — the token from step 1
```

### 3. Wire public hostnames (still in the dashboard)

In the tunnel's **Public Hostnames** tab, add one route per service to expose. The origin URL is on the `traefik` Docker network, so use the container name `traefik`:

| Public Hostname | Service URL | Origin Request → HTTP Host Header |
|---|---|---|
| `vllm.example.com` | `http://traefik:80` | `vllm.spark-1822.local` |
| `llama.example.com` | `http://traefik:80` | `llama.spark-1822.local` |
| `webui.example.com` | `http://traefik:80` | `open-webui.spark-1822.local` |
| `ollama.example.com` | `http://traefik:80` | `ollama.spark-1822.local` |

The HTTP Host Header override is what makes Traefik's internal `Host(...)` router match. Without it, Traefik sees `Host: vllm.example.com` and falls through (no router matches that). With it, Traefik sees `Host: vllm.spark-1822.local` and routes to the right backend.

(For `https://traefik:443` with Traefik's self-signed wildcard, also set Origin Request → **TLS** → "No TLS Verify" or distribute Traefik's root CA via Cloudflare Access — most setups stick with `http://` since the tunnel itself is TLS-encrypted end-to-end with Cloudflare's edge.)

## Deploy

Prereq: the shared `traefik` Docker network exists. (Bring `traefik/` up at least once, or `docker network create traefik --attachable`.)

```bash
docker compose up -d
docker compose logs -f cloudflared    # tail to confirm the tunnel registered
```

The tunnel appears as **Healthy** in the dashboard once the connector handshakes successfully.

## How it works

- cloudflared opens an outbound HTTPS/QUIC connection to Cloudflare's edge. Cloudflare publishes the tunnel's hostnames; visitors hit `https://vllm.example.com`, Cloudflare's edge terminates TLS, and forwards the cleartext request through the tunnel.
- cloudflared (this container) receives the forwarded request and dials the origin URL configured in the dashboard. Because the container is on the `traefik` Docker network, `http://traefik:80` resolves to the Traefik container, which then routes by `Host()` to the right backend.
- No inbound ports on the host. The host's public IP doesn't matter; it doesn't need one.
- Public TLS certs are Cloudflare-managed (real, publicly-trusted). Traefik's internal wildcard is not exposed externally.

## Logs

```bash
docker compose logs -f cloudflared
```

## Upgrade

Bump `CLOUDFLARED_TAG` in `.env`, then:

```bash
docker compose pull
docker compose up -d
```

## Uninstall

```bash
docker compose down
# Also delete the tunnel in the Cloudflare dashboard if you're not reusing it.
```

## See also

- Top-level [README](../README.md)
- [`traefik/`](../traefik/) — local reverse proxy that Cloudflare-tunneled routes flow through
- Cloudflare Tunnel docs: <https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/>
- Connector troubleshooting: <https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/troubleshoot-tunnels/>
