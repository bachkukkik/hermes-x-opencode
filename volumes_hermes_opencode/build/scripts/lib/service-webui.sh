# lib/service-webui.sh - Hermes WebUI service startup - sourced by entrypoint.sh

# Start the Hermes WebUI frontend (chat UI on :8787). Ensures state/workspace/cache
# directories exist with correct ownership, then launches /hermeswebui_init.bash
# in the background. Runs as PID1 (root) — the WebUI init script handles its own
# user setup internally, so do NOT wrap in su (avoids UID mismatch in CI).
start_webui() {
    log "Starting Hermes WebUI..."
    mkdir -p "${HERMES_WEBUI_STATE_DIR:-${HERMES_HOME}/webui}" \
        "${HERMES_WEBUI_DEFAULT_WORKSPACE:-/workspace}" \
        "${UV_CACHE_DIR:-/uv_cache}"
    chown -R "${OPENCODE_USER}:${OPENCODE_USER}" \
        "${HERMES_WEBUI_STATE_DIR:-${HERMES_HOME}/webui}" 2>/dev/null || true
    /hermeswebui_init.bash &
    local pid=$!
    log "Hermes WebUI started (PID: $pid)"
}
