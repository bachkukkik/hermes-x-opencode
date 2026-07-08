#!/usr/bin/env bats
# ─────────────────────────────────────────────────────────────────────────────
# 32-validate-opencode.bats — validate-opencode.sh: Zen API key validation
# ─────────────────────────────────────────────────────────────────────────────

setup() {
    load test_helper/common
}

@test "AC233: validate-opencode.sh module exists in container" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" test -f /usr/local/bin/lib/validate-opencode.sh
    [ "$status" -eq 0 ]
}

@test "AC234: validate_opencode_zen_key function is defined" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/validate-opencode.sh
        declare -f validate_opencode_zen_key
        echo "OK"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "AC235: validate_opencode_zen_key handles empty key gracefully" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/validate-opencode.sh
        OPENCODE_ZEN_API_KEY=""
        validate_opencode_zen_key 2>&1; echo "EXIT: $?"
    '
    [[ "$output" == *"not set"* ]]
}
