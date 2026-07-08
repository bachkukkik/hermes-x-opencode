# 39 — Dashboard Service

## What

`lib/service-dashboard.sh` provides `start_dashboard()` that launches the Hermes web dashboard on port 9119 — a machine-management UI separate from the WebUI chat.

## Why

- Opt-in via `HERMES_DASHBOARD_ENABLED=true`
- Uses `--insecure` to bind to `0.0.0.0` inside the container
- Auto-installs pre-built web dist from staging into venv
- Restart-loop supervisor pattern for resilience

## How

### `start_dashboard()`

1. Web dist installation (idempotent)
2. Log directory creation
3. `hermes dashboard --host 0.0.0.0 --port 9119 --insecure --skip-build --no-open` via `su`
4. Restart loop with 2s delay
