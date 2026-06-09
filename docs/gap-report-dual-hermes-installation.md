# Gap Report: Dual Hermes Installation Investigation

**Date:** 2025-06-09
**Scope:** Is there a DOUBLE Hermes agent installation inside the Docker container? If so, should they be unified?
**Status:** CORRECTED -- initial "dead code" finding was wrong (verified in running container).

---

## 1. Inventory of All Hermes Installation Points

### Installation A -- Base Image Venv (ACTIVE at runtime)

| Property | Detail |
|----------|--------|
| **WHERE** | `/app/venv/bin/hermes` (CLI binary) + `/app/venv/lib/python3.12/site-packages/` (agent code) |
| **WHAT** | The actual agent code that runs at runtime. Both WebUI (in-process `AIAgent`) and gateway (`/app/venv/bin/hermes gateway run --accept-hooks`) use this single venv. |
| **HOW** | Pre-bundled in base image `ghcr.io/nesquena/hermes-webui:latest`. At boot, `/hermeswebui_init.bash` runs `uv pip install "$_stage_src[all]"` from a staged copy of the agent source, installing hermes-agent deps into this venv. |
| **WHICH runtime** | BOTH the WebUI and gateway. The WebUI imports `from run_agent import AIAgent` from this venv. The gateway runs `/app/venv/bin/hermes` from this venv. |

### Installation B -- Staged Clone (PASSIVE staging)

| Property | Detail |
|----------|--------|
| **WHERE (build-time)** | `/opt/hermes-agent-staging/` (git clone during `docker build`) |
| **WHERE (runtime)** | `/home/hermeswebui/.hermes/hermes-agent/` (copied from staging on first boot via `ensure_agent()`) |
| **WHAT** | Full git clone of `https://github.com/NousResearch/hermes-agent.git` (branch: `$HERMES_AGENT_VERSION`, default `main`). Contains `pyproject.toml`, `skills/`, `plugins/`, and full agent source. |
| **HOW** | `git clone --depth 1 --branch ${HERMES_AGENT_VERSION}` in Dockerfile RUN step. Modified with a `sed` patch to add User-Agent header. Copied to bind mount at first boot by `ensure_agent()`. |
| **WHICH runtime** | **Not directly executed.** Serves three roles: (1) Skills source for `install-skills.sh` (llm-wiki extracted during build), (2) Deps source for `/hermeswebui_init.bash` which rsyncs to `/tmp/hermes-agent-build/` and does `uv pip install` from there, (3) Readiness marker (`pyproject.toml` existence check). |

### Installation C -- Config + Skills (Runtime State)

| Property | Detail |
|----------|--------|
| **WHERE** | `/home/hermeswebui/.hermes/` (config.yaml, skills/, wiki/, logs/, webui/) |
| **WHAT** | Runtime configuration and skills. Not agent code -- just YAML configs, skill markdown files, wiki data, and logs. |
| **HOW** | Generated at boot by `entrypoint.sh` → `generate_config()`, `install-skills.sh` (build-time staging to `/opt/hermes-skills-staging/`), runtime copy from staging. |
| **WHICH runtime** | Read by both the WebUI (`config.yaml` via `api/config.py`) and the gateway (`config.yaml` via `gateway/run.py`). |

---

## 2. Active Runtime Code Paths

### Path 1: WebUI Chat (Port 8787)

```
Browser → POST /api/chat/start → WebUI HTTP server (Python ThreadingHTTPServer)
→ from run_agent import AIAgent (from /app/venv site-packages)
→ AIAgent.run_conversation() in daemon thread
→ Reads config from /home/hermeswebui/.hermes/config.yaml
→ Code source: Installation A (base image venv)
```

### Path 2: Gateway API (Port 8642)

```
External client → POST /v1/chat/completions → aiohttp server
→ /app/venv/bin/hermes gateway run --accept-hooks
→ Reads config from /home/hermeswebui/.hermes/config.yaml (via HERMES_HOME)
→ Code source: Installation A (same venv, same binary)
```

### Path 3: Staged Agent → Deps Pipeline (Installation B)

```
/opt/hermes-agent-staging/ (build-time git clone with sed patch)
  ↓ ensure_agent() on first boot
/home/hermeswebui/.hermes/hermes-agent/ (runtime copy on bind mount)
  ↓ /hermeswebui_init.bash searches _agent_paths:
  ↓   [0] = /home/hermeswebui/.hermes/hermes-agent
  ↓   [1] = /opt/hermes
  ↓ rsyncs to /tmp/hermes-agent-build/
  ↓ uv pip install "$_stage_src[all]" into /app/venv/
/app/venv/lib/.../ (active agent code WITH the User-Agent patch)
```

**Key:** The patch propagation chain works correctly. The sed patch on the staged clone flows through `ensure_agent()` → rsync → `uv pip install` → the active venv.

---

## 3. Duplication Assessment

### What IS duplicated

| Artifact | Location A | Location B | Size Impact |
|----------|-----------|-----------|-------------|
| Agent Python source | `/app/venv/lib/.../` (pip-installed) | `/opt/hermes-agent-staging/` + `~/.hermes/hermes-agent/` (git clone) | ~50-100MB in staging + ~100MB on bind mount |
| Skills from upstream | `~/.hermes/skills/` (install-skills.sh target) | `~/.hermes/hermes-agent/skills/` (bundled in git clone) | ~200MB of creative/inference templates duplicated |

### What is NOT duplicated

- **Config**: Single `config.yaml` serves both WebUI and gateway
- **Skills installation**: Intentional split between OpenCode and Hermes targets
- **Runtime**: Single venv, single code path

### Why the duplication exists

1. `/opt/hermes-agent-staging/` -- needed because `/hermeswebui_init.bash` installs deps from it via `uv pip install`
2. `~/.hermes/hermes-agent/` -- needed because `/hermeswebui_init.bash` looks for the agent source at this path first (before `/opt/hermes`)
3. Both copies carry the sed User-Agent patch which propagates to the active venv

---

## 4. Recommendations

### Option A: Keep Current Architecture (RECOMMENDED)

The current architecture is sound. The dual installation serves a clear purpose:
- Installation B is a staging area that feeds deps into Installation A
- The patch propagation chain works correctly (verified)
- The WebUI's init script expects the agent source at `~/.hermes/hermes-agent/`

**Remaining improvements (non-breaking):**

1. **Trim the git clone** -- exclude `skills/`, `docs/`, `tests/`, `.github/` from the clone since only `pyproject.toml`, `plugins/`, and agent source are needed for deps. This saves ~200MB.
2. **Add Dockerfile comments** explaining the dual installation architecture
3. **Document in PRD** -- add a section explaining Installation A vs B roles

### Option B: Unify (NOT RECOMMENDED)

Would require deep changes to the base image's `/hermeswebui_init.bash` script (which we don't control). High risk of breaking the WebUI's in-process agent.

### Option C: Eliminate Staged Agent (NOT RECOMMENDED)

Would lose: (1) deps source for `/hermeswebui_init.bash`, (2) skills source for `install-skills.sh`, (3) the User-Agent patch mechanism.

---

## 5. Proposed PRD Updates

Add to PRD Section 2 (Architecture) a subsection "Agent Installation Architecture" documenting:
- Installation A (base image venv): active runtime for WebUI + gateway
- Installation B (staged clone): passive deps/skills source, feeds into A via pip install
- The propagation chain for the User-Agent patch
- Why both installations exist and must be kept

Add a new constraint C10: "The staged agent clone at `/opt/hermes-agent-staging/` must be trimmed to exclude non-essential directories (skills/, docs/, tests/, .github/) to reduce image size."

---

## 6. Specific Files/Paths to Change

| File | Change | Priority |
|------|--------|----------|
| `PRD.md` Section 2 | Add "Agent Installation Architecture" subsection | HIGH |
| `PRD.md` Section 8 | Add constraint C10 about trimming the clone | MEDIUM |
| `Dockerfile` lines 36-38 | Add `--sparse` or `--filter=blob:none` to git clone; add exclusion comments | MEDIUM |
| `Dockerfile` after line 38 | Add `RUN rm -rf /opt/hermes-agent-staging/skills /opt/hermes-agent-staging/docs /opt/hermes-agent-staging/tests` | MEDIUM |
| `docs/` | New doc `16-agent-installation-architecture.md` | LOW |
| `agent-setup.sh` | Add comment explaining the staging → runtime → venv pipeline | LOW |

---

## 7. Verified Facts (from running container)

```
# All three locations have the User-Agent patch (line 66):
$ docker exec $CID grep -n 'User-Agent' /opt/hermes-agent-staging/plugins/model-providers/custom/__init__.py
66:    default_headers={"User-Agent": "hermes-agent/1.0"},  # User-configured

$ docker exec $CID find /app/venv/lib/ -path '*/plugins/model-providers/custom/__init__.py' -exec grep -n 'User-Agent' {} +
66:    default_headers={"User-Agent": "hermes-agent/1.0"},  # User-configured

$ docker exec $CID grep -n 'User-Agent' /home/hermeswebui/.hermes/hermes-agent/plugins/model-providers/custom/__init__.py
66:    default_headers={"User-Agent": "hermes-agent/1.0"},  # User-configured
```

The patch propagation chain: Dockerfile sed → staging → ensure_agent() → ~/.hermes/hermes-agent/ → /hermeswebui_init.bash rsync → /tmp/hermes-agent-build/ → uv pip install → /app/venv/. **Patch IS effective.**
