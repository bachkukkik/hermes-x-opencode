#!/usr/bin/env bats

setup() {
    load test_helper/common
}

@test "AC11: second boot reaches healthy within 60 seconds" {
    docker compose "${COMPOSE_OPTS[@]}" down
    # Also stop any container holding our test ports (e.g. a manually-started
    # instance using the default hyphenated project name). Port collision on
    # 4096/8642/8787 causes "Bind failed: port already allocated".
    docker compose -f "$PROJECT_DIR/docker-compose.yml" -f "$PROJECT_DIR/docker-compose.ci.yml" down 2>/dev/null || true
    local start
    start=$(date +%s)

    docker compose "${COMPOSE_OPTS[@]}" up -d

    local timeout=300
    local elapsed=0
    while [ "$elapsed" -lt "$timeout" ]; do
        local cid
        cid=$(get_container)
        if [ -n "$cid" ]; then
            local status
            status=$(docker inspect --format='{{.State.Health.Status}}' "$cid" 2>/dev/null || echo "")
            if [ "$status" = "healthy" ]; then
                local end
                end=$(date +%s)
                local duration=$((end - start))
                echo "Second boot healthy in ${duration}s"
                [ "$duration" -lt 60 ]
                return 0
            fi
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done

    echo "Second boot did not become healthy within ${timeout}s"
    return 1
}
