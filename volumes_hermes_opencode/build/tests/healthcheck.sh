#!/usr/bin/env bash
set -euo pipefail

failed=0

check() {
    local url="$1" name="$2"
    if curl -sf --max-time 3 "$url" >/dev/null 2>&1; then
        echo "OK  $name ($url)"
    else
        echo "FAIL  $name ($url)"
        failed=$((failed + 1))
    fi
}

check "http://localhost:8787/health" "Hermes WebUI"
check "http://localhost:8642/health" "Hermes Gateway"
if [ "${OPENCODE_SERVE_ENABLED:-false}" = "true" ]; then
    check "http://localhost:4096/"         "OpenCode Serve"
else
    echo "SKIP  OpenCode Serve (OPENCODE_SERVE_ENABLED!=true)"
fi

if [ "$failed" -ne 0 ]; then
    echo "$failed service(s) unhealthy"
    exit 1
fi

echo "All services healthy"
exit 0
