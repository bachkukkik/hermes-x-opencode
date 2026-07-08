# 34 — OpenCode Serve Service

## What

`lib/service-opencode.sh` provides a single function `start_opencode_serve()` that launches the OpenCode serve process (`opencode serve --port 4096`) as a background process.

## Why

- Opt-in via `OPENCODE_SERVE_ENABLED=true` to avoid unnecessary background processes
- Auto-generates random password when `OPENCODE_SERVER_PASSWORD` is unset
- Passes provider env vars explicitly through `su` for `{env:VAR}` resolution
- Creates `~/.local/state` with proper ownership before starting

## How

### `start_opencode_serve()`

1. Guards: skips if disabled or `opencode` not found
2. Password generation and storage
3. State directory creation
4. Launch via `su` with provider env vars
5. Background with `&`
