# lib/config-opencode.sh - OpenCode config generation - sourced by entrypoint.sh

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
