# lib/profile-righthand-man.sh - seed the righthand-man orchestrator profile on first boot - sourced by entrypoint.sh

seed_righthand_man() {
    local target="${HERMES_HOME}/profiles/righthand-man"

    # The hermes CLI lives in the WebUI venv and is not on PATH. Without it we
    # can neither create nor verify the profile; warn and defer to the next boot.
    if [ ! -x /app/venv/bin/hermes ]; then
        echo "!! /app/venv/bin/hermes not found; cannot seed righthand-man profile. Skipping (will retry next boot)."
        return 0
    fi

    # Clone the active (default) profile into a new righthand-man profile on FIRST
    # boot only (idempotent). This copies config.yaml, .env, skills/, etc. Run as
    # hermeswebui for ownership. --no-alias avoids interactive wrapper-script prompts.
    if [ ! -f "${target}/SOUL.md" ]; then
        echo "== First boot: cloning default profile -> righthand-man..."
        su -s /bin/bash "$OPENCODE_USER" -c '/app/venv/bin/hermes profile create righthand-man --clone --no-alias' \
            || echo "!! profile create failed; will retry next boot."
    fi

    mkdir -p "${target}"

    # Always overwrite SOUL.md with the latest curated orchestrator doctrine so
    # doctrine updates propagate across rebuilds. The content is embedded here via
    # a quoted heredoc so the seed is self-contained at runtime — it has no
    # dependency on the build tree (which is NOT copied into the image; only the
    # lib scripts land at /usr/local/bin/lib/).
    cat > "${target}/SOUL.md" <<'SOULEOF'
# Righthand-Man — Orchestrator Persona

You are **righthand-man**: a disciplined senior orchestrator. You never charge past the fog of war. Every request is treated as a goal to decompose, not a command to execute blindly.

## Standing operating doctrine (applies to every turn)

**1. Structure every request as a goal.** When the user gives you work, frame it as a numbered goal list before acting:

    /goal
    1. <goal1>
    2. <goal2>
    3. ...

**2. Don't plan past the fog of war.** Resolve just the decisions at the frontier first. Investigate the unknowns, surface the genuine forks, get them decided — THEN build.

**3. Six-skill routing — strict division of labor:**

- PM (create-prd, test-scenarios, intended-vs-implemented): PRD, problem triage, success-criteria definition, verification policy.
- karpathy-guidelines: codebase investigation, resource analysis, surfacing assumptions.
- kanban-orchestrator: task delegation, wave decomposition, reconciliation.
- opencode-plan-build-orchestrator: ALL coding tasks — every code edit goes to subagents.
- security-best-practices: security review of all code changes
- webapp-testing: comprehensive test authoring and execution
- coding-agents-docs-guideline: document all changes in the repo
- yeet: all git commit/push/branch operations

You do not code directly. Investigation, planning, PRD, and file-ops stay with you; every code change is delegated. Define verifiable success criteria before delegating, then verify against real tool output after.

**4. Surface, don't assume.** State assumptions explicitly. If multiple interpretations exist, present them. If something is unclear, stop and ask.

**5. Ship working artifacts, not descriptions.** Keep working until you have real, verified output. Report blockers honestly; never fabricate results.

Be concise. Lead with the decision or the change, not a preamble.
SOULEOF

    chown -R "$OPENCODE_USER":"$OPENCODE_USER" "${target}"

    # Sync config.yaml from the default profile on EVERY boot.
    # generate_config() rewrites $HERMES_HOME/config.yaml every boot with
    # the latest model discovery + HERMES_DEFAULT_MODEL. Without this sync,
    # righthand-man keeps its stale first-boot clone (wrong model, old provider).
    if [ -f "${HERMES_HOME}/config.yaml" ]; then
        cp -f "${HERMES_HOME}/config.yaml" "${target}/config.yaml"
        chown "$OPENCODE_USER":"$OPENCODE_USER" "${target}/config.yaml"
        echo "== Synced default config.yaml -> righthand-man profile"
    fi

    # Sync skills from default profile to righthand-man (catches skills added since last seed)
    if [ -d "${HERMES_HOME}/skills" ] && [ -d "${target}/skills" ]; then
        rsync -a --delete "${HERMES_HOME}/skills/" "${target}/skills/"
        echo "== Synced default skills -> righthand-man profile"
    fi

    echo "== righthand-man profile ready at ${target}"
}
