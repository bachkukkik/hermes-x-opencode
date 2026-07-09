#!/usr/bin/env bats
# ─────────────────────────────────────────────────────────────────────────────
# 39-install-skills.bats — install-skills.sh skills installation
# Verifies skill installation from all 6 upstream sources.
# ─────────────────────────────────────────────────────────────────────────────

setup() {
    load test_helper/common
}

@test "AC210: install-skills.sh module exists in container" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" test -f /usr/local/bin/install-skills.sh
    [ "$status" -eq 0 ]
}

@test "AC211: install-skills.sh is executable" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" test -x /usr/local/bin/install-skills.sh
    [ "$status" -eq 0 ]
}

@test "AC212: install-skills.sh runs successfully" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        HERMES_SKILLS_DIR=/home/hermeswebui/.hermes/skills
        OPENCODE_SKILLS_DIR=/home/hermeswebui/.config/opencode/skills
        /usr/local/bin/install-skills.sh 2>&1
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"All skills installed successfully"* ]] || \
    [[ "$output" == *"installed and registered"* ]] || \
    [[ "$output" == *"Copied"* ]]
}

@test "AC213: anthropic skills are installed" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    # Check for at least one of the 6 anthropic skills
    run docker exec "$cid" bash -c '
        count=$(find /home/hermeswebui/.config/opencode/skills -maxdepth 1 -type d -name "algorithmic-art" -o -name "frontend-design" -o -name "web-artifacts-builder" -o -name "webapp-testing" -o -name "internal-comms" -o -name "skill-creator" 2>/dev/null | wc -l)
        echo "$count"
    '
    [ "$status" -eq 0 ]
    [ "$output" -gt 0 ]
}

@test "AC214: openai skills are installed" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        count=$(find /home/hermeswebui/.config/opencode/skills -maxdepth 1 -type d \( -name "jupyter-notebook" -o -name "yeet" -o -name "playwright-interactive" -o -name "security-best-practices" \) 2>/dev/null | wc -l)
        echo "$count"
    '
    [ "$status" -eq 0 ]
    [ "$output" -gt 0 ]
}

@test "AC215: karpathy-guidelines is installed" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        test -d /home/hermeswebui/.config/opencode/skills/karpathy-guidelines && echo "FOUND" || echo "MISSING"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"FOUND"* ]]
}

@test "AC216: opencode-plan-build-orchestrator is installed" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        test -d /home/hermeswebui/.config/opencode/skills/opencode-plan-build-orchestrator && echo "FOUND" || echo "MISSING"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"FOUND"* ]]
}

@test "AC217: pm-skills are installed to hermes" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        count=$(find /home/hermeswebui/.hermes/skills/product-management -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
        echo "$count"
    '
    [ "$status" -eq 0 ]
    [ "$output" -gt 10 ]  # Should have many pm skills
}

@test "AC218: llm-wiki is installed to both opencode and hermes" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        oc_has=0; hermes_has=0
        test -d /home/hermeswebui/.config/opencode/skills/llm-wiki && oc_has=1
        test -d /home/hermeswebui/.hermes/skills/research/llm-wiki && hermes_has=1
        echo "$oc_has $hermes_has"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"1 1"* ]]
}

@test "AC219: graphify is installed and registered" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        test -x /usr/local/bin/graphify && echo "CLI:OK" || echo "CLI:MISSING"
        test -d /home/hermeswebui/.config/opencode/skills/graphify && echo "OC:OK" || echo "OC:MISSING"
        test -d /home/hermeswebui/.hermes/skills/graphify && echo "HERMES:OK" || echo "HERMES:MISSING"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"CLI:OK"* ]]
    [[ "$output" == *"OC:OK"* ]]
    [[ "$output" == *"HERMES:OK"* ]]
}

@test "AC220: install-skills.sh respects SKIP_SKILL_INSTALL" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        SKIP_SKILL_INSTALL=1 /usr/local/bin/install-skills.sh 2>&1
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP_SKILL_INSTALL"* ]] || [[ "$output" == *"skip"* ]]
}
