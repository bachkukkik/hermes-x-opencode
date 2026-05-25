#!/usr/bin/env bats

setup() {
    load test_helper/common
}

@test "AC5: agent source present in bind mount" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" test -f /home/hermeswebui/.hermes/hermes-agent/pyproject.toml
    [ "$status" -eq 0 ]
}

@test "AC6: CustomProfile User-Agent patch applied" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" grep -q '"User-Agent".*"hermes-agent' /home/hermeswebui/.hermes/hermes-agent/plugins/model-providers/custom/__init__.py
    [ "$status" -eq 0 ]
}

@test "AC7: config.yaml has literal key_env string" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" grep -q 'key_env: OPENAI_API_KEY' /home/hermeswebui/.hermes/config.yaml
    [ "$status" -eq 0 ]
}

@test "AC17: config.yaml includes api_server platform" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" grep -q 'api_server' /home/hermeswebui/.hermes/config.yaml
    [ "$status" -eq 0 ]
}

@test "AC18: no wildcard models in config.yaml" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" grep '/\*' /home/hermeswebui/.hermes/config.yaml
    [ "$status" -ne 0 ]
}

@test "AC19: onboarding is skipped" {
    local response=""
    local retries=0
    while [ "$retries" -lt 60 ]; do
        response=$(curl -sf --max-time 5 "$(webui_base)/api/onboarding/status" 2>/dev/null) && break
        sleep 2
        retries=$((retries + 1))
    done
    [ -n "$response" ]
    echo "$response" | grep -q '"completed": *true'
}

@test "AC20: opencode.jsonc is valid JSON" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" python3 -m json.tool /home/hermeswebui/.config/opencode/opencode.jsonc
    [ "$status" -eq 0 ]
}
