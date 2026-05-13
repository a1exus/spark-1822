# llama-cpp

[llama.cpp](https://github.com/ggml-org/llama.cpp) inference server, GPU-accelerated on the GB10 via CUDA. Serves an [OpenAI-compatible API](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md) and a small web UI at `https://llama.${CADDY_DOMAIN}` (fronted by [`caddy/`](../caddy/)).

Set up as the workaround for Ollama not being able to pull `gpt-oss-safeguard:120b` (upstream issue: ollama/ollama#16121).

## Topology

`llama-cpp` runs as a single container on the shared `caddy` Docker network. It connects only to Caddy; no host port is published.

### GPU exclusivity

`-ngl 999` puts every model layer on GPU and keeps them resident (~65 GiB VRAM for the default model). The GB10 has 124 GiB total, but **Ollama lazily loads its own models on demand into the same VRAM**, so you can't have both engines active at once without one OOMing the other. Hence `restart: "no"` here — this stack is manual-start. To use llama.cpp:

```bash
docker compose -f /opt/open-webui/docker-compose.yml stop ollama
cd /opt/llama-cpp && make up VARIANT=<name>
```

To go back to ollama:

```bash
cd /opt/llama-cpp && make down
docker compose -f /opt/open-webui/docker-compose.yml up -d
```

Three model sources are wired into the container:

| In-container path | Source |
|---|---|
| `/root/.cache/llama.cpp/` | llama.cpp's own download cache (named volume `llama-cpp-cache`, filled via `MODEL_URL`) |
| `/ollama/models/blobs/sha256-<hex>` | Ollama-cached GGUF blobs (external volume `open-webui-ollama`, read-only) |
| `/root/.cache/huggingface/hub/...` | HuggingFace CLI cache on the host, bind-mounted read-only |

The entrypoint picks the model in this order: **`MODEL_PATH`** (any mounted file) → **`MODEL_OLLAMA`** (resolved against the `/ollama` manifest store at start, e.g. `gpt-oss-safeguard:20b`) → **`MODEL_URL`** (downloaded into the cache volume).

## Files

```
llama-cpp/
├── docker-compose.yml
├── entrypoint.sh        # resolves MODEL_OLLAMA → blob path; picks PATH/URL/OLLAMA
├── Makefile             # make up VARIANT=<name> / list / down / logs / ps
├── envs/                # one .env per model variant — pick one with `make up VARIANT=…`
│   ├── README.md
│   └── gpt-oss-safeguard-120b-hf.env
├── .env.example         # common settings (image tag, HF cache, HF token)
└── .env                 # gitignored copy of the above
```

## Configure

`.env` holds settings that don't change with the model (image pin, HF cache, optional HF token). Variant files in `envs/` hold the per-model knobs (model source, alias, context, GPU layers).

```bash
cp .env.example .env
# Edit .env:
#   LLAMACPP_TAG     — pinned image (server-cuda@sha256:…). Multi-arch — works on aarch64+CUDA.
#   HF_CACHE_HOST    — host path holding the HuggingFace CLI cache (default /opt/hf/.cache/huggingface).
#   HF_TOKEN         — only needed for gated/private models.
```

### Pinning the image

The arm64 + CUDA build is published only under the floating `server-cuda` tag. To pin to a specific build by content digest of the multi-arch manifest list:

```bash
TOK=$(curl -s 'https://ghcr.io/token?service=ghcr.io&scope=repository:ggml-org/llama.cpp:pull' | jq -r .token)
curl -sI -H "Authorization: Bearer $TOK" \
    -H 'Accept: application/vnd.docker.distribution.manifest.list.v2+json' \
    'https://ghcr.io/v2/ggml-org/llama.cpp/manifests/server-cuda' \
    | grep -i docker-content-digest
```

Set `LLAMACPP_TAG=server-cuda@<that-digest>` in `.env`.

## Deploy

Prereq: `caddy/` is running and the shared `caddy` network exists.

```bash
make list                                  # show available variants
make up VARIANT=gpt-oss-safeguard-20b      # start that one
make logs                                  # tail
```

Equivalent without Make:

```bash
docker compose --env-file .env --env-file envs/<variant>.env up -d
```

Once healthy, the server is at `https://llama.${CADDY_DOMAIN}`:

- Web UI — open in browser.
- OpenAI-compatible API:
  ```bash
  curl -k https://llama.spark-1822.local/v1/models
  curl -k https://llama.spark-1822.local/v1/chat/completions \
      -H 'Content-Type: application/json' \
      -d '{"model":"gpt-oss-safeguard-120b","messages":[{"role":"user","content":"hello"}]}'
  ```

## Changing the model

Switch to another variant with `make up VARIANT=<name>` (or repeat the `--env-file` invocation). The `llama-cpp-cache` volume preserves previously-downloaded URL-pulled models, so swapping back is fast.

### Adding a new variant from the HuggingFace CLI cache

The host's `/opt/hf/.cache/huggingface/` is mounted read-only at `/root/.cache/huggingface/`. Files downloaded via `huggingface-cli download <repo> <file>` or `hf download <repo> <file>` live at:

```
/root/.cache/huggingface/hub/models--<org>--<repo>/snapshots/<rev>/<file>
```

Create `envs/<name>.env`:

```
MODEL_PATH=/root/.cache/huggingface/hub/models--<org>--<repo>/snapshots/<rev>/<file>.gguf
MODEL_ALIAS=<friendly-name>
CTX_SIZE=8192
N_GPU_LAYERS=999
```

### Adding a new Ollama-backed variant

The mount + resolution stay wired up even though no variant file ships with one. `ollama pull <name>:<tag>` on the host puts the GGUF into the `open-webui-ollama` Docker volume; then drop:

```
MODEL_OLLAMA=<name>:<tag>
MODEL_ALIAS=<friendly-name>
CTX_SIZE=8192
N_GPU_LAYERS=999
```

into `envs/<name>-<tag>.env`. The entrypoint resolves the right blob path at start by reading the Ollama manifest at `/ollama/models/manifests/registry.ollama.ai/library/<name>/<tag>` — no hardcoded digests.

### Adding a URL-downloaded variant

Use `MODEL_URL=<https://…>` instead of `MODEL_PATH`. llama.cpp downloads the file into the `llama-cpp-cache` volume on first start and reuses it after.

## Upgrade

Resolve the current `server-cuda` digest (snippet above), bump `LLAMACPP_TAG` in `.env`, then:

```bash
docker compose pull             # uses .env for LLAMACPP_TAG
make up VARIANT=<name>          # restart on the new image
```

## Logs

```bash
make logs                       # tails llama-cpp
```

## Uninstall

```bash
make down
docker volume rm llama-cpp-cache   # destroys cached model downloads
```

## See also

- Top-level [README](../README.md)
- [`caddy/`](../caddy/) — reverse proxy in front of this server
- llama.cpp server: <https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md>
- Compute capability 12.1 on GB10 is supported by the upstream image — confirmed with `ggml_cuda_init: found 1 CUDA devices`.
