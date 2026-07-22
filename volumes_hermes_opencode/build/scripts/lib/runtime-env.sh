# lib/runtime-env.sh - runtime environment detection helpers - sourced by entrypoint.sh

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

# Normalize OPENAI_BASE_URL for downstream consumers:
#   1. Strip trailing slashes (always). Consumers append paths
#      (".../chat/completions"); a trailing "/" yields "//chat/completions",
#      which LiteLLM and other proxies 404 on.
#   2. Replace host.docker.internal with localhost when running outside Docker.
normalize_base_url() {
    local url="$1"
    # Strip every trailing slash ("https://host/" and "https://host//").
    while [ "${url%/}" != "$url" ]; do
        url="${url%/}"
    done
    if [ "${RUNTIME_ENV_MODE}" = "local" ] && [[ "$url" == *host.docker.internal* ]]; then
        url="${url//host.docker.internal/localhost}"
        log "Substituted host.docker.internal -> localhost in OPENAI_BASE_URL (local runtime mode)"
    fi
    echo "${url}"
}

# Backwards-compatible alias (prior name referenced only the local rewrite).
normalize_base_url_for_local() { normalize_base_url "$@"; }
