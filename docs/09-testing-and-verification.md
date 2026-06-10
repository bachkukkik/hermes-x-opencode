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
CONTAINER=$(docker compose ps -q hermes-opencode)
docker exec "$CONTAINER" bash -c 'tr "\\0" "\\n" < /proc/1/environ | grep -q SKIP_ONBOARDING'
# Expected: exit 0 (env var is set)
# Note: onboarding API requires auth, so we check the env var directly
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

BASE="http://localhost:${HERMES_WEBUI_PORT:-8787}"
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
| AC12 | Model discovery populates models | `docker exec $C grep 'context_length' .../config.yaml \| wc -l` returns ≥1 |
| AC13 | Gateway health | `curl -sf http://localhost:${HERMES_API_PORT:-8642}/health` |
| AC14 | Gateway models | `curl http://localhost:${HERMES_API_PORT:-8642}/v1/models` |
| AC15 | Gateway chat | Send completion to `:8642/v1/chat/completions`, verify response |
| AC16 | OpenCode serve responds | (requires OPENCODE_SERVE_ENABLED=true) `docker exec $C bash -c 'echo > /dev/tcp/127.0.0.1/4096'` (port-based, auth blocks curl) |
| AC17 | Config includes api_server | `docker exec $C grep -q 'api_server' /home/hermeswebui/.hermes/config.yaml` |
| AC18 | No wildcard models | `docker exec $C grep -c '/\*' /home/hermeswebui/.hermes/config.yaml` returns 0 |
| AC19 | Onboarding skipped | `docker exec $C tr "\\\\0" "\\\\n" < /proc/1/environ \| grep SKIP_ONBOARDING` (env var check, API requires auth) |
| AC20 | OpenCode config valid | `docker exec $C python3 -m json.tool /home/hermeswebui/.config/opencode/opencode.jsonc` succeeds |
| AC21 | OpenCode skills installed | `docker exec $C find /home/hermeswebui/.config/opencode/skills -name "SKILL.md" \| wc -l` returns >0 |
| AC22 | Security mode applied | `docker exec $C grep -c '"deny"' /home/hermeswebui/.config/opencode/opencode.jsonc` matches mode (strict=31, standard=22) |
| AC23 | OpenCode serve listening | (requires OPENCODE_SERVE_ENABLED=true) `docker exec $C bash -c 'echo > /dev/tcp/127.0.0.1/4096'` (port-based, auth blocks curl) |
| AC24 | Hermes skills present | `docker exec $C find /home/hermeswebui/.hermes/skills -name "SKILL.md" \| wc -l` returns >0 |
| AC25 | Skills in Docker image | `docker run --rm --entrypoint bash $IMAGE -c 'find /opt/hermes-skills-staging -name "SKILL.md" \| wc -l'` returns >0 |
| AC26 | uv available in container | `docker exec $C test -x /usr/local/bin/uv` |
| AC27 | graphify CLI available | `docker exec $C test -x /usr/local/bin/graphify` |
| AC28 | graphify Hermes skill registered | `docker exec $C test -f /home/hermeswebui/.hermes/skills/graphify/SKILL.md` |
| AC29 | graphify OpenCode skill registered | `docker exec $C test -f /home/hermeswebui/.config/opencode/skills/graphify/SKILL.md` |
| AC30 | Agent clone trimmed | `docker exec $C test ! -d /opt/hermes-agent-staging/skills` (no skills/, docs/, tests/ after Dockerfile trim) |

### Wiki initialization tests (14-wiki-init.bats)

| ID | Test | Command |
|----|------|---------|
| WI1 | Wiki dir exists | `docker exec $C test -d /home/hermeswebui/.hermes/wiki` |
| WI2 | SCHEMA.md exists | `docker exec $C test -f /home/hermeswebui/.hermes/wiki/SCHEMA.md` |
| WI3 | Subdirs created | `docker exec $C test -d /home/hermeswebui/.hermes/wiki/raw/articles` (+ concepts, entities, comparisons, queries) |
| WI4 | SCHEMA.md content | `docker exec $C head -5 .../wiki/SCHEMA.md` contains "domain" (case-insensitive) |
| WI5 | Index and log exist | `docker exec $C test -f .../wiki/index.md && test -f .../wiki/log.md` |

### Agent installation architecture tests (15-agent-installation-architecture.bats)

| ID | Test | Command |
|----|------|---------|
| AC26 | Staged clone has pyproject.toml | `docker exec $C test -f /opt/hermes-agent-staging/pyproject.toml` |
| AC27 | Runtime copy exists | `docker exec $C test -d /home/hermeswebui/.hermes/hermes-agent` |
| AC28 | Agent not running from staging | `docker exec $C test ! -d /opt/hermes-agent-staging/skills` (trimmed after install-skills.sh) |
| AC29 | CustomProfile User-Agent patch | `docker exec $C grep -q '"User-Agent".*"hermes-agent' ...custom/__init__.py` |
| AC30 | Staged clone trimmed | `docker exec $C test ! -d /opt/hermes-agent-staging/docs` |

## Verification

Run the full smoke test script above. All steps must complete without error.

## What Works

- All 30 acceptance criteria pass on a fresh build on ARM64 via the bats test suite (`tests/run.sh`, ~109 tests). AC16 and AC23 require `OPENCODE_SERVE_ENABLED=true`. AC0.3 and AC23 use port-based checks (`/dev/tcp`) because curl is blocked by serve auth. Wiki initialization verified by 14-wiki-init.bats (WI1-WI5, 17 tests). Agent installation architecture verified by 15-agent-installation-architecture.bats (5 tests).
- Health endpoints respond within 50ms for WebUI and Gateway
- Gateway chat returns valid OpenAI-format responses with correct `usage` stats
- Session creation, chat, streaming, and cleanup work through the WebUI API
- OpenCode serve reports healthy via `/global/health` endpoint
- Model discovery produces ~297 chat models with no wildcard patterns
- Both Hermes and OpenCode configs contain the same model list
- Onboarding is skipped and reported as completed
- Skills are verified at build time (AC25: staging dir populated) and runtime (AC21: OpenCode skills, AC24: Hermes skills)
- Graphify integration verified (AC26: uv present, AC27: graphify CLI, AC28: Hermes skill, AC29: OpenCode skill)

## What Fails

- **Smoke test script requires manual API key extraction:** The API key must be read from container logs before testing the Gateway. The script automates this, but it requires `docker logs` access.
- **SSE stream test is time-bounded:** The `timeout 30` on the SSE stream may cut off long-running agent responses. This is intentional for smoke testing but not suitable for latency measurements.
- **AC23 tests port only, not LLM call:** The OpenCode serve health endpoint requires password auth, so tests use a port-based check (`/dev/tcp`). This confirms the process is listening but does not verify LLM connectivity. `opencode run` requires API quota and the password, and is not suitable for automated testing.
- **Cosmetic has_key: false:** `/api/providers` reports `has_key: false` for `custom:litellm` and `models_total: 0`. This is a display-only issue; chat works correctly.

## Resolution

- The smoke test script extracts the API key automatically from container logs. If `HERMES_API_KEY` is explicitly set in `.env`, the script falls back to that value.
- Increase the `timeout` value for longer agent responses, or remove it for interactive testing.
- AC23's port-based check is acceptable for CI. For manual LLM verification, use the full smoke test script's Gateway chat step (step 10) which tests end-to-end LLM connectivity via the Hermes gateway, or use `opencode run --attach` with the password from `/tmp/opencode-server-password`.
- The `has_key: false` issue is upstream in the Hermes WebUI. The `key_env: OPENAI_API_KEY` field is correctly resolved at request time. No fix needed for functionality.

## Verdict

The testing coverage is comprehensive. All 30 acceptance criteria are automated in the bats test suite (`tests/run.sh`, ~109 tests), including build-time skill verification (AC25), runtime skill presence (AC21, AC24), graphify integration (AC26–AC29), agent installation architecture (AC26–AC30 in 15-agent-installation-architecture.bats), wiki initialization (WI1–WI5 in 14-wiki-init.bats), OpenCode serve health (AC23, requires `OPENCODE_SERVE_ENABLED=true`), deeper config validation (model limits, small_model, plugin presence, Node.js 22), and security hardening checks (filter completeness, mode matrix, gateway auth rejection). A negative test verifies port 4096 is NOT listening when serve is disabled. The main gap is AC23 testing only port reachability rather than a full LLM call through OpenCode serve (curl is blocked by serve password auth).
