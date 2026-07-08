# 29 — Config Hermes

## What

`lib/config-hermes.sh` generates the Hermes `config.yaml` file from environment variables and the discovered model list. It is the largest lib module (221 lines) and handles model context-length pinning, browser configuration, delegation settings, approvals mode, optional-skills directories, and the YAML generation itself.

## Why

- Eliminates manual `config.yaml` editing — the entrypoint regenerates it from `.env` on every boot
- Ensures the config always reflects current environment state (API keys, model lists, runtime toggles)
- Pins accurate context lengths for known model families (the agent's self-resolution table is a fallback — pinning gives correct values for models like `glm-5.2` with 1M windows)
- Default model always gets an explicit `context_length` so the config has at least one functioning entry
- The API key is auto-generated with `openssl rand -hex 16` when `HERMES_API_KEY` is unset

## How

### Functions

#### `resolve_ctx_len(model)`

Resolves a model ID to its pinned context length using substring matching. Returns the pinned value, or empty string for unknown models (the agent then self-resolves at runtime). Patterns are ordered longest/most-specific first.

**Pinned models:**

| Pattern | Context Length | Reason |
|---------|---------------|--------|
| `glm-5.2` | 1,048,576 | Agent catch-all gives 202,752 (wrong) |
| `claude-opus-4` | 1,000,000 | — |
| `claude-sonnet-4.6` | 1,000,000 | — |
| `gpt-5.4` | 1,050,000 | — |
| `gpt-5` | 400,000 | — |
| `gpt-4o` | 128,000 | — |
| `gpt-4.1` | 1,047,576 | — |
| `gpt-4` | 128,000 | — |
| `gemini` | 1,048,576 | — |
| `deepseek-v4` | 1,000,000 | — |
| `minimax-m3` | 1,000,000 | — |
| `qwen3.6-27b*q4` | 262,144 | Quantized GGUF: real 262K, not family 1M |
| `qwen3.6` | 1,048,576 | — |
| `agents-a1-mtp-apex` | 262,144 | Agents A1 MTP — 262K native ctx |
| `agents-a1-q4` | 262,144 | Agents A1 q4_k_m — same architecture |

#### `generate_config()`

The main config generator. Steps:
1. API key resolution
2. Approvals mode
3. Delegation block
4. Goals block
5. Compression block
6. Minimal config fallback when no `OPENAI_BASE_URL`
7. Model list iteration with context length resolution
8. Browser block
9. Skills block
10. YAML output

#### `append_skills_external_dirs()`

Appends `skills.external_dirs` to config.yaml after `ensure_agent()` runs.
