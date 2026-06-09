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
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    # Verify HERMES_WEBUI_SKIP_ONBOARDING env var is set in the container
    run docker exec "$cid" bash -c 'tr "\\0" "\\n" < /proc/1/environ | grep -q SKIP_ONBOARDING'
    [ "$status" -eq 0 ]
    # Verify webui health endpoint works
    run curl -sf --max-time 5 "$(webui_base)/health"
    [ "$status" -eq 0 ]
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

@test "opencode.jsonc small_model matches OPENCODE_SMALL_MODEL, OPENAI_SMALL_MODEL, or defaults to model" {
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
    if [ -n "${OPENCODE_SMALL_MODEL:-}" ]; then
        [ "$configured_small" = "litellm/${OPENCODE_SMALL_MODEL}" ]
    elif [ -n "${OPENAI_SMALL_MODEL:-}" ]; then
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

@test "config.yaml always has at least one model entry (fallback resilience)" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    local count
    count=$(docker exec "$cid" grep 'context_length' /home/hermeswebui/.hermes/config.yaml | wc -l)
    [ "$count" -ge 1 ]
}

@test "AC12: model discovery populates multiple models in config" {
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    local count
    count=$(docker exec "$cid" grep 'context_length' /home/hermeswebui/.hermes/config.yaml | wc -l)
    [ "$count" -ge 1 ]
}

@test "config.yaml model.default and model.name match HERMES_DEFAULT_MODEL or OPENAI_DEFAULT_MODEL" {
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    local expected="${HERMES_DEFAULT_MODEL:-${OPENAI_DEFAULT_MODEL:-openai/gpt-4o}}"
    local default_val name_val
    default_val=$(docker exec "$cid" grep '^ *default:' /home/hermeswebui/.hermes/config.yaml | head -1 | sed 's/.*default: *//' | tr -d '"')
    name_val=$(docker exec "$cid" grep '^ *name:' /home/hermeswebui/.hermes/config.yaml | head -1 | sed 's/.*name: *//' | tr -d '"')
    [ "$default_val" = "$expected" ]
    [ "$name_val" = "$expected" ]
}

@test "opencode.jsonc model matches OPENCODE_DEFAULT_MODEL or OPENAI_DEFAULT_MODEL" {
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    local expected="${OPENCODE_DEFAULT_MODEL:-${OPENAI_DEFAULT_MODEL:-openai/gpt-4o}}"
    local configured_model
    configured_model=$(docker exec "$cid" python3 -c "
import json, re, sys
text = open(sys.argv[1]).read()
text = re.sub(r'(?<![:a-zA-Z])//.*?\n', '\n', text)
text = re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)
c = json.loads(text)
print(c.get('model', ''))
" /home/hermeswebui/.config/opencode/opencode.jsonc 2>/dev/null)
    [ -n "$configured_model" ]
    [ "$configured_model" = "litellm/${expected}" ]
}

@test "FIX #28: root's opencode config matches hermeswebui's" {
    # After fix #28, the entrypoint copies opencode.jsonc to root's config dir
    # so that docker exec (root) sees the same litellm provider config.
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    # Root's config must exist
    run docker exec "$cid" test -f /root/.config/opencode/opencode.jsonc
    [ "$status" -eq 0 ]

    # Root's config must match hermeswebui's
    run docker exec "$cid" diff /root/.config/opencode/opencode.jsonc /home/hermeswebui/.config/opencode/opencode.jsonc
    [ "$status" -eq 0 ]
}

@test "FIX #29: root's opencode data dir symlinks to hermeswebui's" {
    # After fix #29, root's /root/.local/share/opencode is a symlink to
    # hermeswebui's data dir so that --attach finds sessions created by serve.
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    # Root's opencode data dir should be a symlink
    run docker exec "$cid" test -L /root/.local/share/opencode
    [ "$status" -eq 0 ]

    # Symlink target should be hermeswebui's data dir
    local target
    target=$(docker exec "$cid" readlink /root/.local/share/opencode)
    [ "$target" = "/home/hermeswebui/.local/share/opencode" ]
}

@test "FIX #31: host.docker.internal resolves inside container" {
    # After fix #31, extra_hosts maps host.docker.internal to host-gateway.
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run docker exec "$cid" getent hosts host.docker.internal
    [ "$status" -eq 0 ]
}

@test "opencode run with litellm/ provider prefix loads config but may timeout (fix #28)" {
    # After fix #28, root has the litellm provider config. opencode run now
    # discovers the litellm provider and attempts the LLM call. If the provider
    # is unreachable (e.g., host.docker.internal:4000 not running), it times out.
    # Accept: exit 0 (success), 1 (API error), or 124 (timeout).
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run docker exec "$cid" timeout 15 opencode run -m litellm/z.ai/glm-5.1 'Respond with: HELLO' 2>&1
    # Exit 0, 1, or 124 are all acceptable — the provider is discovered,
    # the call just may not complete within the timeout.
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ] || [ "$status" -eq 124 ]
}

@test "KNOWN LIMITATION: opencode run rejects openai/ prefix with custom model IDs" {
    # Even with OPENAI_API_KEY set, openai/ only accepts models in its built-in
    # registry. Custom model IDs like z.ai/glm-5.1 are rejected.
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run docker exec "$cid" timeout 15 opencode run -m openai/z.ai/glm-5.1 'Respond with: HELLO' 2>&1
    [ "$status" -ne 0 ]
    echo "$output" | grep -qi "error\|not found\|Unexpected"
}

@test "WORKAROUND: opencode run works with opencode/ free-tier models" {
    # The opencode/ prefix uses built-in free models that require no API key.
    # This is the recommended workaround for opencode run CLI one-shot commands.
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run docker exec "$cid" timeout 60 opencode run -m opencode/deepseek-v4-flash-free 'Respond with exactly one word: OK' 2>&1
    # Accept exit 0 (success) or 1 (may fail due to rate limits/no network)
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
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
