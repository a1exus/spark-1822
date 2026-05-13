# vllm

[vLLM](https://github.com/vllm-project/vllm) inference server. Serves an [OpenAI-compatible API](https://docs.vllm.ai/en/latest/serving/openai_compatible_server.html) at `https://vllm.${CADDY_DOMAIN}` (fronted by [`caddy/`](../caddy/)).

vLLM complements [`llama-cpp/`](../llama-cpp/): use llama.cpp for GGUF files (smaller, CPU-friendly quantizations), vLLM for HF-native models (safetensors) and high-throughput serving with continuous batching + PagedAttention.

> ⚠️ **Not yet smoke-tested on this host.** vLLM's published support matrix doesn't list compute capability 12.1 (GB10). The image multi-arch index includes arm64, but the first `docker compose up -d` here may fail if sm_120 CUDA kernels aren't compiled in. If it works, leave this note alone; if it doesn't, expect to build vLLM from source or wait for upstream support.

## Supported model formats

- **HuggingFace transformers format.** vLLM loads `safetensors` (preferred) and PyTorch `.bin` directly by repo ID. All 4 models cached on this host (`openai/gpt-oss-120b`, `openai/gpt-oss-20b`, `Qwen/Qwen3.6-27B`, `Jackrong/Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled`) are this format.
- **Not supported as direct inputs:** GGUF (use [`llama-cpp/`](../llama-cpp/) for those), ONNX, custom TensorRT engines.
- **Quantization formats supported on Hopper/Blackwell-class GPUs:** AWQ, GPTQ, FP8, INT4, BitsAndBytes, and a few more. Full hardware/format compatibility chart: <https://docs.vllm.ai/en/latest/quantization/supported_hardware.html>.
- **Supported architectures** (model families like Llama, Qwen, Mistral, GPT-OSS, DeepSeek, Phi, Gemma, …) are listed here: <https://docs.vllm.ai/en/latest/models/supported_models.html>.

## Topology

Single container on the shared `caddy` Docker network; no host port published. The host's HuggingFace cache is bind-mounted read-write so vLLM and the `hf` CLI share the same downloads. Models come from HuggingFace by repo ID — vLLM loads safetensors directly.

### GPU exclusivity

`--gpu-memory-utilization 0.9` (default) reserves ~90% of VRAM at startup. The GB10 has 124 GiB total; Ollama and `llama-cpp/` also want VRAM, so vLLM can't coexist with either of them active. Hence `restart: "no"` here — manual-start.

```bash
# Switching from ollama to vllm:
docker compose -f /opt/open-webui/docker-compose.yml stop ollama
cd /opt/vllm && make up ENV=<name>

# Going back:
cd /opt/vllm && make down
docker compose -f /opt/open-webui/docker-compose.yml up -d
```

## Files

```
vllm/
├── docker-compose.yml
├── Makefile             # make up ENV=<name> / list / down / logs / ps
├── envs/                # one .env per model variant
│   ├── Makefile         # list / remote / sync / stale against the host's HF cache
│   ├── README.md
│   ├── gpt-oss-120b.env
│   ├── gpt-oss-20b.env
│   ├── qwen3.5-27b-reasoning.env
│   └── qwen3.6-27b.env
├── .env.example         # common settings (image tag, HF cache, HF token)
└── .env                 # gitignored copy of the above
```

## Configure

Each `envs/<name>.env` is **self-contained** — image pin, HF cache, HF token, model spec, served name, GPU memory, and max context all in one file. `make up ENV=<name>` copies it over the project's `.env`, after which plain `docker compose ps / logs / down / pull` work without extra flags.

`.env.example` is a reference template showing every variable; you don't need to edit it.

## Deploy

Prereq: `caddy/` running, shared `caddy` network exists.

```bash
make list                                # show available variants
make up ENV=qwen3.5-27b-reasoning    # start that one
make logs                                # tail
```

Equivalent without Make:

```bash
cp envs/<variant>.env .env
docker compose up -d
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
make up ENV=<name>          # restart on the new image
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
