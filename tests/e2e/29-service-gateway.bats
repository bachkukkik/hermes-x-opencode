#!/usr/bin/env bats
# ─────────────────────────────────────────────────────────────────────────────
# 29-service-gateway.bats — service-gateway.sh: Hermes gateway startup
# ─────────────────────────────────────────────────────────────────────────────

setup() {
    load test_helper/common
}

@test "AC225: service-gateway.sh module exists in container" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" test -f /usr/local/bin/lib/service-gateway.sh
    [ "$status" -eq 0 ]
}

@test "AC226: start_gateway function is defined" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/service-gateway.sh
        declare -f start_gateway
        echo "OK"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "AC227: gateway log directory exists" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" test -d /home/hermeswebui/.hermes/logs
    [ "$status" -eq 0 ]
}
