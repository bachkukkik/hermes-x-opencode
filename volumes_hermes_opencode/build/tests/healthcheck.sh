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
    if timeout 3 bash -c "echo > /dev/tcp/127.0.0.1/4096" 2>/dev/null; then
        echo "OK  OpenCode Serve (port 4096 open)"
    else
        echo "FAIL  OpenCode Serve (port 4096)"
        failed=$((failed + 1))
    fi
else
    echo "SKIP  OpenCode Serve (OPENCODE_SERVE_ENABLED!=true)"
fi

if [ "${BROWSER_HUMAN_LOOP_ENABLED:-false}" = "true" ]; then
    if curl -sf --max-time 3 http://127.0.0.1:9222/json/version >/dev/null 2>&1; then
        echo "OK  Browser CDP (port 9222)"
    else
        echo "FAIL  Browser CDP (port 9222)"
        failed=$((failed + 1))
    fi
else
    echo "SKIP  Browser CDP (BROWSER_HUMAN_LOOP_ENABLED!=true)"
fi

if [ "$failed" -ne 0 ]; then
    echo "$failed service(s) unhealthy"
    exit 1
fi

echo "All services healthy"
exit 0
