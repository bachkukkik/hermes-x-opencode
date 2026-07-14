# lib/service-gateway.sh - Hermes gateway service startup - sourced by entrypoint.sh

start_gateway() {
    if [ ! -f "$AGENT_DIR/pyproject.toml" ]; then
        echo "!! hermes-agent not found, skipping gateway start."
        return
    fi
    if [ ! -f /app/venv/bin/hermes ]; then
        echo "!! hermes CLI not in venv, skipping gateway start."
        return
    fi
    echo "== Starting hermes gateway (api_server on :8642)..."
    mkdir -p "${HERMES_HOME}/logs"
    chown "${OPENCODE_USER}:${OPENCODE_USER}" "${HERMES_HOME}/logs"
    # Forward PLAYWRIGHT_BROWSERS_PATH across the su boundary (su resets the parent
    # env) so the agent's bash-tool children — which inherit this gateway process's
    # environment — can locate the pre-installed chromium when running playwright-cli.
    nohup su -s /bin/bash "$OPENCODE_USER" -c "
        export PLAYWRIGHT_BROWSERS_PATH='${PLAYWRIGHT_BROWSERS_PATH}'
        while true; do
            /app/venv/bin/hermes gateway run --accept-hooks
            rc=\$?
            echo \"[\$(date)] gateway exited rc=\$rc, restarting in 2s\" >> \"\${HERMES_HOME}/logs/gateway-restart.log\"
            sleep 2
        done
    " >> "${HERMES_HOME}/logs/gateway-stdout.log" 2>&1 &
    echo "== Gateway started (PID: $!)"
}
