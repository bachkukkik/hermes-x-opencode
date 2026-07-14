#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# config-claude-code.sh — Resolve Claude Code (`claude`) authentication
#
# Claude Code authenticates from the environment / an on-disk credentials file.
# This deployment supports THREE auth paths, with OAuth as primary:
#   1. CLAUDE_CODE_OAUTH_TOKEN env — long-lived OAuth token minted once with
#      `claude setup-token` on a machine with a browser.
#   2. Interactive `claude /login` in a code-server terminal — the headless
#      paste flow (press `c`, open the URL on your laptop, paste the code back).
#      Credentials land in $CLAUDE_CONFIG_DIR/.credentials.json.
#   3. ANTHROPIC_API_KEY env (+ optional ANTHROPIC_BASE_URL) — fallback.
#
# Persistence: CLAUDE_CONFIG_DIR is baked to a path under the ~/.hermes bind
# mount (Dockerfile ENV), so both settings and interactive-login credentials
# survive container restarts. We create + chown it here so the hermeswebui user
# can write it at runtime.
#
# OAuth-primary policy: Claude Code's native credential precedence puts
# ANTHROPIC_API_KEY ABOVE both the OAuth token AND interactive-login creds. So
# when OAuth is available (token env OR an on-disk login), we drop
# ANTHROPIC_API_KEY from the environment so OAuth wins. This runs in the
# entrypoint (PID 1) shell before any service starts, so every child
# (code-server terminals, the agent, gateway) inherits the resolved env.
# (ANTHROPIC_API_KEY is used only by `claude`; the LLM provider path uses
# OPENAI_API_KEY / OPENCODE_ZEN_API_KEY, so unsetting it is safe.)
#
# Sourced by entrypoint.sh; provides: configure_claude_code_auth()
# ─────────────────────────────────────────────────────────────────────────────

configure_claude_code_auth() {
    local config_dir="${CLAUDE_CONFIG_DIR:-${OPENCODE_USER_HOME}/.hermes/claude}"
    export CLAUDE_CONFIG_DIR="$config_dir"

    # Persist settings + interactive-login credentials on the bind mount.
    mkdir -p "$config_dir"
    chown -R "${OPENCODE_USER}:${OPENCODE_USER}" "$config_dir" 2>/dev/null || \
        warn "[claude-code] could not chown ${config_dir}"

    if [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
        if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
            unset ANTHROPIC_API_KEY
            log "[claude-code] OAuth token present — using OAuth (ANTHROPIC_API_KEY ignored per OAuth-primary policy)"
        else
            log "[claude-code] Authenticating via OAuth token (CLAUDE_CODE_OAUTH_TOKEN)"
        fi
    elif [ -f "${config_dir}/.credentials.json" ]; then
        if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
            unset ANTHROPIC_API_KEY
            log "[claude-code] On-disk OAuth login found — using it (ANTHROPIC_API_KEY ignored per OAuth-primary policy)"
        else
            log "[claude-code] Using persisted OAuth login (${config_dir}/.credentials.json)"
        fi
    elif [ -n "${ANTHROPIC_API_KEY:-}" ]; then
        log "[claude-code] Authenticating via ANTHROPIC_API_KEY"
    else
        log "[claude-code] No credentials — run 'claude' in a code-server terminal and '/login' (paste flow), or set CLAUDE_CODE_OAUTH_TOKEN / ANTHROPIC_API_KEY"
    fi

    # Model selection is consumed directly by `claude` from the environment
    # (ANTHROPIC_MODEL = main thread, CLAUDE_CODE_SUBAGENT_MODEL = subagents /
    # Task delegation). Log for operator visibility; no rewriting needed.
    if [ -n "${ANTHROPIC_MODEL:-}" ]; then
        log "[claude-code] Main model: ${ANTHROPIC_MODEL}"
    fi
    if [ -n "${CLAUDE_CODE_SUBAGENT_MODEL:-}" ]; then
        log "[claude-code] Subagent/delegation model: ${CLAUDE_CODE_SUBAGENT_MODEL}"
    fi
}
