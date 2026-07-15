# 05 — Entrypoint Sequence

## What

The entrypoint script (`scripts/entrypoint.sh`) is the container's `ENTRYPOINT`. It is a thin orchestrator that sources 18 library modules from `scripts/lib/`, then seeds volumes, discovers available models from the LLM provider, generates configuration files for both Hermes and OpenCode, initializes profiles, and starts background services in dependency order, keeping the container alive until any process exits.

## Why

- Discovers all available chat models from the LLM provider at startup, eliminating manual model ID management
- Generates `config.yaml` for Hermes and `opencode.jsonc` for OpenCode from a single model discovery pass, ensuring both services see the same model list
- Skips WebUI onboarding by setting `HERMES_WEBUI_SKIP_ONBOARDING`, removing the interactive setup wizard
- Copies the hermes-agent from the image's staging path to the bind-mounted volume on first start, bridging build-time content with runtime persistence
- Starts services sequentially with health gates, ensuring each service's dependencies are ready before it launches
- Uses `wait` to keep the container alive until any background process exits

## How

The script is located at `volumes_hermes_opencode/build/scripts/entrypoint.sh` and is copied to `/usr/local/bin/entrypoint.sh` during the Docker build. The library modules live in `scripts/lib/` and are copied to `/usr/local/bin/lib/`.

### Modular architecture

The entrypoint is an 110-line orchestrator. All logic lives in 18 sourced library modules under `scripts/lib/`:

```
scripts/entrypoint.sh          (110 lines — orchestrator, sources lib/*.sh)
scripts/lib/
├── constants.sh               (69 lines — path constants, runtime config defaults, log/warn helpers)
├── runtime-env.sh             (runtime environment detection helpers)
├── port-utils.sh              (43 lines — TCP port readiness polling with health endpoint support)
├── mock-llm-server.sh         (mock LLM server for CI/testing fallback)
├── seed-volumes.sh            (volume seeding: skills, graphify, AGENTS.md)
├── agent-setup.sh             (hermes-agent staging/copy logic)
├── model-discovery.sh         (model list discovery from OpenAI-compatible API)
├── config-hermes.sh           (219 lines — hermes config.yaml generation + skills.external_dirs appending)
├── config-opencode.sh         (OpenCode config generation)
├── validate-opencode.sh       (OpenCode Zen API key validation)
├── service-gateway.sh         (Hermes gateway service startup)
├── service-opencode.sh        (OpenCode serve service startup)
├── service-dashboard.sh       (Hermes web dashboard startup)
├── profile-righthand-man.sh   (righthand-man orchestrator profile seeding)
├── service-browser-vnc.sh     (Browser/VNC human-in-the-loop stack startup)
├── service-webui.sh           (16 lines — Hermes WebUI startup wrapper)
├── symlink-cleanup.sh         (broken symlink cleanup)
└── wiki-init.sh               (wiki directory initialization for llm-wiki skill)
```

Modules are sourced in dependency order: constants first (defines paths + log/warn helpers), then helpers (runtime-env, port-utils, mock-llm, seed-volumes, agent-setup), then configuration generators (model-discovery → config-hermes → config-opencode → validate-opencode), then service starters (dashboard, browser-vnc, webui, gateway, opencode), and finally profile initialization and wiki init.

### Key variables

Defined in `lib/constants.sh`:

| Variable | Value | Purpose |
|----------|-------|---------|
| `OPENCODE_USER` | `hermeswebui` | Non-root user for opencode serve and gateway |
| `OPENCODE_USER_HOME` | `/home/hermeswebui` | Home directory of the run user |
| `OPENCODE_CONFIG` | `/home/hermeswebui/.config/opencode/opencode.jsonc` | Generated config path |
| `OPENCODE_SKILLS_DIR` | `/home/hermeswebui/.config/opencode/skills` | OpenCode skills (baked into image at build time) |
| `HERMES_HOME` | `/home/hermeswebui/.hermes` | Hermes state directory |
| `HERMES_BAK` | `/home/hermeswebui/.hermes-bak` | Backup/alternate Hermes state directory |
| `HERMES_SKILLS_DIR` | `/home/hermeswebui/.hermes/skills` | Hermes skills runtime target (populated from staging) |

### Execution sequence

```
 1. set -euo pipefail
 1b. LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
 1c. source "${LIB_DIR}/constants.sh"                    — paths, config defaults, log/warn helpers
 1d. source "${LIB_DIR}/runtime-env.sh"
 1e. source "${LIB_DIR}/port-utils.sh"
 1f. source "${LIB_DIR}/mock-llm-server.sh"              — mock LLM server for CI/testing
 1g. source "${LIB_DIR}/seed-volumes.sh"                 — volume seeding (skills, graphify)
 1h. source "${LIB_DIR}/agent-setup.sh"
 1i. source "${LIB_DIR}/model-discovery.sh"
 1j. source "${LIB_DIR}/config-hermes.sh"
 1k. source "${LIB_DIR}/config-opencode.sh"
 1l. source "${LIB_DIR}/validate-opencode.sh"
 1m. source "${LIB_DIR}/service-gateway.sh"
 1n. source "${LIB_DIR}/service-opencode.sh"
 1o. source "${LIB_DIR}/service-dashboard.sh"            — Hermes web dashboard
 1p. source "${LIB_DIR}/profile-righthand-man.sh"        — righthand-man profile seeding
 1q. source "${LIB_DIR}/service-browser-vnc.sh"
 1r. source "${LIB_DIR}/service-webui.sh"                — WebUI startup wrapper
 1s. source "${LIB_DIR}/symlink-cleanup.sh"              — broken symlink cleanup
 1t. source "${LIB_DIR}/wiki-init.sh"
 2. seed_volumes()           — replaces inline skill-staging; seeds skills, graphify, and AGENTS.md
 3. detect_runtime_env()     — detects Docker/local; normalizes OPENAI_BASE_URL for local networking
 4. start_mock_llm (optional) — starts mock LLM on localhost:4000 if OPENAI_BASE_URL matches (CI fallback)
 5. discover_models()        — curls OPENAI_BASE_URL/models, filters non-chat models and wildcards
 6. generate_config()        — writes config.yaml with multi-model dict, compression block, browser block, goals, delegation
 7. generate_opencode_config() — writes opencode.jsonc with plugins, permissions, discovered models; chowns to hermeswebui
 8. generate_dcp_staging() — writes managed dcp.jsonc with per-model percentage-based compression thresholds
 9. validate_opencode_zen_key() — if OPENCODE_ZEN_API_KEY is set, validates against Zen API; non-fatal
10. cleanup_symlink_loops    — removes broken symlinks that could cause infinite loops
11. ensure_agent()           — copies /opt/hermes-agent-staging → ~/.hermes/hermes-agent (first boot only)
12. init_wiki()              — initializes wiki directory at $WIKI_DIR with SCHEMA.md backbone (idempotent)
13. append_skills_external_dirs() — appends skills.external_dirs to config.yaml (after ensure_agent)
14. Seed AGENTS.md to /workspace if not already present
15. start_webui()            — wraps /hermeswebui_init.bash; creates state/workspace/cache dirs, chowns, launches as hermeswebui
16. wait_for_port 8787 120 "Hermes WebUI" — blocks until WebUI health endpoint responds (120s timeout)
17. seed_righthand_man()     — seeds righthand-man orchestrator profile (idempotent, needs venv from WebUI init)
18. start_browser_vnc()      — starts Browser/VNC human-in-the-loop stack (if BROWSER_HUMAN_LOOP_ENABLED=true)
19. wait_for_port 9222 30 "chromium CDP" "/json/version" — Chromium CDP readiness (non-fatal, only if browser enabled)
20. chown -R $OPENCODE_USER:$OPENCODE_USER $HERMES_HOME — pre-gateway ownership fix
21. start_gateway()          — starts Hermes gateway as hermeswebui
22. wait_for_port 8642 90 "Hermes Gateway" — blocks until Gateway health endpoint responds (90s timeout)
23. mkdir -p ~/.local/share ~/.local/state + chown — pre-opencode .local setup (EACCES fix)
24. start_opencode_serve()   — starts opencode serve (if OPENCODE_SERVE_ENABLED=true)
25. wait_for_port 4096 TIMEOUT "opencode serve" "/health" — boot readiness probe, non-fatal
26. start_dashboard()        — starts Hermes web dashboard (if HERMES_DASHBOARD_ENABLED=true)
27. wait_for_port DASHBOARD_PORT TIMEOUT "hermes dashboard" "/" — dashboard readiness, non-fatal
28. wait                     — blocks until any background process exits
29. Container shuts down
```

### Functions

| Function | Source file | Purpose |
|----------|-------------|---------|
| `detect_runtime_env()` | `lib/runtime-env.sh` | Detects whether running inside Docker, Kubernetes, or on bare Linux. Sets `RUNTIME_ENV_MODE`. |
| `normalize_base_url_for_local(url)` | `lib/runtime-env.sh` | Replaces `host.docker.internal` with `localhost` when running locally (non-Docker). |
| `start_mock_llm()` | `lib/mock-llm-server.sh` | Starts a mock LLM server on localhost:4000 for CI/testing when `OPENAI_BASE_URL=http://localhost:4000`. |
| `seed_volumes()` | `lib/seed-volumes.sh` | Seeds skills, graphify registration, and AGENTS.md into volumes — replaces inline skill-staging code from the old entrypoint. |
| `discover_models()` | `lib/model-discovery.sh` | Curls `$OPENAI_BASE_URL/models` with the API key. Parses response with python3, filters non-chat models (embed, whisper, tts, dall-e, sora, etc.) and wildcard patterns (`anthropic/*`, `openai/*`). Falls back to `OPENAI_DEFAULT_MODEL` only on failure. Sets `DISCOVERED_MODELS` as newline-separated model ID list. |
| `generate_config()` | `lib/config-hermes.sh` | Writes `config.yaml` with litellm custom provider using a `models` dict (key=model ID) with a hybrid value: known families pinned to their true context length via `resolve_ctx_len()` (e.g. glm-5.2→1048576), the default model always pinned (fallback 262144), and unknown families emitted as `{}` so the hermes-agent self-resolves at runtime. Auto-generates API key if `HERMES_API_KEY` is empty. Sets default model from `HERMES_DEFAULT_MODEL` (with `OPENAI_DEFAULT_MODEL` fallback) as both `model.default` and `model.name`. Writes `browser:` block with viewport dimensions when `BROWSER_HUMAN_LOOP_ENABLED=true`. Writes `compression:` block when `HERMES_COMPRESSION_THRESHOLD` is set. Writes `goals.max_turns` from `HERMES_GOAL_MAX_TURNS`. Writes `delegation.model` when `HERMES_DELEGATION_MODEL` is set, and `delegation.provider` when `HERMES_DELEGATION_PROVIDER` is set. Writes `skills.external_dirs` inline when the optional-skills dir exists. On fallback (no OPENAI_BASE_URL), writes a minimal config with api_server + default model only. |
| `generate_opencode_config()` | `lib/config-opencode.sh` | Writes `opencode.jsonc` with plugins, permission block (based on `OPENCODE_SECURITY_MODE`), and a single `@ai-sdk/openai-compatible` provider containing all discovered models with token limits assigned per model family. When `OPENCODE_ZEN_API_KEY` is set, also generates an explicit `opencode` provider block with `apiKey: *** so built-in `opencode/` models have proper authentication mapping. Seeds `auth.json` at `~/.local/share/opencode/auth.json` with the key as a fallback credential store. Copies the config to `/root/.config/opencode/` so root sees providers (fix #28, idempotent via `readlink -f` guard). Symlinks `/root/.local/share/opencode` to hermeswebui's data dir for shared session DB (fix #29). Chowns the config directory to `hermeswebui`. Uses `case` statement with three branches: `strict` (31 bash rules, interpreters denied), `standard` (22 rules, interpreters allowed), `yolo` (allow all). Resolves provider prefix per-model via `_resolve_provider_prefix()` so `model` and `small_model` can route to different providers (issue #46). |
| `generate_dcp_staging()` | `lib/config-opencode.sh` | Writes a managed `dcp.jsonc` with `compress.maxContextLimit`/`compress.minContextLimit` as percentages of each model's context window. Uses surgical merge — loads existing file, sets only compress keys, preserves all others. Driven by `OPENCODE_COMPRESSION_THRESHOLD` (default `0.76`). Chowns the config directory to `hermeswebui`. |
| `validate_opencode_zen_key()` | `lib/validate-opencode.sh` | Validates `OPENCODE_ZEN_API_KEY` against the Zen API models endpoint. If the key is empty, logs an informational message and returns. If set but invalid, logs a warning with instructions to get a valid key. Non-fatal — the container always continues starting (fix #30). |
| `cleanup_symlink_loops()` | `lib/symlink-cleanup.sh` | Removes broken symlinks that could cause infinite loop errors during file traversal. |
| `ensure_agent()` | `lib/agent-setup.sh` | Copies agent from `/opt/hermes-agent-staging` to `/home/hermeswebui/.hermes/hermes-agent` if not already present. Idempotent — skips if `pyproject.toml` exists. **Note:** The staged clone is a deps source for `/hermeswebui_init.bash` (which rsyncs it and runs `uv pip install` into `/app/venv/`), not a second runtime. See `16 — Agent Installation Architecture`. |
| `wait_for_port(port, timeout, label, health_path)` | `lib/port-utils.sh` | Tries HTTP health check at `$health_path` (default `/health`) first, then falls back to `nc -z` TCP probe every 2 seconds until success or timeout. Set `$health_path` to empty string to skip the HTTP check entirely. Returns 0 on success, 1 on timeout. |
| `start_webui()` | `lib/service-webui.sh` | Creates WebUI state/workspace/cache directories with correct ownership, then launches `/hermeswebui_init.bash` under `hermeswebui` in the background. Replaces the inline `/hermeswebui_init.bash &` call from the old entrypoint. |
| `start_gateway()` | `lib/service-gateway.sh` | Starts the gateway as `hermeswebui` via `su`. Skips if agent not found or hermes CLI not in venv. |
| `start_opencode_serve()` | `lib/service-opencode.sh` | Starts OpenCode serve as `hermeswebui` via `su`. Passes `OPENCODE_ZEN_API_KEY` explicitly through `su` so the environment variable reaches the `hermeswebui` user. Creates `~/.local/state` and chowns it before starting (EACCES fix — opencode serve writes state files there). Skips if `opencode` binary not found. |
| `start_dashboard()` | `lib/service-dashboard.sh` | Starts the Hermes web dashboard (machine-management UI on :9119) as `hermeswebui`. Controlled by `HERMES_DASHBOARD_ENABLED`. |
| `start_browser_vnc()` | `lib/service-browser-vnc.sh` | Starts the Browser/VNC human-in-the-loop stack (Xvfb + openbox + x11vnc + websockify + Chromium). All processes run as `hermeswebui`. Controlled by `BROWSER_HUMAN_LOOP_ENABLED`. |
| `init_wiki()` | `lib/wiki-init.sh` | Initializes wiki directory at `$WIKI_DIR` with SCHEMA.md backbone, index.md, log.md, and subdirectories. Idempotent — skips if SCHEMA.md already exists. All dirs/files chowned to `OPENCODE_USER`. |
| `append_skills_external_dirs()` | `lib/config-hermes.sh` | Appends `skills.external_dirs` pointing to `${HERMES_HOME}/hermes-agent/optional-skills` in config.yaml. Must run after `ensure_agent()` because the optional-skills dir doesn't exist at config generation time. Hermes scans local skills first, then external dirs, skipping duplicates by name. Result: 72 custom + 94 built-in = 166 total visible skills. |
| `seed_righthand_man()` | `lib/profile-righthand-man.sh` | Seeds the righthand-man orchestrator profile (idempotent, requires the venv from WebUI init). |

### Model discovery details

`discover_models()` uses a 15-second curl timeout to fetch the model list from the LLM provider. The response is parsed by a python3 inline script that:

1. Extracts all model IDs from the `data` array
2. Filters out non-chat models using regex patterns (embed, whisper, tts, dall-e, sora, image, realtime, transcrib, moderat, audio, codegen, babbage, davinci, curie, ada, text-, stable, midjourney, flux, /sd/, mj, replicate, resolution)
3. Filters out litellm wildcard/model-group patterns (any ID ending with `/*`)
4. Ensures `OPENAI_DEFAULT_MODEL` is present in the final list (adds it if missing)

### Config generation details

`generate_config()` iterates `DISCOVERED_MODELS` and writes each model ID as a key in the `custom_providers[0].models` dict with a hybrid value: known families are pinned to their true context length (`resolve_ctx_len()`), the default model always gets an explicit `context_length` (fallback 262144), and unknown families are emitted as `{}` so the hermes-agent self-resolves at runtime. The `key_env: OPENAI_API_KEY` field instructs the Hermes runtime to read the API key from the environment variable at request time. The `model` section writes both `default` and `name` keys from the resolved Hermes default (`HERMES_DEFAULT_MODEL` if set, else `OPENAI_DEFAULT_MODEL`):

```yaml
model:
  provider: litellm
  default: ${HERMES_DEFAULT_MODEL or OPENAI_DEFAULT_MODEL}
  name: ${HERMES_DEFAULT_MODEL or OPENAI_DEFAULT_MODEL}
```

The `default` key is consumed by the outer WebUI's `models_cache.json` builder (`/app/api/config.py` → `get_effective_default_model()`). The `name` key is consumed by the hermes-agent as a fallback when `default` is absent. Both keys must be present to avoid the WebUI showing an empty default model.

`generate_opencode_config()` writes a JSON file with:
- A `plugin` array containing three plugins: `@tarquinen/opencode-dcp@latest`, `@franlol/opencode-md-table-formatter@latest`, `cc-safety-net`
- A `permission` block generated by a `case` statement on `OPENCODE_SECURITY_MODE` (`strict`/`standard`/`yolo`) — see `13 — Security Hardening`
- A single provider named `litellm` using `@ai-sdk/openai-compatible` npm package
- `apiKey: "{env:OPENAI_API_KEY}"` — OpenCode's env var interpolation syntax
- `baseURL` set to `OPENAI_BASE_URL` with trailing slash stripped
- `models` as an object dict `{model_id: {limit: {context: N, output: N}}}` where each model gets token limits assigned by a `get_limits()` function that pattern-matches the model ID against known families (see `10 — Model Discovery`)
- `model` as a string `"${prefix}/${model}"` where `prefix` is resolved per-model via `_resolve_provider_prefix()` — `litellm` for LiteLLM-routed models, `opencode` for Zen models (issue #46)
- `small_model` as a string `"${prefix}/${model}"` — prefix resolved independently from the default model, so a LiteLLM default and a Zen small model can coexist

After writing, the function runs `chown -R hermeswebui:hermeswebui` on the config directory so the `hermeswebui` user can read it when opencode serve starts.

### Timing

| Boot type | seed_volumes | Discovery | WebUI ready | Browser/VNC | Gateway ready | OpenCode ready | Dashboard | Total |
|-----------|-------------|-----------|-------------|-------------|---------------|----------------|-----------|-------|
| First boot | <1s | +5–15s | 60–120s (Python deps) | +2s (if enabled) | +10–20s | +5s | +3s (if enabled) | 80–160s |
| Subsequent | <1s | +5–15s | 10–20s (cached deps) | +2s (if enabled) | +5–10s | +5s | +3s (if enabled) | 25–50s |

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
== Copied opencode.jsonc to /root/.config/opencode/opencode.jsonc (root config).
== Symlinked /root/.local/share/opencode -> /home/hermeswebui/.local/share/opencode (shared session DB).
== OPENCODE_ZEN_API_KEY not set. opencode/ free models will use public fallback (may be limited).
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
- `wait` correctly keeps the container alive until any background process exits
- Auto-generated API key is printed to logs and written to config.yaml

## What Fails

- **Discovery timeout:** If the LLM provider is slow or unreachable, the 15-second curl timeout fires. Discovery falls back to `OPENAI_DEFAULT_MODEL` only, reducing the available model list to one.
- **Gateway wait timeout kills container:** If the gateway does not become healthy within 90 seconds, `wait_for_port` returns 1 and `set -e` kills the container.
- **Config not generated without OPENAI_BASE_URL:** If `OPENAI_BASE_URL` is empty, `generate_config()` returns early and `config.yaml` is not written. The WebUI and gateway run with default config (no custom provider, no api_server platform).
- **Agent copy failure is non-fatal:** If `/opt/hermes-agent-staging` is missing (should not happen in normal builds), `ensure_agent()` logs a warning but continues. The gateway then skips because the agent is not found.
- **Cosmetic has_key: false:** The WebUI `/api/providers` endpoint reports `has_key: false` for `custom:litellm` because `_provider_has_key()` only checks for a literal `api_key` field, not the `key_env` env var resolution path. Chat functionality works correctly regardless.
- **model.default vs model.name mismatch:** The outer WebUI (`/app/api/config.py`) reads `model.default` from `config.yaml` without fallback to `model.name`. The hermes-agent reads `model.default` with fallback to `model.name`. The entrypoint writes both keys to satisfy both consumers. If `default` is absent, the WebUI's `models_cache.json` gets `default_model: ""` and no model is shown in the UI.

## Resolution

- Increase the curl timeout in `discover_models()` if the provider is consistently slow (edit the `--max-time 15` flag in `lib/model-discovery.sh`).
- The 60-second gateway timeout is generous for normal operation. If gateway startup is consistently slow, increase the timeout in `wait_for_port 8642` call in `entrypoint.sh`.
- Always set `OPENAI_BASE_URL` in `.env`. Without it, the stack runs in degraded mode with no custom provider and no gateway platform.
- The agent staging path is verified during the Docker build (step 8 in `04 — Build Pipeline`). If the build passes, the staging path is guaranteed to exist.
- The `has_key: false` cosmetic issue is upstream in the Hermes WebUI code. The `resolve_custom_provider_connection()` function correctly reads `key_env: OPENAI_API_KEY` at request time, so chat works despite the display issue.
- The `model.default` vs `model.name` mismatch is resolved by the entrypoint writing both keys. Do not remove either key from `generate_config()`. See `06 — Config and Env` for details.

## Verdict

The entrypoint sequence is deterministic and well-ordered. Model discovery eliminates manual model ID management and ensures both Hermes and OpenCode see the same model list. The wildcard filter prevents a common user-facing error. The main operational risk is the discovery timeout, which gracefully degrades to a single model.
