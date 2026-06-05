# 05 — Entrypoint Sequence

## What

The entrypoint script (`scripts/entrypoint.sh`) is the container's `ENTRYPOINT`. It discovers available models from the LLM provider, generates configuration files for both Hermes and OpenCode, copies the staged agent, and starts three background services in dependency order, keeping the container alive until any process exits.

## Why

- Discovers all available chat models from the LLM provider at startup, eliminating manual model ID management
- Generates `config.yaml` for Hermes and `opencode.jsonc` for OpenCode from a single model discovery pass, ensuring both services see the same model list
- Skips WebUI onboarding by setting `HERMES_WEBUI_SKIP_ONBOARDING`, removing the interactive setup wizard
- Copies the hermes-agent from the image's staging path to the bind-mounted volume on first start, bridging build-time content with runtime persistence
- Starts services sequentially with health gates, ensuring each service's dependencies are ready before it launches
- Uses `wait -n` to propagate any background process crash as a container exit

## How

The script is located at `volumes_hermes_opencode/build/scripts/entrypoint.sh` and is copied to `/usr/local/bin/entrypoint.sh` during the Docker build.

### Key variables

| Variable | Value | Purpose |
|----------|-------|---------|
| `OPENCODE_USER` | `hermeswebui` | Non-root user for opencode serve and gateway |
| `OPENCODE_USER_HOME` | `/home/hermeswebui` | Home directory of the run user |
| `OPENCODE_CONFIG` | `/home/hermeswebui/.config/opencode/opencode.jsonc` | Generated config path |
| `OPENCODE_SKILLS_DIR` | `/home/hermeswebui/.config/opencode/skills` | OpenCode skills (baked into image at build time) |
| `HERMES_HOME` | `/home/hermeswebui/.hermes` | Hermes state directory |
| `HERMES_SKILLS_DIR` | `/home/hermeswebui/.hermes/skills` | Hermes skills runtime target (populated from staging) |

### Execution sequence

```
 1. set -euo pipefail
 2. export HERMES_HOME, OPENCODE_USER, OPENCODE_USER_HOME, OPENCODE_CONFIG, OPENCODE_SKILLS_DIR
 3. staging copy                 — copies /opt/hermes-skills-staging → ~/.hermes/skills/, registers graphify for hermes
 4. discover_models()           — curls OPENAI_BASE_URL/models, filters non-chat models and wildcards
 5. generate_config()           — writes config.yaml with multi-model models dict (if OPENAI_BASE_URL is set)
 6. generate_opencode_config()  — writes opencode.jsonc with plugins, permissions, discovered models; chowns to hermeswebui
 7. ensure_agent()              — copies /opt/hermes-agent-staging → /home/hermeswebui/.hermes/hermes-agent (first boot only)
 8. /hermeswebui_init.bash &    — starts WebUI init (UID/GID setup, Python deps, HTTP server)
 9. wait_for_port 8787 120      — blocks until WebUI health endpoint responds
10. start_gateway()             — su hermeswebui -c "/app/venv/bin/hermes gateway run --accept-hooks" &
11. wait_for_port 8642 60       — blocks until Gateway health endpoint responds
12. start_opencode_serve()      — if OPENCODE_SERVE_ENABLED=true: su hermeswebui -c "opencode serve --port 4096 --hostname 0.0.0.0" &
                                else: log and skip
12b. wait_for_port 4096         — (only if serve enabled) boot readiness probe, non-fatal timeout
13. wait -n                     — blocks until any background process exits
14. Container shuts down
```

### Functions

| Function | Purpose |
|----------|---------|
| `discover_models()` | Curls `$OPENAI_BASE_URL/models` with the API key. Parses response with python3, filters non-chat models (embed, whisper, tts, dall-e, sora, etc.) and wildcard patterns (`anthropic/*`, `openai/*`). Falls back to `OPENAI_DEFAULT_MODEL` only on failure. Sets `DISCOVERED_MODELS` as newline-separated model ID list. |
| `generate_config()` | Writes `config.yaml` with litellm custom provider using a `models` dict (key=model ID, value=`{context_length: 200000}`). Auto-generates API key if `HERMES_API_KEY` is empty. Sets default model from `OPENAI_DEFAULT_MODEL` as both `model.default` and `model.name` — the outer WebUI reads `model.default`, the hermes-agent reads `model.default` with fallback to `model.name`. |
| `generate_opencode_config()` | Writes `opencode.jsonc` with plugins, permission block (based on `OPENCODE_SECURITY_MODE`), and a single `@ai-sdk/openai-compatible` provider containing all discovered models with token limits assigned per model family. Chowns the config directory to `hermeswebui`. Uses `case` statement with three branches: `strict` (31 bash rules, interpreters denied), `standard` (22 rules, interpreters allowed), `yolo` (allow all). |
| `ensure_agent()` | Copies agent from `/opt/hermes-agent-staging` to `/home/hermeswebui/.hermes/hermes-agent` if not already present. Idempotent — skips if `pyproject.toml` exists. |
| `wait_for_port(port, timeout)` | Loops `curl -sf http://localhost:${port}/health` every 2 seconds until success or timeout. |
| `start_gateway()` | Starts the gateway as `hermeswebui` via `su`. Skips if agent not found or hermes CLI not in venv. |
| `start_opencode_serve()` | Starts OpenCode serve as `hermeswebui` via `su`. Skips if `opencode` binary not found. |

### Model discovery details

`discover_models()` uses a 15-second curl timeout to fetch the model list from the LLM provider. The response is parsed by a python3 inline script that:

1. Extracts all model IDs from the `data` array
2. Filters out non-chat models using regex patterns (embed, whisper, tts, dall-e, sora, image, realtime, transcrib, moderat, audio, codegen, babbage, davinci, curie, ada, text-, stable, midjourney, flux, /sd/, mj, replicate, resolution)
3. Filters out litellm wildcard/model-group patterns (any ID ending with `/*`)
4. Ensures `OPENAI_DEFAULT_MODEL` is present in the final list (adds it if missing)

### Config generation details

`generate_config()` iterates `DISCOVERED_MODELS` and writes each model ID as a key in the `custom_providers[0].models` dict with `context_length: 200000`. The `key_env: OPENAI_API_KEY` field instructs the Hermes runtime to read the API key from the environment variable at request time. The `model` section writes both `default` and `name` keys from `OPENAI_DEFAULT_MODEL`:

```yaml
model:
  provider: litellm
  default: ${OPENAI_DEFAULT_MODEL}
  name: ${OPENAI_DEFAULT_MODEL}
```

The `default` key is consumed by the outer WebUI's `models_cache.json` builder (`/app/api/config.py` → `get_effective_default_model()`). The `name` key is consumed by the hermes-agent as a fallback when `default` is absent. Both keys must be present to avoid the WebUI showing an empty default model.

`generate_opencode_config()` writes a JSON file with:
- A `plugin` array containing three plugins: `@tarquinen/opencode-dcp@latest`, `@franlol/opencode-md-table-formatter@latest`, `cc-safety-net`
- A `permission` block generated by a `case` statement on `OPENCODE_SECURITY_MODE` (`strict`/`standard`/`yolo`) — see `13 — Security Hardening`
- A single provider named `litellm` using `@ai-sdk/openai-compatible` npm package
- `apiKey: "{env:OPENAI_API_KEY}"` — OpenCode's env var interpolation syntax
- `baseURL` set to `OPENAI_BASE_URL` with trailing slash stripped
- `models` as an object dict `{model_id: {limit: {context: N, output: N}}}` where each model gets token limits assigned by a `get_limits()` function that pattern-matches the model ID against known families (see `10 — Model Discovery`)
- `model` as a string `"litellm/OPENAI_DEFAULT_MODEL"` — the provider prefix is required
- `small_model` as a string `"litellm/OPENAI_SMALL_MODEL"` — falls back to the default model if `OPENAI_SMALL_MODEL` is not set

After writing, the function runs `chown -R hermeswebui:hermeswebui` on the config directory so the `hermeswebui` user can read it when opencode serve starts.

### Timing

| Boot type | Skills | Discovery | WebUI ready | Gateway ready | OpenCode ready | Total |
|-----------|--------|-----------|-------------|---------------|----------------|-------|
| First boot | <1s (cp -a staging) | +5–15s | 60–120s (Python deps) | +10–20s | +5s | 80–160s |
| Subsequent | <1s (cp -a staging) | +5–15s | 10–20s (cached deps) | +5–10s | +5s | 25–50s |

## Verification

```bash
docker logs <container> 2>&1 | grep -E "^(==|!!)"
docker logs <container> 2>&1 | grep -E "(Discovering|Discovered|Wrote config|Wrote opencode|WebUI init|Gateway started|OpenCode serve started|All services running)"
```

Expected output lines in order:
```
== Copying staged hermes skills...
== Registering graphify for hermes...
== Discovering models from https://litellm-sw.bachkukkik.com/v1 ...
== Discovered 297 chat models.
== Wrote config.yaml with 297 models.
== Wrote opencode.jsonc with 297 models.
== Agent already present at /home/hermeswebui/.hermes  (or "Copying staged agent..." on first boot)
== WebUI init started (PID: N)
== Port 8787 is ready.
== Starting hermes gateway (api_server on :8642)...
== Gateway started (PID: N)
== Port 8642 is ready.
== Starting opencode serve on :4096 (workdir: /home/hermeswebui, user: hermeswebui)...
== OpenCode serve started (PID: N)
== All services running. Waiting...
```

## What Works

- Model discovery is idempotent — same provider URL produces same model list every boot
- Both Hermes and OpenCode configs are generated from the same model list, ensuring consistency
- Wildcard patterns (`anthropic/*`, `openai/*`, etc.) are filtered out, preventing 404 errors when users select a model group
- Non-chat models (embeddings, TTS, image generation) are filtered out
- Config regeneration is consistent — same env vars produce same configs every boot
- Agent copy skips on subsequent boots (`Agent already present at ...`)
- Sequential startup with health gates prevents race conditions
- `wait -n` correctly propagates any process crash as a container exit
- Auto-generated API key is printed to logs and written to config.yaml

## What Fails

- **Discovery timeout:** If the LLM provider is slow or unreachable, the 15-second curl timeout fires. Discovery falls back to `OPENAI_DEFAULT_MODEL` only, reducing the available model list to one.
- **Gateway wait timeout kills container:** If the gateway does not become healthy within 60 seconds, `wait_for_port` returns 1 and `set -e` kills the container.
- **Config not generated without OPENAI_BASE_URL:** If `OPENAI_BASE_URL` is empty, `generate_config()` returns early and `config.yaml` is not written. The WebUI and gateway run with default config (no custom provider, no api_server platform).
- **Agent copy failure is non-fatal:** If `/opt/hermes-agent-staging` is missing (should not happen in normal builds), `ensure_agent()` logs a warning but continues. The gateway then skips because the agent is not found.
- **Cosmetic has_key: false:** The WebUI `/api/providers` endpoint reports `has_key: false` for `custom:litellm` because `_provider_has_key()` only checks for a literal `api_key` field, not the `key_env` env var resolution path. Chat functionality works correctly regardless.
- **model.default vs model.name mismatch:** The outer WebUI (`/app/api/config.py`) reads `model.default` from `config.yaml` without fallback to `model.name`. The hermes-agent reads `model.default` with fallback to `model.name`. The entrypoint writes both keys to satisfy both consumers. If `default` is absent, the WebUI's `models_cache.json` gets `default_model: ""` and no model is shown in the UI.

## Resolution

- Increase the curl timeout in `discover_models()` if the provider is consistently slow (edit the `--max-time 15` flag in `entrypoint.sh`).
- The 60-second gateway timeout is generous for normal operation. If gateway startup is consistently slow, increase the timeout in `wait_for_port 8642` call.
- Always set `OPENAI_BASE_URL` in `.env`. Without it, the stack runs in degraded mode with no custom provider and no gateway platform.
- The agent staging path is verified during the Docker build (step 8 in `04 — Build Pipeline`). If the build passes, the staging path is guaranteed to exist.
- The `has_key: false` cosmetic issue is upstream in the Hermes WebUI code. The `resolve_custom_provider_connection()` function correctly reads `key_env: OPENAI_API_KEY` at request time, so chat works despite the display issue.
- The `model.default` vs `model.name` mismatch is resolved by the entrypoint writing both keys. Do not remove either key from `generate_config()`. See `06 — Config and Env` for details.

## Verdict

The entrypoint sequence is deterministic and well-ordered. Model discovery eliminates manual model ID management and ensures both Hermes and OpenCode see the same model list. The wildcard filter prevents a common user-facing error. The main operational risk is the discovery timeout, which gracefully degrades to a single model.
