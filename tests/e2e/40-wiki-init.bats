#!/usr/bin/env bats
# ─────────────────────────────────────────────────────────────────────────────
# 40-wiki-init.bats — wiki-init.sh wiki initialization
# Verifies wiki directory structure and files are created correctly.
# ─────────────────────────────────────────────────────────────────────────────

setup() {
    load test_helper/common
}

@test "AC230: wiki-init.sh module exists in container" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" test -f /usr/local/bin/lib/wiki-init.sh
    [ "$status" -eq 0 ]
}

@test "AC231: init_wiki function is defined" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c 'source /usr/local/bin/lib/constants.sh; source /usr/local/bin/lib/wiki-init.sh; declare -f init_wiki'
    [ "$status" -eq 0 ]
    [[ "$output" == *"init_wiki ()"* ]]
}

@test "AC232: wiki directory structure is created" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/constants.sh
        source /usr/local/bin/lib/wiki-init.sh
        export WIKI_DIR="/tmp/wiki-test-$$"
        mkdir -p "$WIKI_DIR"
        init_wiki
        find "$WIKI_DIR" -type d | sort
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"$WIKI_DIR/raw"* ]]
    [[ "$output" == *"$WIKI_DIR/entities"* ]]
    [[ "$output" == *"$WIKI_DIR/concepts"* ]]
    [[ "$output" == *"$WIKI_DIR/comparisons"* ]]
    [[ "$output" == *"$WIKI_DIR/queries"* ]]
}

@test "AC233: SCHEMA.md is created" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/constants.sh
        source /usr/local/bin/lib/wiki-init.sh
        export WIKI_DIR="/tmp/wiki-test-$$"
        mkdir -p "$WIKI_DIR"
        init_wiki
        cat "$WIKI_DIR/SCHEMA.md"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"Wiki Schema"* ]]
    [[ "$output" == *"Hermes x OpenCode Docker Stack"* ]]
}

@test "AC234: index.md is created" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/constants.sh
        source /usr/local/bin/lib/wiki-init.sh
        export WIKI_DIR="/tmp/wiki-test-$$"
        mkdir -p "$WIKI_DIR"
        init_wiki
        cat "$WIKI_DIR/index.md"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"Wiki Index"* ]]
    [[ "$output" == *"## Entities"* ]]
    [[ "$output" == *"## Concepts"* ]]
}

@test "AC235: log.md is created" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/constants.sh
        source /usr/local/bin/lib/wiki-init.sh
        export WIKI_DIR="/tmp/wiki-test-$$"
        mkdir -p "$WIKI_DIR"
        init_wiki
        cat "$WIKI_DIR/log.md"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"Wiki Log"* ]]
    [[ "$output" == *"Wiki initialized"* ]]
}

@test "AC236: wiki-init.sh is idempotent" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/constants.sh
        source /usr/local/bin/lib/wiki-init.sh
        export WIKI_DIR="/tmp/wiki-test-$$"
        mkdir -p "$WIKI_DIR"
        init_wiki
        init_wiki  # Second call should return early
        echo "SUCCESS"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"SUCCESS"* ]]
}

@test "AC237: wiki-init.sh respects WIKI_DIR not set" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/constants.sh
        source /usr/local/bin/lib/wiki-init.sh
        unset WIKI_DIR
        init_wiki 2>&1
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"WIKI_DIR not set"* ]]
}
