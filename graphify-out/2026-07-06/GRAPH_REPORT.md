# Graphify Report — 2026-07-01

## Summary

- Total files analyzed: 2276
- Total nodes: 2276
- Total edges: 24473

## File Type Distribution

- : 1294 files
- : 695 files
- : 122 files
- : 97 files
- : 41 files
- : 20 files
- : 5 files
- : 2 files

## Key Changes (vs previous graph)

This graph captures the codebase after:
1. OPENCODE_API_KEY → OPENCODE_ZEN_API_KEY rename (PRD §20)
2. Per-delegation model routing (HERMES_DELEGATION_MODEL/PROVIDER) (PRD §21)
3. Documentation gap analysis and updates

## Modified Files (19 total)

- config-opencode.sh — ZEN env var rename
- config-hermes.sh — delegation.model/provider support
- docker-compose.yml — new env vars
- .env.example — updated template
- docs/05-entrypoint-sequence.md — delegation docs
- tests/e2e/03-config.bats — AC34 delegation test
