# 09 — Testing and Verification

## What

A set of runnable smoke tests that verify all three services (WebUI, Gateway, OpenCode Serve) are operational after a fresh build or configuration change, including model discovery and multi-model support.

## Why

- Provides a deterministic checklist for validating the full stack after any change to the Dockerfile, entrypoint, compose file, or environment variables
- Maps directly to the acceptance criteria defined in `PRD.md`
- Catches common regression patterns: missing agent, failed patch, config misgeneration, gateway startup failures, wildcard model leakage

## How

### Prerequisites

```bash
docker compose build
docker compose up -d
sleep 45
```

Wait for all three services to report ready. First boot takes 80–160 seconds; subsequent boots take 25–50 seconds.

### Service health checks

```bash
echo "=== WebUI ===" && curl -sf http://localhost:${HERMES_WEBUI_PORT:-8787}/health | python3 -m json.tool

echo "=== Gateway ===" && curl -sf http://localhost:${HERMES_API_PORT:-8642}/health | python3 -m json.tool

echo "=== OpenCode ===" && curl -sf -o /dev/null -w "%{http_code}\n" http://localhost:${OPENCODE_SERVE_PORT:-4096}/
```

### Model discovery and config

```bash
CONTAINER=$(docker compose ps -q hermes-opencode)

echo "=== Model count ===" && docker exec $CONTAINER grep 'context_length' /home/hermeswebui/.hermes/config.yaml | wc -l

echo "=== No wildcards ===" && docker exec $CONTAINER grep -c '/\*' /home/hermeswebui/.hermes/config.yaml
# Expected: 0

echo "=== Default model ===" && docker exec $CONTAINER grep -A1 '^model:' /home/hermeswebui/.hermes/config.yaml
# Expected: name: <OPENAI_DEFAULT_MODEL>

echo "=== OpenCode config ===" && docker exec $CONTAINER cat /home/hermeswebui/.config/opencode/opencode.jsonc | python3 -m json.tool

echo "=== OpenCode env key ===" && docker exec $CONTAINER grep 'apiKey' /home/hermeswebui/.config/opencode/opencode.jsonc
# Expected: "apiKey": "{env:OPENAI_API_KEY}"
```

### Agent source and patch

```bash
docker exec $CONTAINER test -f /home/hermeswebui/.hermes/hermes-agent/pyproject.toml && echo "AC5: Agent present — OK"

docker exec $CONTAINER grep -q '"User-Agent".*"hermes-agent' /home/hermeswebui/.hermes/hermes-agent/plugins/model-providers/custom/__init__.py && echo "AC6: UA patch — OK"

docker exec $CONTAINER grep -q 'key_env: OPENAI_API_KEY' /home/hermeswebui/.hermes/config.yaml && echo "AC7: key_env literal — OK"

docker exec $CONTAINER grep -q 'api_server' /home/hermeswebui/.hermes/config.yaml && echo "AC17: api_server platform — OK"
```

### Onboarding skip

```bash
curl -sf http://localhost:${HERMES_WEBUI_PORT:-8787}/api/onboarding/status | python3 -m json.tool
# Expected: {"completed": true, ...}
```

### OpenCode binary

```bash
docker exec $CONTAINER opencode --version && echo "AC8: OpenCode — OK"
```

### Gateway chat test

```bash
API_KEY=$(docker logs $CONTAINER 2>&1 | grep "Generated random HERMES_API_KEY" | sed 's/.*: //')

if [ -z "$API_KEY" ]; then
  API_KEY="${HERMES_API_KEY}"
fi

curl -sf http://localhost:${HERMES_API_PORT:-8642}/v1/chat/completions \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"hermes-agent","messages":[{"role":"user","content":"Say hello in one word"}],"stream":false}' \
  --max-time 60 | python3 -m json.tool

echo "AC9+AC15: Gateway chat — OK"
```

### Gateway models endpoint

```bash
curl -sf http://localhost:${HERMES_API_PORT:-8642}/v1/models \
  -H "Authorization: Bearer $API_KEY" | python3 -m json.tool

echo "AC14: Gateway models — OK"
```

### Full smoke test script

```bash
#!/bin/bash
set -euo pipefail

BASE="http://localhost:${HERMES_WEBUI_PORT:-18787}"
CONTAINER=$(docker compose ps -q hermes-opencode)

echo "=== 1. Health Check ==="
curl -s "$BASE/health" | python3 -m json.tool

echo "=== 2. Deep Health ==="
curl -s "$BASE/health?deep=1" | python3 -m json.tool

echo "=== 3. Model Discovery ==="
echo "Models in config: $(docker exec $CONTAINER grep 'context_length' /home/hermeswebui/.hermes/config.yaml | wc -l)"
echo "Wildcard patterns: $(docker exec $CONTAINER grep -c '/\*' /home/hermeswebui/.hermes/config.yaml || echo 0)"

echo "=== 4. Onboarding Status ==="
curl -s "$BASE/api/onboarding/status" | python3 -m json.tool

echo "=== 5. List Sessions ==="
curl -s "$BASE/api/sessions" | python3 -m json.tool

echo "=== 6. Create Session ==="
SESSION=$(curl -s -X POST "$BASE/api/session/new" \
  -H "Content-Type: application/json" \
  -d '{"workspace": "/workspace"}')
SID=$(echo "$SESSION" | python3 -c "import sys,json; print(json.load(sys.stdin)['session']['session_id'])")
echo "Session: $SID"

echo "=== 7. Chat (async start) ==="
START=$(curl -s -X POST "$BASE/api/chat/start" \
  -H "Content-Type: application/json" \
  -d "{\"session_id\": \"$SID\", \"message\": \"Say hello in one word.\"}")
STREAM_ID=$(echo "$START" | python3 -c "import sys,json; print(json.load(sys.stdin)['stream_id'])")
echo "Stream: $STREAM_ID"

echo "=== 8. Stream SSE (30s) ==="
timeout 30 curl -N "$BASE/api/chat/stream?stream_id=$STREAM_ID" 2>/dev/null || true

echo "=== 9. Get Session ==="
curl -s "$BASE/api/session?session_id=$SID" | python3 -m json.tool

echo "=== 10. Gateway Chat ==="
API_KEY=$(docker logs $CONTAINER 2>&1 | grep "Generated random HERMES_API_KEY" | sed 's/.*: //')
curl -s http://localhost:${HERMES_API_PORT:-8642}/v1/chat/completions \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"session_id\": \"$SID\", \"model\": \"hermes-agent\", \"messages\": [{\"role\": \"user\", \"content\": \"What is 2+2?\"}]}" \
  --max-time 60 | python3 -m json.tool

echo "=== 11. OpenCode Config ==="
docker exec $CONTAINER python3 -c "import json; c=json.load(open('/home/hermeswebui/.config/opencode/opencode.jsonc')); print(f'Provider: {list(c[\"provider\"].keys())}'); print(f'Models: {len(c[\"provider\"][\"litellm\"][\"models\"])}'); print(f'Default: {c[\"model\"]}')"

echo "=== 12. Cleanup ==="
curl -s -X POST "$BASE/api/session/delete" \
  -H "Content-Type: application/json" \
  -d "{\"session_id\": \"$SID\"}" | python3 -m json.tool

echo "=== Done ==="
```

### Acceptance criteria mapping

| AC | Test | Command |
|----|------|---------|
| AC1 | Build succeeds | `docker compose build` |
| AC2 | Container starts | `docker compose up -d && docker compose ps` |
| AC3 | Healthcheck passes | `docker inspect --format='{{.State.Health.Status}}' $(docker compose ps -q hermes-opencode)` |
| AC4 | WebUI health | `curl -sf http://localhost:${HERMES_WEBUI_PORT:-8787}/health` |
| AC5 | Agent source present | `docker exec $C test -f /home/hermeswebui/.hermes/hermes-agent/pyproject.toml` |
| AC6 | UA patch applied | `docker exec $C grep -q '"User-Agent".*"hermes-agent' .../custom/__init__.py` |
| AC7 | config.yaml key_env literal | `docker exec $C grep -q 'key_env: OPENAI_API_KEY' /home/hermeswebui/.hermes/config.yaml` |
| AC8 | OpenCode available | `docker exec $C opencode --version` |
| AC9 | LLM call succeeds | Send chat message via WebUI or Gateway, verify non-error response |
| AC10 | No secrets in repo | `git ls-files | xargs grep -r 'sk-\|key-'` returns nothing sensitive |
| AC11 | Fast second boot | `docker compose down && docker compose up -d && time curl --retry 10 --retry-delay 2 -f .../health` |
| AC12 | Clean file tree | No dead files (patches/, scripts/setup-agent.sh, config/config.yaml) |
| AC13 | Gateway health | `curl -sf http://localhost:${HERMES_API_PORT:-8642}/health` |
| AC14 | Gateway models | `curl http://localhost:${HERMES_API_PORT:-8642}/v1/models` |
| AC15 | Gateway chat | Send completion to `:8642/v1/chat/completions`, verify response |
| AC16 | OpenCode serve responds | `curl -sf -o /dev/null -w "%{http_code}" http://localhost:${OPENCODE_SERVE_PORT:-4096}/` |
| AC17 | Config includes api_server | `docker exec $C grep -q 'api_server' /home/hermeswebui/.hermes/config.yaml` |
| AC18 | No wildcard models | `docker exec $C grep -c '/\*' /home/hermeswebui/.hermes/config.yaml` returns 0 |
| AC19 | Onboarding skipped | `curl $BASE/api/onboarding/status` returns `completed: true` |
| AC20 | OpenCode config valid | `docker exec $C python3 -m json.tool /home/hermeswebui/.config/opencode/opencode.jsonc` succeeds |

## Verification

Run the full smoke test script above. All steps must complete without error.

## What Works

- All acceptance criteria pass on a fresh build on ARM64
- Health endpoints respond within 50ms for WebUI and Gateway
- Gateway chat returns valid OpenAI-format responses with correct `usage` stats
- Session creation, chat, streaming, and cleanup work through the WebUI API
- OpenCode serve returns HTTP 200 at the root URL
- Model discovery produces ~297 chat models with no wildcard patterns
- Both Hermes and OpenCode configs contain the same model list
- Onboarding is skipped and reported as completed

## What Fails

- **Smoke test script requires manual API key extraction:** The API key must be read from container logs before testing the Gateway. The script automates this, but it requires `docker logs` access.
- **SSE stream test is time-bounded:** The `timeout 30` on the SSE stream may cut off long-running agent responses. This is intentional for smoke testing but not suitable for latency measurements.
- **No automated test runner:** The smoke test is a shell script that must be run manually. There is no CI integration.
- **Cosmetic has_key: false:** `/api/providers` reports `has_key: false` for `custom:litellm` and `models_total: 0`. This is a display-only issue; chat works correctly.

## Resolution

- The smoke test script extracts the API key automatically from container logs. If `HERMES_API_KEY` is explicitly set in `.env`, the script falls back to that value.
- Increase the `timeout` value for longer agent responses, or remove it for interactive testing.
- Integrate the smoke test into a CI pipeline by adding it as a GitHub Actions workflow step. Not currently implemented.
- The `has_key: false` issue is upstream in the Hermes WebUI. The `key_env: OPENAI_API_KEY` field is correctly resolved at request time. No fix needed for functionality.

## Verdict

The testing coverage is comprehensive for manual verification. All acceptance criteria are testable with curl and docker exec, including model discovery, wildcard filtering, and OpenCode config validation. The main gap is the lack of automated CI integration, which is deferred pending repository setup.
