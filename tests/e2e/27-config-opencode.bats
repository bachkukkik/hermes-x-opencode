#!/usr/bin/env bats
# ─────────────────────────────────────────────────────────────────────────────
# 27-config-opencode.bats — config-opencode.sh: OpenCode config generation
# ─────────────────────────────────────────────────────────────────────────────

setup() {
    load test_helper/common
}

@test "AC217: config-opencode.sh module exists in container" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" test -f /usr/local/bin/lib/config-opencode.sh
    [ "$status" -eq 0 ]
}

@test "AC218: PROVIDER_PREFIXES is exported with opencode and litellm" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/config-opencode.sh
        echo "$PROVIDER_PREFIXES"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"opencode"* ]]
    [[ "$output" == *"litellm"* ]]
}

@test "AC219: normalize_model_id passes through prefixed models" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/config-opencode.sh
        echo "opencode/deepseek-v4: $(normalize_model_id opencode/deepseek-v4)"
        echo "litellm/gpt-4o: $(normalize_model_id litellm/gpt-4o)"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"opencode/deepseek-v4: opencode/deepseek-v4"* ]]
    [[ "$output" == *"litellm/gpt-4o: litellm/gpt-4o"* ]]
}

@test "AC220: generate_opencode_config function is defined" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/config-opencode.sh
        declare -f generate_opencode_config
        echo "OK"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}
