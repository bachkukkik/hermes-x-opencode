#!/usr/bin/env bats
# ─────────────────────────────────────────────────────────────────────────────
# 38-create-stub-skills.bats — create-stub-skills.sh stub skills creation
# Verifies creation of security-best-practices and webapp-testing stub skills.
# ─────────────────────────────────────────────────────────────────────────────

setup() {
    load test_helper/common
}

@test "AC200: create-stub-skills.sh module exists in container" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" test -f /usr/local/bin/create-stub-skills.sh
    [ "$status" -eq 0 ]
}

@test "AC201: create-stub-skills.sh is executable" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" test -x /usr/local/bin/create-stub-skills.sh
    [ "$status" -eq 0 ]
}

@test "AC202: stub skills are created in staging directory" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        /usr/local/bin/create-stub-skills.sh
        test -f /opt/hermes-skills-staging/software-development/security-best-practices/SKILL.md && echo "SEC:OK"
        test -f /opt/hermes-skills-staging/software-development/webapp-testing/SKILL.md && echo "WEB:OK"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"SEC:OK"* ]]
    [[ "$output" == *"WEB:OK"* ]]
}

@test "AC203: security-best-practices stub has correct frontmatter" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        cat /opt/hermes-skills-staging/software-development/security-best-practices/SKILL.md
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"name: security-best-practices"* ]]
    [[ "$output" == *"Security best practices for all code changes"* ]]
}

@test "AC204: webapp-testing stub has correct frontmatter" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        cat /opt/hermes-skills-staging/software-development/webapp-testing/SKILL.md
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"name: webapp-testing"* ]]
    [[ "$output" == *"Write and run comprehensive tests"* ]]
}
