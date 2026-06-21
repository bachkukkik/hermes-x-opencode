#!/usr/bin/env bash
set -euo pipefail

# --- Resolve lib directory relative to this script ---
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"

# --- Source library modules in dependency order ---
source "${LIB_DIR}/constants.sh"
source "${LIB_DIR}/runtime-env.sh"
source "${LIB_DIR}/port-utils.sh"
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
source "${LIB_DIR}/wiki-init.sh"

# =============================================================================
# Main execution sequence
# =============================================================================

# --- Skill installation ---
if [ "${SKIP_SKILL_INSTALL:-0}" != "1" ]; then
    echo "== Copying staged hermes skills..."
    mkdir -p "$HERMES_SKILLS_DIR"
    cp -a /opt/hermes-skills-staging/. "$HERMES_SKILLS_DIR/" 2>/dev/null || true
    if command -v graphify >/dev/null 2>&1; then
        echo "== Registering graphify for hermes..."
        graphify install --platform hermes 2>/dev/null || true
    fi
else
    echo "== Skipping skill staging copy (SKIP_SKILL_INSTALL=1)"
fi

# --- Runtime environment ---
RUNTIME_ENV_MODE="$(detect_runtime_env)"
export RUNTIME_ENV_MODE
if [ -n "${OPENAI_BASE_URL:-}" ]; then
    OPENAI_BASE_URL="$(normalize_base_url_for_local "${OPENAI_BASE_URL}")"
    export OPENAI_BASE_URL
fi

# --- Configuration ---
discover_models
generate_config
generate_opencode_config
validate_opencode_zen_key || true
ensure_agent
init_wiki
append_skills_external_dirs

# --- Seed AGENTS.md into /workspace if not already present ---
if [ -f /usr/local/share/AGENTS.md ] && [ ! -f /workspace/AGENTS.md ]; then
    cp /usr/local/share/AGENTS.md /workspace/AGENTS.md
    chown "${OPENCODE_USER}:${OPENCODE_USER}" /workspace/AGENTS.md
    echo "== Seeded AGENTS.md to /workspace/"
fi

# --- WebUI ---
/hermeswebui_init.bash &
WEBUI_PID=$!
echo "== WebUI init started (PID: $WEBUI_PID)"

wait_for_port 8787 300 "webui"

# --- Seed the righthand-man orchestrator profile (idempotent, needs the venv from WebUI init) ---
seed_righthand_man

# --- Browser human-in-the-loop ---
start_browser_vnc

if [ "${BROWSER_HUMAN_LOOP_ENABLED:-false}" = "true" ]; then
    # Wait for Chromium CDP endpoint (port 9222). Non-fatal: a timeout only logs.
    wait_for_port 9222 30 "chromium CDP" || \
        echo "!! chromium CDP did not become ready within 30s; continuing."
fi

# --- Hermes gateway ---
start_gateway
wait_for_port 8642 60 "hermes gateway"

# --- OpenCode serve ---
start_opencode_serve

if [ "${OPENCODE_SERVE_ENABLED:-false}" = "true" ]; then
    # Boot-time readiness probe for opencode serve. Non-fatal: a timeout only logs.
    wait_for_port 4096 "${OPENCODE_SERVE_BOOT_TIMEOUT:-30}" "opencode serve" || \
        echo "!! opencode serve did not become ready within ${OPENCODE_SERVE_BOOT_TIMEOUT:-30}s; continuing."
fi

# --- Hermes web dashboard ---
start_dashboard
if [ "${HERMES_DASHBOARD_ENABLED:-false}" = "true" ]; then
    # Boot-time readiness probe for hermes dashboard. Non-fatal: a timeout only logs.
    wait_for_port "${HERMES_DASHBOARD_PORT:-9119}" "${HERMES_DASHBOARD_BOOT_TIMEOUT:-30}" "hermes dashboard" || \
        echo "!! hermes dashboard did not become ready within ${HERMES_DASHBOARD_BOOT_TIMEOUT:-30}s; continuing."
fi

# --- Keep container alive ---
echo "== All services running. Waiting..."
wait
echo "!! A background process exited. Container shutting down."
