# 16 — Agent Installation Architecture

## What

The container holds two distinct installations of the Hermes Agent: one is the active runtime used by all services; the other is a passive staging clone that feeds dependencies and patches into the active runtime at boot. This doc explains what each installation contains, how they interact, and why both must exist.

## Why

- The active runtime (Installation A) is the only code that executes — it serves both the WebUI chat and the gateway API
- The staging clone (Installation B) is required because the WebUI's init script installs agent dependencies from a local source tree via `uv pip install`, not from PyPI
- Both installations carry the same User-Agent patch, which propagates from the staging clone through a multi-step pipeline into the active venv

## Overview

```
┌─────────────────────────────────────────────────────────┐
│  Container                                               │
│                                                          │
│  ┌─── Installation A (ACTIVE RUNTIME) ────────────────┐  │
│  │  /app/venv/                                        │  │
│  │    bin/hermes          ← CLI binary                │  │
│  │    lib/.../site-packages/  ← agent code (installed)│  │
│  │                                                    │  │
│  │  Used by: WebUI (in-process AIAgent)               │  │
│  │           Gateway (hermes gateway run)              │  │
│  └────────────────────────────────────────────────────┘  │
│                         ▲                                │
│                         │ uv pip install from staged src │
│                         │                                │
│  ┌─── Installation B (STAGING PIPELINE) ──────────────┐  │
│  │  Build-time: /opt/hermes-agent-staging/             │  │
│  │    (git clone + sed patch in Dockerfile)            │  │
│  │                                                    │  │
│  │  Runtime: ~/.hermes/hermes-agent/                   │  │
│  │    (copied by ensure_agent() on first boot)         │  │
│  │                                                    │  │
│  │  Used by: /hermeswebui_init.bash (deps source)     │  │
│  │           install-skills.sh (skills source)         │  │
│  │           Readiness marker (pyproject.toml check)   │  │
│  └────────────────────────────────────────────────────┘  │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

**There is one active runtime.** Installation B never executes agent code directly. It exists solely as a source tree for dependency installation and patch propagation.

## Installation A — Base Image Venv (Active Runtime)

| Property | Detail |
|----------|--------|
| **Location** | `/app/venv/bin/hermes` (CLI binary) + `/app/venv/lib/python3.12/site-packages/` (agent code) |
| **Origin** | Pre-bundled in the base image `ghcr.io/nesquena/hermes-webui:latest` |
| **Populated by** | `/hermeswebui_init.bash` runs `uv pip install "$_stage_src[all]"` from the staged copy at boot |
| **Used by** | WebUI (`from run_agent import AIAgent` in-process) and Gateway (`/app/venv/bin/hermes gateway run --accept-hooks`) |
| **Config** | Reads `/home/hermeswebui/.hermes/config.yaml` via `HERMES_HOME` |

Both chat paths use the same venv and the same code:

```
Path 1 — WebUI Chat (port 8787):
  Browser → POST /api/chat/start → AIAgent (from /app/venv site-packages)
  → Reads config from ~/.hermes/config.yaml

Path 2 — Gateway API (port 8642):
  External client → POST /v1/chat/completions → /app/venv/bin/hermes gateway run
  → Reads config from ~/.hermes/config.yaml
```

## Installation B — Staged Clone (Deps Pipeline)

| Property | Detail |
|----------|--------|
| **Build-time location** | `/opt/hermes-agent-staging/` (git clone during `docker build`) |
| **Runtime location** | `/home/hermeswebui/.hermes/hermes-agent/` (copied from staging on first boot) |
| **Origin** | `git clone --depth 1 --branch ${HERMES_AGENT_VERSION}` of `https://github.com/NousResearch/hermes-agent.git` |
| **Patch** | `sed` in Dockerfile adds User-Agent header to the custom model provider plugin |
| **Used by** | `/hermeswebui_init.bash` (deps source), `install-skills.sh` (skills source), readiness check (`pyproject.toml` existence) |

Installation B serves exactly three roles:

1. **Deps source for `/hermeswebui_init.bash`** — The init script searches `_agent_paths` (first `~/.hermes/hermes-agent`, then `/opt/hermes`), rsyncs the found source to `/tmp/hermes-agent-build/`, and runs `uv pip install` from there into `/app/venv/`
2. **Skills source for `install-skills.sh`** — Build-time extraction of bundled skills (e.g. llm-wiki)
3. **Readiness marker** — The existence of `pyproject.toml` signals that the agent is present

### Propagation Chain

The User-Agent patch flows from build time to the active runtime through a multi-step chain:

```
Dockerfile: sed patch applied to /opt/hermes-agent-staging/plugins/model-providers/custom/__init__.py
  │
  ▼  ensure_agent() on first boot
/home/hermeswebui/.hermes/hermes-agent/  (runtime copy on bind mount)
  │
  ▼  /hermeswebui_init.bash searches _agent_paths
  │     [0] = /home/hermeswebui/.hermes/hermes-agent
  │     [1] = /opt/hermes
  ▼  rsync to /tmp/hermes-agent-build/
  │
  ▼  uv pip install "$_stage_src[all]" into /app/venv/
  │
  ▼
/app/venv/lib/.../site-packages/  (active agent code WITH the User-Agent patch)
```

This chain has been verified in running containers: the User-Agent header appears on line 66 of the installed plugin at every stage.

## Comparison Table

| Aspect | Installation A (Active Runtime) | Installation B (Staged Clone) |
|--------|--------------------------------|------------------------------|
| **Location** | `/app/venv/` | `/opt/hermes-agent-staging/` + `~/.hermes/hermes-agent/` |
| **Form** | pip-installed package in venv | git clone (source tree) |
| **Executes** | Yes — all agent code runs from here | No — never imported or executed directly |
| **Created by** | Base image + `uv pip install` at boot | `git clone` in Dockerfile + `ensure_agent()` at first boot |
| **Patched** | Receives patch via pip install from B | Patched by `sed` in Dockerfile |
| **Size** | ~100 MB (installed Python packages) | ~50–100 MB (staging) + ~100 MB (runtime copy on bind mount) |
| **Required for** | WebUI chat, Gateway API | Boot-time deps install, skills extraction, readiness check |
| **User-modifiable** | No (regenerated from B on each boot) | No (regenerated from git clone on rebuild) |

## Why Both Exist

The dual installation is a consequence of the WebUI's dependency management design:

1. **The base image ships a venv but not full agent deps** — The WebUI's init script (`/hermeswebui_init.bash`) expects to find the agent source tree locally and install deps from it using `uv pip install`. It does not install from PyPI.

2. **Patches must flow through the source tree** — The User-Agent header is added by `sed` to the staged clone during the Docker build. The only way this patch reaches the active venv is through the `uv pip install` step that reads from the staged source.

3. **The bind mount demands a runtime copy** — The agent source must exist under `/home/hermeswebui/.hermes/hermes-agent/` (on the persistent bind mount) because the init script looks there first. The `ensure_agent()` function copies from the image's staging path to this location on first boot.

Unifying or eliminating either installation would require deep changes to the base image's init script, which is not under our control.

## Image Bloat Mitigation

The staged clone includes directories that are not needed for dependency installation: `skills/`, `docs/`, `tests/`, `.github/`. These add approximately 200 MB to the image.

**Recommended mitigation** (non-breaking):

- Add `--filter=blob:none` or `--sparse` to the `git clone` command in the Dockerfile
- After cloning, remove non-essential directories:
  ```
  RUN rm -rf /opt/hermes-agent-staging/skills \
             /opt/hermes-agent-staging/docs \
             /opt/hermes-agent-staging/tests \
             /opt/hermes-agent-staging/.github
  ```
- This preserves `pyproject.toml`, `plugins/`, and agent source — everything needed for the deps pipeline

This mitigation is low-risk because `install-skills.sh` uses its own staging path (`/opt/hermes-skills-staging/`), not the agent clone's `skills/` directory.

## Verification

Check that the patch propagation chain is working in a running container:

```bash
# All three locations should show the User-Agent patch on line 66:
docker exec $CID grep -n 'User-Agent' \
  /opt/hermes-agent-staging/plugins/model-providers/custom/__init__.py

docker exec $CID grep -n 'User-Agent' \
  /home/hermeswebui/.hermes/hermes-agent/plugins/model-providers/custom/__init__.py

docker exec $CID find /app/venv/lib/ -path '*/plugins/model-providers/custom/__init__.py' \
  -exec grep -n 'User-Agent' {} +

# Verify single active runtime:
docker exec $CID which hermes          # should be /app/venv/bin/hermes
docker exec $CID python3 -c "import run_agent; print(run_agent.__file__)"
# should be under /app/venv/lib/python3.12/site-packages/
```

## Verdict

The dual installation is intentional and architecturally sound. Installation B is a staging pipeline, not a second runtime. The propagation chain correctly delivers patches from build-time `sed` through the staged clone into the active venv. The main cost is image size (~300 MB total for the staged clone and its runtime copy), which can be mitigated by trimming non-essential directories from the git clone without breaking any functionality.
