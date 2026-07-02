# lib/port-utils.sh - TCP port readiness polling with optional health endpoint - sourced by entrypoint.sh

# Poll a TCP port until it accepts a connection or the timeout is reached.
# Optionally checks an HTTP health endpoint before declaring the port ready.
# Uses curl for health checks and nc -z as fallback (more reliable than /dev/tcp).
# Does NOT exit on timeout — caller decides.
#
# Args:
#   $1: port number
#   $2: timeout in seconds (default: 120)
#   $3: label used in log lines (default: "port $1")
#   $4: HTTP health path to check (default: /health) — set to empty string to skip
#
# Returns:
#   0 if the port is ready within the timeout
#   1 on timeout
wait_for_port() {
    local port=$1
    local max_wait=${2:-120}
    local label=${3:-"port $port"}
    local health_path=${4:-/health}
    local elapsed=0

    log "Waiting for $label on :$port (timeout: ${max_wait}s)..."
    while true; do
        if [ -n "$health_path" ] && curl -sf "http://localhost:${port}${health_path}" >/dev/null 2>&1; then
            break
        fi
        if nc -z localhost "$port" 2>/dev/null; then
            if [ -n "$health_path" ]; then
                log "$label port :$port is up (health endpoint $health_path not available)"
            fi
            break
        fi
        sleep 2
        elapsed=$((elapsed + 2))
        if [ "$elapsed" -ge "$max_wait" ]; then
            warn "Timeout waiting for $label on :$port after ${max_wait}s"
            return 1
        fi
    done
    log "$label ready on :$port (${elapsed}s)"
}
