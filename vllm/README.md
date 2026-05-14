# vllm

[vLLM](https://github.com/vllm-project/vllm) inference server. Serves an [OpenAI-compatible API](https://docs.vllm.ai/en/latest/serving/openai_compatible_server.html) at `https://vllm.${CADDY_DOMAIN}` (fronted by [`caddy/`](../caddy/)).

vLLM complements [`llama-cpp/`](../llama-cpp/): use llama.cpp for GGUF files (smaller, CPU-friendly quantizations), vLLM for HF-native models (safetensors) and high-throughput serving with continuous batching + PagedAttention.

Smoke-tested on GB10 (compute capability 12.1) with `Qwen/Qwen3.6-27B` at `--max-model-len 65536`: model loads on the GPU, the OpenAI-compatible API serves `/v1/chat/completions`, and tool-calling (`--tool-call-parser qwen3_xml`) returns a populated `tool_calls` structure for a single-function request. `gpt-oss-*` variants still fail at startup because the bundled `openai-harmony` in `vllm/vllm-openai:v0.20.2` fetches a vocab file from a URL that 404s upstream — unrelated to GB10 / sm_120.

## Supported model formats

- **HuggingFace transformers format.** vLLM loads `safetensors` (preferred) and PyTorch `.bin` directly by repo ID. All 4 models cached on this host (`openai/gpt-oss-120b`, `openai/gpt-oss-20b`, `Qwen/Qwen3.6-27B`, `Jackrong/Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled`) are this format.
- **Not supported as direct inputs:** GGUF (use [`llama-cpp/`](../llama-cpp/) for those), ONNX, custom TensorRT engines.
- **Quantization formats supported on Hopper/Blackwell-class GPUs:** AWQ, GPTQ, FP8, INT4, BitsAndBytes, and a few more. Full hardware/format compatibility chart: <https://docs.vllm.ai/en/latest/quantization/supported_hardware.html>.
- **Supported architectures** (model families like Llama, Qwen, Mistral, GPT-OSS, DeepSeek, Phi, Gemma, …) are listed here: <https://docs.vllm.ai/en/latest/models/supported_models.html>.

## Topology

Single container on the shared `caddy` Docker network. Caddy reaches it over that network for external traffic. The container also publishes its API on the host's loopback interface at `127.0.0.1:8000` for direct host-side curl/benchmarks — not reachable from the LAN. Set `HOST_PORT=<n>` in the variant file if 8000 is taken. The host's HuggingFace cache is bind-mounted read-write so vLLM and the `hf` CLI share the same downloads. Models come from HuggingFace by repo ID — vLLM loads safetensors directly.

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
├── entrypoint.sh        # builds `vllm serve` argv from env; hosts the tool-call parser choice
├── Makefile             # make list / make up ENV=<name> / make hf-cache / make hf-sync
├── envs/                # one .env per model variant
│   ├── README.md
│   ├── gpt-oss-120b.env
│   ├── gpt-oss-20b.env
│   ├── qwen3.5-27b-reasoning.env
│   └── qwen3.6-27b.env
└── .env.example         # reference template showing every variable
```

## Configure

Each `envs/<name>.env` is **self-contained** — image pin, HF cache, HF token, model spec, served name, GPU memory, and max context all in one file. `make up ENV=<name>` invokes `docker compose --env-file envs/<name>.env up -d` directly — no rolling `.env` is written. For subsequent commands, pass the same `--env-file` to docker compose, or use plain `docker` against the container name:

```bash
docker compose --env-file envs/<name>.env ps
docker logs -f vllm
docker stop vllm
```

`.env.example` is a reference template showing every variable; you don't need to edit it.

## Deploy

Prereq: `caddy/` running, shared `caddy` network exists.

```bash
make list                                # show available variants
make up ENV=qwen3.5-27b-reasoning        # start that one
docker logs -f vllm                      # tail (first run downloads the model)
```

Equivalent without Make:

```bash
docker compose --env-file envs/<variant>.env up -d
docker logs -f vllm                      # first run: HF download
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

Bump `VLLM_TAG` in the variant file (`envs/<name>.env`), then:

```bash
docker compose --env-file envs/<name>.env pull   # resolve image tag from the variant
make up ENV=<name>                                # restart on the new image
```

## Logs

```bash
docker logs -f vllm                                # plain docker, no env needed
docker compose --env-file envs/<name>.env logs -f vllm   # equivalent via compose
```

## Uninstall

```bash
docker compose --env-file envs/<name>.env down
# HF cache is on the host (not in a Docker volume) — leave it alone unless you
# also want to delete downloaded weights.
```

## See also

- Top-level [README](../README.md)
- [`caddy/`](../caddy/) — reverse proxy in front of this server
- [`llama-cpp/`](../llama-cpp/) — sibling inference stack for GGUF models
- vLLM docs: <https://docs.vllm.ai/>
