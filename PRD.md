# PRD: Hermes x OpenCode Docker Stack

## 1. Product Overview

A Docker Compose stack that runs [Hermes WebUI](https://github.com/nicholasgriffintn/hermes-webui) + [Hermes Agent](https://github.com/NousResearch/hermes-agent) + [OpenCode CLI](https://opencode.ai) in a single container with three exposed services:

| Service | Port | Purpose |
|---------|------|---------|
| Hermes WebUI | :8787 | Browser-based chat interface |
| Hermes Agent API | :8642 | OpenAI-compatible endpoint (`/v1/chat/completions`) |
| OpenCode Serve | :4096 | Headless server for remote `opencode attach` |

**Data flow:** User → Browser/WebUI OR API client → Hermes Agent → OpenCode CLI (terminal tool) → LLM Provider (external)

### Related Repositories

Host-level (bare-metal) configuration generation — system packages, shell setup, dotfiles, and anything that runs directly on the host rather than in a container — has been split into a separate repository: [`hermes-x-opencode--host-machine`](https://github.com/bachkukkik/hermes-x-opencode--host-machine). This Docker stack repo is container-only and does not source or import the host-machine repo; the two are independent, linked by README cross-reference only.

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
│  │  (opencode serve)        │  ── OPTIONAL ───────────────────────── │
│  │  ⚠ gated by              │  Started only when                     │
│  │    OPENCODE_SERVE_ENABLED│    OPENCODE_SERVE_ENABLED=true         │
│  │    (default: false)      │  (default: false). See §9 Usage        │
│  │                          │  Patterns — most workflows do NOT      │
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
│    OpenCode Zen auth (OPENCODE_ZEN_API_KEY) — optional                   │
└──────────────────────────────────────────────────────────────────────┘
```

### Component Roles

| Component | Source | Role |
|-----------|--------|------|
| Hermes WebUI | `ghcr.io/nesquena/hermes-webui:latest` | Browser UI, HTTP server, agent host process |
| Hermes Gateway | `/app/venv/bin/hermes gateway run --accept-hooks` | OpenAI-compatible API on :8642 |
| Hermes Agent | `https://github.com/NousResearch/hermes-agent.git` | AI agent runtime, runs in-process |
| OpenCode CLI | Official install script (`opencode.ai/install`) | Autonomous coding agent via `terminal` tool |
| OpenCode Serve | `opencode serve` | **Optional.** Headless server for remote `opencode attach`. Disabled by default; gated by `OPENCODE_SERVE_ENABLED=true` (see §9 Usage Patterns). |
| Node.js 22 | nodesource setup script | Required for OpenCode plugin resolution |
| LLM Provider | External (user-configured) | OpenAI-compatible API endpoint |

### Agent Installation Architecture

The container has two copies of the hermes-agent source, serving different roles. There is ONE active runtime — the duplication is a staging pipeline, not a parallel installation.

```
┌─────────────────────────────────────────────────────────────────┐
│  INSTALLATION A — Active Runtime (base image venv)              │
│  /app/venv/bin/hermes                                           │
│  /app/venv/lib/python3.12/site-packages/hermes_agent/           │
│                                                                  │
│  Used by: WebUI (AIAgent in-process) + Gateway (CLI binary)     │
│  Source: pip-installed by /hermeswebui_init.bash at boot         │
└─────────────────────────────────────────────────────────────────┘
        ▲ uv pip install (from staged source)
        │
┌───────┴─────────────────────────────────────────────────────────┐
│  INSTALLATION B — Staged Source (passive, never executed)       │
│                                                                  │
│  Build-time: /opt/hermes-agent-staging/                         │
│    git clone --depth 1 + sed User-Agent patch                   │
│    + skills source for install-skills.sh (llm-wiki, etc.)       │
│                                                                  │
│  Runtime: ~/.hermes/hermes-agent/ (cp -a from staging)          │
│    - pyproject.toml: readiness marker for ensure_agent()        │
│    - agent source: deps source for /hermeswebui_init.bash       │
│    - plugins/: carries the User-Agent sed patch                  │
│                                                                  │
│  Propagation chain:                                              │
│    Dockerfile sed → staging → ensure_agent() →                  │
│    ~/.hermes/hermes-agent/ → /hermeswebui_init.bash rsyncs →    │
│    /tmp/hermes-agent-build/ → uv pip install → /app/venv/       │
│                                                                  │
│  NOT used at runtime by: WebUI, Gateway, or any CLI invocation   │
└─────────────────────────────────────────────────────────────────┘
```

| Dimension | Installation A (Active) | Installation B (Staging) |
|-----------|------------------------|-------------------------|
| Location | `/app/venv/` | `/opt/hermes-agent-staging/` + `~/.hermes/hermes-agent/` |
| Contains | pip-installed agent code | git clone of agent source |
| Executed | Yes — WebUI + gateway | No — never directly invoked |
| CLI binary | `/app/venv/bin/hermes` | None |
| Skills source | No | Yes — extracted during build |
| Patches | Receives via pip install | Carries sed User-Agent patch |
| Can remove | No — breaks everything | No — breaks deps install |

**Why both exist:** `/hermeswebui_init.bash` (base image script, not controlled by this repo) searches for the agent source at `~/.hermes/hermes-agent/` and installs its Python dependencies into `/app/venv/` via `uv pip install`. Without the staged clone, the WebUI's in-process agent cannot initialize. The clone also provides skills source material extracted during `install-skills.sh`.

**Image bloat mitigation:** The git clone includes ~200MB of upstream skills, docs, and tests that are not needed for deps installation. The Dockerfile trims these after clone:
```dockerfile
RUN rm -rf /opt/hermes-agent-staging/skills \
           /opt/hermes-agent-staging/docs \
           /opt/hermes-agent-staging/tests
```

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
    │       ├── entrypoint.sh                             # Runtime: 81-line orchestrator, sources lib/*.sh modules
    │       ├── fix20-providers-keyenv.py                  # Build-time patch: replaces API key literals with key_env references
    │       ├── lib/                                      # Library modules sourced by entrypoint.sh
    │       │   ├── constants.sh                          #   Path and user variable declarations (11 lines)
    │       │   ├── runtime-env.sh                        #   Runtime environment detection helpers (41 lines)
    │       │   ├── port-utils.sh                         #   TCP port readiness polling (31 lines)
    │       │   ├── agent-setup.sh                        #   Hermes-agent staging/copy logic (16 lines)
    │       │   ├── model-discovery.sh                    #   Model list discovery from OpenAI-compatible API (100 lines)
    │       │   ├── config-hermes.sh                      #   Hermes config.yaml generation + skills.external_dirs (116 lines)
    │       │   ├── config-opencode.sh                    #   OpenCode config generation (268 lines)
    │       │   ├── validate-opencode.sh                  #   OpenCode Zen API key validation (38 lines)
    │       │   ├── service-gateway.sh                    #   Hermes gateway service startup (24 lines)
    │       │   ├── service-opencode.sh                   #   OpenCode serve service startup (25 lines)
    │       │   ├── wiki-init.sh                          #   Wiki directory initialization for llm-wiki skill (84 lines)
    │       │   └── service-browser-vnc.sh                #   Browser/VNC human-in-the-loop stack startup (73 lines)
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
COPY scripts/lib/ /usr/local/bin/lib/
COPY tests/healthcheck.sh /usr/local/bin/healthcheck.sh
RUN chmod +x /usr/local/bin/install-skills.sh /usr/local/bin/entrypoint.sh /usr/local/bin/healthcheck.sh

# Step 7: Install skills from upstream sources (extracts llm-wiki from staging clone)
RUN HERMES_SKILLS_DIR=/opt/hermes-skills-staging \
    OPENCODE_SKILLS_DIR=/home/hermeswebui/.config/opencode/skills \
    install-skills.sh

# Step 8: Trim non-essential dirs from staged clone (after skills extraction)
RUN rm -rf /opt/hermes-agent-staging/skills \
           /opt/hermes-agent-staging/docs \
           /opt/hermes-agent-staging/tests \
           /opt/hermes-agent-staging/.github

# Step 9: Verification
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
- Both `install-skills.sh` and `entrypoint.sh` are copied into the image, along with the `scripts/lib/` directory containing 11 library modules.
- The verification step at the end catches missing agent, failed patch, or missing OpenCode.
- `HERMES_AGENT_VERSION` build arg defaults to `main`. Override with `--build-arg HERMES_AGENT_VERSION=v1.2.3`
- The staged clone is trimmed after skill extraction to reduce image size (~200MB savings). Only `pyproject.toml`, `plugins/`, and agent source remain.

### 5.2 `scripts/entrypoint.sh` (at `volumes_hermes_opencode/build/scripts/entrypoint.sh`)

**Purpose:** A thin 81-line orchestrator that sources 12 library modules from `scripts/lib/`, then discovers available models from the LLM provider, generates configuration files for both Hermes and OpenCode, installs skills, copies the staged agent, and starts background services in dependency order. All function logic lives in the lib/ modules; the orchestrator only calls functions and manages the execution sequence.

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

| Function | Module | Purpose |
|----------|--------|---------|
| `detect_runtime_env()` | `lib/runtime-env.sh` | Detects Docker/Kubernetes/local runtime environment. |
| `normalize_base_url_for_local(url)` | `lib/runtime-env.sh` | Replaces `host.docker.internal` with `localhost` for local runs. |
| `discover_models()` | `lib/model-discovery.sh` | Curls `OPENAI_BASE_URL/models` with API key. Filters non-chat models (embed, whisper, tts, dall-e, sora, etc.) and wildcard patterns. Falls back to `OPENAI_DEFAULT_MODEL` only on failure. Sets `DISCOVERED_MODELS`. |
| `generate_config()` | `lib/config-hermes.sh` | Writes `config.yaml` with litellm custom provider, multi-model `models` dict, `api_server` platform. Auto-generates API key if `HERMES_API_KEY` is empty. Writes both `model.default` and `model.name`. |
| `generate_opencode_config()` | `lib/config-opencode.sh` | Writes `opencode.jsonc` with plugins, permission block (based on `OPENCODE_SECURITY_MODE`), and provider config. Copies config to `/root/.config/opencode/` for root access (fix #28). Symlinks `/root/.local/share/opencode` to hermeswebui's data dir for shared session DB (fix #29). Chowns to `hermeswebui`. |
| `validate_opencode_zen_key()` | `lib/validate-opencode.sh` | Validates `OPENCODE_ZEN_API_KEY` against the Zen API models endpoint if set. Non-fatal warning on failure (fix #30). |
| `ensure_agent()` | `lib/agent-setup.sh` | Copies agent from `/opt/hermes-agent-staging` to bind mount if not already present. Idempotent. |
| `wait_for_port(port, timeout, label)` | `lib/port-utils.sh` | Loops curl on health endpoint every 2 seconds until ready or timeout. |
| `start_gateway()` | `lib/service-gateway.sh` | Starts gateway as `hermeswebui` via `su`. Command: `/app/venv/bin/hermes gateway run --accept-hooks`. Skips if agent not found. |
| `start_opencode_serve()` | `lib/service-opencode.sh` | Starts OpenCode serve as `hermeswebui` via `su`. Command: `opencode serve --port 4096 --hostname 0.0.0.0`. **No-op when `OPENCODE_SERVE_ENABLED` is not `true`** (default). |
| `start_browser_vnc()` | `lib/service-browser-vnc.sh` | Starts Browser/VNC human-in-the-loop stack (Xvfb + openbox + x11vnc + websockify + Chromium). Controlled by `BROWSER_HUMAN_LOOP_ENABLED`. |
| `init_wiki()` | `lib/wiki-init.sh` | Initializes wiki directory at `$WIKI_DIR` with SCHEMA.md backbone, index.md, log.md. Idempotent. |
| `append_skills_external_dirs()` | `lib/config-hermes.sh` | Appends `skills.external_dirs` to config.yaml after ensure_agent copies optional-skills into place. Enables 94 built-in + 72 custom = 166 total skills. |

**Startup sequence:**
1. `set -euo pipefail`; resolve `LIB_DIR` relative to script location
2. Source 12 library modules: `constants.sh`, `runtime-env.sh`, `port-utils.sh`, `agent-setup.sh`, `model-discovery.sh`, `config-hermes.sh`, `config-opencode.sh`, `validate-opencode.sh`, `service-gateway.sh`, `service-opencode.sh`, `wiki-init.sh`, `service-browser-vnc.sh`
3. Install skills (`install-skills.sh`) — 6 upstream sources, can skip with `SKIP_SKILL_INSTALL=1`
4. `detect_runtime_env()` — detect Docker/local; normalize `OPENAI_BASE_URL`
5. `discover_models()` — discover all chat models from provider
6. `generate_config()` — write `config.yaml` with multi-model support
7. `generate_opencode_config()` — write `opencode.jsonc` with plugins, permissions, provider; copy to root config; symlink root session DB (fixes #28, #29)
8. `validate_opencode_zen_key()` — validate OPENCODE_ZEN_API_KEY if set; warn on failure (fix #30)
9. `ensure_agent()` — copy staged agent to bind mount (first boot only)
10. Start `/hermeswebui_init.bash` in background
11. Wait for port 8787 to be healthy (timeout 300s)
12. `start_browser_vnc()` — start Browser/VNC stack (if enabled)
13. Start hermes gateway (`/app/venv/bin/hermes gateway run --accept-hooks`) in background
14. Wait for port 8642 to be healthy (timeout 60s)
15. Start `opencode serve --port 4096 --hostname 0.0.0.0` in background **only if `OPENCODE_SERVE_ENABLED=true`** (default: skipped)
16. `wait` to keep container alive (exits if any background process dies)

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
| `${OPENCODE_SERVE_PORT:-4096}:4096` | 4096 | OpenCode Serve (remote attach) — **only published when `OPENCODE_SERVE_ENABLED=true`** |

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
| `OPENCODE_ZEN_API_KEY` | No | API key for OpenCode Zen models. Required only for opencode/ built-in models; leave empty if using your own LLM provider. |
| `HERMES_WEBUI_SKIP_ONBOARDING` | No | Skip WebUI onboarding wizard (set `true`) |
| `HERMES_WEBUI_PASSWORD` | No | Optional password for the WebUI |
| `HERMES_WEBUI_PORT` | No | Host port for WebUI (default: 8787) |
| `HERMES_API_KEY` | No | Bearer token for Agent API (empty = auto-generated) |
| `HERMES_API_PORT` | No | Host port for Agent API (default: 8642) |
| `OPENCODE_SERVE_ENABLED` | No | `false` | Set to `true` to start `opencode serve` on :4096. Disabled by default — see §9 Usage Patterns. |
| `OPENCODE_SERVE_PORT` | No | `4096` | Host port for OpenCode serve (only used when `OPENCODE_SERVE_ENABLED=true`) |
| `SKIP_SKILL_INSTALL` | No | `0` | Skip skill installation (set `1`) |
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
 5b. Copy opencode.jsonc to /root/.config/opencode/ (fix #28)
 5c. Symlink /root/.local/share/opencode → hermeswebui's data dir (fix #29)
 6. Validate OPENCODE_ZEN_API_KEY if set — warn on failure (fix #30)
 7. Copy agent from /opt/hermes-agent-staging to bind mount (~2s)
 8. Start /hermeswebui_init.bash in background
 9. WebUI init script (background):
    a. Sets up UID/GID
    b. Installs hermes-agent Python deps
    c. Starts the WebUI HTTP server on :8787
10. Wait for port 8787 to respond to /health (timeout: 120s)
11. Start hermes gateway: /app/venv/bin/hermes gateway run --accept-hooks
12. Wait for port 8642 to respond to /health (timeout: 60s)
13. Start opencode serve --port 4096 --hostname 0.0.0.0 **(only if `OPENCODE_SERVE_ENABLED=true`)**
14. wait -n to keep container alive
```

**Expected first boot time:** 80–160 seconds (skill install + Python deps + model discovery)

### Subsequent Boots

```
 1. Install skills (OpenCode skills are ephemeral, always reinstalled)
 2. Re-discover models (idempotent)
 3. Regenerate config.yaml and opencode.jsonc (idempotent overwrite)
 3b. Copy opencode.jsonc to /root/.config/opencode/ (fix #28)
 3c. Symlink /root/.local/share/opencode → hermeswebui's data dir (idempotent, fix #29)
 4. Validate OPENCODE_ZEN_API_KEY if set (fix #30)
 5. Agent already present in bind mount (skips copy)
 6. WebUI init: deps already installed, fast startup (~10-20s)
 7. Gateway starts: deps already installed (~5-10s)
 8. OpenCode serve starts (~2-5s) — **only when `OPENCODE_SERVE_ENABLED=true`**; otherwise skipped
 9. All ports ready
```

**Expected subsequent boot time:** 25–50 seconds

### Key Behaviors

- `config.yaml` and `opencode.jsonc` are regenerated on every boot from env vars and model discovery. Manual edits inside the container are lost on restart.
- Model discovery is idempotent — same provider URL produces same model list every boot.
- The hermes-agent source is copied from the image's staging path to the bind mount on first start. It persists across container restarts.
- Session history, skills, and memories persist in the `hermes-home` bind mount across container restarts and rebuilds.
- OpenCode skills are ephemeral (no volume mount) and reinstalled on every boot. Hermes skills persist in the bind mount.
- The WebUI, gateway, and (when enabled) `opencode serve` run as background processes. If any started process exits, the container shuts down (`wait -n`). This is why `opencode serve` is gated behind `OPENCODE_SERVE_ENABLED` — without an LLM provider it would exit immediately and tear the container down.
- `host.docker.internal` resolves inside the container via `extra_hosts` in `docker-compose.yml` (maps to `host-gateway`). This works on all platforms including bare Linux (fixes #27, #31).
- The gateway and opencode serve are started as `hermeswebui` user (not root) via `su`. Note: `opencode serve` only starts when `OPENCODE_SERVE_ENABLED=true` (default: `false`); see §9 Usage Patterns for why.
- Both `model.default` and `model.name` are written to `config.yaml` to satisfy both the WebUI's `models_cache.json` builder and the hermes-agent's model resolution.

## 7. Configuration Reference

### Environment Variables

| Variable | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `OPENAI_API_KEY` | string | **Yes** | — | API key for the LLM provider. Used by hermes-agent for all LLM calls and by OpenCode via `{env:OPENAI_API_KEY}`. |
| `OPENAI_BASE_URL` | string | **Yes** | — | OpenAI-compatible base URL for the LLM provider. Triggers config generation and model discovery. |
| `OPENAI_DEFAULT_MODEL` | string | No | `openai/gpt-4o` | Default model identifier. Must match a model your provider supports. All other chat models are auto-discovered. Used as the fallback default for both Hermes and OpenCode when no per-app override is set. |
| `OPENAI_SMALL_MODEL` | string | No | falls back to `OPENAI_DEFAULT_MODEL` | Small model for lightweight OpenCode tasks (title generation, etc.). Written as `small_model` in `opencode.jsonc`. |
| `HERMES_DEFAULT_MODEL` | string | No | falls back to `OPENAI_DEFAULT_MODEL` | Per-app override for the Hermes default model. When set, written to `config.yaml` as both `model.default` and `model.name`. |
| `OPENCODE_DEFAULT_MODEL` | string | No | falls back to `OPENAI_DEFAULT_MODEL` | Per-app override for the OpenCode default model. When set, written to `opencode.jsonc` as `"model": "litellm/<value>"`. |
| `OPENCODE_SMALL_MODEL` | string | No | falls back to `OPENAI_SMALL_MODEL` | Per-app override for the OpenCode small model. When set, written to `opencode.jsonc` as `"small_model": "litellm/<value>"`. |
| `OPENCODE_ZEN_API_KEY` | string | No | — | API key for OpenCode Zen models. Required only for opencode/ built-in models (sign up at https://opencode.ai/auth). If you only use models from your own LLM provider (via `OPENAI_BASE_URL`), leave this empty. Validated at startup with a warning on failure. |
| `HERMES_WEBUI_SKIP_ONBOARDING` | string | No | — | Set to `true` to skip the WebUI onboarding wizard. |
| `HERMES_WEBUI_PASSWORD` | string | No | empty | Password-protect the WebUI. Empty = no authentication. |
| `HERMES_WEBUI_PORT` | int | No | `8787` | Host port for the WebUI. Container always listens on 8787 internally. |
| `HERMES_API_KEY` | string | No | auto-generated | Bearer token for the Hermes Agent API. Auto-generated random key if empty. Printed to container logs. |
| `HERMES_API_PORT` | int | No | `8642` | Host port for the Hermes Agent API. Container always listens on 8642 internally. |
| `OPENCODE_SECURITY_MODE` | string | No | `strict` | Security profile for OpenCode: `strict` (31 bash rules), `standard` (22 rules), `yolo` (allow all). |
| `OPENCODE_SERVE_ENABLED` | bool | No | `false` | Set to `true` to start `opencode serve` on :4096. Disabled by default because serve exits immediately without an LLM provider and would tear the container down via `wait -n`. See §9 Usage Patterns. |
| `OPENCODE_SERVE_PORT` | int | No | `4096` | Host port for OpenCode serve. Only used when `OPENCODE_SERVE_ENABLED=true`. Container always listens on 4096 internally. |
| `SKIP_SKILL_INSTALL` | string | No | `0` | Set to `1` to skip skill installation at container start. |
| `HOST_UID` | int | No | `1000` | Linux UID for container file processes. Match your host user UID. |
| `HOST_GID` | int | No | `1000` | Linux GID for container file processes. Match your host group GID. |
| `HERMES_WORKSPACE` | string | No | `./volumes_hermes_opencode/data/workspace` | Host path for the workspace volume mount. |

### Build Arguments

| Argument | Default | Description |
|----------|---------|-------------|
| `HERMES_AGENT_VERSION` | `main` | Git branch or tag for hermes-agent clone. E.g. `main`, `v1.0.0`, `develop` |

### Per-Model Provider Routing (Issue #46)

**Problem.** The original `config-opencode.sh` applied a single global `provider_prefix` to both `model` and `small_model` in the generated `opencode.jsonc`. This made dual-provider deployments impossible — for example, using `opencode/` models for the main model (routed to OpenCode Zen) while falling back to a `litellm/` model for `small_model` (routed to the user's own LLM provider via `OPENAI_BASE_URL`). One prefix had to cover both.

**Solution.** A new helper function `_resolve_provider_prefix()` determines routing per-model based on the original model name. Each model in `opencode.jsonc` (`model` and `small_model`) is now resolved independently through this function before the provider prefix is applied.

**Decision table:**

| Original model name | OpenAI creds present (`OPENAI_API_KEY` + `OPENAI_BASE_URL`)? | Resolved prefix | Final model value in `opencode.jsonc` |
|---|---|---|---|
| `opencode/*` | Any | `opencode` | `opencode/<name>` (unchanged) |
| `litellm/*` | Any | `litellm` | `litellm/<name>` (unchanged) |
| bare name (no prefix) | Yes | `litellm` | `litellm/<bare-name>` |
| bare name (no prefix) | No | `opencode` | `opencode/<bare-name>` |

**Backward compatibility.** Existing single-provider deployments are unaffected. When all models share the same prefix (the common case), behavior is identical to the pre-#46 code path. The `_resolve_provider_prefix()` function is only called when the model name is a bare name with no explicit prefix — prefixed names pass through unchanged.

**OpenCode provider block (companion fix).** When `OPENCODE_ZEN_API_KEY` is set, an explicit `opencode` provider entry is generated in `opencode.jsonc` with `apiKey: {env:OPENCODE_ZEN_API_KEY}`. This ensures built-in `opencode/` models (like `deepseek-v4-flash-free`) have proper authentication mapping. Additionally, `auth.json` is seeded as a fallback credential store, and `OPENCODE_ZEN_API_KEY` is explicitly passed through `su` in `service-opencode.sh`.

**Implementation.**

- `_resolve_provider_prefix()` — a shell function in `lib/config-opencode.sh` that inspects the model name and environment variables, returning the appropriate provider prefix string.
- `generate_opencode_config()` — updated to call `_resolve_provider_prefix()` separately for `model` and `small_model`, then prepend the resolved prefix to each model identifier before writing to `opencode.jsonc`.

**Test criteria.** A per-model independence test in `tests/bats/03-config.bats` verifies:

- `opencode/`-prefixed models keep the `opencode` prefix regardless of credential presence.
- `litellm/`-prefixed models keep the `litellm` prefix regardless of credential presence.
- Bare names with OpenAI creds present resolve to `litellm/<name>`.
- Bare names without OpenAI creds resolve to `opencode/<name>`.
- `model` and `small_model` can resolve to different providers in the same `opencode.jsonc`.

### Also Found During Fork Sync (Issue #46)

Three additional fixes discovered while implementing per-model provider routing:

**EACCES on `~/.local/state`.** The entrypoint runs as root but drops privileges for gateway and opencode serve. If `~/.local/state` (or its parent directories) does not exist or is owned by root, the `hermeswebui` user gets `EACCES` on write. Fix: `entrypoint.sh` now ensures the directory tree exists and is owned by `hermeswebui` before dropping privileges.

**Fix #28 idempotency (readlink -f guard).** The fix that copies `opencode.jsonc` to `/root/.config/opencode/` previously used `mkdir -p` unconditionally, which would follow a symlink and create the target directory under the wrong path on subsequent boots. Fix: added a `readlink -f` guard so the copy is skipped when the destination is already a symlink pointing to the correct target.

**Mock LLM server for secretless CI.** A lightweight mock HTTP server that responds to `/v1/models` and `/v1/chat/completions` with canned responses. Used in BATS tests to exercise config generation and model discovery without requiring real API credentials. Runs on `localhost` with a random port, started/stopped by the test harness.

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
| C10 | The staged agent clone must be trimmed after `git clone` to exclude non-essential directories (`skills/`, `docs/`, `tests/`, `.github/`) | Reduces image bloat by ~200MB. The WebUI init only needs `pyproject.toml`, `plugins/`, and agent source for deps installation |

## 9. Usage Patterns

This section is the canonical reference for how end-users invoke OpenCode from inside (or attached to) the container. It mirrors the README's "Usage Patterns" section and exists in the PRD so architecture decisions can be cross-referenced against verified workflows.

> **Note:** The historical `opencode run --agent plan` / `opencode run --agent build` subcommands are **broken** in the current environment (see [#8](https://github.com/bachkukkik/hermes-x-opencode/issues/8) and [#9](https://github.com/bachkukkik/hermes-x-opencode/issues/9)). The patterns below use the verified one-shot `opencode <dir> --prompt` flow.

### Pattern Summary Table

| # | Pattern | Command Shape | Status | Notes |
|---|---------|---------------|--------|-------|
| 1 | Direct one-shot coding | `opencode <dir> -m <model> --prompt "<task>"` | ✅ Verified | Single task, single invocation, model-pinned, scriptable. Default recommendation for CI/CD and `terminal`-tool delegation from Hermes. |
| 2 | Plan → build (chained one-shots) | `opencode <dir> --prompt "<plan>" > plan.md` then `opencode <dir> --prompt "Implement plan.md"` | ✅ Verified | Two-step: first call emits a plan to a file, second call consumes it. No agent state shared between calls. |
| 3 | Gateway chat (Hermes Agent API) | `POST :8642/v1/chat/completions` with model `hermes-agent` | ✅ Verified | OpenAI-compatible. Bypasses OpenCode entirely; agent runs server-side with full tool access. Best for browser/UI and programmatic clients. |
| 4 | Remote attach via `opencode serve` | `opencode attach http://host:4096` | ⚠ Conditional | Only works when `OPENCODE_SERVE_ENABLED=true`. Disabled by default because serve exits without an LLM provider and tears the container down via `wait -n`. |
| 5 | `opencode run --agent plan/build` | `opencode run --agent plan ...` | ❌ Broken | Was the historical CEO-delegation interface. Broken in current OpenCode builds — see issues [#8](https://github.com/bachkukkik/hermes-x-opencode/issues/8) and [#9](https://github.com/bachkukkik/hermes-x-opencode/issues/9). Do **not** document as a supported workflow; tracked for replacement. |

### Pattern 1 — Direct One-Shot Coding (verified)

Run a single coding task in one shot, then return. This is the only pattern the Hermes agent should use when delegating to OpenCode via the `terminal` tool.

```bash
# Inside the container, or on a host with opencode installed
opencode /workspace/project -m opencode/deepseek-v4-flash-free \
  --prompt "Add retry logic to api.py"
```

Free models that require no auth: `opencode/deepseek-v4-flash-free`, `opencode/mimo-v2.5-free`, `opencode/nemotron-3-ultra-free`, `opencode/north-mini-code-free`, `opencode/big-pickle`.

### Pattern 2 — Plan → Build Pipeline, Chained One-Shots (verified)

Generate a plan first, then feed it back as the implementation prompt. Two independent invocations; no shared agent state between them.

```bash
# Step 1: Generate a plan
opencode /workspace/project -m opencode/deepseek-v4-flash-free \
  --prompt "Read PRD.md and output a step-by-step implementation plan" \
  > /tmp/plan.md

# Step 2: Execute the plan
opencode /workspace/project -m opencode/deepseek-v4-flash-free \
  --prompt "Implement the plan in /tmp/plan.md"
```

### Pattern 3 — Direct Chat via Agent API (verified)

Point any OpenAI-compatible client at `:8642/v1` and use model `hermes-agent`. The agent runs server-side with full tool access.

```bash
curl -X POST http://localhost:8642/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"hello"}]}'
```

For the full CEO-OpenCode multi-agent delegation workflow (Hermes decomposes, OpenCode implements, Hermes verifies) that *replaces* the broken `--agent plan/build` interface, see [issue #9](https://github.com/bachkukkik/hermes-x-opencode/issues/9).

### When to Use What

| Scenario | Service / Pattern | Why |
|----------|-------------------|-----|
| Browser-based chat | WebUI :8787 | Full UI with sessions, file browser |
| Connect external chat UI | Agent API :8642 (Pattern 3) | OpenAI-compatible, streaming |
| Code implementation from agent | `opencode <dir> --prompt` (Pattern 1) | One-shot, model-pinned, scriptable |
| Multi-step build with separate plan | Chained one-shots (Pattern 2) | Cheap, no shared state, retry-friendly |
| CI/CD integration | Agent API :8642 (Pattern 3) | Programmatic access |
| Remote coding (experimental) | OpenCode :4096 (Pattern 4) | Attach from another machine — needs `OPENCODE_SERVE_ENABLED=true` |

## 10. Acceptance Criteria

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
| AC17 | OpenCode serve responds (when enabled) | Headless server on :4096 | `OPENCODE_SERVE_ENABLED=true` set, then `curl -f http://localhost:${OPENCODE_SERVE_PORT:-4096}/` responds |
| AC18 | Config includes platform | api_server in config.yaml | `docker exec $C grep -q 'api_server' /home/hermeswebui/.hermes/config.yaml && echo OK` |
| AC19 | OpenCode config valid | opencode.jsonc is valid JSON | `docker exec $C python3 -m json.tool /home/hermeswebui/.config/opencode/opencode.jsonc` succeeds |
| AC20 | Onboarding skipped | WebUI reports onboarding complete | `curl $BASE/api/onboarding/status` returns `completed: true` |
| AC21 | Skills installed | Both platforms have skills | `docker exec $C find /home/hermeswebui/.config/opencode/skills -name "SKILL.md" \| wc -l` > 0 |
| AC22 | Security mode applied | Permission rules in opencode.jsonc | `docker exec $C python3 -c "import json; c=json.load(open('/home/hermeswebui/.config/opencode/opencode.jsonc')); print(len(c.get('permission',{}).get('bash',{})))"` shows rule count |
| AC23 | OpenCode serve healthy (when enabled) | `/global/health` returns `{"healthy":true}` | `OPENCODE_SERVE_ENABLED=true` set, then `curl -sf http://localhost:${OPENCODE_SERVE_PORT:-4096}/global/health` |
| AC24 | Hermes skills present | More than 0 SKILL.md files under hermes skills dir | `docker exec $C find /home/hermeswebui/.hermes/skills -name "SKILL.md" \| wc -l` returns >0 |
| AC25 | Skills baked in Docker image | More than 0 SKILL.md files in staging dir | `docker run --rm --entrypoint bash $IMAGE -c 'find /opt/hermes-skills-staging -name "SKILL.md" \| wc -l'` returns >0 |

## 11. OpenCode Model Fallback (Runtime Failover)

### Requirement
When the primary OpenCode model call fails (rate limit, quota exhausted, 5xx, timeout, overloaded, model-not-found), OpenCode transparently retries with a configured fallback model and replays the request — no manual intervention.

### Configuration (env-driven)
| Var | Required | Default | Purpose |
|-----|----------|---------|---------|
| `OPENCODE_DEFAULT_MODEL` | No | `opencode/deepseek-v4-flash-free` | Primary model for OpenCode agents |
| `OPENCODE_SMALL_MODEL` | No | = `OPENCODE_DEFAULT_MODEL` | Small/title model |
| `OPENCODE_FALLBACK_MODEL` | No | (unset) | Model id retried when primary fails. Cross-provider supported (e.g. primary `opencode/...`, fallback `litellm/...` or a bare `llama_cpp/...` id that resolves via `_resolve_provider_prefix`) |

### Architecture
Plugin approach via the `opencode-runtime-fallback` plugin (no new container):
1. `config-opencode.sh` appends `"opencode-runtime-fallback"` to the `"plugin"` array when `OPENCODE_FALLBACK_MODEL` is set.
2. `config-opencode.sh` emits an `agent` block carrying `fallback_models` (the resolved fallback id) for the active agent, mirroring the existing per-model `model`/`small_model` resolution.
3. The plugin auto-installs from npm on first `opencode` run; it detects retryable failures and switches + replays, with cooldown and auto-recovery back to the primary.

### Constraints
- The fallback target (e.g. a llama.cpp server exposing `qwen3.6-27b-q4_k_m` at `OPENAI_BASE_URL`) must be reachable at runtime, or the fallback is inert.
- No new service/container. The Hermes gateway fallback is a separate concern (AIAgent `fallback_model` param) and out of scope for this change.

## 12. Documentation & Test Hygiene

### Gaps (from intended-vs-implemented audit)
| ID | Pri | Gap | Resolution |
|----|-----|-----|------------|
| G-01 | P0 | Doc number conflict: two `16-` files | Renumber `docs/16-docker-compose-overrides.md` -> `docs/18-docker-compose-overrides.md` (next free; 17 taken); fix its title line |
| G-02 | P0 | `docs/17-wiki-init.md` title uses `# 17.` not `# 17 —` | Fix title to em-dash format |
| G-03 | P1 | `doctrine` (17 tests) has zero doc coverage | New `docs/19-doctrine.md` documenting the OpenCode security doctrine (AGENTS.md-driven permission system) |
| G-04 | P1 | No `docs/README.md` index | Create index table of all docs 01-19 |
| G-05 | P2 | `graphify-out/` stale (predates YOLO commit #53) | Regen via graphify after docs land |

### Non-gaps (verified, no action)
- `.env` extra vars (`HERMES_DEFAULT_MODEL`, `OPENCODE_DEFAULT_MODEL`, `OPENCODE_SMALL_MODEL`) are documented as commented entries in `.env.example`.
- No stale line-number references in docs.
- All 16 test files (00-15) are in the runner glob; no silently excluded tests.
- CI heredoc indentation is handled by YAML block-scalar stripping.

## 13. Additional Acceptance Criteria

| # | Test | Expected Result | How to Verify |
|---|------|-----------------|---------------|
| AC26 | Fallback plugin registered | `opencode.jsonc` lists the fallback plugin when `OPENCODE_FALLBACK_MODEL` set | `docker exec $C python3 -c "import json;c=json.load(open('.../opencode.jsonc'));print('opencode-runtime-fallback' in c.get('plugin',[]))"` -> True |
| AC27 | Fallback absent when unset | No fallback plugin/agent block when `OPENCODE_FALLBACK_MODEL` empty | grep `opencode-runtime-fallback` opencode.jsonc -> none |
| AC28 | Agent fallback_models set | agent block carries the resolved fallback id | parse opencode.jsonc agent block -> fallback_models non-empty |
| AC29 | Doc numbers unique | No two docs share a number | `ls docs/*.md` shows distinct 01-19 prefixes |
| AC30 | Doctrine doc present | `docs/19-doctrine.md` exists and mentions the permission system | `test -f docs/19-doctrine.md && grep -qi permission docs/19-doctrine.md` |
| AC31 | Docs index present | `docs/README.md` lists every doc | `test -f docs/README.md` && row count matches doc count |
| AC32 | graphify regenerated | `graphify-out/graph.json` mtime newer than latest commit | `test graphify-out/graph.json -nt volumes_hermes_opencode/build/scripts/lib/config-hermes.sh` |

## 14. Profile Skills Parity (righthand-man ← default)

> **RESOLVED (2026-06-27).** SOUL.md now separates **8 skills** (loaded via `skill_view`) from **2 built-in Hermes tools** (always available). The routing doctrine explicitly recognizes kanban and browser as built-in Hermes capabilities — not file-based skills — matching their actual implementation (`hermes kanban` subcommand and CDP toolset on port 9222). Dogfood was added as the 8th skill. PROF8 and PROF9 bats tests verify skill and built-in tool availability separately, rather than conflating the two categories. The parity concern (original problem below) is addressed: all capabilities in the routing table now exist on the system, and the doc accurately reflects their category (skill vs. built-in tool).

### Problem

AGENTS.md mandates 6 skills on every task. The righthand-man orchestrator profile's SOUL.md mandates only 4, omitting `security-best-practices`, `webapp-testing`, `coding-agents-docs-guideline`, and `yeet`. While righthand-man inherits AGENTS.md from the workspace mount, the SOUL.md persona file is the stronger behavioral signal — it reasserts the doctrine on every message and should be the single source of truth for mandatory skills.

Additionally, the `--clone` operation during profile seeding copies skills/ at seed time but never syncs afterward. If new skills are added to the default profile between rebuilds, righthand-man's skills/ directory falls behind.

### Root causes

1. SOUL.md was authored when only the 4-skill routing (PM, karpathy, kanban, opencode-plan-build-orchestrator) was the convention — the companion skills mandate was formalized later in AGENTS.md
2. The seed is idempotent (`SOUL.md` presence = skip) so a container rebuild with updated default skills does not propagate to an already-seeded righthand-man
3. `security-best-practices` and `webapp-testing` are mandated by AGENTS.md but do not exist as skills on the system — they are aspirational mandates with no implementation

### Success criteria

| # | Criterion | Verification |
|---|-----------|-------------|
| SC14.1 | SOUL.md mandates all 6 AGENTS.md skills | `grep -c 'security-best-practices\|webapp-testing\|coding-agents-docs-guideline\|yeet' SOUL.md` → ≥4 |
| SC14.2 | righthand-man skills/ count matches default skills/ count | `diff <(ls default/skills/ | wc -l) <(ls righthand-man/skills/ | wc -l)` → equal |
| SC14.3 | Bats PROF5 verifies skill parity | `bats tests/e2e/18-profile.bats --filter PROF5` → pass |
| SC14.4 | Post-clone SOUL.md overwrite preserves mandated skills | Seed is idempotent: second boot does not clobber an updated SOUL.md |
| SC14.5 | `security-best-practices` and `webapp-testing` stub skills exist | `test -f ~/.hermes/skills/software-development/security-best-practices/SKILL.md` → true |

### Changes

1. **SOUL.md** (`build/righthand-man/SOUL.md` and embedded heredoc in `lib/profile-righthand-man.sh`): Expand section 3 from 4 to 6 skills, adding `security-best-practices`, `webapp-testing`, `coding-agents-docs-guideline`, `yeet`
2. **Post-clone skill sync** (`lib/profile-righthand-man.sh`): After the clone + SOUL.md overwrite, rsync default's skills/ into righthand-man's skills/ to catch any skills added since the last seed. Idempotent — runs on every boot, not just first seed
3. **Config.yaml sync on every boot** (`lib/profile-righthand-man.sh`): After the SOUL.md overwrite, copy the default profile's config.yaml into the righthand-man profile so it always uses the latest model/provider config from `generate_config()`. Idempotent — runs on every boot, not just first seed
4. **Stub skills**: Create `security-best-practices/SKILL.md` and `webapp-testing/SKILL.md` as minimal placeholder skills with a note that they are aspirational mandates pending full implementation
5. **Bats test PROF5**: Verify righthand-man skills/ is not empty and has the same count as default
6. **Doc update** (`docs/22-profiles.md`): Update the four-skill routing table to include all 6 mandated skills

### Assumptions

- `hermes profile create --clone` correctly copies the skills/ directory (verified by existing PROF4 test)
- The SOUL.md heredoc in `profile-righthand-man.sh` and the canonical `build/righthand-man/SOUL.md` must stay in sync
- Stub skills are acceptable — they document the mandate and can be fleshed out later
- Post-clone sync via rsync is safe because both directories are owned by hermeswebui

## 15. Browser State Persistence

### Problem

The browser human-in-the-loop stack stores Chromium user data at `/home/hermeswebui/.hermes/chrome-debug`, which lives on the bind-mounted volume. While the mechanism for persistence exists, there is no explicit test verifying that cookies, sessions, and profiles survive `docker compose down && up -d`. Users need confidence that authenticated website sessions persist across redeployments.

### Root causes

1. The persistence mechanism (bind mount) is in place but untested — no bats test verifies survival across container recreate
2. Doc 15 mentions persistence in passing ("Cookies, localStorage, and login state persist across container restarts") but provides no verification procedure
3. Chromium lockfiles are cleaned on each start (SingletonLock, SingletonCookie, SingletonSocket) — correct behavior, but the cleanup could theoretically clobber other state if path assumptions change

### Success criteria

| # | Criterion | Verification |
|---|-----------|-------------|
| SC15.1 | Cookie survives down+up cycle | Cookie file present before down, same file present after up |
| SC15.2 | chrome-debug directory on bind mount | `docker exec $C stat /home/hermeswebui/.hermes/chrome-debug` shows it's on the bind mount (not overlayfs) |
| SC15.3 | Lockfile cleanup is non-destructive | After cleanup, `ls chrome-debug/Default/Cookies` still exists |
| SC15.4 | Bats test BH9 verifies persistence | `bats tests/e2e/12-browser-human-loop.bats --filter BH9` → pass |
| SC15.5 | Doc 23 explicitly covers persistence with verification steps | `docs/23-browser-persistence.md` exists |

### Changes

1. **Bats test BH9** (`tests/e2e/12-browser-human-loop.bats`): New test that (a) verifies chrome-debug/Default/Cookies exists, (b) records its size/mtime, (c) verifies it's on the bind mount (not overlayfs), (d) confirms lockfiles are absent after cleanup, (e) confirms Cookies file survives the cleanup
2. **Doc 23** (`docs/23-browser-persistence.md`): New doc covering the persistence architecture (bind mount → host filesystem), what survives (cookies, localStorage, sessions, profiles, extensions), what doesn't (running tabs — Chromium restarts fresh), verification steps, and troubleshooting (corrupted profile recovery, clearing state)
3. **Doc 15 update** (`docs/15-browser-human-loop.md`): Cross-reference to doc 23 in the persistence line

### Assumptions

- Chromium stores cookies in `Default/Cookies` (SQLite) at the user-data-dir — standard behavior, verified on Debian Chromium
- The bind mount at `./volumes_hermes_opencode/data/hermes-home` is not wiped between redeployments (user responsibility)
- Lockfile cleanup (SingletonLock, SingletonCookie, SingletonSocket) is sufficient — no other stale state files block Chromium startup

## 16. Configurable Browser Viewport (Xvfb Display Size)

### Problem

When a user enables the browser human-in-the-loop stack (`BROWSER_HUMAN_LOOP_ENABLED=true`) and asks the Hermes Agent to access a web page at an arbitrary window size (e.g. desktop 1920x1080, or a specific mobile/tablet viewport), the agent falls back to screenshots at the default viewport. Its reasoning trace reports:

> "CDP viewport override not supported on this backend. Let me take screenshots of key pages at the default viewport to verify the design visually."

The agent cannot set an arbitrary viewport because the underlying virtual display is too small.

### Root causes

1. `scripts/lib/service-browser-vnc.sh` launches Xvfb with a **hardcoded** screen geometry: `Xvfb :99 -screen 0 1280x720x24` (line 27). CDP `Emulation.setDeviceMetricsOverride` / window-resize calls are clamped by the X server's screen dimensions, so any viewport larger than 1280x720 is silently rejected — hence the "not supported on this backend" fallback. The fix raises the default to 1920x1080 (a realistic desktop viewport) and makes it configurable.
2. The Chromium launch line (line 68) passes **no `--window-size` flag**, so the initial window is whatever Chromium defaults to inside the 1280x720 display — not a predictable desktop size.
3. There is **no environment variable** controlling either the Xvfb screen size or the Chromium window size; both values are baked into the script. Doc 15 documents this as "Hardcoded; non-overridable".

### Success criteria

| # | Criterion | Verification |
|---|-----------|-------------|
| SC16.1 | Xvfb screen geometry reads from `BROWSER_DISPLAY_WIDTH` / `BROWSER_DISPLAY_HEIGHT` (with 1920x1080 default) | `docker exec $C bash -lc 'echo $BROWSER_DISPLAY_WIDTH'` echoes the env value; the Xvfb process command line (via `pgrep -fa`) shows the env-derived geometry, defaulting to 1920x1080 |
| SC16.2 | Chromium launches with `--window-size=$W,$H` matching the display | `docker exec $C pgrep -fa chromium` output contains `--window-size=<W>,<H>` equal to the configured values |
| SC16.3 | With width/height set to 1920x1080, the CDP browser can report a viewport ≥ 1920x1080 | `browser_navigate` then a JS `window.innerWidth/innerHeight` snapshot returns ≥1920 and ≥1080 (manual/agent check; the bats test asserts the launch args are present since the test runner has no live LLM) |
| SC16.4 | Default behavior (vars unset) is now 1920x1080 (upgrade from old 1280x720) | With vars unset, the Xvfb process command line (via `pgrep -fa`) shows `1920x1080x24`; low-RAM hosts can set `BROWSER_DISPLAY_WIDTH=1280 BROWSER_DISPLAY_HEIGHT=720` to restore the old footprint |
| SC16.5 | New bats test BH10 verifies the env-derived geometry and `--window-size` flag | `bats tests/e2e/12-browser-human-loop.bats --filter BH10` → pass |
| SC16.6 | Docs updated: doc 15 table row + troubleshooting note, doc 06 env table, README env section | `grep -rn 'BROWSER_DISPLAY_WIDTH' docs/ README.md` returns matches |

### Changes

1. **`scripts/lib/service-browser-vnc.sh`** — read `BROWSER_DISPLAY_WIDTH` (default 1280) and `BROWSER_DISPLAY_HEIGHT` (default 720) at the top of `start_browser_vnc()`; substitute them into both the `Xvfb -screen 0` geometry and a new `--window-size=$W,$H` Chromium flag. No new deps.
2. **`docker-compose.yml`** — add `BROWSER_DISPLAY_WIDTH` and `BROWSER_DISPLAY_HEIGHT` to the `environment:` block (pass-through from `.env`, `${VAR:-}` form) so the vars are transported into the container. Follows the existing per-var convention (every browser var already has its own line).
3. **`tests/e2e/12-browser-human-loop.bats`** — new test BH10: sets the env vars via `docker exec ... bash -lc` is not possible pre-boot; instead assert on the *running* container that (a) the Xvfb process command line contains the configured geometry and (b) the chromium command line contains `--window-size`. Skips when `BROWSER_HUMAN_LOOP_ENABLED!=true`.
4. **`docs/15-browser-human-loop.md`** — change the "Xvfb display" table row from "Hardcoded; non-overridable" to document the two new env vars and defaults; add a short troubleshooting note.
5. **`docs/06-config-and-env.md`** — add `BROWSER_DISPLAY_WIDTH` / `BROWSER_DISPLAY_HEIGHT` rows to the env var table with defaults.
6. **`README.md`** — add the two vars to the browser env section (if README has one; otherwise a one-line mention near `BROWSER_HUMAN_LOOP_ENABLED`).

### Assumptions

- `Emulation.setDeviceMetricsOverride` succeeds for any width/height ≤ the Xvfb screen geometry — standard CDP/Chromium behavior; the prior failure was purely the 1280x720 ceiling, not a CDP protocol limitation.
- 1280x720 remains a safe default (unchanged default behavior, satisfies SC16.4) — some low-RAM hosts may not want a larger framebuffer; the env var lets users opt in.
- `--window-size=$W,$H` is honored by the installed Debian `chromium` package (standard Chrome flag, already documented in the hermes-browser skill).
- Passing the two new vars through `docker-compose.yml` `environment:` (one line each) is the project's established transport pattern; no `.env` wildcard forwarding exists (per the kanban pitfall: "vars are NOT auto-forwarded from `.env`").

### Non-goals (out of scope)

- Mobile device emulation / DPR / user-agent spoofing — the agent can already do that via CDP once the display is large enough; this change only removes the size ceiling.
- Making the color depth (`x24`) or display number (`:99`) configurable — neither is implicated in the viewport bug.
- Cloud browser providers (Browserbase/Camofox) — unaffected; this is Xvfb/CDP-attach only.

## 17. Documentation Gaps: doc06 Env Var Table Parity

## 18. Bare-Metal Host Setup: Model Discovery & Context Length Accuracy

### 18.1 Summary

The bare-metal host machine runs Hermes Agent + OpenCode CLI + a LiteLLM proxy
container that serves 281 models from 20+ providers (Anthropic, DeepSeek, ZAI,
OpenRouter, Vertex AI, Gemini, free Zen tier, local llama.cpp, etc.). A host
config generator (`~/.hermes/host-config-gen/generate.sh`) discovers models and
produces merged config overlays for both Hermes and OpenCode.

### 18.2 Problem

The host config generator hardcodes `context_length: 262144` for every
discovered model regardless of its actual context window. This causes:

- **Inaccurate context display** — `/usage` and the status bar show wrong values
- **Premature or delayed compression** — context compression triggers at the
  wrong threshold (50% of 200K = 100K, even for models with 128K or 1M windows)
- **Silent failures** — models with smaller real windows (e.g. 8K) may overflow
  without warning because Hermes thinks there is 200K of headroom

Root cause: `model-discovery.sh` queries LiteLLM `/v1/models` and extracts only
model IDs, discarding the `max_input_tokens` / `context_length` metadata that
LiteLLM returns for concrete (non-wildcard) models. Then `config-hermes.sh`
assigns every entry `{"context_length": 262144}`.

Additionally, the current active model (`zai/glm-5.2`) is entirely absent from
the Hermes `custom_providers[].models` map because the generator was last run
when a different model set was live. Models present in the map but no longer in
LiteLLM (285 stale entries) are dead weight.

### 18.3 Objective

Ensure every model served by LiteLLM has an accurate `context_length` in both
Hermes `config.yaml` and the `host-config-gen` staging pipeline, so that context
compression, usage display, and overflow detection all work correctly.

Key Results:
- KR1: All 281 LiteLLM models present in Hermes `custom_providers[].models` map
- KR2: `zai/glm-5.2` (current active model) has accurate context_length set
- KR3: `generate.sh --dry-run` extracts real context_length from LiteLLM
       `max_input_tokens`, falling back to `context_length`, then 262144 only
       when neither is available (wildcard-expanded models)
- KR4: righthand-man profile config synced with the same accurate model map
- KR5: No stale entries (models not in LiteLLM) remain in the config

### 18.4 Constraints

- **Must not modify upstream Hermes agent source** — the fix is in the
  host-config-gen layer (`~/.hermes/host-config-gen/lib/`), not in
  `agent/model_metadata.py`
- **Must not break the Docker stack** — this is host-only; the Docker
  entrypoint has its own parallel pipeline that is unaffected
- **Config generation is merge-mode** — preserve all existing config sections
  (agent, tools, platforms, permissions, plugins) and only replace the
  `custom_providers[].models` map for the litellm provider entry
- **Secret safety** — API keys are read in-process via python3, never passed
  through shell variables (Hermes secret-redaction pitfall)

### 18.5 Solution

**18.5.1 Model discovery enhancement** (`lib/model-discovery.sh`)

The discovery Python script currently writes newline-separated model IDs to
`$STAGING_MODELS`. Enhance it to also capture context metadata and write a
second file `$STAGING_MODELS_JSON` containing model id -> context_length pairs
extracted from LiteLLM's response:

- Primary source: `max_input_tokens` (LiteLLM's preferred field)
- Fallback: `context_length` (older OpenAI-compatible servers)
- Final fallback: `262144` (only when neither is present — wildcard-expanded
  models like `zai/*` that LiteLLM reports without metadata)

**18.5.2 Hermes overlay fix** (`lib/config-hermes.sh`)

Replace the hardcoded `{"context_length": 262144}` with the actual value read
from `$STAGING_MODELS_JSON`. The models map is built from the JSON metadata
file, ensuring each model gets its real context window.

**18.5.3 Config application**

After regeneration, apply the staging overlay to:
- `~/.hermes/config.yaml` (default profile)
- `~/.hermes/profiles/righthand-man/config.yaml` (synced copy)
- `~/.config/opencode/opencode.jsonc` (litellm model list refreshed)

### 18.6 Success Criteria & Verification

| # | Criterion | Verification Command |
|---|-----------|---------------------|
| SC1 | `zai/glm-5.2` has context_length in config | `python3 -c "import yaml; d=yaml.safe_load(open('$HOME/.hermes/config.yaml')); print(d['custom_providers'][0]['models'].get('zai/glm-5.2'))"` returns a dict with context_length |
| SC2 | All LiteLLM models present | count of models in config map == count of LiteLLM non-wildcard models |
| SC3 | No stale entries | every model in config map exists in LiteLLM `/v1/models` |
| SC4 | generate.sh dry-run passes | `bash ~/.hermes/host-config-gen/generate.sh --dry-run` exits 0 |
| SC5 | Staging has accurate context | staging models map has non-262144 values for known models (e.g. anthropic models = 1000000) |
| SC6 | righthand-man synced | righthand-man config custom_providers models map matches default |
| SC7 | OpenCode config refreshed | opencode.jsonc litellm provider has current model list |

### 18.7 Context Length Resolution Chain (reference)

Hermes `get_model_context_length()` (agent/model_metadata.py:1613) resolution
order for `custom:litellm` provider:

0. `model.context_length` in config.yaml (top-level override) — not set
0b. `custom_providers[].models[model].context_length` — **this is what we fix**
1. Persistent cache (`context_length_cache.yaml`) — empty
2. Endpoint `/v1/models` live probe — LiteLLM returns `max_input_tokens`, but
   Hermes checks `context_length`/`context_window` first; wildcard models return
   nothing
3-8. Various provider-specific lookups (not applicable to LiteLLM proxy)
9. Default fallback: 256K

By populating step 0b correctly, we short-circuit the entire probe chain.

### Problem

A mechanical gap analysis (function inventory → cross-reference against `docs/` and `tests/`) compared the `docker-compose.yml` `environment:` block, `.env.example`, and `docs/06-config-and-env.md`. The central env-var reference (doc 06's "Environment variables" user-facing table) is missing 7 user-configurable variables that ARE present in both `docker-compose.yml` and `.env.example`. Users consulting doc 06 as the canonical env reference cannot discover these variables there — they must find them in feature-specific docs (15/21/03) instead.

### Root causes

1. doc 06 was written early and grew incrementally; feature docs (15 browser, 21 dashboard, 03 opencode-serve) added their own env vars to `.env.example` and `docker-compose.yml` but never back-filled the central reference table in doc 06.
2. No CI check enforces env-var parity between `docker-compose.yml`, `.env.example`, and doc 06.

### Gap matrix (intended-vs-implemented)

| Gap ID | Variable | In compose | In .env.example | In doc06 user-table | Severity | Fix |
|--------|----------|-----------|-----------------|---------------------|----------|-----|
| GA-01 [LOW] | `BROWSER_HUMAN_LOOP_ENABLED` | yes | yes | **NO** | Low — documented in doc 15 | Add row to doc06 table |
| GA-02 [LOW] | `BROWSER_VNC_PASSWORD` | yes | yes | **NO** | Low — documented in doc 15 | Add row to doc06 table |
| GA-03 [LOW] | `HERMES_DASHBOARD_ENABLED` | yes | yes | **NO** | Low — documented in doc 21 | Add row to doc06 table |
| GA-04 [LOW] | `HERMES_DASHBOARD_HOST` | yes | yes | **NO** | Low — documented in doc 21 | Add row to doc06 table |
| GA-05 [LOW] | `HERMES_DASHBOARD_PORT` | yes | yes | **NO** | Low — documented in doc 21 | Add row to doc06 table |
| GA-06 [LOW] | `OPENCODE_SERVE_ENABLED` | yes | yes | **NO** | Low — documented in doc 03 | Add row to doc06 table |
| GA-07 [LOW] | `OPENCODE_SERVE_BOOT_TIMEOUT` | yes | yes | **NO** | Low — documented in doc 03 | Add row to doc06 table |

### Non-gaps (verified, no action)

| Item | Verdict |
|------|---------|
| 14 function refs in docs (`resolve_trusted_workspace()`, `get_hermes_home()`, etc.) | NOT stale — reference hermes-agent Python internals (conceptual) or non-lib shell files (config-opencode.sh, install-skills.sh) or bats built-ins (teardown) |
| docs/README.md index (docs 01-24) | Complete — all 24 docs indexed |
| Major feature doc+test coverage | Complete — browser, persistence, viewport, profiles, webui-api, dashboard, wiki, fallback, doctrine, agent-install all have doc+test pairs |
| .env.example user-facing vars | Complete — all 12 important user vars present |
| Test helper functions | Complete — skip_if_no_secrets, get_container both defined |

### Success criteria

| # | Criterion | Verification |
|---|-----------|-------------|
| SC17.1 | doc06 "Environment variables" table contains all 7 GA-01..GA-07 vars | `for v in BROWSER_HUMAN_LOOP_ENABLED BROWSER_VNC_PASSWORD HERMES_DASHBOARD_ENABLED HERMES_DASHBOARD_HOST HERMES_DASHBOARD_PORT OPENCODE_SERVE_ENABLED OPENCODE_SERVE_BOOT_TIMEOUT; do grep -c "\\\`$v\\\`" docs/06-config-and-env.md; done` → each returns ≥1 |
| SC17.2 | No existing doc06 content removed (only additions) | `git diff docs/06-config-and-env.md` shows only inserted rows, no deletions |
| SC17.3 | graphify regenerated with new docs | `graphify-out/` has a fresh dated subdir or updated graph.json/manifest.json |
| SC17.4 | llm-wiki updated with viewport feature + gap-fix insights | wiki has new/updated entity page(s) for the configurable viewport and env-var parity |
| SC17.5 | PR documents all changes per coding-agents-docs-guideline | PR body follows the 8-section doc convention where applicable; docs/README.md index current |

### Changes

1. **`docs/06-config-and-env.md`** — add 7 rows to the "Environment variables" table (GA-01..GA-07), cross-referencing their feature docs.
2. **`graphify-out/`** — regenerate the knowledge graph after all doc changes land.
3. **llm-wiki** — ingest the configurable-viewport feature and the env-var parity gap/fix as durable wiki pages.

### Assumptions

- Adding these 7 rows to doc 06 as cross-references (not duplicating full descriptions) avoids doc-drift: the feature docs remain the source of truth for behavior; doc 06 becomes a complete index.
- graphify and llm-wiki are installed skills (confirmed in AGENTS.md section 9); the wiki lives at `/home/hermeswebui/.hermes/wiki` inside the container and on this host's hermes-home.

## 19. Issue Triage: Context-Length Pin (CA-31-A), Compression Threshold Transport (CA-31-B), OpenCode Credential Resolution (CA-30-A)

### 19.1 Summary

Two open issues on the downstream `vanilla-open-design` fork (#30 OpenCode
"0 credentials" on righthand-man profile, #31 compression-threshold and
context-length not respected) were investigated against this repo
(`hermes-x-opencode`). All three root causes are **inherited from this repo's
Docker-stack config-generation layer** — they are deployment-config gaps, not
upstream Hermes agent bugs. This section documents the triage, success criteria,
and fix scope. Fixes land here; the downstream fork will cherry-pick.

### 19.2 Background — why these issues live here

The Docker stack generates `config.yaml`, `opencode.jsonc`, and `auth.json` at
every boot from shell scripts in `volumes_hermes_opencode/build/scripts/lib/`:

- `config-hermes.sh` — Hermes `config.yaml` (model list + context_length pins)
- `config-opencode.sh` — OpenCode `opencode.jsonc` + `auth.json` credential store
- `profile-righthand-man.sh` — clones default profile → righthand-man, syncs config

Downstream `vanilla-open-design` inherited these scripts. Issues #30/#31 surface
at runtime inside the container but originate in these build-time generators.

### 19.3 Problem triage (intended-vs-implemented)

| Gap ID | Severity | Issue | Documented intent | Implemented reality | Impact |
|--------|----------|-------|-------------------|---------------------|--------|
| CA-31-A [HIGH] | #31 | `resolve_ctx_len()` pins the entire `*qwen3.6*` family to 1048576 (1M). | The pin table maps ANY model whose lowercased name contains `qwen3.6` to 1M — including the quantized llama.cpp GGUF `qwen3.6-27b-q4_k_m` whose true context window is 262144. The substring match is too coarse. | UI shows "1M context, 14% used"; actual window is 262144 (53% used). Compression threshold math is computed against the wrong denominator. |
| CA-31-B [HIGH] | #31 | User sets `HERMES_COMPRESSION_THRESHOLD=0.76` in `.env`. | `docker-compose.yml` `environment:` block passes 35 vars into the container. `HERMES_COMPRESSION_THRESHOLD` is NOT among them. The var dies at the host; the container never sees it. Agent uses its default threshold, ignoring 0.76. | User's compression threshold is silently dead. |
| CA-30-A [MEDIUM] | #30 | righthand-man orchestrator reports "OpenCode unavailable (0 credentials)". | When `OPENCODE_ZEN_API_KEY` is unset (the `.env.example` default), `generate_opencode_config()` gates the opencode provider block on `$_has_opencode_key`. Even when `OPENAI_API_KEY` IS set (litellm proxy available), the `auth.json` fallback store is seeded only with non-empty keys. If `OPENCODE_ZEN_API_KEY` is blank, no opencode credential entry is written; the litellm key is seeded but OpenCode's credential counter for the opencode CLI still reads 0 for the built-in provider. The righthand-man profile inherits this empty state. | righthand-man falls back to `delegate_task` instead of opencode CLI (the skill's documented fallback). |

### 19.4 Non-gaps (verified, no action)

| Item | Verdict |
|------|---------|
| Section 18 (bare-metal `host-config-gen`) | Separate pipeline. Section 18.5.2 explicitly states the Docker entrypoint is unaffected. No overlap with #30/#31. |
| Upstream Hermes agent (`agent/model_metadata.py`) | Not the cause. The agent self-resolves correctly when config.yaml omits context_length; our pin fires first (documented in `config-hermes.sh:9-15`). |
| `seed_righthand_man()` config sync | Works correctly — it copies config.yaml every boot. The issue is that the config.yaml IT copies has the wrong pin (CA-31-A), and auth.json has no opencode entry (CA-30-A). |

### 19.5 Objective

Ensure every model served by the LiteLLM proxy has an accurate `context_length`
in Hermes `config.yaml` (including quantized variants), the user's
`HERMES_COMPRESSION_THRESHOLD` reaches the container runtime, and OpenCode
can resolve at least one credential when `OPENCODE_ZEN_API_KEY` is unset but
`OPENAI_API_KEY` is set.

Key Results:
- KR1: Quantized qwen3.6 GGUF variants resolve to their true context window, not the family wildcard's 1M.
- KR2: `HERMES_COMPRESSION_THRESHOLD` set in `.env` is visible inside the container via `printenv`.
- KR3: When `OPENCODE_ZEN_API_KEY` is unset but `OPENAI_API_KEY` is set, OpenCode resolves the litellm provider credential (via `auth.json` seeding) so the righthand-man profile is not "0 credentials".

### 19.6 Success Criteria & Verification

| # | Criterion | Verification Command |
|---|-----------|---------------------|
| SC-31-1 | `resolve_ctx_len()` has a specific pin for the quantized GGUF variant | `grep -c 'qwen3.6-27b' volumes_hermes_opencode/build/scripts/lib/config-hermes.sh` returns >=1 |
| SC-31-2 | `HERMES_COMPRESSION_THRESHOLD` is transported into the container | `grep -c 'HERMES_COMPRESSION_THRESHOLD' docker-compose.yml` returns >=1 |
| SC-31-3 | Generated `config.yaml` shows 262144 for `qwen3.6-27b-q4_k_m` (not 1048576) | functional test: source resolve_ctx_len with the GGUF id, assert echo output == 262144 |
| SC-30-1 | When `OPENCODE_ZEN_API_KEY` unset + `OPENAI_API_KEY` set, `auth.json` contains a litellm entry | functional test: run auth.json seeding logic with OPENCODE_ZEN_API_KEY empty, assert litellm key present |
| SC-30-2 | righthand-man profile config.yaml is synced post-fix (existing behavior preserved) | existing profile-sync test still passes |

### 19.7 Solution

**CA-31-A (context_length pin):** Add a more-specific case row in
`resolve_ctx_len()` for the quantized GGUF variant(s), placed BEFORE the
`*qwen3.6*` family wildcard. Longest/most-specific patterns match first.

**CA-31-B (compression threshold transport):** Add
`HERMES_COMPRESSION_THRESHOLD` to the `docker-compose.yml` `environment:` block
(pass-through with `${HERMES_COMPRESSION_THRESHOLD:-}` default) and document
it in `.env.example`.

**CA-30-A (credential resolution):** The auth.json seeding in
`config-opencode.sh` already writes a litellm entry when `OPENAI_API_KEY` is
set. The fix ensures OpenCode recognizes this as a usable credential. Per user
decision (Q1 = Option 1): seed `auth.json` with the litellm provider entry so
opencode CLI sees >=1 credential (the litellm proxy) even when the built-in
opencode Zen key is absent.

### 19.8 Assumptions (surfaced, karpathy-guidelines)

- Assumption: `vanilla-open-design` is a downstream fork of this repo sharing the same config-generation scripts. Fixing here lets them cherry-pick.
- Assumption: The "1M context" the UI shows comes from our `config.yaml` pin (1048576), not from the agent self-resolving. Verified: our pin fires before self-resolution (`config-hermes.sh:9-15` documents the ordering).
- Assumption: Quantized GGUF variants of a model family need their own pin rows. The family wildcard (`*qwen3.6*`) is too coarse for variants with different context windows.
- Assumption: For CA-30-A, the user left `OPENCODE_ZEN_API_KEY` blank (matches `.env.example` default). The "0 credentials" symptom matches exactly.
- Assumption: Commenting on (not closing) the downstream issues is the correct disposition per user instruction — the fix lands upstream first, then is ported downstream.

### 19.9 Changes

1. `volumes_hermes_opencode/build/scripts/lib/config-hermes.sh` — add quantized GGUF pin row(s) in `resolve_ctx_len()`.
2. `docker-compose.yml` — add `HERMES_COMPRESSION_THRESHOLD` to `environment:` block.
3. `.env.example` — document `HERMES_COMPRESSION_THRESHOLD`.
4. `volumes_hermes_opencode/build/scripts/lib/config-opencode.sh` — ensure `auth.json` litellm seeding is recognized by opencode credential resolution when `OPENCODE_ZEN_API_KEY` is unset.
5. `tests/` — new bats test(s) for SC-31-1..3, SC-30-1..2.
6. GitHub issue comments on `vanilla-open-design` #30 and #31 (explain fix, do NOT close).

### 19.10 Verification Policy

All changes verified by:
1. `bash -n` on all modified shell scripts (syntax).
2. Functional unit tests for `resolve_ctx_len()` (SC-31-1, SC-31-3) and auth.json seeding (SC-30-1).
3. Full bats suite (`tests/run.sh`) — no regressions.
4. `git diff --stat` reconciliation after each wave to catch scope creep.

## 20. Environment Variable Naming Convention Alignment (OPENCODE_API_KEY → OPENCODE_ZEN_API_KEY)

### 20.1 Problem

The Docker stack uses `OPENCODE_ZEN_API_KEY` everywhere (`.env.example`, `docker-compose.yml`, scripts, docs, tests). The official Hermes agent runtime expects `OPENCODE_ZEN_API_KEY` — this is the canonical name used by:

- `hermes config` — auto-detects `OPENCODE_ZEN_API_KEY`
- `hermes doctor` — checks `OPENCODE_ZEN_API_KEY`
- `plugins/model-providers/opencode-zen/__init__.py` — reads `OPENCODE_ZEN_API_KEY` via `env_vars=("OPENCODE_ZEN_API_KEY",)`
- `~/.hermes/.env` (host) — already uses `OPENCODE_ZEN_API_KEY`

**Gap:** Inside the container, the Hermes agent's `opencode-zen` provider plugin cannot find the key because only `OPENCODE_ZEN_API_KEY` is exported. The OpenCode CLI works because its config explicitly references `{env:OPENCODE_ZEN_API_KEY}`. But any code path where the Hermes agent directly invokes the `opencode-zen` provider (e.g. fallback providers, model discovery, `hermes doctor`) will fail to authenticate.

### 20.2 Objective

Align Docker stack environment variable naming with the official Hermes agent convention (`OPENCODE_ZEN_API_KEY`) for a "most vanilla" approach. This ensures:

1. The Hermes agent runtime inside the container can find its Zen credential natively
2. `hermes doctor` reports correct credential status
3. The Docker stack `.env.example` mirrors what a vanilla `~/.hermes/.env` would look like
4. OpenAI-compatible API naming convention is preserved (`OPENAI_*` prefix for proxy, `OPENCODE_ZEN_API_KEY` for Zen)

### 20.3 Impact Map

Rename `OPENCODE_ZEN_API_KEY` → `OPENCODE_ZEN_API_KEY` across the codebase:

| File | References | Notes |
|------|-----------|-------|
| `.env.example` | 1 | Primary template |
| `docker-compose.yml` | 1 (line 49) | Container env injection |
| `lib/config-opencode.sh` | 6 | Config generation + auth.json seeding |
| `lib/service-opencode.sh` | 2 | `su` env passthrough |
| `lib/validate-opencode.sh` | 5 | Zen API key validation |
| `README.md` | 4 | User-facing docs |
| `PRD.md` | ~20 | Architecture docs |
| `AGENTS.md` | 2 (lines 115-116) | Agent instructions |
| `docs/03-opencode-serve.md` | 1 | |
| `docs/05-entrypoint-sequence.md` | 5 | |
| `docs/06-config-and-env.md` | ~15 | |
| `docs/09-testing-and-verification.md` | 1 | |
| `docs/14-delegation-matrix.md` | 2 | |
| `docs/20-opencode-runtime-fallback.md` | 1 | |
| `tests/e2e/03-config.bats` | 8 | |
| `tests/e2e/10-acp-limitation.bats` | 2 | |
| `tests/e2e/19-ctx-pin-and-credentials.bats` | 1 | |
| `.github/workflows/e2e.yml` | 1 | CI secrets reference |

**Critical change:** `config-opencode.sh` generates `{env:OPENCODE_ZEN_API_KEY}` → must become `{env:OPENCODE_ZEN_API_KEY}` in `opencode.jsonc`.

### 20.4 Solution

1. **Rename env var**: `OPENCODE_ZEN_API_KEY` → `OPENCODE_ZEN_API_KEY` everywhere in scripts, docker-compose, `.env.example`
2. **Update generated config**: `{env:OPENCODE_ZEN_API_KEY}` → `{env:OPENCODE_ZEN_API_KEY}` in `config-opencode.sh`
3. **Update CI workflow**: `secrets.OPENCODE_ZEN_API_KEY` → `secrets.OPENCODE_ZEN_API_KEY`
4. **Update tests**: All BATS assertions referencing `OPENCODE_ZEN_API_KEY`
5. **Update docs**: README, PRD, AGENTS.md, all `docs/*.md`

### 20.5 Success Criteria

| ID | Description | Verification |
|----|-------------|-------------|
| SC-20-1 | `docker-compose.yml` exports `OPENCODE_ZEN_API_KEY` | `grep OPENCODE_ZEN_API_KEY docker-compose.yml` |
| SC-20-2 | `config-opencode.sh` writes `{env:OPENCODE_ZEN_API_KEY}` | `grep 'env:OPENCODE_ZEN_API_KEY' config-opencode.sh` |
| SC-20-3 | No remaining references to `OPENCODE_API_KEY` in scripts/docs/tests | `grep -rn 'OPENCODE_API_KEY' --include='*.sh' --include='*.yml' --include='*.bats' --include='*.md' .` returns 0 |
| SC-20-4 | `hermes doctor` inside container sees `OPENCODE_ZEN_API_KEY` | Container runtime check |
| SC-20-5 | All bats tests pass | `tests/run.sh` exits 0 |

### 20.6 Verification Results

All static success criteria met:

| Criteria | Status | Evidence |
|----------|--------|----------|
| SC-20-1 | PASS | `docker-compose.yml` → `- OPENCODE_ZEN_API_KEY=${OPENCODE_ZEN_API_KEY:-}` |
| SC-20-2 | PASS | `config-opencode.sh` → `"apiKey": "{env:OPENCODE_ZEN_API_KEY}"` |
| SC-20-3 | PASS | `grep -rn 'OPENCODE_API_KEY'` returns 0 hits in repo-tracked files (excluding data/ volumes) |
| SC-20-4 | PENDING | Runtime verification on next container boot |
| SC-20-5 | PENDING | CI verification on next push |

**Shell syntax:** All 3 modified `.sh` files pass `bash -n`.
**Files modified:** 18 total (3 scripts + 1 compose + 1 example + 1 CI workflow + 3 docs + 7 tests + PRD + AGENTS.md + README).

### 20.7 Host vs Docker Env Var Parity Analysis

After the rename, remaining gaps between `~/.hermes/.env` (host) and Docker stack:

**Host has, Docker stack does not expose (intentionally N/A):**
| Variable | Purpose | Docker relevance |
|----------|---------|------------------|
| `BROWSERBASE_*` | Browser automation provider | N/A — Docker uses local Xvfb |
| `BROWSER_INACTIVITY_TIMEOUT` | Browser session timeout | N/A |
| `HASS_URL` | Home Assistant integration | N/A |
| `IMAGE_TOOLS_DEBUG` | Debug flag | N/A — container has its own debug controls |
| `MOA_TOOLS_DEBUG` | Debug flag | N/A |
| `SUDO_PASSWORD` | Host sudo | N/A |
| `TERMINAL_*` | Terminal session config | N/A — container terminal is isolated |
| `VISION_TOOLS_DEBUG` | Debug flag | N/A |
| `WEB_TOOLS_DEBUG` | Debug flag | N/A |

**Fully aligned (no action needed):**
| Variable | Status |
|----------|--------|
| `OPENAI_API_KEY` | ✅ Same name, same purpose |
| `OPENAI_BASE_URL` | ✅ Same name, same purpose |
| `OPENAI_DEFAULT_MODEL` | ✅ Same name, same purpose |
| `HERMES_DEFAULT_MODEL` | ✅ Same name, same purpose |
| `OPENCODE_DEFAULT_MODEL` | ✅ Same name, same purpose |
| `OPENCODE_SMALL_MODEL` | ✅ Same name, same purpose |
| `OPENCODE_FALLBACK_MODEL` | ✅ Same name, same purpose |
| `OPENCODE_ZEN_API_KEY` | ✅ Renamed from OPENCODE_API_KEY |
| `WIKI_PATH` | ✅ Same name, same purpose |

**Verdict:** After OPENCODE_API_KEY → OPENCODE_ZEN_API_KEY rename, the Docker stack follows the same OpenAI-compatible API naming convention as the host `~/.hermes/.env`. All LLM provider variables are aligned.

### 20.8 Assumptions

- The Hermes agent source (`data/hermes-home/hermes-agent/`) already uses `OPENCODE_ZEN_API_KEY` and does NOT need changes — it's the authority
- Session JSON files in `data/hermes-home/webui/sessions/` contain historical references that don't need updating
- The GitHub Actions secret name (`OPENCODE_ZEN_API_KEY`) needs to be updated in the CI workflow, but the actual secret value in GitHub settings is out-of-scope for this PR (user must rename the secret in GitHub)
- `vanilla-open-design` downstream fork will cherry-pick this change independently

## 21. Per-Delegation Model Routing

### 21.1 Problem

All agent conversations (parent + subagents) use the same model. The user wants different models for main conversation vs delegated subagents — e.g. expensive reasoning model for the parent, cheaper fast model for subagents.

**Current state:** `config-hermes.sh` writes `delegation.max_iterations` but never writes `delegation.model` or `delegation.provider`. Every subagent inherits the parent's model — no differentiation.

**Hermes agent native support:** The agent runtime already supports per-delegation model routing via:

```yaml
delegation:
  model: openai/gpt-4o-mini
  provider: litellm
```

Reference: `tools/delegate_tool.py:2043` (resolves `delegation.provider` + `delegation.model` credential overrides), `website/docs/user-guide/configuration.md:1717` (subagent provider:model override docs).

### 21.2 Objective

Expose `delegation.model` and `delegation.provider` through Docker env vars so the user can configure different models for subagents without editing config.yaml manually.

### 21.3 Solution

Add two new env vars:

| Variable | Purpose | Maps to config.yaml |
|----------|---------|---------------------|
| `HERMES_DELEGATION_MODEL` | Model for subagent conversations | `delegation.model` |
| `HERMES_DELEGATION_PROVIDER` | Provider for subagent routing | `delegation.provider` |

When `HERMES_DELEGATION_MODEL` is set, `config-hermes.sh` appends the delegation model block. When `HERMES_DELEGATION_PROVIDER` is also set, both are written together. When only `model` is set, the subagent inherits the parent's provider (Hermes documented behavior — "Setting just `model` without `provider` changes only the model name while keeping the parent's credentials").

**Config output example:**

```yaml
delegation:
  max_iterations: 50
  model: openai/gpt-4o-mini
  provider: litellm
```

### 21.4 Impact Map

| File | Change |
|------|--------|
| `.env.example` | Document `HERMES_DELEGATION_MODEL` and `HERMES_DELEGATION_PROVIDER` |
| `docker-compose.yml` | Add env injection for both vars |
| `config-hermes.sh` | Append `model`/`provider` under `delegation:` block in `generate_config()` |
| `README.md` | Document new env vars |
| `docs/06-config-and-env.md` | Add to env var table |
| `tests/e2e/03-config.bats` | Test delegation model block generation |

### 21.5 Verification Results

| Criteria | Status | Evidence |
|----------|--------|----------|
| SC-21-1 | PASS | `.env.example` (lines 113-118), `docker-compose.yml` (lines 57-58) |
| SC-21-2 | PASS | `config-hermes.sh` (lines 60-73) — dynamic delegation_block with model |
| SC-21-3 | PASS | `config-hermes.sh` (lines 61, 68-70) — provider appended when set |
| SC-21-4 | PASS | When unset, only `delegation.max_iterations` appears — model/provider conditional |
| SC-21-5 | PASS | `bash -n config-hermes.sh` → SYNTAX OK |
| SC-21-6 | PENDING | New test `AC34` added to `tests/e2e/03-config.bats` — needs CI runtime |

**Files modified:** 7 total (`config-hermes.sh`, `docker-compose.yml`, `.env.example`, `docs/06-config-and-env.md`, `README.md`, `tests/e2e/03-config.bats`, `PRD.md`).

### 21.6 Assumptions

- The user provides valid model names and provider strings — no validation needed beyond what Hermes agent does at runtime
- `delegation.max_iterations` already exists in the delegation block; `model`/`provider` are additive fields under the same YAML key
- No change to Hermes agent source needed — it already handles `delegation.model`/`delegation.provider`
- The same `key_env: OPENAI_API_KEY` in the `custom_providers` block covers subagent auth when `delegation.provider: litellm` is set

All changes verified by:
1. `bash -n` on all modified shell scripts (syntax).
2. Functional unit tests for `resolve_ctx_len()` (SC-31-1, SC-31-3) and auth.json seeding (SC-30-1).
3. Full bats suite (`tests/run.sh`) — no regressions.
4. `git diff --stat` reconciliation after each wave to catch scope creep.

## 22. Feature Parity Bridge: vanilla-open-design

`vanilla-open-design` is a superset fork of this repo with divergent architecture: it adds an OD daemon (`service-daemon.sh`), an auth proxy (`service-auth-proxy.sh`), code-server (`service-code-server.sh`), and Docker-in-Docker (`service-dind.sh`) on top of the shared Docker stack. These are architectural additions not part of the hermes-x-opencode scope.

This section tracks what was **PORTED** from vanilla-open-design (shared improvements to config generation, lib modules, seeding) versus what was intentionally **SKIPPED** (divergent services outside this repo's scope). Wave 1 and T4/T5 already applied the code changes; this section records the decisions.

### Gap Matrix

| Feature | Status | Notes |
|---------|--------|-------|
| Parameterized constants (`log`/`warn` helpers, env-driven defaults) | PORTED | `constants.sh` now uses `${HERMES_HOME}` + runtime config |
| `seed-volumes.sh` (skill/root/volume seeding) | PORTED | Replaces inline skill-staging in entrypoint.sh |
| `mock-llm-server.sh` (inline CI mock LLM) | PORTED | Lib module version for entrypoint; standalone `tests/mock-llm-server.sh` kept |
| `symlink-cleanup.sh` (symlink loop removal) | PORTED | Prevents recursive symlink issues in skills dirs |
| `service-webui.sh` (modular WebUI startup) | PORTED | Wraps `/hermeswebui_init.bash` in `start_webui()` |
| `port-utils.sh` health endpoint checking | PORTED | `wait_for_port()` now accepts HTTP health path as $4 |
| `config-hermes.sh` compression threshold | PORTED | `HERMES_COMPRESSION_THRESHOLD` transported to config.yaml |
| `config-hermes.sh` browser viewport dimensions | PORTED | `BROWSER_DISPLAY_WIDTH`/`HEIGHT` in browser config block |
| OD daemon (`service-daemon.sh`) | SKIPPED | N/A — hermes-x-opencode has no OD daemon |
| Auth proxy (`service-auth-proxy.sh`) | SKIPPED | N/A — handled via Dokploy reverse proxy per instance |
| code-server (`service-code-server.sh`) | SKIPPED | N/A — not part of hermes-x-opencode scope |
| Docker-in-Docker (`service-dind.sh`) | SKIPPED | N/A — not part of hermes-x-opencode scope |
| `docker-compose.dokploy.yml` | SKIPPED | Dokploy config set via env vars per instance, not tracked |
| `docker-compose.dind.yml` | SKIPPED | N/A — DinD not in scope |
| `docker-compose.dev.yml` | SKIPPED | hx uses `docker-compose.override.yml` convention |

### Code Duplication Audit

- No cross-module function name collisions across `lib/*.sh` (verified via `grep -h '^[a-z_]*()' lib/*.sh | sort | uniq -d`)
- `install-skills.sh` skill list is intentionally duplicated from Dockerfile COPY block — different lifecycle (build-time vs runtime)
- `tests/mock-llm-server.sh` standalone script coexists with `lib/mock-llm-server.sh` — standalone for manual testing, lib for entrypoint startup

## 23. OPENCODE_*_MODEL Provider-Prefix Convention

### Problem

`OPENCODE_*_MODEL` environment variables (`OPENCODE_DEFAULT_MODEL`, `OPENCODE_SMALL_MODEL`, `OPENCODE_FALLBACK_MODEL`) accepted bare model IDs (e.g., `z.ai/glm-5.2`, `llama_cpp/qwen3.6-27b-q4_k_m`) which are auto-resolved at config-generation time by `_resolve_provider_prefix()` in `config-opencode.sh`. Bare IDs route to `litellm` when `OPENAI_BASE_URL` + `OPENAI_API_KEY` are set, else `opencode` Zen. This implicit resolution is non-obvious from `.env.example` — users may not realize their model silently routes to a different provider than intended, especially when credentials change.

### Decision

**Always use explicit `<provider>/<model>` format for all `OPENCODE_*_MODEL` values.** The two recognized provider prefixes are:

| Prefix | Routes to | Requires |
|--------|-----------|----------|
| `opencode/<model>` | OpenCode Zen | `OPENCODE_ZEN_API_KEY` |
| `litellm/<model>` | Self-hosted LiteLLM proxy | `OPENAI_BASE_URL` + `OPENAI_API_KEY` |

Bare IDs still work (backward compatible) but the `.env.example` comments and examples now explicitly show the prefixed form. This makes routing intent visible at a glance and prevents silent misrouting when credential availability changes.

### Scope

- `OPENCODE_*_MODEL` variables only — these flow through `_resolve_provider_prefix()` in `config-opencode.sh`
- `OPENAI_*_MODEL` and `HERMES_*_MODEL` are NOT affected — they go through different resolution paths (Hermes `config.yaml` generation)
- `.env.example` examples and comments updated; no code changes to `config-opencode.sh` needed

### Changes

| File | Change |
|------|--------|
| `.env.example` lines 19-25 | Add format preamble explaining recognized prefixes; update commented-out `OPENCODE_DEFAULT_MODEL` and `OPENCODE_SMALL_MODEL` examples to use `litellm/` prefix |
| `.env.example` lines 36-49 | Update fallback model examples to use explicit `litellm/` prefix on each entry; update chain comment to match |
| `.env.example` line 50 | Update active default fallback value to use `litellm/` prefix |

### Verification

```bash
# All OPENCODE_* model values use explicit prefix
grep 'OPENCODE_' .env.example | grep -v '^#' | grep -v 'opencode/' | grep -v 'litellm/'
# ^ should return empty (no bare IDs in active defaults)

# Commented examples also use explicit prefixes
grep 'OPENCODE_.*MODEL=' .env.example
# ^ all entries use either opencode/ or litellm/ prefix
```

## 24. Cross-Repo Gap Bridge: vanilla-open-design + host-machine (July 2026)

### Source Repos

| Repo | Role | Since |
|------|------|-------|
| `vanilla-open-design` | Downstream fork (superset) | Commits #42–#45 (bcb3378..f2c756d), since last bridge #69 / 07351f8 |
| `hermes-x-opencode--host-machine` | Host-level config generator | Commits #4–#13 (eb24704..HEAD), all new since extraction |

### Gap Matrix: vanilla-open-design (#42–#45)

| Item | Source Commit | Classification | Rationale | Action |
|------|--------------|----------------|-----------|--------|
| Test path fix (AC170-AC171) | 03619eb (#42) | SKIP | Docker-specific test file (`37-service-webui.bats`) — container paths | — |
| OAuth2-proxy multi-email docs | c5522b2 (#43) | SKIP | `AUTHENTICATED_EMAILS` / `EMAIL_DOMAINS` are vanilla-specific (oauth2-proxy not in this repo) | — |
| `.env.example` enforcement language | bcb3378 (#44) | ALREADY-PRESENT | This repo's `.env.example` lines 19–24 already contain: "STRONGLY recommended to make routing intent visible and prevent silent misrouting" | Verify only — no code change |
| Provider routing single source of truth | f2c756d (#45) | PORT | See detailed breakdown below | Refactor `config-opencode.sh` |

### PORT Detail: Provider Routing Single Source of Truth (#45)

Vanilla refactored `config-opencode.sh` to eliminate duplicate provider-prefix logic scattered across bash case statements. The refactor introduces three changes:

#### 1. `PROVIDER_PREFIXES` constant + `normalize_model_id()` function

**Current (this repo):** Two separate bash functions with hardcoded case statements:
- `_resolve_provider_prefix()` — returns just the prefix name (`opencode` / `litellm`)
- `_strip_provider_prefix()` — returns the model ID without prefix

Callers then re-concatenate: `${default_prefix}/${default_model}`. Adding a new provider requires editing both functions + all call sites.

**Target (vanilla PR #45):** One constant + one function:
```bash
export PROVIDER_PREFIXES="opencode litellm"
normalize_model_id() {
    local model="$1"
    local pfx
    for pfx in $PROVIDER_PREFIXES; do
        case "$model" in ${pfx}/*) echo "$model"; return ;; esac
    done
    # Bare ID: litellm if proxy creds present, else opencode Zen
    if [ -n "${OPENAI_BASE_URL:-}" ] && [ -n "${OPENAI_API_KEY:-}" ]; then
        echo "litellm/${model}"
    else
        echo "opencode/${model}"
    fi
}
```
Adding a provider = adding one word to `PROVIDER_PREFIXES`. The function returns the FULL canonical form (`provider/model`) — no strip-then-re-concatenate dance.

#### 2. Models JSON key prefix stripping

**Current:** Python block uses full model IDs as map keys (e.g. `"litellm/z.ai/glm-5.2"`).

**Target:** Python block reads `PROVIDER_PREFIXES` from environment, strips recognized prefixes from map keys, so the models map uses bare IDs as keys (consistent with OpenCode's convention). The full name stays in the `"name"` field.

#### 3. Fallback chain uses `normalize_model_id()` directly

**Current:** Fallback chain iterates entries, calls `_strip_provider_prefix()` + `_resolve_provider_prefix()`, then re-concatenates.

**Target:** Fallback chain calls `normalize_model_id()` once per entry — single call, no re-concatenation.

#### What stays unchanged

- Security mode permission blocks (yolo/standard/strict) — untouched
- Root config copy (Fix #28) — untouched
- Auth.json seeding (CA-30-A) — untouched
- Fallback.jsonc seeding (#55) — untouched
- Root data dir symlink (Fix #29) — untouched
- `get_limits()` logic — untouched (vanilla's version already identical)
- Plugin list and `$schema` — untouched

### Gap Matrix: host-machine (#4–#13)

| Item | Source Commit(s) | Classification | Rationale | Action |
|------|-----------------|----------------|-----------|--------|
| `export-env.sh` generation | ce9083e (#10), 8125b8c (#11) | SKIP | Container environment already has all env vars set — no need for a sourceable export script | — |
| `--apply` flag | ce9083e (#10) | SKIP | Host-only install→generate→apply workflow; container uses direct file writes | — |
| Shell integration | 8149e0d (#12) | SKIP | Host-only `.bashrc` sourcing; container has no shell profile | — |
| CI pipeline + mock server | b301af3 (#9), f8c2e1c (#13) | SKIP | Docker stack has its own CI (`tests/run.sh`, `tests/mock-llm-server.sh`) | — |
| Section-based `.env` sync | 5da3d11 | SKIP | Host-only managed-marker `.env` merging; container regenerates from `.env.example` | — |
| Portable `.env` sourcing | 46dd46b, 9f03127 | SKIP | Container uses fixed paths (`/home/hermeswebui/`) — portability not needed | — |
| `model-discovery.sh` `key_env` fallback | 36673de | N/A | This repo reads `OPENAI_API_KEY` directly from env, not from `config.yaml` — different architecture, no gap | — |
| `OPENCODE_ZEN_API_KEY` rename | 987b589, 65d6218 (#4) | ALREADY-PRESENT | This repo already uses `OPENCODE_ZEN_API_KEY` throughout (constants.sh, config-opencode.sh line 290), no `OPENCODE_API_KEY` → `OPENCODE_ZEN_API_KEY` rename needed | — |
| `validate-zen.sh` module | 8149e0d (#12) | ALREADY-PRESENT | This repo has `validate-opencode.sh` with identical Zen API key validation logic (curl → Zen /v1/models, model count check, warning on failure) | — |
| `delegation.model` + `delegation.provider` routing | 65d6218 (#4) | ALREADY-PRESENT | `config-hermes.sh` lines 60–75 already support `HERMES_DELEGATION_MODEL` and `HERMES_DELEGATION_PROVIDER` env vars | — |
| `model.default` + `model.name` always set | 04876f3 | ALREADY-PRESENT | `config-hermes.sh` lines 176–177 directly assign both fields from `default_model` — no preservation of stale values | — |
| `qwen3.6-27b` context pin (262144) | 65d6218 (#4) | ALREADY-PRESENT | `config-hermes.sh` `resolve_ctx_len()` line 33 already pins `*qwen3.6-27b*q4*` to 262144 | — |
| Multi-provider model routing | 9b9d63f (#7), 21265e5 (#6) | COVERED | Covered by vanilla PR #45 provider routing PORT — `normalize_model_id()` handles all `OPENCODE_*_MODEL` routing | — |

### Summary: Actionable Items

| # | Action | Scope | Delegation |
|---|--------|-------|------------|
| 1 | Refactor `config-opencode.sh`: replace `_resolve_provider_prefix()` + `_strip_provider_prefix()` with `PROVIDER_PREFIXES` + `normalize_model_id()` | 2 bash functions → 1 constant + 1 function; update call sites | Wave 1, Subagent A |
| 2 | Update models_json Python block: strip recognized provider prefixes from map keys | ~3 lines in Python heredoc | Wave 1 (fold into Subagent A) |
| 3 | Update fallback chain: use `normalize_model_id()` directly | ~3 lines in bash loop | Wave 1 (fold into Subagent A) |
| 4 | Verify `.env.example` enforcement language parity | Read-only check — already present | Parent turn (verification) |
| 5 | Append this PRD section (done) | PRD.md | Parent turn |
| 6 | Verify: `bash -n` all scripts, bats tests, config generation | Verification phase | Parent turn |

### Assumptions

1. **Assumption:** Vanilla's `normalize_model_id()` bash pattern (loop over space-separated PROVIDER_PREFIXES) is simpler and correct for this repo's container context. The repo gains single-source-of-truth maintainability without changing runtime behavior.
2. **Assumption:** The models_json key-stripping change (full ID → bare ID as map key) is backward-compatible — OpenCode reads the `"name"` field for routing, not the map key.
3. **Assumption:** No host-machine code patterns are portable to this Docker stack — all are either host-specific workflows or already present.
4. **Assumption:** The `.env.example` enforcement language is already identical in intent — the minor textual differences (─── separator, "no prefix" vs "Bare model IDs") are cosmetic and do not change user behavior.

### Success Criteria

- [ ] `bash -n volumes_hermes_opencode/build/scripts/lib/config-opencode.sh` passes
- [ ] `grep -c '_resolve_provider_prefix\|_strip_provider_prefix' config-opencode.sh` returns 0 (old functions removed)
- [ ] `grep -c 'PROVIDER_PREFIXES\|normalize_model_id' config-opencode.sh` ≥ 2 (new constant + function present)
- [ ] All existing bats tests pass (docker-exec based, skip curl-based)
- [ ] Config generation produces valid `opencode.jsonc` (JSON parse) and `config.yaml` (YAML parse)
- [ ] PR opened on branch `feat/bridge-downstream-jul2026`

## 25. Bats-Core Baked Into Image Build (Issue #71)

### Problem

Agents running inside the container cannot write or run bats tests — bats-core is not installed in the Docker image. Currently bats is only available on the CI runner (installed via `sudo apt-get install -y bats` in `.github/workflows/e2e.yml`) and expected on the developer host (`tests/run.sh`). Baking it into the image gives agents a testing framework knowledge base, as requested in issue #71.

### Changes

1. **Dockerfile** — add `bats` to the first `apt-get install` block (build tools group: build-essential, git, ripgrep, etc.) and add `bats --version` to the final build-time verification assertion chain.
2. **tests/e2e/01-build.bats** — new test AC209 verifies `docker run --rm <image> bats --version` succeeds with non-empty output.

### Assumptions

1. **Assumption:** `apt-get install bats` on Debian provides bats-core — already proven by `.github/workflows/e2e.yml` which uses the same package name successfully.
2. **Assumption:** bats belongs in the build-tools apt-get block (conceptually grouped with build-essential), not the browser/media block.
3. **Assumption:** No entrypoint or PATH changes needed — apt installs bats to `/usr/bin/bats`, available on the default PATH.

### Success Criteria

- [ ] SC-25-1: `docker run --rm <image> bats --version` succeeds (non-empty output, exit 0)
- [ ] SC-25-2: New bats test AC209 passes: `bats tests/e2e/01-build.bats --filter AC209`
- [ ] SC-25-3: Existing bats suite passes (no regression)
- [ ] SC-25-4: `docker compose build` succeeds with the new package

## 26. opencode-go / opencode Model Context Length Pin Table Update

### Problem

The user upserted 11 new models into the LiteLLM proxy config, split across two
opencode Zen API bases:

- `opencode/*` (Zen free tier): deepseek-v4-flash-free, mimo-v2.5-free,
  nemotron-3-ultra-free, north-mini-code-free, qwen3.6-plus-free
- `opencode-go/*` (Zen go tier): deepseek-v4-pro, deepseek-v4-flash, glm-5.2,
  kimi-k2.6, kimi-k2.7-code, minimax-m3

LiteLLM's `/v1/models` endpoint returns no context-window metadata for these
models (only id/object/created/owned_by), so the build scripts' pin tables are
the only source of context length for generated configs.

Two pin tables exist in the build directory:

1. `config-hermes.sh` `resolve_ctx_len()` (bash case) — handles hermes
   `config.yaml`. Already correct for all 11 models: `*glm-5.2*`, `*deepseek-v4*`,
   `*minimax-m3*`, `*qwen3.6*` are pinned; unknown families (kimi, mimo,
   nemotron, north) are omitted so the hermes-agent self-resolves at runtime via
   its own `DEFAULT_CONTEXT_LENGTHS` table.
2. `config-opencode.sh` `get_limits()` (Python in heredoc) — handles
   `opencode.jsonc`. **8 of 11 models are misresolved** because the function
   lacks specific family entries and its `deepseek` catch-all returns 128000
   (wrong for v4 which is 1M).

### Root Cause

`get_limits()` in `config-opencode.sh` (lines 79-114) was written before the
opencode-go/* and opencode/* free-tier models were added. The `deepseek`
catch-all on line 104 returns 128000 — the correct value for legacy deepseek
models, but deepseek-v4 has a 1M context window. Similarly, kimi, minimax-m3,
mimo-v2.5, nemotron, and qwen3.6 families fall through to the default
`return 128000, 8192` because no specific entries exist for them.

### Solution

Add specific family entries to `get_limits()`, placed BEFORE the existing
`deepseek` catch-all (longest-match-first ordering, mirroring the agent's own
`DEFAULT_CONTEXT_LENGTHS` table and `resolve_ctx_len()`). Values sourced from
the agent's authoritative table at `agent/model_metadata.py`:

| Family | Substring | Context | Output | Notes |
|--------|-----------|---------|--------|-------|
| deepseek-v4 | `deepseek-v4` | 1000000 | 8192 | Before `deepseek` catch-all |
| kimi | `kimi` | 262144 | 8192 | Agent table: `kimi` → 262144 |
| minimax-m3 | `minimax-m3` | 1000000 | 8192 | Before any minimax catch-all |
| mimo-v2.5 | `mimo-v2.5` | 1048576 | 8192 | Agent table: `mimo-v2.5` → 1M |
| nemotron | `nemotron` | 131072 | 8192 | Agent table: `nemotron` → 131072 |
| qwen3.6 | `qwen3.6` | 1048576 | 8192 | Agent table: `qwen3.6-plus` → 1M |

`north-mini-code-free` has no entry in the agent's table and no known context
window — left at the 128000 default.

### Assumptions

1. **Assumption:** Output limit of 8192 is acceptable for all new families. The
   agent's `DEFAULT_CONTEXT_LENGTHS` table only tracks context, not output; the
   LiteLLM upsert sets no `max_output_tokens`.
2. **Assumption:** `north-mini-code-free` context window is unknown — keep the
   128000 default.
3. **Assumption:** The `opencode-go/*` and `opencode-go/anthropic/*` wildcard
   entries from LiteLLM are filtered by `model-discovery.sh` line 67
   (`re.search(r'/\*$', ...)`) — no action needed for wildcards.
4. **Assumption:** No changes needed to `config-hermes.sh` `resolve_ctx_len()`
   — it already handles all 11 models correctly (pinned or self-resolved).

### Success Criteria

- [ ] SC-26-1: `get_limits('opencode-go/deepseek-v4-pro')` returns `(1000000, 8192)`
- [ ] SC-26-2: `get_limits('opencode-go/deepseek-v4-flash')` returns `(1000000, 8192)`
- [ ] SC-26-3: `get_limits('opencode/deepseek-v4-flash-free')` returns `(1000000, 8192)`
- [ ] SC-26-4: `get_limits('opencode-go/kimi-k2.6')` returns `(262144, 8192)`
- [ ] SC-26-5: `get_limits('opencode-go/kimi-k2.7-code')` returns `(262144, 8192)`
- [ ] SC-26-6: `get_limits('opencode-go/minimax-m3')` returns `(1000000, 8192)`
- [ ] SC-26-7: `get_limits('opencode/mimo-v2.5-free')` returns `(1048576, 8192)`
- [ ] SC-26-8: `get_limits('opencode/nemotron-3-ultra-free')` returns `(131072, 8192)`
- [ ] SC-26-9: `get_limits('opencode/qwen3.6-plus-free')` returns `(1048576, 8192)`
- [ ] SC-26-10: `get_limits('opencode-go/glm-5.2')` still returns `(1048576, 131072)` (no regression)
- [ ] SC-26-11: `get_limits('llama_cpp/qwen3.6-27b-q4_k_m')` still returns `(262144, 32768)` (no regression)
- [ ] SC-26-12: `bash -n config-opencode.sh` passes (no syntax errors)
- [ ] SC-26-13: Existing bats tests pass: `tests/e2e/19-ctx-pin-and-credentials.bats`, `tests/e2e/03-config.bats`

## 27. Docs & Tests Re-Audit (Jul 2026): agents-a1 Documentation & Coverage Gaps

**Status: RESOLVED** — merged via PR #77 (per-module docs/tests baseline) and
PR #78 (agents-a1 ctx-pin bridge + this re-audit's doc/test closure). All
success criteria below are met; the full e2e suite is green in GitHub CI.

### Problem

The prior gap analysis (which drove PR #77) was satisfied — all 18 lib modules
gained per-module docs (`docs/25-40`) and tests (`tests/e2e/20-34`). This
re-audit covered the gaps that opened **after** that work: chiefly the new
`agents-a1` context-length pins (bridged in PR #78) being undocumented, plus
residual test blind spots surfaced by a fresh codebase cross-check.

Severity-ordered, evidence-backed against the code at audit time.

**Docs**

| # | Sev | Gap | Evidence |
|---|-----|-----|----------|
| D1 | P0 | `agents-a1-mtp-apex` / `agents-a1-q4` (262144) missing from `resolve_ctx_len` pin table | docs/29 table ended at `qwen3.6`; config-hermes.sh:35-36 |
| D2 | P0 | `get_limits()` entirely undocumented (no ctx table) | docs/30 documented only `normalize_model_id`/`generate_opencode_config`; config-opencode.sh:79-126 |
| D3 | P0 | `agents-a1` missing from both tables in model-discovery doc | docs/10 resolve_ctx_len (~L132) + get_limits (~L203) |
| D4 | P1 | Stale test count "~212 tests across 25 files" | docs/09:259,287 |
| D5 | P2 | Doc index skips 36 with no note | docs/README.md (35→37) |
| D6 | P3 | `service-opencode` doc omits `--hostname 0.0.0.0` | docs/34 vs service-opencode.sh:38 |
| D7 | P3 | dashboard doc implies fixed :9119 (actually `HERMES_DASHBOARD_PORT`) | docs/39 vs service-dashboard.sh:34 |
| D8 | P3 | Stale line counts (219→221, 466→471) | docs/29:5, docs/30:5 |

**Tests**

| # | Sev | Gap | Evidence |
|---|-----|-----|----------|
| T1 | P1 | `mock-llm-server.sh` / `start_mock_llm` had ZERO coverage | no .bats referenced it |
| T2 | P2 | `agents-a1` pins asserted only in file 19; canonical 26/27 omitted them; 27 never called `get_limits` | 26:AC214, 27 |
| T3 | P3 | `normalize_model_id` bare-id (credential-dependent) branch untested | 27:AC219 tested passthrough only |
| T4 | P4 | `service-dashboard.sh` had no function-level test (unlike 29/30/33) | 17-dashboard.bats is HTTP-only |
| T5 | P5 | `append_skills_external_dirs` existence-only; append + idempotence untested | 26:AC216 |

Out of scope (deferred, low value / high side-effect): thin guard-path tests on
backgrounded daemon starters (`start_gateway`, `start_opencode_serve`,
`discover_models` fallback-vs-real).

### Solution

- **Docs:** documented the agents-a1 262144 pins in `docs/10` (both tables),
  `docs/29` (`resolve_ctx_len`), and a new `get_limits()` family→(context,output)
  table in `docs/30`; fixed the `docs/09` count (now **254 tests across 37
  files**); noted the intentionally-skipped doc `36` in `docs/README.md`;
  corrected the D6/D7 accuracy nits and D8 line counts.
- **Tests (+7, AC243–AC249):** agents-a1 assertions added to `26` (`resolve_ctx_len`)
  and a `get_limits` + `normalize_model_id`-branch test to `27` so the canonical
  per-module files are self-sufficient; `append_skills_external_dirs` idempotence
  (`26`); new `35-mock-llm-server.bats` (serve + `/v1/models` + chat, port-guarded)
  and `36-service-dashboard.bats` (defined + disabled path).

### Success Criteria

- [x] SC-27-1: `grep -rl agents-a1 docs/` returns docs 10, 29, 30 (D1-D3)
- [x] SC-27-2: docs/30 has a `get_limits()` family→(context,output) table (D2)
- [x] SC-27-3: docs/09 test count matches `ls tests/e2e/*.bats | wc -l` (37) (D4)
- [x] SC-27-4: docs/README.md explains the 36 gap; D5-D8 nits corrected
- [x] SC-27-5: `start_mock_llm` exercised end-to-end — AC246/AC247 (T1)
- [x] SC-27-6: agents-a1 asserted in 26 (`resolve_ctx_len`) and 27 (`get_limits`) — AC214/AC244 (T2)
- [x] SC-27-7: `normalize_model_id` both bare-id branches asserted — AC245 (T3)
- [x] SC-27-8: `start_dashboard` unit test (defined + disabled) — AC248/AC249 (T4)
- [x] SC-27-9: `append_skills_external_dirs` append + idempotence — AC243 (T5)
- [x] SC-27-10: Full e2e bats suite green after clean rebuild (green in CI)
- [~] SC-27-11: graphify-out regen deferred to the CLI flow (manual chunking tripped graphify's node-count fidelity guard; graphify-out left at last-good state); llm wiki updated (`bats-e2e-testing`, index, log)

### Verification Policy

```bash
# Docs
grep -rl agents-a1 docs/                          # expect 10, 29, 30
grep -n "get_limits" docs/30-config-opencode.md    # expect a section
n=$(ls tests/e2e/*.bats | wc -l); grep -q "$n files" docs/09-testing-and-verification.md

# Tests — clean rebuild + full suite. Note: the browser CDP :9222 check does not
# run in the sandbox, so the health gate flaps; core services (WebUI/Gateway/
# OpenCode) come up, so run bats directly against the running container.
SKIP_CLEANUP=1 bash tests/run.sh   # or: rebuild, `up -d`, then `bats tests/e2e/`
bats tests/e2e/19-*.bats tests/e2e/26-*.bats tests/e2e/27-*.bats \
     tests/e2e/35-*.bats tests/e2e/36-*.bats   # affected + new
```

Definition of done: every success-criterion box checked and the full suite green
in CI. The 11 local failures observed during development were entirely the
pre-existing browser-CDP / health-gate cluster (no chromium in the sandbox),
unrelated to this diff — confirmed green in GitHub Actions.

## 28. Feature Parity with Downstream hermes-x-opencode--host-machine (PRs #22, #23)

## Executive Summary

This PRD documents the gap analysis and implementation plan to bring the `hermes-x-opencode` repository into feature parity with the downstream `hermes-x-opencode--host-machine` repo, specifically porting the changes from PR #22 and PR #23.

**Gap**: The current `hermes-x-opencode` repository lacks two critical features from the downstream host-machine repo:
1. **PR #22**: Inline OPENAI_API_KEY resolution at generation time
2. **PR #23**: Managed dcp.jsonc generation with per-model compression thresholds

**Impact**: Without these features, users experience authentication errors and suboptimal context compression behavior on 1M-context models.

---

## Problem Triage

### Issue 1: PR #22 - Inline OPENAI_API_KEY Resolution

**Problem Statement**: 
OpenCode does not auto-load a project `.env`. The generator hardcoded `provider.litellm`/`llama_cpp` `apiKey` to the `"{env:OPENAI_API_KEY}"` placeholder, so launching `opencode` from any shell without `OPENAI_API_KEY` exported resolved it to empty → `Authentication Error, No api key passed in.` The `auth.json` fallback does not rescue this — the config's empty `{env:}` value overrides it.

**Root Cause**: 
- The generator writes `"{env:OPENAI_API_KEY}"` as the `apiKey` in both `provider.litellm.options` and `provider.llama_cpp.options`
- When `OPENAI_API_KEY` is not exported in the current shell, the `{env:}` placeholder resolves to an empty string
- The empty string takes precedence over `auth.json` fallback credentials

**Solution**: 
Resolve the credential at generation time: when `OPENAI_API_KEY` is present in the generator's environment (`generate.sh` already sources `.env` and exports it), inline the literal key so opencode works in any shell/dir with no runtime env dependency. Fall back to the `{env:OPENAI_API_KEY}` placeholder when the key is absent, preserving the original contract.

**Files Modified**:
- `lib/config-opencode.sh` (Python block: resolve `_openai_key` and use it)
- `tests/e2e/03-config-validity.bats` (update assertion)
- `tests/e2e/23-multi-provider-model.bats` (update assertions)

---

### Issue 2: PR #23 - Managed dcp.jsonc with Per-Model Compression Thresholds

**Problem Statement**: 
OpenCode kept compressing context at ~100k tokens even on a 1M-context model (`opencode-go/deepseek-v4-pro`). Root cause: the always-installed `@tarquinen/opencode-dcp` plugin defaults `compress.maxContextLimit` to a **hard 100,000 tokens**, independent of the model's real window — so a 1M model gets compression-nudged at ~10% fill. DCP reads its own `dcp.jsonc` (not `opencode.jsonc`), so the generator never influenced it.

**Root Cause**: 
- DCP plugin has a hardcoded 100k token limit regardless of model context window
- The generator did not produce a managed `dcp.jsonc` file
- Users had no way to configure compression thresholds relative to model context size

**Solution**: 
DCP's schema accepts `"X%"` strings for `compress.maxContextLimit`/`minContextLimit` that it resolves against **each active model's real context window**. The generator now emits a managed `~/.config/opencode/dcp.jsonc` pinning those thresholds as a percentage, driven by a new `OPENCODE_COMPRESSION_THRESHOLD` env var (default `0.76`, mirroring `HERMES_COMPRESSION_THRESHOLD`). One setting adapts to every model.

**Files Modified**:
- `lib/constants.sh` (add `OPENCODE_DCP_CONFIG`, `STAGING_DCP`, `OPENCODE_COMPRESSION_THRESHOLD`)
- `lib/config-opencode.sh` (add `generate_dcp_staging()` function)
- `generate.sh` (invoke DCP generation, integrate into apply/validation loops)
- `.env.example` (document `OPENCODE_COMPRESSION_THRESHOLD`)
- `README.md` (document `OPENCODE_COMPRESSION_THRESHOLD`)
- `tests/e2e/26-dcp-config.bats` (new test file with 4 tests)

---

## Success Criteria

### PR #22 Success Criteria

**SC22.1**: After `generate.sh --apply`, the staging `opencode.jsonc` contains:
- `provider.litellm.options.apiKey` = literal `sk-...` key (not `{env:...}`)
- `provider.llama_cpp.options.apiKey` = literal `sk-...` key (not `{env:...}`)

**SC22.2**: After `generate.sh --apply` with no `OPENAI_API_KEY` in environment:
- Both keys revert to `{env:OPENAI_API_KEY}` placeholder

**SC22.3**: `opencode run` works from any shell without prior `export OPENAI_API_KEY`

**SC22.4**: All existing tests pass (117/117 green)

---

### PR #23 Success Criteria

**SC23.1**: After `generate.sh --apply`, `~/.config/opencode/dcp.jsonc` exists with:
- `compress.maxContextLimit: "76%"`
- `compress.minContextLimit: "38%"`
- `$schema` preserved

**SC23.2**: Setting `OPENCODE_COMPRESSION_THRESHOLD=0.9` produces:
- `compress.maxContextLimit: "90%"`
- `compress.minContextLimit: "45%"`

**SC23.3**: Existing `dcp.jsonc` keys are preserved (surgical merge)

**SC23.4**: Out-of-range threshold (e.g., 1.5) clamps to default 0.76

**SC23.5**: DCP respects per-model context windows (1M model compresses at 760k, not 100k)

**SC23.6**: All existing tests pass + 4 new tests green (117/117 total)

---

## Verification Policy

### Pre-Flight Checks

1. **Baseline test suite**: Run `bats tests/e2e/*.bats` and capture baseline failures
2. **Git status**: Ensure clean working tree before starting
3. **Skill verification**: Confirm `opencode-plan-build-orchestrator` and `karpathy-guidelines` are loadable

### Phase 1: Code Changes

**Verification Commands**:

```bash
# Check PR #22 changes
grep -n "OPENAI_API_KEY" volumes_hermes_opencode/build/scripts/lib/config-opencode.sh
grep -n "dcp.jsonc" volumes_hermes_opencode/build/scripts/lib/config-opencode.sh

# Check PR #23 changes
grep -n "OPENCODE_COMPRESSION_THRESHOLD" lib/constants.sh
grep -n "generate_dcp_staging" lib/config-opencode.sh

# Syntax checks
bash -n generate.sh
bash -n lib/constants.sh
bash -n lib/config-opencode.sh
```

### Phase 2: Test Suite

```bash
# Run full e2e suite
bash tests/run.sh

# Expected: 117/117 tests pass (113 existing + 4 new DCP tests)
```

### Phase 3: Functional Verification

```bash
# Test PR #22: inline key
export OPENAI_API_KEY="sk-test123"
bash generate.sh --dry-run
grep -q '"apiKey": "sk-test123"' staging/opencode.jsonc

# Test PR #23: dcp.jsonc thresholds
bash generate.sh --dry-run
python3 -c "import json; d=json.load(open('staging/dcp.jsonc')); assert d['compress']['maxContextLimit']=='76%'"
```

### Phase 4: Regression Testing

- Verify all existing tests still pass
- Check that no other functionality regressed
- Validate that `--apply` works correctly with new files

---

## Implementation Plan

### Task 1: Port PR #22 (Inline OPENAI_API_KEY)

**Files to Modify**:
1. `volumes_hermes_opencode/build/scripts/lib/config-opencode.sh` - Add `_openai_key` resolution and update provider blocks
2. `tests/e2e/03-config-validity.bats` - Update test assertions (if needed for this Docker stack)
3. `tests/e2e/23-multi-provider-model.bats` - Update test assertions (if needed for this Docker stack)

**Expected Changes**:
- +14/-6 lines in config-opencode.sh
- Test updates (if applicable)

### Task 2: Port PR #23 (DCP Config Generation)

**Files to Modify**:
1. `volumes_hermes_opencode/build/scripts/lib/constants.sh` - Add `OPENCODE_DCP_CONFIG`, `STAGING_DCP`, `OPENCODE_COMPRESSION_THRESHOLD`
2. `volumes_hermes_opencode/build/scripts/lib/config-opencode.sh` - Add `generate_dcp_staging()` function
3. `volumes_hermes_opencode/build/scripts/entrypoint.sh` - Call `generate_dcp_staging`
4. `.env.example` - Document `OPENCODE_COMPRESSION_THRESHOLD`
5. `README.md` - Document `OPENCODE_COMPRESSION_THRESHOLD`
6. `tests/e2e/37-dcp-config.bats` - Already exists, covers DCP functionality

**Expected Changes**:
- +11/-0 in constants.sh
- +106/-0 in config-opencode.sh
- +1 in entrypoint.sh
- +8/-0 in .env.example
- +1/-0 in README.md
- 37-dcp-config.bats already exists (covers DCP tests)

**Note**: This Docker stack repo does NOT have a standalone `generate.sh` file. Config generation is integrated into the container entrypoint script (`entrypoint.sh`). The downstream host-machine repo has a separate `generate.sh`, but the changes are ported to the embedded scripts in this Docker stack.

---

## Risk Assessment

**High Risk**:
- Modifying `config-opencode.sh` affects both OpenCode and Hermes config generation
- DCP integration may impact existing `opencode.jsonc` structure

**Mitigation**:
- Use surgical patches, not full rewrites
- Run full test suite after each change
- Keep changes minimal and focused

**Testing Strategy**:
- Run existing tests before and after each modification
- Add new tests to guard against regressions
- Verify with dry-run before actual apply

---

## Appendix: Reference Diff Sources

- PR #22: https://github.com/bachkukkik/hermes-x-opencode--host-machine/pull/22
- PR #23: https://github.com/bachkukkik/hermes-x-opencode--host-machine/pull/23

**Downstream Commit SHAs**:
- PR #22: `4a1bf2f`
- PR #23: `bf952f5`

---

**Status**: Ready for Implementation
**Priority**: High (affects user experience and functionality)
**Estimate**: 2-4 hours for full porting and verification
