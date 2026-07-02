#!/usr/bin/env bats
# ─────────────────────────────────────────────────────────────────────────────
# 21-symlink-cleanup.bats — symlink-cleanup.sh cleanup_symlink_loops function
# Verifies removal of self-referential skills symlinks and snapshot cache.
# ─────────────────────────────────────────────────────────────────────────────

setup() {
    load test_helper/common
}

@test "AC160: symlink-cleanup.sh module exists in container" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" test -f /usr/local/bin/lib/symlink-cleanup.sh
    [ "$status" -eq 0 ]
}

@test "AC161: cleanup_symlink_loops function is defined" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c 'source /usr/local/bin/lib/constants.sh; source /usr/local/bin/lib/symlink-cleanup.sh; declare -f cleanup_symlink_loops'
    [ "$status" -eq 0 ]
    [[ "$output" == *"cleanup_symlink_loops ()"* ]]
}

@test "AC162: No self-referential skills symlinks in OpenCode skills dir" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        find /home/hermeswebui/.config/opencode/skills -maxdepth 1 -type l -name "skills" 2>/dev/null | wc -l
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"0"* ]]
}

@test "AC163: No self-referential skills symlinks in Hermes skills dir" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        find /home/hermeswebui/.hermes/skills -maxdepth 1 -type l -name "skills" 2>/dev/null | wc -l
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"0"* ]]
}

@test "AC164: .skills_prompt_snapshot.json is absent after cleanup" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/constants.sh
        source /usr/local/bin/lib/symlink-cleanup.sh
        cleanup_symlink_loops
        test -f /home/hermeswebui/.hermes/.skills_prompt_snapshot.json && echo "EXISTS" || echo "GONE"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"GONE"* ]]
}

@test "AC165: cleanup_symlink_loops is idempotent" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/constants.sh
        source /usr/local/bin/lib/symlink-cleanup.sh
        cleanup_symlink_loops
        cleanup_symlink_loops
        echo "SUCCESS"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"SUCCESS"* ]]
}
