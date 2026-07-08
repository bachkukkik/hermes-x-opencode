#!/usr/bin/env bash
set -euo pipefail

# --- Resolve lib directory relative to this script ---
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"

# --- Source library modules in dependency order ---
source "${LIB_DIR}/constants.sh"
source "${LIB_DIR}/runtime-env.sh"
source "${LIB_DIR}/port-utils.sh"
source "${LIB_DIR}/mock-llm-server.sh"
source "${LIB_DIR}/seed-volumes.sh"
source "${LIB_DIR}/agent-setup.sh"
source "${LIB_DIR}/model-discovery.sh"
source "${LIB_DIR}/config-hermes.sh"
source "${LIB_DIR}/config-opencode.sh"
source "${LIB_DIR}/validate-opencode.sh"
source "${LIB_DIR}/service-gateway.sh"
source "${LIB_DIR}/service-opencode.sh"
source "${LIB_DIR}/service-dashboard.sh"
source "${LIB_DIR}/profile-righthand-man.sh"
source "${LIB_DIR}/service-browser-vnc.sh"
source "${LIB_DIR}/service-webui.sh"
source "${LIB_DIR}/symlink-cleanup.sh"
source "${LIB_DIR}/wiki-init.sh"

# =============================================================================
# Main execution sequence
# =============================================================================

# --- Skill installation ---
seed_volumes

# --- Runtime environment ---
RUNTIME_ENV_MODE="$(detect_runtime_env)"
export RUNTIME_ENV_MODE
if [ -n "${OPENAI_BASE_URL:-}" ]; then
    OPENAI_BASE_URL="$(normalize_base_url_for_local "${OPENAI_BASE_URL}")"
    export OPENAI_BASE_URL
fi

# --- Configuration ---
# Start mock LLM server if OPENAI_BASE_URL points to localhost:4000 (CI fallback)
if [ "${OPENAI_BASE_URL:-}" = "http://localhost:4000" ]; then
    start_mock_llm
fi

discover_models
generate_config
generate_opencode_config
validate_opencode_zen_key || true
cleanup_symlink_loops
ensure_agent
init_wiki
append_skills_external_dirs

# --- Seed AGENTS.md into /workspace if not already present ---
if [ -f /usr/local/share/AGENTS.md ] && [ ! -f /workspace/AGENTS.md ]; then
    cp /usr/local/share/AGENTS.md /workspace/AGENTS.md
    chown "${OPENCODE_USER}:${OPENCODE_USER}" /workspace/AGENTS.md
    log "Seeded AGENTS.md to /workspace/"
fi

# --- WebUI ---
start_webui

wait_for_port 8787 120 "Hermes WebUI"

# Fix /app/venv ownership so `hermes update` works from inside the container.
# /hermeswebui_init.bash creates the venv as root; the hermeswebui user needs
# write access to upgrade packages in-place.
chown -R "${OPENCODE_USER}:${OPENCODE_USER}" /app/venv/ 2>/dev/null || true
chown -R "${OPENCODE_USER}:${OPENCODE_USER}" /uv_cache/ 2>/dev/null || true

# --- Seed the righthand-man orchestrator profile (idempotent, needs the venv from WebUI init) ---
seed_righthand_man

# --- Browser human-in-the-loop ---
start_browser_vnc

if [ "${BROWSER_HUMAN_LOOP_ENABLED:-false}" = "true" ]; then
    # Wait for Chromium CDP endpoint (port 9222). Non-fatal: a timeout only logs.
    wait_for_port 9222 30 "chromium CDP" "/json/version" || \
        warn "chromium CDP did not become ready within 30s; continuing."
fi

# --- Hermes gateway ---
chown -R "${OPENCODE_USER}:${OPENCODE_USER}" "$HERMES_HOME" 2>/dev/null || true

start_gateway
wait_for_port 8642 90 "Hermes Gateway"

# --- OpenCode serve ---
mkdir -p "${OPENCODE_USER_HOME}/.local/share" "${OPENCODE_USER_HOME}/.local/state"
chown -R "${OPENCODE_USER}:${OPENCODE_USER}" "${OPENCODE_USER_HOME}/.local" 2>/dev/null || true

start_opencode_serve

if [ "${OPENCODE_SERVE_ENABLED:-false}" = "true" ]; then
    # Boot-time readiness probe for opencode serve. Non-fatal: a timeout only logs.
    wait_for_port 4096 "${OPENCODE_SERVE_BOOT_TIMEOUT:-30}" "opencode serve" "/health" || \
        warn "opencode serve did not become ready within ${OPENCODE_SERVE_BOOT_TIMEOUT:-30}s; continuing."
fi

# --- Hermes web dashboard ---
start_dashboard
if [ "${HERMES_DASHBOARD_ENABLED:-false}" = "true" ]; then
    # Boot-time readiness probe for hermes dashboard. Non-fatal: a timeout only logs.
    wait_for_port "${HERMES_DASHBOARD_PORT:-9119}" "${HERMES_DASHBOARD_BOOT_TIMEOUT:-30}" "hermes dashboard" "/" || \
        warn "hermes dashboard did not become ready within ${HERMES_DASHBOARD_BOOT_TIMEOUT:-30}s; continuing."
fi

# --- Keep container alive ---
log "All services running. Waiting..."
wait
warn "A background process exited. Container shutting down."
