# Graphify Report — 2026-07-01

## Summary

- Total files analyzed: 2276
- Total nodes: 2276
- Total edges: 24473
- Date: 2026-07-01

## Changes Captured

This graph captures the codebase after:

1. **OPENCODE_API_KEY → OPENCODE_ZEN_API_KEY rename** (PRD §20)
   - 18 files renamed across scripts, compose, CI, docs, tests
   - Aligns Docker stack env var naming with official Hermes agent convention
   - Generated opencode.jsonc now uses `{env:OPENCODE_ZEN_API_KEY}`

2. **Per-delegation model routing** (PRD §21)
   - New env vars: HERMES_DELEGATION_MODEL, HERMES_DELEGATION_PROVIDER
   - config-hermes.sh now writes delegation.model/delegation.provider conditionally
   - Enables different models for parent vs subagent conversations
   - 7 files modified (config-hermes.sh, docker-compose.yml, .env.example, docs, tests)

## Modified Files (19 total)

### Scripts
- `volumes_hermes_opencode/build/scripts/lib/config-opencode.sh` — ZEN env var rename
- `volumes_hermes_opencode/build/scripts/lib/config-hermes.sh` — delegation.model/provider support
- `volumes_hermes_opencode/build/scripts/lib/service-opencode.sh` — ZEN env var rename
- `volumes_hermes_opencode/build/scripts/lib/validate-opencode.sh` — ZEN env var rename

### Configuration
- `docker-compose.yml` — OPENCODE_ZEN_API_KEY + delegation env vars
- `.env.example` — Updated template with all changes

### Documentation
- `docs/03-opencode-serve.md` — ZEN env var rename
- `docs/05-entrypoint-sequence.md` — ZEN rename + delegation docs
- `docs/06-config-and-env.md` — Full env var table updates
- `docs/09-testing-and-verification.md` — ZEN env var rename
- `docs/14-delegation-matrix.md` — ZEN env var rename
- `docs/20-opencode-runtime-fallback.md` — ZEN env var rename
- `README.md` — Updated env var table
- `AGENTS.md` — Updated standing orders

### Tests
- `tests/e2e/03-config.bats` — AC34 delegation test + ZEN rename (8 refs)
- `tests/e2e/10-acp-limitation.bats` — ZEN env var rename
- `tests/e2e/19-ctx-pin-and-credentials.bats` — ZEN env var rename

### CI
- `.github/workflows/e2e.yml` — secrets.OPENCODE_ZEN_API_KEY

### Meta
- `PRD.md` — Sections 20 (ZEN rename) + 21 (delegation model)

## Verification

- Shell syntax: All modified .sh files pass `bash -n`
- E2E tests: 38/38 tests pass (including AC34)
- Container: Healthy, config verified live
- grep: Zero remaining OPENCODE_API_KEY in repo-tracked files
