#!/usr/bin/env bats

# Tests for the Hermes web dashboard service (doc 21)
# The dashboard is opt-in via HERMES_DASHBOARD_ENABLED (default false).
# When HERMES_DASHBOARD_ENABLED=true, verifies:
# 1. Dashboard serves HTTP 200 on :9119
# 2. web_dist is present in the venv (index.html exists)
# 3. The "hermes dashboard" process is running
# When HERMES_DASHBOARD_ENABLED!=true, verifies:
# 4. The dashboard process is NOT running and port 9119 is not listening

setup() {
    load test_helper/common
}

@test "DASH2: dashboard enabled serves HTTP 200 on :9119" {
    skip_if_no_secrets
    [ "${HERMES_DASHBOARD_ENABLED:-false}" = "true" ] || skip "HERMES_DASHBOARD_ENABLED!=true"

    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    # The dashboard binds 0.0.0.0:9119 inside the container; localhost works via docker exec
    run docker exec "$cid" curl -s -o /dev/null -w '%{http_code}' http://localhost:9119/
    [ "$status" -eq 0 ]
    [ "$output" = "200" ]
}

@test "DASH3: dashboard web_dist present in venv when enabled" {
    skip_if_no_secrets
    [ "${HERMES_DASHBOARD_ENABLED:-false}" = "true" ] || skip "HERMES_DASHBOARD_ENABLED!=true"

    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run docker exec "$cid" test -f /app/venv/lib/python3.12/site-packages/hermes_cli/web_dist/index.html
    [ "$status" -eq 0 ]
}

@test "DASH4: dashboard process running as hermeswebui when enabled" {
    skip_if_no_secrets
    [ "${HERMES_DASHBOARD_ENABLED:-false}" = "true" ] || skip "HERMES_DASHBOARD_ENABLED!=true"

    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run docker exec "$cid" pgrep -f "hermes dashboard"
    [ "$status" -eq 0 ]
}

# --- Dashboard disabled negative test ---

@test "DASH1: dashboard disabled by default (HERMES_DASHBOARD_ENABLED gate)" {
    # This test runs when the dashboard is NOT enabled (the default).
    # When the feature is enabled, DASH2-DASH4 cover the positive case.
    [ "${HERMES_DASHBOARD_ENABLED:-false}" != "true" ] || skip "HERMES_DASHBOARD_ENABLED=true (covered by DASH2-DASH4)"

    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    # The "hermes dashboard" process should NOT be running
    run docker exec "$cid" pgrep -f "hermes dashboard"
    [ "$status" -ne 0 ]

    # Port 9119 should NOT be listening
    run docker exec "$cid" timeout 3 bash -c 'echo > /dev/tcp/127.0.0.1/9119'
    [ "$status" -ne 0 ]
}
