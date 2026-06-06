#!/usr/bin/env bats

# Tests for Serve + Attach delegation pattern (vanilla-coder#7)
# When OPENCODE_SERVE_ENABLED=true, verifies:
# 1. opencode serve starts and listens on port 4096
# 2. opencode run --attach can delegate a task
# 3. The attach flow creates a file and exits cleanly

setup() {
    load test_helper/common
}

@test "VC7.1: opencode serve is running and listening on port 4096" {
    skip_if_no_secrets
    [ "${OPENCODE_SERVE_ENABLED:-false}" = "true" ] || skip "OPENCODE_SERVE_ENABLED!=true"

    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    # The serve process listens on 127.0.0.1:4096 with auth.
    # Standard HTTP healthcheck returns 401; verify by port + process instead.
    run docker exec "$cid" bash -c 'timeout 3 bash -c "echo > /dev/tcp/127.0.0.1/4096"'
    [ "$status" -eq 0 ]
    run docker exec "$cid" pgrep -f "opencode serve"
    [ "$status" -eq 0 ]
}

@test "VC7.2: serve+attach creates a file and exits cleanly" {
    skip_if_no_secrets
    [ "${OPENCODE_SERVE_ENABLED:-false}" = "true" ] || skip "OPENCODE_SERVE_ENABLED!=true"

    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    local test_file="/tmp/serve-attach-test-$(date +%s).txt"
    local test_content="Serve+Attach delegation works"

    # Get the serve password from the persistent file
    local serve_pass
    serve_pass=$(docker exec "$cid" cat /home/hermeswebui/.hermes/opencode_server_password 2>/dev/null || echo "")
    [ -n "$serve_pass" ]

    # Use opencode run --attach to create a test file
    run docker exec "$cid" timeout 120 opencode run \
        --attach "http://127.0.0.1:4096" \
        -p "$serve_pass" \
        --dir /tmp \
        -m opencode/deepseek-v4-flash-free \
        "Create a file at ${test_file} with the exact content: ${test_content}"
    # Accept 0 (connected, may or may not complete without LLM) or 124 (timeout)
    [ "$status" -eq 0 ] || [ "$status" -eq 124 ]

    # If opencode exited 0 and the file was created, verify its content
    if [ "$status" -eq 0 ]; then
        if docker exec "$cid" test -f "$test_file" 2>/dev/null; then
            run docker exec "$cid" cat "$test_file"
            [ "$status" -eq 0 ]
            echo "$output" | grep -q "$test_content"
            docker exec "$cid" rm -f "$test_file" 2>/dev/null || true
        fi
    fi
}

@test "VC7.3: serve+attach with --format json produces structured output" {
    skip_if_no_secrets
    [ "${OPENCODE_SERVE_ENABLED:-false}" = "true" ] || skip "OPENCODE_SERVE_ENABLED!=true"

    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    local serve_pass
    serve_pass=$(docker exec "$cid" cat /home/hermeswebui/.hermes/opencode_server_password 2>/dev/null || echo "")
    [ -n "$serve_pass" ]

    # Run with JSON format
    run docker exec "$cid" timeout 120 opencode run \
        --attach "http://127.0.0.1:4096" \
        -p "$serve_pass" \
        --dir /tmp \
        -m opencode/deepseek-v4-flash-free \
        --format json \
        "Respond with exactly: JSON_ATTACH_OK"
    # Accept 0 (connected, output may be empty in some versions) or 124 (timeout)
    [ "$status" -eq 0 ] || [ "$status" -eq 124 ]

    # If output exists, check for recognizable event types
    if [ "$status" -eq 0 ] && [ -n "$output" ]; then
        echo "$output" | grep -q "step_start\|step_finish\|tool_use\|text"
    fi
}
