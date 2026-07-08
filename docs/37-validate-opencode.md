# 37 — Validate OpenCode Zen Key

## What

`lib/validate-opencode.sh` provides a single function `validate_opencode_zen_key()` that tests the `OPENCODE_ZEN_API_KEY` against the Zen API at startup.

## Why

- Catches invalid keys immediately rather than failing silently during use
- Helpful message points to sign-up URL when validation fails
- When key is unset, informational message explains free models use a public fallback

## How

### `validate_opencode_zen_key()`

1. **Empty key** — Logs info, returns 0
2. **API call** — `curl -sf https://opencode.ai/zen/v1/models` with Bearer token
3. **Failure** — Warning with sign-up URL, returns 1
4. **Success** — Logs model count from Zen API
