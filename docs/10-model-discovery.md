# 10 — Model Discovery and Multi-Model Support

## What

The entrypoint auto-discovers all available chat models from the LLM provider at container startup and writes them into both the Hermes `config.yaml` and OpenCode `opencode.jsonc`, making every chat-capable model selectable without manual configuration.

## Why

- Eliminates manual model ID management — new models appear automatically after a container restart
- Both Hermes services (WebUI + Gateway) and OpenCode see the same model list from a single discovery pass
- Filters out non-chat models (embeddings, TTS, image generation) that would cause errors if selected
- Filters out litellm wildcard/model-group patterns (`anthropic/*`, `openai/*`) that resolve to 404 errors at request time
- Gracefully degrades to the default model only if the provider is unreachable

## How

### Discovery flow

```
entrypoint.sh
  └─ discover_models()
       ├─ curl $OPENAI_BASE_URL/models (15s timeout)
       ├─ python3: extract all model IDs from data[]
       ├─ python3: filter non-chat models (regex skip patterns)
       ├─ python3: filter wildcard patterns (IDs ending with /*)
       ├─ python3: case-insensitive dedup (model_id.lower() as set key)
       ├─ ensure OPENAI_DEFAULT_MODEL is in the list
       └─ DISCOVERED_MODELS = newline-separated model IDs
            ├─ generate_config()     → config.yaml (models dict)
            └─ generate_opencode_config() → opencode.jsonc (models object)
```

### Non-chat model filter

The python3 inline filter removes models matching these regex patterns (case-insensitive):

| Pattern | Filters out |
|---------|------------|
| `embed` | Text embedding models (`text-embedding-3-small`, etc.) |
| `whisper` | Speech-to-text models |
| `tts` | Text-to-speech models |
| `dall-e` | Image generation models |
| `sora` | Video generation models |
| `\bimage\b` | Image-related models |
| `realtime` | Realtime voice models |
| `transcrib` | Transcription models |
| `moderat` | Content moderation models |
| `\baudio\b` | Audio models |
| `codegen` | Code generation-only models |
| `babbage` | Legacy GPT-3 embeddings |
| `davinci` | Legacy GPT-3 completions |
| `\bcurie\b` | Legacy GPT-3 completions |
| `\bada\b` | Legacy GPT-3 embeddings |
| `text-` | Legacy text models |
| `stable` | Stable Diffusion models |
| `midjourney` | Midjourney models |
| `flux` | Flux image models |
| `/sd/` | Stable Diffusion paths |
| `\bmj\b` | Midjourney shorthand |
| `replicate` | Replicate-hosted models |
| `resolution` | Resolution-specific variants |
| `cli-proxy-api` | CLI proxy API models |

### Wildcard filter

After the non-chat filter, a second check removes litellm model-group patterns:

```python
if re.search(r'/\*$', model_id):
    continue
```

This filters out patterns like:

| Wildcard | Why filtered |
|----------|-------------|
| `anthropic/*` | Litellm model group alias, not a real model ID |
| `openai/*` | Litellm model group alias |
| `deepseek/*` | Litellm model group alias |
| `openrouter/*` | Litellm model group alias |
| `vertex_ai/*` | Litellm model group alias |

These patterns are litellm routing aliases (meaning "any model in this group") that return 404 when used as an actual model ID in a chat completion request.

### Case-insensitive dedup

After filtering, model IDs are deduplicated case-insensitively using `model_id.lower()` as a set key. This prevents duplicate entries when a provider returns the same model with different casing (e.g., `Model/name` and `model/name`). The original casing from the provider response is preserved in the final list — only exact-case duplicates are removed after the lowercased dedup pass.

### Fallback behavior

| Failure condition | Result |
|-------------------|--------|
| `OPENAI_BASE_URL` not set | `DISCOVERED_MODELS = OPENAI_DEFAULT_MODEL` only |
| `OPENAI_API_KEY` not set | `DISCOVERED_MODELS = OPENAI_DEFAULT_MODEL` only |
| curl fails or times out (15s) | `DISCOVERED_MODELS = OPENAI_DEFAULT_MODEL` only |
| All models filtered out | `DISCOVERED_MODELS = OPENAI_DEFAULT_MODEL` only |
| Default model not in discovered list | Default model is prepended to the list |

### Hermes config format

Models are written as a dict under `custom_providers[0].models`. The `model` section includes both `default` and `name` keys:

```yaml
model:
  provider: litellm
  default: z.ai/glm-5.2
  name: z.ai/glm-5.2

custom_providers:
  - name: litellm
    base_url: https://litellm-sw.example.com/v1
    models:
      anthropic/claude-opus-4-6:
        context_length: 200000
      openai/gpt-4o:
        context_length: 200000
    key_env: OPENAI_API_KEY
```

The `model.default` key is read by the outer WebUI's `models_cache.json` builder. The `model.name` key is read by the hermes-agent as a fallback. Both keys must be present. Both the WebUI and the Agent Gateway iterate the `custom_providers[0].models` dict for model routing.

### OpenCode config format

Models are written as an object dict under `provider.litellm.models`:

```jsonc
{
  "provider": {
    "litellm": {
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "apiKey": "{env:OPENAI_API_KEY}",
        "baseURL": "https://litellm-sw.example.com/v1"
      },
      "models": {
        "anthropic/claude-opus-4-6": {},
        "openai/gpt-4o": {}
      }
    }
  },
  "model": "litellm/z.ai/glm-5.2"
}
```

Key constraints:
- `models` must be `{}` (object), not `[]` (array). The OpenCode config schema requires key-value pairs.
- `model` (default) must be a string with provider prefix: `"litellm/MODEL_ID"`.
- `apiKey` uses `{env:OPENAI_API_KEY}` because `@ai-sdk/openai-compatible` does not auto-detect env vars.

### Model limits

The `generate_opencode_config()` function in the entrypoint assigns `context` and `output` token limits per model using a python3 `get_limits()` function that pattern-matches the model ID against known model families. These limits are written into each model entry in the `opencode.jsonc` `models` dict and are consumed by OpenCode to set token budgets:

```jsonc
{
  "provider": {
    "litellm": {
      "models": {
        "openai/gpt-4o": {
          "limit": { "context": 128000, "output": 16384 }
        },
        "anthropic/claude-opus-4-6": {
          "limit": { "context": 200000, "output": 16384 }
        }
      }
    }
  }
}
```

Limit assignment follows model name pattern matching (case-insensitive, checked in order):

| Pattern match | Context | Output | Example match |
|---------------|---------|--------|---------------|
| `gpt-4.1` | 1048576 | 32768 | `openai/gpt-4.1`, `gpt-4.1-nano` |
| `gpt-4o` | 128000 | 16384 | `openai/gpt-4o`, `gpt-4o-mini` |
| `gpt-4-turbo` | 128000 | 4096 | `openai/gpt-4-turbo` |
| `gpt-4` (other) | 8192 | 4096 | `openai/gpt-4`, `gpt-4-32k` |
| `gpt-3.5` | 16384 | 4096 | `openai/gpt-3.5-turbo` |
| `gpt-5` | 128000 | 16384 | `openai/gpt-5` |
| `/o[134]` or `-o[134]` | 200000 | 100000 | `openai/o1`, `openai/o3-mini`, `openai/o4` |
| `claude-3.7`, `claude-4+` | 200000 | 16384 | `anthropic/claude-3.7-sonnet`, `anthropic/claude-4-opus` |
| `claude-3` (other) | 200000 | 4096 | `anthropic/claude-3-haiku` |
| `deepseek` | 128000 | 8192 | `deepseek/deepseek-chat` |
| `glm` | 128000 | 8192 | `zai/glm-5.1`, `zai/glm-4` |
| `glm-5.2` | 1048576 | 131072 | `z.ai/glm-5.2` |
| `llama_cpp` | 200000 | 32768 | `llama_cpp/qwen3.6-27b-q4_k_m` |
| `gemini` | 1048576 | 65536 | `google/gemini-2.5-pro` |
| default (no match) | 128000 | 8192 | Any unmatched model ID |

These limits are used by the OpenCode serve's token budget calculation and are verified by the `03-config.bats` test suite.

### Model counts

| Metric | Typical value |
|--------|--------------|
| Total models from litellm `/v1/models` | ~310 |
| Non-chat models filtered | ~3–5 |
| Wildcard patterns filtered | 5 (`anthropic/*`, `openai/*`, `deepseek/*`, `openrouter/*`, `vertex_ai/*`) |
| Final chat models in config | ~297 |

### Runtime fallback

When `OPENCODE_FALLBACK_MODEL` is set, `config-opencode.sh` adds the `opencode-runtime-fallback` plugin to `opencode.jsonc` and seeds a global fallback chain at `~/.config/opencode/opencode-fallback.jsonc` (plus a root copy at `/root/.config/opencode/opencode-fallback.jsonc`). The fallback id is resolved with the same `_resolve_provider_prefix`/`_strip_provider_prefix` logic as the primary model, so a cross-provider chain works — for example a primary `opencode/deepseek-v4-flash-free` with a fallback of `litellm/llama_cpp/qwen3.6-27b-q4_k_m`. When unset, no fallback plugin is wired and failed calls surface normally. See acceptance criteria AC26–AC28 for the verification tests.

## Verification

```bash
CONTAINER=$(docker compose ps -q hermes-opencode)

echo "Chat models in Hermes config:" && docker exec $CONTAINER grep 'context_length' /home/hermeswebui/.hermes/config.yaml | wc -l

echo "Wildcard patterns (should be 0):" && docker exec $CONTAINER grep -c '/\*' /home/hermeswebui/.hermes/config.yaml || echo 0

echo "Default model:" && docker exec $CONTAINER grep -A1 '^model:' /home/hermeswebui/.hermes/config.yaml

echo "OpenCode model count:" && docker exec $CONTAINER python3 -c "import json; c=json.load(open('/home/hermeswebui/.config/opencode/opencode.jsonc')); print(len(c['provider']['litellm']['models']))"

echo "No HERMES_MODEL references:" && docker exec $CONTAINER grep -r 'HERMES_MODEL' /home/hermeswebui/.hermes/config.yaml || echo "OK - none found"
```

## What Works

- 297 chat models discovered and written to both configs from a single provider endpoint
- Wildcard patterns filtered out, preventing user-facing 404 errors when selecting model groups
- Non-chat models (embeddings, TTS, image generation) filtered out
- Default model is guaranteed to be present (added if missing from discovery)
- Both Hermes and OpenCode configs are generated from the same `DISCOVERED_MODELS` list
- Fallback to default-only model on discovery failure prevents container startup failure

## What Fails

- **Discovery timeout on slow providers:** The 15-second curl timeout may fire if the provider is slow or temporarily unreachable. Discovery falls back to the default model only, reducing the available model list to one entry.
- **Provider returns different model sets:** Different API keys or litellm configurations may return different model lists. The config is generated once at startup and does not update until the container restarts.
- **Cosmetic has_key: false:** The WebUI `/api/providers` endpoint reports `custom:litellm` with `has_key: false` and `models_total: 0`. This is because `_provider_has_key()` only checks for a literal `api_key` field in the provider config, not the `key_env` env var resolution path. The `resolve_custom_provider_connection()` function correctly reads `key_env: OPENAI_API_KEY` at request time, so chat works despite the display issue.
- **Config not refreshed without restart:** Adding a new model to the litellm proxy requires a container restart to re-run discovery. There is no runtime refresh mechanism.
- **models_cache.json default_model empty without model.default key:** The outer WebUI's `get_effective_default_model()` reads `model.default` from `config.yaml` without fallback to `model.name`. If the entrypoint writes only `model.name`, the cache gets `default_model: ""` and the WebUI shows no default model. The entrypoint writes both keys to prevent this.

## Resolution

- Increase the curl timeout in `discover_models()` (edit `--max-time 15` in `entrypoint.sh`) if the provider is consistently slow. Discovery adds 5–15 seconds to startup.
- Restart the container (`docker compose restart`) to re-run discovery and pick up new models from the provider. The WebUI's `models_cache.json` is fingerprinted against `config.yaml` and auto-invalidates when the config changes.
- The `has_key: false` cosmetic issue is upstream in the Hermes WebUI code (`api/providers.py`). No fix is needed for functionality — the `key_env` field is correctly resolved at request time.
- For dynamic model lists without restart, consider adding a webhook endpoint that triggers re-discovery. Not currently implemented.
- The `models_cache.json` `default_model` issue is resolved by the entrypoint writing both `model.default` and `model.name` to `config.yaml`. If customizing `generate_config()`, ensure both keys are present. See `06 — Config and Env` for details.

## Verdict

Model discovery is robust and self-healing. The two-stage filter (non-chat + wildcards) prevents common user-facing errors while exposing all usable models. The fallback to default-only ensures the container always starts even if the provider is temporarily unavailable. The cosmetic `has_key: false` issue is the only known limitation, and it does not affect functionality.
