#!/usr/bin/env bats

# Tests for Browser Human-in-the-Loop feature (doc 15)
# When BROWSER_HUMAN_LOOP_ENABLED=true, verifies:
# 1. Xvfb, openbox, x11vnc, websockify, chromium processes are running
# 2. CDP endpoint responds on port 9222
# 3. config.yaml contains browser.cdp_url
# 4. noVNC port 6901 accepts TCP
# 5. All browser processes run as hermeswebui (UID 1000)

setup() {
    load test_helper/common
}

@test "BH1.1: skip if BROWSER_HUMAN_LOOP_ENABLED!=true" {
    skip_if_no_secrets
    [ "${BROWSER_HUMAN_LOOP_ENABLED:-false}" = "true" ] || skip "BROWSER_HUMAN_LOOP_ENABLED!=true"
}

@test "BH1.2: Xvfb process running" {
    skip_if_no_secrets
    [ "${BROWSER_HUMAN_LOOP_ENABLED:-false}" = "true" ] || skip "BROWSER_HUMAN_LOOP_ENABLED!=true"

    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run docker exec "$cid" pgrep -x Xvfb
    [ "$status" -eq 0 ]
}

@test "BH1.3: chromium process running" {
    skip_if_no_secrets
    [ "${BROWSER_HUMAN_LOOP_ENABLED:-false}" = "true" ] || skip "BROWSER_HUMAN_LOOP_ENABLED!=true"

    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run docker exec "$cid" pgrep -f "chromium.*remote-debugging-port"
    [ "$status" -eq 0 ]
}

@test "BH1.4: x11vnc process running" {
    skip_if_no_secrets
    [ "${BROWSER_HUMAN_LOOP_ENABLED:-false}" = "true" ] || skip "BROWSER_HUMAN_LOOP_ENABLED!=true"

    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run docker exec "$cid" pgrep -x x11vnc
    [ "$status" -eq 0 ]
}

@test "BH1.5: websockify process running" {
    skip_if_no_secrets
    [ "${BROWSER_HUMAN_LOOP_ENABLED:-false}" = "true" ] || skip "BROWSER_HUMAN_LOOP_ENABLED!=true"

    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run docker exec "$cid" pgrep -f "websockify.*6901"
    [ "$status" -eq 0 ]
}

@test "BH1.6: CDP endpoint responds on 9222" {
    skip_if_no_secrets
    [ "${BROWSER_HUMAN_LOOP_ENABLED:-false}" = "true" ] || skip "BROWSER_HUMAN_LOOP_ENABLED!=true"

    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    # Chromium CDP returns JSON at /json/version
    run docker exec "$cid" curl -sf http://127.0.0.1:9222/json/version
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Browser"
}

@test "BH1.7: config.yaml has browser.cdp_url" {
    skip_if_no_secrets
    [ "${BROWSER_HUMAN_LOOP_ENABLED:-false}" = "true" ] || skip "BROWSER_HUMAN_LOOP_ENABLED!=true"

    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run docker exec "$cid" grep -A1 '^browser:' /home/hermeswebui/.hermes/config.yaml
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "cdp_url: http://127.0.0.1:9222"
}

@test "BH1.8: noVNC port 6901 accepts TCP" {
    skip_if_no_secrets
    [ "${BROWSER_HUMAN_LOOP_ENABLED:-false}" = "true" ] || skip "BROWSER_HUMAN_LOOP_ENABLED!=true"

    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run docker exec "$cid" timeout 3 bash -c 'echo > /dev/tcp/127.0.0.1/6901'
    [ "$status" -eq 0 ]
}

@test "BH1.9: all browser processes run as hermeswebui (UID 1000)" {
    skip_if_no_secrets
    [ "${BROWSER_HUMAN_LOOP_ENABLED:-false}" = "true" ] || skip "BROWSER_HUMAN_LOOP_ENABLED!=true"

    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    local procs="Xvfb chromium x11vnc openbox"
    for proc in $procs; do
        run docker exec "$cid" pgrep -x "$proc" -o
        if [ "$status" -eq 0 ]; then
            local pid="$output"
            run docker exec "$cid" ps -o uid= -p "$pid"
            [ "$status" -eq 0 ]
            # UID should be 1000 (hermeswebui)
            echo "$output" | grep -q "1000"
        fi
    done
}

# --- TT-13: Browser disabled negative test ---

@test "BH7: browser processes absent when BROWSER_HUMAN_LOOP_ENABLED!=true" {
    # This test runs when the browser feature is NOT enabled (the default).
    # When the feature is enabled, the earlier BH tests cover the positive case.
    [ "${BROWSER_HUMAN_LOOP_ENABLED:-false}" != "true" ] || skip "BROWSER_HUMAN_LOOP_ENABLED=true (covered by BH1.x)"

    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    # Chromium should NOT be running
    run docker exec "$cid" pgrep -f "chromium.*remote-debugging-port"
    [ "$status" -ne 0 ]

    # Xvfb should NOT be running
    run docker exec "$cid" pgrep -x Xvfb
    [ "$status" -ne 0 ]

    # x11vnc should NOT be running
    run docker exec "$cid" pgrep -x x11vnc
    [ "$status" -ne 0 ]
}

@test "BH8: container logs confirm browser disabled message" {
    [ "${BROWSER_HUMAN_LOOP_ENABLED:-false}" != "true" ] || skip "BROWSER_HUMAN_LOOP_ENABLED=true"

    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run bash -c "docker logs '$cid' 2>&1 | grep -c 'Browser human-in-the-loop disabled'"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}
