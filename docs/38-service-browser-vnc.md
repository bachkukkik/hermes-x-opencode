# 38 — Browser/VNC Human-in-the-Loop

## What

`lib/service-browser-vnc.sh` provides `start_browser_vnc()` that launches the full browser human-in-the-loop stack: Xvfb, openbox, x11vnc, websockify + noVNC, and Chromium with CDP on port 9222.

## Why

- Enables agent visual browser use with human observation/intervention via VNC
- All processes run as `hermeswebui` for consistent permissions
- Stale lockfiles cleaned up before Chromium launches
- Opt-in via `BROWSER_HUMAN_LOOP_ENABLED=true`

## Component Stack

| Component | Port/Display | Purpose |
|-----------|-------------|---------|
| Xvfb | `:99` | Virtual framebuffer |
| openbox | `:99` | Window manager |
| x11vnc | `5900` | VNC server |
| websockify | `6901` | WebSocket bridge |
| Chromium | `9222` | CDP remote debugging |
