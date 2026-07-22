#!/usr/bin/env bash
# ── Path constants & runtime config ─────────────────────────────────────────

# Path constants
export HERMES_HOME="/home/hermeswebui/.hermes"
HERMES_BAK="/home/hermeswebui/.hermes-bak"
CONFIG="${HERMES_HOME}/config.yaml"
AGENT_DIR="${HERMES_HOME}/hermes-agent"
STAGING_DIR="/opt/hermes-agent-staging"
HERMES_SKILLS_DIR="${HERMES_HOME}/skills"

OPENCODE_USER="hermeswebui"
OPENCODE_USER_HOME="/home/${OPENCODE_USER}"
OPENCODE_CONFIG="${OPENCODE_USER_HOME}/.config/opencode/opencode.jsonc"
OPENCODE_DCP_CONFIG="${OPENCODE_USER_HOME}/.config/opencode/dcp.jsonc"
OPENCODE_SKILLS_DIR="${OPENCODE_USER_HOME}/.config/opencode/skills"

# Playwright browser install location (baked by the Dockerfile as a shared,
# world-readable path). Exported here as the single source of truth so it can be
# passed explicitly through the `su` boundary to hermeswebui-owned services —
# `su -s /bin/bash` resets the parent environment (same reason OPENAI_* are
# forwarded to opencode serve), so relying on the Dockerfile ENV alone would
# leave the agent's `playwright-cli` unable to locate its chromium.
export PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/ms-playwright}"

# GitHub CLI / git auth. `gh` auto-reads GH_TOKEN; accept GITHUB_TOKEN as
# an alias so either compose var works. Exported here so services that `su`
# to hermeswebui still see it (the re-export inside each invocation is
# defensive — this image's `su` preserves the parent environment already).
GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
export GH_TOKEN

# Wiki path (used by wiki-init.sh)
HERMES_WIKI_PATH="${HERMES_WIKI_PATH:-${HERMES_HOME}/wiki}"

# Runtime config (from env, with defaults)
OPENAI_BASE_URL="${OPENAI_BASE_URL:-}"
OPENAI_API_KEY="${OPENAI_API_KEY:-}"
OPENAI_DEFAULT_MODEL="${OPENAI_DEFAULT_MODEL:-openai/gpt-4o}"
OPENAI_SMALL_MODEL="${OPENAI_SMALL_MODEL:-}"
OPENAI_CONTEXT_LENGTH="${OPENAI_CONTEXT_LENGTH:-200000}"
OPENAI_IMAGE_MODEL="${OPENAI_IMAGE_MODEL:-gpt-image-2}"

# Web search backend (hermes `web` toolset). ddgs is keyless + search-only, so we
# pair it with an auto/lazy extract backend (leave HERMES_WEB_EXTRACT_BACKEND
# empty). Backends are lazy-installed on first use when allow_lazy_installs=true.
HERMES_WEB_SEARCH_BACKEND="${HERMES_WEB_SEARCH_BACKEND:-ddgs}"
HERMES_WEB_EXTRACT_BACKEND="${HERMES_WEB_EXTRACT_BACKEND:-}"
HERMES_ALLOW_LAZY_INSTALLS="${HERMES_ALLOW_LAZY_INSTALLS:-true}"

# Fine-grained model overrides (fall back to OPENAI_* if unset)
HERMES_DEFAULT_MODEL="${HERMES_DEFAULT_MODEL:-${OPENAI_DEFAULT_MODEL}}"
OPENCODE_DEFAULT_MODEL="${OPENCODE_DEFAULT_MODEL:-${OPENAI_DEFAULT_MODEL}}"
OPENCODE_SMALL_MODEL="${OPENCODE_SMALL_MODEL:-${OPENAI_SMALL_MODEL:-${OPENAI_DEFAULT_MODEL}}}"

HERMES_API_KEY="${HERMES_API_KEY:-}"
HERMES_API_PORT="${HERMES_API_PORT:-8642}"
HERMES_COMPRESSION_THRESHOLD="${HERMES_COMPRESSION_THRESHOLD:-0.76}"
# OUTPUT-token cap baked into config.yaml as model.max_tokens (response-length
# ceiling, NOT the context window). Defaults to 262144 so long responses and
# delegation subagents (which inherit the parent max_tokens) aren't truncated by
# a small upstream proxy/provider default (finish_reason='length'). Integer;
# must stay below the model's context window — lower it if a provider rejects it.
HERMES_MAX_TOKENS="${HERMES_MAX_TOKENS:-262144}"

# --- DCP (dynamic context pruning) compression threshold ---------------------
# The @tarquinen/opencode-dcp plugin defaults to a hard 100_000-token
# maxContextLimit regardless of the model's real window, so a 1M-context model
# gets compression-nudged at ~10% fill. We generate a managed dcp.jsonc whose
# compress.maxContextLimit is expressed as "<pct>%" of EACH model's own context
# window (DCP resolves the percentage per active model). This mirrors Hermes'
# HERMES_COMPRESSION_THRESHOLD. Range 0.0–1.0; default 0.76.
OPENCODE_COMPRESSION_THRESHOLD="${OPENCODE_COMPRESSION_THRESHOLD:-0.76}"

# Runtime autonomy knobs (#53): YOLO mode disables approval prompts and enables
# the delegation subagent loop; max_iterations caps that loop.
HERMES_YOLO_MODE="${HERMES_YOLO_MODE:-1}"
HERMES_DELEGATION_MAX_ITERATIONS="${HERMES_DELEGATION_MAX_ITERATIONS:-50}"

# Main agent tool-calling loop budget → config.yaml `agent.max_turns`, which the
# gateway bridges to HERMES_MAX_ITERATIONS (the runtime `agent.max_iterations`).
# This is the loop that emits "Reached maximum iterations (N)" — DISTINCT from
# HERMES_GOAL_MAX_TURNS (/goal cross-turn budget) and HERMES_DELEGATION_MAX_ITERATIONS
# (per-subagent cap). The agent's built-in default is 90; raised here so long
# autonomous runs don't truncate mid-task. See gateway/run.py (agent.max_turns bridge).
HERMES_AGENT_MAX_TURNS="${HERMES_AGENT_MAX_TURNS:-200}"

# Goal budget (#57) + Hermes web dashboard (#57): /goal max_turns; opt-in management UI on :9119.
HERMES_GOAL_MAX_TURNS="${HERMES_GOAL_MAX_TURNS:-50}"
HERMES_DASHBOARD_ENABLED="${HERMES_DASHBOARD_ENABLED:-false}"
HERMES_DASHBOARD_PORT="${HERMES_DASHBOARD_PORT:-9119}"
HERMES_DASHBOARD_HOST="${HERMES_DASHBOARD_HOST:-0.0.0.0}"

OPENCODE_SERVE_PORT="${OPENCODE_SERVE_PORT:-4096}"
OPENCODE_SECURITY_MODE="${OPENCODE_SECURITY_MODE:-strict}"

# OpenCode runtime model fallback (#55): opt-in. When set, the
# opencode-runtime-fallback plugin + opencode-fallback.jsonc are seeded.
OPENCODE_FALLBACK_MODEL="${OPENCODE_FALLBACK_MODEL:-}"

# Model discovery result (populated by model-discovery.sh, consumed by config-hermes.sh + config-opencode.sh)
DISCOVERED_MODELS=""

# code-server (VS Code in browser)
CODE_SERVER_ENABLED="${CODE_SERVER_ENABLED:-true}"
CODE_SERVER_PORT="${CODE_SERVER_PORT:-8443}"
CODE_SERVER_PASSWORD="${CODE_SERVER_PASSWORD:-}"

SKIP_SKILL_INSTALL="${SKIP_SKILL_INSTALL:-}"

# Browser viewport dimensions (Xvfb geometry + Chromium --window-size).
BROWSER_DISPLAY_WIDTH="${BROWSER_DISPLAY_WIDTH:-1920}"
BROWSER_DISPLAY_HEIGHT="${BROWSER_DISPLAY_HEIGHT:-1080}"

# Helpers
log()  { printf '[entrypoint] %s\n' "$@" >&2; }
warn() { printf '[entrypoint] WARN: %s\n' "$@" >&2; }

# Ensure the Hermes logs directory and agent's log files exist and are writable
# by the runtime user (hermeswebui). Both the gateway and the interactive `hermes`
# CLI open ~/.hermes/logs/agent.log via setup_logging(). Create dir + files
# up-front, make dir setgid + group-writable, and reclaim any root-owned files.
ensure_hermes_logs() {
    local logs="${HERMES_HOME}/logs" f
    mkdir -p "$logs"
    chmod 2775 "$logs" 2>/dev/null || true
    if ! chown "${OPENCODE_USER}:${OPENCODE_USER}" "$logs" 2>&1; then
        warn "chown of ${logs} failed — hermes may hit PermissionError on agent.log"
    fi
    for f in agent.log errors.log gateway.log; do
        [ -e "${logs}/${f}" ] || touch "${logs}/${f}" 2>/dev/null || true
    done
    chown "${OPENCODE_USER}:${OPENCODE_USER}" "${logs}"/*.log 2>/dev/null || true
    chmod 0664 "${logs}"/*.log 2>/dev/null || true
}
