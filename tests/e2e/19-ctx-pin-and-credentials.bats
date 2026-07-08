#!/usr/bin/env bats

# Tests for issues #31 and #30 fixes (PRD.md Section 19.6)
#   CTX1/CTX2/CTX3 -> CA-31-A/CA-31-B (context-length pin + env-var transport)
#   CRED1/CRED2     -> CA-30-A (auth.json litellm seeding + OR guard contract)
#
# Lib scripts are COPYed into the image at /usr/local/bin/lib/ (see Dockerfile).
# Source them in a subshell to exercise resolve_ctx_len() directly.

setup() {
    load test_helper/common
}

@test "CTX1: resolve_ctx_len pins quantized qwen3.6 GGUF to 262144" {
    # CA-31-A: a *qwen3.6-27b*q4*) pin row sits BEFORE the *qwen3.6*) family
    # wildcard, so a quantized GGUF must resolve to 262144 (NOT 1048576).
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run docker exec "$cid" bash -c 'source /usr/local/bin/lib/config-hermes.sh; resolve_ctx_len "llama_cpp/qwen3.6-27b-q4_k_m"'
    [ "$status" -eq 0 ]
    [ "$output" = "262144" ]
}

@test "CTX2: resolve_ctx_len family wildcard preserved for unquantized qwen3.6" {
    # Regression guard for CA-31-A: the new pin must not shadow the family
    # wildcard for non-quantized models. qwen3.6-32b still resolves to 1048576.
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run docker exec "$cid" bash -c 'source /usr/local/bin/lib/config-hermes.sh; resolve_ctx_len "qwen3.6-32b"'
    [ "$status" -eq 0 ]
    [ "$output" = "1048576" ]
}

@test "CTX4: get_limits pins opencode-go and opencode free-tier model families" {
    # Verify get_limits() from config-opencode.sh returns correct (context, output)
    # pairs for the new model families. Extracts the Python function block from the
    # shell script and runs unit tests against it inside the container.
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run docker exec "$cid" bash -c 'python3 -c "
import sys, re
with open(\"/usr/local/bin/lib/config-opencode.sh\") as f:
    content = f.read()
start = content.index(\"import sys, re, json, os\")
end = content.rindex(\"return 128000, 8192\", start) + len(\"return 128000, 8192\")
exec(content[start:end])
tests = [
    (\"opencode-go/deepseek-v4-pro\", (1000000, 8192)),
    (\"opencode-go/deepseek-v4-flash\", (1000000, 8192)),
    (\"opencode/deepseek-v4-flash-free\", (1000000, 8192)),
    (\"opencode-go/kimi-k2.6\", (262144, 8192)),
    (\"opencode-go/kimi-k2.7-code\", (262144, 8192)),
    (\"opencode-go/minimax-m3\", (1000000, 8192)),
    (\"opencode/mimo-v2.5-free\", (1048576, 8192)),
    (\"opencode/nemotron-3-ultra-free\", (131072, 8192)),
    (\"opencode/qwen3.6-plus-free\", (1048576, 8192)),
    (\"opencode-go/glm-5.2\", (1048576, 131072)),
    (\"llama_cpp/qwen3.6-27b-q4_k_m\", (200000, 32768)),
    (\"llama_cpp/agents-a1-mtp-apex-i-balanced\", (262144, 32768)),
    (\"llama_cpp/agents-a1-q4_k_m\", (262144, 32768)),
]
for mid, expected in tests:
    result = get_limits(mid)
    if result != expected:
        print(f\"FAIL: {mid} -> {result} (expected {expected})\")
        sys.exit(1)
print(f\"OK: {len(tests)}/{len(tests)} passed\")
"'
    [ "$status" -eq 0 ]
}

@test "CTX5: resolve_ctx_len pins Agents A1 llama.cpp models to 262144" {
    # Bridged from host-machine PR #20: the new agents-a1-mtp-apex and
    # agents-a1-q4 llama.cpp families have 262K native ctx; both pin rows sit
    # BEFORE the catch-all so a discovered Agents A1 model gets its real window
    # instead of falling through to the agent's default.
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run docker exec "$cid" bash -c 'source /usr/local/bin/lib/config-hermes.sh; resolve_ctx_len "llama_cpp/agents-a1-mtp-apex-i-balanced"'
    [ "$status" -eq 0 ]
    [ "$output" = "262144" ]

    run docker exec "$cid" bash -c 'source /usr/local/bin/lib/config-hermes.sh; resolve_ctx_len "llama_cpp/agents-a1-q4_k_m"'
    [ "$status" -eq 0 ]
    [ "$output" = "262144" ]
}

@test "CTX3: HERMES_COMPRESSION_THRESHOLD transported into container when set" {
    # CA-31-B: docker-compose.yml passes HERMES_COMPRESSION_THRESHOLD through
    # (empty default). The test harness brings the container up once from .env,
    # so we can only READ what's already there. If .env sets the var, the
    # container MUST expose it via printenv; if .env omits it, we skip (can't
    # verify transport of an unset var).
    if [ -z "${HERMES_COMPRESSION_THRESHOLD:-}" ]; then
        skip "HERMES_COMPRESSION_THRESHOLD not set in .env — cannot verify transport"
    fi

    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run docker exec "$cid" bash -c 'printenv HERMES_COMPRESSION_THRESHOLD'
    [ "$status" -eq 0 ]
    [ "$output" = "$HERMES_COMPRESSION_THRESHOLD" ]
}

@test "CRED1: auth.json seeds litellm credential when OPENCODE_ZEN_API_KEY unset but OPENAI_API_KEY set" {
    # CA-30-A: with OPENAI_API_KEY + OPENAI_BASE_URL set, config-opencode.sh
    # seeds auth['litellm'] = {'apiKey': ai_key}, so opencode CLI resolves
    # >=1 credential even without an opencode Zen key.
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run docker exec "$cid" python3 -c "import json; a=json.load(open('/home/hermeswebui/.local/share/opencode/auth.json')); print('litellm' in a)"
    [ "$status" -eq 0 ]
    [ "$output" = "True" ]
}

@test "CRED2: config-opencode.sh auth.json guard uses OR not AND (CA-30-A contract)" {
    # Contract test: the auth.json seeding guard uses `$_has_opencode_key ||
    # $_has_openai_creds` (OR), so a future edit can't silently narrow it to
    # opencode-key-only and drop the litellm credential.
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run docker exec "$cid" bash -c 'grep -q "_has_opencode_key || \$_has_openai_creds" /usr/local/bin/lib/config-opencode.sh'
    [ "$status" -eq 0 ]
}
