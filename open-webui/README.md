# open-webui

Self-hosted [Open WebUI](https://github.com/open-webui/open-webui) backed by [Ollama](https://github.com/ollama/ollama). Two-container stack — `ollama` (GPU, internal-only) and `open-webui` (UI, internal-only, exposed via [Caddy](../caddy/)).

Adapted from NVIDIA's official playbook: <https://build.nvidia.com/spark/open-webui/instructions>. Diverges in four ways: services are split (instead of the bundled `:ollama` image), images are version-pinned via `.env`, secrets live in `.env`, and the UI is fronted by Caddy on HTTPS instead of being published directly on `:8080`.

## Files

```
open-webui/
├── docker-compose.yml
├── .env.example         # committed
└── .env                 # gitignored
```

## Configure

```bash
cp .env.example .env
# Edit .env:
#   OLLAMA_TAG         — Ollama image tag (e.g. 0.23.2)
#   OPEN_WEBUI_TAG     — Open WebUI image tag (e.g. v0.9.5)
#   WEBUI_SECRET_KEY   — generate with: openssl rand -hex 32  (REQUIRED)
#   WEBUI_AUTH         — true (require login) or false (open)
#   ENABLE_SIGNUP      — true initially; flip to false after admin registers
#   OLLAMA_KEEP_ALIVE  — "5m" (default) / "-1" (forever) / "0" (unload now)
```

## Deploy

Prereq: the shared `caddy` external network must exist and [Caddy](../caddy/) must be running.

```bash
docker compose up -d
docker compose ps
```

Open WebUI is then reachable at `https://open-webui.${CADDY_DOMAIN}`. The first user to register becomes admin; after that, set `ENABLE_SIGNUP=false` in `.env` and re-run `docker compose up -d` to lock it down.

The Ollama API is also exposed directly via Caddy at `https://ollama.${CADDY_DOMAIN}` so other tools (Aider, Continue, LiteLLM, the `ollama` CLI with `OLLAMA_HOST`, …) can use it without going through the WebUI:

```bash
curl -k https://ollama.spark-1822.local/api/version
curl -k https://ollama.spark-1822.local/api/tags
OLLAMA_HOST=https://ollama.spark-1822.local ollama list
```

No auth: trusted-LAN posture, same rationale as Netdata. Note that the Ollama REST API includes destructive endpoints (delete model, pull arbitrary model); anyone on the LAN can use them.

## Pull models

```bash
docker compose exec ollama ollama pull llama3.2
docker compose exec ollama ollama list
```

Browse the [Ollama library](https://ollama.com/library) for more.

## Upgrade

Bump `OLLAMA_TAG` / `OPEN_WEBUI_TAG` in `.env`, then:

```bash
docker compose pull
docker compose up -d
```

## Logs

```bash
docker compose logs -f open-webui
docker compose logs -f ollama
```

## Uninstall

```bash
docker compose down
docker volume rm open-webui open-webui-ollama   # destroys data and models
```

## See also

- Top-level [README](../README.md)
- [`caddy/`](../caddy/) — TLS-terminating reverse proxy in front of this UI
- Open WebUI docs: <https://docs.openwebui.com/>
- Ollama docs: <https://github.com/ollama/ollama/blob/main/docs/README.md>
