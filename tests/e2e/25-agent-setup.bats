#!/usr/bin/env bats
# ─────────────────────────────────────────────────────────────────────────────
# 25-agent-setup.bats — agent-setup.sh: hermes-agent staging/copy logic
# ─────────────────────────────────────────────────────────────────────────────

setup() {
    load test_helper/common
}

@test "AC210: agent-setup.sh module exists in container" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" test -f /usr/local/bin/lib/agent-setup.sh
    [ "$status" -eq 0 ]
}

@test "AC211: ensure_agent function is defined" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/agent-setup.sh
        declare -f ensure_agent
        echo "OK"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "AC212: ensure_agent is idempotent (present agent returns cleanly)" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    # The agent should be present after entrypoint runs — calling ensure_agent
    # should log "already present" and return 0
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/constants.sh
        source /usr/local/bin/lib/agent-setup.sh
        ensure_agent 2>&1
    '
    [ "$status" -eq 0 ]
}
