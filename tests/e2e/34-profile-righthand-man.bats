#!/usr/bin/env bats
# ─────────────────────────────────────────────────────────────────────────────
# 34-profile-righthand-man.bats — profile-righthand-man.sh: profile seeding
# ─────────────────────────────────────────────────────────────────────────────

setup() {
    load test_helper/common
}

@test "AC239: profile-righthand-man.sh module exists in container" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" test -f /usr/local/bin/lib/profile-righthand-man.sh
    [ "$status" -eq 0 ]
}

@test "AC240: seed_righthand_man function is defined" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/profile-righthand-man.sh
        declare -f seed_righthand_man
        echo "OK"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "AC241: righthand-man profile directory exists after entrypoint runs" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" test -d /home/hermeswebui/.hermes/profiles/righthand-man
    [ "$status" -eq 0 ]
}

@test "AC242: righthand-man SOUL.md exists with mandated skills section" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        if [ -f /home/hermeswebui/.hermes/profiles/righthand-man/SOUL.md ]; then
            cat /home/hermeswebui/.hermes/profiles/righthand-man/SOUL.md
        fi
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"MANDATED SKILLS"* ]]
}
