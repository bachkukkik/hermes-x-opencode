#!/usr/bin/env bats
# ─────────────────────────────────────────────────────────────────────────────
# 22-service-webui.bats — service-webui.sh start_webui function
# Verifies the WebUI startup helper creates dirs, sets ownership, and launches
# the init script under the hermeswebui user.
# ─────────────────────────────────────────────────────────────────────────────

setup() {
    load test_helper/common
}

@test "AC170: service-webui.sh module exists in container" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" test -f /usr/local/bin/lib/service-webui.sh
    [ "$status" -eq 0 ]
}

@test "AC171: start_webui function is defined" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c 'source /usr/local/bin/lib/constants.sh; source /usr/local/bin/lib/service-webui.sh; declare -f start_webui'
    [ "$status" -eq 0 ]
    [[ "$output" == *"start_webui()"* ]]
}

@test "AC172: start_webui creates state, workspace, and UV cache dirs" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    # After boot, these directories must exist
    run docker exec "$cid" bash -c '
        test -d "${HERMES_WEBUI_STATE_DIR:-/home/hermeswebui/.hermes/webui}" && echo "STATE:OK" || echo "STATE:MISSING"
        test -d "${HERMES_WEBUI_DEFAULT_WORKSPACE:-/workspace}" && echo "WORKSPACE:OK" || echo "WORKSPACE:MISSING"
        test -d "${UV_CACHE_DIR:-/uv_cache}" && echo "UV:OK" || echo "UV:MISSING"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"STATE:OK"* ]]
    [[ "$output" == *"WORKSPACE:OK"* ]]
    [[ "$output" == *"UV:OK"* ]]
}

@test "AC173: WebUI state dir is owned by hermeswebui" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" bash -c '
        stat -c "%U" "${HERMES_WEBUI_STATE_DIR:-/home/hermeswebui/.hermes/webui}"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"hermeswebui"* ]]
}

@test "AC174: hermeswebui_init.bash exists and is executable" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" test -x /hermeswebui_init.bash
    [ "$status" -eq 0 ]
}
