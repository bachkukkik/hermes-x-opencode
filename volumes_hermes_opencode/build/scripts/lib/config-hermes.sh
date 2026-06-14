# lib/config-hermes.sh - hermes config.yaml generation - sourced by entrypoint.sh

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
    while IFS= read -r model_id; do
        [ -z "$model_id" ] && continue
        if echo "$model_id" | grep -q 'glm-5.2'; then
            ctx_len=1048576
        else
            ctx_len=200000
        fi
        models_yaml="${models_yaml}      ${model_id}:
        context_length: ${ctx_len}
"
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
${browser_block}${skills_block}${approvals_block}${delegation_block}
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
