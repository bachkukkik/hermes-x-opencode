# 21 — Hermes Web Dashboard

## What

The Hermes web dashboard is a browser-based **machine-management UI** for the running Hermes agent instance, served on port `9119`. It is distinct from the WebUI chat frontend on `:8787`: where the WebUI is the user-facing chat surface, the dashboard is the operator surface for inspecting and managing Hermes configuration, API keys, skills, plugins, and sessions.

It is launched via the hermes CLI — `/app/venv/bin/hermes dashboard` — from the WebUI base image's venv (Installation A), exactly like the gateway. It is **opt-in** and disabled by default.

## Why

- **Operator visibility without `docker exec`.** Browse config, API keys, installed skills/plugins, and active sessions from a browser instead of dropping into the container shell.
- **Separation of concerns.** The chat surface (`:8787`) and the management surface (`:9119`) are independent services, so each can be enabled, published, and secured independently.
- **Fully opt-in.** When `HERMES_DASHBOARD_ENABLED` is unset/`false`, no process is started and the readiness probe is skipped — zero overhead, zero attack surface. This is the default.

## How

The dashboard runs via `hermes dashboard` using the hermes CLI from the WebUI's venv (`/app/venv/bin/hermes`). It is started by the entrypoint after the OpenCode serve block, from `lib/service-dashboard.sh`.

### Launch flags

```
/app/venv/bin/hermes dashboard --host <host> --port <port> --insecure --skip-build --no-open
```

- `--insecure` — **required** to bind to a non-localhost address. The container must bind `0.0.0.0` for the port to be reachable on the container network. `--insecure` is the CLI's explicit opt-in for non-loopback binding.
- `--skip-build` — serve a **pre-built** web `dist/` without running `npm`. See the dist prerequisite below.
- `--no-open` — do not attempt to launch a browser (irrelevant in a headless container).

### Restart-loop supervisor

The dashboard process is wrapped in a `while true` restart-loop supervisor (see `lib/service-dashboard.sh`), identical to the gateway pattern in `lib/service-gateway.sh`. If the dashboard exits for any reason, the loop automatically restarts it with a 2-second delay. Each restart event is logged to `${HERMES_HOME}/logs/dashboard-restart.log`; primary stdout/stderr goes to `${HERMES_HOME}/logs/dashboard-stdout.log`. Before launching, `start_dashboard()` creates and chowns the logs directory to `hermeswebui`.

### Configuration

| Variable | File | Default | Values / Notes |
|----------|------|---------|----------------|
| `HERMES_DASHBOARD_ENABLED` | `.env` | `false` | Set to `true` to start the dashboard. Disabled → no process, no probe. |
| `HERMES_DASHBOARD_PORT` | `.env` | `9119` | Internal listen port. Also in the compose `expose:` block. |
| `HERMES_DASHBOARD_HOST` | `.env` | `0.0.0.0` | Bind address. `0.0.0.0` is required for in-network reachability. |
| `HERMES_DASHBOARD_BOOT_TIMEOUT` | `.env` | `30` | Seconds the entrypoint readiness probe waits for the port. Non-fatal on timeout. |

Enable with:

```dotenv
HERMES_DASHBOARD_ENABLED=true
# Optional:
# HERMES_DASHBOARD_PORT=9119
# HERMES_DASHBOARD_HOST=0.0.0.0
# HERMES_DASHBOARD_BOOT_TIMEOUT=30
```

Changes require a container restart: `docker compose up -d`.

### Boot-time readiness probe

When enabled, the entrypoint runs a non-fatal readiness probe mirroring the OpenCode serve block:

```bash
start_dashboard
if [ "${HERMES_DASHBOARD_ENABLED:-false}" = "true" ]; then
    wait_for_port "${HERMES_DASHBOARD_PORT:-9119}" "${HERMES_DASHBOARD_BOOT_TIMEOUT:-30}" "hermes dashboard" || \
        echo "!! hermes dashboard did not become ready within ${HERMES_DASHBOARD_BOOT_TIMEOUT:-30}s; continuing."
fi
```

A timeout only logs a warning; it never aborts container startup.

## Verification

```bash
# Syntax check of the launcher.
bash -n volumes_hermes_opencode/build/scripts/lib/service-dashboard.sh

CONTAINER=$(docker compose ps -q hermes-opencode)

# Confirm the port is listening (run inside the container, where the port is bound).
docker exec "$CONTAINER" bash -lc 'cat < /dev/null > /dev/tcp/127.0.0.1/9119 && echo "port 9119 open"'

# Confirm it serves the UI (HTTP 200 + HTML), not an empty/404 response.
docker exec "$CONTAINER" curl -sI http://127.0.0.1:9119/ | head -1
```

## The web `dist/` prerequisite (IMPORTANT)

`hermes dashboard --skip-build` serves a **pre-built** web `dist/` and intentionally skips the `npm` build step (npm is not run at container boot). This means the dashboard will start a listening HTTP server regardless, but it will only serve a real UI **if a pre-built `dist/` is present** in the installed `hermes_agent` package under `/app/venv/`.

**What was verified at implementation time:** the live verification (running `hermes dashboard --skip-build` inside the container and checking for a `dist/`/`index.html`) **could not be executed in the task environment** — the required `docker exec` into the running container was not permitted. There is therefore no live evidence, in this repo, confirming that the base image's pip-installed `hermes_agent` ships a pre-built `dist/`.

**Why this matters:** the active runtime hermes-agent is pip-installed into `/app/venv/` by the base image `ghcr.io/nesquena/hermes-webui:latest` (see `01 — Hermes WebUI` and `16 — Agent Installation Architecture`). The dashboard frontend is an npm-built bundle; Python packages commonly ship Python source only and omit built frontends. If the `dist/` is absent, the server starts on `:9119` but serves no usable UI.

**Operator action:** after enabling, run the `curl -sI` check above. If the port is open but the body is empty / not HTML, a web `dist/` build is required. Building the dist (npm) is intentionally out of scope for this task — no Dockerfile/npm changes were made here. Until the dist is confirmed present, treat the dashboard as "server starts, UI not guaranteed."

## What Works

- Opt-in start/stop with a single env var; disabled by default with zero overhead
- Restart-loop supervisor auto-recovers from crashes with a 2-second backoff
- Non-fatal boot readiness probe that never blocks container startup
- Runs as `hermeswebui` via the same `/app/venv/bin/hermes` CLI + `su` pattern as the gateway
- Independent of the WebUI chat surface (`:8787`) — the two can be enabled and published separately
- `bash -n` syntax check passes on the launcher

## What Fails

- **UI may not serve without a pre-built `dist/`:** `--skip-build` only serves an existing `dist/`; if none ships with the pip package, the port listens but no UI renders. See the prerequisite section above.
- **`--insecure` binds the management surface on `0.0.0.0`:** the dashboard manages API keys and configuration. Binding it to the container network without an auth/termination layer in front is a credential-exposure risk. The compose file only `expose`s `9119` (intra-network), it does not publish it to the host by default.
- **No built-in auth:** like the WebUI, the dashboard has no default authentication. Network exposure must be controlled externally.
- **`HERMES_HOME` must be exported:** the dashboard reads config from `get_hermes_home()`. The entrypoint exports `HERMES_HOME=/home/hermeswebui/.hermes` (same requirement as the gateway).

## Resolution

- Leave `HERMES_DASHBOARD_ENABLED=false` (default) unless you need the management UI.
- Keep `9119` **internal-only** (`expose:`, not `ports:`). If you must publish it to the host, put it behind a reverse proxy with authentication/TLS — the dashboard manages API keys.
- After enabling, verify with `curl -sI http://127.0.0.1:9119/`. If the UI does not render, build/ship the web `dist/` (npm) — this is a separate task; no build changes were made here.

## Verdict

The dashboard is a useful operator surface and is wired to be safely opt-in: disabled by default, supervised by a restart loop, and probed non-fatally at boot. The one open dependency is the pre-built web `dist/` — because the live `--skip-build` check could not be run in this environment, confirm the `dist/` ships with the base image's `hermes_agent` before relying on the UI. Security-wise, the dashboard manages API keys, so it must stay internal-only or sit behind authenticated termination.
