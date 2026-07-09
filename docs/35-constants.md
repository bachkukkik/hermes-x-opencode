# 35 — Constants and Runtime Config

## What

`lib/constants.sh` defines all path constants, default runtime configuration values, and two helper functions (`log()` and `warn()`). It is the first lib module sourced by `entrypoint.sh` — every other module depends on the variables it exports.

## Why

- Centralizes all path and config defaults in one file
- Provides a single override point via `${VAR:-default}` pattern
- `log()` and `warn()` provide consistent formatting for all entrypoint output
- Path constants are referenced by every subsequent module

## Key Constants

| Variable | Value | Purpose |
|----------|-------|---------|
| `HERMES_HOME` | `/home/hermeswebui/.hermes` | Hermes state directory |
| `CONFIG` | `${HERMES_HOME}/config.yaml` | Hermes config file |
| `AGENT_DIR` | `${HERMES_HOME}/hermes-agent` | Staged agent runtime dir |
| `OPENCODE_USER` | `hermeswebui` | Non-root runtime user |
| `OPENCODE_CONFIG` | `/home/hermeswebui/.config/opencode/opencode.jsonc` | OpenCode config |

## Runtime Config Defaults

| Variable | Default | Purpose |
|----------|---------|---------|
| `OPENAI_DEFAULT_MODEL` | `openai/gpt-4o` | Catch-all default |
| `HERMES_YOLO_MODE` | `1` | Disables approval prompts |
| `HERMES_API_PORT` | `8642` | Gateway port |
| `OPENCODE_SERVE_PORT` | `4096` | OpenCode serve port |
| `OPENCODE_SECURITY_MODE` | `strict` | Permission level |
| `OPENCODE_COMPRESSION_THRESHOLD` | `0.76` | DCP compress point as fraction of each model's context window |
