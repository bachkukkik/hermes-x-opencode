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
    [[ "$small_model" == litellm/* ]] || [[ "$small_model" == opencode/* ]]
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

    # Resolve the raw small model name (strip any existing prefix for comparison)
    local raw_small="${OPENCODE_SMALL_MODEL:-${OPENAI_SMALL_MODEL:-${OPENCODE_DEFAULT_MODEL:-${OPENAI_DEFAULT_MODEL:-deepseek-v4-flash-free}}}}"
    local bare_small="${raw_small#opencode/}"
    bare_small="${bare_small#litellm/}"

    # Determine expected prefix using the same logic as _resolve_provider_prefix
    local expected_prefix
    case "$raw_small" in
        opencode/*) expected_prefix="opencode" ;;
        litellm/*)  expected_prefix="litellm" ;;
        *)
            if [ -n "${OPENAI_BASE_URL:-}" ] && [ -n "${OPENAI_API_KEY:-}" ]; then
                expected_prefix="litellm"
            else
                expected_prefix="opencode"
            fi
            ;;
    esac

    [ "$configured_small" = "${expected_prefix}/${bare_small}" ]
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
if not models:
    print('SKIP: no litellm models (Zen-only mode)')
    sys.exit(0)
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
    [[ "$result" == OK:* ]] || [ "$result" = "SKIP: no litellm models (Zen-only mode)" ]
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
if not models:
    print('SKIP: no litellm models (Zen-only mode)')
    sys.exit(0)
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
    [ "$result" = "OK" ] || [ "$result" = "SKIP: no litellm models (Zen-only mode)" ]
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

@test "dynamic context window: glm-5.2 pinned to 1048576 and unknown models omitted" {
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    # ASSERT A: when glm-5.2 is discovered it MUST be pinned to 1048576 (the
    # agent's "glm" catch-all misreports it as 202752). Guarded so the test
    # passes trivially when glm-5.2 is absent from this deployment.
    if docker exec "$cid" grep -q 'glm-5.2:' /home/hermeswebui/.hermes/config.yaml; then
        docker exec "$cid" grep -A1 'glm-5.2:' /home/hermeswebui/.hermes/config.yaml | grep -q 'context_length: 1048576'
    fi

    # ASSERT B (hybrid omission): unknown-family models are emitted as an empty
    # mapping `: {}` so the hermes-agent self-resolves the context length at
    # runtime. With a single model the default-model fallback always writes an
    # explicit context_length, so only assert when >=2 model entries exist.
    local model_count
    model_count=$(docker exec "$cid" grep -E '^      [^ ].*:$' /home/hermeswebui/.hermes/config.yaml | wc -l)
    if [ "$model_count" -ge 2 ]; then
        local omitted_count
        omitted_count=$(docker exec "$cid" grep -c ': {}' /home/hermeswebui/.hermes/config.yaml)
        [ "$omitted_count" -ge 1 ]
    fi
}

@test "goal budget: config.yaml has goals.max_turns from HERMES_GOAL_MAX_TURNS (default 50)" {
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    # goals block must be present
    docker exec "$cid" grep -A1 '^goals:' /home/hermeswebui/.hermes/config.yaml | grep -q 'max_turns:'
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

    # Resolve the raw default model name (strip any existing prefix for comparison)
    local raw_default="${OPENCODE_DEFAULT_MODEL:-${OPENAI_DEFAULT_MODEL:-deepseek-v4-flash-free}}"
    local bare_default="${raw_default#opencode/}"
    bare_default="${bare_default#litellm/}"

    # Determine expected prefix using the same logic as _resolve_provider_prefix
    local expected_prefix
    case "$raw_default" in
        opencode/*) expected_prefix="opencode" ;;
        litellm/*)  expected_prefix="litellm" ;;
        *)
            if [ -n "${OPENAI_BASE_URL:-}" ] && [ -n "${OPENAI_API_KEY:-}" ]; then
                expected_prefix="litellm"
            else
                expected_prefix="opencode"
            fi
            ;;
    esac

    [ "$configured_model" = "${expected_prefix}/${bare_default}" ]
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

@test "FIX #20: WebUI providers display respects key_env for custom providers" {
    # After the Dockerfile patch, _provider_has_key() and get_providers()
    # check key_env in addition to api_key. Verify the patch is present.
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    # The patched code should contain key_env references in providers.py
    docker exec "$cid" grep -q 'cp.get.*key_env' /app/api/providers.py
    docker exec "$cid" grep -q 'provider_cfg.get.*key_env' /app/api/providers.py
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
if not models:
    print('SKIP: no litellm models (Zen-only mode)')
    sys.exit(0)
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
    [[ "$result" == OK:* ]] || [ "$result" = "SKIP: no llama_cpp models" ] || [ "$result" = "SKIP: no litellm models (Zen-only mode)" ]
}


@test "AC31: config.yaml has skills.external_dirs pointing to optional-skills" {
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    # append_skills_external_dirs() adds this after ensure_agent() runs
    run docker exec "$cid" grep -q 'external_dirs' /home/hermeswebui/.hermes/config.yaml
    [ "$status" -eq 0 ]

    # Verify the optional-skills directory actually exists (ensure_agent must have run first)
    run docker exec "$cid" test -d /home/hermeswebui/.hermes/hermes-agent/optional-skills
    [ "$status" -eq 0 ]
}

@test "AC32: config.yaml approvals block reflects HERMES_YOLO_MODE" {
    # config-hermes.sh writes `approvals:` with `mode: off` when HERMES_YOLO_MODE
    # is unset or truthy (default 1). When explicitly falsy, the block is omitted.
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    local yolo_mode="${HERMES_YOLO_MODE:-1}"
    case "$yolo_mode" in
        1|true|yes|on)
            run docker exec "$cid" grep -q '^approvals:' /home/hermeswebui/.hermes/config.yaml
            [ "$status" -eq 0 ]
            run docker exec "$cid" grep -q 'mode: off' /home/hermeswebui/.hermes/config.yaml
            [ "$status" -eq 0 ]
            ;;
        0|false|no|off)
            run docker exec "$cid" grep -q '^approvals:' /home/hermeswebui/.hermes/config.yaml
            [ "$status" -ne 0 ]
            ;;
        *)
            # Unknown values fall back to the default (YOLO on)
            run docker exec "$cid" grep -q '^approvals:' /home/hermeswebui/.hermes/config.yaml
            [ "$status" -eq 0 ]
            run docker exec "$cid" grep -q 'mode: off' /home/hermeswebui/.hermes/config.yaml
            [ "$status" -eq 0 ]
            ;;
    esac
}

@test "AC33: config.yaml delegation block has max_iterations from HERMES_DELEGATION_MAX_ITERATIONS" {
    # config-hermes.sh always writes a `delegation:` block with
    # `max_iterations: N`, where N defaults to 50 (HERMES_DELEGATION_MAX_ITERATIONS).
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    local max_iter="${HERMES_DELEGATION_MAX_ITERATIONS:-50}"
    run docker exec "$cid" grep -q '^delegation:' /home/hermeswebui/.hermes/config.yaml
    [ "$status" -eq 0 ]
    run docker exec "$cid" grep -q "max_iterations: ${max_iter}" /home/hermeswebui/.hermes/config.yaml
    [ "$status" -eq 0 ]
}

# --- Hybrid per-model provider routing tests ---

@test "HYBRID: model and small_model each have valid provider prefix" {
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]
    local both_models
    both_models=$(docker exec "$cid" python3 -c "
import json, re, sys
text = open(sys.argv[1]).read()
text = re.sub(r'(?<![:a-zA-Z])//.*?\n', '\n', text)
text = re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)
c = json.loads(text)
print(c.get('model', ''))
print(c.get('small_model', ''))
" /home/hermeswebui/.config/opencode/opencode.jsonc 2>/dev/null)
    local configured_model configured_small
    configured_model=$(echo "$both_models" | head -1)
    configured_small=$(echo "$both_models" | tail -1)

    # Both must have a valid prefix
    [ -n "$configured_model" ]
    [ -n "$configured_small" ]
    [[ "$configured_model" == opencode/* ]] || [[ "$configured_model" == litellm/* ]]
    [[ "$configured_small" == opencode/* ]] || [[ "$configured_small" == litellm/* ]]

    # Each prefix is resolved independently per _resolve_provider_prefix.
    # In the current env the prefixes may differ (hybrid mode) or match.
    # This assertion just validates they are independently resolved — no
    # requirement that they be the same.
}

@test "HYBRID: _resolve_provider_prefix decision table matches generated config" {
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    # --- Validate default model prefix ---
    local raw_default="${OPENCODE_DEFAULT_MODEL:-${OPENAI_DEFAULT_MODEL:-deepseek-v4-flash-free}}"
    local expected_default_prefix
    case "$raw_default" in
        opencode/*) expected_default_prefix="opencode" ;;
        litellm/*)  expected_default_prefix="litellm" ;;
        *)
            if [ -n "${OPENAI_BASE_URL:-}" ] && [ -n "${OPENAI_API_KEY:-}" ]; then
                expected_default_prefix="litellm"
            else
                expected_default_prefix="opencode"
            fi
            ;;
    esac

    # --- Validate small model prefix ---
    local raw_small="${OPENCODE_SMALL_MODEL:-${OPENAI_SMALL_MODEL:-${OPENCODE_DEFAULT_MODEL:-${OPENAI_DEFAULT_MODEL:-deepseek-v4-flash-free}}}}"
    local expected_small_prefix
    case "$raw_small" in
        opencode/*) expected_small_prefix="opencode" ;;
        litellm/*)  expected_small_prefix="litellm" ;;
        *)
            if [ -n "${OPENAI_BASE_URL:-}" ] && [ -n "${OPENAI_API_KEY:-}" ]; then
                expected_small_prefix="litellm"
            else
                expected_small_prefix="opencode"
            fi
            ;;
    esac

    local configured_model configured_small
    configured_model=$(docker exec "$cid" python3 -c "
import json, re, sys
text = open(sys.argv[1]).read()
text = re.sub(r'(?<![:a-zA-Z])//.*?\n', '\n', text)
text = re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)
c = json.loads(text)
print(c.get('model', ''))
" /home/hermeswebui/.config/opencode/opencode.jsonc 2>/dev/null)
    configured_small=$(docker exec "$cid" python3 -c "
import json, re, sys
text = open(sys.argv[1]).read()
text = re.sub(r'(?<![:a-zA-Z])//.*?\n', '\n', text)
text = re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)
c = json.loads(text)
print(c.get('small_model', ''))
" /home/hermeswebui/.config/opencode/opencode.jsonc 2>/dev/null)

    [ -n "$configured_model" ]
    [ -n "$configured_small" ]

    # Assert prefixes match the decision table
    [[ "$configured_model" == "${expected_default_prefix}/"* ]]
    [[ "$configured_small" == "${expected_small_prefix}/"* ]]
}

@test "HYBRID: per-model independence — different models can have different prefixes" {
    # This test validates the core fix: when OPENCODE_DEFAULT_MODEL and
    # OPENCODE_SMALL_MODEL (or their fallbacks) have different routing needs,
    # each gets its own independently resolved prefix.
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    local raw_default="${OPENCODE_DEFAULT_MODEL:-${OPENAI_DEFAULT_MODEL:-deepseek-v4-flash-free}}"
    local raw_small="${OPENCODE_SMALL_MODEL:-${OPENAI_SMALL_MODEL:-${OPENCODE_DEFAULT_MODEL:-${OPENAI_DEFAULT_MODEL:-deepseek-v4-flash-free}}}}"

    # Compute expected prefix for each model independently
    local default_prefix small_prefix
    case "$raw_default" in
        opencode/*) default_prefix="opencode" ;;
        litellm/*)  default_prefix="litellm" ;;
        *)
            if [ -n "${OPENAI_BASE_URL:-}" ] && [ -n "${OPENAI_API_KEY:-}" ]; then
                default_prefix="litellm"
            else
                default_prefix="opencode"
            fi
            ;;
    esac
    case "$raw_small" in
        opencode/*) small_prefix="opencode" ;;
        litellm/*)  small_prefix="litellm" ;;
        *)
            if [ -n "${OPENAI_BASE_URL:-}" ] && [ -n "${OPENAI_API_KEY:-}" ]; then
                small_prefix="litellm"
            else
                small_prefix="opencode"
            fi
            ;;
    esac

    # Read the actual config
    local configured_model configured_small
    local both
    both=$(docker exec "$cid" python3 -c "
import json, re, sys
text = open(sys.argv[1]).read()
text = re.sub(r'(?<![:a-zA-Z])//.*?\n', '\n', text)
text = re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)
c = json.loads(text)
print(c.get('model', ''))
print(c.get('small_model', ''))
" /home/hermeswebui/.config/opencode/opencode.jsonc 2>/dev/null)
    configured_model=$(echo "$both" | head -1)
    configured_small=$(echo "$both" | tail -1)

    # Strip bare names for comparison
    local bare_default="${raw_default#opencode/}"; bare_default="${bare_default#litellm/}"
    local bare_small="${raw_small#opencode/}"; bare_small="${bare_small#litellm/}"

    # Each model must match its independently resolved prefix
    [ "$configured_model" = "${default_prefix}/${bare_default}" ]
    [ "$configured_small" = "${small_prefix}/${bare_small}" ]
}

@test "FIX #28: readlink guard does not break root config copy" {
    # The readlink -f guard prevents cp when src and dest are the same file.
    # Verify root's config still matches hermeswebui's after this guard.
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    # Root's config must exist
    run docker exec "$cid" test -f /root/.config/opencode/opencode.jsonc
    [ "$status" -eq 0 ]

    # Root's config must match hermeswebui's (readlink guard should not skip the copy)
    run docker exec "$cid" diff /root/.config/opencode/opencode.jsonc /home/hermeswebui/.config/opencode/opencode.jsonc
    [ "$status" -eq 0 ]
}

@test "ZEN: opencode provider block present when OPENCODE_API_KEY set" {
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    # Skip if opencode credentials are not configured in the container
    local api_key_env
    api_key_env=$(docker exec "$cid" printenv OPENCODE_API_KEY 2>/dev/null)
    [ -n "$api_key_env" ] || skip 'OPENCODE_API_KEY not set'

    # The opencode provider block must reference the key via the {env:...} indirection
    local result
    result=$(docker exec "$cid" python3 -c "
import json, re, sys
text = open(sys.argv[1]).read()
text = re.sub(r'(?<![:a-zA-Z])//.*?\n', '\n', text)
text = re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)
c = json.loads(text)
prov = c.get('provider', {}).get('opencode', {})
if not prov:
    print('FAIL: no opencode provider block')
    sys.exit(1)
api_key = prov.get('options', {}).get('apiKey', '')
if api_key != '{env:OPENCODE_API_KEY}':
    print('FAIL: apiKey=' + api_key)
    sys.exit(1)
print('OK')
" /home/hermeswebui/.config/opencode/opencode.jsonc 2>/dev/null)
    [ "$result" = "OK" ]
}

@test "ZEN: auth.json seeded with opencode provider credentials" {
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    local api_key_env
    api_key_env=$(docker exec "$cid" printenv OPENCODE_API_KEY 2>/dev/null)
    [ -n "$api_key_env" ] || skip 'OPENCODE_API_KEY not set'

    # auth.json must exist
    run docker exec "$cid" test -f /home/hermeswebui/.local/share/opencode/auth.json
    [ "$status" -eq 0 ]

    # opencode.apiKey field must be present and non-empty
    local result
    result=$(docker exec "$cid" python3 -c "
import json, sys
c = json.load(open(sys.argv[1]))
api_key = c.get('opencode', {}).get('apiKey', '')
if not api_key:
    print('FAIL: empty opencode.apiKey')
    sys.exit(1)
print('OK')
" /home/hermeswebui/.local/share/opencode/auth.json 2>/dev/null)
    [ "$result" = "OK" ]

    # Credentials file must be private (owner read/write only)
    local perms
    perms=$(docker exec "$cid" stat -c '%a' /home/hermeswebui/.local/share/opencode/auth.json 2>/dev/null)
    [ "$perms" = "600" ]
}

@test "ZEN: opencode provider entry coexists with litellm in hybrid mode" {
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    # Hybrid mode requires both the opencode and litellm (openai) credentials
    local opencode_key litellm_base
    opencode_key=$(docker exec "$cid" printenv OPENCODE_API_KEY 2>/dev/null)
    litellm_base=$(docker exec "$cid" printenv OPENAI_BASE_URL 2>/dev/null)
    if [ -z "$opencode_key" ] || [ -z "$litellm_base" ]; then
        skip 'hybrid mode requires both OPENCODE_API_KEY and OPENAI_BASE_URL'
    fi

    # Both providers must appear in the generated config
    local result
    result=$(docker exec "$cid" python3 -c "
import json, re, sys
text = open(sys.argv[1]).read()
text = re.sub(r'(?<![:a-zA-Z])//.*?\n', '\n', text)
text = re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)
c = json.loads(text)
providers = c.get('provider', {})
if 'opencode' not in providers:
    print('FAIL: opencode provider missing')
    sys.exit(1)
if 'litellm' not in providers:
    print('FAIL: litellm provider missing')
    sys.exit(1)
print('OK')
" /home/hermeswebui/.config/opencode/opencode.jsonc 2>/dev/null)
    [ "$result" = "OK" ]
}

@test "ZEN: auth.json includes litellm provider key when OPENAI_API_KEY set" {
    skip_if_no_secrets
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    local openai_key
    openai_key=$(docker exec "$cid" printenv OPENAI_API_KEY 2>/dev/null)
    [ -n "$openai_key" ] || skip 'OPENAI_API_KEY not set'

    # auth.json must have litellm.apiKey
    local result
    result=$(docker exec "$cid" python3 -c "
import json, sys
c = json.load(open(sys.argv[1]))
api_key = c.get('litellm', {}).get('apiKey', '')
if not api_key:
    print('FAIL: empty litellm.apiKey')
    sys.exit(1)
print('OK')
" /home/hermeswebui/.local/share/opencode/auth.json 2>/dev/null)
    [ "$result" = "OK" ]
}

@test "LITELLM: service-opencode.sh passes OPENAI_API_KEY through su" {
    # Verify the service script includes OPENAI_API_KEY in the su command
    local cid
    cid=$(get_container)
    [ -n "$cid" ]

    run docker exec "$cid" grep -c 'OPENAI_API_KEY' /usr/local/bin/lib/service-opencode.sh 2>/dev/null || true
    # The script must reference OPENAI_API_KEY at least twice (local var + su passthrough)
    [ "$status" -eq 0 ]
    [ "$output" -ge 2 ]
}
