#!/usr/bin/env bats

setup() {
    load test_helper/common
}

@test "AC14: gateway health endpoint returns OK" {
    run curl -sf "$(gateway_base)/health"
    [ "$status" -eq 0 ]
}

@test "AC15: gateway /v1/models returns model list" {
    local api_key
    api_key=$(get_api_key)
    [ -n "$api_key" ]
    run curl -sf "$(gateway_base)/v1/models" -H "Authorization: Bearer $api_key"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q 'hermes-agent'
}

@test "AC16: gateway chat completion returns response" {
    local api_key
    api_key=$(get_api_key)
    [ -n "$api_key" ]
    run curl -sf "$(gateway_base)/v1/chat/completions" \
        -H "Authorization: Bearer $api_key" \
        -H "Content-Type: application/json" \
        --max-time 90 \
        -d '{"model":"hermes-agent","messages":[{"role":"user","content":"Say hello in one word"}],"stream":false}'
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '"choices"'
}
