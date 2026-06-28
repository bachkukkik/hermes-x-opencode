# lib/config-hermes.sh - hermes config.yaml generation - sourced by entrypoint.sh

# Resolve a model's context length from a small pin table of well-known model
# families (substring match, longest/most-specific pattern first). Echoes the
# pinned value, or empty string when the model is unknown — the caller then
# omits the context_length line so the hermes-agent self-resolves it at runtime
# via its own DEFAULT_CONTEXT_LENGTHS table / models.dev / endpoint probe.
#
# Why pin at all when the agent self-resolves? (1) The DEFAULT model must always
# carry an explicit context_length (see generate_config) so config.yaml has >=1
# entry and the active model gets a sane window, and (2) a few families need a
# defensive correct value — notably glm-5.2, whose true 1M window the agent's
# "glm" catch-all misreports as 202752. Values mirror the agent's authoritative
# DEFAULT_CONTEXT_LENGTHS table (agent/model_metadata.py) so a pinned model gets
# the same value it would self-resolve to.
resolve_ctx_len() {
    local model="$1"
    local m
    m=$(printf '%s' "$model" | tr '[:upper:]' '[:lower:]')
    # Longest/most-specific patterns FIRST (first match wins).
    case "$m" in
        *glm-5.2*)           echo 1048576 ;;  # agent catch-all gives 202752 (wrong)
        *claude-opus-4*)     echo 1000000 ;;
        *claude-sonnet-4.6*) echo 1000000 ;;
        *gpt-5.4*)           echo 1050000 ;;
        *gpt-5*)             echo 400000  ;;
        *gpt-4o*)            echo 128000  ;;
        *gpt-4.1*)           echo 1047576 ;;
        *gpt-4*)             echo 128000  ;;
        *gemini*)            echo 1048576 ;;
        *deepseek-v4*)       echo 1000000 ;;
        *minimax-m3*)        echo 1000000 ;;
        *qwen3.6-27b*q4*)    echo 262144  ;;  # quantized GGUF: 262144 real ctx, not family 1M
        *qwen3.6*)           echo 1048576 ;;
        *)                   echo ""      ;;  # unknown -> omit, agent self-resolves
    esac
}

generate_config() {
    mkdir -p "$(dirname "$CONFIG")"

    local api_key="${HERMES_API_KEY:-}"
    if [ -z "$api_key" ]; then
        api_key="hermes-$(openssl rand -hex 16)"
        echo "== Generated random HERMES_API_KEY: $api_key"
    fi

    local yolo_mode="${HERMES_YOLO_MODE:-1}"
    local approvals_block=""
    case "$yolo_mode" in
        1|true|yes|on)
            approvals_block="
approvals:
  mode: off
"
            ;;
    esac

    local max_iter="${HERMES_DELEGATION_MAX_ITERATIONS:-50}"
    local delegation_block="
delegation:
  max_iterations: ${max_iter}
"
    local goal_max_turns="${HERMES_GOAL_MAX_TURNS:-50}"
    local goals_block="
goals:
  max_turns: ${goal_max_turns}
"

    if [ -z "${OPENAI_BASE_URL:-}" ]; then
        echo "!! No OPENAI_BASE_URL — writing minimal config (api_server + default model)."
        cat > "$CONFIG" << YAMLEOF
model:
  provider: litellm
  default: openai/gpt-4o
  name: openai/gpt-4o

custom_providers:
  - name: litellm
    base_url: ""
    models:
      openai/gpt-4o:
        context_length: 200000
    key_env: OPENAI_API_KEY

platforms:
  api_server:
    enabled: true
    extra:
      host: "0.0.0.0"
      port: 8642
      key: "${api_key}"
      cors_origins: "*"
${approvals_block}${delegation_block}
YAMLEOF
        echo "== Wrote minimal config.yaml."
        return
    fi

    local default_model="${HERMES_DEFAULT_MODEL:-${OPENAI_DEFAULT_MODEL:-openai/gpt-4o}}"

    local models_yaml=""
    local model_id ctx_len is_default
    while IFS= read -r model_id; do
        [ -z "$model_id" ] && continue
        is_default=0
        [ "$model_id" = "$default_model" ] && is_default=1
        ctx_len=$(resolve_ctx_len "$model_id")
        if [ -n "$ctx_len" ]; then
            # Known family -> pin the accurate context length.
            models_yaml="${models_yaml}      ${model_id}:
        context_length: ${ctx_len}
"
        elif [ "$is_default" -eq 1 ]; then
            # Default model ALWAYS gets an explicit context_length so config.yaml
            # has >=1 entry (fallback-resilience test) and the active model has a
            # sane window even when its family is unknown.
            models_yaml="${models_yaml}      ${model_id}:
        context_length: 200000
"
        else
            # Unknown family -> emit an empty mapping so the hermes-agent
            # self-resolves the context length at runtime (its own table /
            # models.dev / endpoint probe).
            models_yaml="${models_yaml}      ${model_id}: {}
"
        fi
    done <<< "$DISCOVERED_MODELS"

    local browser_block=""
    if [ "${BROWSER_HUMAN_LOOP_ENABLED:-false}" = "true" ]; then
        browser_block="
browser:
  cdp_url: http://127.0.0.1:9222
"
    fi

    # Built-in optional skills from the agent runtime copy
    local optional_skills_dir="${HERMES_HOME}/hermes-agent/optional-skills"
    local skills_block=""
    if [ -d "$optional_skills_dir" ]; then
        skills_block="
skills:
  external_dirs:
    - ${optional_skills_dir}
"
    fi

    cat > "$CONFIG" << YAMLEOF
model:
  provider: litellm
  default: ${default_model}
  name: ${default_model}

custom_providers:
  - name: litellm
    base_url: ${OPENAI_BASE_URL}
    models:
${models_yaml}
    key_env: OPENAI_API_KEY

platforms:
  api_server:
    enabled: true
    extra:
      host: "0.0.0.0"
      port: 8642
      key: "${api_key}"
      cors_origins: "*"
${browser_block}${skills_block}${approvals_block}${goals_block}${delegation_block}
YAMLEOF

    echo "== Wrote config.yaml with $(echo "$DISCOVERED_MODELS" | wc -l) models."
}

# Append skills.external_dirs to config.yaml — called AFTER ensure_agent()
# so that the optional-skills directory exists on disk.
append_skills_external_dirs() {
    local optional_skills_dir="${HERMES_HOME}/hermes-agent/optional-skills"
    if [ ! -d "$optional_skills_dir" ]; then
        echo "!! optional-skills dir not found at $optional_skills_dir, skipping external_dirs."
        return
    fi
    # Only add if not already present
    if grep -q 'external_dirs' "$CONFIG" 2>/dev/null; then
        return
    fi
    cat >> "$CONFIG" << YAMLEOF

skills:
  external_dirs:
    - ${optional_skills_dir}
YAMLEOF
    echo "== Appended skills.external_dirs -> ${optional_skills_dir}"
}
