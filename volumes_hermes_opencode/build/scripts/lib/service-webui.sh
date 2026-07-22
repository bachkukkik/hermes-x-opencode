# lib/service-webui.sh - Hermes WebUI service startup - sourced by entrypoint.sh

start_webui() {
    log "--- start_webui ---"
    mkdir -p "${HERMES_WEBUI_STATE_DIR:-${HERMES_HOME}/webui}" \
        "${HERMES_WEBUI_DEFAULT_WORKSPACE:-/workspace}" \
        "${UV_CACHE_DIR:-/uv_cache}"
    chown -R "${OPENCODE_USER}:${OPENCODE_USER}" \
        "${HERMES_WEBUI_STATE_DIR:-${HERMES_HOME}/webui}" 2>/dev/null || true
    # Official docs: set HERMES_WEBUI_GATEWAY_BASE_URL so the WebUI reaches the
    # gateway via HTTP health check rather than polling stale gateway_state.json
    # files (which go stale when HERMES_HOME is profile-scoped). Both run in the
    # same container, so the URL is localhost:HERMES_API_PORT. Also pass the API
    # key so the gateway's api_server accepts the health check requests.
    # Forward GH_TOKEN across the su boundary (#80) so the WebUI-hosted agent's
    # terminal tool has GitHub auth for gh/git push.
    su -s /bin/bash "$OPENCODE_USER" -c "
        export HERMES_WEBUI_GATEWAY_BASE_URL='http://127.0.0.1:${HERMES_API_PORT}'
        export HERMES_WEBUI_GATEWAY_API_KEY='${HERMES_API_KEY}'
        export GH_TOKEN='${GH_TOKEN:-}'
        export GITHUB_TOKEN='${GH_TOKEN:-}'
        /hermeswebui_init.bash
    " &
    local pid=$!
    log "Hermes WebUI started (PID: $pid, gateway: http://127.0.0.1:${HERMES_API_PORT})"
}
