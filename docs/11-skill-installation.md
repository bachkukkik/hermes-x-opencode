# 11 — Skill Installation

## What

The `install-skills.sh` script installs curated skills from six upstream sources into both the OpenCode and Hermes skill directories during container startup, before model discovery and service launch.

## Why

- Eliminates manual skill management — both agent platforms receive relevant skills automatically on every boot
- Draws from multiple ecosystems (Anthropic, OpenAI, community repos, PyPI) to cover coding, product management, documentation, and codebase analysis
- Cross-platform SKILL.md format is compatible with both OpenCode (flat discovery) and Hermes (recursive discovery) without modification
- Opt-out via `SKIP_SKILL_INSTALL=1` allows faster boot when skills are not needed

## How

The script is located at `volumes_hermes_opencode/build/scripts/install-skills.sh`, copied to `/usr/local/bin/install-skills.sh` during the Docker build (`04 — Build Pipeline`), and called by the entrypoint (`05 — Entrypoint Sequence`) before model discovery.

### Execution context

| Parameter | Value | Notes |
|-----------|-------|-------|
| `OPENCODE_SKILLS_DIR` | `/home/hermeswebui/.config/opencode/skills` | Ephemeral — no volume mount, recreated each boot. Owned by hermeswebui. |
| `HERMES_SKILLS_DIR` | `/home/hermeswebui/.hermes/skills` | Persisted via bind mount (`07 — Volume Layout`) |
| `SKIP_SKILL_INSTALL` | `0` (default) | Set `1` in `.env` to skip the entire script |
| `TMPDIR` | `mktemp -d` | Cleaned up on exit via trap |

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

Each skill directory is copied to `$OPENCODE_SKILLS_DIR/<name>/` with its `.git` directory removed. SKILL.md frontmatter contains `name`, `description`, and `license` fields.

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
| OpenCode | `/home/hermeswebui/.config/opencode/skills/opencode-plan-build-orchestrator/` |
| Hermes | `/home/hermeswebui/.hermes/skills/autonomous-ai-agents/opencode-plan-build-orchestrator/` |

The `references/` directory (containing `plan-build-patterns.md` and `opencode-cli-reference.md`) is copied alongside `SKILL.md` because the skill references these files with relative links.

### Source 5: phuryn/pm-skills

Iterates all `pm-*/skills/*/` directories from the cloned repo and copies each into `$HERMES_SKILLS_DIR/product-management/<name>/`. After copy:

1. **DESCRIPTION.md creation** — Writes a category description file at `product-management/DESCRIPTION.md` with YAML frontmatter, matching the Hermes bundled skill format.
2. **Description shortening** — Iterates all installed `product-management/*/SKILL.md` files. If the `description:` value exceeds 60 characters, truncates to 57 characters + `...` using sed. This satisfies the Hermes style guideline.

### Source 6: graphify

Installs the `graphifyy` Python package via `uv tool install`, then registers the skill for each platform:

```bash
timeout 120 uv tool install graphifyy || timeout 120 uv tool upgrade graphifyy || true
graphify install --platform opencode
graphify install --platform hermes
```

The `uv tool install/upgrade` commands are wrapped with `timeout 120` to prevent the entrypoint from hanging on network issues. Both commands pipe stderr to stdout (not `/dev/null`) so download progress and errors are visible in container logs. If `uv` is not available or `graphify` fails, the script continues with a warning.

### Sparse clone helper

`clone_sparse()` uses git partial clone to avoid downloading the entire repository:

```bash
git clone --depth 1 --filter=blob:none --sparse "$repo_url" "$dest"
cd "$dest"
git sparse-checkout set --no-cone "${paths[@]}"
git checkout HEAD
```

### Platform skill discovery

The two agent platforms discover skills differently:

| Platform | Discovery mechanism | Depth | Key file |
|----------|---------------------|-------|----------|
| OpenCode | `skills/*/SKILL.md` | 1 level (flat) | Configured in OpenCode binary |
| Hermes | `os.walk` recursive scan | Unlimited | `hermes-agent/agent/skill_utils.py` (`iter_skill_index_files`) |

Hermes also scans for `DESCRIPTION.md` files at category level to generate the skill category banner in the system prompt. The install script creates `product-management/DESCRIPTION.md` to provide this description.

### SKILL.md frontmatter compatibility

Both platforms parse YAML frontmatter leniently — unknown fields are silently ignored.

| Frontmatter field | OpenCode | Hermes | Notes |
|-------------------|----------|--------|-------|
| `name` | Required | Falls back to directory name | 1–64 chars, `^[a-z0-9]+(-[a-z0-9]+)*$` |
| `description` | Required | Falls back to first body line | Max 1024 chars |
| `license` | Recognized | Recognized | Optional |
| `compatibility` | Recognized | Ignored | Optional |
| `metadata` | Recognized (string map) | Checks `metadata.hermes.*` | Optional |
| `platforms` | Ignored | OS gate (`[linux, macos, windows]`) | Optional |
| `version`, `author` | Ignored | Recognized | Optional |

### Skip mechanism

The entrypoint gates the script call with `SKIP_SKILL_INSTALL`:

```bash
if [ "${SKIP_SKILL_INSTALL:-0}" != "1" ]; then
    export OPENCODE_SKILLS_DIR
    mkdir -p "$OPENCODE_SKILLS_DIR"
    install-skills.sh
fi
```

Set `SKIP_SKILL_INSTALL=1` in `.env` to skip. This is documented in `.env.example` and passed through `docker-compose.yml` (`06 — Config and Env`).

### Verification section

The script ends with a verification pass that checks for `SKILL.md` in every installed directory. It counts total skills for both platforms and exits with code 1 if any OpenCode skill is missing its `SKILL.md`.

```bash
for dir in "$OPENCODE_SKILLS_DIR"/*/; do
    [ -f "$dir/SKILL.md" ] || errors=$((errors + 1))
done
find "$HERMES_SKILLS_DIR" -name "SKILL.md" -print0
```

### Timing impact

| Boot type | Skill install adds | Primary cost |
|-----------|-------------------|--------------|
| First boot | 15–45s | Six git clones (sparse/shallow) + graphify pip install |
| Subsequent | 15–45s | Hermes skills are cached in bind mount, but OpenCode skills are ephemeral (always reinstalled) |

## Verification

```bash
docker logs <container> 2>&1 | grep -E "(=== |  Copied|  Total:|graphify|SKILL\.MD)"
docker exec <container> find /home/hermeswebui/.config/opencode/skills -name "SKILL.md" | wc -l
docker exec <container> find /home/hermeswebui/.hermes/skills -name "SKILL.md" | wc -l
docker exec <container> ls /home/hermeswebui/.hermes/skills/product-management/DESCRIPTION.md
docker exec <container> stat -c "%U:%G" /home/hermeswebui/.config/opencode/skills
```

Expected output in container logs:
```
=== anthropics/skills (6 opencode skills) ===
=== openai/skills (4 opencode skills) ===
=== coding-agents-docs-guideline (1 opencode skill) ===
=== opencode-plan-build-orchestrator (opencode + hermes) ===
=== phuryn/pm-skills (hermes product-management skills) ===
  Copied 55 skills into product-management/
  Shortened 42 descriptions to <=60 chars
=== graphify ===
  graphify installed and registered.
=== Verification ===
  Total: 12 skills
  Total: 56 skills
All skills installed successfully.
```

## What Works

- All six upstream sources install correctly from their respective clone or pip methods
- Sparse checkout avoids downloading entire repositories for `anthropics/skills` and `openai/skills`
- Both platforms discover their installed skills using their native discovery mechanisms
- Cross-platform SKILL.md frontmatter (from `opencode-plan-build-orchestrator`) is parsed without errors by both platforms
- `DESCRIPTION.md` generation enables the Hermes category banner for `product-management/`
- Description shortening keeps the Hermes system prompt skill listing within the 60-char style guideline
- graphify graceful degradation — install timeout or missing `uv` produces a warning, not an error; all other services start normally
- `SKIP_SKILL_INSTALL=1` provides a clean opt-out for faster boot
- Verification section catches missing `SKILL.md` files and exits with code 1

## What Fails

- **OpenCode skills are ephemeral:** The `/home/hermeswebui/.config/opencode/skills/` directory has no volume mount. Skills are reinstalled from scratch on every boot, adding 15–45 seconds to startup.
- **graphify install can be slow:** The `uv tool install graphifyy` step downloads ~50MB of Python packages (numpy, scipy, networkx). On slow or contested networks, the 120-second timeout may fire, leaving graphify unregistered. The script continues and all other services start normally.
- **pm-skills descriptions lose fidelity:** The 60-char truncation shortens descriptive skill names to approximate summaries. The full description is discarded.
- **Git clone failures are fatal:** If any upstream repository is unreachable, the script exits due to `set -e`. The container does not start.
- **No offline mode:** All skill sources require network access. There is no cache or fallback for previously downloaded skills.

## Resolution

- OpenCode skills ephemerality is acceptable — the install adds 15–45s but guarantees the latest versions from upstream. To persist, add a volume mount for `/home/hermeswebui/.config/opencode/skills/` in `docker-compose.yml`.
- The 120-second timeout is generous for most networks. If graphify consistently times out, increase the value in `install-skills.sh` or set `SKIP_SKILL_INSTALL=1` to skip the graphify section entirely.
- Description truncation preserves the most important content (first 57 chars). The original descriptions are available in the phuryn/pm-skills repository. To keep full descriptions, remove the shortening loop from `install-skills.sh`.
- Wrap individual clone blocks with `|| eprintf "WARNING: ..."` to make git failures non-fatal if resilient startup is preferred over guaranteed skill availability.
- For air-gapped environments, pre-download skill directories into `build/data/opencode-skills/` and `build/data/hermes-skills/` and copy from local paths instead of git clone.

## Verdict

The skill installation system provides comprehensive coverage across coding, documentation, product management, and codebase analysis domains for both agent platforms. The ephemeral OpenCode install and network dependency are the main operational constraints, both with straightforward mitigations.
