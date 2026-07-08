# PRD Gap Analysis: Docs and Tests Coverage

## Executive Summary

The Hermes x OpenCode Docker Stack has **27 documentation files** and **24 e2e test files**, but there are significant gaps between the actual codebase (17 lib modules) and what is documented/tested.

## Gap Matrix

### Documentation Gaps

**Total Lib Modules:** 17
**Modules with Documentation:** 5 (29%)
**Modules without Documentation:** 12 (71%)

| Module | Status | Priority |
|--------|--------|----------|
| agent-setup.sh | ❌ Missing | HIGH |
| config-hermes.sh | ❌ Missing | HIGH |
| config-opencode.sh | ❌ Missing | HIGH |
| constants.sh | ❌ Missing | MEDIUM |
| mock-llm-server.sh | ❌ Missing | LOW |
| port-utils.sh | ❌ Missing | HIGH |
| profile-righthand-man.sh | ❌ Missing | MEDIUM |
| runtime-env.sh | ❌ Missing | HIGH |
| service-browser-vnc.sh | ❌ Missing | MEDIUM |
| service-dashboard.sh | ❌ Missing | LOW |
| service-gateway.sh | ❌ Missing | HIGH |
| service-opencode.sh | ❌ Missing | HIGH |
| validate-opencode.sh | ❌ Missing | MEDIUM |
| model-discovery.sh | ✅ Exists (10-model-discovery.md) | - |
| seed-volumes.sh | ✅ Exists (25-seed-volumes.md) | - |
| service-webui.sh | ✅ Exists (27-service-webui.md) | - |
| symlink-cleanup.sh | ✅ Exists (26-symlink-cleanup.md) | - |
| wiki-init.sh | ✅ Exists (17-wiki-init.md) | - |

### Test Coverage Gaps

**Total Lib Modules:** 17
**Modules with Tests:** 6 (35%)
**Modules without Tests:** 11 (65%)

| Module | Status | Priority |
|--------|--------|----------|
| agent-setup.sh | ❌ Missing | HIGH |
| config-hermes.sh | ❌ Missing | HIGH |
| config-opencode.sh | ❌ Missing | HIGH |
| constants.sh | ✅ Test 24 exists | - |
| mock-llm-server.sh | ❌ Missing | LOW |
| port-utils.sh | ✅ Test 23 exists | - |
| profile-righthand-man.sh | ❌ Missing | MEDIUM |
| runtime-env.sh | ❌ Missing | HIGH |
| service-browser-vnc.sh | ❌ Missing | MEDIUM |
| service-dashboard.sh | ❌ Missing | LOW |
| service-gateway.sh | ❌ Missing | HIGH |
| service-opencode.sh | ❌ Missing | HIGH |
| validate-opencode.sh | ❌ Missing | MEDIUM |
| model-discovery.sh | ❌ Missing | HIGH |
| seed-volumes.sh | ✅ Test 20 exists | - |
| service-webui.sh | ✅ Test 22 exists | - |
| symlink-cleanup.sh | ✅ Test 21 exists | - |
| wiki-init.sh | ✅ Test 14 exists | - |

## Root Cause Analysis

1. **Documentation is scattered and incomplete** - Only modules that were recently added or had specific issues got documented
2. **Test coverage is inconsistent** - Tests exist for some modules but not others, often based on when they were written
3. **No systematic documentation/testing process** - Each PR adds docs/tests ad-hoc without a checklist

## Success Criteria

### Documentation Goals
- [ ] All 17 lib modules have corresponding documentation in docs/
- [ ] Each doc follows the project's existing style (numbered, consistent format)
- [ ] Each doc includes: purpose, key variables/functions, usage patterns, troubleshooting

### Test Coverage Goals
- [ ] All 17 lib modules have corresponding e2e tests in tests/e2e/
- [ ] Each test verifies the module's core functionality
- [ ] Test numbering follows existing convention (00-24, continue from 25)

### Integration Goals
- [ ] Graphify-out regenerated to reflect all changes
- [ ] LLM wiki updated with new architectural insights
- [ ] PRD.md updated to reflect current state (if needed)

## Verification Policy

**Documentation Verification:**
```bash
for module in agent-setup config-hermes config-opencode constants mock-llm-server port-utils profile-righthand-man runtime-env service-browser-vnc service-dashboard service-gateway service-opencode validate-opencode model-discovery; do
  test -f docs/${module}.md && echo "✅ $module documented" || echo "❌ $module NOT documented"
done
```

**Test Verification:**
```bash
for module in agent-setup config-hermes config-opencode constants mock-llm-server port-utils profile-righthand-man runtime-env service-browser-vnc service-dashboard service-gateway service-opencode validate-opencode model-discovery; do
  test -f tests/e2e/XX-${module}.bats && echo "✅ $module tested" || echo "❌ $module NOT tested"
done
```

## Recommended PR Strategy

**Phase 1: Critical Documentation (HIGH priority)**
- Create docs for: agent-setup.sh, config-hermes.sh, config-opencode.sh, port-utils.sh, runtime-env.sh, service-gateway.sh, service-opencode.sh
- These are core startup and configuration modules

**Phase 2: Critical Tests (HIGH priority)**
- Create tests for: agent-setup.sh, config-hermes.sh, config-opencode.sh, port-utils.sh, runtime-env.sh, service-gateway.sh, service-opencode.sh, model-discovery.sh
- Focus on modules that are critical to startup and configuration

**Phase 3: Medium Priority**
- Profile-righthand-man.sh (doc + test)
- validate-opencode.sh (doc + test)
- service-browser-vnc.sh (doc + test)

**Phase 4: Low Priority**
- mock-llm-server.sh (doc + test)
- service-dashboard.sh (doc + test)

## Notes

- This analysis is based on the current state of the repository
- Some modules may have overlapping functionality, allowing combined documentation/tests
- The existing docs/ and tests/ numbering should be preserved where possible
