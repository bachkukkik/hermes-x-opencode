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
    run curl -sf --max-time 3 "$(opencode_base)/"
    [ "$status" -eq 0 ]
}
