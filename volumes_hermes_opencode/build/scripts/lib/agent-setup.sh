# lib/agent-setup.sh - hermes-agent staging/copy logic - sourced by entrypoint.sh

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
