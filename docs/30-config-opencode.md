# 30 — Config OpenCode

## What

`lib/config-opencode.sh` generates the OpenCode `opencode.jsonc` configuration file. It is the most complex lib module (471 lines), handling provider resolution, model context limits, security permissions, credential seeding, fallback chains, and root-user configuration mirroring.

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

#### `get_limits(model_id)`

Resolves a model ID to its `(context, output)` token limits for the generated
`opencode.jsonc` `limit` block. Matching is by substring on the lowercased ID,
most-specific first; unmatched IDs fall through to the `(128000, 8192)` default.
The `llama_cpp` branch pins the Agents A1 families **before** its generic
catch-all so quantized/MTP builds get their real 262K window.

| Family (substring) | Context | Output | Note |
|--------------------|---------|--------|------|
| `gpt-4.1` | 1,048,576 | 32,768 | |
| `gpt-4o` | 128,000 | 16,384 | |
| `gpt-4-turbo` | 128,000 | 4,096 | |
| `gpt-4` (bare/`gpt-4.`/`gpt-4-`) | 8,192 | 4,096 | |
| `gpt-3.5` | 16,384 | 4,096 | |
| `gpt-5` | 128,000 | 16,384 | |
| `o1`/`o3`/`o4` | 200,000 | 100,000 | reasoning models |
| `claude-3.7`/`claude-4`/`claude-5` | 200,000 | 16,384 | |
| `claude-3`/`claude-4` (other) | 200,000 | 4,096 | |
| `llama_cpp/agents-a1-mtp-apex` | 262,144 | 32,768 | Agents A1 MTP (262K native) |
| `llama_cpp/agents-a1-q4` | 262,144 | 32,768 | Agents A1 q4_k_m |
| `llama_cpp` (other) | 200,000 | 32,768 | catch-all |
| `deepseek-v4` | 1,000,000 | 8,192 | |
| `kimi` | 262,144 | 8,192 | |
| `minimax-m3` | 1,000,000 | 8,192 | |
| `mimo-v2.5` | 1,048,576 | 8,192 | |
| `nemotron` | 131,072 | 8,192 | |
| `qwen3.6` | 1,048,576 | 8,192 | |
| `deepseek` (other) | 128,000 | 8,192 | |
| `glm-5.2` | 1,048,576 | 131,072 | |
| `glm` (other) | 128,000 | 8,192 | |
| `gemini` | 1,048,576 | 65,536 | |
| *(default)* | 128,000 | 8,192 | unknown families |

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
