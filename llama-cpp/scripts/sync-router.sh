#!/usr/bin/env bash
# Build the symlink farm for llama.cpp router mode, then regenerate config.ini.
# Idempotent. Called by `make hf-sync` (which exports the env vars below).
#
# Env (with defaults):
#   HF_CACHE        host HuggingFace cache dir (default /opt/hf/.cache/huggingface)
#   SYMLINK_FARM    host symlink farm dir (default /opt/hf/.cache/llama-cpp-models)
#   CTX_DEFAULT     default ctx-size for new config.ini sections (default 8192)
#   NGL_DEFAULT     default n-gpu-layers for new config.ini sections (default 999)

set -euo pipefail

HF_CACHE="${HF_CACHE:-/opt/hf/.cache/huggingface}"
SYMLINK_FARM="${SYMLINK_FARM:-/opt/hf/.cache/llama-cpp-models}"
CTX_DEFAULT="${CTX_DEFAULT:-8192}"
NGL_DEFAULT="${NGL_DEFAULT:-999}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGEN="$SCRIPT_DIR/regen-config-ini.py"

if [[ ! -x "$REGEN" ]]; then
    echo "sync-router: $REGEN not executable" >&2
    exit 1
fi
mkdir -p "$SYMLINK_FARM"

# Enumerate GGUFs in the HF cache. Output: <repo-id>\t<host-path>
list_ggufs() {
    if command -v hf >/dev/null 2>&1; then
        if hf cache scan --format json 2>/dev/null \
            | jq -re --arg cache "$HF_CACHE" '
                .repos[]
                | .repo_id as $repo
                | .revisions[]
                | .files[]
                | select(.path | endswith(".gguf"))
                | "\($repo)\t\(.path)"
            '; then
            return
        fi
    fi
    # Fallback: find walk; derive repo from path.
    find "$HF_CACHE/hub" -name "*.gguf" 2>/dev/null \
        | while read -r fp; do
            repo=$(echo "$fp" | sed -nE 's|.*/hub/models--([^/]+)/.*|\1|p' | sed 's|--|/|')
            [[ -n "$repo" ]] || continue
            printf '%s\t%s\n' "$repo" "$fp"
        done
}

# Portable associative-array shim (bash 3.2 / macOS compatible).
# Keys are GGUF basenames; values are repo-ids.
# Usage: seen_set KEY VALUE / seen_get KEY / seen_has KEY
_seen_encode() { printf '%s' "$1" | LC_ALL=C tr -cs 'A-Za-z0-9_' '_'; }
seen_set() { local k; k=$(_seen_encode "$1"); eval "_seen_${k}=\$2"; }
seen_get() { local k; k=$(_seen_encode "$1"); eval "printf '%s' \"\${_seen_${k}:-}\""; }
seen_has() { [[ -n "$(seen_get "$1")" ]]; }

specs=""
created=0
unchanged=0
collisions=0

while IFS=$'\t' read -r repo host_path; do
    [[ -n "$host_path" ]] || continue
    base=$(basename "$host_path")
    container_path="/root/.cache/huggingface${host_path#"$HF_CACHE"}"

    if seen_has "$base"; then
        echo "  collision: $base already linked from $(seen_get "$base"); skipping $repo" >&2
        collisions=$((collisions + 1))
        continue
    fi
    seen_set "$base" "$repo"

    section=$(echo "$base" \
        | sed -E 's/\.gguf$//; s/-0*[0-9]+-of-[0-9]+$//; s/-MXFP4.*//; s/-Q[0-9].*//; s/-IQ[0-9].*//; s/-F1[6]$//; s/-F32$//' \
        | tr '[:upper:]' '[:lower:]')

    quant=$(echo "$base" | grep -oE '(MXFP4|Q[0-9][_KMS0-9]*|IQ[0-9][_KMS0-9]*|F16|F32)' | head -1 || true)
    if [[ -n "$quant" ]]; then
        hf_alias="$repo:$quant"
    else
        hf_alias="$repo"
    fi

    target="$SYMLINK_FARM/$base"
    if [[ -L "$target" && "$(readlink "$target")" == "$container_path" ]]; then
        unchanged=$((unchanged + 1))
    else
        ln -sfn "$container_path" "$target"
        echo "+ symlink $base → $container_path"
        created=$((created + 1))
    fi

    # Only the first part of a multi-part split is the load entry point.
    part=$(echo "$base" | sed -nE 's/.*-0*([0-9]+)-of-[0-9]+\.gguf$/\1/p')
    if [[ -z "$part" || "$part" == "1" ]]; then
        specs+="$section"$'\t'"/models/$base"$'\t'"$hf_alias"$'\n'
    fi
done < <(list_ggufs)

orphaned=0
shopt -s nullglob
for link in "$SYMLINK_FARM"/*.gguf; do
    base=$(basename "$link")
    if ! seen_has "$base"; then
        echo "→ orphan symlink: $base"
        rm "$link"
        orphaned=$((orphaned + 1))
    fi
done

printf '%s' "$specs" | "$REGEN" \
    "$SYMLINK_FARM/config.ini" \
    "$SYMLINK_FARM/config.ini.orphans" \
    "$CTX_DEFAULT" \
    "$NGL_DEFAULT"

echo "router summary: $created symlinks created/updated, $unchanged unchanged, $orphaned orphaned, $collisions collisions"
