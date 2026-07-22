# lib/config-hermes.sh - hermes config.yaml generation - sourced by entrypoint.sh

# Resolve a model's context length from a small pin table of well-known model
# families (substring match, longest/most-specific pattern first). Echoes the
# pinned value, or empty string when the model is unknown — the caller then
# omits the context_length line so the hermes-agent self-resolves it at runtime
# via its own DEFAULT_CONTEXT_LENGTHS table / models.dev / endpoint probe.
#
# Why pin at all when the agent self-resolves? (1) The DEFAULT model must always
# carry an explicit context_length (see generate_hermes_config) so config.yaml has >=1
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
        *agents-a1-mtp-apex*) echo 262144  ;;  # Agents A1 MTP (new) — 262K native ctx
        *agents-a1-q4*)      echo 262144  ;;  # Agents A1 q4_k_m (new) — same architecture
        *)                   echo ""      ;;  # unknown -> omit, agent self-resolves
    esac
}

generate_hermes_config() {
    log "--- generate_hermes_config ---"

    mkdir -p "$(dirname "$CONFIG")"

    if [ -z "$HERMES_API_KEY" ]; then
        HERMES_API_KEY="hermes-$(openssl rand -hex 16)"
        export HERMES_API_KEY
        log "Generated random HERMES_API_KEY: $HERMES_API_KEY"
    fi

    # Runtime autonomy blocks (#53): approvals off + delegation subagent loop,
    # both gated on HERMES_YOLO_MODE so supervised (non-YOLO) boots emit neither.
    local approvals_block=""
    local delegation_block=""
    case "$HERMES_YOLO_MODE" in
        1|true|yes|on)
            approvals_block="
approvals:
  mode: off
"
            delegation_block="
delegation:
  max_iterations: ${HERMES_DELEGATION_MAX_ITERATIONS}
"
            if [ -n "${HERMES_DELEGATION_MODEL:-}" ]; then
                log "Delegation model: ${HERMES_DELEGATION_MODEL}"
                delegation_block="${delegation_block}
  model: ${HERMES_DELEGATION_MODEL}"
            fi
            if [ -n "${HERMES_DELEGATION_PROVIDER:-}" ]; then
                log "Delegation provider: ${HERMES_DELEGATION_PROVIDER}"
                delegation_block="${delegation_block}
  provider: ${HERMES_DELEGATION_PROVIDER}"
            fi
            ;;
    esac

    # Main agent tool-calling loop budget: always emitted so the agent runs up to
    # HERMES_AGENT_MAX_TURNS iterations instead of the built-in 90. The gateway
    # bridges agent.max_turns → HERMES_MAX_ITERATIONS (config.yaml is authoritative
    # and wins over any stale .env HERMES_MAX_ITERATIONS ghost). This is the loop
    # that prints "Reached maximum iterations (N)" — NOT goals.max_turns or
    # delegation.max_iterations, which cap the /goal and subagent loops respectively.
    local agent_block="
agent:
  max_turns: ${HERMES_AGENT_MAX_TURNS}
"

    # /goal cross-turn budget: always emitted so /goal runs up to
    # HERMES_GOAL_MAX_TURNS turns (default 50) instead of the built-in 20.
    local goals_block="
goals:
  max_turns: ${HERMES_GOAL_MAX_TURNS}
"

    # Web search backend: ddgs (keyless, search-only) for web_search, with the
    # extract backend left to auto/lazy so web_extract still fetches URL content.
    # Set HERMES_WEB_EXTRACT_BACKEND to pin a specific extractor.
    local web_block="
web:
  search_backend: ${HERMES_WEB_SEARCH_BACKEND}
"
    if [ -n "${HERMES_WEB_EXTRACT_BACKEND:-}" ]; then
        web_block="${web_block}  extract_backend: ${HERMES_WEB_EXTRACT_BACKEND}
"
    fi

    # Lazy-install optional deps (e.g. the `ddgs` package) on first use.
    local security_block="
security:
  allow_lazy_installs: ${HERMES_ALLOW_LAZY_INSTALLS}
"

    # model.max_tokens: OUTPUT-token cap Hermes sends per request (NOT the
    # context window — that's context_length in the models map). Left unset,
    # Hermes sends no max_tokens and the upstream proxy/provider applies its own
    # small default, truncating long responses (finish_reason='length') — e.g. a
    # delegation subagent emitting one large JSON payload gets its tool-call args
    # cut off mid-stream. Subagents inherit the parent max_tokens (delegation has
    # no separate output-cap knob), so baking it here raises the cap for the main
    # agent AND its subagents. cli.py reads model.max_tokens (env HERMES_MAX_TOKENS
    # wins at runtime). Integer only — a non-integer value is ignored. Value must
    # stay below the model's context window; if a provider rejects it, lower it.
    local max_tokens_line=""
    if printf '%s' "${HERMES_MAX_TOKENS:-}" | grep -qE '^[0-9]+$'; then
        max_tokens_line="
  max_tokens: ${HERMES_MAX_TOKENS}"
    fi

    # Minimal fallback config when no LLM provider is configured
    if [ -z "${OPENAI_BASE_URL:-}" ]; then
        warn "NO OPENAI_BASE_URL — writing minimal config (api_server + default model)."
        cat > "$CONFIG" << YAMLEOF
model:
  provider: litellm
  default: ${HERMES_DEFAULT_MODEL}
  name: ${HERMES_DEFAULT_MODEL}${max_tokens_line}

custom_providers:
  - name: litellm
    base_url: ""
    models:
      ${HERMES_DEFAULT_MODEL}:
        context_length: ${OPENAI_CONTEXT_LENGTH}
    key_env: OPENAI_API_KEY

platforms:
  api_server:
    enabled: true
    extra:
      host: "0.0.0.0"
      port: ${HERMES_API_PORT}
      key: "${HERMES_API_KEY}"
      cors_origins: "*"
${agent_block}${approvals_block}${goals_block}${delegation_block}
YAMLEOF
        log "Wrote minimal config.yaml."
        return
    fi

    local models_yaml=""
    local model_id ctx_len is_default
    while IFS= read -r model_id; do
        [ -z "$model_id" ] && continue
        is_default=0
        [ "$model_id" = "$HERMES_DEFAULT_MODEL" ] && is_default=1
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
        context_length: ${OPENAI_CONTEXT_LENGTH}
"
        else
            # Unknown family -> emit an empty mapping so the hermes-agent
            # self-resolves the context length at runtime (its own table /
            # models.dev / endpoint probe).
            models_yaml="${models_yaml}      ${model_id}: {}
"
        fi
    done <<< "$DISCOVERED_MODELS"

    cat > "$CONFIG" << YAMLEOF
model:
  provider: litellm
  default: ${HERMES_DEFAULT_MODEL}
  name: ${HERMES_DEFAULT_MODEL}${max_tokens_line}

custom_providers:
  - name: litellm
    base_url: ${OPENAI_BASE_URL}
    models:
${models_yaml}
    key_env: OPENAI_API_KEY

compression:
  threshold: ${HERMES_COMPRESSION_THRESHOLD}

logging:
  level: DEBUG
  max_size_mb: 5
  backup_count: 3

image_gen:
  provider: openai
  model: ${OPENAI_IMAGE_MODEL}
${web_block}${security_block}
platforms:
  api_server:
    enabled: true
    extra:
      host: "0.0.0.0"
      port: ${HERMES_API_PORT}
      key: "${HERMES_API_KEY}"
      cors_origins: "*"
${agent_block}${approvals_block}${goals_block}${delegation_block}
YAMLEOF

    log "Wrote config.yaml with $(echo "$DISCOVERED_MODELS" | wc -l) models."
}

append_browser_config() {
    log "--- append_browser_config ---"
    if [ "${BROWSER_HUMAN_LOOP_ENABLED:-false}" = "true" ]; then
        cat >> "$CONFIG" << YAMLEOF

browser:
  cdp_url: http://127.0.0.1:9222
  viewport:
    width: ${BROWSER_DISPLAY_WIDTH:-1920}
    height: ${BROWSER_DISPLAY_HEIGHT:-1080}
YAMLEOF
        log "Appended browser.cdp_url + viewport to config.yaml"
    fi
}

append_computer_use_config() {
    log "--- append_computer_use_config ---"
    # Stub — skip for now (no computer_use support in HXO yet).
    :
}

# Append skills.external_dirs to config.yaml — called AFTER ensure_agent()
# so that the optional-skills directory exists on disk.
append_skills_external_dirs() {
    log "--- append_skills_external_dirs ---"
    local optional_skills_dir="${AGENT_DIR:-${HERMES_HOME}/hermes-agent}/optional-skills"
    if [ -d "$optional_skills_dir" ]; then
        if ! grep -q 'external_dirs' "$CONFIG"; then
            cat >> "$CONFIG" << YAMLEOF

skills:
  external_dirs:
    - ${optional_skills_dir}
YAMLEOF
            log "Appended skills.external_dirs to config.yaml"
        fi
    else
        log "optional-skills dir not found at $optional_skills_dir, skipping external_dirs"
    fi
}
