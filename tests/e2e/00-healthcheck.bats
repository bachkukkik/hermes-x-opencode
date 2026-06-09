#!/usr/bin/env bats

setup() {
    load test_helper/common
}

@test "AC0.1: Hermes WebUI health endpoint returns 200" {
    run curl -sf --max-time 3 "$(webui_base)/health"
    [ "$status" -eq 0 ]
}

@test "AC0.2: Hermes Gateway health endpoint returns 200" {
    run curl -sf --max-time 3 "$(gateway_base)/health"
    [ "$status" -eq 0 ]
}

@test "AC0.3: OpenCode Serve endpoint is reachable" {
    [ "${OPENCODE_SERVE_ENABLED:-false}" = "true" ] || skip "OPENCODE_SERVE_ENABLED!=true"
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c 'timeout 3 bash -c "echo > /dev/tcp/127.0.0.1/4096"'
    [ "$status" -eq 0 ]
}

@test "healthcheck.sh exits 0 when all services are healthy" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash /usr/local/bin/healthcheck.sh
    [ "$status" -eq 0 ]
}

@test "ACX: deep health endpoint returns extended status" {
    local basic deep
    basic=$(curl -sf --max-time 3 "$(webui_base)/health" 2>/dev/null || echo "")
    deep=$(curl -sf --max-time 3 "$(webui_base)/health?deep=1" 2>/dev/null || echo "")
    [ -n "$deep" ]
    # Deep response should contain strictly more keys than basic
    local basic_count deep_count
    basic_count=$(echo "$basic" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0)
    deep_count=$(echo "$deep" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0)
    [ "$deep_count" -gt "$basic_count" ]
}
