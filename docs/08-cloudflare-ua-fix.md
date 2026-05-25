# 08 — Cloudflare UA Fix

## What

A build-time `sed` patch that modifies the Hermes Agent's CustomProfile model provider to send a custom `User-Agent` HTTP header (`hermes-agent/1.0`) instead of the OpenAI Python SDK's default (`OpenAI/Python x.x.x`).

## Why

- The OpenAI Python SDK sends a `User-Agent` header like `OpenAI/Python 1.30.0`, which Cloudflare's WAF blocks on many LLM provider endpoints (especially those behind Cloudflare proxies like LiteLLM)
- Without the fix, LLM API calls return HTTP 403 from Cloudflare before reaching the actual provider
- The fix is applied at build time so it is deterministic and never needs runtime patching

## How

The patch is applied in the Dockerfile as a `RUN sed` command on the staged agent source.

### Patch command

```dockerfile
RUN sed -i 's/base_url="",/base_url="",\n    default_headers={"User-Agent": "hermes-agent\/1.0"},/' \
    /opt/hermes-agent-staging/plugins/model-providers/custom/__init__.py
```

### What it does

The `sed` command searches for the literal string `base_url="",` in the `CustomProfile` class definition and replaces it with the original line plus a new line that sets `default_headers`:

**Before:**
```python
class CustomProfile:
    def __init__(self, base_url="", ...
```

**After:**
```python
class CustomProfile:
    def __init__(self, base_url="",
        default_headers={"User-Agent": "hermes-agent/1.0"}, ...
```

### Verification in Dockerfile

The build includes a verification step that confirms the patch was applied:

```dockerfile
RUN grep -q '"User-Agent".*"hermes-agent' \
    /opt/hermes-agent-staging/plugins/model-providers/custom/__init__.py
```

If the `grep` fails (pattern not found), the build fails. This catches cases where the upstream `CustomProfile` class format changes and the sed no longer matches.

### Build-time vs runtime

The patch is applied to `/opt/hermes-agent-staging` during the Docker build. When the entrypoint copies the agent from staging to the bind mount, the patched version is copied. Subsequent container restarts use the already-patched version from the bind mount.

### Affected file

`/home/hermeswebui/.hermes/hermes-agent/plugins/model-providers/custom/__init__.py`

## Verification

```bash
docker exec <container> grep -A1 'base_url=""' \
  /home/hermeswebui/.hermes/hermes-agent/plugins/model-providers/custom/__init__.py | head -5
docker exec <container> grep -c 'User-Agent.*hermes-agent' \
  /home/hermeswebui/.hermes/hermes-agent/plugins/model-providers/custom/__init__.py
```

## What Works

- Patch applies cleanly on the current hermes-agent `main` branch
- Build fails if the sed pattern does not match, preventing silent failures
- The custom User-Agent header is sent on all LLM API requests through the CustomProfile provider
- HTTP 403 errors from Cloudflare are eliminated

## What Fails

- **Upstream format changes break the sed:** If the hermes-agent CustomProfile class changes the `base_url=""` line (different spacing, different parameter order, renamed parameter), the sed pattern no longer matches.
- **Patch does not affect non-CustomProfile providers:** If the agent uses a different provider (e.g., the built-in OpenAI provider), the default User-Agent is sent and Cloudflare may block the request.
- **Agent version updates require rebuild:** To get the patch applied to a newer agent version, the image must be rebuilt.

## Resolution

- The build-time verification step catches a broken sed pattern by failing the build. When upgrading `HERMES_AGENT_VERSION`, test the build locally first. If the sed fails, update the pattern to match the new CustomProfile format.
- The `litellm` custom provider defined in `config.yaml` uses the CustomProfile class, so all LLM calls through this provider include the patched User-Agent. The entrypoint sets `provider: litellm` in `config.yaml` by default.
- Rebuild the image with `docker compose build --build-arg HERMES_AGENT_VERSION=<new-version>` to update the agent and re-apply the patch.

## Verdict

The Cloudflare UA fix is a targeted, build-time patch with a verification safety net. It solves the immediate 403 problem for CustomProfile-based providers. The main risk is upstream format drift, which is mitigated by the build-time grep check.
