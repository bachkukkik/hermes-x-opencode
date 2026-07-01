# 06 — Config and Env

## What

All runtime configuration is managed through environment variables defined in `.env` and processed by the entrypoint script into `config.yaml` (Hermes) and `opencode.jsonc` (OpenCode). No manual config file editing is required or persists across container restarts.

## Why

- Eliminates config file drift between environments — the same `.env` produces the same configs every time
- Enables the entrypoint to generate complete, valid configs on first boot without interactive setup
- Keeps secrets out of tracked files — `.env` is gitignored and `.env.example` contains only placeholder values
- Single model discovery pass feeds both Hermes and OpenCode configs, ensuring consistency
- WebUI onboarding is skipped entirely via environment variable, removing the interactive setup wizard

## How

### Environment variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `OPENAI_API_KEY` | Yes | — | API key for the LLM provider. Used by hermes-agent for all LLM calls and by OpenCode via `{env:OPENAI_API_KEY}`. |
| `OPENAI_BASE_URL` | Yes | — | OpenAI-compatible base URL (e.g. `https://litellm-sw.example.com/v1`). Triggers config generation and model discovery. |
| `OPENAI_DEFAULT_MODEL` | No | `openai/gpt-4o` | Default model identifier. Must match a model your provider supports. Used as the fallback default for both Hermes and OpenCode when no per-app override is set. Also used as the safety-net model for `/models` discovery. |
| `OPENAI_SMALL_MODEL` | No | falls back to `OPENAI_DEFAULT_MODEL` | Small model for lightweight OpenCode tasks (title generation, etc.). Written as `small_model` in `opencode.jsonc`. Falls back to `OPENAI_DEFAULT_MODEL` if unset. |
| `HERMES_DEFAULT_MODEL` | No | falls back to `OPENAI_DEFAULT_MODEL` | Per-app override for the Hermes default model. When set, written to `config.yaml` as both `model.default` and `model.name`. Leave unset to follow `OPENAI_DEFAULT_MODEL`. |
| `OPENCODE_DEFAULT_MODEL` | No | falls back to `OPENAI_DEFAULT_MODEL` | Per-app override for the OpenCode default model. When set, written to `opencode.jsonc` as `"model": "litellm/<value>"`. Leave unset to follow `OPENAI_DEFAULT_MODEL`. |
| `OPENCODE_SMALL_MODEL` | No | falls back to `OPENAI_SMALL_MODEL` then `OPENCODE_DEFAULT_MODEL` (resolved) | Per-app override for the OpenCode small model. When set, written to `opencode.jsonc` as `"small_model": "litellm/<value>"`. Leave unset to follow `OPENAI_SMALL_MODEL`. |
| `OPENCODE_FALLBACK_MODEL` | No | — (unset) | Runtime fallback model(s) for OpenCode. Accepts a single model id OR a comma-separated ORDERED list — `config-opencode.sh` seeds the full ordered `fallback_models` array tried in sequence after the primary fails (rate limits, quota, 5xx, timeouts). Each entry is independently provider-prefix-resolved (bare id → litellm if OpenAI creds present, else opencode Zen). Single value = 1-element chain (backward compatible). Leave unset for no fallback. |
| `OPENCODE_ZEN_API_KEY` | No | — | API key for OpenCode Zen models. Sign up at `https://opencode.ai/auth`, add billing details, copy your key. Even "free" models (deepseek-v4-flash-free, etc.) require a valid key. If you only use models from your own LLM provider (via `OPENAI_BASE_URL`), leave this empty — the litellm provider in `opencode.jsonc` will work without it. |
| `HERMES_WEBUI_SKIP_ONBOARDING` | No | — | Set to `true` to skip the WebUI onboarding wizard. Recommended for automated setups. |
| `HERMES_WEBUI_PASSWORD` | No | empty | Password-protect the WebUI. Empty = no authentication. |
| `HERMES_WEBUI_PORT` | No | `8787` | Host port for the WebUI. Container always listens on 8787. |
| `HERMES_API_KEY` | No | auto-generated | Bearer token for the Agent API (`:8642`). If empty, a random key is generated and printed to logs. |
| `HERMES_API_PORT` | No | `8642` | Host port for the Agent API. Container always listens on 8642. |
| `HERMES_YOLO_MODE` | No | `1` | Enables Hermes YOLO mode — writes `approvals.mode: off` to `config.yaml`, skipping dangerous-command approval prompts (equivalent to `hermes --yolo`). Set to `0` to restore manual approval prompts. |
| `HERMES_DELEGATION_MAX_ITERATIONS` | No | `50` | Sets `delegation.max_iterations` in `config.yaml` — the default max tool-calling turns for `delegate_task` subagents. |
| `HERMES_DELEGATION_MODEL` | No | — (unset = inherit parent model) | Sets `delegation.model` in `config.yaml` — the model used for delegated subagent conversations. By default, subagents inherit the parent's model. Set this to route subagents to a different (typically cheaper/faster) model. |
| `HERMES_DELEGATION_PROVIDER` | No | — (unset = inherit parent provider) | Sets `delegation.provider` in `config.yaml` — the provider used for delegated subagent conversations. Set alongside `HERMES_DELEGATION_MODEL` to route subagents to a different provider. If only the model is set, subagents inherit the parent's provider. |
| `HERMES_GOAL_MAX_TURNS` | No | `50` | Sets `goals.max_turns` in `config.yaml` — the cross-turn budget for the `/goal` command. Previously this was hardcapped at 20 turns inside the agent; raising this env var (e.g. to 50) lets long-running goals persist across more turns. |
| `HERMES_COMPRESSION_THRESHOLD` | No | — (unset = agent default) | Context compression threshold (fraction of context window, 0–1). When token usage reaches this fraction, the agent compresses older messages. Example: `0.76` triggers compression at 76% context usage. Transported into the container via the `environment:` block; unset = the hermes-agent uses its built-in default. See [19 — Issue Triage](../PRD.md) §19.3 CA-31-B. |
| `OPENCODE_SECURITY_MODE` | No | `strict` | Security profile for OpenCode: `strict` (31 bash rules, interpreters denied), `standard` (22 rules, interpreters allowed), `yolo` (allow all). See `13 — Security Hardening`. |
| `OPENCODE_SERVER_PASSWORD` | No | auto-generated | Password for `opencode serve` authentication. Pass via `-p` flag when attaching or running tasks. Auto-generated and printed to logs if empty. Written to `/tmp/opencode-server-password` for ephemeral `docker exec` access and to `/home/hermeswebui/.hermes/opencode_server_password` for persistent access across container restarts (bind-mounted). |
| `OPENCODE_SERVE_PORT` | No | `4096` | Host port for OpenCode serve. Container always listens on 4096. |
| `HOST_UID` | No | `1000` | Linux UID for container file processes. Match your host user UID. |
| `HOST_GID` | No | `1000` | Linux GID for container file processes. Match your host group GID. |
| `HERMES_WORKSPACE` | No | `./volumes_hermes_opencode/data/workspace` | Host path for the workspace volume mount. |
| `SKIP_SKILL_INSTALL` | No | `0` | Set `1` to skip the runtime Hermes skills staging copy and graphify hermes registration. Does not affect build-time skill installation. |
| `WIKI_PATH` | No | `/home/hermeswebui/.hermes/wiki` | Container-internal path for the llm-wiki knowledge base. Auto-created on first boot with `SCHEMA.md` backbone. The wiki stores personal knowledge base data: raw source articles, entity pages, concept pages, and cross-references using `[[wikilinks]]`. |
| `HERMES_WIKI_VOLUME` | No | — | Host path for optional wiki volume mount. When set (and the commented volume line is uncommented in `docker-compose.yml`), the container's wiki directory is backed by the host path. This lets the agent share a personal wiki with the host user. Example: `HERMES_WIKI_VOLUME=/home/username/.hermes/wiki`. |
| `BROWSER_DISPLAY_WIDTH` | No | `1920` | Width in pixels of the Xvfb virtual display that the human-in-the-loop Chromium runs on. Also drives the Chromium `--window-size` flag. The agent's CDP viewport-override calls cannot exceed this value. Lower it (e.g. `1280`) on low-RAM hosts. Only takes effect when `BROWSER_HUMAN_LOOP_ENABLED=true`. |
| `BROWSER_DISPLAY_HEIGHT` | No | `1080` | Height in pixels of the Xvfb virtual display. See `BROWSER_DISPLAY_WIDTH`. |
| `BROWSER_HUMAN_LOOP_ENABLED` | No | `false` | Enable the viewable/interactive Chromium browser stack (Xvfb + VNC + CDP on :9222). See [15 — Browser Human-in-the-Loop](15-browser-human-loop.md). |
| `BROWSER_VNC_PASSWORD` | No | `hermes` | VNC password for the browser human-in-the-loop web client (:6901). See [15 — Browser Human-in-the-Loop](15-browser-human-loop.md). |
| `OPENCODE_SERVE_ENABLED` | No | `false` | Start `opencode serve` (headless server for `opencode attach`) on :4096. Enable only with an LLM provider configured. See [03 — OpenCode Serve](03-opencode-serve.md). |
| `OPENCODE_SERVE_BOOT_TIMEOUT` | No | `30` | Seconds to wait for opencode serve to bind :4096 at boot. Non-fatal timeout. See [03 — OpenCode Serve](03-opencode-serve.md). |
| `HERMES_DASHBOARD_ENABLED` | No | `false` | Start the Hermes web dashboard (machine-management UI) on :9119. SECURITY: manages API keys. See [21 — Hermes Web Dashboard](21-dashboard.md). |
| `HERMES_DASHBOARD_PORT` | No | `9119` | Port for the Hermes web dashboard. See [21 — Hermes Web Dashboard](21-dashboard.md). |
| `HERMES_DASHBOARD_HOST` | No | `0.0.0.0` | Bind host for the Hermes web dashboard. Set to `127.0.0.1` to restrict. See [21 — Hermes Web Dashboard](21-dashboard.md). |

### Hardcoded environment (in docker-compose.yml)

| Variable | Value | Why hardcoded |
|----------|-------|---------------|
| `WANTED_UID` | `${HOST_UID:-1000}` | Mapped from HOST_UID |
| `WANTED_GID` | `${HOST_GID:-1000}` | Mapped from HOST_GID |
| `HERMES_WEBUI_HOST` | `0.0.0.0` | Must bind to all interfaces for port mapping |
| `HERMES_WEBUI_PORT` | `8787` | Container-side port (not host-side) |
| `HERMES_WEBUI_STATE_DIR` | `/home/hermeswebui/.hermes/webui` | Persisted via bind mount |
| `HERMES_WEBUI_DEFAULT_WORKSPACE` | `/workspace` | Container-side workspace path |
| `HERMES_HOME` | `/home/hermeswebui/.hermes` | Ensures gateway finds config.yaml |

### config.yaml (Hermes)

The entrypoint generates `config.yaml` at `/home/hermeswebui/.hermes/config.yaml`. Both the WebUI and the Agent Gateway read this single file. The `models` dict contains all discovered chat models. The `model` section writes both `default` and `name` keys — the WebUI reads `default`, the agent reads `name` as fallback:

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
        context_length: 1000000
      openai/gpt-4o:
        context_length: 128000
      z.ai/glm-5.2:
        context_length: 1048576
      some/unknown-model: {}    # unknown family -> agent self-resolves
      # ... all discovered models
    key_env: OPENAI_API_KEY

platforms:
  api_server:
    enabled: true
    extra:
      host: "0.0.0.0"
      port: 8642
      key: "hermes-<auto-generated>"
      cors_origins: "*"

approvals:
  mode: off

delegation:
  max_iterations: 50
```

### opencode.jsonc (OpenCode)

The entrypoint generates `opencode.jsonc` at `/home/hermeswebui/.config/opencode/opencode.jsonc`. The file is written as root then chowned to `hermeswebui`. OpenCode serve reads this on startup (it runs as `hermeswebui` via `su`):

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": [
    "@tarquinen/opencode-dcp@latest",
    "@franlol/opencode-md-table-formatter@latest",
    "cc-safety-net"
  ],
  "permission": {
    // Generated based on OPENCODE_SECURITY_MODE (see 13 — Security Hardening)
  },
  "provider": {
    "litellm": {
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "apiKey": "{env:OPENAI_API_KEY}",
        "baseURL": "https://litellm-sw.example.com/v1"
      },
      "models": {
        "anthropic/claude-opus-4-6": {},
        "openai/gpt-4o": {},
        "z.ai/glm-5.2": {}
      }
    }
  },
  "model": "litellm/z.ai/glm-5.2",
  "small_model": "opencode/deepseek-v4-flash-free"
}
```

Key constraints for the OpenCode config:
- `plugin` is an array of npm spec strings or `[name, options]` tuples. Three plugins are configured: `@tarquinen/opencode-dcp` (context pruning), `@franlol/opencode-md-table-formatter` (markdown tables), and `cc-safety-net` (destructive command blocking). See `12 — Plugin System`.
- `permission` block is generated by `case` statement on `OPENCODE_SECURITY_MODE`. In `strict` mode, contains 31 bash denial rules, .env read/edit/grep denial, and interpreter one-liner blocking. See `13 — Security Hardening`.
- `models` must be an object `{}`, not an array `[]`. Each key is a model ID, each value is `{}`.
- `model` and `small_model` are strings with a provider prefix determined independently per model by `_resolve_provider_prefix()` (see Per-model provider routing below).
- `apiKey` uses OpenCode's `{env:VAR_NAME}` interpolation syntax. Custom providers (`@ai-sdk/openai-compatible`) do not auto-detect env vars.

### Per-model provider routing

`config-opencode.sh` uses `_resolve_provider_prefix()` to determine the provider prefix for each model independently. This allows the default model to route through a self-hosted LiteLLM proxy while the small model routes through OpenCode Zen (or vice versa), without any manual configuration.

**Decision table:**

| Model name pattern | Resolved prefix | Routed to |
|--------------------|-----------------|-----------|
| `opencode/*` | `opencode` | OpenCode Zen (requires `OPENCODE_ZEN_API_KEY`) |
| `litellm/*` | `litellm` | Self-hosted LiteLLM proxy (requires `OPENAI_BASE_URL` + `OPENAI_API_KEY`) |
| Any other name + `OPENAI_BASE_URL` set | `litellm` | Self-hosted LiteLLM proxy |
| Any other name + no `OPENAI_BASE_URL` | `opencode` | OpenCode Zen public fallback |

**Backward compatibility:**

| Topology | Before (single-prefix) | After (per-model) | Change? |
|----------|------------------------|--------------------|---------|
| Zen-only (`OPENCODE_ZEN_API_KEY` set, no `OPENAI_BASE_URL`) | `opencode/X`, `opencode/Y` | Same | None |
| LiteLLM-only (`OPENAI_BASE_URL` set, no `OPENCODE_ZEN_API_KEY`) | `litellm/X`, `litellm/Y` | Same | None |
| Dual (both keys set) | `litellm/X`, `litellm/Y` (bug: small model routed to LiteLLM even for Zen models) | Each model gets its correct prefix | **Bug fix** — Zen models now correctly route to Zen |

The only behavioral change is in dual-provider mode. Previously, both `model` and `small_model` always received the `litellm` prefix, causing 401 errors when the small model was a Zen-only model (e.g. `deepseek-v4-flash-free`). With per-model routing, each model's prefix is resolved independently based on its name.

**OpenCode provider block.** When `OPENCODE_ZEN_API_KEY` is set, an explicit `opencode` provider entry is generated in `opencode.jsonc` alongside the `litellm` provider (if OpenAI credentials are also present). This ensures built-in `opencode/` models (like `deepseek-v4-flash-free`) have an explicit API key mapping rather than relying on implicit resolution:

```jsonc
"provider": {
  "opencode": {
    "options": {
      "apiKey": "{env:OPENCODE_ZEN_API_KEY}"
    }
  },
  "litellm": {
    "npm": "@ai-sdk/openai-compatible",
    "options": {
      "apiKey": "{env:OPENAI_API_KEY}",
      "baseURL": "https://litellm-sw.example.com/v1"
    },
    "models": { ... }
  }
}
```

As a fallback credential store, `auth.json` is seeded at `~/.local/share/opencode/auth.json` with entries for each available provider. When `OPENCODE_ZEN_API_KEY` is set, an `opencode` entry is written; when `OPENAI_API_KEY` is set, a `litellm` entry is written. The seeding guard uses OR logic (`$_has_opencode_key || $_has_openai_creds`), so even when `OPENCODE_ZEN_API_KEY` is unset (the `.env.example` default), the litellm proxy credential is seeded — letting OpenCode CLI resolve at least one credential (the litellm proxy) without a built-in Zen key. This covers code paths that read credentials from the auth store rather than the config provider block, and resolves the 'OpenCode unavailable (0 credentials)' report from the righthand-man orchestrator profile (PRD.md §19.3 CA-30-A). Additionally, `OPENCODE_ZEN_API_KEY` is passed explicitly through `su` in `service-opencode.sh` so that the environment variable is available to the `hermeswebui` user when `opencode serve` starts.

### Runtime environment detection

The entrypoint sources `lib/runtime-env.sh`, which provides two helpers for adapting to the execution environment:

- **`detect_runtime_env()`** — Determines whether the container is running in Docker or on bare Linux. Precedence: `RUNTIME_ENV` env var > `/.dockerenv` presence > `KUBERNETES_SERVICE_HOST` presence > default `local`. Logs the detected mode and source to stderr.
- **`normalize_base_url_for_local(url)`** — When running in `local` mode (not Docker), replaces `host.docker.internal` with `localhost` in `OPENAI_BASE_URL`. This allows the same `.env` file to work both inside Docker (where `host.docker.internal` resolves via Docker DNS) and on bare metal (where it does not).

| Mode | `host.docker.internal` handling | Typical use |
|------|--------------------------------|-------------|
| `docker` | No substitution | Normal container deployment |
| `local` | Replaced with `localhost` | Bare-metal / WSL testing with the same `.env` |

### Zen API key validation

At startup, the entrypoint calls `validate_opencode_zen_key()` (sourced from `lib/validate-opencode.sh`), which makes an **outbound HTTP request** to `https://opencode.ai/zen/v1/models` using the `OPENCODE_ZEN_API_KEY` to verify the key is valid. This call has a 10-second timeout. If the key is empty, the check is skipped with an informational message. If the key is set but validation fails, a warning is logged — the container always continues starting (non-fatal). This validation helps catch invalid keys early instead of discovering 401 errors during first use.

### Startup outbound calls

| Call | URL | Trigger | Timeout | Fatal? |
|------|-----|---------|---------|--------|
| Model discovery | `${OPENAI_BASE_URL}/models` | `OPENAI_BASE_URL` is set | 15s | Yes (falls back to single model) |
| Zen API key validation | `https://opencode.ai/zen/v1/models` | `OPENCODE_ZEN_API_KEY` is set | 10s | No |

### Config path resolution

| Service | Config path | Reads via |
|---------|------------|-----------|
| Hermes WebUI | `/home/hermeswebui/.hermes/config.yaml` | `api/config.py` → `get_active_hermes_home() / "config.yaml"` |
| Hermes Agent Gateway | `/home/hermeswebui/.hermes/config.yaml` | `gateway/run.py` → `get_hermes_home() / "config.yaml"` |
| OpenCode Serve | `/home/hermeswebui/.config/opencode/opencode.jsonc` | OpenCode binary reads `$HOME/.config/opencode/opencode.jsonc` (runs as hermeswebui) |
| OpenCode (root / docker exec) | `/root/.config/opencode/opencode.jsonc` | Copy of hermeswebui's config — ensures root sees providers when invoked via `terminal()` tool (fix #28) |
| OpenCode session DB (root) | `/root/.local/share/opencode/` | Symlink → `/home/hermeswebui/.local/share/opencode/` — ensures root shares the session DB (fix #29) |

## Verification

```bash
docker exec <container> cat /home/hermeswebui/.hermes/config.yaml
docker exec <container> cat /home/hermeswebui/.config/opencode/opencode.jsonc
docker exec <container> env | grep -E "HERMES_HOME|OPENAI_BASE_URL|HERMES_DEFAULT_MODEL|OPENCODE_DEFAULT_MODEL|OPENCODE_SMALL_MODEL|OPENCODE_SECURITY_MODE"
docker logs <container> 2>&1 | grep "Generated random HERMES_API_KEY"
```

## What Works

- Config regeneration is idempotent and consistent across boots
- Both Hermes configs (WebUI + Gateway) share the same `config.yaml` with identical model lists
- OpenCode config uses env var interpolation (`{env:OPENAI_API_KEY}`), avoiding hardcoded secrets
- Auto-generated API key enables the gateway even when `HERMES_API_KEY` is not explicitly set
- All env vars are passed from `.env` through docker-compose to the container
- Onboarding is skipped when `HERMES_WEBUI_SKIP_ONBOARDING=true`

## What Fails

- **Config not generated if OPENAI_BASE_URL is empty:** Both `generate_config()` and `generate_opencode_config()` return early. No config files are written. The WebUI falls back to default config (no custom provider).
- **Manual config edits lost on restart:** Both `config.yaml` and `opencode.jsonc` are overwritten on every boot. Any changes made inside the container are discarded.
- **.env not tracked in git:** New collaborators must copy `.env.example` to `.env` and fill in values manually. There is no validation that required vars are set.
- **Cosmetic has_key: false:** The WebUI `/api/providers` endpoint reports `has_key: false` for `custom:litellm` because it only checks literal `api_key` fields, not `key_env` env var resolution. Chat works correctly regardless.
- **Missing model.default key breaks WebUI model display:** The outer WebUI (`/app/api/config.py`) reads `model.default` from `config.yaml` to populate `models_cache.json`'s `default_model` field. The hermes-agent reads `model.default` with fallback to `model.name`. The entrypoint writes both keys to satisfy both consumers. If only `name` is present, the WebUI shows no default model.

## Resolution

- Always set `OPENAI_BASE_URL` in `.env`. This is the trigger for config generation.
- All configuration changes must be made in `.env`, not inside the container. Restart the container to apply: `docker compose restart`.
- Copy `.env.example` to `.env` and fill in all required values. Add a startup check in the entrypoint to validate required env vars and exit with a clear error message if they are missing (not currently implemented).
- The `has_key: false` issue is cosmetic. The `key_env: OPENAI_API_KEY` field is correctly resolved at request time by `resolve_custom_provider_connection()`.
- The entrypoint writes both `model.default` and `model.name` to `config.yaml`. Both keys must be present. Removing `default` causes the WebUI's `models_cache.json` to have an empty `default_model` field. Removing `name` breaks the hermes-agent's fallback path.

## Verdict

The env-driven config approach is clean, reproducible, and covers both Hermes and OpenCode from a single model discovery pass. The env var interpolation for OpenCode's API key avoids hardcoded secrets. The main gap is the lack of validation for required environment variables at startup.
