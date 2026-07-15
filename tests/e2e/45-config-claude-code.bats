#!/usr/bin/env bats
# ─────────────────────────────────────────────────────────────────────────────
# 45-config-claude-code.bats — Claude Code (`claude`) install + auth resolution
# Covers: binary install, CLAUDE_CONFIG_DIR persistence, and the OAuth-primary
# credential precedence in lib/config-claude-code.sh::configure_claude_code_auth
# ─────────────────────────────────────────────────────────────────────────────

setup() {
    load test_helper/common
}

@test "AC-cc-1: claude binary installed in image" {
    local cid; cid=$(get_container); [ -n "$cid" ]
    run docker exec "$cid" bash -c 'command -v claude'
    [ "$status" -eq 0 ]
}

@test "AC-cc-2: claude --version succeeds" {
    local cid; cid=$(get_container); [ -n "$cid" ]
    run docker exec "$cid" claude --version
    [ "$status" -eq 0 ]
    [[ "$output" =~ [0-9]+\.[0-9]+\.[0-9]+ ]]
}

@test "AC-cc-3: config-claude-code.sh module exists" {
    local cid; cid=$(get_container); [ -n "$cid" ]
    run docker exec "$cid" test -f /usr/local/bin/lib/config-claude-code.sh
    [ "$status" -eq 0 ]
}

@test "AC-cc-4: configure_claude_code_auth is defined" {
    local cid; cid=$(get_container); [ -n "$cid" ]
    run docker exec "$cid" bash -c 'source /usr/local/bin/lib/constants.sh && source /usr/local/bin/lib/config-claude-code.sh && declare -f configure_claude_code_auth'
    [ "$status" -eq 0 ]
}

@test "AC-cc-5: CLAUDE_CONFIG_DIR is baked to the persistent ~/.hermes bind mount" {
    local cid; cid=$(get_container); [ -n "$cid" ]
    run docker exec "$cid" printenv CLAUDE_CONFIG_DIR
    [ "$status" -eq 0 ]
    [[ "$output" == "/home/hermeswebui/.hermes/claude" ]]
}

@test "AC-cc-6: OAuth token present drops ANTHROPIC_API_KEY (OAuth primary)" {
    local cid; cid=$(get_container); [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/constants.sh
        source /usr/local/bin/lib/config-claude-code.sh
        export CLAUDE_CONFIG_DIR=/tmp/cc-ac6-$$
        export CLAUDE_CODE_OAUTH_TOKEN=tok ANTHROPIC_API_KEY=key
        configure_claude_code_auth >/dev/null 2>&1
        echo "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-UNSET}"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == "ANTHROPIC_API_KEY=UNSET" ]]
}

@test "AC-cc-7: API key alone (no OAuth) is retained" {
    local cid; cid=$(get_container); [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/constants.sh
        source /usr/local/bin/lib/config-claude-code.sh
        export CLAUDE_CONFIG_DIR=/tmp/cc-ac7-$$
        unset CLAUDE_CODE_OAUTH_TOKEN
        export ANTHROPIC_API_KEY=key
        configure_claude_code_auth >/dev/null 2>&1
        echo "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-UNSET}"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == "ANTHROPIC_API_KEY=key" ]]
}

@test "AC-cc-8: on-disk login credentials drop ANTHROPIC_API_KEY (OAuth primary)" {
    local cid; cid=$(get_container); [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/constants.sh
        source /usr/local/bin/lib/config-claude-code.sh
        export CLAUDE_CONFIG_DIR=/tmp/cc-ac8-$$
        mkdir -p "$CLAUDE_CONFIG_DIR"
        echo "{}" > "$CLAUDE_CONFIG_DIR/.credentials.json"
        unset CLAUDE_CODE_OAUTH_TOKEN
        export ANTHROPIC_API_KEY=key
        configure_claude_code_auth >/dev/null 2>&1
        echo "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-UNSET}"
        rm -rf "$CLAUDE_CONFIG_DIR"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == "ANTHROPIC_API_KEY=UNSET" ]]
}

@test "AC-cc-9: no credentials logs the interactive-login hint" {
    local cid; cid=$(get_container); [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/constants.sh
        source /usr/local/bin/lib/config-claude-code.sh
        export CLAUDE_CONFIG_DIR=/tmp/cc-ac9-$$
        unset CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY
        configure_claude_code_auth 2>&1
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"No credentials"* ]]
    [[ "$output" == *"/login"* ]]
}

@test "AC-cc-10: configure_claude_code_auth creates the config dir owned by hermeswebui" {
    local cid; cid=$(get_container); [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/constants.sh
        source /usr/local/bin/lib/config-claude-code.sh
        d=/tmp/cc-ac10-$$
        export CLAUDE_CONFIG_DIR="$d"
        unset CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY
        configure_claude_code_auth >/dev/null 2>&1
        test -d "$d" && stat -c "%U" "$d"
        rm -rf "$d"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == "hermeswebui" ]]
}

@test "AC-cc-11: main + subagent model selection is logged when set" {
    local cid; cid=$(get_container); [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/constants.sh
        source /usr/local/bin/lib/config-claude-code.sh
        export CLAUDE_CONFIG_DIR=/tmp/cc-ac11-$$
        unset CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY
        export ANTHROPIC_MODEL=opus CLAUDE_CODE_SUBAGENT_MODEL=haiku
        configure_claude_code_auth 2>&1
        rm -rf "$CLAUDE_CONFIG_DIR"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"Main model: opus"* ]]
    [[ "$output" == *"Subagent/delegation model: haiku"* ]]
}

@test "AC-cc-12: model + Claude Code env vars are wired through docker-compose.yml" {
    # Static contract: compose must forward the model/auth knobs to the container.
    run bash -c "grep -qE 'ANTHROPIC_MODEL=' '$BATS_TEST_DIRNAME/../../docker-compose.yml' \
        && grep -qE 'CLAUDE_CODE_SUBAGENT_MODEL=' '$BATS_TEST_DIRNAME/../../docker-compose.yml' \
        && grep -qE 'CLAUDE_CODE_OAUTH_TOKEN=' '$BATS_TEST_DIRNAME/../../docker-compose.yml'"
    [ "$status" -eq 0 ]
}

@test "AC-cc-13: IS_SANDBOX=1 is baked so claude allows --dangerously-skip-permissions under root" {
    local cid; cid=$(get_container); [ -n "$cid" ]
    # ENV inherited by every child process...
    run docker exec "$cid" printenv IS_SANDBOX
    [ "$status" -eq 0 ]
    [[ "$output" == "1" ]]
    # ...and recorded in /etc/environment for root `docker exec` shells.
    run docker exec "$cid" grep -qx 'IS_SANDBOX=1' /etc/environment
    [ "$status" -eq 0 ]
}
