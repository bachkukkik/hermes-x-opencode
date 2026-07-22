# lib/service-opencode.sh - OpenCode serve service startup - sourced by entrypoint.sh

start_opencode_serve() {
    log "--- start_opencode_serve ---"
    local enabled="${OPENCODE_SERVE_ENABLED:-false}"
    if [ "$enabled" != "true" ]; then
        log "opencode serve disabled (OPENCODE_SERVE_ENABLED=${enabled})"
        return 0
    fi
    if ! command -v opencode >/dev/null 2>&1; then
        warn "opencode not found, skipping serve start."
        return 0
    fi
    local password="${OPENCODE_SERVER_PASSWORD:-}"
    if [ -z "$password" ]; then
        password="$(openssl rand -hex 16)"
        log "Generated random OPENCODE_SERVER_PASSWORD"
        export OPENCODE_SERVER_PASSWORD="$password"
    fi
    # Write password file via su as hermeswebui so the file is owned by the
    # runtime user and stays overwritable on later boots. Best-effort under
    # set -e (rm -f before, || true on failures).
    local pw_file="/tmp/opencode-server-password"
    rm -f "$pw_file" 2>/dev/null || true
    if ! su -s /bin/bash "$OPENCODE_USER" -c "umask 077 && echo '$password' > '$pw_file'"; then
        warn "su password-file write failed; falling back to root write + chown"
        echo "$password" > "$pw_file" 2>/dev/null || true
        chown "$OPENCODE_USER:$OPENCODE_USER" "$pw_file" 2>/dev/null || true
    fi
    # Also persist to HERMES_HOME so clients can read from a stable path.
    local hermes_pw_file="${HERMES_HOME}/opencode_server_password"
    if ! su -s /bin/bash "$OPENCODE_USER" -c "umask 077 && echo '$password' > '$hermes_pw_file'"; then
        echo "$password" > "$hermes_pw_file" 2>/dev/null || true
        chown "$OPENCODE_USER:$OPENCODE_USER" "$hermes_pw_file" 2>/dev/null || true
    fi
    local workdir="${OPENCODE_USER_HOME}"
    # Ensure ~/.local/state exists and is owned by the user (opencode serve writes state here)
    mkdir -p "${OPENCODE_USER_HOME}/.local/state"
    chown "${OPENCODE_USER}:${OPENCODE_USER}" "${OPENCODE_USER_HOME}/.local/state"
    log "Starting opencode serve on :${OPENCODE_SERVE_PORT} (user: ${OPENCODE_USER})..."
    # Also pass OPENAI_API_KEY + OPENAI_BASE_URL so the litellm provider block
    # PLAYWRIGHT_BROWSERS_PATH is forwarded for the same reason so opencode-spawned
    # playwright-cli invocations can locate the pre-installed chromium.
    # OPENCODE_API_KEY is forwarded so the {env:OPENCODE_API_KEY} placeholder in the
    # opencode provider block resolves (parity with OPENCODE_ZEN_API_KEY, #77).
    # GH_TOKEN/GITHUB_TOKEN are forwarded so opencode-spawned shells can run `gh`
    # and `git push` over HTTPS (#80).
    su -s /bin/bash "$OPENCODE_USER" -c \
      "OPENCODE_SERVER_PASSWORD='$password' \
       OPENCODE_ZEN_API_KEY='${OPENCODE_ZEN_API_KEY:-}' \
       OPENCODE_API_KEY='${OPENCODE_API_KEY:-}' \
       OPENAI_API_KEY='${OPENAI_API_KEY:-}' \
       OPENAI_BASE_URL='${OPENAI_BASE_URL:-}' \
       GH_TOKEN='${GH_TOKEN:-}' \
       GITHUB_TOKEN='${GH_TOKEN:-}' \
       PLAYWRIGHT_BROWSERS_PATH='${PLAYWRIGHT_BROWSERS_PATH}' \
       opencode serve --port ${OPENCODE_SERVE_PORT} --hostname 0.0.0.0" &
    local pid=$!
    log "OpenCode serve started (PID: $pid)"
}
