# vllm env variants

One file per model. Picked at start via `--env-file` so `.env` stays put for common settings (image tag, HF cache, HF token).

Each variant here corresponds to a model **already downloaded** on this host (under `/opt/hf/.cache/huggingface/`). Adding a new variant means first `hf download <repo>` (or letting vLLM pull on first start), then dropping a new `<name>.env` here.

## Current variants

| File | HF repo |
|---|---|
| `gpt-oss-120b.env` | `openai/gpt-oss-120b` |
| `qwen3.5-27b-reasoning.env` | `Jackrong/Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled` |

## What each file sets

- `VLLM_MODEL` — HuggingFace repo ID (vLLM resolves via the standard HF Hub cache).
- `VLLM_SERVED_NAME` — name surfaced via the OpenAI-compatible API.
- `VLLM_GPU_MEM` — fraction of VRAM vLLM may use (0.0–1.0).
- `VLLM_MAX_LEN` — max context length.

Gated models need `HF_TOKEN` set in `.env`.

## Picking a variant

```bash
# from /opt/vllm:
make list                                  # show available variants
make up VARIANT=qwen3.5-27b-reasoning      # start with that one
make logs                                  # tail
make down
```

Behind the scenes:

```bash
docker compose --env-file .env --env-file envs/<variant>.env up -d
```

## See also

- [`../README.md`](../README.md) for the rest of the stack docs.
