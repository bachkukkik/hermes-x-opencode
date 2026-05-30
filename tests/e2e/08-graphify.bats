#!/usr/bin/env bats

setup() {
    load test_helper/common
}

@test "graphify CLI available in container" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" test -x /usr/local/bin/graphify
    [ "$status" -eq 0 ]
}

@test "uv tool manager available in container" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" test -x /usr/local/bin/uv
    [ "$status" -eq 0 ]
}

@test "graphify Hermes skill registered" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" test -f /home/hermeswebui/.hermes/skills/graphify/SKILL.md
    [ "$status" -eq 0 ]
}

@test "graphify OpenCode skill registered" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" test -f /home/hermeswebui/.config/opencode/skills/graphify/SKILL.md
    [ "$status" -eq 0 ]
}

@test "graphify Hermes skill baked into staging dir during build" {
    local image="hermes_x_opencode-hermes-opencode:latest"
    run docker run --rm --entrypoint test "$image" -f /opt/hermes-skills-staging/graphify/SKILL.md
    [ "$status" -eq 0 ]
}

@test "graphify OpenCode skill baked into image during build" {
    local image="hermes_x_opencode-hermes-opencode:latest"
    run docker run --rm --entrypoint test "$image" -f /home/hermeswebui/.config/opencode/skills/graphify/SKILL.md
    [ "$status" -eq 0 ]
}
