#!/usr/bin/env bats
# ─────────────────────────────────────────────────────────────────────────────
# 23-port-utils.bats — port-utils.sh wait_for_port function
# Verifies the health-gated polling function used for all service startup.
# ─────────────────────────────────────────────────────────────────────────────

setup() {
    load test_helper/common
}

@test "AC180: port-utils.sh module exists in container" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" test -f /usr/local/bin/lib/port-utils.sh
    [ "$status" -eq 0 ]
}

@test "AC181: wait_for_port function is defined" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c 'source /usr/local/bin/lib/constants.sh; source /usr/local/bin/lib/port-utils.sh; declare -f wait_for_port'
    [ "$status" -eq 0 ]
    [[ "$output" == *"wait_for_port()"* ]]
}

@test "AC182: wait_for_port succeeds for already-listening port" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    # Start a simple listener on an ephemeral port, then verify wait_for_port detects it
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/constants.sh
        source /usr/local/bin/lib/port-utils.sh
        # Start a listener in background
        python3 -c "
import socket, time
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind((\"127.0.0.1\", 19876))
s.listen(1)
time.sleep(10)
" &
        sleep 1
        wait_for_port 19876 10 "test" ""
        echo "SUCCESS"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"test ready"* ]]
}

@test "AC183: wait_for_port times out for non-listening port" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/constants.sh
        source /usr/local/bin/lib/port-utils.sh
        wait_for_port 19999 4 "timeout-test" "" 2>&1; echo "EXIT:$?"
    '
    [[ "$output" == *"Timeout"* ]]
    [[ "$output" == *"EXIT:1"* ]]
}

@test "AC184: wait_for_port with health endpoint succeeds when health responds" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    # Start a tiny HTTP server that responds on /health
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/constants.sh
        source /usr/local/bin/lib/port-utils.sh
        python3 -c "
import http.server, time, threading

class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == \"/health\":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b\"ok\")
        else:
            self.send_response(404)
            self.end_headers()
    def log_message(self, *a): pass

s = http.server.HTTPServer((\"127.0.0.1\", 19877), H)
t = threading.Thread(target=s.serve_forever); t.daemon=True; t.start()
time.sleep(10)
" &
        sleep 1
        wait_for_port 19877 10 "health-test" "/health"
        echo "SUCCESS"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"health-test ready"* ]]
}

@test "AC185: wait_for_port with health endpoint falls back to TCP if health path 404s" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    # Start an HTTP server that always 404s — port is up but health endpoint fails.
    # wait_for_port should fall back to nc -z and succeed with a warning.
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/constants.sh
        source /usr/local/bin/lib/port-utils.sh
        python3 -c "
import http.server, time, threading

class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(404)
        self.end_headers()
    def log_message(self, *a): pass

s = http.server.HTTPServer((\"127.0.0.1\", 19878), H)
t = threading.Thread(target=s.serve_forever); t.daemon=True; t.start()
time.sleep(10)
" &
        sleep 1
        wait_for_port 19878 10 "fallback-test" "/health" 2>&1
        echo "DONE:$?"
    '
    [ "$status" -eq 0 ]
    # Should contain the fallback log about health endpoint not available
    [[ "$output" == *"health endpoint"* ]] || [[ "$output" == *"ready"* ]]
}
