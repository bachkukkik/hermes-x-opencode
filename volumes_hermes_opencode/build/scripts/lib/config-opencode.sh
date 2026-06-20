# lib/config-opencode.sh - OpenCode config generation - sourced by entrypoint.sh

_resolve_provider_prefix() {
    local model="$1"
    case "$model" in
        opencode/*) echo "opencode" ;;
        litellm/*)  echo "litellm" ;;
        *)
            if [ -n "${OPENAI_BASE_URL:-}" ] && [ -n "${OPENAI_API_KEY:-}" ]; then
                echo "litellm"
            else
                echo "opencode"
            fi
            ;;
    esac
}

_strip_provider_prefix() {
    local model="$1"
    case "$model" in
        opencode/*) echo "${model#opencode/}" ;;
        litellm/*) echo "${model#litellm/}" ;;
        *) echo "$model" ;;
    esac
}

generate_opencode_config() {
    local _has_opencode_key=false
    local _has_openai_creds=false
    [ -n "${OPENCODE_API_KEY:-}" ] && _has_opencode_key=true
    [ -n "${OPENAI_BASE_URL:-}" ] && [ -n "${OPENAI_API_KEY:-}" ] && _has_openai_creds=true

    if ! $_has_opencode_key && ! $_has_openai_creds; then
        echo "!! Skipping opencode config: missing OPENCODE_API_KEY or (OPENAI_BASE_URL + OPENAI_API_KEY)."
        return
    fi

    mkdir -p "$(dirname "$OPENCODE_CONFIG")"

    local _raw_default_model="${OPENCODE_DEFAULT_MODEL:-${OPENAI_DEFAULT_MODEL:-deepseek-v4-flash-free}}"
    local _raw_small_model="${OPENCODE_SMALL_MODEL:-${OPENAI_SMALL_MODEL:-$_raw_default_model}}"

    local default_model
    default_model="$(_strip_provider_prefix "$_raw_default_model")"
    local small_model
    small_model="$(_strip_provider_prefix "$_raw_small_model")"

    local default_prefix
    default_prefix=$(_resolve_provider_prefix "$_raw_default_model")
    local small_prefix
    small_prefix=$(_resolve_provider_prefix "$_raw_small_model")

    local _raw_fallback_model="${OPENCODE_FALLBACK_MODEL:-}"
    local fallback_model fallback_prefix
    if [ -n "$_raw_fallback_model" ]; then
        fallback_model="$(_strip_provider_prefix "$_raw_fallback_model")"
        fallback_prefix="$(_resolve_provider_prefix "$_raw_fallback_model")"
    fi

    local base_url="${OPENAI_BASE_URL%/}"

    local models_json=""
    if $_has_openai_creds; then
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
    if 'glm-5.2' in name:
        return 1048576, 131072
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
    fi

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

    # Build provider entries: opencode (built-in models) then litellm (proxy)
    local _oc_entry=""
    if $_has_opencode_key; then
        _oc_entry=$(cat << 'OCEOF'
    "opencode": {
      "options": {
        "apiKey": "{env:OPENCODE_API_KEY}"
      }
    }
OCEOF
)
    fi

    local _ll_entry=""
    if $_has_openai_creds; then
        _ll_entry=$(cat << PROVEOF
    "litellm": {
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "apiKey": "{env:OPENAI_API_KEY}",
        "baseURL": "${base_url}"
      },
      "models": {${models_json}
      }
    }
PROVEOF
)
    fi

    # Join entries (comma-separated), wrap in provider block
    local _entries=""
    if [ -n "$_oc_entry" ] && [ -n "$_ll_entry" ]; then
        _entries="${_oc_entry},
${_ll_entry}"
    else
        _entries="${_oc_entry}${_ll_entry}"
    fi

    local provider_block
    provider_block=$(cat << PEMEOF
  "provider": {
${_entries}
  },
PEMEOF
)

    local _plugins
    _plugins='    "@tarquinen/opencode-dcp@latest",
    "@franlol/opencode-md-table-formatter@latest",
    "cc-safety-net"'
    if [ -n "$_raw_fallback_model" ]; then
        _plugins="${_plugins},
    \"opencode-runtime-fallback\""
    fi

    cat > "$OPENCODE_CONFIG" << JSONEOF
{
  "\$schema": "https://opencode.ai/config.json",
  "plugin": [
${_plugins}
  ],
${permission_block}
${provider_block}
  "model": "${default_prefix}/${default_model}",
  "small_model": "${small_prefix}/${small_model}"
}
JSONEOF

    local _model_count=0
    $_has_openai_creds && _model_count=$(echo "$DISCOVERED_MODELS" | wc -l)
    local _zen_status="disabled"
    $_has_opencode_key && _zen_status="enabled"
    local _fallback_status="none"
    [ -n "$_raw_fallback_model" ] && _fallback_status="${fallback_prefix}/${fallback_model}"
    echo "== Wrote opencode.jsonc with ${_model_count} models, default: ${default_prefix}/${default_model}, small: ${small_prefix}/${small_model}, fallback: ${_fallback_status} (security: ${security_mode}, opencode_zen: ${_zen_status})."

    chown -R "${OPENCODE_USER}:${OPENCODE_USER}" "$(dirname "$OPENCODE_CONFIG")"

    # --- Fix #28: Copy opencode config to root's config dir ---
    # When Hermes agent uses terminal() -> docker exec, it runs as root.
    # Without this, root has an empty config and custom providers are invisible.
    local root_opencode_config_dir="/root/.config/opencode"
    mkdir -p "$root_opencode_config_dir"
    if [ "$(readlink -f "$OPENCODE_CONFIG")" != "$(readlink -f "${root_opencode_config_dir}/opencode.jsonc")" ]; then
        cp "$OPENCODE_CONFIG" "${root_opencode_config_dir}/opencode.jsonc"
    fi
    echo "== Copied opencode.jsonc to ${root_opencode_config_dir}/opencode.jsonc (root config)."

    # --- Seed auth.json as fallback credential store ---
    # {env:VAR} in opencode.jsonc requires the env var at runtime; auth.json is
    # OpenCode's native credential store, seeded here as a fallback for both
    # the opencode (Zen) and litellm (proxy) providers.
    if $_has_opencode_key || $_has_openai_creds; then
        local user_auth_dir="${OPENCODE_USER_HOME}/.local/share/opencode"
        local user_auth="${user_auth_dir}/auth.json"
        local root_auth="/root/.local/share/opencode/auth.json"
        mkdir -p "$user_auth_dir"
        local _openai_key="${OPENAI_API_KEY:-}"
        python3 -c "
import json, sys
auth = {}
oc_key = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else ''
ai_key = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] else ''
if oc_key:
    auth['opencode'] = {'apiKey': oc_key}
if ai_key:
    auth['litellm'] = {'apiKey': ai_key}
with open(sys.argv[1], 'w') as f:
    json.dump(auth, f)
" "$user_auth" "$OPENCODE_API_KEY" "$_openai_key"
        chmod 600 "$user_auth"
        chown "${OPENCODE_USER}:${OPENCODE_USER}" "$user_auth"
        mkdir -p "$(dirname "$root_auth")"
        if [ "$(readlink -f "$user_auth")" != "$(readlink -f "$root_auth")" ]; then
            cp "$user_auth" "$root_auth"
        fi
        echo "== Seeded auth.json (opencode + litellm provider fallbacks)."
    fi

    # --- Seed opencode-fallback.jsonc when OPENCODE_FALLBACK_MODEL is set ---
    # The opencode-runtime-fallback plugin reads a global fallback chain from
    # ~/.config/opencode/opencode-fallback.jsonc (mirrors the auth.json seeding
    # pattern above, including the root copy). Only written when non-empty.
    if [ -n "$_raw_fallback_model" ]; then
        local _fallback_dir
        _fallback_dir="$(dirname "$OPENCODE_CONFIG")"
        local user_fallback="${_fallback_dir}/opencode-fallback.jsonc"
        local root_fallback="/root/.config/opencode/opencode-fallback.jsonc"
        cat > "$user_fallback" << FBEOF
{
  "fallback_models": ["${fallback_prefix}/${fallback_model}"]
}
FBEOF
        chown "${OPENCODE_USER}:${OPENCODE_USER}" "$user_fallback"
        mkdir -p "$(dirname "$root_fallback")"
        if [ "$(readlink -f "$user_fallback")" != "$(readlink -f "$root_fallback")" ]; then
            cp "$user_fallback" "$root_fallback"
        fi
        echo "== Seeded opencode-fallback.jsonc (fallback: ${fallback_prefix}/${fallback_model})."
    fi

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
