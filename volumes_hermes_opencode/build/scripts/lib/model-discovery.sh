# lib/model-discovery.sh - model list discovery from OpenAI-compatible API - sourced by entrypoint.sh

discover_models() {
    local base_url="${OPENAI_BASE_URL:-}"
    local api_key="${OPENAI_API_KEY:-}"
    local default_model="${HERMES_DEFAULT_MODEL:-${OPENAI_DEFAULT_MODEL:-openai/gpt-4o}}"
    DISCOVERED_MODELS=""

    if [ -z "$base_url" ] || [ -z "$api_key" ]; then
        echo "!! OPENAI_BASE_URL or OPENAI_API_KEY not set, using default model only."
        DISCOVERED_MODELS="$default_model"
        return
    fi

    echo "== Discovering models from $base_url ..."
    local response
    response=$(curl -sf --max-time 15 \
        -H "Authorization: Bearer ${api_key}" \
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
