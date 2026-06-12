# 14 — Delegation Pattern Matrix

## What

This document catalogues all agent-to-agent delegation patterns available in the Hermes x OpenCode stack, their current status, and recommended use cases.

Based on real-world interoperability testing documented in vanilla-coder#8.

## Why

Multiple delegation patterns exist, but not all work reliably. This matrix prevents wasted effort on broken patterns and guides users to production-ready approaches.

## Delegation Matrix

### Production-Ready Patterns

| Pattern | Command | Exit Behavior | Reliability | Use Case |
|---------|---------|---------------|-------------|----------|
| **Serve + Attach** (RECOMMENDED) | `opencode serve` + `opencode run --attach URL` | Exit 0, 1 (session not found), or 124 (timeout) | HIGH | Automated delegation, CI/CD, batch tasks |
| JSON structured output | `opencode run --attach URL --format json` | Exit 0, 1 (session not found), or 124 (timeout) | HIGH | Programmatic parsing, logging, metrics |
| Gateway chat | `curl POST :8642/v1/chat/completions` | HTTP response | HIGH | External client integration (Open WebUI, LobeChat, etc.) |
| Hermes subagent | `delegate_task` in Hermes Agent | Return value | HIGH | In-agent task parallelization |

### Conditionally Working Patterns

| Pattern | Command | Exit Behavior | Reliability | Limitation |
|---------|---------|---------------|-------------|------------|
| One-shot `<dir> --prompt` | `opencode /path -m model --prompt "task"` | Enters TUI | MEDIUM | Blocks if no PTY; use `--format json` or `opencode run` instead |
| `opencode run` (standalone) | `opencode run -m model "task"` | Clean exit (0) | MEDIUM | Requires session DB to be initialized; fails on first run after install |
| `opencode run` with custom model via litellm | `opencode run -m litellm/z.ai/glm-5.1 "task"` | Exit 1, `ProviderModelNotFoundError` | BROKEN | OpenCode v1.16.2 has a hardcoded provider registry for `opencode run`; custom providers from opencode.jsonc only load in TUI/serve mode. Use `opencode/` prefix with built-in models instead. |

### Broken Patterns (Do Not Use)

| Pattern | Command | Error | Root Cause | Since |
|---------|---------|-------|------------|-------|
| ACP standalone TCP | `opencode acp --port N` | Exits immediately, port never bound | ACP is IDE stdio only, not TCP server | v1.15.x |
| `opencode serve` unsupervised | `nohup opencode serve &` + `wait -n` | Container exits when serve dies | Serve exits on lifecycle signals; needs restart loop | fixed via OPENCODE_SERVE_ENABLED |
| Custom model via `openai/` prefix | `opencode run -m openai/z.ai/glm-5.1 "task"` | `ProviderModelNotFoundError` | Model ID not in `openai` provider's built-in registry; config can only add metadata, not register new models | v1.16.2 |
| Custom model via `litellm/` prefix | `opencode run -m litellm/z.ai/glm-5.1 "task"` | `ProviderModelNotFoundError` | `litellm` is not a built-in provider; custom providers from config only load in TUI/serve mode | v1.16.2 |

## Architecture: Serve + Attach (Recommended)

```
┌─────────────────────────────────────────────────────┐
│  Hermes Agent (Orchestrator)                        │
│                                                     │
│  1. Start server (persistent, in entrypoint.sh):    │
│     OPENCODE_SERVE_ENABLED=true                     │
│     → opencode serve --port 4096                    │
│                                                     │
│  2. Delegate tasks (many, clean exits):             │
│     opencode run --attach http://127.0.0.1:4096     │
│       -p "$OPENCODE_SERVER_PASSWORD"                │
│       --dir /path/to/project                        │
│       -m opencode/deepseek-v4-flash-free            │
│       "TASK DESCRIPTION"                            │
│                                                     │
│  3. Optional structured output:                     │
│       --format json                                 │
│       (events: step_start, tool_use, step_finish)   │
└─────────────────────────────────────────────────────┘
```

## Free Models

These models require no API key and are built into OpenCode:

| Model | Notes |
|-------|-------|
| `opencode/deepseek-v4-flash-free` | General-purpose, fast |
| `opencode/mimo-v2.5-free` | Alternative free tier |
| `opencode/nemotron-3-ultra-free` | Available but less tested |
| `opencode/north-mini-code-free` | Code-focused free tier |
| `opencode/big-pickle` | Available but less tested |

> Verified against `opencode models opencode` output on OpenCode v1.16.2. The previous `minimax-m3-free` model has been removed; current minimax models (`m2.5`, `m2.7`) are paid.

## Gateway Supervision

The Hermes Gateway (port 8642) runs under a restart-loop supervisor in `entrypoint.sh`:

```bash
nohup su -s /bin/bash "$OPENCODE_USER" -c '
    while true; do
        /app/venv/bin/hermes gateway run --accept-hooks
        echo "[$(date)] gateway exited rc=$?, restarting in 2s" >> '"${HERMES_HOME}"'/logs/gateway-restart.log
        sleep 2
    done
' >> /home/hermeswebui/.hermes/logs/gateway-stdout.log 2>&1 &
```

This ensures the gateway revives automatically after:
- SIGTERM from parent processes (coder agent, container runtime)
- Crashes from OOM or unhandled exceptions
- Any other unexpected exit

Restart events are logged to `$HERMES_HOME/logs/gateway-restart.log` inside the container (bind-mounted, survives restarts).

## Test Coverage

| Test File | Covers | Issue |
|-----------|--------|-------|
| `tests/e2e/04-gateway.bats` | Gateway health, models, chat | — |
| `tests/e2e/09-gateway-resilience.bats` | Gateway SIGTERM survival | vanilla-coder#5 |
| `tests/e2e/10-acp-limitation.bats` | ACP port-bind failure | vanilla-coder#6 |
| `tests/e2e/11-serve-attach.bats` | Serve+Attach delegation flow | vanilla-coder#7 |

## Related Issues

- [vanilla-coder#5](https://github.com/vanilla-republic/vanilla-coder/issues/5) — Gateway SIGTERM fix
- [vanilla-coder#6](https://github.com/vanilla-republic/vanilla-coder/issues/6) — ACP broken
- [vanilla-coder#7](https://github.com/vanilla-republic/vanilla-coder/issues/7) — Serve + Attach recommendation
- [vanilla-coder#8](https://github.com/vanilla-republic/vanilla-coder/issues/8) — Interoperability report
