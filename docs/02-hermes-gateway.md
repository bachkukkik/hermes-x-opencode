# 02 — Hermes Gateway

## What

The Hermes Gateway is an aiohttp-based OpenAI-compatible API server that runs as a gateway platform (`api_server`) inside the `hermes-opencode` service on port 8642. It exposes `/v1/chat/completions`, `/v1/models`, `/v1/responses`, and related endpoints.

## Why

- Provides a standard OpenAI-compatible endpoint so external clients (Open WebUI, LobeChat, LibreChat, AnythingLLM, ChatBox) can connect without custom integration
- Runs a full Hermes `AIAgent` instance server-side with tools, memory, skills, and streaming — not a simple proxy
- Supports session continuity via `X-Hermes-Session-Id` header and long-term memory scoping via `X-Hermes-Session-Key`

## How

The gateway runs via `hermes gateway run --accept-hooks` using the hermes CLI from the WebUI's venv (`/app/venv/bin/hermes`). It is started by the entrypoint after the WebUI becomes healthy.

### Restart-loop supervisor

The gateway process is wrapped in a `while true` restart-loop supervisor (see `lib/service-gateway.sh`, lines 14-21). If the gateway exits for any reason, the loop automatically restarts it with a 2-second delay. Each restart event is logged to `${HERMES_HOME}/logs/gateway-restart.log` with the exit code and timestamp. The primary stdout/stderr log goes to `${HERMES_HOME}/logs/gateway-stdout.log` (the shell redirect uses a different filename than Python's RotatingFileHandler on `gateway.log` to avoid conflicts). Before launching, `start_gateway()` creates and chowns the logs directory to `hermeswebui` to prevent `PermissionError` when the gateway writes log files. This ensures the gateway recovers from crashes without requiring a full container restart.

| Parameter | Value | Notes |
|-----------|-------|-------|
| Internal port | `8642` | Configured in `config.yaml` under `platforms.api_server.extra.port` |
| Host port | `${HERMES_API_PORT:-8642}` | Configurable via `.env` |
| Bind address | `0.0.0.0` | Required for host access. Gateway refuses `0.0.0.0` without an API key set. |
| Auth | `API_SERVER_KEY` via config.yaml | Auto-generated if `HERMES_API_KEY` is empty |
| CORS origins | `*` | Configured in `config.yaml` |
| Config loader | `HERMES_HOME` env var | Falls back to `Path.home() / '.hermes'` |

### HERMES_HOME resolution

The gateway loads its configuration from `get_hermes_home()`, which checks the `HERMES_HOME` environment variable first, then falls back to `Path.home() / '.hermes'`. The entrypoint runs as root (HOME=/root), so `HERMES_HOME` must be explicitly exported to `/home/hermeswebui/.hermes` where `config.yaml` is located. This is set in two places:

1. `export HERMES_HOME="/home/hermeswebui/.hermes"` in `scripts/entrypoint.sh`
2. `HERMES_HOME=/home/hermeswebui/.hermes` in `docker-compose.yml` environment block

### API key auto-generation

When `HERMES_API_KEY` is empty or unset, the entrypoint generates a random key (`hermes-<32-hex-chars>`) and writes it to `config.yaml`. The generated key is printed to container logs:

```bash
docker logs <container> 2>&1 | grep "Generated random HERMES_API_KEY"
```

### Key endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/health` | Health check |
| `GET` | `/v1/models` | Lists `hermes-agent` as available model |
| `POST` | `/v1/chat/completions` | OpenAI Chat Completions (streaming + non-streaming) |
| `POST` | `/v1/responses` | OpenAI Responses API (stateful via `previous_response_id`) |
| `GET` | `/v1/responses/{id}` | Retrieve stored response |
| `POST` | `/v1/runs` | Start async run (returns `run_id`, HTTP 202) |
| `GET` | `/v1/runs/{id}/events` | SSE stream of structured lifecycle events |
| `POST` | `/v1/runs/{id}/approval` | Resolve a pending run approval |
| `GET` | `/v1/capabilities` | Machine-readable API capabilities |

### Usage example

```bash
API_KEY=$(docker logs <container> 2>&1 | grep "Generated random HERMES_API_KEY" | sed 's/.*: //')

curl http://localhost:8642/v1/chat/completions \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"hermes-agent","messages":[{"role":"user","content":"Hello"}],"stream":false}'
```

## Verification

```bash
curl -sf http://localhost:${HERMES_API_PORT:-8642}/health | python3 -m json.tool
curl -sf http://localhost:${HERMES_API_PORT:-8642}/v1/models | python3 -m json.tool
```

## What Works

- Non-streaming chat completions return correct OpenAI-format responses with usage stats
- Streaming chat completions emit SSE events with token-by-token output
- Health endpoint reports `{"status":"ok","platform":"hermes-agent"}`
- Models endpoint lists `hermes-agent`
- Bearer token authentication works when `API_SERVER_KEY` is set
- Session continuity via `X-Hermes-Session-Id` header

## What Fails

- **Gateway refuses 0.0.0.0 without API key:** The api_server platform refuses to bind to `0.0.0.0` unless `API_SERVER_KEY` is set. Without a key, it logs: `[Api_Server] Refusing to start: binding to 0.0.0.0 requires API_SERVER_KEY`.
- **HERMES_HOME resolves to /root/.hermes:** If `HERMES_HOME` is not exported, the gateway reads config from `/root/.hermes` (which is empty) instead of `/home/hermeswebui/.hermes/config.yaml`. Result: "No messaging platforms enabled."
- **Gateway starts with no connected platforms on first boot:** If the agent has not yet been copied from staging to the bind mount, `start_gateway()` skips entirely because `AGENT_DIR/pyproject.toml` is not found.
- **No user allowlists configured:** The gateway warns about missing allowlists. This is cosmetic — the api_server platform does not use user allowlists.

## Resolution

- The entrypoint auto-generates a random API key when `HERMES_API_KEY` is empty. The key is printed to container logs. To set a fixed key, define `HERMES_API_KEY` in `.env`.
- `HERMES_HOME` is exported in both the entrypoint script and the compose environment block. If gateway config loading fails, verify: `docker exec <container> echo $HERMES_HOME`.
- The `ensure_agent()` function in the entrypoint copies the agent from `/opt/hermes-agent-staging` to the bind mount before `start_gateway()` is called. See `05 — Entrypoint Sequence`.
- The allowlist warning can be ignored for the `api_server` platform. It is relevant only for messaging platforms (Telegram, Discord).

## Verdict

The gateway provides a fully functional OpenAI-compatible API with minimal configuration. The HERMES_HOME and API key requirements are handled automatically by the entrypoint. The main operational concern is retrieving the auto-generated API key from container logs.
