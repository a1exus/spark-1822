# .github

GitHub-side configuration: CI workflows and (in the future) community-health files.

## Workflows

### `workflows/trivy.yml` — Trivy security scanning

Runs on:

- `push` to `main`
- `pull_request` to `main`
- Weekly schedule (Mon 06:00 UTC) — catches new CVEs against already-pinned images
- Manual `workflow_dispatch`

Jobs:

| Job | What it scans |
|---|---|
| `extract-tags` | Reads pinned image tags from each stack's `.env.example` and exposes them as job outputs. |
| `image-scan` (matrix) | CVE scan of each pinned image (`ollama/ollama`, `open-webui`, `caddy`, `netdata/netdata`) — HIGH+CRITICAL, fixed-only. |
| `config-scan` | Trivy IaC config check across the whole repo (compose misconfig, etc.). |
| `secret-scan` | Filesystem scan for accidentally-committed secrets. |

All findings are uploaded as SARIF to the repo's [Security tab](https://github.com/a1exus/spark-1822/security/code-scanning).

### Gating

- **Push / PR** — fails on any CRITICAL CVE or any leaked secret.
- **Scheduled** — never fails. Upstream-only CVEs against pinned images shouldn't break the green badge between version bumps; new findings still surface in the Security tab.

### Hardening

- All third-party actions are pinned by commit SHA (not tag).
- Top-level `permissions: contents: read`; jobs declare `security-events: write` only where needed.
- `extract-tags` parses `.env.example` with `grep` + a strict regex (no `source`-ing user-controlled files).
- Concurrency: `cancel-in-progress` per ref.

### Maintenance

- When bumping a stack's image tag in `<stack>/.env.example`, the next CI run picks it up automatically.
- When a new stack is added, extend `extract-tags` and the `image-scan` matrix.

## See also

- Top-level [README](../README.md)
- Trivy: <https://aquasecurity.github.io/trivy/>
