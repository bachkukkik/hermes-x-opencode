# lib/agent-setup.sh - hermes-agent staging/copy logic - sourced by entrypoint.sh

ensure_agent() {
    log "--- ensure_agent ---"
    if [ ! -d "$STAGING_DIR" ]; then
        warn "No staged agent found at $STAGING_DIR"
        return
    fi
    log "Syncing staged agent to $AGENT_DIR..."
    mkdir -p "$(dirname "$AGENT_DIR")"
    rsync -a --delete "$STAGING_DIR/" "$AGENT_DIR/"
    log "Agent synced."
}
