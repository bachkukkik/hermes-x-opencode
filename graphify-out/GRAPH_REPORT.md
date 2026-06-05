# Graph Report - .  (2026-06-05)

## Corpus Check
- Corpus is ~22,941 words - fits in a single context window. You may not need a graph.

## Summary
- 83 nodes · 162 edges · 9 communities (7 shown, 2 thin omitted)
- Extraction: 85% EXTRACTED · 15% INFERRED · 0% AMBIGUOUS · INFERRED: 25 edges (avg confidence: 0.84)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Graphify Detection|Graphify Detection]]
- [[_COMMUNITY_Service Architecture|Service Architecture]]
- [[_COMMUNITY_Build & Security|Build & Security]]
- [[_COMMUNITY_Testing & CICD|Testing & CI/CD]]
- [[_COMMUNITY_Config & Discovery|Config & Discovery]]
- [[_COMMUNITY_Test Helpers|Test Helpers]]
- [[_COMMUNITY_Gateway & Serve|Gateway & Serve]]
- [[_COMMUNITY_Plugins & Security|Plugins & Security]]
- [[_COMMUNITY_Test Runner|Test Runner]]

## God Nodes (most connected - your core abstractions)
1. `PRD.md — Product Requirements Document` - 19 edges
2. `docker-compose.yml — Service Definition` - 12 edges
3. `Hermes WebUI Service (:8787)` - 10 edges
4. `Hermes Gateway Service (:8642)` - 10 edges
5. `docs/04-build-pipeline.md — Build Pipeline Architecture` - 9 edges
6. `AGENTS.md — Agent Standing Orders` - 8 edges
7. `docs/05-entrypoint-sequence.md — Entrypoint Sequence` - 8 edges
8. `docs/02-hermes-gateway.md — Hermes Gateway Architecture` - 8 edges
9. `OpenCode Serve Service (:4096)` - 8 edges
10. `README.md — User Documentation` - 7 edges

## Surprising Connections (you probably didn't know these)
- `tests/run.sh — E2E Test Orchestrator` --conceptually_related_to--> `.github/workflows/e2e.yml — GitHub Actions E2E Workflow`  [INFERRED]
  tests/run.sh → .github/workflows/e2e.yml
- `docs/09-testing-and-verification.md — Testing and Verification` --references--> `tests/run.sh — E2E Test Orchestrator`  [INFERRED]
  docs/09-testing-and-verification.md → tests/run.sh
- `docs/09-testing-and-verification.md — Testing and Verification` --references--> `tests/e2e/test_helper/common.bash — Bats Helper Library`  [INFERRED]
  docs/09-testing-and-verification.md → tests/e2e/test_helper/common.bash
- `tests/e2e/test_helper/common.bash — Bats Helper Library` --references--> `Hermes Gateway Service (:8642)`  [EXTRACTED]
  tests/e2e/test_helper/common.bash → docs/02-hermes-gateway.md
- `tests/e2e/test_helper/common.bash — Bats Helper Library` --references--> `Hermes WebUI Service (:8787)`  [EXTRACTED]
  tests/e2e/test_helper/common.bash → docs/01-hermes-webui.md

## Hyperedges (group relationships)
- **Three-Service Docker Stack (WebUI + Gateway + OpenCode Serve)** — concept_hermes_webui_service, concept_hermes_gateway_service, concept_opencode_serve_service [EXTRACTED 1.00]
- **Sequential Health-Gated Startup Chain** — concept_entrypoint_sequence, concept_hermes_webui_service, concept_hermes_gateway_service, concept_opencode_serve_service, concept_wait_n_supervisor [EXTRACTED 1.00]
- **Model Discovery → Config Generation Pipeline** — concept_model_discovery, concept_wildcard_filter, concept_nonchat_filter, concept_config_generation, concept_model_default_name_keys [EXTRACTED 1.00]
- **Build-Time Staging to Runtime Bind Mount Handoff** — concept_build_pipeline, concept_staging_paths, concept_volume_layout, concept_entrypoint_sequence [EXTRACTED 1.00]
- **Defense-in-Depth Security Stack** — concept_user_isolation, concept_cc_safety_net, concept_security_modes, concept_plugin_system [EXTRACTED 1.00]
- **Two-Phase Skill Installation Pipeline** — concept_skill_installation, concept_skill_sources, concept_graphify_integration, concept_staging_paths [EXTRACTED 1.00]
- **E2E Verification Pipeline (CI → Bats → AC)** — doc_e2e_workflow, doc_tests_run_sh, doc_tests_common_bash, concept_e2e_tests, concept_acceptance_criteria [EXTRACTED 1.00]
- **Boot-Time Config Regeneration Cycle** — concept_entrypoint_sequence, concept_config_generation, concept_model_discovery, concept_security_modes [EXTRACTED 1.00]
- **Cloudflare UA Patch Pipeline** — concept_cloudflare_ua_patch, concept_build_pipeline, concept_hermes_agent, concept_hermes_gateway_service [EXTRACTED 1.00]
- **Compose Service Definition Triple** — doc_docker_compose, doc_docker_compose_override, concept_volume_layout, concept_healthcheck [EXTRACTED 1.00]
- **Secret Protection Layers (env, file, network)** — concept_secrets_handling, concept_security_modes, concept_cc_safety_net, concept_hermes_api_key [INFERRED 0.90]

## Communities (9 total, 2 thin omitted)

### Community 0 - "Graphify Detection"
Cohesion: 0.14
Nodes (13): files, code, document, image, paper, video, graphifyignore_patterns, needs_graph (+5 more)

### Community 1 - "Service Architecture"
Cohesion: 0.23
Nodes (13): Graphify Integration (cross-platform skill), Hermes Agent (NousResearch/hermes-agent), Hermes WebUI Service (:8787), Two-Phase Skill Installation, Seven Skill Upstream Sources, Build-Time Staging Paths (/opt/*-staging), state.db (SQLite Session Store), Volume Layout (bind mounts) (+5 more)

### Community 2 - "Build & Security"
Cohesion: 0.38
Nodes (11): Linux ARM64 Target Platform, Multi-Step Docker Build Pipeline, Cloudflare UA Patch (CustomProfile sed), Node.js 22 Requirement, Secrets Handling (key_env vs literal), OpenCode Security Modes (strict/standard/yolo), AGENTS.md — Agent Standing Orders, docs/04-build-pipeline.md — Build Pipeline Architecture (+3 more)

### Community 3 - "Testing & CI/CD"
Cohesion: 0.42
Nodes (10): Acceptance Criteria (AC1-AC29), portainer-cloudflare-traefik_default Network, Bats E2E Test Suite, Docker Healthcheck (bash healthcheck.sh), docker-compose.yml — Service Definition, docker-compose.override.yml — Cloudflare Network Override, .github/workflows/e2e.yml — GitHub Actions E2E Workflow, docs/09-testing-and-verification.md — Testing and Verification (+2 more)

### Community 4 - "Config & Discovery"
Cohesion: 0.42
Nodes (9): Config Generation (config.yaml + opencode.jsonc), Entrypoint Sequence (13-step startup), model.default AND model.name Keys, Model Discovery Mechanism, Non-Chat Model Filter, Wildcard Model Filter (IDs ending in /*), docs/06-config-and-env.md — Configuration and Environment, docs/05-entrypoint-sequence.md — Entrypoint Sequence (+1 more)

### Community 6 - "Gateway & Serve"
Cohesion: 0.46
Nodes (8): HERMES_API_KEY (auto-generated gateway token), Hermes Gateway Service (:8642), OpenAI-Compatible API Surface, OpenCode Serve Service (:4096), hermeswebui User Isolation (UID 1000), wait -n Process Supervisor, docs/02-hermes-gateway.md — Hermes Gateway Architecture, docs/03-opencode-serve.md — OpenCode Serve Architecture

### Community 7 - "Plugins & Security"
Cohesion: 0.53
Nodes (6): cc-safety-net Plugin (PreToolUse Hook), @franlol/opencode-md-table-formatter, @tarquinen/opencode-dcp (Context Pruner), OpenCode Plugin System (npm-resolved), docs/12-plugin-system.md — OpenCode Plugin System, docs/13-security-hardening.md — Security Hardening

## Knowledge Gaps
- **14 isolated node(s):** `code`, `document`, `paper`, `image`, `video` (+9 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **2 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `PRD.md — Product Requirements Document` connect `Build & Security` to `Service Architecture`, `Testing & CI/CD`, `Config & Discovery`, `Gateway & Serve`?**
  _High betweenness centrality (0.168) - this node is a cross-community bridge._
- **Why does `docker-compose.yml — Service Definition` connect `Testing & CI/CD` to `Service Architecture`, `Build & Security`, `Gateway & Serve`?**
  _High betweenness centrality (0.075) - this node is a cross-community bridge._
- **Why does `docs/05-entrypoint-sequence.md — Entrypoint Sequence` connect `Config & Discovery` to `Build & Security`, `Plugins & Security`?**
  _High betweenness centrality (0.055) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `docker-compose.yml — Service Definition` (e.g. with `hermeswebui User Isolation (UID 1000)` and `.github/workflows/e2e.yml — GitHub Actions E2E Workflow`) actually correct?**
  _`docker-compose.yml — Service Definition` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `Hermes WebUI Service (:8787)` (e.g. with `Hermes Gateway Service (:8642)` and `docker-compose.override.yml — Cloudflare Network Override`) actually correct?**
  _`Hermes WebUI Service (:8787)` has 2 INFERRED edges - model-reasoned connections that need verification._
- **What connects `code`, `document`, `paper` to the rest of the system?**
  _16 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Graphify Detection` be split into smaller, more focused modules?**
  _Cohesion score 0.14285714285714285 - nodes in this community are weakly interconnected._