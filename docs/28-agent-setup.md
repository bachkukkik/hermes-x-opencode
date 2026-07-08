# 28 — Agent Setup

## What

`lib/agent-setup.sh` provides a single function `ensure_agent()` that copies the staged hermes-agent from build-time paths into the runtime bind-mounted volume. This bridges the gap between the Docker image build (where the agent is installed to `/opt/hermes-agent-staging`) and the first boot (where `~/.hermes` is empty).

## Why

- `~/.hermes` is a bind-mounted Docker volume that starts empty on first boot
- The Docker build installs the hermes-agent to `/opt/hermes-agent-staging` but cannot write to the bind mount (it doesn't exist at build time)
- The agent must be present at `$AGENT_DIR` before config generation and gateway startup, so this runs early in the entrypoint sequence

## How

The module defines a single function `ensure_agent()` sourced by `entrypoint.sh`.

### Function signature

```bash
ensure_agent()
```

No parameters. Reads environment variables defined in `lib/constants.sh`.

### Environment variables

| Variable | Source | Purpose |
|----------|--------|---------|
| `AGENT_DIR` | `lib/constants.sh` | Target directory at `${HERMES_HOME}/hermes-agent` |
| `STAGING_DIR` | `lib/constants.sh` | Build-time staging path at `/opt/hermes-agent-staging` |

### Operations

1. **Already-present check** — If `$AGENT_DIR/pyproject.toml` exists, logs and returns immediately (idempotent).
2. **Staging check** — If no staged agent at `$STAGING_DIR`, logs a warning and returns.
3. **Copy** — Creates the parent directory and copies recursively with `cp -a` (preserves permissions, symlinks, timestamps).
4. **Logs** — Confirms the copy with `== Agent copied.`
