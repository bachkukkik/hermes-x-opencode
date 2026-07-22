# lib/service-gateway.sh - Hermes gateway service startup - sourced by entrypoint.sh

start_gateway() {
    log "--- start_gateway ---"
    if [ ! -f "$AGENT_DIR/pyproject.toml" ]; then
        warn "hermes-agent not found, skipping gateway start."
        return
    fi
    local hermes_bin=""
    if [ -x /app/venv/bin/hermes ]; then
        hermes_bin=/app/venv/bin/hermes
    elif command -v hermes >/dev/null 2>&1; then
        hermes_bin="$(command -v hermes)"
    else
        warn "hermes CLI not found, skipping gateway start."
        return
    fi
    log "Starting hermes gateway (${HERMES_API_PORT}) via ${hermes_bin}..."
    # Pre-create the logs directory AND log files as the runtime user.
    # HERMES_HOME is bind-mounted from the host, so a root `mkdir` + non-recursive
    # `chown` can silently fail, leaving a root-owned directory. The gateway's
    # setup_logging() then opens RotatingFileHandlers for agent.log, errors.log
    # and gateway.log as hermeswebui and crash-loops with PermissionError.
    if ! su -s /bin/bash "$OPENCODE_USER" -c "mkdir -p '${HERMES_HOME}/logs' && touch '${HERMES_HOME}/logs/agent.log' '${HERMES_HOME}/logs/errors.log' '${HERMES_HOME}/logs/gateway.log' '${HERMES_HOME}/logs/gateway-stdout.log'"; then
        warn "su pre-create failed; falling back to root mkdir + recursive chown"
        mkdir -p "${HERMES_HOME}/logs"
        touch "${HERMES_HOME}/logs/agent.log" "${HERMES_HOME}/logs/errors.log" "${HERMES_HOME}/logs/gateway.log" "${HERMES_HOME}/logs/gateway-stdout.log" 2>/dev/null || true
        chown -R "${OPENCODE_USER}:${OPENCODE_USER}" "${HERMES_HOME}/logs" 2>/dev/null || true
    fi
    # Determine the gateway's HERMES_HOME. When a profile dir exists, use it
    # so the cron scheduler finds profile-scoped jobs (#74).
    local gw_home="$HERMES_HOME"
    if [ -n "${HERMES_GATEWAY_PROFILE:-}" ] && [ -d "${HERMES_HOME}/profiles/${HERMES_GATEWAY_PROFILE}" ]; then
        gw_home="${HERMES_HOME}/profiles/${HERMES_GATEWAY_PROFILE}"
    fi
    local gw_restart_log="${HERMES_HOME}/logs/gateway-restart.log"
    # Forward PLAYWRIGHT_BROWSERS_PATH across the su boundary (su resets the
    # parent env) so the agent's bash-tool children can locate pre-installed
    # chromium when running playwright-cli.
    nohup su -s /bin/bash "$OPENCODE_USER" -c "
        export HERMES_HOME='${gw_home}'
        export PLAYWRIGHT_BROWSERS_PATH='${PLAYWRIGHT_BROWSERS_PATH}'
        export OPENAI_API_KEY='${OPENAI_API_KEY:-}'
        export OPENAI_BASE_URL='${OPENAI_BASE_URL:-}'
        export OPENCODE_ZEN_API_KEY='${OPENCODE_ZEN_API_KEY:-}'
        export OPENCODE_API_KEY='${OPENCODE_API_KEY:-}'
        export HERMES_DELEGATION_MODEL='${HERMES_DELEGATION_MODEL:-}'
        export HERMES_DELEGATION_PROVIDER='${HERMES_DELEGATION_PROVIDER:-}'
        export GH_TOKEN='${GH_TOKEN:-}'
        export GITHUB_TOKEN='${GH_TOKEN:-}'
        while true; do
            ${hermes_bin} gateway run --accept-hooks
            rc=\$?
            echo \"[\$(date)] gateway exited rc=\$rc, restarting in 2s\" >> '${gw_restart_log}'
            sleep 2
        done
    " >> "${HERMES_HOME}/logs/gateway-stdout.log" 2>&1 &
    local pid=$!
    log "Hermes gateway started (PID: $pid, restart-on-exit enabled)"
}
