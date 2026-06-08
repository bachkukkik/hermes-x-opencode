# 03 — OpenCode Serve

## What

OpenCode Serve is a headless HTTP server that exposes the OpenCode CLI as a remote-attachable endpoint on port 4096. It runs the same server component as `opencode` normally does, but without the TUI client.

## Why

- Allows remote `opencode attach` from any machine on the network, providing a full interactive coding session without local installation
- Supports one-shot prompts via `opencode run --attach <url> "prompt"`, useful for CI/CD integration or scripted automation
- Keeps MCP server connections warm across multiple requests, avoiding cold-boot latency on every invocation

## How

OpenCode Serve is started by the entrypoint as the third background process, after the WebUI and Gateway are healthy. It is **opt-in** — controlled by the `OPENCODE_SERVE_ENABLED` environment variable (default: `false`). When enabled, it runs `opencode serve --port 4096 --hostname 0.0.0.0` as the `hermeswebui` user via `su`, ensuring the process operates with reduced privileges. The entrypoint (PID 1) runs as root and wraps the serve command: `su -s /bin/bash hermeswebui -c "opencode serve --port 4096 --hostname 0.0.0.0"`.

| Parameter | Value | Notes |
|-----------|-------|-------|
| Internal port | `4096` | Pinned via `--port 4096` flag |
| Host port | `${OPENCODE_SERVE_PORT:-4096}` | Configurable via `.env` |
| Bind address | `0.0.0.0` | Required for host access. Set via `--hostname 0.0.0.0`. |
| Auth | `OPENCODE_SERVER_PASSWORD` env var | Auto-generated if empty. Pass via `-p` flag when attaching. |
| Binary | `/usr/local/bin/opencode` | Installed via `opencode.ai/install` during build |
| Run user | `hermeswebui` (UID 1000) | Launched via `su` from root entrypoint |
| Enable flag | `OPENCODE_SERVE_ENABLED=true` | Required to start serve (default: `false`) |
| Boot timeout | `OPENCODE_SERVE_BOOT_TIMEOUT=30` | Seconds to wait for serve to bind :4096 |
| Working directory | `/home/hermeswebui` | `HOME=/home/hermeswebui` for the hermeswebui user |
| Config path | `/home/hermeswebui/.config/opencode/opencode.jsonc` | Owned by hermeswebui |

### Connect from a remote machine

```bash
opencode attach http://<host-ip>:4096

opencode run --attach http://<host-ip>:4096 "What does this project do?"
```

### Connect from another container on the same network

Containers on the `hermes_x_opencode_default` network can reach the server via the network alias `hermes-opencode` on port 4096.

### Authentication

OpenCode serve authenticates clients via the `OPENCODE_SERVER_PASSWORD` environment variable. The entrypoint auto-generates a random password if the variable is empty and writes it to `/tmp/opencode-server-password` (for `docker exec` access) and to the container logs. Clients must pass the password via the `-p` flag:

```bash
opencode attach http://<host-ip>:4096 -p "$password"
opencode run --attach http://<host-ip>:4096 -p "$password" "prompt"
```

The password is exported into the entrypoint's environment and inherited by the `su`-launched serve process. `docker exec` does not inherit exported env vars, so the file `/tmp/opencode-server-password` is the reliable way to read the password from outside the container.

## Verification

**Prerequisite:** Set `OPENCODE_SERVE_ENABLED=true` in `.env` before starting the stack.

```bash
# Port-based check (auth blocks curl)
CONTAINER=$(docker compose ps -q hermes-opencode)
docker exec "$CONTAINER" bash -c 'echo > /dev/tcp/127.0.0.1/4096'
opencode --version
```

## What Works

- Server starts within 5 seconds after the gateway is healthy
- Serves an HTML page (the OpenCode web UI) at the root URL, returning HTTP 200
- Remote attach via `opencode attach` establishes a working TUI session
- One-shot prompts via `opencode run --attach` work without local MCP server setup
- Database migration (`sqlite-migration:done`) runs automatically on first start
- Runs as `hermeswebui` user (UID 1000), not root — reduced filesystem blast radius

## What Fails

- **Password required for remote access:** Clients must know the `OPENCODE_SERVER_PASSWORD` to attach. The password is auto-generated and must be read from logs or the `/tmp/opencode-server-password` file.
- **Not started if gateway fails:** OpenCode serve starts after the gateway healthcheck passes. If the gateway never becomes healthy, OpenCode serve never starts (the entrypoint waits for port 8642 first).
- **opencode 1.16+ `--attach` requires a pre-existing session:** As of opencode v1.16, `opencode run --attach` returns exit code 1 with `Error: Session not found` unless a session already exists on the serve side. Previously, attach would auto-create a session. This means one-shot `run --attach` invocations fail when no session has been established via an interactive `opencode attach` first. The serve process itself is healthy (port open, auth works), but the attach flow cannot bootstrap a new session autonomously. Tests in `tests/e2e/11-serve-attach.bats` accept exit code 1 as a known regression.

## Resolution

- Read the auto-generated password from `docker logs` or `docker exec <container> cat /tmp/opencode-server-password`. Pass it with the `-p` flag when attaching.
- The sequential startup dependency ensures services start in order. If the gateway is intentionally disabled (no agent), modify the entrypoint to skip the gateway wait and start OpenCode serve directly.

## Verdict

OpenCode Serve provides a convenient remote access point for the OpenCode CLI. Running as hermeswebui instead of root reduces the filesystem blast radius. The `OPENCODE_SERVER_PASSWORD` auth prevents unauthorized access. The sequential startup ensures it only starts when the full stack is healthy.
