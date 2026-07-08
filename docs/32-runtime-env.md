# 32 — Runtime Environment Detection

## What

`lib/runtime-env.sh` provides two functions for detecting the execution environment (Docker vs bare Linux) and normalizing network addresses accordingly. This is the first lib module sourced by `entrypoint.sh` because other modules depend on `RUNTIME_ENV_MODE`.

## Why

- The same entrypoint script can run inside Docker or on bare Linux
- Automatic detection eliminates manual `RUNTIME_ENV` configuration
- `host.docker.internal` → `localhost` substitution prevents network failures outside Docker

## How

### `detect_runtime_env()`

Detection precedence:
1. `RUNTIME_ENV` env var (explicit override)
2. `/.dockerenv` file presence
3. `KUBERNETES_SERVICE_HOST` env var
4. Default: `local`

Stores result in `RUNTIME_ENV_MODE`.

### `normalize_base_url_for_local(url)`

Substitutes `host.docker.internal` with `localhost` when `RUNTIME_ENV_MODE=local`.
