# PRD: Hermes x OpenCode Docker Stack

## 1. Product Overview

A Docker Compose stack that runs [Hermes WebUI](https://github.com/nicholasgriffintn/hermes-webui) + [Hermes Agent](https://github.com/NousResearch/hermes-agent) + [OpenCode CLI](https://opencode.ai) in a single container with three exposed services:

| Service | Port | Purpose |
|---------|------|---------|
| Hermes WebUI | :8787 | Browser-based chat interface |
| Hermes Agent API | :8642 | OpenAI-compatible endpoint (`/v1/chat/completions`) |
| OpenCode Serve | :4096 | Headless server for remote `opencode attach` |

**Data flow:** User → Browser/WebUI OR API client → Hermes Agent → OpenCode CLI (terminal tool) → LLM Provider (external)

## 2. Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│  Container: hermes-opencode (service name in docker-compose)         │
│                                                                      │
│  ┌──────────────────────────┐                                        │
│  │  Hermes WebUI            │  :8787 (browser chat UI)               │
│  │  ┌────────────────────┐  │                                        │
│  │  │ Python server      │  │  imports hermes_cli, creates           │
│  │  │ (ghcr.io/nesquena/ │──│──> AIAgent → run_conversation()        │
│  │  │  hermes-webui)     │  │                                        │
│  │  └────────────────────┘  │                                        │
│  └──────────────────────────┘                                        │
│                                                                      │
│  ┌──────────────────────────┐                                        │
│  │  Hermes Gateway          │  :8642 (OpenAI-compatible API)         │
│  │  (hermes gateway run     │                                        │
│  │   --accept-hooks)        │  /v1/chat/completions (streaming)      │
│  │  ┌────────────────────┐  │  /v1/responses                        │
│  │  │ api_server platform│  │  /v1/runs                             │
│  │  └────────────────────┘  │  /health                              │
│  └──────────────────────────┘                                        │
│                                                                      │
│  ┌──────────────────────────┐                                        │
│  │  OpenCode Serve          │  :4096 (headless server)               │
│  │  (opencode serve)        │                                        │
│  │                          │  Remote attach via:                    │
│  │    opencode attach       │    opencode attach http://host:4096    │
│  └──────────────────────────┘                                        │
│                                                                      │
│  Shared:                                                             │
│    Bind mount: /home/hermeswebui/.hermes/                            │
│      config.yaml         — Generated at startup (multi-model)        │
│      hermes-agent/        — Copied from staging on first boot        │
│      state.db             — Session history (SQLite)                 │
│      skills/, logs/, webui/                                          │
│                                                                      │
│  OpenCode config:                                                    │
│    /home/hermeswebui/.config/opencode/opencode.jsonc                 │
│      — Generated at startup (plugins, permissions, provider)         │
│                                                                      │
│  External:                                                           │
│    LLM Provider (OpenAI-compatible endpoint via OPENAI_BASE_URL)     │
│    OpenCode auth (OPENCODE_API_KEY)                                  │
└──────────────────────────────────────────────────────────────────────┘
```

### Component Roles

| Component | Source | Role |
|-----------|--------|------|
| Hermes WebUI | `ghcr.io/nesquena/hermes-webui:latest` | Browser UI, HTTP server, agent host process |
| Hermes Gateway | `/app/venv/bin/hermes gateway run --accept-hooks` | OpenAI-compatible API on :8642 |
| Hermes Agent | `https://github.com/NousResearch/hermes-agent.git` | AI agent runtime, runs in-process |
| OpenCode CLI | Official install script (`opencode.ai/install`) | Autonomous coding agent via `terminal` tool |
| OpenCode Serve | `opencode serve` | Headless server for remote `opencode attach` |
| Node.js 22 | nodesource setup script | Required for OpenCode plugin resolution |
| LLM Provider | External (user-configured) | OpenAI-compatible API endpoint |

## 3. Tech Stack

| Layer | Technology | Version/Source |
|-------|-----------|----------------|
| Base image | `ghcr.io/nesquena/hermes-webui:latest` | Pre-built WebUI image |
| Agent source | `NousResearch/hermes-agent` | Git clone to staging path, branch configurable via build arg |
| Coding agent | OpenCode CLI | Latest from official install script |
| Node.js | 22.x | Required for OpenCode plugin npm resolution |
| Platform | Linux ARM64 | Must build and run on ARM64 (Raspberry Pi) |
| Orchestration | Docker Compose v2 | Single service, one container |
| Skill sources | Anthropic, OpenAI, community repos, PyPI | 6 upstream sources, installed at boot |

## 4. File Inventory

```
.
├── docker-compose.yml                                    # Service definition: 3 ports, bind mounts, env, healthcheck
├── .env.example                                          # All supported env vars with defaults and descriptions
├── .gitignore                                            # .env (Python boilerplate, 220 lines)
├── PRD.md                                                # This file
├── README.md                                             # User-facing documentation
├── docs/                                                 # Architecture documentation (01–13)
└── volumes_hermes_opencode/
    ├── .gitkeep
    ├── .gitignore                                        # Ignores data contents, keeps .gitkeep
    ├── .dockerignore                                     # Excludes data/ from build context
    ├── build/
    │   ├── .dockerignore                                 # .git, .env, *.pyc, __pycache__, workspace/
    │   ├── Dockerfile                                    # Multi-step build: base + packages + node + opencode + agent + patch
    │   └── scripts/
    │       ├── entrypoint.sh                             # Runtime: model discovery, config gen, start 3 services
    │       └── install-skills.sh                         # Installs skills from 6 upstream sources
    └── data/
        ├── hermes-home/.gitkeep                          # Bind mount: /home/hermeswebui/.hermes
        └── workspace/.gitkeep                            # Bind mount: /workspace
```

## 5. File Specifications

### 5.1 `Dockerfile` (at `volumes_hermes_opencode/build/Dockerfile`)

**Purpose:** Build a single image containing WebUI + system packages + Node.js + OpenCode CLI + staged agent source + Cloudflare UA patch.

**Build steps (in this exact order):**

```dockerfile
FROM ghcr.io/nesquena/hermes-webui:latest

ARG HERMES_AGENT_VERSION=main

# Step 1: System packages
RUN apt-get update -y --no-install-recommends \
    && apt-get install -y --no-install-recommends \
       build-essential git ripgrep ffmpeg procps curl \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Step 2: Install Node.js 22 (required for OpenCode plugin resolution)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && node --version && npm --version

# Step 3: Install OpenCode CLI
RUN curl -fsSL https://opencode.ai/install | bash \
    && if [ -f /root/.opencode/bin/opencode ]; then \
         cp /root/.opencode/bin/opencode /usr/local/bin/opencode; \
       fi \
    && opencode --version

# Step 4: Clone hermes-agent to staging path (not the runtime path)
RUN git clone --depth 1 --branch ${HERMES_AGENT_VERSION} \
    https://github.com/NousResearch/hermes-agent.git \
    /opt/hermes-agent-staging

# Step 5: Patch CustomProfile to set User-Agent header
RUN sed -i 's/base_url="",/base_url="",\n    default_headers={"User-Agent": "hermes-agent\/1.0"},/' \
    /opt/hermes-agent-staging/plugins/model-providers/custom/__init__.py

# Step 6: Copy scripts and set executable
COPY scripts/install-skills.sh /usr/local/bin/install-skills.sh
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/install-skills.sh /usr/local/bin/entrypoint.sh

# Step 7: Verification
RUN echo "=== Hermes x OpenCode Stack ===" \
    && python3 -c "import sys; print(f'Python: {sys.version}')" \
    && opencode --version \
    && test -f /opt/hermes-agent-staging/pyproject.toml \
    && grep -q '"User-Agent".*"hermes-agent' /opt/hermes-agent-staging/plugins/model-providers/custom/__init__.py \
    && echo "================================"

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
```

**Key requirements:**
- Agent is cloned to `/opt/hermes-agent-staging`, NOT to the runtime path. The entrypoint copies it to the bind mount on first boot.
- Node.js 22 is required for OpenCode's npm-based plugin resolution at runtime.
- Both `install-skills.sh` and `entrypoint.sh` are copied into the image.
- The verification step at the end catches missing agent, failed patch, or missing OpenCode.
- `HERMES_AGENT_VERSION` build arg defaults to `main`. Override with `--build-arg HERMES_AGENT_VERSION=v1.2.3`

### 5.2 `scripts/entrypoint.sh` (at `volumes_hermes_opencode/build/scripts/entrypoint.sh`)

**Purpose:** Discover available models from the LLM provider, generate configuration files for both Hermes and OpenCode, install skills, copy the staged agent, and start three background services in dependency order.

**Requirements:**
- Must be executable (`chmod +x`)
- Must use `set -euo pipefail`
- Runs as root (PID 1). Gateway and OpenCode serve are started via `su -s /bin/bash hermeswebui -c "..."` for reduced privileges.

**Key variables:**

| Variable | Value | Purpose |
|----------|-------|---------|
| `HERMES_HOME` | `/home/hermeswebui/.hermes` | Hermes state directory |
| `OPENCODE_USER` | `hermeswebui` | Non-root user for gateway and opencode serve |
| `OPENCODE_CONFIG` | `/home/hermeswebui/.config/opencode/opencode.jsonc` | Generated OpenCode config |
| `OPENCODE_SKILLS_DIR` | `/home/hermeswebui/.config/opencode/skills` | Skills install target |
| `STAGING_DIR` | `/opt/hermes-agent-staging` | Build-time agent source |
| `AGENT_DIR` | `/home/hermeswebui/.hermes/hermes-agent` | Runtime agent path (bind mount) |

**Functions:**

| Function | Purpose |
|----------|---------|
| `discover_models()` | Curls `OPENAI_BASE_URL/models` with API key. Filters non-chat models (embed, whisper, tts, dall-e, sora, etc.) and wildcard patterns. Falls back to `OPENAI_DEFAULT_MODEL` only on failure. Sets `DISCOVERED_MODELS`. |
| `generate_config()` | Writes `config.yaml` with litellm custom provider, multi-model `models` dict, `api_server` platform. Auto-generates API key if `HERMES_API_KEY` is empty. Writes both `model.default` and `model.name`. |
| `generate_opencode_config()` | Writes `opencode.jsonc` with plugins, permission block (based on `OPENCODE_SECURITY_MODE`), and provider config. Chowns to `hermeswebui`. |
| `ensure_agent()` | Copies agent from `/opt/hermes-agent-staging` to bind mount if not already present. Idempotent. |
| `wait_for_port(port, timeout)` | Loops curl on health endpoint every 2 seconds until ready or timeout. |
| `start_gateway()` | Starts gateway as `hermeswebui` via `su`. Command: `/app/venv/bin/hermes gateway run --accept-hooks`. Skips if agent not found. |
| `start_opencode_serve()` | Starts OpenCode serve as `hermeswebui` via `su`. Command: `opencode serve --port 4096 --hostname 0.0.0.0`. |

**Startup sequence:**
1. Install skills (`install-skills.sh`) — 6 upstream sources, can skip with `SKIP_SKILL_INSTALL=1`
2. `discover_models()` — discover all chat models from provider
3. `generate_config()` — write `config.yaml` with multi-model support
4. `generate_opencode_config()` — write `opencode.jsonc` with plugins, permissions, provider
5. `ensure_agent()` — copy staged agent to bind mount (first boot only)
6. Start `/hermeswebui_init.bash` in background
7. Wait for port 8787 to be healthy (timeout 120s)
8. Start hermes gateway (`/app/venv/bin/hermes gateway run --accept-hooks`) in background
9. Wait for port 8642 to be healthy (timeout 60s)
10. Start `opencode serve --port 4096 --hostname 0.0.0.0` in background
11. `wait -n` to keep container alive (exits if any background process dies)

**Model discovery filter patterns:**
Non-chat models matching: embed, whisper, tts, dall-e, sora, image, realtime, transcrib, moderat, audio, codegen, babbage, davinci, curie, ada, text-, stable, midjourney, flux, /sd/, mj, replicate, resolution. Also filters litellm wildcard patterns (IDs ending with `/*`).

**Security modes:**

| Mode | `OPENCODE_SECURITY_MODE` | Bash rules | Interpreters | .env files | Use case |
|------|--------------------------|-----------|-------------|------------|----------|
| Strict | `strict` (default) | 31 | DENIED | DENIED | Production |
| Standard | `standard` | 22 | ALLOWED | DENIED | Development |
| Yolo | `yolo` | 0 (allow all) | ALLOWED | ALLOWED | Trusted sandbox |

### 5.3 `docker-compose.yml`

**Purpose:** Define the single service with bind mounts, environment, and healthcheck.

**Requirements:**
- Service name: `hermes-opencode`
- Build context: `./volumes_hermes_opencode/build`
- No `command:` block — the Dockerfile `ENTRYPOINT` handles everything
- No `entrypoint:` override — let the Dockerfile's ENTRYPOINT work

**Ports:**
| Host mapping | Container | Purpose |
|-------------|-----------|---------|
| `${HERMES_WEBUI_PORT:-8787}:8787` | 8787 | Hermes WebUI (browser) |
| `${HERMES_API_PORT:-8642}:8642` | 8642 | Hermes Agent API (OpenAI-compatible) |
| `${OPENCODE_SERVE_PORT:-4096}:4096` | 4096 | OpenCode Serve (remote attach) |

**Volumes (bind mounts):**
| Mount | Purpose |
|-------|---------|
| `./volumes_hermes_opencode/data/hermes-home:/home/hermeswebui/.hermes` | Agent config, sessions, skills, state.db |
| `${HERMES_WORKSPACE:-./volumes_hermes_opencode/data/workspace}:/workspace` | User's project workspace |

**Environment variables (all from `.env`):**
| Variable | Required | Description |
|----------|----------|-------------|
| `OPENAI_API_KEY` | Yes | API key for the LLM provider |
| `OPENAI_BASE_URL` | Yes | Base URL for the LLM provider endpoint |
| `OPENAI_DEFAULT_MODEL` | No | Model identifier (default: `openai/gpt-4o`) |
| `OPENCODE_API_KEY` | Yes | API key for OpenCode CLI |
| `HERMES_WEBUI_SKIP_ONBOARDING` | No | Skip WebUI onboarding wizard (set `true`) |
| `HERMES_WEBUI_PASSWORD` | No | Optional password for the WebUI |
| `HERMES_WEBUI_PORT` | No | Host port for WebUI (default: 8787) |
| `HERMES_API_KEY` | No | Bearer token for Agent API (empty = auto-generated) |
| `HERMES_API_PORT` | No | Host port for Agent API (default: 8642) |
| `OPENCODE_SERVE_PORT` | No | Host port for OpenCode serve (default: 4096) |
| `SKIP_SKILL_INSTALL` | No | Skip skill installation (set `1`) |
| `OPENCODE_SECURITY_MODE` | No | Security profile: strict/standard/yolo (default: strict) |
| `HOST_UID` | No | UID for file permissions (default: 1000) |
| `HOST_GID` | No | GID for file permissions (default: 1000) |

**Additional environment (hardcoded in compose):**
- `WANTED_UID`, `WANTED_GID` — mapped from `HOST_UID`/`HOST_GID`
- `HERMES_WEBUI_HOST=0.0.0.0`
- `HERMES_WEBUI_PORT=8787` (container-side, not host-side)
- `HERMES_WEBUI_STATE_DIR=/home/hermeswebui/.hermes/webui`
- `HERMES_WEBUI_DEFAULT_WORKSPACE=/workspace`
- `HERMES_HOME=/home/hermeswebui/.hermes`

**Healthcheck:**
```
test: ["CMD", "curl", "-f", "http://localhost:8787/health"]
interval: 10s
timeout: 5s
start_period: 30s
retries: 10
```

**Restart policy:** `unless-stopped`

**Network:** Default network with alias `hermes-opencode`

### 5.4 `.env.example`

Contains all environment variables listed above with:
- Comment explaining what each variable does
- Example/default value
- Clear marking of required vs optional
- Detailed descriptions for security modes

### 5.5 `.gitignore`

Standard Python boilerplate (220 lines). Key entries: `.env`, `__pycache__/`, `.venv`, `*.egg-info/`, etc.

### 5.6 `.dockerignore`

Two `.dockerignore` files exist:

**`volumes_hermes_opencode/.dockerignore`** (build context root):
```
data/
.git
.gitignore
```

**`volumes_hermes_opencode/build/.dockerignore`**:
```
.git
.env
*.pyc
__pycache__
workspace/
```

No `.dockerignore` exists at the project root — the build context is `volumes_hermes_opencode/build/`.

## 6. Startup Sequence

### First Boot

```
 1. Container starts, ENTRYPOINT runs /usr/local/bin/entrypoint.sh
 2. Install skills from 6 upstream sources (15–45s, skip with SKIP_SKILL_INSTALL=1)
 3. Discover models: curl OPENAI_BASE_URL/models, filter non-chat + wildcards (5–15s)
 4. Generate config.yaml with multi-model support (all discovered chat models)
 5. Generate opencode.jsonc with plugins, permissions, provider
 6. Copy agent from /opt/hermes-agent-staging to bind mount (~2s)
 7. Start /hermeswebui_init.bash in background
 8. WebUI init script (background):
    a. Sets up UID/GID
    b. Installs hermes-agent Python deps
    c. Starts the WebUI HTTP server on :8787
 9. Wait for port 8787 to respond to /health (timeout: 120s)
10. Start hermes gateway: /app/venv/bin/hermes gateway run --accept-hooks
11. Wait for port 8642 to respond to /health (timeout: 60s)
12. Start opencode serve --port 4096 --hostname 0.0.0.0
13. wait -n to keep container alive
```

**Expected first boot time:** 80–160 seconds (skill install + Python deps + model discovery)

### Subsequent Boots

```
 1. Install skills (OpenCode skills are ephemeral, always reinstalled)
 2. Re-discover models (idempotent)
 3. Regenerate config.yaml and opencode.jsonc (idempotent overwrite)
 4. Agent already present in bind mount (skips copy)
 5. WebUI init: deps already installed, fast startup (~10-20s)
 6. Gateway starts: deps already installed (~5-10s)
 7. OpenCode serve starts (~2-5s)
 8. All ports ready
```

**Expected subsequent boot time:** 25–50 seconds

### Key Behaviors

- `config.yaml` and `opencode.jsonc` are regenerated on every boot from env vars and model discovery. Manual edits inside the container are lost on restart.
- Model discovery is idempotent — same provider URL produces same model list every boot.
- The hermes-agent source is copied from the image's staging path to the bind mount on first start. It persists across container restarts.
- Session history, skills, and memories persist in the `hermes-home` bind mount across container restarts and rebuilds.
- OpenCode skills are ephemeral (no volume mount) and reinstalled on every boot. Hermes skills persist in the bind mount.
- All three services run as background processes. If any process exits, the container shuts down (`wait -n`).
- The gateway and opencode serve are started as `hermeswebui` user (not root) via `su`.
- Both `model.default` and `model.name` are written to `config.yaml` to satisfy both the WebUI's `models_cache.json` builder and the hermes-agent's model resolution.

## 7. Configuration Reference

### Environment Variables

| Variable | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `OPENAI_API_KEY` | string | **Yes** | — | API key for the LLM provider. Used by hermes-agent for all LLM calls and by OpenCode via `{env:OPENAI_API_KEY}`. |
| `OPENAI_BASE_URL` | string | **Yes** | — | OpenAI-compatible base URL for the LLM provider. Triggers config generation and model discovery. |
| `OPENAI_DEFAULT_MODEL` | string | No | `openai/gpt-4o` | Default model identifier. Must match a model your provider supports. All other chat models are auto-discovered. |
| `OPENCODE_API_KEY` | string | **Yes** | — | API key for OpenCode CLI. Obtained from https://opencode.ai |
| `HERMES_WEBUI_SKIP_ONBOARDING` | string | No | — | Set to `true` to skip the WebUI onboarding wizard. |
| `HERMES_WEBUI_PASSWORD` | string | No | empty | Password-protect the WebUI. Empty = no authentication. |
| `HERMES_WEBUI_PORT` | int | No | `8787` | Host port for the WebUI. Container always listens on 8787 internally. |
| `HERMES_API_KEY` | string | No | auto-generated | Bearer token for the Hermes Agent API. Auto-generated random key if empty. Printed to container logs. |
| `HERMES_API_PORT` | int | No | `8642` | Host port for the Hermes Agent API. Container always listens on 8642 internally. |
| `OPENCODE_SECURITY_MODE` | string | No | `strict` | Security profile for OpenCode: `strict` (31 bash rules), `standard` (22 rules), `yolo` (allow all). |
| `OPENCODE_SERVE_PORT` | int | No | `4096` | Host port for OpenCode serve. Container always listens on 4096 internally. |
| `SKIP_SKILL_INSTALL` | string | No | `0` | Set to `1` to skip skill installation at container start. |
| `HOST_UID` | int | No | `1000` | Linux UID for container file processes. Match your host user UID. |
| `HOST_GID` | int | No | `1000` | Linux GID for container file processes. Match your host group GID. |
| `HERMES_WORKSPACE` | string | No | `./volumes_hermes_opencode/data/workspace` | Host path for the workspace volume mount. |

### Build Arguments

| Argument | Default | Description |
|----------|---------|-------------|
| `HERMES_AGENT_VERSION` | `main` | Git branch or tag for hermes-agent clone. E.g. `main`, `v1.0.0`, `develop` |

## 8. Constraints

| ID | Constraint | Rationale |
|----|-----------|-----------|
| C1 | Must build and run on Linux ARM64 (Raspberry Pi) | Target deployment hardware |
| C2 | No secrets in any tracked file | Repo is published publicly |
| C3 | `config.yaml` `key_env` must be literal string `OPENAI_API_KEY`, never the expanded value | Shell expansion in heredocs will break the agent's key resolution |
| C4 | The CustomProfile User-Agent patch must survive across hermes-agent version updates | If the sed pattern breaks on a new version, the build must fail (not silently skip) |
| C5 | Container must not require interactive setup | Fully unattended startup from `docker compose up -d` |
| C6 | Second boot must be fast (<30s to healthcheck pass) | Agent deps cached, no network fetch on restart |
| C7 | Both `model.default` and `model.name` must be written to `config.yaml` | The WebUI reads `model.default`; the agent reads `model.name` as fallback |
| C8 | Agent must be cloned to staging path, not runtime path | Runtime path is a bind mount that starts empty on first boot |
| C9 | Node.js 22 must be installed in the image | Required for OpenCode's npm-based plugin resolution |

## 9. Acceptance Criteria

| # | Test | Expected Result | How to Verify |
|---|------|----------------|---------------|
| AC1 | Build the image | `docker compose build` succeeds without error | `docker compose build` |
| AC2 | Start the container | `docker compose up -d` starts without error | `docker compose up -d && docker compose ps` shows `running` |
| AC3 | Healthcheck passes | Container reports healthy | `docker inspect --format='{{.State.Health.Status}}' $(docker compose ps -q hermes-opencode)` returns `healthy` |
| AC4 | WebUI responds | HTTP 200 on health endpoint | `curl -f http://localhost:${HERMES_WEBUI_PORT:-8787}/health` |
| AC5 | Agent source present | hermes-agent copied to bind mount | `docker exec $C test -f /home/hermeswebui/.hermes/hermes-agent/pyproject.toml && echo OK` |
| AC6 | CustomProfile patched | User-Agent header set in CustomProfile | `docker exec $C grep -q '"User-Agent".*"hermes-agent' /home/hermeswebui/.hermes/hermes-agent/plugins/model-providers/custom/__init__.py && echo OK` |
| AC7 | config.yaml generated | Custom provider with multi-model dict | `docker exec $C grep -q 'key_env: OPENAI_API_KEY' /home/hermeswebui/.hermes/config.yaml && echo OK` |
| AC8 | OpenCode available | CLI binary exists and runs | `docker exec $C opencode --version` returns version string |
| AC9 | LLM call succeeds | No 403 from Cloudflare | Send a message through the WebUI API and get a non-error response |
| AC10 | No secrets in repo | Tracked files contain no API keys | `git ls-files | xargs grep -r 'sk-\|key-'` returns nothing sensitive |
| AC11 | Fast second boot | Subsequent startup <30s to healthy | `docker compose down && docker compose up -d && time curl --retry 10 --retry-delay 2 -f .../health` |
| AC12 | Model discovery works | Multiple models in config | `docker exec $C grep 'context_length' /home/hermeswebui/.hermes/config.yaml | wc -l` > 1 |
| AC13 | No wildcard models | No `/*` patterns in config | `docker exec $C grep -c '/\*' /home/hermeswebui/.hermes/config.yaml` returns 0 |
| AC14 | Agent API health | Gateway responds on :8642 | `curl -f http://localhost:${HERMES_API_PORT:-8642}/health` returns OK |
| AC15 | Agent API models | Lists hermes-agent model | `curl http://localhost:${HERMES_API_PORT:-8642}/v1/models` returns model list |
| AC16 | Agent API chat | OpenAI-compatible chat works | Send chat completion to `:8642/v1/chat/completions` and get LLM response |
| AC17 | OpenCode serve responds | Headless server on :4096 | `curl -f http://localhost:${OPENCODE_SERVE_PORT:-4096}/` responds |
| AC18 | Config includes platform | api_server in config.yaml | `docker exec $C grep -q 'api_server' /home/hermeswebui/.hermes/config.yaml && echo OK` |
| AC19 | OpenCode config valid | opencode.jsonc is valid JSON | `docker exec $C python3 -m json.tool /home/hermeswebui/.config/opencode/opencode.jsonc` succeeds |
| AC20 | Onboarding skipped | WebUI reports onboarding complete | `curl $BASE/api/onboarding/status` returns `completed: true` |
| AC21 | Skills installed | Both platforms have skills | `docker exec $C find /home/hermeswebui/.config/opencode/skills -name "SKILL.md" \| wc -l` > 0 |
| AC22 | Security mode applied | Permission rules in opencode.jsonc | `docker exec $C python3 -c "import json; c=json.load(open('/home/hermeswebui/.config/opencode/opencode.jsonc')); print(len(c.get('permission',{}).get('bash',{})))"` shows rule count |
