# Graph Report - hermes-x-opencode  (2026-06-10)

## Corpus Check
- 23 files · ~31,392 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 461 nodes · 527 edges · 25 communities (24 shown, 1 thin omitted)
- Extraction: 95% EXTRACTED · 5% INFERRED · 0% AMBIGUOUS · INFERRED: 25 edges (avg confidence: 0.84)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `2bf2f113`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- [[_COMMUNITY_Community 0|Community 0]]
- [[_COMMUNITY_Community 1|Community 1]]
- [[_COMMUNITY_Community 2|Community 2]]
- [[_COMMUNITY_Community 3|Community 3]]
- [[_COMMUNITY_Community 4|Community 4]]
- [[_COMMUNITY_Community 5|Community 5]]
- [[_COMMUNITY_Community 6|Community 6]]
- [[_COMMUNITY_Community 7|Community 7]]
- [[_COMMUNITY_Community 8|Community 8]]
- [[_COMMUNITY_Community 9|Community 9]]
- [[_COMMUNITY_Community 10|Community 10]]
- [[_COMMUNITY_Community 11|Community 11]]
- [[_COMMUNITY_Community 12|Community 12]]
- [[_COMMUNITY_Community 13|Community 13]]
- [[_COMMUNITY_Community 14|Community 14]]
- [[_COMMUNITY_Community 15|Community 15]]
- [[_COMMUNITY_Community 16|Community 16]]
- [[_COMMUNITY_Community 17|Community 17]]
- [[_COMMUNITY_Community 18|Community 18]]
- [[_COMMUNITY_Community 19|Community 19]]
- [[_COMMUNITY_Community 20|Community 20]]
- [[_COMMUNITY_Community 21|Community 21]]
- [[_COMMUNITY_Community 22|Community 22]]
- [[_COMMUNITY_Community 23|Community 23]]
- [[_COMMUNITY_Community 24|Community 24]]

## God Nodes (most connected - your core abstractions)
1. `How` - 19 edges
2. `PRD.md — Product Requirements Document` - 19 edges
3. `How` - 13 edges
4. `docker-compose.yml — Service Definition` - 12 edges
5. `PRD: Hermes x OpenCode Docker Stack` - 11 edges
6. `Hermes x OpenCode` - 11 edges
7. `16 — Agent Installation Architecture` - 11 edges
8. `How` - 10 edges
9. `How` - 10 edges
10. `15 — Browser Human-in-the-Loop` - 10 edges

## Surprising Connections (you probably didn't know these)
- `tests/run.sh — E2E Test Orchestrator` --conceptually_related_to--> `.github/workflows/e2e.yml — GitHub Actions E2E Workflow`  [INFERRED]
  tests/run.sh → .github/workflows/e2e.yml
- `tests/run.sh — E2E Test Orchestrator` --references--> `docs/09-testing-and-verification.md — Testing and Verification`  [INFERRED]
  tests/run.sh → docs/09-testing-and-verification.md
- `tests/e2e/test_helper/common.bash — Bats Helper Library` --references--> `docs/09-testing-and-verification.md — Testing and Verification`  [INFERRED]
  tests/e2e/test_helper/common.bash → docs/09-testing-and-verification.md
- `OpenCode Security Modes (strict/standard/yolo)` --semantically_similar_to--> `Secrets Handling (key_env vs literal)`  [INFERRED] [semantically similar]
  docs/13-security-hardening.md → AGENTS.md
- `tests/run.sh — E2E Test Orchestrator` --depends_on--> `Docker Healthcheck (bash healthcheck.sh)`  [EXTRACTED]
  tests/run.sh → docker-compose.yml

## Import Cycles
- None detected.

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

## Communities (25 total, 1 thin omitted)

### Community 0 - "Community 0"
Cohesion: 0.06
Nodes (34): 1. Clone this repo, 2. Configure environment, 3. Build and start, 4. Use it, 5. Verify OpenCode works, Agent Version, Architecture, config.yaml has expanded API key instead of literal string (+26 more)

### Community 1 - "Community 1"
Cohesion: 0.07
Nodes (29): 10. Acceptance Criteria, 1. Product Overview, 2. Architecture, 3. Tech Stack, 4. File Inventory, 5.1 `Dockerfile` (at `volumes_hermes_opencode/build/Dockerfile`), 5.2 `scripts/entrypoint.sh` (at `volumes_hermes_opencode/build/scripts/entrypoint.sh`), 5.3 `docker-compose.yml` (+21 more)

### Community 2 - "Community 2"
Cohesion: 0.15
Nodes (12): 17. Wiki Initialization (llm-wiki skill), Directory structure (created on first boot), Initialization, Integration with llm-wiki skill, Overview, Ownership, Persistence, SCHEMA.md backbone (+4 more)

### Community 3 - "Community 3"
Cohesion: 0.09
Nodes (57): Acceptance Criteria (AC1-AC29), Linux ARM64 Target Platform, Multi-Step Docker Build Pipeline, cc-safety-net Plugin (PreToolUse Hook), portainer-cloudflare-traefik_default Network, Cloudflare UA Patch (CustomProfile sed), Config Generation (config.yaml + opencode.jsonc), Bats E2E Test Suite (+49 more)

### Community 4 - "Community 4"
Cohesion: 0.07
Nodes (27): 11 — Skill Installation, Build phase, How, Platform skill discovery, Resolution, Runtime phase, Skill directories, Skill sources (+19 more)

### Community 5 - "Community 5"
Cohesion: 0.31
Nodes (8): common.bash script, gateway_base(), get_api_key(), get_container(), opencode_base(), skip_if_no_secrets(), wait_for_healthy(), webui_base()

### Community 6 - "Community 6"
Cohesion: 0.09
Nodes (21): 09 — Testing and Verification, Acceptance criteria mapping, Agent installation architecture tests (15-agent-installation-architecture.bats), Agent source and patch, Full smoke test script, Gateway chat test, Gateway models endpoint, How (+13 more)

### Community 7 - "Community 7"
Cohesion: 0.11
Nodes (18): 10 — Model Discovery and Multi-Model Support, Case-insensitive dedup, Discovery flow, Fallback behavior, Hermes config format, How, Model counts, Model limits (+10 more)

### Community 9 - "Community 9"
Cohesion: 0.11
Nodes (18): 13 — Security Hardening, Attack testing results, Configuration, File access rules, How, Known remaining gaps, Layer 1: User isolation, Layer 2: cc-safety-net plugin (+10 more)

### Community 10 - "Community 10"
Cohesion: 0.11
Nodes (17): 06 — Config and Env, Config path resolution, config.yaml (Hermes), Environment variables, Hardcoded environment (in docker-compose.yml), How, opencode.jsonc (OpenCode), Resolution (+9 more)

### Community 11 - "Community 11"
Cohesion: 0.11
Nodes (17): 07 — Volume Layout, Bind mounts, Directory structure, .dockerignore (volumes_hermes_opencode/), .dockerignore (volumes_hermes_opencode/build/), First-start agent copy, .gitignore (root), .gitignore (volumes_hermes_opencode/) (+9 more)

### Community 12 - "Community 12"
Cohesion: 0.12
Nodes (16): 05 — Entrypoint Sequence, Config generation details, Execution sequence, Functions, How, Key variables, Model discovery details, Modular architecture (+8 more)

### Community 13 - "Community 13"
Cohesion: 0.13
Nodes (14): 02 — Hermes Gateway, API key auto-generation, HERMES_HOME resolution, How, Key endpoints, Resolution, Restart-loop supervisor, Usage example (+6 more)

### Community 14 - "Community 14"
Cohesion: 0.13
Nodes (14): 04 — Build Pipeline, Agent staging, Build command, Build steps (in order), How, Platform, Resolution, Skill staging (+6 more)

### Community 15 - "Community 15"
Cohesion: 0.13
Nodes (14): 08 — Cloudflare UA Fix, Affected file, Build-time vs runtime, How, Patch command, Resolution, Verdict, Verification (+6 more)

### Community 16 - "Community 16"
Cohesion: 0.13
Nodes (14): 12 — Plugin System, cc-safety-net architecture, How, Interaction with permission system, Plugin failure behavior, Plugin inventory, Plugin resolution, Resolution (+6 more)

### Community 17 - "Community 17"
Cohesion: 0.15
Nodes (12): 01 — Hermes WebUI, Chat flow, How, Key endpoints, Resolution, Session management, Verdict, Verification (+4 more)

### Community 18 - "Community 18"
Cohesion: 0.15
Nodes (12): 03 — OpenCode Serve, Authentication, Connect from a remote machine, Connect from another container on the same network, How, Resolution, Verdict, Verification (+4 more)

### Community 19 - "Community 19"
Cohesion: 0.15
Nodes (12): 14 — Delegation Pattern Matrix, Architecture: Serve + Attach (Recommended), Broken Patterns (Do Not Use), Conditionally Working Patterns, Delegation Matrix, Free Models, Gateway Supervision, Production-Ready Patterns (+4 more)

### Community 20 - "Community 20"
Cohesion: 0.15
Nodes (12): 15 — Browser Human-in-the-Loop, How, How Hermes attaches, Resolution, Start sequence (inside `entrypoint.sh`), Usage, Verdict, Verification (+4 more)

### Community 21 - "Community 21"
Cohesion: 0.17
Nodes (11): 1. MANDATED SKILLS, 2. Code Quality Rules, 3. Docker/Build Constraints, 4. File Locations (inside container), 5. Security Modes, 6. Verification Commands, 7. Project-Specific Patterns, 8. Agent Capabilities (+3 more)

### Community 22 - "Community 22"
Cohesion: 0.17
Nodes (11): 16 — Docker Compose Overrides, docker-compose.ci.yml (CI Port Publishing), docker-compose.override.yml (Cloudflare/Traefik), How, Resolution, Verdict, Verification, What (+3 more)

### Community 23 - "Community 23"
Cohesion: 0.10
Nodes (20): 1. Inventory of All Hermes Installation Points, 2. Active Runtime Code Paths, 3. Duplication Assessment, 4. Recommendations, 5. Proposed PRD Updates, 6. Specific Files/Paths to Change, 7. Verified Facts (from running container), Gap Report: Dual Hermes Installation Investigation (+12 more)

### Community 24 - "Community 24"
Cohesion: 0.15
Nodes (12): 16 — Agent Installation Architecture, Comparison Table, Image Bloat Mitigation, Installation A — Base Image Venv (Active Runtime), Installation B — Staged Clone (Deps Pipeline), Overview, Propagation Chain, Verdict (+4 more)

## Knowledge Gaps
- **312 isolated node(s):** `Architecture`, `1. MANDATED SKILLS`, `2. Code Quality Rules`, `3. Docker/Build Constraints`, `4. File Locations (inside container)` (+307 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **1 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Are the 2 inferred relationships involving `docker-compose.yml — Service Definition` (e.g. with `hermeswebui User Isolation (UID 1000)` and `.github/workflows/e2e.yml — GitHub Actions E2E Workflow`) actually correct?**
  _`docker-compose.yml — Service Definition` has 2 INFERRED edges - model-reasoned connections that need verification._
- **What connects `Architecture`, `1. MANDATED SKILLS`, `2. Code Quality Rules` to the rest of the system?**
  _314 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.05714285714285714 - nodes in this community are weakly interconnected._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.06666666666666667 - nodes in this community are weakly interconnected._
- **Should `Community 3` be split into smaller, more focused modules?**
  _Cohesion score 0.08709273182957393 - nodes in this community are weakly interconnected._
- **Should `Community 4` be split into smaller, more focused modules?**
  _Cohesion score 0.07142857142857142 - nodes in this community are weakly interconnected._
- **Should `Community 6` be split into smaller, more focused modules?**
  _Cohesion score 0.09090909090909091 - nodes in this community are weakly interconnected._