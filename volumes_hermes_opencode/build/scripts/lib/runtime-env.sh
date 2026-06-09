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

# Replace host.docker.internal with localhost when running outside Docker.
normalize_base_url_for_local() {
    local url="$1"
    if [ "${RUNTIME_ENV_MODE}" = "local" ] && [[ "$url" == *host.docker.internal* ]]; then
        url="${url//host.docker.internal/localhost}"
        echo "== Substituted host.docker.internal -> localhost in OPENAI_BASE_URL (local runtime mode)" >&2
    fi
    echo "${url}"
}
