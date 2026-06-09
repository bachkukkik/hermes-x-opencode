#!/usr/bin/env bats

# Test group: Wiki Initialization (WI)
# Verifies: AC18 - Wiki auto-init on first boot
#
# Checks that inside the Docker container:
# 1. WIKI_PATH env var is set to /home/hermeswebui/.hermes/wiki
# 2. Wiki directory exists and has backbone files (SCHEMA.md, index.md, log.md)
# 3. Wiki subdirectories exist (raw/articles, entities, concepts, comparisons, queries)
# 4. SCHEMA.md contains expected domain header
# 5. File ownership is hermeswebui:hermeswebui

setup() {
    load test_helper/common
}

# --- WI1: Environment variable ---

@test "WI1.1: WIKI_PATH env var is set to /home/hermeswebui/.hermes/wiki" {
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run docker exec "$cid" printenv WIKI_PATH
    [ "$status" -eq 0 ]
    [ "$output" = "/home/hermeswebui/.hermes/wiki" ]
}

# --- WI2: Backbone files ---

@test "WI2.1: wiki directory exists" {
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run docker exec "$cid" test -d /home/hermeswebui/.hermes/wiki
    [ "$status" -eq 0 ]
}

@test "WI2.2: SCHEMA.md exists" {
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run docker exec "$cid" test -f /home/hermeswebui/.hermes/wiki/SCHEMA.md
    [ "$status" -eq 0 ]
}

@test "WI2.3: index.md exists" {
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run docker exec "$cid" test -f /home/hermeswebui/.hermes/wiki/index.md
    [ "$status" -eq 0 ]
}

@test "WI2.4: log.md exists" {
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run docker exec "$cid" test -f /home/hermeswebui/.hermes/wiki/log.md
    [ "$status" -eq 0 ]
}

# --- WI3: Subdirectories ---

@test "WI3.1: raw/articles subdirectory exists" {
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run docker exec "$cid" test -d /home/hermeswebui/.hermes/wiki/raw/articles
    [ "$status" -eq 0 ]
}

@test "WI3.2: entities subdirectory exists" {
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run docker exec "$cid" test -d /home/hermeswebui/.hermes/wiki/entities
    [ "$status" -eq 0 ]
}

@test "WI3.3: concepts subdirectory exists" {
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run docker exec "$cid" test -d /home/hermeswebui/.hermes/wiki/concepts
    [ "$status" -eq 0 ]
}

@test "WI3.4: comparisons subdirectory exists" {
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run docker exec "$cid" test -d /home/hermeswebui/.hermes/wiki/comparisons
    [ "$status" -eq 0 ]
}

@test "WI3.5: queries subdirectory exists" {
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run docker exec "$cid" test -d /home/hermeswebui/.hermes/wiki/queries
    [ "$status" -eq 0 ]
}

# --- WI4: SCHEMA.md content ---

@test "WI4.1: SCHEMA.md contains domain header" {
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run docker exec "$cid" head -5 /home/hermeswebui/.hermes/wiki/SCHEMA.md
    [ "$status" -eq 0 ]
    echo "$output" | grep -qi "domain"
}

# --- WI5: File ownership ---

@test "WI5.1: wiki directory owned by hermeswebui:hermeswebui" {
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run docker exec "$cid" stat -c '%U:%G' /home/hermeswebui/.hermes/wiki
    [ "$status" -eq 0 ]
    [ "$output" = "hermeswebui:hermeswebui" ]
}

@test "WI5.2: SCHEMA.md owned by hermeswebui:hermeswebui" {
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run docker exec "$cid" stat -c '%U:%G' /home/hermeswebui/.hermes/wiki/SCHEMA.md
    [ "$status" -eq 0 ]
    [ "$output" = "hermeswebui:hermeswebui" ]
}

@test "WI5.3: index.md owned by hermeswebui:hermeswebui" {
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run docker exec "$cid" stat -c '%U:%G' /home/hermeswebui/.hermes/wiki/index.md
    [ "$status" -eq 0 ]
    [ "$output" = "hermeswebui:hermeswebui" ]
}

@test "WI5.4: log.md owned by hermeswebui:hermeswebui" {
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run docker exec "$cid" stat -c '%U:%G' /home/hermeswebui/.hermes/wiki/log.md
    [ "$status" -eq 0 ]
    [ "$output" = "hermeswebui:hermeswebui" ]
}

@test "WI5.5: raw subdirectory owned by hermeswebui:hermeswebui" {
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run docker exec "$cid" stat -c '%U:%G' /home/hermeswebui/.hermes/wiki/raw
    [ "$status" -eq 0 ]
    [ "$output" = "hermeswebui:hermeswebui" ]
}
