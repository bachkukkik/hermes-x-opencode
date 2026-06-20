# 20 — OpenCode Runtime Model Fallback

## What

OpenCode has no native model fallback. This subsystem adds one through the `opencode-runtime-fallback` npm plugin, gated entirely on the `OPENCODE_FALLBACK_MODEL` environment variable. When the primary model call fails — rate-limit, quota exhaustion, 5xx, timeout, or an overloaded provider — the plugin transparently retries the same request against a configured fallback model before surfacing the error to the agent.

## Why

- **Resilience for shared/free primaries.** The stack frequently runs OpenCode against a free, shared primary such as `opencode/deepseek-v4-flash-free` on OpenCode Zen. These tiers are rate-limited and shared across tenants, so transient throttling is common; a single 429 should not abort an in-progress coding session.
- **Isolation by provider.** The fallback is intended to run on a *different* provider than the primary (for example a local `llama.cpp` GGUF served through a LiteLLM proxy), so one outage cannot take down both ends of the chain.
- **Fully opt-in.** When `OPENCODE_FALLBACK_MODEL` is unset, no plugin is wired and no fallback config is written — zero overhead, zero behavior change. The feature only activates when explicitly configured.

## How

The feature is implemented in `config-opencode.sh` (sourced by `entrypoint.sh`) inside the `generate_opencode_config()` function. It composes two artifacts when enabled: a plugin entry in `opencode.jsonc` and a global fallback chain file. It reads `OPENCODE_FALLBACK_MODEL` once into `_raw_fallback_model`; all downstream behavior branches on whether that value is non-empty.

### Config generation

When `OPENCODE_FALLBACK_MODEL` is non-empty, `generate_opencode_config()` performs two steps:

1. **Appends the plugin.** The base plugin array (`@tarquinen/opencode-dcp@latest`, `@franlol/opencode-md-table-formatter@latest`, `cc-safety-net`) gains a fourth entry, `"opencode-runtime-fallback"`, in the `opencode.jsonc` `plugin` array:

   ```jsonc
   "plugin": [
       "@tarquinen/opencode-dcp@latest",
       "@franlol/opencode-md-table-formatter@latest",
       "cc-safety-net",
       "opencode-runtime-fallback"
   ]
   ```

2. **Seeds a global fallback chain.** It writes `opencode-fallback.jsonc` into the user's OpenCode config directory (`dirname($OPENCODE_CONFIG)` → `~/.config/opencode/opencode-fallback.jsonc`) containing a single resolved fallback id, then mirrors a copy at `/root/.config/opencode/opencode-fallback.jsonc`. The root copy mirrors the existing `auth.json` dual-location seeding so that root `docker exec` sessions (Hermes `terminal()` calls run as root) read the same chain as the `hermeswebui` `opencode serve` process:

   ```jsonc
   {
     "fallback_models": ["litellm/llama_cpp/qwen3.6-27b-q4_k_m"]
   }
   ```

When `OPENCODE_FALLBACK_MODEL` is unset, neither artifact is produced — the plugin array stays at its three base entries and no `opencode-fallback.jsonc` is written. This is the default state.

The generator emits two log lines summarizing the result:

```
== Wrote opencode.jsonc with N models, default: <prefix>/<model>, small: <prefix>/<model>, fallback: <status> (security: <mode>, opencode_zen: <enabled|disabled>).
== Seeded opencode-fallback.jsonc (fallback: <prefix>/<model>).
```

The `fallback:` field is `none` when the var is unset, otherwise the resolved `<prefix>/<model>`. The second line is only emitted when a fallback is seeded.

### Fallback id resolution

The fallback id is resolved with the **same** `_resolve_provider_prefix` / `_strip_provider_prefix` logic used for the primary (`model`) and `small_model` fields:

| Input id | OPENAI_BASE_URL + OPENAI_API_KEY | Resolved prefix | Stripped id |
|----------|----------------------------------|-----------------|-------------|
| `opencode/foo` | any | `opencode` | `foo` |
| `litellm/foo` | any | `litellm` | `foo` |
| `llama_cpp/qwen3.6-27b-q4_k_m` | both set | `litellm` | `llama_cpp/qwen3.6-27b-q4_k_m` (unchanged — `llama_cpp/` is not a provider prefix) |
| `llama_cpp/qwen3.6-27b-q4_k_m` | not both set | `opencode` | `llama_cpp/qwen3.6-27b-q4_k_m` (unchanged) |

A bare id (no `opencode/` or `litellm/` prefix) routes to the `litellm` provider when both `OPENAI_BASE_URL` and `OPENAI_API_KEY` are set, otherwise to OpenCode Zen. Prefix the id explicitly to force a specific provider. Because resolution is per-model and independent of the primary, the primary and fallback can sit on different providers — this is what makes a cross-provider chain possible.

### Cross-provider example

A resilience-focused deployment running a free primary on OpenCode Zen with a self-hosted fallback served by `llama.cpp` behind a LiteLLM proxy:

```dotenv
OPENCODE_API_KEY=sk-zc-...
OPENCODE_DEFAULT_MODEL=opencode/deepseek-v4-flash-free
OPENCODE_FALLBACK_MODEL=llama_cpp/qwen3.6-27b-q4_k_m
OPENAI_BASE_URL=https://litellm-sw.example.com/v1
OPENAI_API_KEY=sk-litellm-...
```

With both `OPENAI_BASE_URL` and `OPENAI_API_KEY` set, the bare fallback id resolves to the `litellm` provider, yielding a cross-provider chain:

| Slot | Resolved id | Provider |
|------|-------------|----------|
| Primary | `opencode/deepseek-v4-flash-free` | OpenCode Zen |
| Fallback | `litellm/llama_cpp/qwen3.6-27b-q4_k_m` | LiteLLM proxy → local llama.cpp |

The seeded `~/.config/opencode/opencode-fallback.jsonc` (and its `/root` mirror) for the above:

```jsonc
{
  "fallback_models": ["litellm/llama_cpp/qwen3.6-27b-q4_k_m"]
}
```

### Configuration

| Variable | File | Default | Values |
|----------|------|---------|--------|
| `OPENCODE_FALLBACK_MODEL` | `.env` | (unset — no fallback) | Any resolvable model id, optionally provider-prefixed (`opencode/...`, `litellm/...`, or bare) |

Changes require a container restart: `docker compose up -d`.

## Verification

```bash
# Static syntax check of the generator.
bash -n volumes_hermes_opencode/build/scripts/lib/config-opencode.sh

CONTAINER=$(docker compose ps -q hermes-opencode)

# AC26 — when set, the plugin and fallback chain are present.
docker exec "$CONTAINER" python3 -c "
import json, re, sys
t = open(sys.argv[1]).read()
t = re.sub(r'(?<![:a-zA-Z])//.*?\n', '\n', t)
c = json.loads(t)
print('\n'.join(c.get('plugin', [])))
" /tmp/fbtest-set/opencode.jsonc | grep -qx 'opencode-runtime-fallback'

# AC27 — when unset, the plugin and chain are absent (three base plugins only).
docker exec "$CONTAINER" python3 -c "
import json, re, sys
t = open(sys.argv[1]).read()
t = re.sub(r'(?<![:a-zA-Z])//.*?\n', '\n', t)
c = json.loads(t)
print('\n'.join(c.get('plugin', [])))
" /tmp/fbtest-unset/opencode.jsonc | grep -qx 'opencode-runtime-fallback'   # must NOT match

# AC28 — the resolved fallback id is provider-prefixed in the chain.
docker exec "$CONTAINER" python3 -c "
import json, sys
c = json.load(open(sys.argv[1]))
print(','.join(c.get('fallback_models', [])))
" /tmp/fbtest-set/opencode-fallback.jsonc
# expected: litellm/llama_cpp/qwen3.6-27b-q4_k_m
```

The full assertions live in `tests/e2e/16-model-fallback.bats` (AC26–AC28). Each test runs `generate_opencode_config()` in the live container with a controlled `OPENCODE_FALLBACK_MODEL`, backing up and restoring the root `opencode.jsonc` in `teardown()` so the live config is left untouched.

## What Works

- Transparent retry of failed OpenCode LLM calls (rate-limit, quota, 5xx, timeout, overloaded) against a configured fallback model
- Cross-provider chains: primary on OpenCode Zen, fallback on a LiteLLM-served local model, because prefix resolution is independent per model
- Per-model prefix resolution identical to the primary, so the fallback id is unambiguous
- Dual-location seeding (`hermeswebui` + root) so both `opencode serve` and root `docker exec` sessions read the same chain
- Fully opt-in: zero plugins, zero files, and zero runtime overhead when `OPENCODE_FALLBACK_MODEL` is unset
- The `bash -n` syntax check passes on the generator

## What Fails

- **Fallback target unreachable at runtime:** the configured fallback model must be served at request time (e.g. a `llama.cpp` server reachable at `OPENAI_BASE_URL`). If it is down, the fallback is inert — the original error surfaces after the plugin's retry also fails.
- **Plugin auto-install needs network at boot:** `opencode-runtime-fallback` is fetched from npm on OpenCode's first run. An air-gapped or offline boot leaves the plugin uninstalled, so fallback silently does not engage.
- **Not a Hermes gateway fallback:** this is OpenCode-side only. The Hermes Gateway's own fallback (the `AIAgent` `fallback_model` parameter) is a separate, independent concern and is out of scope here.
- **Single-model chain:** the seeded `opencode-fallback.jsonc` contains exactly one `fallback_models` entry. There is no multi-hop chain generation in this config step; extending the array requires editing the file after seeding.

## Resolution

- Run the fallback model on a host/provider independent of the primary so correlated outages are unlikely. A local `llama.cpp` GGUF behind a LiteLLM proxy is the intended pattern.
- Ensure outbound npm access (or a local npm cache) at container boot so the plugin installs; if offline operation is required, pre-install the plugin into the image.
- To customize the chain beyond a single model, edit `~/.config/opencode/opencode-fallback.jsonc` (and the `/root` mirror) after `generate_opencode_config()` runs. Note both are regenerated on container restart.
- For gateway-level resilience, configure the Hermes Gateway's `fallback_model` separately — the two fallback mechanisms are orthogonal and can coexist.

## Verdict

OpenCode lacks a native fallback, and the free/shared primaries the stack favors are the most failure-prone. Wiring `opencode-runtime-fallback` behind an opt-in `OPENCODE_FALLBACK_MODEL` — resolved through the same prefix logic as the primary and seeded to both runtime users — adds a robust, cross-provider safety net with no cost when disabled. The main caveats are operational: the fallback target must be reachable at runtime, and the plugin must be able to install at boot.
