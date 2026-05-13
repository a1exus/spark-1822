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
docker compose -f /opt/vllm/docker-compose.yml up -d

# Going back:
docker compose -f /opt/vllm/docker-compose.yml down
docker compose -f /opt/open-webui/docker-compose.yml up -d
```

## Files

```
vllm/
├── docker-compose.yml
├── .env.example
└── .env                 # gitignored
```

## Configure

```bash
cp .env.example .env
# Edit .env:
#   VLLM_TAG          — pinned image tag (e.g. v0.20.2). Multi-arch — arm64+CUDA works on GB10.
#   VLLM_MODEL        — HuggingFace repo ID, e.g. Qwen/Qwen2.5-7B-Instruct
#   VLLM_SERVED_NAME  — optional override of the model name surfaced via the API
#   VLLM_GPU_MEM      — fraction of VRAM vLLM may use (0.0–1.0)
#   VLLM_MAX_LEN      — max context length
#   HF_CACHE_HOST     — host path holding the HuggingFace CLI cache
#   HF_TOKEN          — only needed for gated/private models
```

## Deploy

Prereq: `caddy/` running, shared `caddy` network exists.

```bash
docker compose up -d
docker compose logs -f vllm   # first run: HF download
```

Once healthy:

```bash
curl -k https://vllm.spark-1822.local/v1/models
curl -k https://vllm.spark-1822.local/v1/chat/completions \
    -H 'Content-Type: application/json' \
    -d '{"model":"Qwen/Qwen2.5-7B-Instruct","messages":[{"role":"user","content":"hello"}]}'
```

## Picking a model

vLLM works best with HF transformers-format models (safetensors). It does **not** load GGUF files like llama.cpp does — for GGUF, use the [`llama-cpp/`](../llama-cpp/) stack.

Some that fit comfortably on the GB10's 124 GiB VRAM:

| Model | Approx VRAM | Notes |
|---|---|---|
| `Qwen/Qwen2.5-7B-Instruct` | ~15 GB | Open, strong general-purpose default |
| `Qwen/Qwen2.5-72B-Instruct` | ~145 GB FP16 → use AWQ/INT4 quant | Larger; needs quantization |
| `meta-llama/Llama-3.1-8B-Instruct` | ~16 GB | Gated — set `HF_TOKEN` |
| `microsoft/Phi-3.5-mini-instruct` | ~8 GB | Small, fast |
| `mistralai/Mistral-7B-Instruct-v0.3` | ~15 GB | Gated |

For larger models use a quantized variant (e.g. `Qwen/Qwen2.5-72B-Instruct-AWQ`) — vLLM supports AWQ, GPTQ, FP8, BitsAndBytes, and a few others. See <https://docs.vllm.ai/en/latest/quantization/supported_hardware.html>.

## Reusing existing HF downloads

The bind-mount at `${HF_CACHE_HOST}` is the standard HuggingFace cache. Anything you've downloaded via `huggingface-cli` / `hf download` on the host is already there and vLLM will use it without re-downloading. The reverse is also true: models vLLM downloads land in that directory and are usable by the `hf` CLI or any other tool that reads `~/.cache/huggingface/`.

## Upgrade

Bump `VLLM_TAG` in `.env`, then:

```bash
docker compose pull
docker compose up -d
```

## Logs

```bash
docker compose logs -f vllm
```

## Uninstall

```bash
docker compose down
# HF cache is on the host (not in a Docker volume) — leave it alone unless you
# also want to delete downloaded weights.
```

## See also

- Top-level [README](../README.md)
- [`caddy/`](../caddy/) — reverse proxy in front of this server
- [`llama-cpp/`](../llama-cpp/) — sibling inference stack for GGUF models
- vLLM docs: <https://docs.vllm.ai/>
