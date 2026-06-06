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
