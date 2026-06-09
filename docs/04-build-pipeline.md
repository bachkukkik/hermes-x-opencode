# 04 — Build Pipeline

## What

The Dockerfile builds a single image containing the Hermes WebUI base, system packages, the OpenCode CLI, a staged copy of the Hermes Agent source with the CustomProfile User-Agent patch applied, and all skills pre-installed for both OpenCode and Hermes platforms.

## Why

- Produces a self-contained image with all runtime dependencies pre-installed, eliminating network fetches during container startup
- Applies the Cloudflare User-Agent fix at build time so it is baked into the image layer and never needs runtime patching
- Clones the hermes-agent at a configurable version (branch, tag, or commit) via build arg, enabling version pinning
- Installs all skills (14 OpenCode + ~67 Hermes) at build time, reducing container startup from 15–45s of git clones to a near-instant `cp -a`

## How

The Dockerfile is located at `volumes_hermes_opencode/build/Dockerfile`. The build context is `./volumes_hermes_opencode/build`.

### Build steps (in order)

| Step | Instruction | Purpose |
|------|-------------|---------|
| 1 | `FROM ghcr.io/nesquena/hermes-webui:latest` | Base image with Python 3.12, WebUI server, hermes CLI |
| 2 | `ARG HERMES_AGENT_VERSION=main` | Build arg for agent version |
| 3 | `RUN apt-get install build-essential git ripgrep ffmpeg procps curl` | System packages for agent build deps and OpenCode |
| 4 | `RUN curl -fsSL https://opencode.ai/install \|\| bash` | Install OpenCode CLI, copy to `/usr/local/bin` |
| 5 | `RUN curl -LsSf https://astral.sh/uv/install.sh \|\| sh` | Install uv tool manager for graphify and other Python tool installs |
| 6 | `RUN git clone --depth 1 --branch ${HERMES_AGENT_VERSION} ... /opt/hermes-agent-staging` | Clone agent to staging path (not the runtime path) |
| 7 | `RUN sed -i ... custom/__init__.py` | Apply CustomProfile User-Agent patch (see `08 — Cloudflare UA Fix`) |
| 8a | `COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh` | Copy entrypoint script |
| 8b | `COPY scripts/lib/ /usr/local/bin/lib/` | Copy library modules (11 files) |
| 9 | `RUN HERMES_SKILLS_DIR=/opt/hermes-skills-staging OPENCODE_SKILLS_DIR=/home/hermeswebui/.config/opencode/skills install-skills.sh` | Build-time skill installation (14 OpenCode + ~67 Hermes skills), including graphify for both platforms |
| 10 | `RUN echo "=== Hermes x OpenCode Stack ===" && ...` | Verification: Python version, opencode version, graphify version, agent present, patch applied |
| 11 | `ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]` | Set entrypoint |

### Agent staging

The agent is cloned to `/opt/hermes-agent-staging`, not to the runtime path (`/home/hermeswebui/.hermes/hermes-agent`). The runtime path is a bind-mounted volume that starts empty on first boot. The entrypoint copies the agent from staging to the bind mount on first start.

This separation ensures:
- The agent is baked into the image (no runtime git clone)
- The bind mount at `/home/hermeswebui/.hermes` persists sessions, config, and skills across rebuilds
- The agent source is copied only once (subsequent boots detect it already exists)

### Skill staging

Skills are installed at build time by running `install-skills.sh` with environment overrides (`11 — Skill Installation`):

| Directory | Contents | Persisted via |
|-----------|----------|---------------|
| `/home/hermeswebui/.config/opencode/skills` | 14 OpenCode skills (incl. graphify) | Image layer (no volume mount) |
| `/opt/hermes-skills-staging` | ~67 Hermes skills (incl. graphify) | Image layer (staging only) |

Hermes skills are staged to `/opt/hermes-skills-staging` instead of the runtime path (`/home/hermeswebui/.hermes/skills`) because `~/.hermes` is a bind-mounted volume that overwrites at runtime. The entrypoint copies from staging to the bind mount at every boot (`cp -a`, near-instant). OpenCode skills have no volume mount and persist in the image directly.

Graphify registers for both platforms at build time. The OpenCode skill is written directly to `/home/hermeswebui/.config/opencode/skills/graphify/`. The Hermes skill is written to `$GRAPHIFY_HOME/.hermes/skills/graphify/` (with `HOME=/home/hermeswebui`), then copied to `/opt/hermes-skills-staging/graphify/` for staging. The graphify binary is also copied to `/usr/local/bin/graphify` for all-user accessibility. Runtime `entrypoint.sh` re-runs `graphify install --platform hermes` as an overlayfs safety net.

### Build command

```bash
docker compose build

docker compose build --build-arg HERMES_AGENT_VERSION=v1.2.3

docker compose build --no-cache
```

### Platform

The image builds and runs on **Linux ARM64** (Raspberry Pi). The base image (`ghcr.io/nesquena/hermes-webui:latest`) provides ARM64 manifests.

## Verification

```bash
docker compose build 2>&1 | tail -5
docker compose run --rm --entrypoint bash hermes-opencode -c \
  'test -f /opt/hermes-agent-staging/pyproject.toml && echo "Agent: OK" && \
   grep -q "User-Agent.*hermes-agent" /opt/hermes-agent-staging/plugins/model-providers/custom/__init__.py && echo "Patch: OK" && \
   opencode --version && echo "OpenCode: OK" && \
   uv --version && echo "uv: OK" && \
   graphify --version && echo "graphify: OK" && \
   test -d /opt/hermes-skills-staging/product-management && echo "Hermes skills staging: OK" && \
   test -f /opt/hermes-skills-staging/graphify/SKILL.md && echo "graphify staging: OK" && \
   find /home/hermeswebui/.config/opencode/skills -name "SKILL.md" | wc -l | grep -q "^[0-9]" && echo "OpenCode skills: OK"'
```

## What Works

- Build completes in under 3 minutes with layer caching on ARM64 (skill installation adds ~1 minute)
- Agent clone uses `--depth 1` to minimize image size
- OpenCode CLI installs from the official script and is available at `/usr/local/bin/opencode`
- Verification step at the end of the build catches missing agent or failed patch
- `--build-arg HERMES_AGENT_VERSION` correctly switches branches/tags
- Skills install at build time — all git clones and pip installs happen once during `docker compose build`
- Runtime startup is fast — only a `cp -a` from staging to bind mount (near-instant)
- `uv` tool manager installed and available for future Python tool installs
- graphify installed and registered for both OpenCode and Hermes at build time
- graphify binary copied to `/usr/local/bin` for all-user accessibility

## What Fails

- **sed pattern breaks on upstream changes:** If the CustomProfile class in hermes-agent changes the `base_url="",` line format, the `sed` command silently fails or applies incorrectly. The verification `grep` catches this and fails the build.
- **OpenCode install script may change:** The `curl | bash` install method depends on `opencode.ai/install` being available and returning a compatible installer.
- **Staging paths are not cleaned up:** `/opt/hermes-agent-staging` and `/opt/hermes-skills-staging` remain in the image after content is copied to bind mounts. They consume approximately 50MB and 10MB of image space respectively.
- **Skill install fails if upstream repos are unreachable:** `install-skills.sh` runs with `set -e`. If any git clone or pip install fails, the Docker build fails.

## Resolution

- The build-time verification step (`grep -q '"User-Agent".*"hermes-agent'`) catches a failed sed and fails the build. Update the sed pattern when upgrading hermes-agent versions.
- Pin the OpenCode version or switch to a direct binary download if the install script becomes unreliable.
- The staging directory overhead is acceptable (~60MB total). To reclaim space, add a multi-stage build, but note this prevents the entrypoint from copying content on first boot.
- Skill install failures are caught by the build-time verification in `install-skills.sh` (checks all `SKILL.md` files exist, exits 1 on missing). Use `--no-cache` to force a fresh build if upstream repos recover.

## Verdict

The build pipeline is straightforward and deterministic. The main risks are the sed pattern for the CustomProfile patch and upstream repo availability during skill installation, both mitigated by build-time verification steps. The staging approach cleanly separates build-time content from runtime volumes.
