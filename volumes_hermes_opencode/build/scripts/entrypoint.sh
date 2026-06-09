#!/usr/bin/env bash
set -euo pipefail

export HERMES_HOME="/home/hermeswebui/.hermes"
CONFIG="/home/hermeswebui/.hermes/config.yaml"
AGENT_DIR="/home/hermeswebui/.hermes/hermes-agent"
STAGING_DIR="/opt/hermes-agent-staging"
HERMES_SKILLS_DIR="/home/hermeswebui/.hermes/skills"
OPENCODE_USER="hermeswebui"
OPENCODE_USER_HOME="/home/${OPENCODE_USER}"
OPENCODE_CONFIG="${OPENCODE_USER_HOME}/.config/opencode/opencode.jsonc"
OPENCODE_SKILLS_DIR="${OPENCODE_USER_HOME}/.config/opencode/skills"

# Detect whether we're running inside Docker or on bare Linux.
# Precedence: RUNTIME_ENV env var > /.dockerenv > KUBERNETES_SERVICE_HOST > default "local"
detect_runtime_env() {
    local mode source
    if [ -n "${RUNTIME_ENV:-}" ]; then
        mode="$(printf '%s' "$RUNTIME_ENV" | tr '[:upper:]' '[:lower:]')"
        case "$mode" in
            docker|local) source="RUNTIME_ENV" ;;
            *)
                echo "!! WARNING: Invalid RUNTIME_ENV value '${RUNTIME_ENV}', falling through to auto-detection." >&2
                mode=""
                ;;
        esac
    fi
    if [ -z "${mode:-}" ] && [ -f "/.dockerenv" ]; then
        mode="docker"
        source="/.dockerenv"
    fi
    if [ -z "${mode:-}" ] && [ -n "${KUBERNETES_SERVICE_HOST:-}" ]; then
        mode="docker"
        source="KUBERNETES_SERVICE_HOST"
    fi
    if [ -z "${mode:-}" ]; then
        mode="local"
        source="default"
    fi
    echo "== Detected runtime environment: ${mode} (source: ${source})" >&2
    echo "${mode}"
}

# Replace host.docker.internal with localhost when running outside Docker.
normalize_base_url_for_local() {
    local url="$1"
    if [ "${RUNTIME_ENV_MODE}" = "local" ] && [[ "$url" == *host.docker.internal* ]]; then
        url="${url//host.docker.internal/localhost}"
        echo "== Substituted host.docker.internal -> localhost in OPENAI_BASE_URL (local runtime mode)" >&2
    fi
    echo "${url}"
}

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
    r'replicate', r'resolution', r'cli-proxy-api',
]
skip_re = [re.compile(p, re.IGNORECASE) for p in skip_patterns]

seen_keys = set()
for line in sys.stdin:
    model_id = line.strip()
    if not model_id:
        continue
    if any(p.search(model_id) for p in skip_re):
        continue
    if re.search(r'/\*$', model_id):
        continue
    key = model_id.lower()
    if key in seen_keys:
        continue
    seen_keys.add(key)
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
${browser_block}
YAMLEOF

    echo "== Wrote config.yaml with $(echo "$DISCOVERED_MODELS" | wc -l) models."
}

generate_opencode_config() {
    if [ -z "${OPENAI_BASE_URL:-}" ] || [ -z "${OPENAI_API_KEY:-}" ]; then
        echo "!! Skipping opencode config: missing OPENAI_BASE_URL or OPENAI_API_KEY."
        return
    fi

    mkdir -p "$(dirname "$OPENCODE_CONFIG")"

    local default_model="${OPENCODE_DEFAULT_MODEL:-${OPENAI_DEFAULT_MODEL:-openai/gpt-4o}}"
    local small_model="${OPENCODE_SMALL_MODEL:-${OPENAI_SMALL_MODEL:-$default_model}}"
    local base_url="${OPENAI_BASE_URL%/}"

    local models_json
    models_json=$(echo "$DISCOVERED_MODELS" | python3 -c "
import sys, re, json

def get_limits(model_id):
    name = model_id.lower()
    bare = name.split('/', 1)[-1] if '/' in name else name

    if any(p in name for p in ['openrouter/', 'vertex_ai/', 'cli-proxy-api/']):
        name = bare

    if 'gpt-4.1' in name:
        return 1048576, 32768
    if 'gpt-4o' in name:
        return 128000, 16384
    if 'gpt-4-turbo' in name:
        return 128000, 4096
    if re.search(r'gpt-4[\.-]', name) or name.endswith('gpt-4'):
        return 8192, 4096
    if 'gpt-3.5' in name:
        return 16384, 4096
    if 'gpt-5' in name:
        return 128000, 16384
    if re.search(r'/o[134]', name) or re.search(r'-o[134]', name):
        return 200000, 100000
    if re.search(r'claude-[34]', name):
        if re.search(r'claude-3\.7|claude-[45]', name):
            return 200000, 16384
        return 200000, 4096
    if 'deepseek' in name:
        return 128000, 8192
    if 'glm' in name:
        return 128000, 8192
    if 'llama_cpp' in model_id:
        return 200000, 32768
    if 'gemini' in name:
        return 1048576, 65536
    return 128000, 8192

entries = []
for line in sys.stdin:
    mid = line.strip()
    if not mid:
        continue
    ctx, out = get_limits(mid)
    entries.append(f'        \"{mid}\": {{\"limit\": {{\"context\": {ctx}, \"output\": {out}}}}}')

print(','.join(entries))
" 2>/dev/null)

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
  "model": "litellm/${default_model}",
  "small_model": "litellm/${small_model}"
}
JSONEOF

    echo "== Wrote opencode.jsonc with $(echo "$DISCOVERED_MODELS" | wc -l) models (security: ${security_mode})."

    chown -R "${OPENCODE_USER}:${OPENCODE_USER}" "$(dirname "$OPENCODE_CONFIG")"

    # --- Fix #28: Copy opencode config to root's config dir ---
    # When Hermes agent uses terminal() -> docker exec, it runs as root.
    # Without this, root has an empty config and custom providers are invisible.
    local root_opencode_config_dir="/root/.config/opencode"
    mkdir -p "$root_opencode_config_dir"
    cp "$OPENCODE_CONFIG" "${root_opencode_config_dir}/opencode.jsonc"
    echo "== Copied opencode.jsonc to ${root_opencode_config_dir}/opencode.jsonc (root config)."

    # --- Fix #29: Symlink root's opencode data dir to hermeswebui's ---
    # opencode serve runs as hermeswebui, so sessions live in hermeswebui's DB.
    # Root's DB (/root/.local/share/opencode/) is empty -> --attach always fails.
    local root_opencode_data="/root/.local/share/opencode"
    local user_opencode_data="${OPENCODE_USER_HOME}/.local/share/opencode"
    mkdir -p "$user_opencode_data"
    if [ -L "$root_opencode_data" ]; then
        echo "== ${root_opencode_data} already a symlink, skipping."
    elif [ -d "$root_opencode_data" ]; then
        # opencode installer creates this dir; replace with symlink
        rmdir "$root_opencode_data" 2>/dev/null || rm -rf "$root_opencode_data"
        ln -s "$user_opencode_data" "$root_opencode_data"
        echo "== Replaced existing ${root_opencode_data} dir with symlink -> ${user_opencode_data}."
    else
        ln -s "$user_opencode_data" "$root_opencode_data"
        echo "== Symlinked ${root_opencode_data} -> ${user_opencode_data} (shared session DB)."
    fi
    chown -R "${OPENCODE_USER}:${OPENCODE_USER}" "$user_opencode_data"
}

# --- Fix #30: Validate OpenCode Zen API key if set ---
# When OPENCODE_API_KEY is set but invalid, opencode/ models return 401.
# This check provides a helpful startup message instead of silent failures.
validate_opencode_zen_key() {
    local key="${OPENCODE_API_KEY:-}"
    if [ -z "$key" ]; then
        echo "== OPENCODE_API_KEY not set. opencode/ free models will use public fallback (may be limited)."
        return 0
    fi

    # Quick validation: try the Zen API models endpoint with the provided key
    local response
    response=$(curl -sf --max-time 10 \
        -H "Authorization: Bearer ${key}" \
        "https://opencode.ai/zen/v1/models" 2>/dev/null || echo "")

    if [ -z "$response" ]; then
        echo "!! WARNING: OPENCODE_API_KEY is set but the Zen API returned an error."
        echo "   opencode/ models may fail with 401 Invalid API key."
        echo "   Get a valid key at: https://opencode.ai/auth"
        return 1
    fi

    local model_count
    model_count=$(echo "$response" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(len(d.get('data', [])))
except Exception:
    print(0)
" 2>/dev/null || echo "0")

    echo "== OPENCODE_API_KEY validated. Zen API returned ${model_count} models."
    return 0
}

# Poll a TCP port until it accepts a connection or the timeout is reached.
# Uses bash /dev/tcp (no external deps). Does NOT exit on timeout — caller decides.
#
# Args:
#   $1: port number (default: 4096)
#   $2: timeout in seconds (default: 30)
#   $3: label used in log lines (default: "service")
#
# Returns:
#   0 if the port accepts a connection within the timeout
#   1 on timeout
wait_for_port() {
    local port="${1:-4096}"
    local timeout="${2:-30}"
    local label="${3:-service}"
    local elapsed=0
    echo "== ${label}: waiting for :${port} (0/${timeout}s)"
    while ! (exec 3<>"/dev/tcp/127.0.0.1/${port}") >/dev/null 2>&1; do
        sleep 5
        elapsed=$((elapsed + 5))
        if [ "$elapsed" -ge "$timeout" ]; then
            echo "!! ${label}: timeout waiting for :${port} after ${timeout}s"
            return 1
        fi
        echo "== ${label}: waiting for :${port} (${elapsed}/${timeout}s)"
    done
    echo "== ${label}: port ${port} ready (after ${elapsed}s)"
    return 0
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
    mkdir -p "${HERMES_HOME}/logs"
    nohup su -s /bin/bash "$OPENCODE_USER" -c '
        while true; do
            /app/venv/bin/hermes gateway run --accept-hooks
            rc=$?
            echo "[$(date)] gateway exited rc=$rc, restarting in 2s" >> "'"${HERMES_HOME}"'/logs/gateway-restart.log"
            sleep 2
        done
    ' > "${HERMES_HOME}/logs/gateway.log" 2>&1 &
    echo "== Gateway started (PID: $!)"
}

start_opencode_serve() {
    local enabled="${OPENCODE_SERVE_ENABLED:-false}"
    if [ "$enabled" != "true" ]; then
        echo "[entrypoint] opencode serve disabled (OPENCODE_SERVE_ENABLED=${enabled})"
        return 0
    fi
    if ! command -v opencode >/dev/null 2>&1; then
        echo "!! opencode not found, skipping serve start."
        return 0
    fi
    local password="${OPENCODE_SERVER_PASSWORD:-}"
    if [ -z "$password" ]; then
        password="$(openssl rand -hex 16)"
        echo "== Generated random OPENCODE_SERVER_PASSWORD: $password"
        export OPENCODE_SERVER_PASSWORD="$password"
    fi
    echo "$password" > /tmp/opencode-server-password
    chown "$OPENCODE_USER":"$OPENCODE_USER" /tmp/opencode-server-password
    local workdir="${OPENCODE_USER_HOME}"
    echo "== Starting opencode serve on :4096 (workdir: $workdir, user: $OPENCODE_USER)..."
    su -s /bin/bash "$OPENCODE_USER" -c "OPENCODE_SERVER_PASSWORD='$password' opencode serve --port 4096 --hostname 0.0.0.0" &
    echo "== OpenCode serve started (PID: $!)"
}

# Start the browser human-in-the-loop stack (Xvfb + openbox + x11vnc + websockify + Chromium).
# All processes run as hermeswebui (UID 1000). Controlled by BROWSER_HUMAN_LOOP_ENABLED.
start_browser_vnc() {
    if [ "${BROWSER_HUMAN_LOOP_ENABLED:-false}" != "true" ]; then
        echo "== Browser human-in-the-loop disabled (BROWSER_HUMAN_LOOP_ENABLED=${BROWSER_HUMAN_LOOP_ENABLED:-false})"
        return 0
    fi

    echo "== Starting browser human-in-the-loop stack..."

    # Ensure log directory exists
    mkdir -p "${HERMES_HOME}/logs"

    # Create chromium user-data directory and remove stale lockfiles from previous containers
    mkdir -p /home/hermeswebui/.hermes/chrome-debug
    chown "${OPENCODE_USER}:${OPENCODE_USER}" /home/hermeswebui/.hermes/chrome-debug
    rm -f /home/hermeswebui/.hermes/chrome-debug/SingletonLock \
           /home/hermeswebui/.hermes/chrome-debug/SingletonCookie \
           /home/hermeswebui/.hermes/chrome-debug/SingletonSocket

    # 1. Start Xvfb on display :99
    echo "== Starting Xvfb on :99..."
    su -s /bin/bash "$OPENCODE_USER" -c \
        'Xvfb :99 -screen 0 1280x720x24' \
        > "${HERMES_HOME}/logs/xvfb.log" 2>&1 &
    local xvfb_pid=$!
    echo "== Xvfb started (PID: $xvfb_pid)"

    export DISPLAY=:99
    sleep 1

    # 2. Start openbox window manager
    echo "== Starting openbox..."
    su -s /bin/bash "$OPENCODE_USER" -c \
        "DISPLAY=:99 openbox" \
        > "${HERMES_HOME}/logs/openbox.log" 2>&1 &
    echo "== Openbox started (PID: $!)"

    # 3. Set up VNC password
    local vnc_password="${BROWSER_VNC_PASSWORD:-hermes}"
    x11vnc -storepasswd "$vnc_password" /tmp/.vnc_passwd
    chown "${OPENCODE_USER}:${OPENCODE_USER}" /tmp/.vnc_passwd

    # 4. Start x11vnc
    echo "== Starting x11vnc on :5900..."
    su -s /bin/bash "$OPENCODE_USER" -c \
        "DISPLAY=:99 x11vnc -display :99 -rfbport 5900 -rfbauth /tmp/.vnc_passwd -forever -shared" \
        > "${HERMES_HOME}/logs/x11vnc.log" 2>&1 &
    echo "== x11vnc started (PID: $!)"

    # 5. Start websockify + noVNC
    local novnc_dir="/usr/share/novnc"
    if [ ! -f "${novnc_dir}/vnc.html" ]; then
        echo "!! WARNING: noVNC assets not found at ${novnc_dir}, websockify will run without web client."
    fi
    echo "== Starting websockify on :6901 -> localhost:5900 (noVNC: ${novnc_dir})..."
    websockify 6901 localhost:5900 --web="${novnc_dir}" \
        > "${HERMES_HOME}/logs/websockify.log" 2>&1 &
    echo "== websockify started (PID: $!)"

    # 6. Start Chromium with remote debugging
    echo "== Starting Chromium (CDP on :9222)..."
    su -s /bin/bash "$OPENCODE_USER" -c \
        "DISPLAY=:99 chromium --remote-debugging-port=9222 --user-data-dir=/home/hermeswebui/.hermes/chrome-debug --no-sandbox --disable-gpu --no-first-run --disable-dev-shm-usage" \
        > "${HERMES_HOME}/logs/chromium.log" 2>&1 &
    echo "== Chromium started (PID: $!)"

    echo "== Browser human-in-the-loop stack started."
}

if [ "${SKIP_SKILL_INSTALL:-0}" != "1" ]; then
    echo "== Copying staged hermes skills..."
    mkdir -p "$HERMES_SKILLS_DIR"
    cp -a /opt/hermes-skills-staging/. "$HERMES_SKILLS_DIR/" 2>/dev/null || true
    if command -v graphify >/dev/null 2>&1; then
        echo "== Registering graphify for hermes..."
        graphify install --platform hermes 2>/dev/null || true
    fi
else
    echo "== Skipping skill staging copy (SKIP_SKILL_INSTALL=1)"
fi

RUNTIME_ENV_MODE="$(detect_runtime_env)"
export RUNTIME_ENV_MODE
if [ -n "${OPENAI_BASE_URL:-}" ]; then
    OPENAI_BASE_URL="$(normalize_base_url_for_local "${OPENAI_BASE_URL}")"
    export OPENAI_BASE_URL
fi

discover_models
generate_config
generate_opencode_config
validate_opencode_zen_key || true
ensure_agent

/hermeswebui_init.bash &
WEBUI_PID=$!
echo "== WebUI init started (PID: $WEBUI_PID)"

wait_for_port 8787 300 "webui"

start_browser_vnc

start_gateway
wait_for_port 8642 60 "hermes gateway"

start_opencode_serve

if [ "${OPENCODE_SERVE_ENABLED:-false}" = "true" ]; then
    # Boot-time readiness probe for opencode serve. Non-fatal: a timeout only logs.
    wait_for_port 4096 "${OPENCODE_SERVE_BOOT_TIMEOUT:-30}" "opencode serve" || \
        echo "!! opencode serve did not become ready within ${OPENCODE_SERVE_BOOT_TIMEOUT:-30}s; continuing."
fi

echo "== All services running. Waiting..."
wait
echo "!! A background process exited. Container shutting down."
