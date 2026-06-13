# lib/service-opencode.sh - OpenCode serve service startup - sourced by entrypoint.sh

start_opencode_serve() {
    local enabled="${OPENCODE_SERVE_ENABLED:-false}"
    if [ "$enabled" != "true" ]; then
        echo "[entrypoint] opencode serve disabled (OPENCODE_SERVE_ENABLED=${enabled})"
        return 0
    fi
    if ! command -v opencode >/dev/null 2>&1; then
        echo "!! opencode not found, skipping serve start."
        return 0
    fi
    local password="${OPENCODE_SERVER_PASSWORD:-}"
    if [ -z "$password" ]; then
        password="$(openssl rand -hex 16)"
        echo "== Generated random OPENCODE_SERVER_PASSWORD: $password"
        export OPENCODE_SERVER_PASSWORD="$password"
    fi
    echo "$password" > /tmp/opencode-server-password
    echo "$password" > "${HERMES_HOME}/opencode_server_password"
    chown "$OPENCODE_USER":"$OPENCODE_USER" /tmp/opencode-server-password "${HERMES_HOME}/opencode_server_password"
    local workdir="${OPENCODE_USER_HOME}"
    # Ensure ~/.local/state exists and is owned by the user (opencode serve writes state here)
    mkdir -p "${OPENCODE_USER_HOME}/.local/state"
    chown "${OPENCODE_USER}:${OPENCODE_USER}" "${OPENCODE_USER_HOME}/.local/state"
    local opencode_key="${OPENCODE_API_KEY:-}"
    echo "== Starting opencode serve on :4096 (workdir: $workdir, user: $OPENCODE_USER)..."
    su -s /bin/bash "$OPENCODE_USER" -c "OPENCODE_SERVER_PASSWORD='$password' OPENCODE_API_KEY='$opencode_key' opencode serve --port 4096 --hostname 0.0.0.0" &
    echo "== OpenCode serve started (PID: $!)"
}
