#!/usr/bin/env bash

PROJECT_DIR="$(cd "$(dirname "$BATS_TEST_DIRNAME")/.." && pwd)"
export PROJECT_DIR

if [ -f "$PROJECT_DIR/.env" ]; then
    set -a
    source "$PROJECT_DIR/.env"
    set +a
fi

COMPOSE_OPTS=(--project-name hermes_x_opencode -f "$PROJECT_DIR/docker-compose.yml")
# Append CI override if present (publishes ports for test curls to localhost).
if [ -f "$PROJECT_DIR/docker-compose.ci.yml" ]; then
    COMPOSE_OPTS+=(-f "$PROJECT_DIR/docker-compose.ci.yml")
fi

get_container() {
    docker compose "${COMPOSE_OPTS[@]}" ps -q hermes-opencode 2>/dev/null
}

wait_for_healthy() {
    local timeout=${1:-180}
    local elapsed=0
    while [ "$elapsed" -lt "$timeout" ]; do
        local cid
        cid=$(get_container)
        if [ -n "$cid" ]; then
            local status
            status=$(docker inspect --format='{{.State.Health.Status}}' "$cid" 2>/dev/null || echo "")
            if [ "$status" = "healthy" ]; then
                return 0
            fi
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    return 1
}

get_api_key() {
    local cid
    cid=$(get_container)
    if [ -z "$cid" ]; then
        echo ""
        return
    fi
    local key
    key=$(docker logs "$cid" 2>&1 | grep "Generated random HERMES_API_KEY" | sed 's/.*: //' | tail -1)
    if [ -z "$key" ]; then
        key="${HERMES_API_KEY:-}"
    fi
    echo "$key"
}

webui_base() {
    echo "http://localhost:${HERMES_WEBUI_PORT:-8787}"
}

gateway_base() {
    echo "http://localhost:${HERMES_API_PORT:-8642}"
}

opencode_base() {
    echo "http://localhost:${OPENCODE_SERVE_PORT:-4096}"
}

skip_if_no_secrets() {
    if [ -z "${OPENAI_BASE_URL:-}" ] || [ -z "${OPENAI_API_KEY:-}" ]; then
        skip "OPENAI_BASE_URL or OPENAI_API_KEY not set"
    fi
}

# Get the PID of the actual hermes gateway process (not the su/bash wrapper)
get_gateway_pid() {
    local cid="$1"
    docker exec "$cid" bash -c '
        ps aux | grep "[h]ermes gateway run" | grep -v "su \|bash -c " | head -1 | awk "{print \$2}"
    ' 2>/dev/null || echo ""
}
