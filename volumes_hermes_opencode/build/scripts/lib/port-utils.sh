# lib/port-utils.sh - TCP port readiness polling - sourced by entrypoint.sh

# Poll a TCP port until it accepts a connection or the timeout is reached.
# Uses bash /dev/tcp (no external deps). Does NOT exit on timeout — caller decides.
#
# Args:
#   $1: port number (default: 4096)
#   $2: timeout in seconds (default: 30)
#   $3: label used in log lines (default: "service")
#
# Returns:
#   0 if the port accepts a connection within the timeout
#   1 on timeout
wait_for_port() {
    local port="${1:-4096}"
    local timeout="${2:-30}"
    local label="${3:-service}"
    local elapsed=0
    echo "== ${label}: waiting for :${port} (0/${timeout}s)"
    while ! (exec 3<>"/dev/tcp/127.0.0.1/${port}") >/dev/null 2>&1; do
        sleep 5
        elapsed=$((elapsed + 5))
        if [ "$elapsed" -ge "$timeout" ]; then
            echo "!! ${label}: timeout waiting for :${port} after ${timeout}s"
            return 1
        fi
        echo "== ${label}: waiting for :${port} (${elapsed}/${timeout}s)"
    done
    echo "== ${label}: port ${port} ready (after ${elapsed}s)"
    return 0
}
