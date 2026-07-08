#!/usr/bin/env bats
# ─────────────────────────────────────────────────────────────────────────────
# 26-config-hermes.bats — config-hermes.sh: hermes config.yaml generation
# ─────────────────────────────────────────────────────────────────────────────

setup() {
    load test_helper/common
}

@test "AC213: config-hermes.sh module exists in container" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" test -f /usr/local/bin/lib/config-hermes.sh
    [ "$status" -eq 0 ]
}

@test "AC214: resolve_ctx_len returns pinned values for known model families" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/config-hermes.sh
        echo "deepseek-v4: $(resolve_ctx_len deepseek-v4)"
        echo "gpt-4o: $(resolve_ctx_len gpt-4o)"
        echo "gemini: $(resolve_ctx_len gemini)"
        echo "glm-5.2: $(resolve_ctx_len glm-5.2)"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"deepseek-v4: 1000000"* ]]
    [[ "$output" == *"gpt-4o: 128000"* ]]
    [[ "$output" == *"gemini: 1048576"* ]]
    [[ "$output" == *"glm-5.2: 1048576"* ]]
}

@test "AC215: resolve_ctx_len returns empty for unknown models" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/config-hermes.sh
        result=$(resolve_ctx_len "unknown-model-xyz")
        echo "result=[${result}]"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"result=[]"* ]]
}

@test "AC216: generate_config and append_skills_external_dirs functions are defined" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/config-hermes.sh
        declare -f generate_config
        declare -f append_skills_external_dirs
        echo "OK"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}
