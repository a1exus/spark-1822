# llama-cpp

[llama.cpp](https://github.com/ggml-org/llama.cpp) inference server, GPU-accelerated on the GB10 via CUDA. Serves an [OpenAI-compatible API](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md) and a small web UI at `https://llama.${CADDY_DOMAIN}` (fronted by [`caddy/`](../caddy/)).

Set up as the workaround for Ollama not being able to pull `gpt-oss-safeguard:120b` (upstream issue: ollama/ollama#16121).

## Supported model formats

- **GGUF only.** The single input format llama.cpp's server can load directly. Single-file or multi-part split GGUF (the model in `envs/gpt-oss-safeguard-120b-hf.env` is a 2-file split — llama.cpp opens the first file and picks the second up by naming convention).
- **Not supported as direct inputs:** HuggingFace `safetensors`, PyTorch `.bin`, ONNX, ggml v1/v2 (legacy).
- **HF safetensors models can be converted to GGUF** with [`convert_hf_to_gguf.py`](https://github.com/ggml-org/llama.cpp/blob/master/convert_hf_to_gguf.py) shipped in the llama.cpp repo. The 4 safetensors models in this host's HF cache (`openai/gpt-oss-120b`, `openai/gpt-oss-20b`, `Qwen/Qwen3.6-27B`, `Jackrong/Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled`) are **not** loaded as-is — convert first, or pull a ready-made GGUF (look on HF for `<author>/<repo>-GGUF` published by `bartowski`, `lmstudio-community`, `unsloth`, etc.).
- **Quantization formats supported inside GGUF**: `Q2_K`–`Q8_0`, `F16`, `F32`, `IQ*`, OpenAI's `MXFP4`, and others. See <https://github.com/ggml-org/llama.cpp/blob/master/examples/quantize/README.md>.
- **Architecture support** is broad and tracked here: <https://github.com/ggml-org/llama.cpp#description> (search the README for the list of supported model families).

## Topology

`llama-cpp` runs as a single container on the shared `caddy` Docker network. Caddy reaches it over that network for external traffic. The container also publishes its API on the host's loopback interface at `127.0.0.1:8080` for direct host-side curl/benchmarks — not reachable from the LAN. Set `HOST_PORT=<n>` in the variant file if 8080 is taken.

### GPU exclusivity

`-ngl 999` puts every model layer on GPU and keeps them resident (~65 GiB VRAM for the default model). The GB10 has 124 GiB total, but **Ollama lazily loads its own models on demand into the same VRAM**, so you can't have both engines active at once without one OOMing the other. Hence `restart: "no"` here — this stack is manual-start. To use llama.cpp:

```bash
docker compose -f /opt/open-webui/docker-compose.yml stop ollama
cd /opt/llama-cpp && make up ENV=<name>
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
├── Makefile             # make list / make up ENV=<name>
├── envs/                # one .env per model variant — pick one with `make up ENV=…`
│   ├── Makefile         # list / remote / sync / stale against the host's GGUF caches
│   ├── README.md
│   └── gpt-oss-safeguard-120b-hf.env
└── .env.example         # reference template showing every variable
```

## Configure

Each `envs/<name>.env` is **self-contained** — it has the image pin, HF cache path, HF token, model source, alias, context, and GPU layers in one file. `make up ENV=<name>` invokes `docker compose --env-file envs/<name>.env up -d` directly — no rolling `.env` is written. For subsequent commands, pass the same `--env-file` to docker compose, or use plain `docker` against the container name:

```bash
docker compose --env-file envs/<name>.env ps
docker logs -f llama-cpp
docker stop llama-cpp
```

`.env.example` is a reference template showing every variable; you don't need to edit it.

### Pinning the image

The arm64 + CUDA build is published only under the floating `server-cuda` tag. To pin to a specific build by content digest of the multi-arch manifest list:

```bash
TOK=$(curl -s 'https://ghcr.io/token?service=ghcr.io&scope=repository:ggml-org/llama.cpp:pull' | jq -r .token)
curl -sI -H "Authorization: Bearer $TOK" \
    -H 'Accept: application/vnd.docker.distribution.manifest.list.v2+json' \
    'https://ghcr.io/v2/ggml-org/llama.cpp/manifests/server-cuda' \
    | grep -i docker-content-digest
```

Set `LLAMACPP_TAG=server-cuda@<that-digest>` in the variant file (`envs/<name>.env`).

## Deploy

Prereq: `caddy/` is running and the shared `caddy` network exists.

```bash
make list                                  # show available variants
make up ENV=gpt-oss-safeguard-120b-hf      # start that one
docker logs -f llama-cpp                   # tail (first run downloads the model)
```

Equivalent without Make:

```bash
docker compose --env-file envs/<variant>.env up -d
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

Switch to another variant with `make up ENV=<name>` (or `docker compose --env-file envs/<name>.env up -d`). The `llama-cpp-cache` volume preserves previously-downloaded URL-pulled models, so swapping back is fast.

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

Resolve the current `server-cuda` digest (snippet above), bump `LLAMACPP_TAG` in the variant file (`envs/<name>.env`), then:

```bash
docker compose --env-file envs/<name>.env pull   # resolve image tag from the variant
make up ENV=<name>                                # restart on the new image
```

## Logs

```bash
docker logs -f llama-cpp                           # plain docker, no env needed
docker compose --env-file envs/<name>.env logs -f llama-cpp   # equivalent via compose
```

## Uninstall

```bash
docker compose --env-file envs/<name>.env down
docker volume rm llama-cpp-cache   # destroys cached model downloads
```

## See also

- Top-level [README](../README.md)
- [`caddy/`](../caddy/) — reverse proxy in front of this server
- llama.cpp server: <https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md>
- Compute capability 12.1 on GB10 is supported by the upstream image — confirmed with `ggml_cuda_init: found 1 CUDA devices`.
