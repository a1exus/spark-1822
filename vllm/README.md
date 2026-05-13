# vllm

[vLLM](https://github.com/vllm-project/vllm) inference server. Serves an [OpenAI-compatible API](https://docs.vllm.ai/en/latest/serving/openai_compatible_server.html) at `https://vllm.${CADDY_DOMAIN}` (fronted by [`caddy/`](../caddy/)).

vLLM complements [`llama-cpp/`](../llama-cpp/): use llama.cpp for GGUF files (smaller, CPU-friendly quantizations), vLLM for HF-native models (safetensors) and high-throughput serving with continuous batching + PagedAttention.

> ⚠️ **Not yet smoke-tested on this host.** vLLM's published support matrix doesn't list compute capability 12.1 (GB10). The image multi-arch index includes arm64, but the first `docker compose up -d` here may fail if sm_120 CUDA kernels aren't compiled in. If it works, leave this note alone; if it doesn't, expect to build vLLM from source or wait for upstream support.

## Topology

Single container on the shared `caddy` Docker network; no host port published. The host's HuggingFace cache is bind-mounted read-write so vLLM and the `hf` CLI share the same downloads. Models come from HuggingFace by repo ID — vLLM loads safetensors directly.

### GPU exclusivity

`--gpu-memory-utilization 0.9` (default) reserves ~90% of VRAM at startup. The GB10 has 124 GiB total; Ollama and `llama-cpp/` also want VRAM, so vLLM can't coexist with either of them active. Hence `restart: "no"` here — manual-start.

```bash
# Switching from ollama to vllm:
docker compose -f /opt/open-webui/docker-compose.yml stop ollama
cd /opt/vllm && make up VARIANT=<name>

# Going back:
cd /opt/vllm && make down
docker compose -f /opt/open-webui/docker-compose.yml up -d
```

## Files

```
vllm/
├── docker-compose.yml
├── Makefile             # make up VARIANT=<name> / list / down / logs / ps
├── envs/                # one .env per model variant
│   ├── README.md
│   ├── gpt-oss-120b.env
│   └── qwen3.5-27b-reasoning.env
├── .env.example         # common settings (image tag, HF cache, HF token)
└── .env                 # gitignored copy of the above
```

## Configure

`.env` holds settings that don't change with the model (image pin, HF cache, optional HF token). Variant files in `envs/` hold the per-model knobs.

```bash
cp .env.example .env
# Edit .env:
#   VLLM_TAG          — pinned image tag (e.g. v0.20.2).
#   HF_CACHE_HOST     — host path holding the HuggingFace CLI cache.
#   HF_TOKEN          — only needed for gated/private models.
```

## Deploy

Prereq: `caddy/` running, shared `caddy` network exists.

```bash
make list                                # show available variants
make up VARIANT=qwen3.5-27b-reasoning    # start that one
make logs                                # tail
```

Equivalent without Make:

```bash
docker compose --env-file .env --env-file envs/<variant>.env up -d
docker compose logs -f vllm        # first run: HF download
```

Once healthy:

```bash
curl -k https://vllm.spark-1822.local/v1/models
curl -k https://vllm.spark-1822.local/v1/chat/completions \
    -H 'Content-Type: application/json' \
    -d '{"model":"qwen3.5-27b-reasoning","messages":[{"role":"user","content":"hello"}]}'
```

## Adding a new variant

vLLM works best with HF transformers-format models (safetensors). It does **not** load GGUF files like llama.cpp does — for GGUF, use the [`llama-cpp/`](../llama-cpp/) stack.

To add a model, download it into the host's HF cache first (so the first `make up` doesn't hang on a long download):

```bash
hf download <org>/<repo>            # lands in /opt/hf/.cache/huggingface/
```

Then drop a new file at `envs/<name>.env`:

```
VLLM_MODEL=<org>/<repo>
VLLM_SERVED_NAME=<friendly-name>
VLLM_GPU_MEM=0.9
VLLM_MAX_LEN=8192
```

For larger models, use a quantized variant (e.g. `Qwen/Qwen2.5-72B-Instruct-AWQ`) — vLLM supports AWQ, GPTQ, FP8, BitsAndBytes, and a few others. See <https://docs.vllm.ai/en/latest/quantization/supported_hardware.html>.

## Reusing existing HF downloads

The bind-mount at `${HF_CACHE_HOST}` is the standard HuggingFace cache. Anything you've downloaded via `huggingface-cli` / `hf download` on the host is already there and vLLM will use it without re-downloading. The reverse is also true: models vLLM downloads land in that directory and are usable by the `hf` CLI or any other tool that reads `~/.cache/huggingface/`.

## Upgrade

Bump `VLLM_TAG` in `.env`, then:

```bash
docker compose pull             # uses .env for VLLM_TAG
make up VARIANT=<name>          # restart on the new image
```

## Logs

```bash
make logs                       # tails vllm
```

## Uninstall

```bash
make down
# HF cache is on the host (not in a Docker volume) — leave it alone unless you
# also want to delete downloaded weights.
```

## See also

- Top-level [README](../README.md)
- [`caddy/`](../caddy/) — reverse proxy in front of this server
- [`llama-cpp/`](../llama-cpp/) — sibling inference stack for GGUF models
- vLLM docs: <https://docs.vllm.ai/>
