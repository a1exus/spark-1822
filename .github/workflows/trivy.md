# Trivy

Workflow: [`trivy.yml`](trivy.yml). Scans every container image we deploy plus the repo itself for vulnerabilities, misconfigurations, and leaked secrets, using [Aqua Security Trivy](https://aquasecurity.github.io/trivy/).

## Triggers

- `push` to `main`
- `pull_request` targeting `main`
- Weekly schedule — Mondays 06:00 UTC. Catches new CVEs against already-pinned images.
- Manual `workflow_dispatch`

## Jobs

| Job | What it scans |
|---|---|
| `extract-tags` | Reads pinned image tags from each stack's `.env.example` and exposes them as job outputs. |
| `image-scan` (matrix) | CVE scan of each pinned image: `ollama/ollama`, `ghcr.io/open-webui/open-webui`, `caddy`, `netdata/netdata`, `ghcr.io/ggml-org/llama.cpp`, `vllm/vllm-openai`, `traefik`, `cloudflare/cloudflared`. Severity HIGH+CRITICAL, fixed-only. |
| `config-scan` | Trivy IaC config check across the whole repo (compose misconfig, etc.). |
| `secret-scan` | Filesystem scan for accidentally-committed secrets. |

All findings are uploaded as SARIF to the repo's [Security tab](https://github.com/a1exus/spark-1822/security/code-scanning).

## Gating

- **Push / PR** — fails on any CRITICAL CVE or any leaked secret. Blocks merges on real regressions.
- **Scheduled** — never fails. Upstream-only CVEs against pinned images shouldn't break the green badge between version bumps; new findings still surface in the Security tab so we know to bump tags.

## Hardening

- All third-party actions are pinned by commit SHA (not tag). [`.github/dependabot.yml`](../dependabot.yml) opens a grouped PR each Monday with any updates so the pins don't go stale.
- Top-level `permissions: contents: read`; jobs declare `security-events: write` only where needed.
- Every job has `timeout-minutes` set (5/20/10/10 for `extract-tags` / `image-scan` / `config-scan` / `secret-scan`) so a stuck step can't burn the runner's 6-hour default.
- `extract-tags` parses `.env.example` with `grep` + a strict regex `^[A-Za-z0-9._@:+-]+$` (no `source`-ing of user-controlled files — protects against workflow injection via PR-modified env values). The regex accepts OCI digest pins like `server-cuda@sha256:…` while excluding every shell-meaningful character.
- Concurrency: `cancel-in-progress` per ref to avoid wasted runs.

## Maintenance

- Bumping a stack's image tag in `<stack>/.env.example` is picked up automatically by the next run.
- Adding a new stack: extend `extract-tags` to read the new `<stack>/.env.example`, then add an entry to the `image-scan` matrix referencing the new tag output.
- Bumping `aquasecurity/trivy-action` itself: resolve the new tag to a commit SHA and update all three `uses:` lines together.

## Local equivalent

To reproduce a single scan locally:

```bash
docker run --rm -v "$PWD:/repo" aquasec/trivy:latest \
    image --severity HIGH,CRITICAL --ignore-unfixed ollama/ollama:0.23.2

docker run --rm -v "$PWD:/repo" aquasec/trivy:latest \
    config /repo
```

## See also

- [`.github/README.md`](../README.md) — workflow index
- Top-level [README](../../README.md)
- Trivy: <https://aquasecurity.github.io/trivy/>
