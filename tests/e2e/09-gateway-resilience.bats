#!/usr/bin/env bats

# Tests for gateway process resilience (vanilla-coder#5)
# Verifies the restart-loop supervisor in start_gateway() works:
# when the gateway process is killed, it should come back automatically.

setup() {
    load test_helper/common
}

@test "VC5.1: gateway process is running" {
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" pgrep -f "hermes gateway run"
    [ "$status" -eq 0 ]
}

@test "VC5.2: gateway restart loop supervisor is active" {
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    # The supervisor is the parent shell running the while-true loop
    run docker exec "$cid" pgrep -af "while true"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "hermes gateway run"
}

@test "VC5.3: gateway survives SIGTERM and revives within 15 seconds" {
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    # Get the current gateway PID (actual process, not su/bash wrapper)
    local gateway_pid
    gateway_pid=$(get_gateway_pid "$cid")
    [ -n "$gateway_pid" ]

    # SIGTERM the gateway process
    docker exec "$cid" kill -TERM "$gateway_pid" 2>/dev/null || true

    # Wait up to 15 seconds for the supervisor to restart it
    local elapsed=0
    local revived=false
    while [ "$elapsed" -lt 15 ]; do
        sleep 1
        elapsed=$((elapsed + 1))
        local new_pid
        new_pid=$(docker exec "$cid" pgrep -f "hermes gateway run" 2>/dev/null | head -1)
        if [ -n "$new_pid" ] && [ "$new_pid" != "$gateway_pid" ]; then
            revived=true
            echo "Gateway revived with new PID $new_pid after ${elapsed}s"
            break
        fi
    done

    [ "$revived" = "true" ]
}

@test "VC5.4: gateway health endpoint recovers after SIGTERM" {
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    # Verify gateway is healthy before proceeding
    local settle=0
    while [ "$settle" -lt 10 ]; do
        if curl -sf --max-time 3 "$(gateway_base)/health" >/dev/null 2>&1; then
            break
        fi
        sleep 1
        settle=$((settle + 1))
    done

    # Kill the gateway (real process, not su/bash wrapper)
    local gateway_pid
    gateway_pid=$(get_gateway_pid "$cid")
    [ -n "$gateway_pid" ] || skip "gateway not running"
    echo "Killing gateway PID: $gateway_pid"
    docker exec "$cid" kill -TERM "$gateway_pid" 2>/dev/null || true

    # Wait up to 20 seconds for health endpoint to recover
    local elapsed=0
    local recovered=false
    while [ "$elapsed" -lt 20 ]; do
        sleep 2
        elapsed=$((elapsed + 2))
        if curl -sf --max-time 3 "$(gateway_base)/health" >/dev/null 2>&1; then
            recovered=true
            echo "Gateway health recovered after ${elapsed}s"
            break
        fi
    done

    [ "$recovered" = "true" ]
}

@test "VC5.5: restart event logged to HERMES_HOME/logs/gateway-restart.log" {
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    # Wait for gateway to be running, then kill to trigger a restart event
    local gateway_pid=""
    local pid_wait=0
    while [ "$pid_wait" -lt 10 ]; do
        gateway_pid=$(get_gateway_pid "$cid")
        [ -n "$gateway_pid" ] && break
        sleep 1
        pid_wait=$((pid_wait + 1))
    done
    [ -n "$gateway_pid" ] || skip "gateway not running (cannot test restart log)"
    echo "Killing gateway PID: $gateway_pid"
    docker exec "$cid" kill -TERM "$gateway_pid" 2>/dev/null || true

    # Wait for restart
    sleep 8

    # Check the restart log in the persistent bind-mounted path
    run docker exec "$cid" cat /home/hermeswebui/.hermes/logs/gateway-restart.log
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "gateway exited"
    echo "$output" | grep -q "restarting in 2s"
}
