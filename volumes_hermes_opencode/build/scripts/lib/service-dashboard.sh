# lib/service-dashboard.sh - Hermes web dashboard (machine-management UI) startup - sourced by entrypoint.sh

# Start the Hermes web dashboard, the machine-management UI (config / api-keys /
# skills / sessions) on :9119. This is a SEPARATE surface from the WebUI chat
# frontend on :8787. Opt-in via HERMES_DASHBOARD_ENABLED=true.
#
# SECURITY: --insecure is REQUIRED to bind the dashboard to 0.0.0.0 (non-localhost)
# inside the container. This exposes the management surface on the container
# network — the dashboard manages API keys — so keep it INTERNAL ONLY. Do NOT
# publish port 9119 to the host without an auth/termination layer in front.
start_dashboard() {
    local enabled="${HERMES_DASHBOARD_ENABLED:-false}"
    if [ "$enabled" != "true" ]; then
        echo "[entrypoint] hermes dashboard disabled (HERMES_DASHBOARD_ENABLED=${enabled})"
        return 0
    fi
    if [ ! -f /app/venv/bin/hermes ]; then
        echo "!! hermes CLI not in venv, skipping dashboard."
        return 0
    fi

    # The web dist was built at image time and staged at /opt/hermes_cli_web_dist.
    # /app/venv is created at runtime by the WebUI init; by the time start_dashboard
    # runs (after :8787 is up) the venv exists. Copy the staged dist into the live
    # venv's hermes_cli package so `hermes dashboard --skip-build` serves a UI.
    # Idempotent: only copies when the venv hermes_cli lacks web_dist.
    local venv_hermes_cli="/app/venv/lib/python3.12/site-packages/hermes_cli"
    if [ -d "$venv_hermes_cli" ] && [ ! -d "$venv_hermes_cli/web_dist" ] && [ -d /opt/hermes_cli_web_dist ]; then
        cp -r /opt/hermes_cli_web_dist "$venv_hermes_cli/web_dist"
        echo "== Installed dashboard web_dist into $venv_hermes_cli/web_dist"
    fi

    local host="${HERMES_DASHBOARD_HOST:-0.0.0.0}"
    local port="${HERMES_DASHBOARD_PORT:-9119}"

    # Ensure log directory exists (owned by hermeswebui)
    mkdir -p "${HERMES_HOME}/logs"
    chown "${OPENCODE_USER}:${OPENCODE_USER}" "${HERMES_HOME}/logs"

    echo "== Starting hermes dashboard on :${port} (host: ${host}, user: ${OPENCODE_USER})..."

    # Restart-loop supervisor (mirrors service-gateway.sh). --skip-build serves a
    # pre-built web dist without npm; see docs/21-dashboard.md for the dist
    # prerequisite. host/port are expanded by this shell; \$?/\$(date) expand in
    # the su subshell.
    nohup su -s /bin/bash "$OPENCODE_USER" -c "
        while true; do
            /app/venv/bin/hermes dashboard --host $host --port $port --insecure --skip-build --no-open
            rc=\$?
            echo \"[\$(date)] dashboard exited rc=\$rc, restarting in 2s\" >> \"${HERMES_HOME}/logs/dashboard-restart.log\"
            sleep 2
        done
    " >> "${HERMES_HOME}/logs/dashboard-stdout.log" 2>&1 &

    echo "== Dashboard started on :$port (PID: $!)"
}
