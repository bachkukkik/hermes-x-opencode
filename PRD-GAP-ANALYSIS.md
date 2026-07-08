# PRD Gap Analysis — Docs & Tests Re-Audit (Jul 2026)

## 1. Summary

The prior gap analysis (which drove PR #77) is satisfied: all 18 lib modules now
have per-module docs (`docs/25-40`) and tests (`tests/e2e/20-34`). This re-audit
covers the gaps that opened **after** that work — chiefly the new `agents-a1`
context-length pins (bridged in PR #78) being undocumented, plus residual test
blind spots surfaced by a fresh codebase cross-check.

## 2. Problem Triage

Severity ordered; each item is evidence-backed against current code.

### Docs
| # | Sev | Gap | Evidence |
|---|-----|-----|----------|
| D1 | P0 | `agents-a1-mtp-apex` / `agents-a1-q4` (262144) missing from `resolve_ctx_len` pin table | docs/29-config-hermes.md table ends at `qwen3.6`; code at config-hermes.sh:35-36 |
| D2 | P0 | `get_limits()` entirely undocumented (no ctx table) | docs/30-config-opencode.md documents only `normalize_model_id`/`generate_opencode_config`; code config-opencode.sh:79-126 |
| D3 | P0 | `agents-a1` missing from both tables in model-discovery doc | docs/10-model-discovery.md resolve_ctx_len (~L132) + get_limits (~L203) |
| D4 | P1 | Stale test count "~212 tests across 25 files" (actual 35 files, 00-34) | docs/09-testing-and-verification.md:259,287 |
| D5 | P2 | Doc index skips 36 with no note | docs/README.md (35→37) |
| D6 | P3 | `service-opencode` doc omits `--hostname 0.0.0.0` | docs/34 vs service-opencode.sh:38 |
| D7 | P3 | dashboard doc implies fixed :9119 (actually `HERMES_DASHBOARD_PORT`) | docs/39 vs service-dashboard.sh:34 |
| D8 | P3 | Stale line counts (219→221, 466→471) | docs/29:5, docs/30:5 |

### Tests
| # | Sev | Gap | Evidence |
|---|-----|-----|----------|
| T1 | P1 | `mock-llm-server.sh` / `start_mock_llm` has ZERO coverage | no .bats references it |
| T2 | P2 | `agents-a1` pins asserted only in file 19; canonical 26/27 omit them; 27 never calls `get_limits` | 26:AC214, 27 (no get_limits) |
| T3 | P3 | `normalize_model_id` bare-id (credential-dependent) branch untested | 27:AC219 tests passthrough only |
| T4 | P4 | `service-dashboard.sh` has no function-level test (unlike 29/30/33) | 17-dashboard.bats is HTTP-only |
| T5 | P5 | `append_skills_external_dirs` existence-only; append + idempotence untested | 26:AC216 |

Out of scope (deferred, low value / high side-effect): thin guard-path tests on
backgrounded daemon starters (`start_gateway`, `start_opencode_serve`,
`discover_models` fallback-vs-real). Noted, not fixed.

## 3. Success Criteria

- [ ] `grep -r agents-a1 docs/` returns hits in docs 10, 29, 30 (D1-D3).
- [ ] docs/30 has a `get_limits()` section with a family→(context,output) table (D2).
- [ ] docs/09 test count matches `ls tests/e2e/*.bats | wc -l` (D4).
- [ ] docs/README.md explains the 36 gap; P3 nits corrected (D5-D8).
- [ ] `start_mock_llm` exercised end-to-end (serve + `/v1/models` + chat) (T1).
- [ ] agents-a1 pins asserted in 26 (resolve_ctx_len) and 27 (get_limits) (T2).
- [ ] `normalize_model_id` bare-id both branches asserted (T3).
- [ ] `start_dashboard` has a unit test (defined + disabled-path) (T4).
- [ ] `append_skills_external_dirs` append + idempotence asserted (T5).
- [ ] Full e2e bats suite green after a clean rebuild (no regressions).
- [ ] graphify-out regenerated; llm wiki updated.

## 4. Verification Policy

```bash
# Docs
grep -rl agents-a1 docs/                       # expect 10, 29, 30
grep -n "get_limits" docs/30-config-opencode.md # expect a section
n=$(ls tests/e2e/*.bats | wc -l); grep -q "$n files" docs/09-testing-and-verification.md

# Tests — clean rebuild + full suite (CDP :9222 flaps in this env; core services OK,
# so run bats directly against the running container after `up -d`)
SKIP_CLEANUP=1 bash tests/run.sh   # or: rebuild, up -d, then `bats tests/e2e/`
bats tests/e2e/19-*.bats tests/e2e/26-*.bats tests/e2e/27-*.bats \
     tests/e2e/35-*.bats tests/e2e/36-*.bats   # affected + new
```

Definition of done: every success-criterion box checked and the full suite green.
