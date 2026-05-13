#!/usr/bin/env bash
# vllm-openai launcher. Mirrors llama-cpp/entrypoint.sh — keeps the
# server-shape decisions (tool-calling parser, etc.) in one readable
# place instead of a long YAML command list.

set -euo pipefail

args=(
    --model                  "${VLLM_MODEL:?VLLM_MODEL must be set}"
    --served-model-name      "${VLLM_SERVED_NAME:-${VLLM_MODEL}}"
    --host                   "${LISTEN_HOST:-0.0.0.0}"
    --port                   "${LISTEN_PORT:-8000}"
    --gpu-memory-utilization "${VLLM_GPU_MEM:-0.9}"
    --max-model-len          "${VLLM_MAX_LEN:-8192}"
    # Tool-calling: `qwen3_xml` parses the XML tool-call format that
    # Qwen3.x emits: <tool_call><function=NAME><parameter=PARAM>VAL
    # </parameter></function></tool_call>. The other Qwen parser,
    # `qwen3_coder`, is for a different (JSON-style) format. For non-
    # Qwen families the parser is a no-op (chat completions still
    # work). Switch to per-variant control if we ever serve multiple
    # families with active tool calls at the same time.
    --enable-auto-tool-choice
    --tool-call-parser       qwen3_xml
)

echo "launching: vllm serve ${args[*]}"
exec vllm serve "${args[@]}"
