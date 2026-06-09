# lib/config-hermes.sh - hermes config.yaml generation - sourced by entrypoint.sh

generate_config() {
    mkdir -p "$(dirname "$CONFIG")"

    local api_key="${HERMES_API_KEY:-}"
    if [ -z "$api_key" ]; then
        api_key="hermes-$(openssl rand -hex 16)"
        echo "== Generated random HERMES_API_KEY: $api_key"
    fi

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
YAMLEOF
        echo "== Wrote minimal config.yaml."
        return
    fi

    local default_model="${HERMES_DEFAULT_MODEL:-${OPENAI_DEFAULT_MODEL:-openai/gpt-4o}}"

    local models_yaml=""
    while IFS= read -r model_id; do
        [ -z "$model_id" ] && continue
        models_yaml="${models_yaml}      ${model_id}:
        context_length: 200000
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
${browser_block}${skills_block}
YAMLEOF

    echo "== Wrote config.yaml with $(echo "$DISCOVERED_MODELS" | wc -l) models."
}
