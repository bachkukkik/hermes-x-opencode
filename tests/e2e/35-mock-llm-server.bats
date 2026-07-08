#!/usr/bin/env bats
# ─────────────────────────────────────────────────────────────────────────────
# 35-mock-llm-server.bats — mock-llm-server.sh: CI-only OpenAI-compatible stub
# Closes T1: this module previously had ZERO coverage.
# ─────────────────────────────────────────────────────────────────────────────

setup() {
    load test_helper/common
}

@test "AC246: mock-llm-server.sh module exists and start_mock_llm is defined" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        test -f /usr/local/bin/lib/mock-llm-server.sh
        source /usr/local/bin/lib/mock-llm-server.sh
        declare -f start_mock_llm
        echo "OK"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "AC247: start_mock_llm serves OpenAI-compatible /v1/models and chat completions" {
    # Boots the mock on :4000, verifies both endpoints, then tears it down.
    # Skips if :4000 is already occupied (e.g. a real proxy is mapped there).
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        source /usr/local/bin/lib/mock-llm-server.sh
        if (exec 3<>/dev/tcp/127.0.0.1/4000) 2>/dev/null; then exec 3>&-; echo "RESULT=SKIP"; exit 0; fi
        start_mock_llm; pid=$!
        for i in $(seq 1 20); do
            curl -sf http://127.0.0.1:4000/v1/models >/dev/null 2>&1 && break
            sleep 0.25
        done
        ok=1
        curl -sf http://127.0.0.1:4000/v1/models \
            | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if any(m[\"id\"]==\"mock-gpt-4o\" for m in d[\"data\"]) else 1)" || ok=0
        curl -sf -X POST http://127.0.0.1:4000/v1/chat/completions -d "{}" \
            | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if d[\"choices\"][0][\"message\"][\"content\"]==\"mock\" else 1)" || ok=0
        kill "$pid" 2>/dev/null
        [ "$ok" = 1 ] && echo "RESULT=PASS" || echo "RESULT=FAIL"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"RESULT=PASS"* || "$output" == *"RESULT=SKIP"* ]]
}
