# lib/service-browser-vnc.sh - Browser/VNC human-in-the-loop stack startup - sourced by entrypoint.sh

# Start the browser human-in-the-loop stack (Xvfb + openbox + x11vnc + websockify + Chromium).
# All processes run as hermeswebui (UID 1000). Controlled by BROWSER_HUMAN_LOOP_ENABLED.
start_browser_vnc() {
    if [ "${BROWSER_HUMAN_LOOP_ENABLED:-false}" != "true" ]; then
        echo "== Browser human-in-the-loop disabled (BROWSER_HUMAN_LOOP_ENABLED=${BROWSER_HUMAN_LOOP_ENABLED:-false})"
        return 0
    fi

    echo "== Starting browser human-in-the-loop stack..."

    # Ensure log directory exists
    mkdir -p "${HERMES_HOME}/logs"

    # Create chromium user-data directory and remove stale lockfiles from previous containers
    mkdir -p /home/hermeswebui/.hermes/chrome-debug
    chown "${OPENCODE_USER}:${OPENCODE_USER}" /home/hermeswebui/.hermes/chrome-debug
    rm -f /home/hermeswebui/.hermes/chrome-debug/SingletonLock \
           /home/hermeswebui/.hermes/chrome-debug/SingletonCookie \
           /home/hermeswebui/.hermes/chrome-debug/SingletonSocket

    # 1. Start Xvfb on display :99
    echo "== Starting Xvfb on :99..."
    su -s /bin/bash "$OPENCODE_USER" -c \
        'Xvfb :99 -screen 0 1280x720x24' \
        > "${HERMES_HOME}/logs/xvfb.log" 2>&1 &
    local xvfb_pid=$!
    echo "== Xvfb started (PID: $xvfb_pid)"

    export DISPLAY=:99
    sleep 1

    # 2. Start openbox window manager
    echo "== Starting openbox..."
    su -s /bin/bash "$OPENCODE_USER" -c \
        "DISPLAY=:99 openbox" \
        > "${HERMES_HOME}/logs/openbox.log" 2>&1 &
    echo "== Openbox started (PID: $!)"

    # 3. Set up VNC password
    local vnc_password="${BROWSER_VNC_PASSWORD:-hermes}"
    x11vnc -storepasswd "$vnc_password" /tmp/.vnc_passwd
    chown "${OPENCODE_USER}:${OPENCODE_USER}" /tmp/.vnc_passwd

    # 4. Start x11vnc
    echo "== Starting x11vnc on :5900..."
    su -s /bin/bash "$OPENCODE_USER" -c \
        "DISPLAY=:99 x11vnc -display :99 -rfbport 5900 -rfbauth /tmp/.vnc_passwd -forever -shared" \
        > "${HERMES_HOME}/logs/x11vnc.log" 2>&1 &
    echo "== x11vnc started (PID: $!)"

    # 5. Start websockify + noVNC
    local novnc_dir="/usr/share/novnc"
    if [ ! -f "${novnc_dir}/vnc.html" ]; then
        echo "!! WARNING: noVNC assets not found at ${novnc_dir}, websockify will run without web client."
    fi
    echo "== Starting websockify on :6901 -> localhost:5900 (noVNC: ${novnc_dir})..."
    websockify 6901 localhost:5900 --web="${novnc_dir}" \
        > "${HERMES_HOME}/logs/websockify.log" 2>&1 &
    echo "== websockify started (PID: $!)"

    # 6. Start Chromium with remote debugging
    echo "== Starting Chromium (CDP on :9222)..."
    su -s /bin/bash "$OPENCODE_USER" -c \
        "DISPLAY=:99 chromium --remote-debugging-port=9222 --remote-debugging-address=0.0.0.0 --user-data-dir=/home/hermeswebui/.hermes/chrome-debug --no-sandbox --disable-gpu --no-first-run --disable-dev-shm-usage" \
        > "${HERMES_HOME}/logs/chromium.log" 2>&1 &
    echo "== Chromium started (PID: $!)"

    echo "== Browser human-in-the-loop stack started."
}
