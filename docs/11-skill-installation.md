# 11 — Skill Installation

## What

The `install-skills.sh` script installs curated skills from six upstream sources into both the OpenCode and Hermes skill directories. It runs at Docker **build time** (via the Dockerfile), with a fast runtime staging copy for Hermes skills at container startup.

## Why

- Eliminates network fetches at container startup — all git clones and pip installs happen once during `docker compose build`
- Both agent platforms receive relevant skills automatically without manual management
- Draws from multiple ecosystems (Anthropic, OpenAI, community repos, PyPI) to cover coding, product management, documentation, and codebase analysis
- Cross-platform SKILL.md format is compatible with both OpenCode (flat discovery) and Hermes (recursive discovery) without modification

## How

The script is located at `volumes_hermes_opencode/build/scripts/install-skills.sh`, copied to `/usr/local/bin/install-skills.sh` during the Docker build (`04 — Build Pipeline`).

### Two-phase architecture

Skills are installed in two phases:

| Phase | When | What | Duration |
|-------|------|------|----------|
| Build | `docker compose build` | Full `install-skills.sh` execution: git clones, pip installs, graphify registration for OpenCode | ~60s |
| Runtime | `docker compose up` | `cp -a /opt/hermes-skills-staging/ → ~/.hermes/skills/` + graphify hermes registration | <1s |

### Build phase

The Dockerfile runs `install-skills.sh` with environment overrides:

```dockerfile
RUN HERMES_SKILLS_DIR=/opt/hermes-skills-staging \
    SKIP_HERMES_REGISTRATION=1 \
    OPENCODE_SKILLS_DIR=/home/hermeswebui/.config/opencode/skills \
    install-skills.sh
```

| Override | Purpose |
|----------|---------|
| `HERMES_SKILLS_DIR=/opt/hermes-skills-staging` | Stage to a non-volume-mounted path (the runtime `~/.hermes` is overwritten by bind mount) |
| `SKIP_HERMES_REGISTRATION=1` | Skip `graphify install --platform hermes` (hermes home dir is not available during build) |
| `OPENCODE_SKILLS_DIR=/home/hermeswebui/.config/opencode/skills` | Install to final location (no volume mount, persists in image) |

### Runtime phase

The entrypoint (`05 — Entrypoint Sequence`) copies staged Hermes skills and registers graphify:

```bash
if [ "${SKIP_SKILL_INSTALL:-0}" != "1" ]; then
    mkdir -p "$HERMES_SKILLS_DIR"
    cp -a /opt/hermes-skills-staging/. "$HERMES_SKILLS_DIR/" 2>/dev/null || true
    graphify install --platform hermes 2>/dev/null || true
fi
```

This copy is near-instant because the data is already in the image layer.

### Skill directories

| Directory | Contents | Persisted via | Installed at |
|-----------|----------|---------------|-------------|
| `/home/hermeswebui/.config/opencode/skills` | 12 OpenCode skills | Image layer (no volume mount) | Build time |
| `/opt/hermes-skills-staging` | ~66 Hermes skills | Image layer (staging) | Build time |
| `/home/hermeswebui/.hermes/skills` | ~66 Hermes skills (runtime copy) | Bind mount (`07 — Volume Layout`) | Runtime `cp -a` |

### Skill sources

| # | Source | Target platform | Count | Clone method |
|---|--------|-----------------|-------|--------------|
| 1 | `anthropics/skills` | OpenCode | 6 | Sparse (`--filter=blob:none --sparse`) |
| 2 | `openai/skills` | OpenCode | 4 | Sparse |
| 3 | `bachkukkik/coding-agents-docs-guideline` | OpenCode | 1 | Shallow (`--depth 1`) |
| 4 | `bachkukkik/opencode-plan-build-orchestrator` | OpenCode + Hermes | 1 | Shallow |
| 5 | `phuryn/pm-skills` | Hermes | ~55 | Shallow |
| 6 | `graphifyy` (PyPI) | OpenCode + Hermes | 1 | `uv tool install` + `graphify install` |

### Source 1: anthropics/skills

Installs six skills from the Anthropic official skills repository using git sparse checkout to download only the required directories.

```bash
ANTHROPIC_SKILLS=(
  "skills/algorithmic-art"
  "skills/frontend-design"
  "skills/web-artifacts-builder"
  "skills/webapp-testing"
  "skills/internal-comms"
  "skills/skill-creator"
)
clone_sparse "$ANTHROPIC_REPO" "$ANTHROPIC_TMP" "${ANTHROPIC_SKILLS[@]}"
```

Each skill directory is copied to `$OPENCODE_SKILLS_DIR/<name>/` with its `.git` directory removed.

### Source 2: openai/skills

Installs four curated skills from the OpenAI skills repository. Skills live under `skills/.curated/` in the repo.

```bash
OPENAI_SKILLS=(
  "skills/.curated/jupyter-notebook"
  "skills/.curated/yeet"
  "skills/.curated/playwright-interactive"
  "skills/.curated/security-best-practices"
)
```

Same sparse checkout and copy pattern as Source 1.

### Source 3: coding-agents-docs-guideline

Shallow clones the full repo and copies all contents (including `examples/` directory) to `$OPENCODE_SKILLS_DIR/coding-agents-docs-guideline/`.

### Source 4: opencode-plan-build-orchestrator

Installs to both platforms:

| Platform | Path |
|----------|------|
| OpenCode | `$OPENCODE_SKILLS_DIR/opencode-plan-build-orchestrator/` |
| Hermes | `$HERMES_SKILLS_DIR/autonomous-ai-agents/opencode-plan-build-orchestrator/` |

The `references/` directory is copied alongside `SKILL.md` because the skill references these files with relative links.

### Source 5: phuryn/pm-skills

Iterates all `pm-*/skills/*/` directories from the cloned repo and copies each into `$HERMES_SKILLS_DIR/product-management/<name>/`. After copy:

1. **DESCRIPTION.md creation** — Writes a category description file at `product-management/DESCRIPTION.md` with YAML frontmatter
2. **Description shortening** — Truncates `description:` values exceeding 60 chars to 57 chars + `...` via sed

### Source 6: graphify

Installs the `graphifyy` Python package via `uv tool install`, then registers for each platform:

```bash
timeout 120 uv tool install graphifyy || timeout 120 uv tool upgrade graphifyy || true
graphify install --platform opencode   # build time
graphify install --platform hermes     # runtime only (SKIP_HERMES_REGISTRATION guards build)
```

The `uv tool install/upgrade` commands are wrapped with `timeout 120` to prevent the build from hanging on network issues.

### Sparse clone helper

`clone_sparse()` uses git partial clone to avoid downloading the entire repository:

```bash
git clone --depth 1 --filter=blob:none --sparse "$repo_url" "$dest"
cd "$dest"
git sparse-checkout set --no-cone "${paths[@]}"
git checkout HEAD
```

### Platform skill discovery

| Platform | Discovery mechanism | Depth | Key file |
|----------|---------------------|-------|----------|
| OpenCode | `skills/*/SKILL.md` | 1 level (flat) | Configured in OpenCode binary |
| Hermes | `os.walk` recursive scan | Unlimited | `hermes-agent/agent/skill_utils.py` (`iter_skill_index_files`) |

### Skip mechanisms

| Variable | Scope | Default | Effect |
|----------|-------|---------|--------|
| `SKIP_SKILL_INSTALL=1` | Runtime only | `0` | Skips the `cp -a` staging copy and graphify hermes registration |
| `SKIP_HERMES_REGISTRATION=1` | Build time | `0` | Skips `graphify install --platform hermes` during build |

### Verification section

The script ends with a verification pass that checks for `SKILL.md` in every installed directory and exits with code 1 if any OpenCode skill is missing its `SKILL.md`.

### Timing impact

| Phase | Duration | Primary cost |
|-------|----------|-------------|
| Build (one-time) | ~60s | Six git clones + graphify pip install |
| Runtime (every boot) | <1s | `cp -a` from staging + graphify hermes registration |

## Verification

```bash
docker compose build 2>&1 | grep -E "(=== |  Copied|  Total:|All skills)"
docker exec <container> find /home/hermeswebui/.config/opencode/skills -name "SKILL.md" | wc -l
docker exec <container> find /home/hermeswebui/.hermes/skills -name "SKILL.md" | wc -l
docker exec <container> ls /home/hermeswebui/.hermes/skills/product-management/DESCRIPTION.md
docker run --rm --entrypoint bash hermes_x_opencode-hermes-opencode:latest -c \
  'find /opt/hermes-skills-staging -name "SKILL.md" | wc -l'
```

Expected build output:
```
=== anthropics/skills (6 opencode skills) ===
=== openai/skills (4 opencode skills) ===
=== coding-agents-docs-guideline (1 opencode skill) ===
=== opencode-plan-build-orchestrator (opencode + hermes) ===
=== phuryn/pm-skills (hermes product-management skills) ===
  Copied 55 skills into product-management/
=== graphify ===
  graphify installed and registered.
=== Verification ===
  Total: 12 skills
  Total: 66 skills
All skills installed successfully.
```

## What Works

- All six upstream sources install correctly from their respective clone or pip methods at build time
- Sparse checkout avoids downloading entire repositories for `anthropics/skills` and `openai/skills`
- Both platforms discover their installed skills using their native discovery mechanisms
- Runtime startup is fast — only a `cp -a` from staging (<1s) instead of git clones (15–45s)
- OpenCode skills persist in the image layer across container restarts (no volume mount)
- Hermes skills are staged at build time and copied to the bind mount at runtime
- `SKIP_SKILL_INSTALL=1` provides a clean opt-out for the runtime staging copy
- Build-time verification catches missing `SKILL.md` files and fails the build (exit 1)
- Cross-platform SKILL.md frontmatter is parsed without errors by both platforms

## What Fails

- **Build requires network access:** All skill sources (6 git repos + 1 PyPI package) must be reachable during `docker compose build`. If any is unavailable, the build fails.
- **graphify install can be slow:** The `uv tool install graphifyy` step downloads ~50MB of Python packages. On slow networks, the 120-second timeout may fire, leaving graphify unregistered. The build continues and the warning is visible in build output.
- **pm-skills descriptions lose fidelity:** The 60-char truncation shortens descriptive skill names to approximate summaries.
- **Staging directories consume image space:** `/opt/hermes-skills-staging` (~10MB) and `/opt/hermes-agent-staging` (~50MB) remain in the image after content is copied to bind mounts.

## Resolution

- Build-time network dependency is inherent to the approach. For air-gapped environments, pre-download skill directories into `build/data/` and modify `install-skills.sh` to copy from local paths instead of git clone.
- The 120-second graphify timeout is generous for most networks. If graphify consistently times out, increase the value in `install-skills.sh`.
- Description truncation preserves the most important content (first 57 chars). To keep full descriptions, remove the shortening loop from `install-skills.sh`.
- The staging directory overhead (~60MB total) is acceptable. To reclaim space, use a multi-stage build.

## Verdict

The two-phase skill installation architecture eliminates runtime network dependency and reduces container startup from 15–45s to under 1s for skill setup. The build-time cost (~60s) is paid once per image rebuild. The main constraint is build-time network access to six upstream repositories.
