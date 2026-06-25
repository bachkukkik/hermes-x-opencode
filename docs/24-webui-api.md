# 24 — WebUI API

The Hermes WebUI exposes a REST API on port 8787 for health checks,
session management, and agent interaction.

## Endpoints

### `GET /health`

Returns JSON health status including uptime, session count, active
streams, and the accept-loop request counter.

**Test:** `tests/e2e/13-webui-api.bats`

## Related Docs

- [01 — Hermes WebUI](01-hermes-webui.md) — WebUI architecture and configuration
- [04 — Build Pipeline](04-build-pipeline.md) — how the WebUI service is built and started
