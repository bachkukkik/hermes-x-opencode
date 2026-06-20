#!/usr/bin/env bats

# Tests for the righthand-man profile seeding (doc 22)
# The profile seed runs on every boot (not gated), so these tests always run.
# Verifies:
# 1. ~/.hermes/profiles/righthand-man/SOUL.md exists
# 2. SOUL.md contains the orchestrator doctrine ("Righthand-Man")
# 3. The profile directory is owned by hermeswebui
# 4. config.yaml exists (cloned from the default profile)

setup() {
    load test_helper/common
}

@test "PROF1: righthand-man profile seeded with SOUL.md" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run docker exec "$cid" test -f /home/hermeswebui/.hermes/profiles/righthand-man/SOUL.md
    [ "$status" -eq 0 ]
}

@test "PROF2: righthand-man SOUL.md contains orchestrator doctrine" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run docker exec "$cid" grep -q "Righthand-Man" /home/hermeswebui/.hermes/profiles/righthand-man/SOUL.md
    [ "$status" -eq 0 ]
}

@test "PROF3: righthand-man profile dir owned by hermeswebui" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run docker exec "$cid" stat -c '%U' /home/hermeswebui/.hermes/profiles/righthand-man
    [ "$status" -eq 0 ]
    [ "$output" = "hermeswebui" ]
}

@test "PROF4: righthand-man profile has config.yaml (cloned from default)" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run docker exec "$cid" test -f /home/hermeswebui/.hermes/profiles/righthand-man/config.yaml
    [ "$status" -eq 0 ]
}
