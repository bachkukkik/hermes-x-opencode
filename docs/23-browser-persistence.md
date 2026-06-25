# 23 — Browser State Persistence

## What

Browser state — cookies, localStorage, sessions, and Chromium profiles — persists across Docker redeployments (`docker compose down && docker compose up -d`) via the bind-mounted `hermes-home` volume. Chromium's `--user-data-dir` points to a directory on that mount, so all persistent browser data lives on the host filesystem and survives container destruction.

## Why

Users can revisit authenticated websites without re-logging in after a container restart. Once a human operator completes a login or CAPTCHA challenge through the noVNC interface, those credentials and session tokens remain available to the Hermes Agent across redeployments. This makes the browser human-in-the-loop workflow practical for long-running, multi-session tasks.

## How

Chromium is launched with:

```
--user-data-dir=/home/hermeswebui/.hermes/chrome-debug
```

The `/home/hermeswebui/.hermes` directory lives on the bind mount at `./volumes_hermes_opencode/data/hermes-home` (or whichever host path is configured as the `hermes-home` volume in `docker-compose.yml`). Because this is a Docker **bind mount**, not a container-local overlayfs layer, the data outlives the container.

The directory tree that accumulates inside `chrome-debug/` includes:

```
chrome-debug/
├── Default/
│   ├── Cookies          ← HTTP cookies (login sessions, preferences)
│   ├── Login Data       ← saved passwords (if Chrome sync is disabled, this is local-only)
│   ├── Preferences      ← browser settings, homepage, search engine
│   ├── History           ← browsing history
│   ├── Bookmarks
│   ├── Extensions/       ← installed extensions and their state
│   ├── Local Storage/    ← leveldb stores for `localStorage` API
│   │   └── leveldb/
│   ├── Session Storage/  ← `sessionStorage` (if persistent; otherwise ephemeral)
│   ├── Service Worker/   ← registered service workers and Cache API
│   └── IndexedDB/        ← IndexedDB databases
├── GrShaderCache/
├── ShaderCache/
├── Local State           ← browser-wide settings, incognito flag, etc.
└── SingletonLock         ← removed on each start (see Lockfile cleanup below)
```

## What survives

| Data | Survives redeploy? | Notes |
|------|--------------------|-------|
| Cookies (HTTP) | ✅ Yes | Stored in `Default/Cookies` (SQLite) |
| localStorage | ✅ Yes | `Default/Local Storage/leveldb/` |
| sessionStorage | ⚠️ Partial | Chromium may clear on restart; relies on `--restore-last-session` flag which is not used |
| Browser profile (extensions, bookmarks, history) | ✅ Yes | Full `Default/` directory |
| Saved passwords | ✅ Yes (local) | `Default/Login Data` — available if Chrome sync not configured |
| Open tabs | ❌ No | Chromium starts with a blank new-tab page each boot |
| In-flight downloads | ❌ No | Downloads not completed before shutdown are lost |
| Clipboard contents | ❌ No | X11 clipboard is per-session, destroyed with Xvfb |

## Lockfile cleanup

On each container start, `service-browser-vnc.sh` removes Chromium's singleton lock files before launching the browser:

```bash
rm -f "${CHROME_USER_DATA}/SingletonLock" \
      "${CHROME_USER_DATA}/SingletonCookie" \
      "${CHROME_USER_DATA}/SingletonSocket"
```

These lockfiles are left behind if Chromium exits uncleanly (e.g., `docker compose down` without a graceful shutdown). Removing them is **safe and non-destructive** — it does not delete any user data. It simply allows Chromium to start fresh, acquiring a new singleton lock for the new process.

## Security note

The `chrome-debug/` directory on the host filesystem contains the user's full browser profile — cookies, localStorage, saved passwords, browsing history. Anyone with filesystem access to the `./volumes_hermes_opencode/data/hermes-home/` path can extract these. This is the intended trade-off for persistence. If you need to purge all browser state, see [Clearing state deliberately](#clearing-state-deliberately) below.

## Verification steps

### 1. Confirm the user-data-dir is on the bind mount

```bash
CONTAINER=$(docker compose ps -q hermes-opencode)

# The directory must exist and contain a Default/ subdirectory
docker exec "$CONTAINER" test -d /home/hermeswebui/.hermes/chrome-debug/Default

# The directory must be writable
docker exec "$CONTAINER" touch /home/hermeswebui/.hermes/chrome-debug/.write_test
docker exec "$CONTAINER" rm -f /home/hermeswebui/.hermes/chrome-debug/.write_test
```

### 2. Verify Cookies file exists (pre-restart)

```bash
docker exec "$CONTAINER" ls -la /home/hermeswebui/.hermes/chrome-debug/Default/Cookies
```

### 3. Restart the container and verify Cookies survive

```bash
# Note the container ID
CID_BEFORE=$(docker compose ps -q hermes-opencode)

# Restart
docker compose down
docker compose up -d

# Wait for health
sleep 5

# Cookies file must still exist
CID_AFTER=$(docker compose ps -q hermes-opencode)
docker exec "$CID_AFTER" ls -la /home/hermeswebui/.hermes/chrome-debug/Default/Cookies
```

### 4. Confirm lockfiles are cleaned up on start

```bash
# SingletonLock must NOT exist after container start
docker exec "$CONTAINER" test -f /home/hermeswebui/.hermes/chrome-debug/SingletonLock
# Expected: exit code 1 (file not found)
```

### 5. Check that Local Storage directory is intact

```bash
docker exec "$CONTAINER" ls /home/hermeswebui/.hermes/chrome-debug/Default/Local\ Storage/
```

## Troubleshooting

### Corrupted profile (Chromium crashes on start, blank windows, or "Profile error" dialogs)

**Symptom:** Chromium fails to start, displays an "Aw, Snap!" page, shows a profile corruption dialog, or the VNC screen is blank/black.

**Root cause:** The `chrome-debug/` directory on the bind mount may have been corrupted by an unclean shutdown at the filesystem level (host power loss, NFS interruption, etc.).

**Fix:** Delete the profile directory and restart. This **will** lose all cookies, localStorage, and saved passwords — treat it as a last resort.

```bash
docker compose down
rm -rf ./volumes_hermes_opencode/data/hermes-home/chrome-debug/
docker compose up -d
```

After restart, Chromium creates a fresh profile. You'll need to re-authenticate on any sites.

### Clearing state deliberately

To intentionally wipe all browser state (for security or a clean-slate test):

```bash
docker compose down
rm -rf ./volumes_hermes_opencode/data/hermes-home/chrome-debug/
docker compose up -d
```

To wipe only cookies while keeping extensions and bookmarks:

```bash
docker compose down
rm -f ./volumes_hermes_opencode/data/hermes-home/chrome-debug/Default/Cookies
rm -f ./volumes_hermes_opencode/data/hermes-home/chrome-debug/Default/Cookies-journal
docker compose up -d
```

### SingletonLock prevents Chromium from starting

**Symptom:** Chromium exits immediately after start, and `docker logs` shows nothing from the browser process.

**Root cause:** The lockfile cleanup in `service-browser-vnc.sh` failed (permissions issue, or the script was bypassed).

**Fix:** Manually remove the lockfiles inside the container:

```bash
CONTAINER=$(docker compose ps -q hermes-opencode)
docker exec "$CONTAINER" rm -f \
    /home/hermeswebui/.hermes/chrome-debug/SingletonLock \
    /home/hermeswebui/.hermes/chrome-debug/SingletonCookie \
    /home/hermeswebui/.hermes/chrome-debug/SingletonSocket
```

Then restart Chromium (or restart the container).

### "Permission denied" when writing to chrome-debug/

**Symptom:** Chromium logs show `Permission denied` errors when trying to write to the profile directory.

**Root cause:** The UID/GID on the host's `./volumes_hermes_opencode/data/hermes-home/` directory does not match the `hermeswebui` user (UID 1000) inside the container.

**Fix:** Correct the ownership on the host:

```bash
sudo chown -R 1000:1000 ./volumes_hermes_opencode/data/hermes-home/
```

## See also

- [15 — Browser Human-in-the-Loop](15-browser-human-loop.md) — feature overview and setup
- [service-browser-vnc.sh](../scripts/service-browser-vnc.sh) — the startup script that performs lockfile cleanup
- [docker-compose.yml](../docker-compose.yml) — volume mount configuration
