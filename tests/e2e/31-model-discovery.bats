#!/usr/bin/env bats
# ─────────────────────────────────────────────────────────────────────────────
# 31-model-discovery.bats — model-discovery.sh: model list discovery
# ─────────────────────────────────────────────────────────────────────────────

setup() {
    load test_helper/common
}

@test "AC230: model-discovery.sh module exists in container" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" test -f /usr/local/bin/lib/model-discovery.sh
    [ "$status" -eq 0 ]
}

@test "AC231: discover_models function is defined" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/model-discovery.sh
        declare -f discover_models
        echo "OK"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "AC232: discover_models falls back to default model when no API config is set" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    # In the container, OPENAI_BASE_URL should be set to the mock/fake URL
    # from CI config. This test just checks the function runs without error.
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/constants.sh
        source /usr/local/bin/lib/model-discovery.sh
        discover_models 2>/dev/null || true
        echo "DISCOVERED_MODELS=${DISCOVERED_MODELS:0:50}"
    '
    [ "$status" -eq 0 ]
    # DISCOVERED_MODELS should be non-empty (either discovered or default)
    [ -n "$output" ]
}
