#!/usr/bin/env bats
# ─────────────────────────────────────────────────────────────────────────────
# 36-service-dashboard.bats — service-dashboard.sh: function-level unit test
# Closes T4: the module had only the HTTP-endpoint probe in 17-dashboard.bats;
# this mirrors the disabled-path unit test every other service module has (33).
# ─────────────────────────────────────────────────────────────────────────────

setup() {
    load test_helper/common
}

@test "AC248: service-dashboard.sh module exists and start_dashboard is defined" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        test -f /usr/local/bin/lib/service-dashboard.sh
        source /usr/local/bin/lib/service-dashboard.sh
        declare -f start_dashboard
        echo "OK"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "AC249: start_dashboard returns cleanly and prints disabled when opt-out" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/service-dashboard.sh
        HERMES_DASHBOARD_ENABLED=false start_dashboard 2>&1; echo "EXIT: $?"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"disabled"* ]]
    [[ "$output" == *"EXIT: 0"* ]]
}
