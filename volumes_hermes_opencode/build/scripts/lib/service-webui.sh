# lib/service-webui.sh - Hermes WebUI service startup - sourced by entrypoint.sh

# Start the Hermes WebUI frontend (chat UI on :8787). Ensures state/workspace/cache
# directories exist with correct ownership, then launches /hermeswebui_init.bash
# under the $OPENCODE_USER account in the background.
start_webui() {
    echo "== Starting Hermes WebUI..."
    mkdir -p "${HERMES_WEBUI_STATE_DIR:-${HERMES_HOME}/webui}" \
        "${HERMES_WEBUI_DEFAULT_WORKSPACE:-/workspace}" \
        "${UV_CACHE_DIR:-/uv_cache}"
    chown -R "${OPENCODE_USER}:${OPENCODE_USER}" \
        "${HERMES_WEBUI_STATE_DIR:-${HERMES_HOME}/webui}" 2>/dev/null || true
    su -s /bin/bash "$OPENCODE_USER" -c "/hermeswebui_init.bash" &
    local pid=$!
    echo "== Hermes WebUI started (PID: $pid)"
}
