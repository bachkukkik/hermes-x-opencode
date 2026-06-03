#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SKIP_BUILD="${SKIP_BUILD:-0}"
SKIP_CLEANUP="${SKIP_CLEANUP:-0}"
BATS_FLAGS="${BATS_FLAGS:-}"

COMPOSE_OPTS=(--project-name hermes_x_opencode -f "$PROJECT_DIR/docker-compose.yml")

cleanup() {
    if [ "$SKIP_CLEANUP" = "1" ]; then
        echo "== Skipping cleanup (SKIP_CLEANUP=1)"
        return
    fi
    echo "== Tearing down..."
    docker compose "${COMPOSE_OPTS[@]}" down -v --remove-orphans 2>/dev/null || true
}
trap cleanup EXIT

if ! command -v bats >/dev/null 2>&1; then
    echo "!! bats is not installed."
    echo "   Install with: sudo apt-get install bats"
    echo "   Or:           brew install bats-core"
    exit 1
fi

if [ ! -f "$PROJECT_DIR/.env" ]; then
    echo "!! .env file not found at $PROJECT_DIR/.env"
    echo "   Copy .env.example and fill in your API keys."
    exit 1
fi

cd "$PROJECT_DIR"

if [ "$SKIP_BUILD" = "1" ]; then
    echo "== Skipping build (SKIP_BUILD=1)"
else
    echo "== Building image..."
    docker compose "${COMPOSE_OPTS[@]}" build
fi

echo "== Starting stack..."
mkdir -p "${PROJECT_DIR}/volumes_hermes_opencode/data/workspace"
cp -f "${PROJECT_DIR}/AGENTS.md" "${PROJECT_DIR}/volumes_hermes_opencode/data/workspace/AGENTS.md"
docker compose "${COMPOSE_OPTS[@]}" up -d

HEALTH_TIMEOUT=${HEALTH_TIMEOUT:-300}
echo "== Waiting for stack to become healthy (up to ${HEALTH_TIMEOUT}s)..."
elapsed=0
while [ "$elapsed" -lt "$HEALTH_TIMEOUT" ]; do
    cid=$(docker compose "${COMPOSE_OPTS[@]}" ps -q hermes-opencode 2>/dev/null || true)
    if [ -n "$cid" ]; then
        status=$(docker inspect --format='{{.State.Health.Status}}' "$cid" 2>/dev/null || echo "")
        if [ "$status" = "healthy" ]; then
            echo "== Stack healthy after ${elapsed}s"
            break
        fi
    fi
    sleep 5
    elapsed=$((elapsed + 5))
done

if [ "$elapsed" -ge "$HEALTH_TIMEOUT" ]; then
    echo "!! Stack did not become healthy within ${HEALTH_TIMEOUT}s"
    docker compose "${COMPOSE_OPTS[@]}" logs --tail=50 2>/dev/null || true
    exit 1
fi

echo "== Running e2e tests..."
bats $BATS_FLAGS "$SCRIPT_DIR/e2e/"
