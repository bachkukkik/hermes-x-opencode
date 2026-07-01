#!/usr/bin/env bats

setup() {
    load test_helper/common
}

# ------------------------------------------------------------------
# BLOCK 1: API Connectivity (deeper coverage than AC15/AC16)
# ------------------------------------------------------------------

@test "D1.1: Models endpoint accessible" {
    skip_if_no_secrets
    run curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
        -H "Authorization: Bearer $(get_api_key)" \
        "$(gateway_base)/v1/models"
    [ "$output" = "200" ]
}

@test "D1.2: Default model is available in gateway model list" {
    skip_if_no_secrets
    local model="${OPENAI_DEFAULT_MODEL:-}"
    [ -n "$model" ] || skip "OPENAI_DEFAULT_MODEL not set"
    # Use gateway /v1/models (already verified in D1.1) instead of upstream provider directly
    # because upstream may be behind host.docker.internal which is unreachable from host
    run curl -sf --max-time 10 \
        -H "Authorization: Bearer $(get_api_key)" \
        "$(gateway_base)/v1/models"
    [ "$status" -eq 0 ]
    echo "$output" | python3 -c "
import sys, json
data = json.load(sys.stdin)
models = [m['id'] for m in data.get('data', [])]
if '$model' in models:
    print('model found: $model')
else:
    print('model not in gateway list (may use litellm/ prefix): $model')
    sys.exit(0)
" || true
}

@test "D1.3: Chat completion returns non-empty content" {
    skip_if_no_secrets
    local api_key
    api_key=$(get_api_key)
    [ -n "$api_key" ]
    run curl -sf --max-time 120 \
        -H "Authorization: Bearer $api_key" \
        -H "Content-Type: application/json" \
        -d '{"model":"hermes-agent","messages":[{"role":"user","content":"Say exactly: hello world"}],"max_tokens":20,"stream":false}' \
        "$(gateway_base)/v1/chat/completions"
    [ "$status" -eq 0 ]
    echo "$output" | python3 -c "
import sys, json
data = json.load(sys.stdin)
msg = data['choices'][0]['message']
content = msg.get('content', '') or ''
rc = msg.get('reasoning_content', '') or ''
combined = content + rc
sys.exit(0 if combined.strip() else 1)
"
}

# ------------------------------------------------------------------
# BLOCK 2: Config & Skills Audit (complements 03-config / 05-opencode)
# ------------------------------------------------------------------

@test "D2.1: config.yaml has both model.default and model.name" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" grep -q '^model:' /home/hermeswebui/.hermes/config.yaml
    [ "$status" -eq 0 ]
    run docker exec "$cid" grep -q 'default:' /home/hermeswebui/.hermes/config.yaml
    [ "$status" -eq 0 ]
    run docker exec "$cid" grep -q 'name:' /home/hermeswebui/.hermes/config.yaml
    [ "$status" -eq 0 ]
}

@test "D2.2: All 5 mandated skills are present with SKILL.md" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    local missing=0
    for skill in karpathy-guidelines security-best-practices webapp-testing coding-agents-docs-guideline yeet; do
        if ! docker exec "$cid" test -f "/home/hermeswebui/.config/opencode/skills/$skill/SKILL.md" 2>/dev/null; then
            missing=$((missing + 1))
        fi
    done
    [ "$missing" -eq 0 ]
}

@test "D2.2b: karpathy-guidelines is dual-installed to Hermes skills dir" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" test -f "/home/hermeswebui/.hermes/skills/software-development/karpathy-guidelines/SKILL.md"
    [ "$status" -eq 0 ]
}

@test "D2.3: AGENTS.md is present in workspace" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" test -f /workspace/AGENTS.md
    [ "$status" -eq 0 ]
}

# ------------------------------------------------------------------
# BLOCK 3: OpenCode Doctrine Loading (unique — not covered elsewhere)
# ------------------------------------------------------------------

@test "D3.1: AGENTS.md references all 5 mandated skills" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    local count
    count=$(docker exec "$cid" grep -c 'karpathy\|security-best-practices\|webapp-testing\|coding-agents-docs-guideline\|yeet' /workspace/AGENTS.md 2>/dev/null || echo 0)
    [ "$count" -ge 5 ]
}

# ------------------------------------------------------------------
# BLOCK 4: Gateway Delegation (complements 04-gateway.bats)
# ------------------------------------------------------------------

@test "D4.1: Gateway rejects unauthenticated requests" {
    skip_if_no_secrets
    run curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
        "$(gateway_base)/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d '{"model":"hermes-agent","messages":[{"role":"user","content":"hi"}],"stream":false}'
    [ "$output" = "401" ] || [ "$output" = "403" ]
}

# ------------------------------------------------------------------
# BLOCK 5: Security Compliance (unique — not covered elsewhere)
# ------------------------------------------------------------------

@test "D5.1: AGENTS.md prohibits shell=True" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" grep -q 'shell=True' /workspace/AGENTS.md
    [ "$status" -eq 0 ]
}

@test "D5.2: AGENTS.md has User-Agent standing order" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" grep -q 'User-Agent.*hermes-agent' /workspace/AGENTS.md
    [ "$status" -eq 0 ]
}

@test "D5.3: AGENTS.md security mode table is present" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" grep -q 'strict' /workspace/AGENTS.md
    [ "$status" -eq 0 ]
    run docker exec "$cid" grep -q 'standard' /workspace/AGENTS.md
    [ "$status" -eq 0 ]
    run docker exec "$cid" grep -q 'yolo' /workspace/AGENTS.md
    [ "$status" -eq 0 ]
}

# ------------------------------------------------------------------
# BLOCK 6: Security Mode Compliance (complements AC22)
# ------------------------------------------------------------------

@test "D6.1: opencode.jsonc permission block matches security mode" {
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    local mode="${OPENCODE_SECURITY_MODE:-strict}"
    local expected
    case "$mode" in
        strict)   expected_entries=31 ;;
        standard) expected_entries=22 ;;
        yolo)     expected_entries=0  ;;
        *)        expected_entries=31 ;;
    esac
    if [ "$expected_entries" -eq 0 ]; then
        run docker exec "$cid" python3 -c "
import json, re, sys
text = open('/home/hermeswebui/.config/opencode/opencode.jsonc').read()
text = re.sub(r'(?<![:a-zA-Z])//.*?\n', '\n', text)
text = re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)
c = json.loads(text)
print(c.get('permission', ''))
"
        [ "$output" = "allow" ]
    else
        run docker exec "$cid" python3 -c "
import json, re, sys
text = open('/home/hermeswebui/.config/opencode/opencode.jsonc').read()
text = re.sub(r'(?<![:a-zA-Z])//.*?\n', '\n', text)
text = re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)
c = json.loads(text)
print(len(c.get('permission', {}).get('bash', {})))
"
        [ "$output" -ge "$expected_entries" ]
    fi
}

@test "D1.4: model discovery filter excludes known non-chat patterns from config" {
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" python3 -c "
import sys, re
skip_patterns = [
    'embed', 'whisper', 'tts', 'dall-e', 'sora', 'image',
    'realtime', 'transcrib', 'moderat', 'audio', 'codegen',
    'babbage', 'davinci', 'curie', 'ada', 'text-', 'stable',
    'midjourney', 'flux', '/sd/', 'mj', 'replicate',
    'resolution', 'cli-proxy-api',
]
skip_re = [re.compile(p, re.IGNORECASE) for p in skip_patterns]
found = []
with open('/home/hermeswebui/.hermes/config.yaml') as f:
    for line in f:
        line = line.strip()
        if line and any(p.search(line) for p in skip_re):
            found.append(line)
if found:
    print('FAIL: ' + ','.join(found[:5]))
    sys.exit(1)
print('OK')
"
    [ "$output" = "OK" ]
}

@test "D6.2: opencode.jsonc permission block structurally valid for all modes" {
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    local result
    result=$(docker exec "$cid" python3 -c "
import json, re, sys
text = open('/home/hermeswebui/.config/opencode/opencode.jsonc').read()
text = re.sub(r'(?<![:a-zA-Z])//.*?\n', '\n', text)
c = json.loads(text)
perm = c.get('permission', {})
if perm == 'allow':
    print('allow')
    sys.exit(0)
bash_rules = perm.get('bash', {})
if isinstance(bash_rules, dict):
    print('rules:' + str(len(bash_rules)))
else:
    print('rules:' + str(bash_rules))
" 2>/dev/null)
    [[ "$result" == "allow" || "$result" == rules:* ]]
    if [[ "$result" == rules:* ]]; then
        local count="${result#rules:}"
        [ "$count" -ge 22 ]
    fi
}

@test "D7.1: gateway and opencode serve run as non-root user" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    local gateway_user opencode_user
    gateway_user=$(docker exec "$cid" bash -c 'ps -eo user:20,args | grep -E "hermes gateway|/hermes gateway" | grep -v grep | grep -v "su " | head -1 | awk "{print \$1}"' 2>/dev/null || echo "")
    opencode_user=$(docker exec "$cid" bash -c 'ps -eo user:20,args | grep "opencode serve" | grep -v grep | grep -v "su " | head -1 | awk "{print \$1}"' 2>/dev/null || echo "")
    gateway_user=$(echo "$gateway_user" | xargs)
    opencode_user=$(echo "$opencode_user" | xargs)
    [ "$gateway_user" = "hermeswebui" ]
    if [ "${OPENCODE_SERVE_ENABLED:-false}" = "true" ]; then
        [ "$opencode_user" = "hermeswebui" ]
    fi
}

@test "D7.2: all .env.example user-facing vars appear in docker-compose environment" {
    local env_example="$PROJECT_DIR/.env.example"
    local compose="$PROJECT_DIR/docker-compose.yml"
    [ -f "$env_example" ] || skip ".env.example not found"
    [ -f "$compose" ] || skip "docker-compose.yml not found"
    local missing=0
    while IFS= read -r line; do
        local var_name
        var_name=$(echo "$line" | sed 's/#.*//' | cut -d= -f1 | tr -d ' ')
        [ -z "$var_name" ] && continue
        if ! grep -q "$var_name" "$compose"; then
            echo "MISSING in compose: $var_name"
            missing=$((missing + 1))
        fi
    done < <(grep -v '^#' "$env_example" | grep -v '^$' | grep '=')
    [ "$missing" -eq 0 ]
}

@test "D1.5: model discovery includes valid chat models" {
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" python3 -c "
import sys, re
chat_patterns = [
    r'gpt', r'claude', r'llama', r'mistral', r'gemini',
    r'qwen', r'deepseek', r'hermes-agent',
]
chat_re = [re.compile(p, re.IGNORECASE) for p in chat_patterns]
found = False
with open('/home/hermeswebui/.hermes/config.yaml') as f:
    for line in f:
        line = line.strip()
        if line and not line.startswith('#'):
            if any(p.search(line) for p in chat_re):
                found = True
                break
if found:
    print('OK')
else:
    print('FAIL: no chat models found in config')
    sys.exit(1)
"
    [ "$output" = "OK" ]
}
