# Graph Report - .  (2026-05-30)

## Corpus Check
- Corpus is ~21,721 words - fits in a single context window. You may not need a graph.

## Summary
- 85 nodes · 109 edges · 14 communities (8 shown, 6 thin omitted)
- Extraction: 94% EXTRACTED · 6% INFERRED · 0% AMBIGUOUS · INFERRED: 7 edges (avg confidence: 0.79)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_WebUI, Gateway & OpenCode Core|WebUI, Gateway & OpenCode Core]]
- [[_COMMUNITY_Build & Staging Pipeline|Build & Staging Pipeline]]
- [[_COMMUNITY_Test Helper Library|Test Helper Library]]
- [[_COMMUNITY_E2E Testing & Verification|E2E Testing & Verification]]
- [[_COMMUNITY_Skill Installation Architecture|Skill Installation Architecture]]
- [[_COMMUNITY_Security & Plugin System|Security & Plugin System]]
- [[_COMMUNITY_Hermes Agent & LLM Config|Hermes Agent & LLM Config]]
- [[_COMMUNITY_Build Pipeline & Docker|Build Pipeline & Docker]]
- [[_COMMUNITY_OpenCode Schema|OpenCode Schema]]
- [[_COMMUNITY_Plugin Dependencies|Plugin Dependencies]]
- [[_COMMUNITY_Test Runner Script|Test Runner Script]]
- [[_COMMUNITY_Graphify Plugin Config|Graphify Plugin Config]]
- [[_COMMUNITY_Root Project Identity|Root Project Identity]]

## God Nodes (most connected - your core abstractions)
1. `Entrypoint Script (entrypoint.sh)` - 12 edges
2. `Skill Installation Document` - 10 edges
3. `Dockerfile` - 8 edges
4. `Build Pipeline Document` - 7 edges
5. `hermes-opencode Service` - 6 edges
6. `Hermes Gateway (:8642)` - 6 edges
7. `Testing and Verification Document` - 6 edges
8. `config.yaml Generated File` - 6 edges
9. `Hermes WebUI (:8787)` - 5 edges
10. `Shared Bind Mount (/home/hermeswebui/.hermes)` - 5 edges

## Surprising Connections (you probably didn't know these)
- `hermes-opencode Service` --references--> `Test Runner (tests/run.sh)`  [EXTRACTED]
  docker-compose.yml → tests/run.sh
- `hermes-opencode Service` --references--> `Test Helper Library (common.bash)`  [EXTRACTED]
  docker-compose.yml → tests/e2e/test_helper/common.bash
- `cc-safety-net Plugin` --semantically_similar_to--> `OpenCode Security Modes (strict/standard/yolo)`  [INFERRED] [semantically similar]
  docs/12-plugin-system.md → README.md
- `Hermes Gateway (:8642)` --starts--> `start_gateway()`  [EXTRACTED]
  README.md → docs/05-entrypoint-sequence.md
- `Hermes Agent Runtime` --is_instance_of--> `AIAgent Class (run_conversation)`  [INFERRED]
  PRD.md → docs/01-hermes-webui.md

## Hyperedges (group relationships)
- **Build " Testing " Skill Pipeline** — doc04_docker_build_steps, doc04_graphify_dual_platform, doc09_graphify_integration_tests, doc11_graphify_install_mechanics, doc11_seven_skill_sources, doc11_two_phase_architecture, doc09_acceptance_criteria_29 [INFERRED 0.75]

## Communities (14 total, 6 thin omitted)

### Community 0 - "WebUI, Gateway & OpenCode Core"
Cohesion: 0.17
Nodes (17): Hermes Gateway (:8642), Hermes WebUI (:8787), OpenCode Serve (:4096), Test Helper Library (common.bash), AIAgent Class (run_conversation), discover_models(), generate_opencode_config(), start_opencode_serve() (+9 more)

### Community 1 - "Build & Staging Pipeline"
Cohesion: 0.18
Nodes (12): Agent Staging Path (/opt/hermes-agent-staging), Dockerfile, Entrypoint Script (entrypoint.sh), Install Skills Script (install-skills.sh), Node.js 22 Runtime, OpenCode CLI, Skills Staging Path (/opt/hermes-skills-staging), ensure_agent() (+4 more)

### Community 3 - "E2E Testing & Verification"
Cohesion: 0.36
Nodes (8): 29 Acceptance Criteria (AC1-AC29), Graphify Integration Tests (AC26-AC29), Testing Known Issues (has_key, API key, SSE), Runtime Security Hardening Checks, Full Smoke Test Script (12 steps), Testing and Verification Document, E2E GitHub Actions Workflow, Test Runner (tests/run.sh)

### Community 4 - "Skill Installation Architecture"
Cohesion: 0.36
Nodes (8): Build-time graphify Dual-Platform Install, Graphify Install Mechanics (HOME override, PATH fix, staging copy), Platform Discovery Differences (OpenCode flat vs Hermes recursive), Seven Upstream Skill Sources, Skill Installation Document, Skill Installation Timing Impact (build 60s, runtime <1s), Sparse Clone Helper (clone_sparse), Two-Phase Skill Architecture (Build + Runtime)

### Community 5 - "Security & Plugin System"
Cohesion: 0.40
Nodes (6): OpenCode Security Modes (strict/standard/yolo), cc-safety-net Plugin, md-table-formatter Plugin, opencode-dcp Plugin, Plugin System Document, Security Hardening Defense-in-Depth

### Community 6 - "Hermes Agent & LLM Config"
Cohesion: 0.40
Nodes (5): AGENTS.md Mandated Skills, Hermes Agent Runtime, External LLM Provider, CustomProfile Class, CustomProfile UA Patch

### Community 7 - "Build Pipeline & Docker"
Cohesion: 0.70
Nodes (5): Build Pipeline Document, Build Pipeline Risks, COPY Scripts to /usr/local/bin (Dockerfile Step 8), Docker Build Steps (11-stage pipeline), Staging Directory Overhead (~60MB)

## Knowledge Gaps
- **19 isolated node(s):** `run.sh script`, `common.bash script`, `$schema`, `plugin`, `@opencode-ai/plugin` (+14 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **6 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Entrypoint Script (entrypoint.sh)` connect `Build & Staging Pipeline` to `WebUI, Gateway & OpenCode Core`?**
  _High betweenness centrality (0.174) - this node is a cross-community bridge._
- **Why does `Dockerfile` connect `Build & Staging Pipeline` to `Hermes Agent & LLM Config`, `Build Pipeline & Docker`?**
  _High betweenness centrality (0.168) - this node is a cross-community bridge._
- **Why does `Skill Installation Document` connect `Skill Installation Architecture` to `Build & Staging Pipeline`, `Hermes Agent & LLM Config`, `Build Pipeline & Docker`?**
  _High betweenness centrality (0.132) - this node is a cross-community bridge._
- **What connects `run.sh script`, `common.bash script`, `$schema` to the rest of the system?**
  _19 weakly-connected nodes found - possible documentation gaps or missing edges._