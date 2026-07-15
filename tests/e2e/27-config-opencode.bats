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

@test "AC244: get_limits returns pinned (context,output) per family incl agents-a1" {
    # T2b: the get_limits pin table is otherwise tested only in 19-CTX4. Extract the
    # embedded python block (same technique as CTX4) and assert the load-bearing rows,
    # including both agents-a1 llama.cpp families pinned BEFORE the llama_cpp catch-all.
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c 'python3 -c "
import sys
with open(\"/usr/local/bin/lib/config-opencode.sh\") as f:
    content = f.read()
start = content.index(\"import sys, re, json, os\")
end = content.rindex(\"return 128000, 8192\", start) + len(\"return 128000, 8192\")
exec(content[start:end])
tests = [
    (\"llama_cpp/agents-a1-mtp-apex-i-balanced\", (262144, 32768)),
    (\"llama_cpp/agents-a1-q4_k_m\", (262144, 32768)),
    (\"llama_cpp/qwen3.6-27b-q4_k_m\", (262144, 32768)),
    (\"opencode-go/deepseek-v4-pro\", (1000000, 65536)),
    (\"z.ai/glm-5.2\", (1048576, 131072)),
    (\"unknown-xyz\", (128000, 8192)),
]
for mid, exp in tests:
    r = get_limits(mid)
    assert r == exp, f\"{mid} -> {r} != {exp}\"
print(\"OK\")
"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "AC245: normalize_model_id resolves bare ids by credential presence" {
    # T3: the credential-dependent bare-id branch (config-opencode.sh:18-22) was
    # untested (AC219 only covers explicit-prefix passthrough).
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/config-opencode.sh
        echo "creds: $(OPENAI_BASE_URL=http://x OPENAI_API_KEY=sk-x normalize_model_id foo)"
        echo "nocreds: $(unset OPENAI_BASE_URL OPENAI_API_KEY; normalize_model_id foo)"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"creds: litellm/foo"* ]]
    [[ "$output" == *"nocreds: opencode/foo"* ]]
}
