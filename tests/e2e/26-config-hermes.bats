#!/usr/bin/env bats
# ─────────────────────────────────────────────────────────────────────────────
# 26-config-hermes.bats — config-hermes.sh: hermes config.yaml generation
# ─────────────────────────────────────────────────────────────────────────────

setup() {
    load test_helper/common
}

@test "AC213: config-hermes.sh module exists in container" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" test -f /usr/local/bin/lib/config-hermes.sh
    [ "$status" -eq 0 ]
}

@test "AC214: resolve_ctx_len returns pinned values for known model families" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/config-hermes.sh
        echo "deepseek-v4: $(resolve_ctx_len deepseek-v4)"
        echo "gpt-4o: $(resolve_ctx_len gpt-4o)"
        echo "gemini: $(resolve_ctx_len gemini)"
        echo "glm-5.2: $(resolve_ctx_len glm-5.2)"
        echo "agents-a1-mtp-apex: $(resolve_ctx_len llama_cpp/agents-a1-mtp-apex-i-balanced)"
        echo "agents-a1-q4: $(resolve_ctx_len llama_cpp/agents-a1-q4_k_m)"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"deepseek-v4: 1000000"* ]]
    [[ "$output" == *"gpt-4o: 128000"* ]]
    [[ "$output" == *"gemini: 1048576"* ]]
    [[ "$output" == *"glm-5.2: 1048576"* ]]
    # agents-a1 llama.cpp families (bridged from host-machine PR #20) — canonical
    # per-module assertion so this file is self-sufficient (mirrors 19-CTX5).
    [[ "$output" == *"agents-a1-mtp-apex: 262144"* ]]
    [[ "$output" == *"agents-a1-q4: 262144"* ]]
}

@test "AC215: resolve_ctx_len returns empty for unknown models" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/config-hermes.sh
        result=$(resolve_ctx_len "unknown-model-xyz")
        echo "result=[${result}]"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"result=[]"* ]]
}

@test "AC216: generate_config and append_skills_external_dirs functions are defined" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/config-hermes.sh
        declare -f generate_config
        declare -f append_skills_external_dirs
        echo "OK"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "AC244: HERMES_MAX_TOKENS bakes model.max_tokens (set int / unset / non-integer)" {
    # Bridged from host-machine PR #24. HERMES_MAX_TOKENS is the OUTPUT-token cap
    # Hermes sends per request; unset lets the upstream provider apply a small
    # default that truncates long responses (finish_reason='length'), incl.
    # delegation subagents (they inherit the parent max_tokens). Hermetic: temp
    # CONFIG + a single DISCOVERED_MODELS entry, log/warn stubbed, so it does not
    # touch the live config. Exercises all three branches of the integer guard.
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/config-hermes.sh
        log() { :; }; warn() { :; }
        export OPENAI_BASE_URL="http://127.0.0.1:9/v1"
        export DISCOVERED_MODELS="openai/gpt-4o"
        export HERMES_DEFAULT_MODEL="openai/gpt-4o"

        export HERMES_MAX_TOKENS=32000
        export CONFIG=$(mktemp)
        generate_config
        echo "SET: $(grep -c "max_tokens: 32000" "$CONFIG")"
        rm -f "$CONFIG"

        unset HERMES_MAX_TOKENS
        export CONFIG=$(mktemp)
        generate_config
        echo "UNSET: $(grep -c "max_tokens" "$CONFIG")"
        rm -f "$CONFIG"

        export HERMES_MAX_TOKENS=not-a-number
        export CONFIG=$(mktemp)
        generate_config
        echo "INVALID: $(grep -c "max_tokens" "$CONFIG")"
        rm -f "$CONFIG"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"SET: 1"* ]]
    [[ "$output" == *"UNSET: 0"* ]]
    [[ "$output" == *"INVALID: 0"* ]]
}

@test "AC243: append_skills_external_dirs appends the block once and is idempotent" {
    # T5: exercise the append + "already present" grep-guard (config-hermes.sh:210-213).
    # Hermetic: temp HERMES_HOME with a fake optional-skills dir + temp CONFIG, so the
    # test does not depend on container env or mutate the live config.
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/config-hermes.sh
        log() { :; }; warn() { :; }
        export HERMES_HOME=$(mktemp -d)
        mkdir -p "$HERMES_HOME/hermes-agent/optional-skills"
        export CONFIG=$(mktemp)
        printf "model:\n  default: x\n" > "$CONFIG"
        append_skills_external_dirs
        first=$(grep -c "external_dirs" "$CONFIG")
        append_skills_external_dirs
        second=$(grep -c "external_dirs" "$CONFIG")
        echo "first=$first second=$second"
        rm -rf "$HERMES_HOME" "$CONFIG"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"first=1 second=1"* ]]
}

@test "AC252: generate_config emits agent.max_turns from HERMES_AGENT_MAX_TURNS" {
    # Regression for the "Reached maximum iterations (90)" bug: config-hermes.sh
    # must write a top-level `agent:` block with `max_turns` (the main agent-loop
    # cap the gateway bridges to agent.max_iterations) — distinct from the
    # goals/delegation blocks. Hermetic: temp CONFIG + minimal path (empty
    # OPENAI_BASE_URL) so it is deterministic and needs no LLM secrets. A unique
    # value (177) disambiguates it from goals.max_turns (default 50).
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/constants.sh
        source /usr/local/bin/lib/config-hermes.sh
        log() { :; }; warn() { :; }
        export HERMES_AGENT_MAX_TURNS=177
        export OPENAI_BASE_URL=""
        export HERMES_HOME=$(mktemp -d)
        export CONFIG="$HERMES_HOME/config.yaml"
        generate_config >/dev/null 2>&1
        # Extract the agent block max_turns specifically (not goals/delegation).
        awk "/^agent:/{f=1;next} f&&/max_turns:/{print \"agent.max_turns=\"\$2; exit}" "$CONFIG"
        rm -rf "$HERMES_HOME"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"agent.max_turns=177"* ]]
}

@test "AC253: agent.max_turns is emitted independently of goals/delegation budgets" {
    # The original bug: raising only goals/delegation left the main loop pinned at
    # the built-in 90 because agent.max_turns was never written. Assert all three
    # land as distinct values so a future regression that drops the agent block
    # (or aliases it to goals) is caught. Full path (non-empty OPENAI_BASE_URL +
    # one discovered model) so the goals block is emitted alongside agent.
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/constants.sh
        source /usr/local/bin/lib/config-hermes.sh
        log() { :; }; warn() { :; }
        export HERMES_YOLO_MODE=1
        export HERMES_AGENT_MAX_TURNS=111
        export HERMES_GOAL_MAX_TURNS=122
        export HERMES_DELEGATION_MAX_ITERATIONS=133
        export OPENAI_BASE_URL="http://localhost:9999"
        export DISCOVERED_MODELS="openai/gpt-4o"
        export HERMES_DEFAULT_MODEL="openai/gpt-4o"
        export HERMES_HOME=$(mktemp -d)
        export CONFIG="$HERMES_HOME/config.yaml"
        generate_config >/dev/null 2>&1
        a=$(awk "/^agent:/{f=1;next} f&&/max_turns:/{print \$2; exit}" "$CONFIG")
        g=$(awk "/^goals:/{f=1;next} f&&/max_turns:/{print \$2; exit}" "$CONFIG")
        d=$(awk "/^delegation:/{f=1;next} f&&/max_iterations:/{print \$2; exit}" "$CONFIG")
        echo "a=$a g=$g d=$d"
        rm -rf "$HERMES_HOME"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"a=111 g=122 d=133"* ]]
}
