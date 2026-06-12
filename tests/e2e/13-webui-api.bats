#!/usr/bin/env bats

# Tests for WebUI API health endpoints (TT-03, TT-04)

setup() {
    load test_helper/common
}

# ------------------------------------------------------------------
# WebUI Health API (TT-03)
# ------------------------------------------------------------------

@test "AC17a: WebUI API serves JSON health response" {
    run curl -sf --max-time 5 "$(webui_base)/health"
    [ "$status" -eq 0 ]
    echo "$output" | python3 -c "
import sys, json
data = json.load(sys.stdin)
assert data.get('status') == 'ok', f'expected status=ok, got {data.get(\"status\")}'
"
}

# ------------------------------------------------------------------
# WebUI Health API - session count (TT-04)
# ------------------------------------------------------------------

@test "AC17b: WebUI health response includes session count" {
    run curl -sf --max-time 5 "$(webui_base)/health"
    [ "$status" -eq 0 ]
    echo "$output" | python3 -c "
import sys, json
data = json.load(sys.stdin)
sessions = data.get('sessions')
assert isinstance(sessions, int), f'expected int sessions, got {type(sessions).__name__}'
"
}
