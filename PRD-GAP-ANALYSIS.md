# PRD: Feature Parity with Downstream hermes-x-opencode--host-machine (PRs #22, #23)

## Executive Summary

This PRD documents the gap analysis and implementation plan to bring the `hermes-x-opencode` repository into feature parity with the downstream `hermes-x-opencode--host-machine` repo, specifically porting the changes from PR #22 and PR #23.

**Gap**: The current `hermes-x-opencode` repository lacks two critical features from the downstream host-machine repo:
1. **PR #22**: Inline OPENAI_API_KEY resolution at generation time
2. **PR #23**: Managed dcp.jsonc generation with per-model compression thresholds

**Impact**: Without these features, users experience authentication errors and suboptimal context compression behavior on 1M-context models.

---

## Problem Triage

### Issue 1: PR #22 - Inline OPENAI_API_KEY Resolution

**Problem Statement**: 
OpenCode does not auto-load a project `.env`. The generator hardcoded `provider.litellm`/`llama_cpp` `apiKey` to the `"{env:OPENAI_API_KEY}"` placeholder, so launching `opencode` from any shell without `OPENAI_API_KEY` exported resolved it to empty → `Authentication Error, No api key passed in.` The `auth.json` fallback does not rescue this — the config's empty `{env:}` value overrides it.

**Root Cause**: 
- The generator writes `"{env:OPENAI_API_KEY}"` as the `apiKey` in both `provider.litellm.options` and `provider.llama_cpp.options`
- When `OPENAI_API_KEY` is not exported in the current shell, the `{env:}` placeholder resolves to an empty string
- The empty string takes precedence over `auth.json` fallback credentials

**Solution**: 
Resolve the credential at generation time: when `OPENAI_API_KEY` is present in the generator's environment (`generate.sh` already sources `.env` and exports it), inline the literal key so opencode works in any shell/dir with no runtime env dependency. Fall back to the `{env:OPENAI_API_KEY}` placeholder when the key is absent, preserving the original contract.

**Files Modified**:
- `lib/config-opencode.sh` (Python block: resolve `_openai_key` and use it)
- `tests/e2e/03-config-validity.bats` (update assertion)
- `tests/e2e/23-multi-provider-model.bats` (update assertions)

---

### Issue 2: PR #23 - Managed dcp.jsonc with Per-Model Compression Thresholds

**Problem Statement**: 
OpenCode kept compressing context at ~100k tokens even on a 1M-context model (`opencode-go/deepseek-v4-pro`). Root cause: the always-installed `@tarquinen/opencode-dcp` plugin defaults `compress.maxContextLimit` to a **hard 100,000 tokens**, independent of the model's real window — so a 1M model gets compression-nudged at ~10% fill. DCP reads its own `dcp.jsonc` (not `opencode.jsonc`), so the generator never influenced it.

**Root Cause**: 
- DCP plugin has a hardcoded 100k token limit regardless of model context window
- The generator did not produce a managed `dcp.jsonc` file
- Users had no way to configure compression thresholds relative to model context size

**Solution**: 
DCP's schema accepts `"X%"` strings for `compress.maxContextLimit`/`minContextLimit` that it resolves against **each active model's real context window**. The generator now emits a managed `~/.config/opencode/dcp.jsonc` pinning those thresholds as a percentage, driven by a new `OPENCODE_COMPRESSION_THRESHOLD` env var (default `0.76`, mirroring `HERMES_COMPRESSION_THRESHOLD`). One setting adapts to every model.

**Files Modified**:
- `lib/constants.sh` (add `OPENCODE_DCP_CONFIG`, `STAGING_DCP`, `OPENCODE_COMPRESSION_THRESHOLD`)
- `lib/config-opencode.sh` (add `generate_dcp_staging()` function)
- `generate.sh` (invoke DCP generation, integrate into apply/validation loops)
- `.env.example` (document `OPENCODE_COMPRESSION_THRESHOLD`)
- `README.md` (document `OPENCODE_COMPRESSION_THRESHOLD`)
- `tests/e2e/26-dcp-config.bats` (new test file with 4 tests)

---

## Success Criteria

### PR #22 Success Criteria

**SC22.1**: After `generate.sh --apply`, the staging `opencode.jsonc` contains:
- `provider.litellm.options.apiKey` = literal `sk-...` key (not `{env:...}`)
- `provider.llama_cpp.options.apiKey` = literal `sk-...` key (not `{env:...}`)

**SC22.2**: After `generate.sh --apply` with no `OPENAI_API_KEY` in environment:
- Both keys revert to `{env:OPENAI_API_KEY}` placeholder

**SC22.3**: `opencode run` works from any shell without prior `export OPENAI_API_KEY`

**SC22.4**: All existing tests pass (117/117 green)

---

### PR #23 Success Criteria

**SC23.1**: After `generate.sh --apply`, `~/.config/opencode/dcp.jsonc` exists with:
- `compress.maxContextLimit: "76%"`
- `compress.minContextLimit: "38%"`
- `$schema` preserved

**SC23.2**: Setting `OPENCODE_COMPRESSION_THRESHOLD=0.9` produces:
- `compress.maxContextLimit: "90%"`
- `compress.minContextLimit: "45%"`

**SC23.3**: Existing `dcp.jsonc` keys are preserved (surgical merge)

**SC23.4**: Out-of-range threshold (e.g., 1.5) clamps to default 0.76

**SC23.5**: DCP respects per-model context windows (1M model compresses at 760k, not 100k)

**SC23.6**: All existing tests pass + 4 new tests green (117/117 total)

---

## Verification Policy

### Pre-Flight Checks

1. **Baseline test suite**: Run `bats tests/e2e/*.bats` and capture baseline failures
2. **Git status**: Ensure clean working tree before starting
3. **Skill verification**: Confirm `opencode-plan-build-orchestrator` and `karpathy-guidelines` are loadable

### Phase 1: Code Changes

**Verification Commands**:

```bash
# Check PR #22 changes
grep -n "OPENAI_API_KEY" volumes_hermes_opencode/build/scripts/lib/config-opencode.sh
grep -n "dcp.jsonc" volumes_hermes_opencode/build/scripts/lib/config-opencode.sh

# Check PR #23 changes
grep -n "OPENCODE_COMPRESSION_THRESHOLD" lib/constants.sh
grep -n "generate_dcp_staging" lib/config-opencode.sh

# Syntax checks
bash -n generate.sh
bash -n lib/constants.sh
bash -n lib/config-opencode.sh
```

### Phase 2: Test Suite

```bash
# Run full e2e suite
bash tests/run.sh

# Expected: 117/117 tests pass (113 existing + 4 new DCP tests)
```

### Phase 3: Functional Verification

```bash
# Test PR #22: inline key
export OPENAI_API_KEY="sk-test123"
bash generate.sh --dry-run
grep -q '"apiKey": "sk-test123"' staging/opencode.jsonc

# Test PR #23: dcp.jsonc thresholds
bash generate.sh --dry-run
python3 -c "import json; d=json.load(open('staging/dcp.jsonc')); assert d['compress']['maxContextLimit']=='76%'"
```

### Phase 4: Regression Testing

- Verify all existing tests still pass
- Check that no other functionality regressed
- Validate that `--apply` works correctly with new files

---

## Implementation Plan

### Task 1: Port PR #22 (Inline OPENAI_API_KEY)

**Files to Modify**:
1. `volumes_hermes_opencode/build/scripts/lib/config-opencode.sh` - Add `_openai_key` resolution and update provider blocks
2. `tests/e2e/03-config-validity.bats` - Update test assertions (if needed for this Docker stack)
3. `tests/e2e/23-multi-provider-model.bats` - Update test assertions (if needed for this Docker stack)

**Expected Changes**:
- +14/-6 lines in config-opencode.sh
- Test updates (if applicable)

### Task 2: Port PR #23 (DCP Config Generation)

**Files to Modify**:
1. `volumes_hermes_opencode/build/scripts/lib/constants.sh` - Add `OPENCODE_DCP_CONFIG`, `STAGING_DCP`, `OPENCODE_COMPRESSION_THRESHOLD`
2. `volumes_hermes_opencode/build/scripts/lib/config-opencode.sh` - Add `generate_dcp_staging()` function
3. `volumes_hermes_opencode/build/scripts/entrypoint.sh` - Call `generate_dcp_staging`
4. `.env.example` - Document `OPENCODE_COMPRESSION_THRESHOLD`
5. `README.md` - Document `OPENCODE_COMPRESSION_THRESHOLD`
6. `tests/e2e/37-dcp-config.bats` - Already exists, covers DCP functionality

**Expected Changes**:
- +11/-0 in constants.sh
- +106/-0 in config-opencode.sh
- +1 in entrypoint.sh
- +8/-0 in .env.example
- +1/-0 in README.md
- 37-dcp-config.bats already exists (covers DCP tests)

**Note**: This Docker stack repo does NOT have a standalone `generate.sh` file. Config generation is integrated into the container entrypoint script (`entrypoint.sh`). The downstream host-machine repo has a separate `generate.sh`, but the changes are ported to the embedded scripts in this Docker stack.

---

## Risk Assessment

**High Risk**:
- Modifying `config-opencode.sh` affects both OpenCode and Hermes config generation
- DCP integration may impact existing `opencode.jsonc` structure

**Mitigation**:
- Use surgical patches, not full rewrites
- Run full test suite after each change
- Keep changes minimal and focused

**Testing Strategy**:
- Run existing tests before and after each modification
- Add new tests to guard against regressions
- Verify with dry-run before actual apply

---

## Appendix: Reference Diff Sources

- PR #22: https://github.com/bachkukkik/hermes-x-opencode--host-machine/pull/22
- PR #23: https://github.com/bachkukkik/hermes-x-opencode--host-machine/pull/23

**Downstream Commit SHAs**:
- PR #22: `4a1bf2f`
- PR #23: `bf952f5`

---

**Status**: Ready for Implementation
**Priority**: High (affects user experience and functionality)
**Estimate**: 2-4 hours for full porting and verification
