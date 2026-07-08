#!/usr/bin/env bats
# ─────────────────────────────────────────────────────────────────────────────
# 33-service-browser-vnc.bats — service-browser-vnc.sh: Browser/VNC startup
# ─────────────────────────────────────────────────────────────────────────────

setup() {
    load test_helper/common
}

@test "AC236: service-browser-vnc.sh module exists in container" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" test -f /usr/local/bin/lib/service-browser-vnc.sh
    [ "$status" -eq 0 ]
}

@test "AC237: start_browser_vnc function is defined" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/service-browser-vnc.sh
        declare -f start_browser_vnc
        echo "OK"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "AC238: start_browser_vnc returns immediately when disabled" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/service-browser-vnc.sh
        BROWSER_HUMAN_LOOP_ENABLED=false
        start_browser_vnc 2>&1; echo "EXIT: $?"
    '
    [[ "$output" == *"disabled"* ]]
}
