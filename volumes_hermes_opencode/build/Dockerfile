FROM ghcr.io/nesquena/hermes-webui:latest

ARG HERMES_AGENT_VERSION=main

RUN apt-get update -y --no-install-recommends \
    && apt-get install -y --no-install-recommends \
       build-essential git ripgrep ffmpeg procps curl \
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

# Fix #20: WebUI providers.py ignores key_env for provider status display.
# Upstream: https://github.com/nesquena/hermes-webui (not yet fixed as of v0.51.340)
# The runtime's _resolve_key() already handles key_env; this brings the display in sync.
COPY scripts/fix20-providers-keyenv.py /tmp/fix20-providers-keyenv.py
RUN python3 /tmp/fix20-providers-keyenv.py && rm /tmp/fix20-providers-keyenv.py

COPY scripts/install-skills.sh /usr/local/bin/install-skills.sh
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY scripts/lib/ /usr/local/bin/lib/
COPY tests/healthcheck.sh /usr/local/bin/healthcheck.sh
RUN chmod +x /usr/local/bin/install-skills.sh /usr/local/bin/entrypoint.sh /usr/local/bin/healthcheck.sh

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
    && test -f /opt/hermes-agent-staging/pyproject.toml \
    && grep -q '"User-Agent".*"hermes-agent' /opt/hermes-agent-staging/plugins/model-providers/custom/__init__.py \
    && echo "================================"

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
