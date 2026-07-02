#!/usr/bin/env bats
# ─────────────────────────────────────────────────────────────────────────────
# 20-seed-volumes.bats — seed-volumes.sh seed_volumes function
# Verifies volume seeding of skills, root symlinks, and ownership.
# ─────────────────────────────────────────────────────────────────────────────

setup() {
    load test_helper/common
}

@test "AC150: seed-volumes.sh module exists in container" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" test -f /usr/local/bin/lib/seed-volumes.sh
    [ "$status" -eq 0 ]
}

@test "AC151: seed_volumes function is defined" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c 'source /usr/local/bin/lib/constants.sh; source /usr/local/bin/lib/seed-volumes.sh; declare -f seed_volumes'
    [ "$status" -eq 0 ]
    [[ "$output" == *"seed_volumes ()"* ]]
}

@test "AC152: OpenCode skills directory exists after seeding" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c 'test -d /home/hermeswebui/.config/opencode/skills && echo "EXISTS"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"EXISTS"* ]]
}

@test "AC153: Hermes skills directory exists after seeding" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c 'test -d /home/hermeswebui/.hermes/skills && echo "EXISTS"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"EXISTS"* ]]
}

@test "AC154: Root symlinks for OpenCode config and skills exist" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        test -L /root/.config/opencode/opencode.jsonc && echo "CONFIG:LINK" || echo "CONFIG:MISSING"
        test -L /root/.config/opencode/skills && echo "SKILLS:LINK" || echo "SKILLS:MISSING"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"CONFIG:LINK"* ]]
    [[ "$output" == *"SKILLS:LINK"* ]]
}

@test "AC155: Root symlinks for Hermes config and skills exist" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        test -L /root/.hermes/config.yaml && echo "CONFIG:LINK" || echo "CONFIG:MISSING"
        test -L /root/.hermes/skills && echo "SKILLS:LINK" || echo "SKILLS:MISSING"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"CONFIG:LINK"* ]]
    [[ "$output" == *"SKILLS:LINK"* ]]
}

@test "AC156: seed_volumes respects SKIP_SKILL_INSTALL" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/constants.sh
        source /usr/local/bin/lib/seed-volumes.sh
        SKIP_SKILL_INSTALL=1 seed_volumes 2>&1
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP_SKILL_INSTALL=1"* ]] || [[ "$output" == *"skipping skill seeding"* ]]
}
