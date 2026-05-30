#!/usr/bin/env bats

setup() {
    load test_helper/common
}

@test "AC5: agent source present in bind mount" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" test -f /home/hermeswebui/.hermes/hermes-agent/pyproject.toml
    [ "$status" -eq 0 ]
}

@test "AC6: CustomProfile User-Agent patch applied" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" grep -q '"User-Agent".*"hermes-agent' /home/hermeswebui/.hermes/hermes-agent/plugins/model-providers/custom/__init__.py
    [ "$status" -eq 0 ]
}

@test "AC7: config.yaml has literal key_env string" {
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" grep -q 'key_env: OPENAI_API_KEY' /home/hermeswebui/.hermes/config.yaml
    [ "$status" -eq 0 ]
}

@test "AC17: config.yaml includes api_server platform" {
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" grep -q 'api_server' /home/hermeswebui/.hermes/config.yaml
    [ "$status" -eq 0 ]
}

@test "AC18: no wildcard models in config.yaml" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" grep '/\*' /home/hermeswebui/.hermes/config.yaml
    [ "$status" -ne 0 ]
}

@test "AC19: onboarding is skipped" {
    local response=""
    local retries=0
    while [ "$retries" -lt 60 ]; do
        response=$(curl -sf --max-time 5 "$(webui_base)/api/onboarding/status" 2>/dev/null) && break
        sleep 2
        retries=$((retries + 1))
    done
    [ -n "$response" ]
    echo "$response" | grep -q '"completed": *true'
}

@test "AC20: opencode.jsonc is valid JSON" {
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    run docker exec "$cid" python3 -c "
import json, re, sys
text = open(sys.argv[1]).read()
text = re.sub(r'(?<![:a-zA-Z])//.*?\n', '\n', text)
text = re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)
json.loads(text)
" /home/hermeswebui/.config/opencode/opencode.jsonc
    [ "$status" -eq 0 ]
}

@test "opencode.jsonc contains small_model key" {
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    local small_model
    small_model=$(docker exec "$cid" python3 -c "
import json, re, sys
text = open(sys.argv[1]).read()
text = re.sub(r'(?<![:a-zA-Z])//.*?\n', '\n', text)
text = re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)
c = json.loads(text)
sm = c.get('small_model', '')
print(sm)
" /home/hermeswebui/.config/opencode/opencode.jsonc 2>/dev/null)
    [ -n "$small_model" ]
    [[ "$small_model" == litellm/* ]]
}

@test "opencode.jsonc small_model matches OPENAI_SMALL_MODEL or defaults to model" {
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    local small_model default_model configured_small
    small_model=$(docker exec "$cid" python3 -c "
import json, re, sys
text = open(sys.argv[1]).read()
text = re.sub(r'(?<![:a-zA-Z])//.*?\n', '\n', text)
text = re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)
c = json.loads(text)
print(c.get('small_model', ''))
print(c.get('model', ''))
" /home/hermeswebui/.config/opencode/opencode.jsonc 2>/dev/null)
    configured_small=$(echo "$small_model" | head -1)
    default_model=$(echo "$small_model" | tail -1)
    [ -n "$configured_small" ]
    if [ -n "${OPENAI_SMALL_MODEL:-}" ]; then
        [ "$configured_small" = "litellm/${OPENAI_SMALL_MODEL}" ]
    else
        [ "$configured_small" = "$default_model" ]
    fi
}

@test "opencode.jsonc all model entries have limit objects" {
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    local result
    result=$(docker exec "$cid" python3 -c "
import json, re, sys
text = open(sys.argv[1]).read()
text = re.sub(r'(?<![:a-zA-Z])//.*?\n', '\n', text)
text = re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)
c = json.loads(text)
models = c.get('provider', {}).get('litellm', {}).get('models', {})
empty = []
missing_limit = []
bad_type = []
for mid, val in models.items():
    if val == {}:
        empty.append(mid)
        continue
    if 'limit' not in val:
        missing_limit.append(mid)
        continue
    lim = val['limit']
    if not isinstance(lim.get('context'), int) or not isinstance(lim.get('output'), int):
        bad_type.append(mid)
errors = empty + missing_limit + bad_type
if errors:
    print('FAIL: ' + ','.join(errors[:5]))
    sys.exit(1)
print('OK: {} models'.format(len(models)))
" /home/hermeswebui/.config/opencode/opencode.jsonc 2>/dev/null)
    [[ "$result" == OK:* ]]
}

@test "opencode.jsonc model limits are within sane ranges" {
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    local result
    result=$(docker exec "$cid" python3 -c "
import json, re, sys
text = open(sys.argv[1]).read()
text = re.sub(r'(?<![:a-zA-Z])//.*?\n', '\n', text)
text = re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)
c = json.loads(text)
models = c.get('provider', {}).get('litellm', {}).get('models', {})
bad = []
for mid, val in models.items():
    lim = val.get('limit', {})
    ctx = lim.get('context', 0)
    out = lim.get('output', 0)
    if ctx < 1000 or ctx > 2000000:
        bad.append('{}:context={}'.format(mid, ctx))
    if out < 1000 or out > 200000:
        bad.append('{}:output={}'.format(mid, out))
if bad:
    print('FAIL: ' + ','.join(bad[:5]))
    sys.exit(1)
print('OK')
" /home/hermeswebui/.config/opencode/opencode.jsonc 2>/dev/null)
    [ "$result" = "OK" ]
}

@test "opencode.jsonc llama_cpp models have 200k context" {
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    local result
    result=$(docker exec "$cid" python3 -c "
import json, re, sys
text = open(sys.argv[1]).read()
text = re.sub(r'(?<![:a-zA-Z])//.*?\n', '\n', text)
text = re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)
c = json.loads(text)
models = c.get('provider', {}).get('litellm', {}).get('models', {})
llama_models = {k: v for k, v in models.items() if 'llama_cpp/' in k}
if not llama_models:
    print('SKIP: no llama_cpp models')
    sys.exit(0)
bad = []
for mid, val in llama_models.items():
    ctx = val.get('limit', {}).get('context', 0)
    out = val.get('limit', {}).get('output', 0)
    if ctx < 200000:
        bad.append('{}:context={} (expected >=200000)'.format(mid, ctx))
    if out < 32768:
        bad.append('{}:output={} (expected >=32768)'.format(mid, out))
if bad:
    print('FAIL: ' + ','.join(bad))
    sys.exit(1)
print('OK: {} llama_cpp models checked'.format(len(llama_models)))
" /home/hermeswebui/.config/opencode/opencode.jsonc 2>/dev/null)
    [[ "$result" == OK:* ]] || [ "$result" = "SKIP: no llama_cpp models" ]
}
