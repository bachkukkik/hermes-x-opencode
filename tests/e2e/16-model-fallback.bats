#!/usr/bin/env bats

# Runtime model fallback (opencode-runtime-fallback plugin).
#
# These tests exercise generate_opencode_config() directly with a controlled
# OPENCODE_FALLBACK_MODEL so both the SET and UNSET states are verified
# deterministically, regardless of the value present at container boot.
#
# The generator is sourced from /usr/local/bin/lib/ and run against temp config
# dirs. Its hardcoded root-copy step (/root/.config/opencode/opencode.jsonc) is
# backed up before each test and restored in teardown() so the live container
# config is left untouched.

setup() {
    load test_helper/common
    CID="$(get_container)"
    export CID
}

teardown() {
    if [ -n "${CID:-}" ]; then
        # Restore the live root opencode config and remove test artifacts.
        docker exec "$CID" bash -c \
            'cp /tmp/.fb-backup.jsonc /root/.config/opencode/opencode.jsonc 2>/dev/null; rm -f /tmp/.fb-backup.jsonc /root/.config/opencode/opencode-fallback.jsonc; rm -rf /tmp/fbtest-set /tmp/fbtest-unset /tmp/fbtest-home' \
            2>/dev/null || true
    fi
}

# Run generate_opencode_config in the container with controlled env.
#   $1 = container id, $2 = temp config dir, $3 = OPENCODE_FALLBACK_MODEL (may be empty)
# constants.sh reassigns OPENCODE_CONFIG/OPENCODE_USER_HOME, so they are set
# AFTER sourcing and passed as positional args to avoid being clobbered.
_run_gen() {
    docker exec "$1" bash -c '
        source /usr/local/bin/lib/constants.sh
        source /usr/local/bin/lib/config-opencode.sh
        OPENCODE_USER_HOME="/tmp/fbtest-home"
        OPENCODE_CONFIG="$1/opencode.jsonc"
        if [ -n "$2" ]; then
            export OPENCODE_FALLBACK_MODEL="$2"
        else
            unset OPENCODE_FALLBACK_MODEL
        fi
        generate_opencode_config >/dev/null 2>&1
    ' _ "$2" "$3"
}

@test "AC26: OPENCODE_FALLBACK_MODEL set adds plugin and fallback chain" {
    skip_if_no_secrets
    [ -n "$CID" ]
    # Back up the live root config so teardown can restore it.
    docker exec "$CID" cp /root/.config/opencode/opencode.jsonc /tmp/.fb-backup.jsonc

    _run_gen "$CID" /tmp/fbtest-set "llama_cpp/qwen3.6-27b-q4_k_m"

    # The opencode-runtime-fallback plugin must be present in the plugin array.
    local plugins
    plugins=$(docker exec "$CID" python3 -c "
import json, re, sys
t = open(sys.argv[1]).read()
t = re.sub(r'(?<![:a-zA-Z])//.*?\n', '\n', t)
c = json.loads(t)
print('\n'.join(c.get('plugin', [])))
" /tmp/fbtest-set/opencode.jsonc 2>/dev/null)
    echo "$plugins" | grep -qx 'opencode-runtime-fallback'

    # The base plugins must still be present.
    echo "$plugins" | grep -qx 'cc-safety-net'

    # The global fallback chain config must be seeded next to opencode.jsonc.
    docker exec "$CID" test -f /tmp/fbtest-set/opencode-fallback.jsonc
    docker exec "$CID" grep -q 'fallback_models' /tmp/fbtest-set/opencode-fallback.jsonc
}

@test "AC27: OPENCODE_FALLBACK_MODEL unset omits plugin and fallback chain" {
    skip_if_no_secrets
    [ -n "$CID" ]
    docker exec "$CID" cp /root/.config/opencode/opencode.jsonc /tmp/.fb-backup.jsonc

    _run_gen "$CID" /tmp/fbtest-unset ""

    # No runtime-fallback plugin in the array.
    local plugins
    plugins=$(docker exec "$CID" python3 -c "
import json, re, sys
t = open(sys.argv[1]).read()
t = re.sub(r'(?<![:a-zA-Z])//.*?\n', '\n', t)
c = json.loads(t)
print('\n'.join(c.get('plugin', [])))
" /tmp/fbtest-unset/opencode.jsonc 2>/dev/null)
    ! echo "$plugins" | grep -qx 'opencode-runtime-fallback'

    # Exactly the three base plugins remain.
    local count
    count=$(echo "$plugins" | wc -l | tr -d ' ')
    [ "$count" -eq 3 ]

    # No fallback chain config is written.
    run docker exec "$CID" test -f /tmp/fbtest-unset/opencode-fallback.jsonc
    [ "$status" -ne 0 ]
}

@test "AC28: resolved fallback id is provider-prefixed in the chain" {
    skip_if_no_secrets
    [ -n "$CID" ]
    docker exec "$CID" cp /root/.config/opencode/opencode.jsonc /tmp/.fb-backup.jsonc

    _run_gen "$CID" /tmp/fbtest-set "llama_cpp/qwen3.6-27b-q4_k_m"

    # OPENAI_BASE_URL + OPENAI_API_KEY are set (skip_if_no_secrets), so a bare
    # llama_cpp/* id resolves to the litellm provider; the llama_cpp/ segment is
    # not a provider prefix, so it is preserved verbatim after stripping.
    local expected="litellm/llama_cpp/qwen3.6-27b-q4_k_m"
    docker exec "$CID" grep -q "\"${expected}\"" /tmp/fbtest-set/opencode-fallback.jsonc

    # And the resolved id must be a single, valid JSON array entry.
    local result
    result=$(docker exec "$CID" python3 -c "
import json, sys
c = json.load(open(sys.argv[1]))
print(','.join(c.get('fallback_models', [])))
" /tmp/fbtest-set/opencode-fallback.jsonc 2>/dev/null)
    [ "$result" = "$expected" ]
}
