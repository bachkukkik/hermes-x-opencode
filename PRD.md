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
│    OpenCode Zen auth (OPENCODE_API_KEY) — optional                   │
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
| `validate_opencode_zen_key()` | `lib/validate-opencode.sh` | Validates `OPENCODE_API_KEY` against the Zen API models endpoint if set. Non-fatal warning on failure (fix #30). |
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
8. `validate_opencode_zen_key()` — validate OPENCODE_API_KEY if set; warn on failure (fix #30)
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
| `OPENCODE_API_KEY` | No | API key for OpenCode Zen models. Required only for opencode/ built-in models; leave empty if using your own LLM provider. |
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
 6. Validate OPENCODE_API_KEY if set — warn on failure (fix #30)
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
 4. Validate OPENCODE_API_KEY if set (fix #30)
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
| `OPENCODE_API_KEY` | string | No | — | API key for OpenCode Zen models. Required only for opencode/ built-in models (sign up at https://opencode.ai/auth). If you only use models from your own LLM provider (via `OPENAI_BASE_URL`), leave this empty. Validated at startup with a warning on failure. |
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

**OpenCode provider block (companion fix).** When `OPENCODE_API_KEY` is set, an explicit `opencode` provider entry is generated in `opencode.jsonc` with `apiKey: {env:OPENCODE_API_KEY}`. This ensures built-in `opencode/` models (like `deepseek-v4-flash-free`) have proper authentication mapping. Additionally, `auth.json` is seeded as a fallback credential store, and `OPENCODE_API_KEY` is explicitly passed through `su` in `service-opencode.sh`.

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
