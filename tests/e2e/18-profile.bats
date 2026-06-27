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

@test "PROF5: righthand-man skills/ has same count as default skills/" {
    cid=$(get_container)
    local default_count righthand_count
    default_count=$(docker exec "$cid" find /home/hermeswebui/.hermes/skills -name SKILL.md 2>/dev/null | wc -l)
    righthand_count=$(docker exec "$cid" find /home/hermeswebui/.hermes/profiles/righthand-man/skills -name SKILL.md 2>/dev/null | wc -l)
    echo "Default skills: $default_count, righthand-man skills: $righthand_count"
    [ "$default_count" -gt 0 ]
    [ "$default_count" -eq "$righthand_count" ]
}

@test "PROF6: righthand-man SOUL.md has routing doctrine (updated on every boot)" {
    cid=$(get_container)
    run docker exec "$cid" grep -c 'Routing — skills, built-in tools' /home/hermeswebui/.hermes/profiles/righthand-man/SOUL.md
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "PROF7: righthand-man config.yaml uses same model and provider as default" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run docker exec "$cid" /bin/bash -c '
        def_model=$(sed -n "3p" /home/hermeswebui/.hermes/config.yaml | awk "{print \$2}")
        def_prov=$(sed -n "2p" /home/hermeswebui/.hermes/config.yaml | awk "{print \$2}")
        rh_model=$(sed -n "3p" /home/hermeswebui/.hermes/profiles/righthand-man/config.yaml | awk "{print \$2}")
        rh_prov=$(sed -n "2p" /home/hermeswebui/.hermes/profiles/righthand-man/config.yaml | awk "{print \$2}")
        if [ "$def_model" = "$rh_model" ] && [ "$def_prov" = "$rh_prov" ]; then echo "MATCH"; else echo "MISMATCH: def=${def_model} rh=${rh_model}"; fi
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *MATCH* ]]
}

@test "PROF8: all routed SKILLS are loadable in the container" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    # Skills (load via skill_view) — must exist as SKILL.md somewhere Hermes can load them:
    # hermes skills dir, righthand-man profile skills, OpenCode skills dir, or optional-skills.
    local missing=""
    for skill in \
        karpathy-guidelines \
        opencode-plan-build-orchestrator \
        dogfood \
        security-best-practices \
        webapp-testing \
        coding-agents-docs-guideline \
        yeet; do
        if ! docker exec "$cid" bash -c \
            "find /home/hermeswebui/.hermes/skills \
                 /home/hermeswebui/.hermes/profiles/righthand-man/skills \
                 /home/hermeswebui/.config/opencode/skills \
                 /home/hermeswebui/.hermes/hermes-agent/optional-skills \
                 -name SKILL.md -path '*${skill}*' 2>/dev/null | grep -q ."; then
            missing="${missing} ${skill}"
        fi
    done

    [ -z "$missing" ] || { echo "Missing routed skills:${missing}"; false; }
}

@test "PROF9: routed BUILT-IN TOOLS are available in the container" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    # Built-in Hermes tools (not skills) — kanban is a hermes subcommand,
    # browser is a toolset backed by CDP on port 9222.
    run docker exec "$cid" /app/venv/bin/hermes kanban --help
    [ "$status" -eq 0 ]

    run docker exec "$cid" /app/venv/bin/hermes tools list
    [ "$status" -eq 0 ]
    echo "$output" | grep -q 'browser'
}
