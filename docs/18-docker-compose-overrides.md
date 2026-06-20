# 18 — Docker Compose Overrides

## What

Two Docker Compose override files extend the base `docker-compose.yml` for specific deployment contexts: reverse-proxy networking (Cloudflare/Traefik) and CI port publishing.

## Why

- The base `docker-compose.yml` uses `expose` only (no host port mapping), keeping production deployments flexible
- Different environments need different networking: production uses a reverse proxy network, CI needs direct host ports
- Override files follow Docker Compose's standard merge convention (`docker-compose.override.yml` is auto-loaded)

## How

### docker-compose.override.yml (Cloudflare/Traefik)

Auto-loaded by `docker compose up` (Docker Compose convention). Attaches the container to an external Cloudflare/Traefik reverse proxy network:

```yaml
services:
  hermes-opencode:
    networks:
      cloudflare:
        aliases:
          - vanilla-hermes-opencode

networks:
  cloudflare:
    name: portainer-cloudflare-traefik_default
    external: true
```

| Key | Value | Purpose |
|-----|-------|---------|
| `networks.cloudflare` | External network | Joins the container to the existing Traefik network managed by Portainer |
| `aliases` | `vanilla-hermes-opencode` | DNS alias for the container within the Traefik network |
| `name` | `portainer-cloudflare-traefik_default` | Matches the exact Docker network name created by the Portainer/Traefik stack |

**Usage:** No special flags needed — `docker compose up -d` auto-merges this file. To skip the override (e.g., for local testing), run `docker compose -f docker-compose.yml up -d`.

### docker-compose.ci.yml (CI Port Publishing)

**Not** auto-loaded. Must be explicitly specified with `-f`. Publishes host ports for E2E test access:

```yaml
services:
  hermes-opencode:
    ports:
      - "${HERMES_WEBUI_PORT:-8787}:8787"
      - "${HERMES_API_PORT:-8642}:8642"
      - "${OPENCODE_SERVE_PORT:-4096}:4096"
      - "${CHROME_CDP_PORT:-9222}:9222"
```

| Port | Env var default | Service |
|------|-----------------|---------|
| `8787` | `HERMES_WEBUI_PORT` | Hermes WebUI |
| `8642` | `HERMES_API_PORT` | Hermes Agent Gateway |
| `4096` | `OPENCODE_SERVE_PORT` | OpenCode Serve |
| `9222` | `CHROME_CDP_PORT` | Chromium CDP (browser human-in-the-loop) |

**Usage:**

```bash
# CI: explicit dual-file invocation
docker compose -f docker-compose.yml -f docker-compose.ci.yml up -d

# Local development (no port publishing, access via docker exec only)
docker compose up -d

# Production (auto-loads override for Traefik networking)
docker compose up -d
```

## Verification

```bash
# Verify CI ports are published
docker compose -f docker-compose.yml -f docker-compose.ci.yml config | grep -A5 "ports:"

# Verify override network is attached
docker compose config | grep -A3 "cloudflare"
```

## What Works

- Override file convention keeps environment-specific config out of the base compose file
- CI file is explicit opt-in, preventing unwanted port exposure in production
- Traefik override is auto-loaded for zero-config production deployments

## What Fails

- **Override auto-loading can surprise local devs:** Running `docker compose up -d` on a developer machine without Traefik running will fail because the external network does not exist. Use `docker compose -f docker-compose.yml up -d` to skip the override.
- **No validation of network existence:** If the `portainer-cloudflare-traefik_default` network doesn't exist, `docker compose up` fails with a clear error.

## Resolution

- For local development without Traefik, either delete/rename `docker-compose.override.yml` or use the explicit `-f docker-compose.yml` form.
- The CI override is safe to include unconditionally in CI pipelines — it only adds port mappings.

## Verdict

Two focused override files cover the two non-default deployment patterns. The Cloudflare/Traefik override is auto-loaded for production convenience; the CI override is explicit opt-in for test isolation. The main friction is the auto-loading behavior catching local developers without a Traefik network.
