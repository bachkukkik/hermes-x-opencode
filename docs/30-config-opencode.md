# 30 — Config OpenCode

## What

`lib/config-opencode.sh` generates the OpenCode `opencode.jsonc` configuration file. It is the most complex lib module (466 lines), handling provider resolution, model context limits, security permissions, credential seeding, fallback chains, and root-user configuration mirroring.

## Why

- Generates a complete, valid `opencode.jsonc` from `.env` variables on every boot
- Resolves provider prefixes (opencode/ for Zen, litellm/ for proxy) via `normalize_model_id()`
- Seeds `auth.json` as a fallback credential store for both providers
- Mirrors configs to root's home directory so `docker exec` (which runs as root) sees the same providers
- Seeds `opencode-fallback.jsonc` for runtime model fallback chains
- Symlinks root's OpenCode data directory to the user's so `--attach` works for root sessions

## How

### Functions

#### `normalize_model_id(model)`

Single source of truth for provider/model prefix resolution. Recognized prefixes: `opencode/` (Zen) and `litellm/` (proxy). Explicit prefixes pass through unchanged. Bare IDs get `litellm/` when `OPENAI_BASE_URL` + `OPENAI_API_KEY` are set, otherwise `opencode/` (Zen).

#### `generate_opencode_config()`

The main config generator with credential gating, model resolution, fallback chain parsing, security mode, provider entries, config write, root mirror, auth.json seeding, and session DB symlink.

### Environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `OPENCODE_ZEN_API_KEY` | — | API key for OpenCode Zen models |
| `OPENCODE_DEFAULT_MODEL` | `$OPENAI_DEFAULT_MODEL` | Default model for OpenCode |
| `OPENCODE_FALLBACK_MODEL` | — | Comma-separated ordered fallback chain |
| `OPENCODE_SECURITY_MODE` | `strict` | Permission level |

### Provider prefix resolution

| Input | OpenAI creds? | Result |
|-------|-------------|--------|
| `opencode/id` | — | `opencode/id` (pass through) |
| `litellm/id` | — | `litellm/id` (pass through) |
| `bare-id` | Yes | `litellm/bare-id` |
| `bare-id` | No | `opencode/bare-id` |
