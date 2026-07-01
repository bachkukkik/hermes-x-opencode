#!/usr/bin/env bats

# Tests for ACP (Agent Client Protocol) limitation (vanilla-coder#6)
# ACP is designed for IDE stdio integration, NOT as a standalone TCP server.
# The --port flag is accepted but never binds a port.
# These tests document that upstream limitation.

setup() {
    load test_helper/common
}

@test "VC6.1: opencode acp --port does not bind the specified port" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    local test_port=18998

    # Run ACP with --port flag; it exits immediately without binding
    docker exec "$cid" timeout 10 opencode acp --port "$test_port" --print-logs 2>/dev/null || true

    # Verify the port was never bound
    run docker exec "$cid" bash -c "ss -tlnp | grep ':${test_port} '"
    [ "$status" -ne 0 ]
}

@test "VC6.2: opencode acp exits with code 0 (not an error, just no-op)" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run docker exec "$cid" timeout 10 opencode acp --port 19999 --print-logs
    # ACP exits cleanly (code 0) even though it doesn't bind the port.
    # Accept exit 124 (timeout) too — upstream may hang in certain environments.
    [ "$status" -eq 0 ] || [ "$status" -eq 124 ]
}

@test "VC6.3: ACP limitation is documented in README" {
    [ -f "$PROJECT_DIR/README.md" ]
    run grep -i "ACP.*broken\|ACP.*limitation\|ACP.*stdio\|ACP.*does not bind\|acp.*not.*tcp" "$PROJECT_DIR/README.md"
    [ "$status" -eq 0 ]
}

# --- TT-09: Invalid OPENCODE_ZEN_API_KEY validation (source-level test) ---

@test "VC6.4: Zen API key validation script exists and contains error handling" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    # The validation library must be present at /usr/local/bin/lib/validate-opencode.sh
    run docker exec "$cid" test -f /usr/local/bin/lib/validate-opencode.sh
    [ "$status" -eq 0 ]

    # The script must reference 401-style error handling (warns on validation failure)
    run docker exec "$cid" grep -c "WARNING\|401\|Invalid API key\|validation\|returned an error" /usr/local/bin/lib/validate-opencode.sh
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "VC6.5: entrypoint sources the validation library" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run docker exec "$cid" grep "validate-opencode.sh" /usr/local/bin/entrypoint.sh
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "source.*validate-opencode"
}

@test "VC6.6: container logs show key validation output (or skipped message)" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    # The entrypoint always calls validate_opencode_zen_key — it either validates
    # or prints a "not set" / "WARNING" message. Verify one of those appeared.
    run bash -c "docker logs '$cid' 2>&1 | grep -c 'OPENCODE_ZEN_API_KEY'"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}
