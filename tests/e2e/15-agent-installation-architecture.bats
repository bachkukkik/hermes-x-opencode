#!/usr/bin/env bats

setup() {
    load test_helper/common
}

@test "AC26: staged agent clone is trimmed (no skills/ docs/ tests/)" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    # Staged clone should NOT have skills/, docs/, tests/ directories
    run docker exec "$cid" test -d /opt/hermes-agent-staging/skills
    [ "$status" -ne 0 ]
    run docker exec "$cid" test -d /opt/hermes-agent-staging/docs
    [ "$status" -ne 0 ]
    run docker exec "$cid" test -d /opt/hermes-agent-staging/tests
    [ "$status" -ne 0 ]
}

@test "AC27: runtime agent copy exists on bind mount" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    docker exec "$cid" test -f /home/hermeswebui/.hermes/hermes-agent/pyproject.toml
}

@test "AC28: User-Agent patch propagated to active venv" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    # The patch must be in the active venv (Installation A)
    docker exec "$cid" find /app/venv/lib/ -path '*/plugins/model-providers/custom/__init__.py' -exec grep -q '"User-Agent".*"hermes-agent' {} +
}

@test "AC29: active venv hermes binary exists" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    docker exec "$cid" test -x /app/venv/bin/hermes
}

@test "AC30: staged clone does not have skills/ dir (trimmed)" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    # Verify skills are NOT in the staged clone (trimmed for image size)
    run docker exec "$cid" test -d /opt/hermes-agent-staging/skills
    [ "$status" -ne 0 ]
}
