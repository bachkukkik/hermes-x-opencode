# Hermes x OpenCode

A Docker Compose stack that connects [Hermes Agent](https://github.com/nousresearch/hermes-agent) + [Hermes WebUI](https://github.com/nicholasgriffintn/hermes-webui) + [OpenCode CLI](https://opencode.ai) into a fully integrated AI coding orchestrator.

Three services exposed:

| Service | Port | Purpose |
|---------|------|---------|
| Hermes WebUI | :8787 | Browser-based chat interface |
| Hermes Agent API | :8642 | OpenAI-compatible endpoint (`/v1/chat/completions`) |
| OpenCode Serve | :4096 | Headless server for remote `opencode attach` |

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│  Container: hermes-opencode                                          │
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
│  │   --accept-hooks)        │  Compatible with Open WebUI, LobeChat, │
│  │    /v1/chat/completions  │  LibreChat, AnythingLLM, NextChat, etc.│
│  │    /v1/models            │                                        │
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
│      config.yaml, state.db, skills/, logs/, webui/                   │
│                                                                      │
│  External:                                                           │
│    LLM Provider (OpenAI-compatible endpoint via OPENAI_BASE_URL)     │
│    OpenCode auth (OPENCODE_API_KEY)                                  │
└──────────────────────────────────────────────────────────────────────┘
```

## Quick Start

### 1. Clone this repo

```bash
git clone https://github.com/bachkukkik/hermes-x-opencode.git
cd hermes-x-opencode
```

### 2. Configure environment

```bash
cp .env.example .env
```

Edit `.env` and fill in your API keys:

```env
# Required: API key for your LLM provider
OPENAI_API_KEY=sk-your-key-here

# Required: OpenAI-compatible base URL
OPENAI_BASE_URL=https://openrouter.ai/api/v1

# Required: Default model (other chat models are auto-discovered)
OPENAI_DEFAULT_MODEL=openai/gpt-4o

# Required: OpenCode API key (get from https://opencode.ai)
OPENCODE_API_KEY=your-opencode-key-here
```

### 3. Build and start

```bash
docker compose up -d --build
```

First build clones hermes-agent and installs OpenCode + Node.js 22. First startup installs Python dependencies, discovers models from your provider, installs skills, and starts all three services (~80-160s). Subsequent starts are faster (~25-50s).

### 4. Use it

- **WebUI:** http://localhost:8787
- **Agent API:** http://localhost:8642/v1/chat/completions
- **OpenCode attach:** `opencode attach http://localhost:4096`

## Service Details

### Hermes WebUI (:8787)

Browser-based chat interface. The agent has access to `opencode` via the terminal tool.

Start chatting and ask Hermes to delegate coding work:

```
"Use opencode to build me a Python CLI tool that converts CSV to JSON"
```

### Hermes Agent API (:8642)

OpenAI-compatible endpoint. Connect any OpenAI-compatible client:

```bash
# List models
curl http://localhost:8642/v1/models

# Chat completion (streaming)
curl -N http://localhost:8642/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "hermes-agent",
    "messages": [{"role": "user", "content": "Hello"}],
    "stream": true
  }'

# Chat completion (non-streaming)
curl http://localhost:8642/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "hermes-agent",
    "messages": [{"role": "user", "content": "What is 2+2?"}]
  }'
```

**With auth** (if `HERMES_API_KEY` is set, or check auto-generated key):

```bash
# Get auto-generated key from logs
API_KEY=$(docker logs $(docker compose ps -q hermes-opencode) 2>&1 | grep "Generated random HERMES_API_KEY" | sed 's/.*: //')

curl http://localhost:8642/v1/chat/completions \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "hermes-agent", "messages": [{"role": "user", "content": "Hello"}]}'
```

**Connect external UIs** by pointing them at `http://<host>:8642/v1` with model name `hermes-agent`. Compatible with Open WebUI, LobeChat, LibreChat, AnythingLLM, NextChat, ChatBox, etc.

**Session continuity:** Pass `X-Hermes-Session-Id` header to continue an existing conversation.

### OpenCode Serve (:4096)

Headless OpenCode server. Attach from another machine:

```bash
# From any machine on the network
opencode attach http://<host-ip>:4096

# One-shot prompt
opencode run --attach http://<host-ip>:4096 "What does this project do?"
```

## Usage Patterns

### Pattern 1: Direct Coding via OpenCode

```
"Use opencode to build me a Python CLI tool that converts CSV to JSON"
```

Hermes will:
1. Run `opencode run --agent plan --title "Plan: CSV to JSON" "<prompt>"`
2. Review the plan output
3. Run `opencode run --agent build -s <session_id> "Implement the plan"`
4. Verify and report results

### Pattern 2: Plan -> Build Pipeline

```
"First plan, then build: add user authentication to my Express app"
```

This uses the two-phase OpenCode flow:
- **Plan agent**: reads codebase, designs approach (read-only, no files written)
- **Build agent**: picks up the plan, implements it, runs tests

### Pattern 3: Via Agent API

Point any OpenAI-compatible client at `:8642/v1` and use model `hermes-agent`. The agent runs server-side with full tool access.

### When to Use What

| Scenario | Service | Why |
|----------|---------|-----|
| Browser-based chat | WebUI :8787 | Full UI with sessions, file browser |
| Connect external chat UI | Agent API :8642 | OpenAI-compatible, streaming |
| Remote coding session | OpenCode :4096 | Attach from another machine |
| CI/CD integration | Agent API :8642 | Programmatic access |
| Code implementation | opencode run | Built for code, plan->build flow |

## Configuration

### Environment Variables

All configuration is done through the `.env` file. See `.env.example` for the full list.

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `OPENAI_API_KEY` | Yes | — | API key for the LLM provider |
| `OPENAI_BASE_URL` | Yes | — | OpenAI-compatible base URL |
| `OPENAI_DEFAULT_MODEL` | No | `openai/gpt-4o` | Default model (others auto-discovered) |
| `OPENCODE_API_KEY` | Yes | — | API key for OpenCode CLI |
| `HERMES_WEBUI_PASSWORD` | No | empty | Password-protect the WebUI |
| `HERMES_WEBUI_PORT` | No | `8787` | Host port for WebUI |
| `HERMES_API_KEY` | No | auto-generated | Bearer token for Agent API |
| `HERMES_API_PORT` | No | `8642` | Host port for Agent API |
| `OPENCODE_SECURITY_MODE` | No | `strict` | Security profile: strict/standard/yolo |
| `OPENCODE_SERVE_PORT` | No | `4096` | Host port for OpenCode serve |
| `SKIP_SKILL_INSTALL` | No | `0` | Skip skill installation (set `1`) |
| `HOST_UID` / `HOST_GID` | No | `1000` | File permission UID/GID |

### Model Discovery

When `OPENAI_BASE_URL` and `OPENAI_API_KEY` are set, the entrypoint automatically discovers all available chat models from your LLM provider at startup. Non-chat models (embeddings, TTS, image generation) and wildcard patterns are filtered out. Both the Hermes config and OpenCode config receive the same model list.

`OPENAI_DEFAULT_MODEL` specifies the default model. If it's not found in the discovered list, it's added automatically. No manual model configuration needed.

### Security Modes

The `OPENCODE_SECURITY_MODE` variable controls the OpenCode agent's permission profile:

| Mode | Bash rules | Interpreters | .env access | Use case |
|------|-----------|-------------|-------------|----------|
| `strict` (default) | 31 deny rules | Blocked | Blocked | Production |
| `standard` | 22 deny rules | Allowed | Blocked | Development |
| `yolo` | Allow all | Allowed | Allowed | Trusted sandbox |

All modes include the cc-safety-net plugin which blocks destructive git and filesystem commands.

### Agent Version

The hermes-agent version is set at build time:

```bash
# Default (main branch)
docker compose up -d --build

# Specific version
docker compose build --build-arg HERMES_AGENT_VERSION=v1.2.3
docker compose up -d
```

### OpenCode Auth

Set `OPENCODE_API_KEY` in `.env`. The key is passed through as an environment variable to the container.

### Persistent Data

Data is stored in bind mounts under `volumes_hermes_opencode/data/`:

| Host path | Container path | Contents |
|-----------|---------------|----------|
| `data/hermes-home/` | `/home/hermeswebui/.hermes` | config.yaml, state.db, skills/, logs/, webui/, hermes-agent/ |
| `data/workspace/` | `/workspace` | User project workspace |

This data survives container restarts and rebuilds.

## Troubleshooting

### "Your request was blocked" (Cloudflare 403)

If your LLM provider is behind Cloudflare (e.g., a LiteLLM proxy), the OpenAI Python SDK's default User-Agent gets blocked. This stack patches the hermes-agent CustomProfile at build time to send `User-Agent: hermes-agent/1.0` instead. No manual fix needed.

If you still see 403s, verify the patch is applied:
```bash
docker exec $(docker compose ps -q hermes-opencode) grep "User-Agent" /home/hermeswebui/.hermes/hermes-agent/plugins/model-providers/custom/__init__.py
```

### Gateway not starting on :8642

The gateway starts after the WebUI is healthy. Check logs:
```bash
docker logs $(docker compose ps -q hermes-opencode) 2>&1 | grep -i gateway
```

Verify config.yaml has the api_server platform:
```bash
docker exec $(docker compose ps -q hermes-opencode) cat /home/hermeswebui/.hermes/config.yaml
```

### OpenCode serve not responding on :4096

OpenCode serve starts after the gateway. Check:
```bash
docker logs $(docker compose ps -q hermes-opencode) 2>&1 | grep -i "opencode serve"
docker exec $(docker compose ps -q hermes-opencode) opencode --version
```

### Session not connecting

The WebUI and agent share state via the bind mount. If sessions don't appear:
```bash
docker exec $(docker compose ps -q hermes-opencode) ls -la /home/hermeswebui/.hermes/
```

### config.yaml has expanded API key instead of literal string

The `key_env` field must contain the literal string `OPENAI_API_KEY`, not the actual key value. Verify:
```bash
docker exec $(docker compose ps -q hermes-opencode) cat /home/hermeswebui/.hermes/config.yaml
```

## Files

```
.
├── docker-compose.yml              # Service: 3 ports, bind mounts, env, healthcheck
├── .env.example                    # All supported env vars
├── .gitignore
├── PRD.md                          # Engineer handoff document
├── README.md                       # This file
├── docs/                           # Architecture documentation (01–13)
└── volumes_hermes_opencode/
    ├── build/
    │   ├── Dockerfile              # Multi-step build: base + node + opencode + agent + patch
    │   └── scripts/
    │       ├── entrypoint.sh       # Model discovery, config gen, start 3 services
    │       └── install-skills.sh   # Skills from 6 upstream sources
    └── data/
        ├── hermes-home/.gitkeep    # Bind mount target (agent config, sessions)
        └── workspace/.gitkeep      # Bind mount target (user workspace)
```

## Credits

- [Hermes Agent](https://github.com/nousresearch/hermes-agent) by Nous Research
- [Hermes WebUI](https://github.com/nicholasgriffintn/hermes-webui) by Nicholas Griffin
- [OpenCode](https://opencode.ai) by the OpenCode team

## License

MIT
