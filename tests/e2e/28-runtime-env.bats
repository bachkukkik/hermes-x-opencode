#!/usr/bin/env bats
# ─────────────────────────────────────────────────────────────────────────────
# 28-runtime-env.bats — runtime-env.sh: environment detection helpers
# ─────────────────────────────────────────────────────────────────────────────

setup() {
    load test_helper/common
}

@test "AC221: runtime-env.sh module exists in container" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" test -f /usr/local/bin/lib/runtime-env.sh
    [ "$status" -eq 0 ]
}

@test "AC222: detect_runtime_env and normalize_base_url_for_local are defined" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/runtime-env.sh
        declare -f detect_runtime_env
        declare -f normalize_base_url_for_local
        echo "OK"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "AC223: detect_runtime_env respects RUNTIME_ENV override" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/runtime-env.sh
        RUNTIME_ENV=local
        result=$(detect_runtime_env 2>/dev/null)
        RUNTIME_ENV_MODE=$result
        echo "mode=$result"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"mode=local"* ]]
}

@test "AC224: normalize_base_url_for_local replaces host.docker.internal in local mode" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/runtime-env.sh
        RUNTIME_ENV_MODE=local
        result=$(normalize_base_url_for_local "http://host.docker.internal:4000/v1")
        echo "result=$result"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"result=http://localhost:4000/v1"* ]]
}
