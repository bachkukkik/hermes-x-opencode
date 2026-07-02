# 27 — Service WebUI Startup

## What

`lib/service-webui.sh` starts the Hermes WebUI frontend as a background process under the `hermeswebui` user, ensuring state, workspace, and cache directories exist with correct ownership before launch.

## Why

- The WebUI init script (`/hermeswebui_init.bash`) sets up the Python virtual environment, installs dependencies, and starts the HTTP server on port 8787. It must run as the `hermeswebui` user, not root.
- State directories created by root (e.g., bind mounts) need ownership transferred before the non-root user can write to them.
- The entrypoint needs a clean separation between directory preparation and process launch.

## How

The module defines a single function `start_webui()` sourced by `entrypoint.sh`.

### Function signature

```bash
start_webui()
```

No parameters. Reads environment variables defined in `lib/constants.sh` and `.env`.

### Environment variables

| Variable | Source | Purpose |
|----------|--------|---------|
| `HERMES_WEBUI_STATE_DIR` | `.env` (default: `${HERMES_HOME}/webui`) | WebUI state directory |
| `HERMES_WEBUI_DEFAULT_WORKSPACE` | `.env` (default: `/workspace`) | Default workspace path |
| `UV_CACHE_DIR` | `.env` (default: `/uv_cache`) | uv package manager cache |
| `OPENCODE_USER` | `lib/constants.sh` | Non-root user (`hermeswebui`) to run as |
| `HERMES_HOME` | `lib/constants.sh` | Hermes home directory (`/home/hermeswebui/.hermes`) |

### Operations

1. **Create directories** — Creates `$HERMES_WEBUI_STATE_DIR`, `$HERMES_WEBUI_DEFAULT_WORKSPACE`, and `$UV_CACHE_DIR` with `mkdir -p`.
2. **Set ownership** — Runs `chown -R ${OPENCODE_USER}:${OPENCODE_USER}` on `$HERMES_WEBUI_STATE_DIR`.
3. **Launch** — Starts `/hermeswebui_init.bash` as `$OPENCODE_USER` via `su -s /bin/bash` in the background (`&`), captures the PID, and logs it.

## Verification

```bash
# Check WebUI is running
docker exec <container> ps aux | grep hermeswebui_init

# Check WebUI responds on port 8787
docker exec <container> curl -sf http://localhost:8787/health || echo "NOT READY"

# Check directory ownership
docker exec <container> ls -ld /home/hermeswebui/.hermes/webui /workspace /uv_cache
```

## What Works

- WebUI starts in the background, allowing the entrypoint to continue with gateway and OpenCode serve.
- Directory ownership is set before the non-root user writes, preventing EACCES errors.
- PID is logged for debugging and process tracking.
- `su` correctly drops privileges from root to `hermeswebui`.

## What Fails

- **WebUI init hangs on first boot:** The first boot runs `uv pip install` for Python dependencies, which can take 60–120 seconds on slow networks or ARM64 hardware. The entrypoint blocks on `wait_for_port 8787` until the server is healthy.
- **State directory not writable:** If `HERMES_WEBUI_STATE_DIR` points to a path that `chown` cannot modify (e.g., a read-only mount), the WebUI process fails to write state files.

## Resolution

- The 300-second `wait_for_port 8787 300` timeout in the entrypoint is generous enough for first-boot dependency installation.
- Ensure `HERMES_WEBUI_STATE_DIR` is inside `$HERMES_HOME` (default) or another writable path. The volume mount for `~/.hermes` is configured in `docker-compose.yml` as a named volume.

## Verdict

A minimal, focused startup helper that prepares directories and launches the WebUI under the correct user. The real complexity lives in `/hermeswebui_init.bash` (Python env setup), while this module handles the shell-side orchestration.
