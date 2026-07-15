FROM ghcr.io/nesquena/hermes-webui:latest

ARG HERMES_AGENT_VERSION=main

RUN apt-get update -y --no-install-recommends \
    && apt-get install -y --no-install-recommends \
       build-essential git ripgrep tree ffmpeg procps curl netcat-openbsd bats \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Browser human-in-the-loop: Xvfb + VNC + Chromium (always installed, enabled at runtime via BROWSER_HUMAN_LOOP_ENABLED)
RUN apt-get update -y --no-install-recommends \
    && apt-get install -y --no-install-recommends \
       chromium xvfb x11vnc openbox websockify novnc \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && node --version \
    && npm --version

RUN curl -fsSL https://opencode.ai/install | bash \
    && if [ -f /root/.opencode/bin/opencode ]; then \
         cp /root/.opencode/bin/opencode /usr/local/bin/opencode; \
       fi \
    && opencode --version

RUN curl -LsSf https://astral.sh/uv/install.sh | sh \
    && cp /root/.local/bin/uv /usr/local/bin/uv \
    && cp /root/.local/bin/uvx /usr/local/bin/uvx 2>/dev/null || true \
    && uv --version

# ── Claude Code CLI (anthropic `claude`) ─────────────────────────────────────
# Installed globally so `claude` is on PATH for the agent and for `docker exec`
# terminals. Auth resolves at runtime (OAuth primary, API key fallback) — see
# lib/config-claude-code.sh. Three auth paths are supported:
#   1. CLAUDE_CODE_OAUTH_TOKEN env (minted once via `claude setup-token`)
#   2. Interactive `claude /login` in a `docker exec` terminal (headless paste
#      flow: press `c`, open the URL on your laptop, paste the code back)
#   3. ANTHROPIC_API_KEY env (fallback)
# CLAUDE_CONFIG_DIR points at the persistent ~/.hermes bind mount so interactive
# logins (.credentials.json) and settings survive container restarts. Recorded
# in /etc/environment too, so `docker exec` sessions as hermeswebui resolve the
# same config dir.
#
# IS_SANDBOX=1: Claude Code refuses `--dangerously-skip-permissions` when the
# process has root/sudo privileges UNLESS it believes it is in a sandbox. The
# entrypoint runs as root (PID 1) and `docker exec` sessions are root by
# default, so any caller passing that flag fails with exit 1 ("cannot be used
# with root/sudo privileges"). This container IS an isolated sandbox, so we opt
# in — baked as ENV (all children inherit it) and written to /etc/environment so
# root exec shells resolve it too (mirrors CLAUDE_CONFIG_DIR).
ENV CLAUDE_CONFIG_DIR=/home/hermeswebui/.hermes/claude
ENV IS_SANDBOX=1
RUN npm install -g --legacy-peer-deps @anthropic-ai/claude-code \
    && claude --version \
    && printf 'CLAUDE_CONFIG_DIR=%s\n' "${CLAUDE_CONFIG_DIR}" >> /etc/environment \
    && printf 'IS_SANDBOX=%s\n' "${IS_SANDBOX}" >> /etc/environment

# ── Playwright CLI + chromium (built-in browser automation) ──────────────────
# @playwright/cli (github.com/microsoft/playwright-cli) — the token-efficient,
# agent-oriented CLI (binary `playwright-cli`, cmds: open/screenshot/pdf), NOT
# the classic `playwright` test runner. Installed globally so `playwright-cli` is
# on PATH for the agent. The package pins a specific alpha `playwright`/-core, so
# browsers are installed via ITS bundled `playwright` binary — using a separately
# installed stable `playwright` would fetch a mismatched chromium revision.
# Browsers land in a SHARED, world-readable path (not root's ~/.cache) so the
# runtime user (hermeswebui) resolves them via PLAYWRIGHT_BROWSERS_PATH. The
# base image already installs the debian `chromium` package with its full
# shared-lib deps, which satisfy the downloaded chromium's runtime requirements,
# so `--with-deps` (apt) is unnecessary. PLAYWRIGHT_BROWSERS_PATH is recorded in
# /etc/environment too, so `docker exec` sessions as hermeswebui resolve the
# browsers; the entrypoint additionally forwards it across the `su` boundary for
# the gateway/opencode (su resets the parent env, so the ENV directive alone is
# not enough for the agent's runtime).
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright
RUN npm install -g --legacy-peer-deps @playwright/cli \
    && mkdir -p "${PLAYWRIGHT_BROWSERS_PATH}" \
    && PW_BIN="$(npm root -g)/.bin/playwright" \
    && { [ -x "$PW_BIN" ] || PW_BIN="$(npm root -g)/@playwright/cli/node_modules/.bin/playwright"; } \
    && "$PW_BIN" install chromium \
    && chmod -R a+rX "${PLAYWRIGHT_BROWSERS_PATH}" \
    && playwright-cli --version \
    && printf 'PLAYWRIGHT_BROWSERS_PATH=%s\n' "${PLAYWRIGHT_BROWSERS_PATH}" >> /etc/environment

# Clone hermes-agent to staging path for:
# 1) Skills source extraction during install-skills.sh
# 2) Dependency installation by /hermeswebui_init.bash (uv pip install from staged source)
# 3) Readiness marker for ensure_agent() at runtime
# NOTE: This is NOT the active runtime — the WebUI uses /app/venv/ (Installation A).
# The staged source feeds deps into /app/venv/ via pip install.
RUN git clone --depth 1 --branch ${HERMES_AGENT_VERSION} \
    https://github.com/NousResearch/hermes-agent.git \
    /opt/hermes-agent-staging

# Patch CustomProfile User-Agent header. This patch propagates to the active venv through:
# staging → ensure_agent() → ~/.hermes/hermes-agent/ → /hermeswebui_init.bash rsync → uv pip install → /app/venv/
RUN sed -i 's/base_url="",/base_url="",\n    default_headers={"User-Agent": "hermes-agent\/1.0"},/' \
    /opt/hermes-agent-staging/plugins/model-providers/custom/__init__.py

# Build the Hermes web dashboard dist (npm) and stage it at a stable image path.
# Do NOT place it under /app/venv here — /app/venv is created at RUNTIME by the
# WebUI init (uv venv), and pre-creating any part of it breaks that init. The
# runtime dashboard service copies this staged dist into the live venv on start.
# vite.config.ts outDir is "../hermes_cli/web_dist" relative to web/.
RUN cd /opt/hermes-agent-staging \
    && npm install --workspace web \
    && npm run build -w web \
    && cp -r /opt/hermes-agent-staging/hermes_cli/web_dist /opt/hermes_cli_web_dist \
    && rm -rf /opt/hermes-agent-staging/web/node_modules \
    && echo "== Dashboard web_dist built and staged at /opt/hermes_cli_web_dist"

# Fix #20: WebUI providers.py ignores key_env for provider status display.
# Upstream: https://github.com/nesquena/hermes-webui (not yet fixed as of v0.51.340)
# The runtime's _resolve_key() already handles key_env; this brings the display in sync.
COPY volumes_hermes_opencode/build/scripts/fix20-providers-keyenv.py /tmp/fix20-providers-keyenv.py
RUN python3 /tmp/fix20-providers-keyenv.py && rm /tmp/fix20-providers-keyenv.py

COPY volumes_hermes_opencode/build/scripts/install-skills.sh /usr/local/bin/install-skills.sh
COPY volumes_hermes_opencode/build/scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY volumes_hermes_opencode/build/scripts/lib/ /usr/local/bin/lib/
COPY volumes_hermes_opencode/build/tests/healthcheck.sh /usr/local/bin/healthcheck.sh
COPY volumes_hermes_opencode/build/scripts/create-stub-skills.sh /usr/local/bin/create-stub-skills.sh
COPY AGENTS.md /usr/local/share/AGENTS.md
RUN chmod +x /usr/local/bin/install-skills.sh /usr/local/bin/entrypoint.sh /usr/local/bin/healthcheck.sh /usr/local/bin/create-stub-skills.sh

RUN HERMES_SKILLS_DIR=/opt/hermes-skills-staging \
    OPENCODE_SKILLS_DIR=/home/hermeswebui/.config/opencode/skills \
    install-skills.sh

# Trim non-essential directories from staged clone after skills extraction.
# install-skills.sh extracts llm-wiki from skills/research/ above.
RUN rm -rf /opt/hermes-agent-staging/skills \
           /opt/hermes-agent-staging/docs \
           /opt/hermes-agent-staging/tests \
           /opt/hermes-agent-staging/.github

RUN echo "=== Hermes x OpenCode Stack ===" \
    && python3 -c "import sys; print(f'Python: {sys.version}')" \
    && opencode --version \
    && bats --version \
    && test -f /opt/hermes-agent-staging/pyproject.toml \
    && grep -q '"User-Agent".*"hermes-agent' /opt/hermes-agent-staging/plugins/model-providers/custom/__init__.py \
    && echo "================================"

# Create AGENTS.md-mandated stub skills in staging (pending full implementation)
RUN create-stub-skills.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
