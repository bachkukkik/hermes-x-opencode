# Graph Report - hermes-x-opencode  (2026-06-27)

## Corpus Check
- 31 files · ~44,976 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 812 nodes · 856 edges · 71 communities (52 shown, 19 thin omitted)
- Extraction: 94% EXTRACTED · 6% INFERRED · 0% AMBIGUOUS · INFERRED: 49 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `d8c190b2`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- [[_COMMUNITY_Build Pipeline & Acceptance Criteria|Build Pipeline & Acceptance Criteria]]
- [[_COMMUNITY_Quick Start & README|Quick Start & README]]
- [[_COMMUNITY_PRD & Product Overview|PRD & Product Overview]]
- [[_COMMUNITY_Dual Installation Architecture|Dual Installation Architecture]]
- [[_COMMUNITY_Skill Installation|Skill Installation]]
- [[_COMMUNITY_Provider Routing & Zen Auth|Provider Routing & Zen Auth]]
- [[_COMMUNITY_Testing & Verification|Testing & Verification]]
- [[_COMMUNITY_Security Rules & Patterns|Security Rules & Patterns]]
- [[_COMMUNITY_Gap Report Dual Installation|Gap Report: Dual Installation]]
- [[_COMMUNITY_Model Discovery|Model Discovery]]
- [[_COMMUNITY_Security Hardening|Security Hardening]]
- [[_COMMUNITY_Docker Health & Build Verification|Docker Health & Build Verification]]
- [[_COMMUNITY_Config & Environment|Config & Environment]]
- [[_COMMUNITY_Volume Layout|Volume Layout]]
- [[_COMMUNITY_Entrypoint Sequence|Entrypoint Sequence]]
- [[_COMMUNITY_Hermes Gateway|Hermes Gateway]]
- [[_COMMUNITY_Build Pipeline Steps|Build Pipeline Steps]]
- [[_COMMUNITY_Cloudflare UA Fix|Cloudflare UA Fix]]
- [[_COMMUNITY_Plugin System|Plugin System]]
- [[_COMMUNITY_Hermes WebUI|Hermes WebUI]]
- [[_COMMUNITY_OpenCode Serve|OpenCode Serve]]
- [[_COMMUNITY_Delegation Matrix|Delegation Matrix]]
- [[_COMMUNITY_Browser Human-in-the-Loop|Browser Human-in-the-Loop]]
- [[_COMMUNITY_Agent Installation Architecture|Agent Installation Architecture]]
- [[_COMMUNITY_Wiki Initialization|Wiki Initialization]]
- [[_COMMUNITY_AGENTS.md Standing Orders|AGENTS.md Standing Orders]]
- [[_COMMUNITY_Docker Compose Overrides|Docker Compose Overrides]]
- [[_COMMUNITY_Test Helper (common.bash)|Test Helper (common.bash)]]
- [[_COMMUNITY_Config Patterns & Interpolation|Config Patterns & Interpolation]]
- [[_COMMUNITY_CI Workflow & Mock LLM|CI Workflow & Mock LLM]]
- [[_COMMUNITY_Test Runner (run.sh)|Test Runner (run.sh)]]
- [[_COMMUNITY_Model Filters|Model Filters]]
- [[_COMMUNITY_VNC & Chromium CDP Stack|VNC & Chromium CDP Stack]]
- [[_COMMUNITY_Mock LLM Server Script|Mock LLM Server Script]]
- [[_COMMUNITY_Quick Start Models|Quick Start Models]]
- [[_COMMUNITY_Chat Flow & SSE Streaming|Chat Flow & SSE Streaming]]
- [[_COMMUNITY_ARM64 Platform|ARM64 Platform]]
- [[_COMMUNITY_Bash Heredoc JSON Rule|Bash Heredoc JSON Rule]]
- [[_COMMUNITY_Mandated Skills Policy|Mandated Skills Policy]]
- [[_COMMUNITY_No Hardcoded Secrets Rule|No Hardcoded Secrets Rule]]
- [[_COMMUNITY_No shell=True Rule|No shell=True Rule]]
- [[_COMMUNITY_Build Arg Agent Version|Build Arg: Agent Version]]
- [[_COMMUNITY_Zen Key Validation|Zen Key Validation]]
- [[_COMMUNITY_Hermes Subagent Delegation|Hermes Subagent Delegation]]
- [[_COMMUNITY_Delegation Matrix Reference|Delegation Matrix Reference]]
- [[_COMMUNITY_Model Discovery Fallback|Model Discovery Fallback]]
- [[_COMMUNITY_validate_opencode_zen_key|validate_opencode_zen_key]]
- [[_COMMUNITY_Session Continuity|Session Continuity]]
- [[_COMMUNITY_Data Flow Pipeline|Data Flow Pipeline]]
- [[_COMMUNITY_Wiki Init Tests|Wiki Init Tests]]
- [[_COMMUNITY_HMAC Cookie Auth|HMAC Cookie Auth]]
- [[_COMMUNITY_Community 51|Community 51]]
- [[_COMMUNITY_Community 52|Community 52]]
- [[_COMMUNITY_Community 53|Community 53]]
- [[_COMMUNITY_Community 54|Community 54]]
- [[_COMMUNITY_Community 55|Community 55]]
- [[_COMMUNITY_Community 56|Community 56]]
- [[_COMMUNITY_Community 57|Community 57]]
- [[_COMMUNITY_Community 58|Community 58]]
- [[_COMMUNITY_Community 59|Community 59]]
- [[_COMMUNITY_Community 60|Community 60]]
- [[_COMMUNITY_Community 61|Community 61]]
- [[_COMMUNITY_Community 62|Community 62]]
- [[_COMMUNITY_Community 63|Community 63]]
- [[_COMMUNITY_Community 64|Community 64]]
- [[_COMMUNITY_Community 65|Community 65]]
- [[_COMMUNITY_Community 66|Community 66]]
- [[_COMMUNITY_Community 67|Community 67]]
- [[_COMMUNITY_Community 68|Community 68]]
- [[_COMMUNITY_Community 69|Community 69]]
- [[_COMMUNITY_Community 70|Community 70]]

## God Nodes (most connected - your core abstractions)
1. `How` - 19 edges
2. `PRD.md — Product Requirements Document` - 19 edges
3. `PRD: Hermes x OpenCode Docker Stack` - 18 edges
4. `Standing Orders (ALWAYS apply)` - 17 edges
5. `15. Browser State Persistence` - 16 edges
6. `17. Documentation Gaps: doc06 Env Var Table Parity` - 14 edges
7. `How` - 14 edges
8. `16. Configurable Browser Viewport (Xvfb Display Size)` - 12 edges
9. `22 — Profiles and the Righthand-Man Orchestrator` - 12 edges
10. `docker-compose.yml — Service Definition` - 12 edges

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
- **Secretless CI Flow** — e2e_workflow, e2e_mock_llm_server_ci, e2e_env_seeding [EXTRACTED 0.90]
- **Code Quality Rules** — agents_no_shell_true, agents_no_hardcoded_secrets, agents_no_wildcard_models, agents_both_model_keys, agents_customprofile_ua_header [EXTRACTED 0.90]
- **Dual Agent Installation Architecture** — prd_installation_a, prd_installation_b, prd_customprofile_patch [EXTRACTED 0.95]
- **WebUI Chat Pipeline** — webui_async_chat_flow, webui_sse_streaming, webui_session_sqlite [EXTRACTED 0.90]
- **Build-Time Staging Pipeline** — build_agent_staging, build_skill_staging, build_graphify_registration [EXTRACTED 0.90]
- **Config Generation Pipeline** — entrypoint_discover_models, entrypoint_generate_config, entrypoint_generate_opencode_config, entrypoint_resolve_provider_prefix [EXTRACTED 0.95]
- **Issue #46 Config Features** — config_per_model_routing_detail, config_opencode_provider_explicit, config_auth_json_fallback [EXTRACTED 0.95]
- **Model Discovery Filter Pipeline** — discovery_nonchat_filter, discovery_wildcard_filter, discovery_case_dedup [EXTRACTED 0.95]
- **Production-Ready Delegation Patterns** — delegation_serve_attach, delegation_gateway_chat, delegation_hermes_subagent [EXTRACTED 0.90]
- **X/VNC/Chromium Process Stack** — browser_xvfb, browser_chromium_cdp, browser_novnc_websockify [EXTRACTED 0.95]
- **Dual Installation Architecture** — agent_install_a_detail, agent_install_b_detail, agent_propagation_chain, agent_why_both_exist [EXTRACTED 0.95]
- **Wiki Initialization Pipeline** — wiki_init_function, wiki_schema_backbone, wiki_dir_structure [EXTRACTED 0.90]

## Communities (71 total, 19 thin omitted)

### Community 0 - "Build Pipeline & Acceptance Criteria"
Cohesion: 0.09
Nodes (57): Acceptance Criteria (AC1-AC29), Linux ARM64 Target Platform, Multi-Step Docker Build Pipeline, cc-safety-net Plugin (PreToolUse Hook), portainer-cloudflare-traefik_default Network, Cloudflare UA Patch (CustomProfile sed), Config Generation (config.yaml + opencode.jsonc), Bats E2E Test Suite (+49 more)

### Community 1 - "Quick Start & README"
Cohesion: 0.06
Nodes (34): 1. Clone this repo, 2. Configure environment, 3. Build and start, 4. Use it, 5. Verify OpenCode works, Agent Version, Architecture, config.yaml has expanded API key instead of literal string (+26 more)

### Community 2 - "PRD & Product Overview"
Cohesion: 0.22
Nodes (8): 10. Acceptance Criteria, 13. Additional Acceptance Criteria, 1. Product Overview, 3. Tech Stack, 4. File Inventory, 8. Constraints, PRD: Hermes x OpenCode Docker Stack, Related Repositories

### Community 3 - "Dual Installation Architecture"
Cohesion: 0.08
Nodes (27): Image Bloat Mitigation Detail, Installation A — Active Runtime Detail, Installation B — Staged Clone Detail, User-Agent Patch Propagation Chain, Why Both Installations Exist (Rationale), Browser Human-in-the-Loop Capability, Dual Installation Architecture, Agent Source Goes to Staging Path (+19 more)

### Community 4 - "Skill Installation"
Cohesion: 0.07
Nodes (27): 11 — Skill Installation, Build phase, How, Platform skill discovery, Resolution, Runtime phase, Skill directories, Skill sources (+19 more)

### Community 5 - "Provider Routing & Zen Auth"
Cohesion: 0.09
Nodes (24): auth.json Seeding (opencode + litellm providers), Bats Testing Framework, Collect Docker Compose Logs on Failure, config-opencode.sh (opencode.jsonc generator), Hermes x OpenCode Docker Compose Stack, E2E Tests CI Workflow, Create .env from Secrets Step, Env Var Conditional (_HAS_OPENAI_KEY) (+16 more)

### Community 6 - "Testing & Verification"
Cohesion: 0.10
Nodes (22): OpenCode Provider Block (issue #46), Per-Model Provider Routing (issue #46), auth.json Credential Store Seeding, Explicit opencode Provider Block, Per-Model Provider Routing Decision Table, Free Models Require OPENCODE_API_KEY, opencode run with litellm/ BROKEN, Serve + Attach Pattern (RECOMMENDED) (+14 more)

### Community 7 - "Security Rules & Patterns"
Cohesion: 0.09
Nodes (22): 09 — Testing and Verification, Acceptance criteria mapping, Agent installation architecture tests (15-agent-installation-architecture.bats), Agent source and patch, Full smoke test script, Gateway chat test, Gateway models endpoint, How (+14 more)

### Community 8 - "Gap Report: Dual Installation"
Cohesion: 0.10
Nodes (21): CustomProfile User-Agent Header Rule, Graphify Skill, Container: hermes-opencode, host.docker.internal extra_hosts Fix, Docker overlayfs ARM64 Issue, Security Modes (strict/standard/yolo), Graphify Build-Time Registration, Skill Staging (Two-Phase) (+13 more)

### Community 9 - "Model Discovery"
Cohesion: 0.10
Nodes (20): 1. Inventory of All Hermes Installation Points, 2. Active Runtime Code Paths, 3. Duplication Assessment, 4. Recommendations, 5. Proposed PRD Updates, 6. Specific Files/Paths to Change, 7. Verified Facts (from running container), Gap Report: Dual Hermes Installation Investigation (+12 more)

### Community 10 - "Security Hardening"
Cohesion: 0.10
Nodes (19): 10 — Model Discovery and Multi-Model Support, Case-insensitive dedup, Discovery flow, Fallback behavior, Hermes config format, How, Model counts, Model limits (+11 more)

### Community 11 - "Docker Health & Build Verification"
Cohesion: 0.11
Nodes (18): 13 — Security Hardening, Attack testing results, Configuration, File access rules, How, Known remaining gaps, Layer 1: User isolation, Layer 2: cc-safety-net plugin (+10 more)

### Community 12 - "Config & Environment"
Cohesion: 0.10
Nodes (19): 1. Confirm the user-data-dir is on the bind mount, 23 — Browser State Persistence, 2. Verify Cookies file exists (pre-restart), 3. Restart the container and verify Cookies survive, 4. Confirm lockfiles are cleaned up on start, 5. Check that Local Storage directory is intact, Clearing state deliberately, Corrupted profile (Chromium crashes on start, blank windows, or "Profile error" dialogs) (+11 more)

### Community 13 - "Volume Layout"
Cohesion: 0.11
Nodes (18): 06 — Config and Env, Config path resolution, config.yaml (Hermes), Environment variables, Hardcoded environment (in docker-compose.yml), How, opencode.jsonc (OpenCode), Per-model provider routing (+10 more)

### Community 14 - "Entrypoint Sequence"
Cohesion: 0.11
Nodes (17): 07 — Volume Layout, Bind mounts, Directory structure, .dockerignore (volumes_hermes_opencode/), .dockerignore (volumes_hermes_opencode/build/), First-start agent copy, .gitignore (root), .gitignore (volumes_hermes_opencode/) (+9 more)

### Community 15 - "Hermes Gateway"
Cohesion: 0.12
Nodes (16): 05 — Entrypoint Sequence, Config generation details, Execution sequence, Functions, How, Key variables, Model discovery details, Modular architecture (+8 more)

### Community 16 - "Build Pipeline Steps"
Cohesion: 0.13
Nodes (14): 02 — Hermes Gateway, API key auto-generation, HERMES_HOME resolution, How, Key endpoints, Resolution, Restart-loop supervisor, Usage example (+6 more)

### Community 17 - "Cloudflare UA Fix"
Cohesion: 0.13
Nodes (14): 04 — Build Pipeline, Agent staging, Build command, Build steps (in order), How, Platform, Resolution, Skill staging (+6 more)

### Community 18 - "Plugin System"
Cohesion: 0.13
Nodes (14): 08 — Cloudflare UA Fix, Affected file, Build-time vs runtime, How, Patch command, Resolution, Verdict, Verification (+6 more)

### Community 19 - "Hermes WebUI"
Cohesion: 0.13
Nodes (14): 12 — Plugin System, cc-safety-net architecture, How, Interaction with permission system, Plugin failure behavior, Plugin inventory, Plugin resolution, Resolution (+6 more)

### Community 20 - "OpenCode Serve"
Cohesion: 0.15
Nodes (12): 01 — Hermes WebUI, Chat flow, How, Key endpoints, Resolution, Session management, Verdict, Verification (+4 more)

### Community 21 - "Delegation Matrix"
Cohesion: 0.12
Nodes (14): 03 — OpenCode Serve, Authentication, Connect from a remote machine, Connect from another container on the same network, Entrypoint integration, How, Module: service-opencode.sh, Resolution (+6 more)

### Community 22 - "Browser Human-in-the-Loop"
Cohesion: 0.15
Nodes (12): 14 — Delegation Pattern Matrix, Architecture: Serve + Attach (Recommended), Broken Patterns (Do Not Use), Conditionally Working Patterns, Delegation Matrix, Free Models, Gateway Supervision, Production-Ready Patterns (+4 more)

### Community 23 - "Agent Installation Architecture"
Cohesion: 0.12
Nodes (16): 15 — Browser Human-in-the-Loop, CDP connection refused, Chromium startup timeout (30-second wait exceeded), Container marked unhealthy due to CDP failure, How, How Hermes attaches, Resolution, Start sequence (inside `entrypoint.sh`) (+8 more)

### Community 24 - "Wiki Initialization"
Cohesion: 0.15
Nodes (12): 16 — Agent Installation Architecture, Comparison Table, Image Bloat Mitigation, Installation A — Base Image Venv (Active Runtime), Installation B — Staged Clone (Deps Pipeline), Overview, Propagation Chain, Verdict (+4 more)

### Community 25 - "AGENTS.md Standing Orders"
Cohesion: 0.15
Nodes (12): 17 — Wiki Initialization (llm-wiki skill), Directory structure (created on first boot), Initialization, Integration with llm-wiki skill, Overview, Ownership, Persistence, SCHEMA.md backbone (+4 more)

### Community 26 - "Docker Compose Overrides"
Cohesion: 0.10
Nodes (19): 1. MANDATED SKILLS, 2. Code Quality Rules, 2. Kanban Delegation Rules (coding discipline), 3. Code Quality Rules, 3. Docker/Build Constraints, 4. Docker/Build Constraints, 4. File Locations (inside container), 5. File Locations (inside container) (+11 more)

### Community 27 - "Test Helper (common.bash)"
Cohesion: 0.17
Nodes (11): 16 — Docker Compose Overrides, docker-compose.ci.yml (CI Port Publishing), docker-compose.override.yml (Cloudflare/Traefik), How, Resolution, Verdict, Verification, What (+3 more)

### Community 28 - "Config Patterns & Interpolation"
Cohesion: 0.31
Nodes (8): common.bash script, gateway_base(), get_api_key(), get_container(), opencode_base(), skip_if_no_secrets(), wait_for_healthy(), webui_base()

### Community 29 - "CI Workflow & Mock LLM"
Cohesion: 0.25
Nodes (8): Both model.default and model.name Rule, browser.cdp_url Config Injection, Env-Driven Configuration Pattern, Cosmetic has_key:false Issue, OpenCode {env:VAR} Key Interpolation, Dual Config Model List Sync, generate_config() Function, Empty default_model in models_cache.json

### Community 30 - "Test Runner (run.sh)"
Cohesion: 0.33
Nodes (7): .env Seeding from GitHub Secrets, Collect Logs on Failure, Mock LLM Server for CI, E2E Test Workflow (GitHub Actions), 30 Acceptance Criteria (AC1-AC30), Bats E2E Test Suite (~109 tests), Mock LLM Server Detail (tests/mock-llm-server.sh)

### Community 32 - "VNC & Chromium CDP Stack"
Cohesion: 0.40
Nodes (5): No Wildcard Model Patterns Rule, Case-Insensitive Model Dedup, Non-Chat Model Filter, Wildcard/Model-Group Filter, discover_models() Function

### Community 33 - "Mock LLM Server Script"
Cohesion: 0.50
Nodes (4): Chromium CDP Endpoint (:9222), noVNC + websockify (:6901), Chromium User Data Persistence, Xvfb Virtual Display (:99)

### Community 51 - "Community 51"
Cohesion: 0.14
Nodes (13): 19 — Security Doctrine, How, Permission block generation, Resolution, Security modes, The two halves, Verdict, Verification (+5 more)

### Community 52 - "Community 52"
Cohesion: 0.17
Nodes (11): 18 — Docker Compose Overrides, docker-compose.ci.yml (CI Port Publishing), docker-compose.override.yml (Cloudflare/Traefik), How, Resolution, Verdict, Verification, What (+3 more)

### Community 54 - "Community 54"
Cohesion: 0.10
Nodes (19): 22 — Profiles and the Righthand-Man Orchestrator, Built-in Hermes tools, CLI, First-boot seeding in the container, Host-side profile, How, How to use it, Routing doctrine (+11 more)

### Community 55 - "Community 55"
Cohesion: 0.13
Nodes (14): 21 — Hermes Web Dashboard, Boot-time readiness probe, Configuration, How, Launch flags, Resolution, Restart-loop supervisor, The web `dist/` prerequisite (IMPORTANT) (+6 more)

### Community 56 - "Community 56"
Cohesion: 0.13
Nodes (14): 20 — OpenCode Runtime Model Fallback, Config generation, Configuration, Cross-provider example, Fallback id resolution, How, Multi-model ordered chain, Resolution (+6 more)

### Community 57 - "Community 57"
Cohesion: 0.15
Nodes (12): Assumptions (surfaced), Feature (the fix), Goal (from /goal), Live state (confirmed in running container), Out of scope (explicit), Plan — Ordered Multi-Model Fallback Chain for OpenCode, Root-cause analysis (investigated directly — karpathy domain), Subsequent prompts (pre-queued by user) (+4 more)

### Community 58 - "Community 58"
Cohesion: 0.29
Nodes (7): 5.1 `Dockerfile` (at `volumes_hermes_opencode/build/Dockerfile`), 5.2 `scripts/entrypoint.sh` (at `volumes_hermes_opencode/build/scripts/entrypoint.sh`), 5.3 `docker-compose.yml`, 5.4 `.env.example`, 5.5 `.gitignore`, 5.6 `.dockerignore`, 5. File Specifications

### Community 59 - "Community 59"
Cohesion: 0.33
Nodes (6): 14. Profile Skills Parity (righthand-man ← default), Assumptions, Changes, Problem, Root causes, Success criteria

### Community 60 - "Community 60"
Cohesion: 0.12
Nodes (16): 15. Browser State Persistence, Assumptions, Assumptions, Assumptions, Changes, Changes, Changes, Problem (+8 more)

### Community 61 - "Community 61"
Cohesion: 0.33
Nodes (6): 9. Usage Patterns, Pattern 1 — Direct One-Shot Coding (verified), Pattern 2 — Plan → Build Pipeline, Chained One-Shots (verified), Pattern 3 — Direct Chat via Agent API (verified), Pattern Summary Table, When to Use What

### Community 62 - "Community 62"
Cohesion: 0.40
Nodes (4): 24 — WebUI API, Endpoints, `GET /health`, Related Docs

### Community 63 - "Community 63"
Cohesion: 0.40
Nodes (5): 11. OpenCode Model Fallback (Runtime Failover), Architecture, Configuration (env-driven), Constraints, Requirement

### Community 64 - "Community 64"
Cohesion: 0.40
Nodes (5): 7. Configuration Reference, Also Found During Fork Sync (Issue #46), Build Arguments, Environment Variables, Per-Model Provider Routing (Issue #46)

### Community 65 - "Community 65"
Cohesion: 0.50
Nodes (4): 6. Startup Sequence, First Boot, Key Behaviors, Subsequent Boots

### Community 66 - "Community 66"
Cohesion: 0.67
Nodes (3): 12. Documentation & Test Hygiene, Gaps (from intended-vs-implemented audit), Non-gaps (verified, no action)

### Community 67 - "Community 67"
Cohesion: 0.67
Nodes (3): 2. Architecture, Agent Installation Architecture, Component Roles

### Community 68 - "Community 68"
Cohesion: 0.11
Nodes (18): LLM-Wiki Capability, Dockerfile (Multi-Step Build), Build-Time Verification Step, Docker Healthcheck (healthcheck.sh), hermes-opencode Docker Compose Service, Optional Wiki Volume Mount, Library Modules (scripts/lib/), entrypoint.sh (Thin Orchestrator) (+10 more)

### Community 69 - "Community 69"
Cohesion: 0.14
Nodes (14): 17. Documentation Gaps: doc06 Env Var Table Parity, Assumptions, Assumptions, Changes, Changes, Gap matrix (intended-vs-implemented), Non-gaps (verified, no action), Non-gaps (verified, no action) (+6 more)

### Community 70 - "Community 70"
Cohesion: 0.17
Nodes (12): 16. Configurable Browser Viewport (Xvfb Display Size), Assumptions, Assumptions, Changes, Changes, Non-goals (out of scope), Problem, Problem (+4 more)

## Knowledge Gaps
- **499 isolated node(s):** `Architecture`, `1. MANDATED SKILLS`, `2. Kanban Delegation Rules (coding discipline)`, `3. Code Quality Rules`, `4. Docker/Build Constraints` (+494 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **19 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `PRD: Hermes x OpenCode Docker Stack` connect `PRD & Product Overview` to `Community 64`, `Community 65`, `Community 66`, `Community 67`, `Community 69`, `Community 70`, `Community 58`, `Community 59`, `Community 60`, `Community 61`, `Community 63`?**
  _High betweenness centrality (0.011) - this node is a cross-community bridge._
- **Why does `OpenCode Serve (Headless HTTP Server)` connect `Testing & Verification` to `Dual Installation Architecture`?**
  _High betweenness centrality (0.005) - this node is a cross-community bridge._
- **Why does `15. Browser State Persistence` connect `Community 60` to `PRD & Product Overview`?**
  _High betweenness centrality (0.004) - this node is a cross-community bridge._
- **What connects `Architecture`, `1. MANDATED SKILLS`, `2. Kanban Delegation Rules (coding discipline)` to the rest of the system?**
  _550 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Build Pipeline & Acceptance Criteria` be split into smaller, more focused modules?**
  _Cohesion score 0.08709273182957393 - nodes in this community are weakly interconnected._
- **Should `Quick Start & README` be split into smaller, more focused modules?**
  _Cohesion score 0.05714285714285714 - nodes in this community are weakly interconnected._
- **Should `Dual Installation Architecture` be split into smaller, more focused modules?**
  _Cohesion score 0.07936507936507936 - nodes in this community are weakly interconnected._