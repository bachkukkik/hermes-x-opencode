#!/usr/bin/env bats
# 37-dcp-config.bats — DCP (dynamic context pruning) config generation
#
# The @tarquinen/opencode-dcp plugin defaults compress.maxContextLimit to a hard
# 100_000 tokens regardless of the active model, so a 1M-context model gets
# compression-nudged at ~10% fill. generate_dcp_staging() writes a managed
# dcp.jsonc whose compress thresholds are a PERCENTAGE of each model's own
# context window (DCP resolves "X%" per active model), driven by
# OPENCODE_COMPRESSION_THRESHOLD (default 0.76, mirroring Hermes).

setup() {
    load test_helper/common
}

# Helper: run generate_dcp_staging inside the container with optional env overrides.
# Usage: _run_dcp_gen [ENV_VAR=value ...]
_run_dcp_gen() {
    local cid
    cid=$(get_container)
    [ -n "$cid" ] || return 1
    local env_prefix=""
    local arg
    for arg in "$@"; do
        env_prefix="${env_prefix}export ${arg}; "
    done
    docker exec "$cid" bash -c "
        ${env_prefix}source /usr/local/bin/lib/constants.sh
        source /usr/local/bin/lib/config-opencode.sh
        generate_dcp_staging 2>/dev/null
        cat \"\$OPENCODE_DCP_CONFIG\"
    "
}

@test "DC1: default threshold writes 76% maxContextLimit + valid JSON + \$schema" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    # Unset any env override so default 0.76 applies
    run docker exec "$cid" bash -c '
        unset OPENCODE_COMPRESSION_THRESHOLD
        source /usr/local/bin/lib/constants.sh
        source /usr/local/bin/lib/config-opencode.sh
        generate_dcp_staging 2>/dev/null
        cat "$OPENCODE_DCP_CONFIG"
    '
    [ "$status" -eq 0 ]
    echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d.get('compress', {}).get('maxContextLimit') == '76%', d
assert d.get('compress', {}).get('minContextLimit') == '38%', d
assert '\$schema' in d, d
print('OK: default DCP thresholds 76%/38%')
"
}

@test "DC2: OPENCODE_COMPRESSION_THRESHOLD=0.9 writes 90% maxContextLimit" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run docker exec "$cid" bash -c '
        export OPENCODE_COMPRESSION_THRESHOLD=0.9
        source /usr/local/bin/lib/constants.sh
        source /usr/local/bin/lib/config-opencode.sh
        generate_dcp_staging 2>/dev/null
        cat "$OPENCODE_DCP_CONFIG"
    '
    [ "$status" -eq 0 ]
    echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['compress']['maxContextLimit'] == '90%', d
assert d['compress']['minContextLimit'] == '45%', d
print('OK: threshold 0.9 -> 90%/45%')
"
}

@test "DC3: existing dcp.jsonc keys are preserved (surgical merge)" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    # Seed a pre-existing dcp.jsonc with extra keys
    docker exec "$cid" bash -c '
        mkdir -p /home/hermeswebui/.config/opencode
        cat > /home/hermeswebui/.config/opencode/dcp.jsonc << DCPEOF
{
  "enabled": true,
  "debug": true,
  "compress": {
    "nudgeFrequency": 3,
    "maxContextLimit": 100000
  },
  "strategies": { "deduplication": { "enabled": false } }
}
DCPEOF
    '

    run docker exec "$cid" bash -c '
        unset OPENCODE_COMPRESSION_THRESHOLD
        source /usr/local/bin/lib/constants.sh
        source /usr/local/bin/lib/config-opencode.sh
        generate_dcp_staging 2>/dev/null
        cat "$OPENCODE_DCP_CONFIG"
    '
    [ "$status" -eq 0 ]
    echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
# Overridden target keys
assert d['compress']['maxContextLimit'] == '76%', d
# Preserved untouched keys
assert d['debug'] is True, d
assert d['compress']['nudgeFrequency'] == 3, d
assert d['strategies']['deduplication']['enabled'] is False, d
print('OK: unrelated dcp.jsonc keys preserved')
"
}

@test "DC4: out-of-range threshold falls back to default 0.76" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run docker exec "$cid" bash -c '
        export OPENCODE_COMPRESSION_THRESHOLD=1.5
        source /usr/local/bin/lib/constants.sh
        source /usr/local/bin/lib/config-opencode.sh
        generate_dcp_staging 2>/dev/null
        cat "$OPENCODE_DCP_CONFIG"
    '
    [ "$status" -eq 0 ]
    echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['compress']['maxContextLimit'] == '76%', d
print('OK: out-of-range threshold clamped to default')
"
}
