# Hermes x OpenCode Docker Stack — Agent Instructions

This repo builds a Docker Compose stack running Hermes WebUI + Hermes Agent + OpenCode CLI in a single container.

## Architecture

```
Container: hermes-opencode
├── Hermes WebUI    :8787  (browser chat UI, hosts AIAgent in-process)
├── Hermes Gateway  :8642  (OpenAI-compatible API /v1/chat/completions)
├── OpenCode Serve  :4096  (headless server for remote attach)
└── Shared bind mount: /home/hermeswebui/.hermes/
```

See `PRD.md` for full specifications. See `docs/` for architecture deep-dives.

---

## Standing Orders (ALWAYS apply)

These rules apply to **every session, every agent, every prompt** — no exceptions.

### 1. MANDATED SKILLS

Load and use these skills on EVERY task:

| Skill | When | Purpose |
|-------|------|---------|
| `karpathy-guidelines` | ALWAYS | Research context, knowledge base patterns, clean code |
| `security-best-practices` | ALWAYS | All code changes must follow security best practices |
| `webapp-testing` | Testing | Write and run comprehensive tests |
| `coding-agents-docs-guideline` | Docs | Document all changes in the repo |
| `yeet` | Git ops | All commit/push/branch operations |

### 2. Code Quality Rules

- **No `shell=True`** in subprocess calls
- **No hardcoded secrets** — use env vars or `key_env` references
- **No wildcard patterns (`/*`)** in model config — filter them during discovery
- **Both `model.default` AND `model.name`** must be written to config.yaml
- **CustomProfile must have `User-Agent: hermes-agent/1.0`** header — verify after any agent update
- **Agent source goes to staging path** (`/opt/hermes-agent-staging`), not runtime path

### 3. Docker/Build Constraints

- Target platform: **Linux ARM64** (Raspberry Pi)
- **No interactive setup** — everything must be unattended from `docker compose up -d`
- **No secrets in tracked files** — repo is public
- `config.yaml` and `opencode.jsonc` are regenerated every boot — manual edits are lost
- OpenCode skills are ephemeral (no volume mount) — reinstalled every boot
- Hermes skills persist in the bind mount
- **`host.docker.internal`** resolves inside the container via `extra_hosts` in `docker-compose.yml` (maps to `host-gateway`) — fixes DNS resolution on bare Linux hosts (#27, #31)

### 4. File Locations (inside container)

| Path | Purpose |
|------|---------|
| `/home/hermeswebui/.hermes/config.yaml` | Agent config (generated) |
| `/home/hermeswebui/.hermes/hermes-agent/` | Agent runtime staging (bind mount). Copied from /opt/hermes-agent-staging/ on first boot. Provides pyproject.toml readiness marker and deps source for /hermeswebui_init.bash. Active code is pip-installed at /app/venv/. |
| `/home/hermeswebui/.hermes/state.db` | Session history (SQLite) |
| `/home/hermeswebui/.config/opencode/opencode.jsonc` | OpenCode config (generated, copied to root) |
| `/root/.config/opencode/opencode.jsonc` | Root's OpenCode config (copy of hermeswebui's, fix #28) |
| `/root/.local/share/opencode/` | Symlink → hermeswebui's data dir (shared session DB, fix #29) |
| `/home/hermeswebui/.config/opencode/skills/` | OpenCode skills (ephemeral) |
| `/opt/hermes-agent-staging/` | Agent source staging (build-time). NOT the active runtime — provides deps for /hermeswebui_init.bash and skills for install-skills.sh. Active code is at /app/venv/. |
| `/workspace/` | User project workspace (bind mount) |

### 5. Security Modes

| Mode | Bash Rules | Interpreters | .env | Use Case |
|------|-----------|-------------|------|----------|
| `strict` (default) | 31 | DENIED | DENIED | Production |
| `standard` | 22 | ALLOWED | DENIED | Development |
| `yolo` | 0 (allow all) | ALLOWED | ALLOWED | Trusted sandbox |

### 6. Verification Commands

After any change to build/entrypoint/config:

```bash
# Build and start
docker compose build && docker compose up -d

# Check health
docker compose ps
curl -f http://localhost:8787/health
curl -f http://localhost:8642/health

# Check agent source + patch
docker exec $(docker compose ps -q hermes-opencode) test -f /home/hermeswebui/.hermes/hermes-agent/pyproject.toml
docker exec $(docker compose ps -q hermes-opencode) grep -q '"User-Agent".*"hermes-agent' /home/hermeswebui/.hermes/hermes-agent/plugins/model-providers/custom/__init__.py

# Check OpenCode
docker exec $(docker compose ps -q hermes-opencode) opencode --version

# Check config validity
docker exec $(docker compose ps -q hermes-opencode) python3 -m json.tool /home/hermeswebui/.config/opencode/opencode.jsonc
```

### 7. Project-Specific Patterns

- **Bash heredoc JSON breaks with 300+ dynamic entries** — use `python3 -c "import json; json.dump(...)"` for config generation
- **Docker overlayfs on ARM64 may drop new layers** — modifications to existing files survive, new files may vanish. Use inline `command:` in docker-compose as workaround
- **Agent installation is dual but NOT parallel**: The base image venv (`/app/venv/`) provides the active runtime for both WebUI and gateway. The staged clone (`/opt/hermes-agent-staging/` → `~/.hermes/hermes-agent/`) is a deps pipeline that feeds `uv pip install` into the venv. The User-Agent sed patch propagates through: staging → ensure_agent() → rsync → uv pip install → /app/venv/.
- **Cloudflare blocks OpenAI SDK default User-Agent** — the CustomProfile patch (`hermes-agent/1.0`) is critical for LLM calls to work
- **Model discovery filters**: exclude embed, whisper, tts, dall-e, sora, image, realtime, transcrib, moderat, audio, codegen, babbage, davinci, curie, ada, text-, stable, midjourney, flux, /sd/, mj, replicate, resolution, and wildcard patterns ending with `/*`
- **Per-model provider routing** (issue #46): `_resolve_provider_prefix()` in `config-opencode.sh` determines `opencode/` vs `litellm/` prefix independently per model based on the raw model name and available credentials. Supports hybrid deployments where `model` routes through LiteLLM and `small_model` routes through Zen (or vice versa).
- **OpenCode provider block** (issue #46): When `OPENCODE_API_KEY` is set, an explicit `opencode` provider entry with `apiKey: {env:OPENCODE_API_KEY}` is generated in `opencode.jsonc`. Also seeds `auth.json` as fallback credential store and passes `OPENCODE_API_KEY` explicitly through `su` in `service-opencode.sh`. Required for built-in `opencode/` models (e.g. `deepseek-v4-flash-free`) to authenticate.
- **Mock LLM server for CI**: `tests/mock-llm-server.sh` provides a Python stdlib HTTP server on port 4000 for secretless CI. Started conditionally when `OPENAI_BASE_URL=http://localhost:4000`.

### 8. Agent Capabilities

| Capability | Details |
|------------|---------|
| **graphify** | Installed as a Hermes skill at build time. Run `/graphify` to build a knowledge graph from repo contents. Tested in `test/08-graphify.bats`. |
| **browser human-loop** | Chromium CDP available for agent-browser cooperation when `BROWSER_HUMAN_LOOP_ENABLED=true`. DISPLAY=`:1` Xvfb session with VNC access. Ports: 6901 (noVNC web), 5901 (raw VNC), 9222 (Chromium DevTools Protocol). |
| **security modes** | `strict` (default, 31 bash rules — no interpreters, no env dump), `standard` (22 rules — interpreters allowed), `yolo` (unrestricted). Set via `OPENCODE_SECURITY_MODE`. See section 5 for full matrix. |
| **llm-wiki** | Personal knowledge base at `/home/hermeswebui/.hermes/wiki`. Auto-initialized on first boot with SCHEMA.md, index.md, log.md backbone. Agent ingests sources into `raw/articles/` and creates entity/concept pages with `[[wikilinks]]`. Persists on the hermes-home bind mount. Optional host sharing via `HERMES_WIKI_VOLUME` env var. |
