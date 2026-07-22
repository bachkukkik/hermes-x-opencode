# lib/config-opencode.sh - OpenCode config generation - sourced by entrypoint.sh

# normalize_model_id — canonical provider/model form. Single source of truth.
# Recognized prefixes: opencode/ (Zen), litellm/ (proxy).
# Explicit prefixes pass through unchanged. Bare ids get litellm/ when
# OPENAI_BASE_URL + OPENAI_API_KEY are set, else opencode/ (Zen).
# Adding a new provider: add its prefix to PROVIDER_PREFIXES.
export PROVIDER_PREFIXES="opencode litellm"

normalize_model_id() {
    local model="$1"
    local pfx
    for pfx in $PROVIDER_PREFIXES; do
        case "$model" in
            ${pfx}/*) echo "$model"; return ;;
        esac
    done
    if [ -n "${OPENAI_BASE_URL:-}" ] && [ -n "${OPENAI_API_KEY:-}" ]; then
        echo "litellm/${model}"
    else
        echo "opencode/${model}"
    fi
}

generate_opencode_config() {
    local _has_opencode_key=false
    local _has_openai_creds=false
    [ -n "${OPENCODE_ZEN_API_KEY:-}" ] && _has_opencode_key=true
    [ -n "${OPENAI_BASE_URL:-}" ] && [ -n "${OPENAI_API_KEY:-}" ] && _has_openai_creds=true

    if ! $_has_opencode_key && ! $_has_openai_creds; then
        echo "!! Skipping opencode config: missing OPENCODE_ZEN_API_KEY or (OPENAI_BASE_URL + OPENAI_API_KEY)."
        return
    fi

    mkdir -p "$(dirname "$OPENCODE_CONFIG")"

    local _raw_default_model="${OPENCODE_DEFAULT_MODEL:-${OPENAI_DEFAULT_MODEL:-deepseek-v4-flash-free}}"
    local _raw_small_model="${OPENCODE_SMALL_MODEL:-${OPENAI_SMALL_MODEL:-$_raw_default_model}}"

    local default_model
    default_model="$(normalize_model_id "$_raw_default_model")"
    local small_model
    small_model="$(normalize_model_id "$_raw_small_model")"

    local _raw_fallback_model="${OPENCODE_FALLBACK_MODEL:-}"
    # OPENCODE_FALLBACK_MODEL accepts a comma-separated ORDERED list. Each entry
    # is independently prefix-resolved (opencode/..., litellm/..., or bare ->
    # litellm when OpenAI creds are present, else opencode Zen), preserving the
    # declared order. The opencode-runtime-fallback plugin tries them in array
    # order after the primary fails. Single value = 1-element list (backward
    # compatible). Empty/whitespace entries are skipped.
    local _fallback_chain=""   # newline-joined resolved "prefix/model" ids
    local _fallback_count=0
    if [ -n "$_raw_fallback_model" ]; then
        local _fb_entry _fb_normalized
        while IFS= read -r _fb_entry; do
            # trim leading/trailing whitespace
            _fb_entry="${_fb_entry#"${_fb_entry%%[![:space:]]*}"}"
            _fb_entry="${_fb_entry%"${_fb_entry##*[![:space:]]}"}"
            [ -z "$_fb_entry" ] && continue
            _fb_normalized="$(normalize_model_id "$_fb_entry")"
            if [ -n "$_fallback_chain" ]; then
                _fallback_chain="${_fallback_chain}"$'\n'"${_fb_normalized}"
            else
                _fallback_chain="${_fb_normalized}"
            fi
            _fallback_count=$((_fallback_count + 1))
        done < <(printf '%s\n' "$_raw_fallback_model" | tr ',' '\n')
    fi

    local base_url="${OPENAI_BASE_URL%/}"

    local models_json=""
    if $_has_openai_creds; then
        models_json=$(echo "$DISCOVERED_MODELS" | python3 -c "
import sys, re, json, os

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
    if re.search(r'gpt-4[\\.-]', name) or name.endswith('gpt-4'):
        return 8192, 4096
    if 'gpt-3.5' in name:
        return 16384, 4096
    if 'gpt-5' in name:
        return 128000, 16384
    if re.search(r'/o[134]', name) or re.search(r'-o[134]', name):
        return 200000, 100000
    if re.search(r'claude-[34]', name):
        if re.search(r'claude-3\\.7|claude-[45]', name):
            return 200000, 16384
        return 200000, 4096
    if 'llama_cpp' in model_id:
        # Agents A1 models have 256K native context (qwen35moe arch)
        if 'agents-a1-mtp-apex' in name:
            return 262144, 32768
        if 'agents-a1-q4' in name:
            return 262144, 32768
        # qwen3.6-27b (qwen35moe arch) has 256K native context
        if 'qwen3.6' in name:
            return 262144, 32768
        return 200000, 32768
    if 'deepseek-v4' in name:
        # DeepSeek V4 family (v4-pro / v4-flash, incl. opencode-go/*) is 1M
        # context — matches resolve_ctx_len() in config-hermes.sh. Without this
        # it falls through to the generic 128K deepseek branch below and OpenCode
        # caps the window at 128K.
        return 1000000, 65536
    if 'kimi' in name:
        return 262144, 8192
    if 'minimax-m3' in name:
        return 1000000, 8192
    if 'mimo-v2.5' in name:
        return 1048576, 8192
    if 'nemotron' in name:
        return 131072, 8192
    if 'qwen3.6' in name:
        return 1048576, 8192
    if 'deepseek' in name:
        return 128000, 8192
    if 'glm-5.2' in name:
        return 1048576, 131072
    if 'glm' in name:
        return 128000, 8192
    if 'gemini' in name:
        return 1048576, 65536
    return 128000, 8192

entries = []
for line in sys.stdin:
    mid = line.strip()
    if not mid:
        continue
    _PREFIXES = os.environ.get('PROVIDER_PREFIXES', 'opencode litellm').split()
    key = mid
    for _pfx in _PREFIXES:
        _pfx_slash = _pfx + '/'
        if key.startswith(_pfx_slash):
            key = key[len(_pfx_slash):]
            break
    ctx, out = get_limits(mid)
    entries.append(f'        \\"{key}\\": {{\"limit\": {{\"context\": {ctx}, \"output\": {out}}}}}')

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
        "apiKey": "{env:OPENCODE_ZEN_API_KEY}"
      }
    }
OCEOF
)
    fi

    # Inline the resolved OPENAI_API_KEY so opencode.jsonc is self-contained
    # in any shell/dir; fall back to the {env:OPENAI_API_KEY} placeholder when
    # unset at generation time.
    # Two-step: avoid nested-brace bash expansion bug. Bash closes ${VAR:-WORD}
    # at the FIRST '}' inside WORD, so writing "{env:...}" directly inside the
    # default makes a SET key expand to "<key>}" — a stray trailing brace that
    # corrupts the inlined key and LiteLLM rejects (issue #53).
    local _openai_key="${OPENAI_API_KEY:-}"
    [ -z "$_openai_key" ] && _openai_key='{env:OPENAI_API_KEY}'
    local _ll_entry=""
    if $_has_openai_creds; then
        _ll_entry=$(cat << PROVEOF
    "litellm": {
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "apiKey": "${_openai_key}",
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
    if [ -n "$_entries" ]; then
        provider_block=$(cat << PEMEOF
  "provider": {
${_entries}
  },
PEMEOF
)
    else
        provider_block='  "provider": {},'
    fi

    local _plugins
    _plugins='    "@tarquinen/opencode-dcp@latest",
    "@franlol/opencode-md-table-formatter@latest",
    "cc-safety-net"'
    if [ "$_fallback_count" -gt 0 ]; then
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
  "model": "${default_model}",
  "small_model": "${small_model}"
}
JSONEOF

    local _model_count=0
    $_has_openai_creds && _model_count=$(echo "$DISCOVERED_MODELS" | wc -l)
    local _zen_status="disabled"
    $_has_opencode_key && _zen_status="enabled"
    local _fallback_status="none"
    if [ "$_fallback_count" -gt 0 ]; then
        _fallback_status=$(printf '%s' "$_fallback_chain" | tr '\n' ',' | sed 's/,$//')
    fi
    echo "== Wrote opencode.jsonc with ${_model_count} models, default: ${default_model}, small: ${small_model}, fallback: ${_fallback_status} (security: ${security_mode}, opencode_zen: ${_zen_status})."

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
    #
    # CA-30-A: The guard below intentionally uses `$_has_opencode_key || $_has_openai_creds`
    # (NOT `$_has_opencode_key` alone). When OPENCODE_ZEN_API_KEY is unset (the
    # .env.example default) but OPENAI_API_KEY + OPENAI_BASE_URL ARE set, the
    # litellm proxy is the available backend. The Python block writes
    # auth['litellm'] = {'apiKey': ai_key} for the non-empty AI key, so opencode
    # CLI resolves >=1 credential (the litellm proxy) even without a built-in
    # opencode Zen key. This is the intended resolution for the
    # 'OpenCode unavailable (0 credentials)' report from the righthand-man
    # orchestrator. Do NOT narrow this guard to opencode-key-only.
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
" "$user_auth" "$OPENCODE_ZEN_API_KEY" "$_openai_key"
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
    if [ "$_fallback_count" -gt 0 ]; then
        local _fallback_dir
        _fallback_dir="$(dirname "$OPENCODE_CONFIG")"
        local user_fallback="${_fallback_dir}/opencode-fallback.jsonc"
        local root_fallback="/root/.config/opencode/opencode-fallback.jsonc"
        local _fb_json_arr
        _fb_json_arr=$(printf '%s' "$_fallback_chain" | python3 -c 'import sys,json; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))')
        printf '{\n  "fallback_models": %s\n}\n' "$_fb_json_arr" > "$user_fallback"
        chown -R "${OPENCODE_USER}:${OPENCODE_USER}" "$user_fallback"
        mkdir -p "$(dirname "$root_fallback")"
        if [ "$(readlink -f "$user_fallback")" != "$(readlink -f "$root_fallback")" ]; then
            cp "$user_fallback" "$root_fallback"
        fi
        echo "== Seeded opencode-fallback.jsonc (chain: $(printf '%s' "$_fallback_chain" | tr '\n' ',' | sed 's/,$//'))."
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

# generate_dcp_staging — write a managed dcp.jsonc pinning the DCP compress
# thresholds to a PERCENTAGE of each model's own context window.
#
# WHY: @tarquinen/opencode-dcp defaults compress.maxContextLimit to a hard
# 100_000 tokens irrespective of the active model, so a 1M-context model gets
# compression-nudged at ~10% fill. DCP's schema accepts "X%" strings for
# max/minContextLimit which it resolves against the ACTIVE model's real window
# (see dcp.schema.json) — so one percentage setting adapts to every model,
# matching Hermes' HERMES_COMPRESSION_THRESHOLD behavior.
#
# Merge policy (surgical, lossless): load the existing dcp.jsonc, set ONLY
# compress.maxContextLimit / compress.minContextLimit, preserve every other key.
generate_dcp_staging() {
    mkdir -p "$(dirname "$OPENCODE_DCP_CONFIG")"
    local threshold="${OPENCODE_COMPRESSION_THRESHOLD:-0.76}"

    python3 - "$OPENCODE_DCP_CONFIG" "$threshold" << 'PYEOF'
import sys, json, re

live_path, threshold_raw = sys.argv[1], sys.argv[2]

# --- Tolerant JSONC parser (string-aware // and /* */ stripping) -----------
def _strip_jsonc_comments(text):
    result = []; i = 0; in_string = False; escape = False
    while i < len(text):
        ch = text[i]
        if escape:
            result.append(ch); escape = False; i += 1; continue
        if in_string:
            result.append(ch)
            if ch == '\\': escape = True
            elif ch == '"': in_string = False
            i += 1; continue
        if ch == '"':
            in_string = True; result.append(ch); i += 1; continue
        if ch == '/' and i + 1 < len(text) and text[i + 1] == '/':
            while i < len(text) and text[i] != '\n': i += 1
            continue
        if ch == '/' and i + 1 < len(text) and text[i + 1] == '*':
            i += 2
            while i + 1 < len(text) and not (text[i] == '*' and text[i + 1] == '/'): i += 1
            i += 2; continue
        result.append(ch); i += 1
    return ''.join(result)

def load_jsonc(path):
    with open(path) as f:
        text = f.read()
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass
    stripped = _strip_jsonc_comments(text)
    stripped = re.sub(r',\s*([}\]])', r'\1', stripped)
    return json.loads(stripped)

existing = {}
try:
    existing = load_jsonc(live_path)
except FileNotFoundError:
    existing = {}
except Exception as e:
    sys.stderr.write("!! Could not parse live dcp.jsonc (%s); starting fresh.\n" % e)
    existing = {}
if not isinstance(existing, dict):
    existing = {}

# --- Clamp threshold to (0, 1] and derive percentage strings ----------------
try:
    t = float(threshold_raw)
except (TypeError, ValueError):
    t = 0.76
if t <= 0 or t > 1:
    t = 0.76
max_pct = round(t * 100)
# minContextLimit is DCP's soft lower bound for gentle reminder nudges; keep
# DCP's native 2:1 band (default 50k:100k) anchored at the configured ceiling.
min_pct = max(1, round(max_pct / 2))
max_str = "%d%%" % max_pct
min_str = "%d%%" % min_pct

existing.setdefault("$schema",
    "https://raw.githubusercontent.com/Opencode-DCP/"
    "opencode-dynamic-context-pruning/master/dcp.schema.json")
compress = existing.setdefault("compress", {})
if not isinstance(compress, dict):
    compress = {}
    existing["compress"] = compress
compress["maxContextLimit"] = max_str
compress["minContextLimit"] = min_str

with open(live_path, "w") as f:
    json.dump(existing, f, indent=2)
    f.write("\n")

# Human-readable summary goes to STDERR so callers that capture the managed
# dcp.jsonc from stdout (e.g. the e2e tests) get clean JSON, not log noise.
print("DCP merge summary", file=sys.stderr)
print("=" * 40, file=sys.stderr)
print("compress.maxContextLimit -> %s (of each model's context window)" % max_str, file=sys.stderr)
print("compress.minContextLimit -> %s" % min_str, file=sys.stderr)
print("threshold source         -> OPENCODE_COMPRESSION_THRESHOLD=%s" % t, file=sys.stderr)
print("other dcp.jsonc keys     -> preserved", file=sys.stderr)
PYEOF

    chown -R "${OPENCODE_USER}:${OPENCODE_USER}" "$(dirname "$OPENCODE_DCP_CONFIG")"
    # NB: max_str/min_str live inside the Python heredoc above, not in shell
    # scope; the "DCP merge summary" it prints already reports the resolved
    # percentages. Reference only shell-scoped vars here (entrypoint runs under
    # `set -u`, so an unbound var would abort startup before the healthcheck).
    printf '== Wrote managed dcp.jsonc (compression threshold: %s of each model context window).\n' "$threshold" >&2
}
