#!/usr/bin/env bash
# ── Volume seeding ──────────────────────────────────────────────────────────

seed_volumes() {
    log "--- seed_volumes ---"

    if [ "${SKIP_SKILL_INSTALL}" = "1" ]; then
        log "SKIP_SKILL_INSTALL=1, skipping skill seeding"
        return 0
    fi

    # OpenCode skills (from staging)
    mkdir -p "$OPENCODE_SKILLS_DIR"
    if [ -d "/opt/opencode-skills-staging" ]; then
        cp -rn /opt/opencode-skills-staging/. "$OPENCODE_SKILLS_DIR/" 2>/dev/null || true
        log "Seeded opencode skills"
    fi

    # Hermes skills (from staging)
    mkdir -p "$HERMES_SKILLS_DIR"
    if [ -d "/opt/hermes-skills-staging" ]; then
        cp -rn /opt/hermes-skills-staging/. "$HERMES_SKILLS_DIR/" 2>/dev/null || true
        log "Seeded hermes skills"
    fi

    # Root symlinks (for processes running as root)
    mkdir -p /root/.config/opencode /root/.hermes
    ln -sf "$OPENCODE_CONFIG" /root/.config/opencode/opencode.jsonc 2>/dev/null || true
    ln -sf "$OPENCODE_SKILLS_DIR" /root/.config/opencode/skills 2>/dev/null || true
    ln -sf "$CONFIG" /root/.hermes/config.yaml 2>/dev/null || true
    ln -sf "$HERMES_SKILLS_DIR" /root/.hermes/skills 2>/dev/null || true

    # Ensure /workspace and /app/.od are owned by hermeswebui (Docker creates bind mounts as root:root)
    chown -R "${OPENCODE_USER}:${OPENCODE_USER}" /workspace 2>/dev/null || true
    chown -R "${OPENCODE_USER}:${OPENCODE_USER}" /app/.od 2>/dev/null || true

    # Ensure hermeswebui owns its home dir (bind mount may be root-owned on first boot)
    chown -R "${OPENCODE_USER}:${OPENCODE_USER}" "$HERMES_HOME" 2>/dev/null || true

    log "Volume seeding complete"
}
