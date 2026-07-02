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
OPENCODE_SKILLS_DIR="${OPENCODE_USER_HOME}/.config/opencode/skills"

# Wiki path (used by wiki-init.sh)
WIKI_DIR="${WIKI_PATH:-${HERMES_HOME}/wiki}"

# Runtime config (from env, with defaults)
OPENAI_BASE_URL="${OPENAI_BASE_URL:-}"
OPENAI_API_KEY="${OPENAI_API_KEY:-}"
OPENAI_DEFAULT_MODEL="${OPENAI_DEFAULT_MODEL:-openai/gpt-4o}"
OPENAI_SMALL_MODEL="${OPENAI_SMALL_MODEL:-}"
OPENAI_CONTEXT_LENGTH="${OPENAI_CONTEXT_LENGTH:-200000}"
OPENAI_IMAGE_MODEL="${OPENAI_IMAGE_MODEL:-gpt-image-2}"

# Fine-grained model overrides (fall back to OPENAI_* if unset)
HERMES_DEFAULT_MODEL="${HERMES_DEFAULT_MODEL:-${OPENAI_DEFAULT_MODEL}}"
OPENCODE_DEFAULT_MODEL="${OPENCODE_DEFAULT_MODEL:-${OPENAI_DEFAULT_MODEL}}"
OPENCODE_SMALL_MODEL="${OPENCODE_SMALL_MODEL:-${OPENAI_SMALL_MODEL:-${OPENAI_DEFAULT_MODEL}}}"

HERMES_API_KEY="${HERMES_API_KEY:-}"
HERMES_API_PORT="${HERMES_API_PORT:-8642}"
HERMES_COMPRESSION_THRESHOLD="${HERMES_COMPRESSION_THRESHOLD:-}"

# Runtime autonomy knobs (#53): YOLO mode disables approval prompts and enables
# the delegation subagent loop; max_iterations caps that loop.
HERMES_YOLO_MODE="${HERMES_YOLO_MODE:-1}"
HERMES_DELEGATION_MAX_ITERATIONS="${HERMES_DELEGATION_MAX_ITERATIONS:-50}"

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

# Browser viewport dimensions (Xvfb geometry + Chromium --window-size).
BROWSER_DISPLAY_WIDTH="${BROWSER_DISPLAY_WIDTH:-1920}"
BROWSER_DISPLAY_HEIGHT="${BROWSER_DISPLAY_HEIGHT:-1080}"

# Helpers
log()  { printf '[entrypoint] %s\n' "$@" >&2; }
warn() { printf '[entrypoint] WARN: %s\n' "$@" >&2; }
