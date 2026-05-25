# 01 — Hermes WebUI

## What

Hermes WebUI is a browser-based chat interface backed by a Python HTTP server (`ThreadingHTTPServer`) that hosts the Hermes Agent runtime in-process. It serves as the primary user-facing entry point on port 8787.

## Why

- Provides a full browser UI for multi-session chat, file browsing, and agent management without requiring any client-side installation
- Imports the Hermes Agent (`AIAgent`) directly in-process via `from run_agent import AIAgent`, avoiding a separate agent process or IPC layer
- Ships as a pre-built Docker image (`ghcr.io/nesquena/hermes-webui:latest`) that includes Python, the WebUI server, and the hermes CLI

## How

The WebUI runs inside the `hermes-opencode` service as the first background process. The entrypoint starts `/hermeswebui_init.bash`, which sets up UID/GID, installs hermes-agent Python dependencies from the staged agent source, and launches the HTTP server.

| Parameter | Value | Notes |
|-----------|-------|-------|
| Base image | `ghcr.io/nesquena/hermes-webui:latest` | Pre-built, includes Python 3.12 and hermes CLI |
| Internal port | `8787` | Always 8787 inside the container |
| Host port | `${HERMES_WEBUI_PORT:-8787}` | Configurable via `.env` |
| Bind address | `0.0.0.0` | Set via `HERMES_WEBUI_HOST` env var |
| State dir | `/home/hermeswebui/.hermes/webui` | Persisted via bind mount |
| Default workspace | `/workspace` | Set via `HERMES_WEBUI_DEFAULT_WORKSPACE` |
| Auth | Optional via `HERMES_WEBUI_PASSWORD` | HMAC-signed HTTP-only cookie, 24h TTL |
| CSRF | Origin header validation | Non-browser clients (no `Origin` header) bypass CSRF |

### Chat flow

Chat uses a two-step async pattern:

1. `POST /api/chat/start` — queues the message, spawns a daemon thread running `AIAgent.run_conversation()`, returns a `stream_id` immediately
2. `GET /api/chat/stream?stream_id=X` — long-lived SSE connection forwarding tokens, tool calls, and completion events

A synchronous fallback exists at `POST /api/chat` (blocks until complete). The frontend never uses this endpoint.

### Key endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/health` | Basic health check (used by Docker healthcheck) |
| `GET` | `/health?deep=1` | Deep health: checks streams, sessions, projects, state.db |
| `POST` | `/api/session/new` | Create a new chat session |
| `GET` | `/api/sessions` | List all sessions |
| `GET` | `/api/session?session_id=SID` | Get full session with messages |
| `POST` | `/api/chat/start` | Send a message (returns `stream_id`) |
| `GET` | `/api/chat/stream?stream_id=X` | SSE stream for tokens/events |
| `POST` | `/api/chat` | Sync fallback (blocks until complete) |
| `POST` | `/api/chat/cancel` | Cancel a running stream |
| `GET` | `/api/models` | List configured models |
| `GET` | `/api/settings` | Read UI settings |

### Session management

Sessions are stored in SQLite at `/home/hermeswebui/.hermes/state.db`. The WebUI validates workspaces via `resolve_trusted_workspace()`, which checks: (A) under home directory, (B) in saved workspace list, (C) under `DEFAULT_WORKSPACE`. The container sets `DEFAULT_WORKSPACE=/workspace`, so `/workspace` is always trusted.

## Verification

```bash
curl -sf http://localhost:${HERMES_WEBUI_PORT:-8787}/health | python3 -m json.tool
curl -sf "http://localhost:${HERMES_WEBUI_PORT:-8787}/health?deep=1" | python3 -m json.tool
curl -sf http://localhost:${HERMES_WEBUI_PORT:-8787}/api/sessions | python3 -m json.tool
```

## What Works

- Health endpoint responds within 50ms under normal load
- Chat flow (start → stream SSE) delivers tokens in real time
- Session persistence across container restarts via bind-mounted state.db
- Workspace validation trusts `/workspace` without extra configuration
- Optional password auth via `HERMES_WEBUI_PASSWORD` with HMAC cookie
- Deep health endpoint reports active streams, runs, and uptime

## What Fails

- **Binding to 127.0.0.1 inside container:** The WebUI must bind to `0.0.0.0` for the host port mapping to work. Binding to `127.0.0.1` makes the port unreachable from outside the container.
- **No auth by default:** Without `HERMES_WEBUI_PASSWORD`, all endpoints are fully open with zero headers required. The startup banner warns about this.
- **Config regeneration overwrites manual edits:** `config.yaml` is regenerated from environment variables on every container start. Manual edits inside the container are lost on restart.
- **Empty default_model in models_cache.json:** The WebUI generates `~/.hermes/webui/models_cache.json` with a `default_model` field sourced from `config.yaml`'s `model.default` key. If `model.default` is absent (only `model.name` is set), `default_model` is written as `""` and no model appears in the WebUI's model settings panel. The entrypoint resolves this by writing both `model.default` and `model.name`.

## Resolution

- `HERMES_WEBUI_HOST=0.0.0.0` is hardcoded in the compose environment. No user action needed.
- Set `HERMES_WEBUI_PASSWORD` in `.env` to enable authentication. The WebUI uses HMAC-signed cookies with a 24h TTL.
- All configuration must be done through environment variables in `.env`. The entrypoint reads these and generates `config.yaml` on every boot. See `06 — Config and Env`.
- The `models_cache.json` `default_model` issue is resolved by the entrypoint writing `model.default` alongside `model.name` in `config.yaml`. If customizing the entrypoint, ensure both keys are present.

## Verdict

The WebUI is a solid, self-contained chat frontend with a clean HTTP API surface. The lack of default auth is acceptable for containerized deployments behind a firewall or reverse proxy, but must be explicitly addressed for network-exposed deployments.
