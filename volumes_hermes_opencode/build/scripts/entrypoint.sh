#!/usr/bin/env bash
set -euo pipefail

export HERMES_HOME="/home/hermeswebui/.hermes"
CONFIG="/home/hermeswebui/.hermes/config.yaml"
AGENT_DIR="/home/hermeswebui/.hermes/hermes-agent"
STAGING_DIR="/opt/hermes-agent-staging"
OPENCODE_USER="hermeswebui"
OPENCODE_USER_HOME="/home/${OPENCODE_USER}"
OPENCODE_CONFIG="${OPENCODE_USER_HOME}/.config/opencode/opencode.jsonc"
OPENCODE_SKILLS_DIR="${OPENCODE_USER_HOME}/.config/opencode/skills"

_SKIP_MODEL_PATTERNS="embed whisper tts dall-e sora image realtime transcrib moderat audio codegen babbage davinci curie ^ada$ text- stable midjourney flux /sd/ mj replicate dall-e"

ensure_agent() {
    if [ -f "$AGENT_DIR/pyproject.toml" ]; then
        echo "== Agent already present at $AGENT_DIR"
        return
    fi
    if [ ! -d "$STAGING_DIR" ]; then
        echo "!! No staged agent found at $STAGING_DIR"
        return
    fi
    echo "== Copying staged agent to $AGENT_DIR..."
    mkdir -p "$(dirname "$AGENT_DIR")"
    cp -a "$STAGING_DIR" "$AGENT_DIR"
    echo "== Agent copied."
}

discover_models() {
    local base_url="${OPENAI_BASE_URL:-}"
    local api_key="${OPENAI_API_KEY:-}"
    local default_model="${OPENAI_DEFAULT_MODEL:-openai/gpt-4o}"
    DISCOVERED_MODELS=""

    if [ -z "$base_url" ] || [ -z "$api_key" ]; then
        echo "!! OPENAI_BASE_URL or OPENAI_API_KEY not set, using default model only."
        DISCOVERED_MODELS="$default_model"
        return
    fi

    echo "== Discovering models from $base_url ..."
    local response
    response=$(curl -sf --max-time 15 \
        -H "Authorization: Bearer $api_key" \
        "${base_url}/models" 2>/dev/null || echo "")

    if [ -z "$response" ]; then
        echo "!! Model discovery failed, using default model only."
        DISCOVERED_MODELS="$default_model"
        return
    fi

    local all_ids
    all_ids=$(echo "$response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    models = data.get('data', [])
    for m in models:
        mid = m.get('id', '')
        if mid:
            print(mid)
except Exception:
    pass
" 2>/dev/null || echo "")

    if [ -z "$all_ids" ]; then
        echo "!! Could not parse model list, using default model only."
        DISCOVERED_MODELS="$default_model"
        return
    fi

    local filtered
    filtered=$(echo "$all_ids" | python3 -c "
import sys, re

skip_patterns = [
    r'embed', r'whisper', r'tts', r'dall[\-\-]?e', r'sora',
    r'\bimage\b', r'realtime', r'transcrib', r'moderat', r'\baudio\b',
    r'codegen', r'babbage', r'davinci', r'\bcurie\b', r'\bada\b',
    r'text-', r'stable', r'midjourney', r'flux', r'/sd/', r'\bmj\b',
    r'replicate', r'resolution',
]
skip_re = [re.compile(p, re.IGNORECASE) for p in skip_patterns]

for line in sys.stdin:
    model_id = line.strip()
    if not model_id:
        continue
    if any(p.search(model_id) for p in skip_re):
        continue
    if re.search(r'/\*$', model_id):
        continue
    print(model_id)
" 2>/dev/null || echo "")

    if [ -z "$filtered" ]; then
        echo "!! All models filtered out, using default model only."
        DISCOVERED_MODELS="$default_model"
        return
    fi

    local count
    count=$(echo "$filtered" | wc -l)
    echo "== Discovered $count chat models."

    has_default=false
    while IFS= read -r m; do
        if [ "$m" = "$default_model" ]; then
            has_default=true
            break
        fi
    done <<< "$filtered"

    if [ "$has_default" = false ]; then
        echo "== Adding default model $default_model to discovered list."
        filtered="${default_model}"$'\n'"${filtered}"
    fi

    DISCOVERED_MODELS="$filtered"
}

generate_config() {
    if [ -z "${OPENAI_BASE_URL:-}" ]; then
        return
    fi
    mkdir -p "$(dirname "$CONFIG")"

    local api_key="${HERMES_API_KEY:-}"
    if [ -z "$api_key" ]; then
        api_key="hermes-$(openssl rand -hex 16)"
        echo "== Generated random HERMES_API_KEY: $api_key"
    fi

    local default_model="${OPENAI_DEFAULT_MODEL:-openai/gpt-4o}"

    local models_yaml=""
    while IFS= read -r model_id; do
        [ -z "$model_id" ] && continue
        models_yaml="${models_yaml}      ${model_id}:
        context_length: 200000
"
    done <<< "$DISCOVERED_MODELS"

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
YAMLEOF

    echo "== Wrote config.yaml with $(echo "$DISCOVERED_MODELS" | wc -l) models."
}

generate_opencode_config() {
    if [ -z "${OPENAI_BASE_URL:-}" ] || [ -z "${OPENAI_API_KEY:-}" ]; then
        echo "!! Skipping opencode config: missing OPENAI_BASE_URL or OPENAI_API_KEY."
        return
    fi

    mkdir -p "$(dirname "$OPENCODE_CONFIG")"

    local default_model="${OPENAI_DEFAULT_MODEL:-openai/gpt-4o}"
    local base_url="${OPENAI_BASE_URL%/}"

    local models_json=""
    local first=true
    while IFS= read -r model_id; do
        [ -z "$model_id" ] && continue
        if [ "$first" = true ]; then
            first=false
        else
            models_json="${models_json},"
        fi
        models_json="${models_json}
        \"${model_id}\": {}"
    done <<< "$DISCOVERED_MODELS"

    local security_mode="${OPENCODE_SECURITY_MODE:-strict}"
    local permission_block

    case "$security_mode" in
        yolo)
            permission_block='"permission": "allow",'
            ;;
        standard)
            permission_block=$(cat << 'PERMEOF'
  "permission": {
    "read": {
      "*": "allow",
      ".env*": "deny",
      "*/.env*": "deny",
      "*.env": "deny"
    },
    "edit": {
      "*": "allow",
      ".env*": "deny",
      "*/.env*": "deny",
      "*.env": "deny"
    },
    "glob": {
      "*": "allow",
      ".env*": "deny",
      "*/.env*": "deny"
    },
    "grep": {
      "*": "allow",
      ".env*": "deny",
      "*/.env*": "deny"
    },
    "list": "allow",
    "bash": {
      "*": "allow",
      "printenv *": "deny",
      "printenv": "deny",
      "*/printenv": "deny",
      "*/printenv *": "deny",
      "/usr/bin/printenv": "deny",
      "/usr/bin/printenv *": "deny",
      "env": "deny",
      "/usr/bin/env": "deny",
      "/usr/bin/env *": "deny",
      "set": "deny",
      "export": "deny",
      "export *": "deny",
      "echo *$*": "deny",
      "printf *$*": "deny",
      "cat *.env*": "deny",
      "cat */.env*": "deny",
      "cat */.envrc": "deny",
      "less *.env*": "deny",
      "head *.env*": "deny",
      "tail *.env*": "deny",
      "cat /proc/*/environ*": "deny"
    },
    "task": "allow",
    "external_directory": { "*": "allow" },
    "todowrite": "allow",
    "question": "allow",
    "webfetch": "allow",
    "websearch": "allow",
    "skill": "allow",
    "lsp": "allow",
    "repo_clone": "allow",
    "repo_overview": "allow",
    "doom_loop": "allow"
  },
PERMEOF
)
            ;;
        strict|*)
            permission_block=$(cat << 'PERMEOF'
  "permission": {
    "read": {
      "*": "allow",
      ".env*": "deny",
      "*/.env*": "deny",
      "*.env": "deny"
    },
    "edit": {
      "*": "allow",
      ".env*": "deny",
      "*/.env*": "deny",
      "*.env": "deny"
    },
    "glob": {
      "*": "allow",
      ".env*": "deny",
      "*/.env*": "deny"
    },
    "grep": {
      "*": "allow",
      ".env*": "deny",
      "*/.env*": "deny"
    },
    "list": "allow",
    "bash": {
      "*": "allow",
      "printenv *": "deny",
      "printenv": "deny",
      "*/printenv": "deny",
      "*/printenv *": "deny",
      "/usr/bin/printenv": "deny",
      "/usr/bin/printenv *": "deny",
      "env": "deny",
      "/usr/bin/env": "deny",
      "/usr/bin/env *": "deny",
      "set": "deny",
      "export": "deny",
      "export *": "deny",
      "echo *$*": "deny",
      "printf *$*": "deny",
      "cat *.env*": "deny",
      "cat */.env*": "deny",
      "cat */.envrc": "deny",
      "less *.env*": "deny",
      "head *.env*": "deny",
      "tail *.env*": "deny",
      "cat /proc/*/environ*": "deny",
      "python3 -c *": "deny",
      "python -c *": "deny",
      "node -e *": "deny",
      "node -c *": "deny",
      "perl -e *": "deny",
      "ruby -e *": "deny",
      "ruby -c *": "deny",
      "bash -c *": "deny",
      "sh -c *": "deny"
    },
    "task": "allow",
    "external_directory": { "*": "allow" },
    "todowrite": "allow",
    "question": "allow",
    "webfetch": "allow",
    "websearch": "allow",
    "skill": "allow",
    "lsp": "allow",
    "repo_clone": "allow",
    "repo_overview": "allow",
    "doom_loop": "allow"
  },
PERMEOF
)
            ;;
    esac

    cat > "$OPENCODE_CONFIG" << JSONEOF
{
  "\$schema": "https://opencode.ai/config.json",
  "plugin": [
    "@tarquinen/opencode-dcp@latest",
    "@franlol/opencode-md-table-formatter@latest",
    "cc-safety-net"
  ],
${permission_block}
  "provider": {
    "litellm": {
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "apiKey": "{env:OPENAI_API_KEY}",
        "baseURL": "${base_url}"
      },
      "models": {${models_json}
      }
    }
  },
  "model": "litellm/${default_model}"
}
JSONEOF

    echo "== Wrote opencode.jsonc with $(echo "$DISCOVERED_MODELS" | wc -l) models (security: ${security_mode})."

    chown -R "${OPENCODE_USER}:${OPENCODE_USER}" "$(dirname "$OPENCODE_CONFIG")"
}

wait_for_port() {
    local port=$1
    local max_wait=${2:-120}
    local elapsed=0
    echo "== Waiting for port $port to be ready (timeout: ${max_wait}s)..."
    while ! curl -sf "http://localhost:${port}/health" >/dev/null 2>&1; do
        sleep 2
        elapsed=$((elapsed + 2))
        if [ "$elapsed" -ge "$max_wait" ]; then
            echo "!! Timeout waiting for port $port after ${max_wait}s"
            return 1
        fi
    done
    echo "== Port $port is ready."
}

start_gateway() {
    if [ ! -f "$AGENT_DIR/pyproject.toml" ]; then
        echo "!! hermes-agent not found, skipping gateway start."
        return
    fi
    if [ ! -f /app/venv/bin/hermes ]; then
        echo "!! hermes CLI not in venv, skipping gateway start."
        return
    fi
    echo "== Starting hermes gateway (api_server on :8642)..."
    su -s /bin/bash "$OPENCODE_USER" -c "/app/venv/bin/hermes gateway run --accept-hooks" &
    echo "== Gateway started (PID: $!)"
}

start_opencode_serve() {
    if ! command -v opencode >/dev/null 2>&1; then
        echo "!! opencode not found, skipping serve start."
        return
    fi
    local workdir="${OPENCODE_USER_HOME}"
    echo "== Starting opencode serve on :4096 (workdir: $workdir, user: $OPENCODE_USER)..."
    su -s /bin/bash "$OPENCODE_USER" -c "opencode serve --port 4096 --hostname 0.0.0.0" &
    echo "== OpenCode serve started (PID: $!)"
}

if [ "${SKIP_SKILL_INSTALL:-0}" != "1" ]; then
    echo "== Installing skills..."
    export OPENCODE_SKILLS_DIR
    mkdir -p "$OPENCODE_SKILLS_DIR"
    install-skills.sh
else
    echo "== Skipping skill install (SKIP_SKILL_INSTALL=1)"
fi

discover_models
generate_config
generate_opencode_config
ensure_agent

/hermeswebui_init.bash &
WEBUI_PID=$!
echo "== WebUI init started (PID: $WEBUI_PID)"

wait_for_port 8787 120

start_gateway
wait_for_port 8642 60

start_opencode_serve

echo "== All services running. Waiting..."
wait -n
echo "!! A background process exited. Container shutting down."
