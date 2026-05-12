# sparky

Configuration for the NVIDIA DGX Spark workstation `spark-1822` (Ubuntu, aarch64, GB10 GPU).

## Layout

```
.
├── open-webui/          # Open WebUI + Ollama docker-compose stack
│   ├── docker-compose.yml
│   ├── .env.example
│   └── .env             # not committed — copy from .env.example
└── README.md
```

Files in this repo correspond to `/opt/<name>/` on the host. Workflow: edit here, `scp` to the host (or sync via your tool of choice), then `docker compose up -d` on the host.

## Host

| | |
|---|---|
| Hostname | `spark-1822.local` |
| OS | Ubuntu (kernel `6.17.0-nvidia`), aarch64 |
| GPU | NVIDIA GB10 |
| Docker | 29.x + Compose v2 |
| GPU runtime | `nvidia-container-toolkit` 1.19 (CDI mode) |

## open-webui

Self-hosted [Open WebUI](https://github.com/open-webui/open-webui) backed by [Ollama](https://github.com/ollama/ollama). Two-container stack: `ollama` (GPU, internal only) + `open-webui` (UI, published on `:8080`).

Adapted from NVIDIA's official playbook: <https://build.nvidia.com/spark/open-webui/instructions>. Diverges in three ways: services are split (instead of the bundled `:ollama` image), images are version-pinned, and secrets/config live in `.env`.

### Deploy

```bash
# On the host, first time:
cd /opt/open-webui
cp .env.example .env
# Edit .env — set WEBUI_SECRET_KEY (openssl rand -hex 32)
docker compose up -d
docker compose ps
```

Open WebUI is then reachable at `http://spark-1822.local:8080`. The first user to register becomes admin; after that, set `ENABLE_SIGNUP=false` in `.env` and re-run `docker compose up -d` to lock it down.

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
- Image tags are pinned to specific versions — no `:latest`.
- Services bind to the host network only via explicit `ports:` entries; everything else stays on the internal compose network.
