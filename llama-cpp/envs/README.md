# llama-cpp env variants

One file per model. Picked at start via `--env-file` so `.env` stays put for common settings (image tag, HF cache, HF token).

Each variant chooses **how to find the model**:

- `MODEL_PATH=<absolute path inside the container>` — point at any mounted file (e.g. `/root/.cache/huggingface/hub/.../<file>.gguf`, or an Ollama blob under `/ollama/models/blobs/`).
- `MODEL_OLLAMA=<name>:<tag>` — point at an Ollama-cached blob by name; resolved against the mounted `/ollama` manifest store at start (no hardcoded digests).
- `MODEL_URL=<https://…>` — remote download, cached in the `llama-cpp-cache` Docker volume thereafter.

Plus `MODEL_ALIAS`, `CTX_SIZE`, and `N_GPU_LAYERS` tuned per model.

## Current variants

| File | Source |
|---|---|
| `gpt-oss-safeguard-120b-hf.env` | `MODEL_URL` → `lmstudio-community/gpt-oss-safeguard-120b-GGUF` (already in `llama-cpp-cache`, ~59 GiB) |

## Picking a variant

```bash
# from /opt/llama-cpp:
make list                                       # show available variants
make up VARIANT=gpt-oss-safeguard-120b-hf       # start with that one
make logs                                       # tail
make down
```

Behind the scenes:

```bash
docker compose --env-file .env --env-file envs/<variant>.env up -d
```

## See also

- [`../README.md`](../README.md) for the rest of the stack docs.
