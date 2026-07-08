# 33 — Gateway Service

## What

`lib/service-gateway.sh` provides a single function `start_gateway()` that launches the Hermes gateway service (`hermes gateway run --accept-hooks`) as a background process with automatic restart.

## Why

- The gateway must run as `hermeswebui` user for correct file permissions
- Auto-restart ensures resilience — respawns after 2 seconds on crash
- Guarded by agent presence checks (requires both `$AGENT_DIR/pyproject.toml` and `/app/venv/bin/hermes`)

## How

### `start_gateway()`

1. Creates `${HERMES_HOME}/logs` with user ownership
2. Launches `hermes gateway run --accept-hooks` via `su` as `$OPENCODE_USER`
3. Runs in infinite `while true` loop with 2s restart delay
4. Logs to `${HERMES_HOME}/logs/gateway-stdout.log` and `gateway-restart.log`
