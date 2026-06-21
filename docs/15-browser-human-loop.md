# 15 — Browser Human-in-the-Loop

## What

A viewable and interactive Chromium browser running inside the `hermes-opencode` container that both the Hermes Agent (via Chrome DevTools Protocol) and a human operator (via a web-based VNC client) can share. It is **opt-in** — disabled by default — and toggled by a single environment variable.

## Why

- Lets the agent browse authenticated / JS-heavy / CAPTCHA-protected pages that pure HTTP fetching cannot reach
- Lets a human complete logins, solve CAPTCHAs, and inspect the agent's browsing session live through a web browser
- Keeps cookies, localStorage, and login state across container restarts via the existing `/home/hermeswebui/.hermes` bind mount
- Zero host-side installation: open a URL in any browser, type the VNC password, and you're driving the same Chromium the agent drives

## How

The browser stack is started by the entrypoint after the WebUI becomes healthy but before the Hermes Gateway starts. It is controlled by the `BROWSER_HUMAN_LOOP_ENABLED` environment variable (default: `false`).

```
Container: hermes-opencode
├── Hermes WebUI    :8787
├── Hermes Gateway  :8642
├── OpenCode Serve  :4096 (optional)
├── Xvfb            :99   (virtual display, internal only)
├── x11vnc          :5900 (VNC server, internal only)
├── websockify+noVNC:6901 (browser-accessible VNC, EXPOSED)
└── Chromium CDP    :9222 (internal — Hermes attaches here)
```

| Parameter | Value | Notes |
|-----------|-------|-------|
| Master toggle | `BROWSER_HUMAN_LOOP_ENABLED=true` | Required to start the stack (default: `false`) |
| VNC host port | `${BROWSER_VNC_PORT:-6901}` | Configurable via `.env` |
| VNC password | `BROWSER_VNC_PASSWORD` env var | Defaults to `hermes` if empty |
| CDP URL (internal) | `http://127.0.0.1:9222` | Written to `config.yaml` as `browser.cdp_url` |
| Chromium user data dir | `/home/hermeswebui/.hermes/chrome-debug` | Persisted via bind mount |
| Xvfb display | `:99` at `1280x720x24` | Hardcoded; non-overridable |
| Run user | `hermeswebui` (UID 1000) | All X servers, Chromium, VNC run via `su` from root entrypoint |
| noVNC web assets | `/usr/share/novnc/` | Served by `websockify --web` |

### Start sequence (inside `entrypoint.sh`)

1. `mkdir -p /home/hermeswebui/.hermes/chrome-debug` (chown to `hermeswebui`)
2. `Xvfb :99 -screen 0 1280x720x24 ...` as `hermeswebui` (background)
3. `export DISPLAY=:99` then brief `sleep 1` for X readiness
4. `openbox` (background, X window manager — Chromium needs one)
5. `rm -f /tmp/.vnc_passwd` (removes stale password file from prior container starts that can cause Permission denied), then `x11vnc -storepasswd "$BROWSER_VNC_PASSWORD" /tmp/.vnc_passwd`, then `chown hermeswebui`
6. `x11vnc -display :99 -rfbport 5900 -rfbauth /tmp/.vnc_passwd -forever -shared` (background)
7. `websockify 6901 localhost:5900 --web=/usr/share/novnc` (background)
8. `chromium --remote-debugging-port=9222 --user-data-dir=... --no-sandbox ...` as `hermeswebui` (background)
9. `wait_for_port 9222 30 "chromium CDP"` — blocks until CDP endpoint responds (30s timeout, non-fatal; logs warning if timeout, then proceeds)

Process logs land in `/home/hermeswebui/.hermes/logs/` (`xvfb.log`, `openbox.log`, `x11vnc.log`, `websockify.log`, `chromium.log`).

### How Hermes attaches

When `BROWSER_HUMAN_LOOP_ENABLED=true`, the entrypoint's `generate_config()` function injects the following block into `config.yaml`:

```yaml
browser:
  cdp_url: http://127.0.0.1:9222
```

The Hermes Agent reads `browser.cdp_url` at runtime and connects to Chromium's DevTools endpoint over the loopback interface. Both the agent and the human VNC viewer see the same tabs, cookies, and localStorage.

## Usage

1. Set in `.env`:

   ```
   BROWSER_HUMAN_LOOP_ENABLED=true
   BROWSER_VNC_PASSWORD=changeme   # optional, defaults to "hermes"
   ```

2. Rebuild / restart the stack:

   ```bash
   docker compose up -d
   ```

3. Open the noVNC web client in your browser:

   ```
   http://<host>:6901/vnc.html
   ```

4. Enter the VNC password when prompted. You'll see Chromium running on the Xvfb display.

5. Use Chromium normally. Logins, cookies, and CAPTCHAs persist in `/home/hermeswebui/.hermes/chrome-debug/` across container restarts.

## Verification

```bash
CONTAINER=$(docker compose ps -q hermes-opencode)

# noVNC port accepts TCP
docker exec "$CONTAINER" bash -c 'echo > /dev/tcp/127.0.0.1/6901'

# x11vnc port accepts TCP
docker exec "$CONTAINER" bash -c 'echo > /dev/tcp/127.0.0.1/5900'

# Chromium CDP endpoint returns JSON
docker exec "$CONTAINER" curl -sf http://127.0.0.1:9222/json/version | python3 -m json.tool

# config.yaml contains browser.cdp_url
docker exec "$CONTAINER" grep -A1 '^browser:' /home/hermeswebui/.hermes/config.yaml
```

## Troubleshooting

### CDP connection refused

**Symptom:** The agent logs `All CDP discovery methods failed for 127.0.0.1:9222` (or similar "connection refused" errors).

**What it means:** Hermes tried to attach to Chromium's DevTools endpoint before Chromium finished initializing, or Chromium never started at all.

**How to diagnose:**
1. Check that the flag is actually set:

   ```bash
   docker exec hermes-opencode env | grep BROWSER_HUMAN_LOOP_ENABLED
   ```

   If the output is missing or shows `false`, the browser stack never launched.

2. Check whether Chromium is running:

   ```bash
   docker exec hermes-opencode ps aux | grep chromium
   ```

   If nothing shows up, Chromium crashed — inspect `/home/hermeswebui/.hermes/logs/chromium.log`.

3. Check whether the CDP endpoint is listening:

   ```bash
   docker exec hermes-opencode curl -sf http://127.0.0.1:9222/json/version
   ```

   A JSON response with a `Browser` field means CDP is up. A connection error means it is not.

**Boot-time race (most common):** Before the readiness-wait fix, this error appeared intermittently on fast-start containers because Chromium needs ~3–10 seconds to spin up its CDP server after the process launches. The entrypoint now blocks on `wait_for_port 9222 30` after starting Chromium, so the gateway does not start until CDP responds.

---

### Container marked unhealthy due to CDP failure

**Symptom:** `docker compose ps` shows `unhealthy` for `hermes-opencode`.

**What it means:** When `BROWSER_HUMAN_LOOP_ENABLED=true`, the healthcheck runs:

```bash
curl -sf --max-time 3 http://127.0.0.1:9222/json/version
```

If this fails (Chromium exited, crashed, or is stuck), the container is marked unhealthy. This detects situations where the browser stack silently dies after boot — e.g., a segfault, OOM kill, or sandbox crash.

**How to diagnose:**
1. Check the healthcheck logs:

   ```bash
   docker inspect --format='{{json .State.Health}}' hermes-opencode | python3 -m json.tool
   ```

2. Look at Chromium's crash log:

   ```bash
   docker exec hermes-opencode tail -50 /home/hermeswebui/.hermes/logs/chromium.log
   ```

3. Check system-level reasons (OOM, disk full, etc.):

   ```bash
   docker exec hermes-opencode dmesg | tail -20
   ```

---

### Chromium startup timeout (30-second wait exceeded)

**Symptom:** Entrypoint log shows `WARN: chromium CDP port 9222 not ready after 30s` but the container still starts.

**What it means:** The `wait_for_port` probe did not see CDP respond within 30 seconds. This is **non-fatal** — the entrypoint logs the warning and proceeds to start the gateway anyway. The agent will attempt its own CDP connection retry loop after boot.

**When this happens:**
- Cold start on slow disk (Chrome user-data-dir first-time setup, profile creation, etc.)
- Resource-constrained hosts (low CPU/RAM, heavy Docker overhead)
- Chromium stuck on an update or profile migration

**What to do:**
- Check `chromium.log` for startup errors or long stalls.
- If this is a one-off on first boot, ignore it — subsequent boots are typically much faster once the profile is warm.
- If it persists, consider increasing the timeout by modifying the `wait_for_port` call in `scripts/entrypoint.sh` (change `30` to a larger value).

## What Works

- Browser stack starts within 5 seconds after the WebUI is healthy (before the gateway starts)
- Boot-time CDP readiness wait (`wait_for_port 9222 30`) ensures the agent never tries to connect before Chromium is ready
- Healthcheck validates CDP endpoint — container marked unhealthy if Chromium crashes after boot
- noVNC web client accessible from any modern browser at `:6901/vnc.html`
- Chromium CDP endpoint responds on `127.0.0.1:9222` and the agent attaches via `browser.cdp_url`
- Cookies, localStorage, and login state persist across container restarts via the bind-mounted user-data-dir
- All processes (Xvfb, openbox, x11vnc, websockify, chromium) run as `hermeswebui` user (UID 1000) — not root
- When disabled (`BROWSER_HUMAN_LOOP_ENABLED=false`, the default), no processes start, no port is opened, and `config.yaml` contains no `browser:` block — identical to the pre-feature container

## What Fails

- **Default VNC password is weak:** If `BROWSER_VNC_PASSWORD` is unset, it defaults to `hermes`. Anyone with network access to port 6901 can drive the browser. Always set a strong password when exposing port 6901.
- **Chromium crashes without `--no-sandbox`:** The container runs as non-root but without a privileged sandbox, so `--no-sandbox` is mandatory. Without it Chromium exits immediately with `Operation not permitted`.
- **noVNC asset path varies by Debian release:** The Dockerfile installs the `novnc` Debian package which usually installs assets to `/usr/share/novnc/`. If the package layout changes, websockify will start without serving the web client. The entrypoint logs a warning (`!! noVNC assets not found at ...`) and falls back to plain WebSocket proxying.
- **Display :99 collision:** Hardcoded. If anything else on the container is using display :99, Xvfb will fail to start.
- **`config.yaml` regeneration overwrites manual edits:** As with the rest of the config, the `browser.cdp_url` block is regenerated from the environment on every boot. Manual edits inside the container are lost on restart.

## Resolution

- Set `BROWSER_VNC_PASSWORD` to a strong secret in `.env` before exposing port 6901 beyond localhost.
- The `--no-sandbox` flag is included in the entrypoint — no user action needed.
- If `websockify` starts but the noVNC web client does not load, inspect the Dockerfile's `novnc` package version and confirm `/usr/share/novnc/vnc.html` exists. If the Debian package renames the path, update the `novnc_dir` variable in `scripts/entrypoint.sh` (`start_browser_vnc` function).
- Display :99 is reserved by convention for this feature — do not start other X servers inside the container.

## Verdict

The human-in-the-loop browser gives the agent eyes and fingers for the parts of the web that defeat headless HTTP fetching, while letting a human jump in for the unscriptable moments (login, CAPTCHA, age gate, payment). Disabling the feature is a single env var, leaving the container byte-for-byte equivalent to before. Running the entire X/VNC/Chromium stack as UID 1000 keeps the filesystem blast radius small.
