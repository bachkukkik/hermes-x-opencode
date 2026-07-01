# lib/validate-opencode.sh - OpenCode Zen API key validation - sourced by entrypoint.sh

# --- Fix #30: Validate OpenCode Zen API key if set ---
# When OPENCODE_ZEN_API_KEY is set but invalid, opencode/ models return 401.
# This check provides a helpful startup message instead of silent failures.
validate_opencode_zen_key() {
    local key="${OPENCODE_ZEN_API_KEY:-}"
    if [ -z "$key" ]; then
        echo "== OPENCODE_ZEN_API_KEY not set. opencode/ free models will use public fallback (may be limited)."
        return 0
    fi

    # Quick validation: try the Zen API models endpoint with the provided key
    local response
    response=$(curl -sf --max-time 10 \
        -H "Authorization: Bearer ${key}" \
        "https://opencode.ai/zen/v1/models" 2>/dev/null || echo "")

    if [ -z "$response" ]; then
        echo "!! WARNING: OPENCODE_ZEN_API_KEY is set but the Zen API returned an error."
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

    echo "== OPENCODE_ZEN_API_KEY validated. Zen API returned ${model_count} models."
    return 0
}
