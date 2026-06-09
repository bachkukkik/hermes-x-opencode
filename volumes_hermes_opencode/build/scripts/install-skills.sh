#!/usr/bin/env bash
set -euo pipefail

OPENCODE_SKILLS_DIR="${OPENCODE_SKILLS_DIR:-/home/hermeswebui/.config/opencode/skills}"
HERMES_SKILLS_DIR="${HERMES_SKILLS_DIR:-/home/hermeswebui/.hermes/skills}"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

eprintf() { printf '%b\n' "$*" >&2; }

clone_sparse() {
  local repo_url="$1" dest="$2"
  shift 2
  local paths=("$@")

  eprintf "  Cloning %s (sparse: %s)" "$repo_url" "${paths[*]}"
  git clone --depth 1 --filter=blob:none --sparse "$repo_url" "$dest" 2>/dev/null
  (
    cd "$dest"
    git sparse-checkout set --no-cone "${paths[@]}" 2>/dev/null
    git checkout HEAD 2>/dev/null
  )
}

# ==============================================================================
# --- anthropics/skills (6 skills) ---
# ==============================================================================
eprintf ""
eprintf "=== anthropics/skills (6 opencode skills) ==="
ANTHROPIC_REPO="https://github.com/anthropics/skills.git"
ANTHROPIC_TMP="$TMPDIR/anthropics-skills"

ANTHROPIC_SKILLS=(
  "skills/algorithmic-art"
  "skills/frontend-design"
  "skills/web-artifacts-builder"
  "skills/webapp-testing"
  "skills/internal-comms"
  "skills/skill-creator"
)

mkdir -p "$OPENCODE_SKILLS_DIR"
clone_sparse "$ANTHROPIC_REPO" "$ANTHROPIC_TMP" "${ANTHROPIC_SKILLS[@]}"

for skill_path in "${ANTHROPIC_SKILLS[@]}"; do
  skill_name="$(basename "$skill_path")"
  eprintf "  Copying anthropics/skills -> %s" "$skill_name"
  rm -rf "$OPENCODE_SKILLS_DIR/$skill_name"
  cp -r "$ANTHROPIC_TMP/$skill_path" "$OPENCODE_SKILLS_DIR/$skill_name"
  rm -rf "$OPENCODE_SKILLS_DIR/$skill_name/.git"
done

# ==============================================================================
# --- openai/skills (4 skills) ---
# ==============================================================================
eprintf ""
eprintf "=== openai/skills (4 opencode skills) ==="
OPENAI_REPO="https://github.com/openai/skills.git"
OPENAI_TMP="$TMPDIR/openai-skills"

OPENAI_SKILLS=(
  "skills/.curated/jupyter-notebook"
  "skills/.curated/yeet"
  "skills/.curated/playwright-interactive"
  "skills/.curated/security-best-practices"
)

clone_sparse "$OPENAI_REPO" "$OPENAI_TMP" "${OPENAI_SKILLS[@]}"

for skill_path in "${OPENAI_SKILLS[@]}"; do
  skill_name="$(basename "$skill_path")"
  eprintf "  Copying openai/skills -> %s" "$skill_name"
  rm -rf "$OPENCODE_SKILLS_DIR/$skill_name"
  cp -r "$OPENAI_TMP/$skill_path" "$OPENCODE_SKILLS_DIR/$skill_name"
  rm -rf "$OPENCODE_SKILLS_DIR/$skill_name/.git"
done

# Also install yeet as a Hermes skill (under github/ category)
rm -rf "$HERMES_SKILLS_DIR/github/yeet"
mkdir -p "$HERMES_SKILLS_DIR/github/yeet"
cp "$OPENCODE_SKILLS_DIR/yeet/SKILL.md" "$HERMES_SKILLS_DIR/github/yeet/SKILL.md"
eprintf "  Installed yeet -> hermes/github/"

# GitHub category description
if [ ! -f "$HERMES_SKILLS_DIR/github/DESCRIPTION.md" ]; then
  mkdir -p "$HERMES_SKILLS_DIR/github"
  cat > "$HERMES_SKILLS_DIR/github/DESCRIPTION.md" <<'DESEOF'
---
description: GitHub workflow skills for managing repositories, pull requests, code reviews, and CI/CD pipelines.
---
DESEOF
fi

# ==============================================================================
# --- multica-ai/andrej-karpathy-skills (1 skill) ---
# ==============================================================================
eprintf ""
eprintf "=== multica-ai/andrej-karpathy-skills (1 opencode skill) ==="
KARPATHY_REPO="https://github.com/multica-ai/andrej-karpathy-skills.git"
KARPATHY_TMP="$TMPDIR/andrej-karpathy-skills"
KARPATHY_SKILLS=(
  "skills/karpathy-guidelines"
)

clone_sparse "$KARPATHY_REPO" "$KARPATHY_TMP" "${KARPATHY_SKILLS[@]}"

for skill_path in "${KARPATHY_SKILLS[@]}"; do
  skill_name="$(basename "$skill_path")"
  eprintf "  Copying multica-ai/andrej-karpathy-skills -> %s" "$skill_name"
  rm -rf "$OPENCODE_SKILLS_DIR/$skill_name"
  cp -r "$KARPATHY_TMP/$skill_path" "$OPENCODE_SKILLS_DIR/$skill_name"
  rm -rf "$OPENCODE_SKILLS_DIR/$skill_name/.git"
done

# ==============================================================================
# --- bachkukkik/coding-agents-docs-guideline (1 skill) ---
# ==============================================================================
eprintf ""
eprintf "=== coding-agents-docs-guideline (1 opencode skill) ==="
CUSTOM_REPO="https://github.com/bachkukkik/coding-agents-docs-guideline.git"
CUSTOM_TMP="$TMPDIR/coding-agents-docs-guideline"
SKILL_NAME="coding-agents-docs-guideline"

eprintf "  Cloning %s" "$CUSTOM_REPO"
git clone --depth 1 "$CUSTOM_REPO" "$CUSTOM_TMP" 2>/dev/null
rm -rf "$OPENCODE_SKILLS_DIR/$SKILL_NAME"
mkdir -p "$OPENCODE_SKILLS_DIR/$SKILL_NAME"
cp -r "$CUSTOM_TMP"/* "$OPENCODE_SKILLS_DIR/$SKILL_NAME/" 2>/dev/null || true
cp -r "$CUSTOM_TMP"/.* "$OPENCODE_SKILLS_DIR/$SKILL_NAME/" 2>/dev/null || true
rm -rf "$OPENCODE_SKILLS_DIR/$SKILL_NAME/.git"

# ==============================================================================
# --- bachkukkik/opencode-plan-build-orchestrator -> opencode + hermes ---
# ==============================================================================
eprintf ""
eprintf "=== opencode-plan-build-orchestrator (opencode + hermes) ==="
ORCHESTRATOR_REPO="https://github.com/bachkukkik/opencode-plan-build-orchestrator.git"
ORCHESTRATOR_TMP="$TMPDIR/opencode-plan-build-orchestrator"
ORCHESTRATOR_SKILL="opencode-plan-build-orchestrator"

eprintf "  Cloning %s" "$ORCHESTRATOR_REPO"
git clone --depth 1 "$ORCHESTRATOR_REPO" "$ORCHESTRATOR_TMP" 2>/dev/null

rm -rf "$OPENCODE_SKILLS_DIR/$ORCHESTRATOR_SKILL"
mkdir -p "$OPENCODE_SKILLS_DIR/$ORCHESTRATOR_SKILL"
cp "$ORCHESTRATOR_TMP/SKILL.md" "$OPENCODE_SKILLS_DIR/$ORCHESTRATOR_SKILL/SKILL.md"
cp -r "$ORCHESTRATOR_TMP/references" "$OPENCODE_SKILLS_DIR/$ORCHESTRATOR_SKILL/references" 2>/dev/null || true

rm -rf "$HERMES_SKILLS_DIR/autonomous-ai-agents/$ORCHESTRATOR_SKILL"
mkdir -p "$HERMES_SKILLS_DIR/autonomous-ai-agents/$ORCHESTRATOR_SKILL"
cp "$ORCHESTRATOR_TMP/SKILL.md" "$HERMES_SKILLS_DIR/autonomous-ai-agents/$ORCHESTRATOR_SKILL/SKILL.md"
cp -r "$ORCHESTRATOR_TMP/references" "$HERMES_SKILLS_DIR/autonomous-ai-agents/$ORCHESTRATOR_SKILL/references" 2>/dev/null || true

eprintf "  Installed %s -> opencode + hermes" "$ORCHESTRATOR_SKILL"

# ==============================================================================
# --- phuryn/pm-skills -> hermes skills/product-management/ ---
# ==============================================================================
eprintf ""
eprintf "=== phuryn/pm-skills (hermes product-management skills) ==="
PM_SKILLS_REPO="https://github.com/phuryn/pm-skills.git"
PM_SKILLS_TMP="$TMPDIR/pm-skills"

eprintf "  Cloning %s" "$PM_SKILLS_REPO"
git clone --depth 1 "$PM_SKILLS_REPO" "$PM_SKILLS_TMP" 2>/dev/null

mkdir -p "$HERMES_SKILLS_DIR/product-management"
pm_count=0
for plugin_dir in "$PM_SKILLS_TMP"/pm-*/skills/; do
  [ -d "$plugin_dir" ] || continue
  for skill_dir in "$plugin_dir"/*/; do
    [ -d "$skill_dir" ] || continue
    [ -f "$skill_dir/SKILL.md" ] || continue
    skill_name="$(basename "$skill_dir")"
    rm -rf "$HERMES_SKILLS_DIR/product-management/$skill_name"
    cp -r "$skill_dir" "$HERMES_SKILLS_DIR/product-management/$skill_name"
    pm_count=$((pm_count + 1))
  done
done
eprintf "  Copied %d skills into product-management/" "$pm_count"

cat > "$HERMES_SKILLS_DIR/product-management/DESCRIPTION.md" <<'DESEOF'
---
description: Product management skills for discovery, strategy, execution, and growth.
---
DESEOF

shortened=0
for skill_md in "$HERMES_SKILLS_DIR"/product-management/*/SKILL.md; do
  [ -f "$skill_md" ] || continue
  desc_line="$(grep -m1 '^description:' "$skill_md" 2>/dev/null)" || continue
  desc_val="${desc_line#description: }"
  desc_val="${desc_val#\"}"
  desc_val="${desc_val%\"}"
  if [ ${#desc_val} -gt 60 ]; then
    short_desc="${desc_val:0:57}..."
    sed -i "s|^description: .*|description: \"$short_desc\"|" "$skill_md"
    shortened=$((shortened + 1))
  fi
done
eprintf "  Shortened %d descriptions to <=60 chars" "$shortened"

# ==============================================================================
# --- llm-wiki (from hermes-agent staging -> opencode + hermes/research/) ---
# ==============================================================================
eprintf ""
eprintf "=== llm-wiki (opencode + hermes research skill) ==="
LLM_WIKI_SRC="/opt/hermes-agent-staging/skills/research/llm-wiki"
LLM_WIKI_SKILL="llm-wiki"

if [ -f "$LLM_WIKI_SRC/SKILL.md" ]; then
  # OpenCode (flat namespace)
  rm -rf "$OPENCODE_SKILLS_DIR/$LLM_WIKI_SKILL"
  mkdir -p "$OPENCODE_SKILLS_DIR/$LLM_WIKI_SKILL"
  cp "$LLM_WIKI_SRC/SKILL.md" "$OPENCODE_SKILLS_DIR/$LLM_WIKI_SKILL/SKILL.md"
  # Copy any sibling files (references/, scripts/, assets/) if present
  cp -r "$LLM_WIKI_SRC"/. "$OPENCODE_SKILLS_DIR/$LLM_WIKI_SKILL/" 2>/dev/null || true
  rm -rf "$OPENCODE_SKILLS_DIR/$LLM_WIKI_SKILL/.git"

  # Hermes (categorized under research/)
  rm -rf "$HERMES_SKILLS_DIR/research/$LLM_WIKI_SKILL"
  mkdir -p "$HERMES_SKILLS_DIR/research/$LLM_WIKI_SKILL"
  cp "$LLM_WIKI_SRC/SKILL.md" "$HERMES_SKILLS_DIR/research/$LLM_WIKI_SKILL/SKILL.md"
  cp -r "$LLM_WIKI_SRC"/. "$HERMES_SKILLS_DIR/research/$LLM_WIKI_SKILL/" 2>/dev/null || true
  rm -rf "$HERMES_SKILLS_DIR/research/$LLM_WIKI_SKILL/.git"

  eprintf "  Installed llm-wiki -> opencode + hermes/research/"
else
  eprintf "  WARNING: llm-wiki source not found at $LLM_WIKI_SRC"
fi

# Research category description (mirrors product-management pattern)
if [ ! -f "$HERMES_SKILLS_DIR/research/DESCRIPTION.md" ]; then
  mkdir -p "$HERMES_SKILLS_DIR/research"
  cat > "$HERMES_SKILLS_DIR/research/DESCRIPTION.md" <<'DESEOF'
---
description: Research skills for academic literature, knowledge bases, and domain reconnaissance.
---
DESEOF
fi

# ==============================================================================
# --- graphify (PyPI package -> registers skill for opencode + hermes) ---
# ==============================================================================
eprintf ""
eprintf "=== graphify ==="
if command -v uv >/dev/null 2>&1; then
  eprintf "  Installing graphifyy via uv tool..."
  timeout 120 uv tool install graphifyy || timeout 120 uv tool upgrade graphifyy || true
  export PATH="$HOME/.local/bin:$PATH"

  if command -v graphify >/dev/null 2>&1; then
    GRAPHIFY_HOME="/home/hermeswebui"
    eprintf "  Registering graphify for opencode..."
    HOME="$GRAPHIFY_HOME" graphify install --platform opencode 2>/dev/null || true
    if [ "${SKIP_HERMES_REGISTRATION:-0}" != "1" ]; then
      eprintf "  Registering graphify for hermes..."
      HOME="$GRAPHIFY_HOME" graphify install --platform hermes 2>/dev/null || true
    fi

    # Copy graphify bin for runtime availability (uv installs to root's .local)
    if [ -f /root/.local/bin/graphify ]; then
      cp /root/.local/bin/graphify /usr/local/bin/graphify
    fi

    # Copy Hermes skill to staging dir (graphify writes to $HOME/.hermes)
    if [ -f "$GRAPHIFY_HOME/.hermes/skills/graphify/SKILL.md" ]; then
      mkdir -p /opt/hermes-skills-staging/graphify
      cp "$GRAPHIFY_HOME/.hermes/skills/graphify/SKILL.md" /opt/hermes-skills-staging/graphify/SKILL.md
    fi

    eprintf "  graphify installed and registered."
  else
    eprintf "  WARNING: graphify CLI not found after uv tool install"
  fi
else
  eprintf "  WARNING: uv not available, skipping graphify install"
fi

# ==============================================================================
# --- Verification ---
# ==============================================================================
eprintf ""
eprintf "=== Verification ==="

errors=0

eprintf "  OpenCode skills ($OPENCODE_SKILLS_DIR):"
for dir in "$OPENCODE_SKILLS_DIR"/*/; do
  [ -d "$dir" ] || continue
  skill_name="$(basename "$dir")"
  if [ -f "$dir/SKILL.md" ]; then
    eprintf "    OK  %s" "$skill_name"
  else
    eprintf "    MISSING SKILL.md: %s" "$skill_name"
    errors=$((errors + 1))
  fi
done
oc_total=$(find "$OPENCODE_SKILLS_DIR" -maxdepth 1 -type d | tail -n +2 | wc -l)
eprintf "    Total: %d skills" "$oc_total"

eprintf "  Hermes skills ($HERMES_SKILLS_DIR):"
hermes_skill_count=0
hermes_errors=0
while IFS= read -r -d '' skill_md; do
  skill_dir="$(dirname "$skill_md")"
  rel_path="${skill_dir#$HERMES_SKILLS_DIR/}"
  hermes_skill_count=$((hermes_skill_count + 1))
  eprintf "    OK  %s" "$rel_path"
done < <(find "$HERMES_SKILLS_DIR" -name "SKILL.md" -print0 2>/dev/null)
if [ "$hermes_skill_count" -eq 0 ]; then
  eprintf "    (none)"
fi
eprintf "    Total: %d skills" "$hermes_skill_count"

if [ "$errors" -gt 0 ]; then
  eprintf "ERRORS: %d opencode skills missing SKILL.md" "$errors"
  exit 1
fi
if [ "$hermes_errors" -gt 0 ]; then
  eprintf "ERRORS: %d hermes skills missing SKILL.md" "$hermes_errors"
  exit 1
fi

chown -R hermeswebui:hermeswebui "$OPENCODE_SKILLS_DIR" 2>/dev/null || true
chown -R hermeswebui:hermeswebui "$HERMES_SKILLS_DIR" 2>/dev/null || true

eprintf ""
eprintf "All skills installed successfully."
