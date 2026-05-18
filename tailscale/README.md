# tailscale

[Tailscale](https://tailscale.com/) sidecar that registers this host as a node on your tailnet and runs [Tailscale Serve](https://tailscale.com/kb/1242/tailscale-serve) to terminate TLS on tailnet `:443` and reverse-proxy all traffic to `http://traefik:80`. Every backend Traefik already routes becomes reachable over the tailnet without opening any host port.

Based on Tailscale's [Connect a Docker container](https://tailscale.com/docs/features/containers/docker/how-to/connect-docker-container) guide, adapted to this repo's conventions (pinned image tag in `.env`, named state volume, traefik network).

## Files

```
tailscale/
├── docker-compose.yml          # tailscale sidecar, joined to the traefik network, Serve config mounted
├── serve.json                  # Tailscale Serve config — TLS on :443, proxy / → http://traefik:80
├── .env.example                # committed; copy to .env and fill in
└── .env                        # not committed (gitignored)
```

## Configure

### 1. Mint an auth key

Tailscale admin console → **Settings → Keys → Generate auth key**. Recommended:

- **Reusable** — yes (re-creating the container doesn't burn the key)
- **Ephemeral** — no (node state persists across restarts)
- **Pre-approved** — yes (skip manual approval)
- **Tags** — e.g. `tag:server` (matches your ACL policy)

### 2. Drop secrets into `.env`

```bash
cp .env.example .env
# Edit .env:
#   TAILSCALE_TAG  — pin the image (see hub.docker.com/r/tailscale/tailscale/tags)
#   TS_AUTHKEY     — the key from step 1
#   TS_HOSTNAME    — tailnet hostname (default: spark-1822)
```

## Deploy

Prereq: the shared `traefik` Docker network exists. (Bring `traefik/` up at least once, or `docker network create traefik --attachable`.)

```bash
docker compose up -d
docker compose logs -f tailscale    # confirm "Success." and the node URL
```

The node appears in the admin console under **Machines**. MagicDNS publishes it at `https://<TS_HOSTNAME>.<tailnet>.ts.net` — any tailnet-connected device can reach it. TLS uses Tailscale's auto-provisioned MagicDNS cert; no client-side root install needed.

## How it works

```
tailnet client  ──(http  on :80 )──>  tailscale  ──(http  )──>  http://traefik:80
                                                                       │
                                                                       │ web entrypoint
                                                                       │ 308 → https
                                                                       ▼
tailnet client  ──(https on :443)──>  tailscale  ──(https-insecure)──> https://traefik:443
                                                                       │
                                                                       │ Host header routing
                                                                       ▼
                                                                   backend (vllm / open-webui / netdata / ...)
```

- The Tailscale daemon runs in userspace mode (no `/dev/net/tun`, no privileged caps) and registers as one node on your tailnet using `TS_AUTHKEY`.
- [Tailscale Serve](https://tailscale.com/kb/1242/tailscale-serve) is configured via the mounted `serve.json`. The container substitutes `${TS_CERT_DOMAIN}` with the node's MagicDNS hostname at startup, then exposes two listeners:
  - **`:80` plain HTTP**, proxied to `http://traefik:80`. Traefik's `web` entrypoint then 308-redirects to HTTPS. The redirect's `Location` header preserves the tailnet `Host`, so the client follows back to the `:443` listener below — one extra hop on first request, then HTTPS the rest of the way.
  - **`:443` HTTPS**, with TLS terminated using the publicly-trusted MagicDNS cert, proxied to `https-insecure://traefik:443`. The `-insecure` modifier skips Traefik's wildcard-cert verification (the inner connection is over the trusted `traefik` Docker network, container-to-container — no external attacker reachable). Traefik's `websecure` entrypoint terminates the inner TLS with its own wildcard and routes by Host header.
- Why not just proxy `:443` to `http://traefik:80`? Because Traefik would see plain HTTP on its `web` entrypoint and 308-redirect — sending the client back through Tailscale `:443` → http://traefik:80 → 308 again → infinite loop. `https-insecure://traefik:443` lands directly on `websecure` and avoids the redirect entirely.
- State (node key, machine identity) lives in a named docker volume `tailscale-state`, not under `/opt` — so the host's git working tree stays free of secrets.

### Host-header routing — applied

Tailscale Serve forwards requests with the **original** Host header. Each Traefik router uses a single `HostRegexp` matcher pinned to its per-service subdomain — `<svc>.spark*.<domain>` — which accepts both the LAN form (`vllm.spark-1822.local`) and any per-service tailnet form a [Tailscale HTTPS subdomain](https://tailscale.com/kb/1153/enabling-https) can present (`vllm.spark-1822.<tailnet>.ts.net`).

```yaml
# example, open-webui/docker-compose.yml
- "traefik.http.routers.open-webui.rule=HostRegexp(`open-webui.spark{x:.+}`)"
```

Six routers, one per service — `ollama`, `open-webui`, `vllm`, `llama` (label-based in each app's compose), plus `netdata` and `traefik` (file-based in `traefik/dynamic/services.yml`).

**Bare tailnet host → Traefik dashboard.** A request whose Host header is `spark-1822.<tailnet>.ts.net` (the form Tailscale Serve forwards by default — Tailscale Serve only knows about the node's own MagicDNS hostname) lands on the **Traefik dashboard**. The dashboard router in `traefik/dynamic/services.yml` is the only one that carries a second `HostRegexp(`spark{x:.+}`)` matcher; every other router stays pinned to its own `<svc>.spark*` subdomain. So `https://spark-1822.<tailnet>.ts.net/` opens the dashboard, and the rest of the backends (`vllm`, `llama`, `ollama`, `open-webui`, `netdata`) are LAN-only — Tailscale Serve doesn't support per-service hostnames on a single node, and we chose not to set up port-based dispatch or run one tailscale container per backend.

### VIP Service (`svc:spark`)

A Tailscale [VIP Service](https://tailscale.com/kb/1417/services) is a separate tailnet entity from the node — it has its own MagicDNS name (e.g. `spark.<tailnet>.ts.net`) and its own cert. Nodes opt in to host a service. We use `svc:spark` as a secondary entry point that, like the node hostname, lands on Traefik.

Services config lives in [`services.json`](services.json) (not `serve.json` — different file, different schema; see [Tailscale Services configuration file](https://tailscale.com/kb/1589/tailscale-services-configuration-file)). Because we apply it with `--service=svc:spark`, the file uses the **single-service** form (`ServiceDetailsFile`) — flat `version` + `endpoints`, no outer `services` wrapper:

```json
{
  "version": "0.0.1",
  "endpoints": {
    "tcp:80":  "http://traefik:80",
    "tcp:443": "https-insecure://traefik:443"
  }
}
```

Two steps to make the node advertise it (state lives in the `tailscale-state` docker volume — survives restarts; not in the committed compose because `svc:spark` is tailnet-specific):

```bash
# 1. load the endpoints config
docker compose cp services.json tailscale:/config/services.json
docker compose exec tailscale tailscale serve set-config --service=svc:spark /config/services.json

# 2. tell the daemon to advertise the service
docker compose exec tailscale tailscale serve advertise svc:spark
```

To stop advertising:

```bash
docker compose exec tailscale tailscale serve drain svc:spark    # gradually stop accepting new traffic
docker compose exec tailscale tailscale serve clear svc:spark    # forget the config entirely
```

## Logs

```bash
docker compose logs -f tailscale
```

The "Success." line confirms the node is logged in. `tailscale status` inside the container shows peers:

```bash
docker exec tailscale tailscale status
```

## Upgrade

Bump `TAILSCALE_TAG` in `.env`, then:

```bash
docker compose pull
docker compose up -d
```

## Uninstall

```bash
docker compose down
docker volume rm tailscale-state    # also discard the node key + machine state
```

Then delete the node from the Tailscale admin console under **Machines** if you're not reusing it.

## Hardening / industry-standard follow-ups

What's shipped is the minimum that works. Four deferred items move this from "homelab-grade" to what Tailscale's own production guides recommend. Each is independently applicable.

### 1. Auth secret via file mount (not env var)

Today `TS_AUTHKEY` is read from `.env` and exposed in the container's environment — visible to anyone who can `docker inspect` the container. Tailscale's `containerboot` supports a file indirection that keeps the secret off the process env: set `TS_AUTHKEY=file:/run/secrets/ts_authkey` (or `TS_AUTHKEY_FILE=/run/secrets/ts_authkey`) and mount the file via a compose `secrets:` block.

Migration sketch (base `docker-compose.yml`):

```yaml
services:
  tailscale:
    environment:
      - TS_AUTHKEY=file:/run/secrets/ts_authkey   # was: TS_AUTHKEY=${TS_AUTHKEY:?…}
    secrets:
      - ts_authkey

secrets:
  ts_authkey:
    file: ./ts_authkey                            # host-local file, mode 0600, gitignored
```

Tradeoff: one extra file on disk to manage (and rotate). Same threat model as `.env` in practice on this single-host setup, but it's the conventional pattern.

### 2. OAuth client credentials instead of a static auth key

Auth keys are accepted but discouraged for persistent nodes — they expire (90-day max), and rotation is manual toil. The recommended pattern for long-running infrastructure is OAuth client credentials: mint an OAuth client in the admin console (**Settings → OAuth clients**), give it the `devices:write` scope and the `tag:server` tag, and use the resulting `tskey-client-...` token. `containerboot` exchanges it for an ephemeral auth key on every restart — no rotation needed.

```bash
# .env
TS_AUTHKEY=tskey-client-<your-oauth-client-secret>?preauthorized=true&ephemeral=false
```

Tradeoff: one-time setup cost in the dashboard. Bigger lift than (1) — this is a real provisioning decision, not just a refactor.

### 3. Advertise an ACL tag

Without `--advertise-tags`, this node inherits the *minting user's* identity in the Tailscale ACL graph. That works, but it means ACL rules can't distinguish "Dmitry's laptop" from "the inference server" — every device under the same user is treated the same.

Idiomatic fix:

```bash
# .env
TS_EXTRA_ARGS=--advertise-tags=tag:server
```

And in the tailnet ACL JSON:

```json
{
  "tagOwners": {
    "tag:server": ["autogroup:admin"]
  }
}
```

Required if you later want rules like *"only `tag:client` may reach `tag:server:443`"*. OAuth clients (option 2) typically mint pre-tagged keys, so this combines naturally with (2).

### 4. Kernel networking mode

The base file runs in userspace mode (`TS_USERSPACE=true`). Works without elevated privileges, but every packet goes through a userspace TCP stack — meaningful throughput penalty on a busy node. For an inference host fronting LLM endpoints, kernel mode is the production setting.

```yaml
# docker-compose.yml diff
services:
  tailscale:
    environment:
      - TS_USERSPACE=false      # was: true
    devices:
      - /dev/net/tun:/dev/net/tun
    cap_add:
      - net_admin
      - net_raw
```

Tradeoff: requires `/dev/net/tun` on the host (true on stock Ubuntu) and the two capabilities. Required to use this node as a subnet router or exit node, which userspace mode can't do either way.

### Priority

Recommended baseline: **1 + 3 + 4** as a single hardening pass. **2 (OAuth)** is the biggest improvement but it's a provisioning decision, not a config refactor — promote it whenever the next auth key would otherwise need renewing.

## See also

- Top-level [README](../README.md)
- [`traefik/`](../traefik/) — the proxy this sidecar fronts
- [`cloudflare/`](../cloudflare/) — the other edge-ingress stack in this repo, structurally analogous (also tunnels into traefik over an outbound-only connection)
- Tailscale Docker guide: <https://tailscale.com/docs/features/containers/docker/how-to/connect-docker-container>
- Tailscale Serve docs: <https://tailscale.com/kb/1242/tailscale-serve>
- Tailscale OAuth clients: <https://tailscale.com/kb/1215/oauth-clients>
- Tailscale ACL tags: <https://tailscale.com/kb/1068/acl-tags>
