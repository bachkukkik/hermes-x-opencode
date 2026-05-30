# 03 — OpenCode Serve

## What

OpenCode Serve is a headless HTTP server that exposes the OpenCode CLI as a remote-attachable endpoint on port 4096. It runs the same server component as `opencode` normally does, but without the TUI client.

## Why

- Allows remote `opencode attach` from any machine on the network, providing a full interactive coding session without local installation
- Supports one-shot prompts via `opencode run --attach <url> "prompt"`, useful for CI/CD integration or scripted automation
- Keeps MCP server connections warm across multiple requests, avoiding cold-boot latency on every invocation

## How

OpenCode Serve is started by the entrypoint as the third and final background process, after the WebUI and Gateway are healthy. It runs `opencode serve --port 4096 --hostname 0.0.0.0` as the `hermeswebui` user via `su`, ensuring the process operates with reduced privileges. The entrypoint (PID 1) runs as root and wraps the serve command: `su -s /bin/bash hermeswebui -c "opencode serve --port 4096 --hostname 0.0.0.0"`.

| Parameter | Value | Notes |
|-----------|-------|-------|
| Internal port | `4096` | Pinned via `--port 4096` flag |
| Host port | `${OPENCODE_SERVE_PORT:-4096}` | Configurable via `.env` |
| Bind address | `0.0.0.0` | Required for host access. Set via `--hostname 0.0.0.0`. |
| Auth | None (no HTTP auth support) | Server is unsecured — protect via firewall or VPN |
| Binary | `/usr/local/bin/opencode` | Installed via `opencode.ai/install` during build |
| Run user | `hermeswebui` (UID 1000) | Launched via `su` from root entrypoint |
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

OpenCode serve has no built-in HTTP authentication. The server is unsecured by design — any client that reaches port 4096 can attach and execute commands. Protect the endpoint with a firewall, or deploy behind an authenticating reverse proxy (nginx, Caddy, Tailscale). The `OPENCODE_API_KEY` provides authentication at the OpenCode client level but does not protect the serve port.

## Verification

```bash
curl -sf -o /dev/null -w "%{http_code}" http://localhost:${OPENCODE_SERVE_PORT:-4096}/
curl -sf http://localhost:${OPENCODE_SERVE_PORT:-4096}/global/health
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

- **No authentication:** OpenCode serve has no built-in HTTP auth. Any network client that reaches port 4096 can attach and execute commands with full filesystem access.
- **Not started if gateway fails:** OpenCode serve starts after the gateway healthcheck passes. If the gateway never becomes healthy, OpenCode serve never starts (the entrypoint waits for port 8642 first).

## Resolution

- Protect port 4096 with a firewall (e.g., `ufw deny 4096` on the host) or deploy behind an authenticating reverse proxy.
- The sequential startup dependency ensures services start in order. If the gateway is intentionally disabled (no agent), modify the entrypoint to skip the gateway wait and start OpenCode serve directly.

## Verdict

OpenCode Serve provides a convenient remote access point for the OpenCode CLI. Running as hermeswebui instead of root reduces the filesystem blast radius. The lack of built-in HTTP auth is the main operational concern — protect the port with a firewall or reverse proxy. The sequential startup ensures it only starts when the full stack is healthy.
