#!/usr/bin/env bats
# ─────────────────────────────────────────────────────────────────────────────
# 30-service-opencode.bats — service-opencode.sh: OpenCode serve startup
# ─────────────────────────────────────────────────────────────────────────────

setup() {
    load test_helper/common
}

@test "AC228: service-opencode.sh module exists in container" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" test -f /usr/local/bin/lib/service-opencode.sh
    [ "$status" -eq 0 ]
}

@test "AC229: start_opencode_serve function is defined" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/service-opencode.sh
        declare -f start_opencode_serve
        echo "OK"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}
