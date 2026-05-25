#!/usr/bin/env bats

setup() {
    load test_helper/common
}

@test "AC2: container starts and is running" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    local state
    state=$(docker inspect --format='{{.State.Running}}' "$cid")
    [ "$state" = "true" ]
}

@test "AC3: healthcheck reports healthy" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    local status
    status=$(docker inspect --format='{{.State.Health.Status}}' "$cid")
    [ "$status" = "healthy" ]
}

@test "AC4: WebUI health endpoint returns 200" {
    run curl -sf "$(webui_base)/health"
    [ "$status" -eq 0 ]
}
