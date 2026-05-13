# llama-cpp

[llama.cpp](https://github.com/ggml-org/llama.cpp) inference server, GPU-accelerated on the GB10 via CUDA. Serves an [OpenAI-compatible API](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md) and a small web UI at `https://llama.${CADDY_DOMAIN}` (fronted by [`caddy/`](../caddy/)).

Set up as the workaround for Ollama not being able to pull `gpt-oss-safeguard:120b` (upstream issue: ollama/ollama#16121).

## Topology

`llama-cpp` runs as a single container on the shared `caddy` Docker network. It connects only to Caddy; no host port is published.

### GPU exclusivity

`-ngl 999` puts every model layer on GPU and keeps them resident (~65 GiB VRAM for the default model). The GB10 has 124 GiB total, but **Ollama lazily loads its own models on demand into the same VRAM**, so you can't have both engines active at once without one OOMing the other. Hence `restart: "no"` here — this stack is manual-start. To use llama.cpp:

```bash
docker compose -f /opt/open-webui/docker-compose.yml stop ollama
docker compose -f /opt/llama-cpp/docker-compose.yml up -d
```

To go back to ollama:

```bash
docker compose -f /opt/llama-cpp/docker-compose.yml down
docker compose -f /opt/open-webui/docker-compose.yml up -d
```

Three model sources are wired up read-only into the container so existing downloads can be reused:

| In-container path | Source |
|---|---|
| `/root/.cache/llama.cpp/` | llama.cpp's own download cache (named volume `llama-cpp-cache`) |
| `/ollama/models/blobs/sha256-<hex>` | Ollama-cached GGUF blobs (external volume `open-webui-ollama`, read-only) |
| `/root/.cache/huggingface/hub/...` | HuggingFace CLI cache on the host, bind-mounted read-only |

The entrypoint picks the model based on env vars: `MODEL_PATH` (a local file path inside the container) wins if set, otherwise it falls back to `MODEL_URL` (downloaded into `/root/.cache/llama.cpp/`).

## Files

```
llama-cpp/
├── docker-compose.yml
├── entrypoint.sh         # selects MODEL_PATH or MODEL_URL
├── .env.example
└── .env                  # gitignored
```

## Configure

```bash
cp .env.example .env
# Edit .env:
#   LLAMACPP_TAG     — pinned image (server-cuda@sha256:...). Multi-arch; works on aarch64+CUDA.
#   MODEL_PATH       — local file inside the container (Ollama blob, HF snapshot, anything mounted). Wins if set.
#   MODEL_URL        — remote URL; llama.cpp downloads into the llama-cpp-cache volume.
#   MODEL_ALIAS      — name surfaced via the OpenAI-compatible API.
#   CTX_SIZE         — context window (default 8192)
#   N_GPU_LAYERS     — layers on GPU (999 = all)
#   HF_CACHE_HOST    — host path holding the HuggingFace CLI cache (default /home/alexus/.cache/huggingface).
#   HF_TOKEN         — only needed for gated/private models
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
docker compose up -d
docker compose logs -f llama-cpp   # first run: HF download (can be many GB / minutes)
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

Edit `MODEL_PATH` (preferred) or `MODEL_URL` in `.env`, plus `MODEL_ALIAS`, then:

```bash
docker compose up -d
```

The cache volume preserves previously-downloaded files, so swapping back to a URL-pulled model is fast.

### Use a model Ollama already has

Ollama's volume is mounted at `/ollama:ro` inside the container. The GGUF for any pulled model is one of its blobs — specifically the layer with mediaType `application/vnd.ollama.image.model`. Find the blob path for a model:

```bash
docker run --rm -v open-webui-ollama:/data:ro -v ./tools:/tools:ro alpine sh -c '
    apk add -q jq >/dev/null
    jq -r ".layers[] | select(.mediaType==\"application/vnd.ollama.image.model\") | .digest" \
        /data/models/manifests/registry.ollama.ai/library/MODEL/TAG \
        | sed "s|sha256:|/ollama/models/blobs/sha256-|"
'
```

For example, after `ollama pull gpt-oss-safeguard:20b`:

```bash
docker run --rm -v open-webui-ollama:/data:ro alpine sh -c '
    apk add -q jq >/dev/null
    jq -r ".layers[] | select(.mediaType==\"application/vnd.ollama.image.model\") | .digest" \
        /data/models/manifests/registry.ollama.ai/library/gpt-oss-safeguard/20b \
        | sed "s|sha256:|/ollama/models/blobs/sha256-|"
'
# → /ollama/models/blobs/sha256-c4016c9e54d0a9218b5911790579e58284a9ed57c48b7e87607125c6307f9da1
```

Set that path as `MODEL_PATH` in `.env`:

```
MODEL_PATH=/ollama/models/blobs/sha256-c4016c9e54d0a9218b5911790579e58284a9ed57c48b7e87607125c6307f9da1
MODEL_ALIAS=gpt-oss-safeguard-20b
```

List Ollama-cached models with:

```bash
docker run --rm -v open-webui-ollama:/data:ro alpine \
    find /data/models/manifests/registry.ollama.ai/library -mindepth 2 -type f \
    -printf '%P\n'
```

### Use a model already downloaded by the HuggingFace CLI

The host's `~/.cache/huggingface/` is mounted read-only at `/root/.cache/huggingface/`. Files downloaded via `huggingface-cli download <repo> <file>` or `hf download <repo> <file>` live at:

```
/root/.cache/huggingface/hub/models--<org>--<repo>/snapshots/<rev>/<file>
```

Point `MODEL_PATH` at the actual file path inside that snapshots directory.

## Upgrade

Resolve the current `server-cuda` digest (snippet above), bump `LLAMACPP_TAG` in `.env`, then:

```bash
docker compose pull
docker compose up -d
```

## Logs

```bash
docker compose logs -f llama-cpp
```

## Uninstall

```bash
docker compose down
docker volume rm llama-cpp-cache   # destroys cached model downloads
```

## See also

- Top-level [README](../README.md)
- [`caddy/`](../caddy/) — reverse proxy in front of this server
- llama.cpp server: <https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md>
- Compute capability 12.1 on GB10 is supported by the upstream image — confirmed with `ggml_cuda_init: found 1 CUDA devices`.
