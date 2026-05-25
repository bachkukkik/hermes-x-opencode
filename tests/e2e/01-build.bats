#!/usr/bin/env bats

setup() {
    load test_helper/common
}

@test "AC1: docker compose build succeeds" {
    run docker compose "${COMPOSE_OPTS[@]}" build
    [ "$status" -eq 0 ]
}

@test "AC25: skills baked into Docker image (staging dir populated)" {
    local image="hermes_x_opencode-hermes-opencode:latest"
    local staging_count
    staging_count=$(docker run --rm --entrypoint find "$image" /opt/hermes-skills-staging -name "SKILL.md" 2>/dev/null | wc -l)
    [ "$staging_count" -gt 0 ]
    local opencode_count
    opencode_count=$(docker run --rm --entrypoint find "$image" /home/hermeswebui/.config/opencode/skills -name "SKILL.md" 2>/dev/null | wc -l)
    [ "$opencode_count" -gt 0 ]
}

@test "AC10: no secrets in tracked files" {
    run bash -c 'cd "$PROJECT_DIR" && git ls-files -z | xargs -0 grep -rl "sk-[a-zA-Z0-9]\{48,\}" 2>/dev/null || true'
    [ -z "$output" ]
}
