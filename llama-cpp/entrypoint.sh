#!/usr/bin/env bash
# llama-server launcher. Picks the model in this order:
#   1. MODEL_PATH   — local file inside the container (any mounted dir).
#   2. MODEL_OLLAMA — Ollama model:tag — resolved against the mounted
#                     /ollama manifest store to the right blob path.
#   3. MODEL_URL    — remote URL (llama.cpp downloads + caches it).
# Exactly one of these must select a model.

set -euo pipefail

args=(
    --host "${LISTEN_HOST:-0.0.0.0}"
    --port "${LISTEN_PORT:-8080}"
    --ctx-size "${CTX_SIZE:-32768}"
    --n-gpu-layers "${N_GPU_LAYERS:-999}"
    --alias "${MODEL_ALIAS:-llama-cpp}"
)

# Resolve MODEL_OLLAMA → MODEL_PATH if set (and MODEL_PATH not already set).
if [[ -n "${MODEL_OLLAMA:-}" && -z "${MODEL_PATH:-}" ]]; then
    name="${MODEL_OLLAMA%:*}"
    tag="${MODEL_OLLAMA##*:}"
    manifest="/ollama/models/manifests/registry.ollama.ai/library/${name}/${tag}"
    if [[ ! -f "${manifest}" ]]; then
        echo "MODEL_OLLAMA=${MODEL_OLLAMA}: manifest not found at ${manifest}" >&2
        echo "available models:" >&2
        find /ollama/models/manifests/registry.ollama.ai/library -mindepth 2 -type f -printf '  %P\n' 2>/dev/null >&2 || true
        exit 1
    fi
    # Minified JSON; split records on '}' so each layer becomes its own
    # record. Pick the model-layer record (mediaType ends in image.model)
    # and pull its sha256 digest.
    digest=$(awk -v RS='}' '
        /application\/vnd\.ollama\.image\.model/ {
            if (match($0, /sha256:[a-f0-9]+/)) {
                print substr($0, RSTART, RLENGTH); exit
            }
        }' "${manifest}")
    if [[ -z "${digest}" ]]; then
        echo "MODEL_OLLAMA=${MODEL_OLLAMA}: no model layer in manifest" >&2
        exit 1
    fi
    MODEL_PATH="/ollama/models/blobs/${digest/:/-}"
    echo "resolved MODEL_OLLAMA=${MODEL_OLLAMA} → MODEL_PATH=${MODEL_PATH}"
fi

if [[ -n "${MODEL_PATH:-}" ]]; then
    if [[ ! -e "${MODEL_PATH}" ]]; then
        echo "MODEL_PATH=${MODEL_PATH} does not exist inside the container" >&2
        echo "available roots:" >&2
        echo "  /ollama/models/blobs/             — Ollama-cached GGUF blobs (sha256-named)" >&2
        echo "  /root/.cache/huggingface/hub/     — HuggingFace Hub cache snapshots" >&2
        echo "  /root/.cache/llama.cpp/           — llama.cpp's own download cache" >&2
        exit 1
    fi
    args+=( --model "${MODEL_PATH}" )
elif [[ -n "${MODEL_URL:-}" ]]; then
    args+=( --model-url "${MODEL_URL}" )
else
    echo "set MODEL_PATH, MODEL_OLLAMA, or MODEL_URL — see envs/*.env for ready-made variants" >&2
    exit 64
fi

echo "launching: llama-server ${args[*]}"
exec /app/llama-server "${args[@]}"
