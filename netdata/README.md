# netdata

Real-time observability agent for the host — CPU, memory, disks, network, every Docker container, plus systemd units and a long list of auto-detected applications. UI is fronted by Traefik at `https://netdata.spark-1822.local`.

## Topology

Netdata runs with `network_mode: host` and `pid: host` so it has full visibility into the host's processes, namespaces, and network interfaces. It listens on `0.0.0.0:19999` directly and is also reachable via HTTPS through Traefik (route defined in `traefik/dynamic/services.yml` since `network_mode: host` makes the docker provider unable to attach a Docker network endpoint). No authentication: the dashboard is read-only telemetry on a trusted LAN, and Netdata itself has no built-in local auth. If you need auth, claim the agent in [Netdata Cloud](https://www.netdata.cloud/) (free, supports SSO/MFA) or front it with an OAuth proxy.

## Files

```
netdata/
├── docker-compose.yml
├── .env.example         # committed
└── .env                 # gitignored
```

## Configure

```bash
cp .env.example .env
# Edit .env:
#   NETDATA_TAG       — image tag (`latest` by default; pin to a release for prod)
#   NETDATA_HOSTNAME  — what netdata reports as host name
#   DOCKER_GID        — host's docker-group GID (so netdata can read docker.sock)
#                       getent group docker | cut -d: -f3
```

## Deploy

```bash
docker compose up -d
docker compose ps
curl -fsS http://127.0.0.1:19999/api/v1/info | jq .version
```

Then browse to `https://netdata.spark-1822.local`.

## What it monitors out of the box

- System: CPU, load, RAM, swap, IO, network interfaces, TCP/UDP socket stats, disk space and IO, systemd units, kernel events.
- Docker: every running container's CPU/memory/IO/network (via docker.sock and cgroups).
- Apps: many are auto-detected (Postgres, Redis, NGINX, etc.) when they're running.

## GPU metrics (not yet wired up)

The default agent doesn't expose `nvidia-smi` metrics on the GB10. To add them, bind-mount `/usr/bin/nvidia-smi` (and matching libs) into the container, or run the dedicated [DCGM exporter](https://github.com/NVIDIA/dcgm-exporter) and let Netdata scrape it. Tracked as a follow-up.

## Upgrade

```bash
# Bump NETDATA_TAG in .env, then:
docker compose pull
docker compose up -d
```

## Logs

```bash
docker compose logs -f netdata
```

## Uninstall

```bash
docker compose down
docker volume rm netdata-config netdata-lib netdata-cache
```

## See also

- Top-level [README](../README.md) for overall layout, conventions, and CI.
- Netdata Docker docs: <https://learn.netdata.cloud/docs/installing/docker>
- Netdata configuration reference: <https://learn.netdata.cloud/docs/configuring/daemon-configuration>
