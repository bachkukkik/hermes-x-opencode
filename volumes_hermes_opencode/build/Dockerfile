FROM ghcr.io/nesquena/hermes-webui:latest

ARG HERMES_AGENT_VERSION=main

RUN apt-get update -y --no-install-recommends \
    && apt-get install -y --no-install-recommends \
       build-essential git ripgrep ffmpeg procps curl \
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

RUN git clone --depth 1 --branch ${HERMES_AGENT_VERSION} \
    https://github.com/NousResearch/hermes-agent.git \
    /opt/hermes-agent-staging

RUN sed -i 's/base_url="",/base_url="",\n    default_headers={"User-Agent": "hermes-agent\/1.0"},/' \
    /opt/hermes-agent-staging/plugins/model-providers/custom/__init__.py

COPY scripts/install-skills.sh /usr/local/bin/install-skills.sh
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY tests/healthcheck.sh /usr/local/bin/healthcheck.sh
RUN chmod +x /usr/local/bin/install-skills.sh /usr/local/bin/entrypoint.sh /usr/local/bin/healthcheck.sh

RUN HERMES_SKILLS_DIR=/opt/hermes-skills-staging \
    SKIP_HERMES_REGISTRATION=1 \
    OPENCODE_SKILLS_DIR=/home/hermeswebui/.config/opencode/skills \
    install-skills.sh

RUN echo "=== Hermes x OpenCode Stack ===" \
    && python3 -c "import sys; print(f'Python: {sys.version}')" \
    && opencode --version \
    && test -f /opt/hermes-agent-staging/pyproject.toml \
    && grep -q '"User-Agent".*"hermes-agent' /opt/hermes-agent-staging/plugins/model-providers/custom/__init__.py \
    && echo "================================"

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
