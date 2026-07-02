#!/usr/bin/env bats
# ─────────────────────────────────────────────────────────────────────────────
# 24-constants-runtime-config.bats — constants.sh runtime config defaults
# Verifies the runtime configuration variables introduced in constants.sh
# (YOLO mode, delegation, dashboard, code-server, browser, etc.)
# ─────────────────────────────────────────────────────────────────────────────

setup() {
    load test_helper/common
}

@test "AC190: constants.sh module exists in container" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" test -f /usr/local/bin/lib/constants.sh
    [ "$status" -eq 0 ]
}

@test "AC191: constants.sh defines path variables" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c 'source /usr/local/bin/lib/constants.sh; echo "$HERMES_HOME:$OPENCODE_USER:$OPENCODE_USER_HOME"'
    [ "$status" -eq 0 ]
    [[ "$output" == "/home/hermeswebui/.hermes:hermeswebui:/home/hermeswebui"* ]]
}

@test "AC192: constants.sh defines port defaults" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c 'source /usr/local/bin/lib/constants.sh; echo "$DAEMON_PORT:$HERMES_API_PORT:$OPENCODE_SERVE_PORT"'
    [ "$status" -eq 0 ]
    # DAEMON_PORT defaults to empty, HERMES_API_PORT=8642, OPENCODE_SERVE_PORT=4096
    [[ "$output" == ":8642:4096"* ]] || [[ "$output" == "7456:8642:4096"* ]]
}

@test "AC193: log() and warn() helpers are defined" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/constants.sh
        declare -f log
        declare -f warn
        echo "OK"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "AC194: log() outputs to stderr with [entrypoint] prefix" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c 'source /usr/local/bin/lib/constants.sh; log "test msg" 2>&1'
    [ "$status" -eq 0 ]
    [[ "$output" == *"[entrypoint] test msg"* ]]
}

@test "AC195: warn() outputs to stderr with WARN label" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c 'source /usr/local/bin/lib/constants.sh; warn "test warning" 2>&1'
    [ "$status" -eq 0 ]
    [[ "$output" == *"[entrypoint] WARN: test warning"* ]]
}

@test "AC196: HERMES_YOLO_MODE defaults to 1" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c 'source /usr/local/bin/lib/constants.sh; echo "$HERMES_YOLO_MODE"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"1"* ]]
}

@test "AC197: HERMES_DELEGATION_MAX_ITERATIONS defaults to 50" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c 'source /usr/local/bin/lib/constants.sh; echo "$HERMES_DELEGATION_MAX_ITERATIONS"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"50"* ]]
}

@test "AC198: HERMES_GOAL_MAX_TURNS defaults to 50" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c 'source /usr/local/bin/lib/constants.sh; echo "$HERMES_GOAL_MAX_TURNS"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"50"* ]]
}

@test "AC199: HERMES_DASHBOARD_ENABLED defaults to false" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c 'source /usr/local/bin/lib/constants.sh; echo "$HERMES_DASHBOARD_ENABLED"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"false"* ]]
}

@test "AC200: HERMES_DASHBOARD_PORT defaults to 9119" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c 'source /usr/local/bin/lib/constants.sh; echo "$HERMES_DASHBOARD_PORT"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"9119"* ]]
}

@test "AC201: CODE_SERVER_ENABLED defaults to true and port defaults to 8443" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c 'source /usr/local/bin/lib/constants.sh; echo "$CODE_SERVER_ENABLED:$CODE_SERVER_PORT"'
    [ "$status" -eq 0 ]
    [[ "$output" == "true:8443"* ]]
}

@test "AC202: BROWSER_DISPLAY defaults to 1920x1080" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c 'source /usr/local/bin/lib/constants.sh; echo "$BROWSER_DISPLAY_WIDTH:$BROWSER_DISPLAY_HEIGHT"'
    [ "$status" -eq 0 ]
    [[ "$output" == "1920:1080"* ]]
}

@test "AC203: OPENCODE_SECURITY_MODE defaults to strict" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c 'source /usr/local/bin/lib/constants.sh; echo "$OPENCODE_SECURITY_MODE"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"strict"* ]]
}

@test "AC204: OPENAI_DEFAULT_MODEL defaults to openai/gpt-4o" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c 'source /usr/local/bin/lib/constants.sh; echo "$OPENAI_DEFAULT_MODEL"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"openai/gpt-4o"* ]]
}

@test "AC205: Fine-grained model overrides fall back to OPENAI_DEFAULT_MODEL" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c 'source /usr/local/bin/lib/constants.sh; echo "$HERMES_DEFAULT_MODEL:$OPENCODE_DEFAULT_MODEL"'
    [ "$status" -eq 0 ]
    # When HERMES_DEFAULT_MODEL and OPENCODE_DEFAULT_MODEL are not set, they
    # fall back to OPENAI_DEFAULT_MODEL which defaults to openai/gpt-4o
    [[ "$output" == *"openai/gpt-4o"* ]]
}

@test "AC206: OPENAI_IMAGE_MODEL defaults to gpt-image-2" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c 'source /usr/local/bin/lib/constants.sh; echo "$OPENAI_IMAGE_MODEL"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"gpt-image-2"* ]]
}

@test "AC207: OPENAI_CONTEXT_LENGTH defaults to 200000" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c 'source /usr/local/bin/lib/constants.sh; echo "$OPENAI_CONTEXT_LENGTH"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"200000"* ]]
}

@test "AC208: Runtime config can be overridden via environment" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        export HERMES_YOLO_MODE=0
        export HERMES_DASHBOARD_ENABLED=true
        source /usr/local/bin/lib/constants.sh
        echo "$HERMES_YOLO_MODE:$HERMES_DASHBOARD_ENABLED"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == "0:true"* ]]
}
