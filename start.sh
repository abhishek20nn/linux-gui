#!/usr/bin/env bash
set -e

export DISPLAY="${DISPLAY:-:1}"

echo "===================================================================="
echo " 🚀 Resuming / Starting Cloud Linux GUI Desktop"
echo "===================================================================="

# 1. If XFCE or Google Chrome is missing (e.g. after a full container rebuild), auto-install
if ! command -v startxfce4 >/dev/null 2>&1 || ! command -v google-chrome >/dev/null 2>&1; then
    echo "Desktop environment or Chrome missing. Running upgrade setup..."
    bash upgrade-desktop.sh
    exit 0
fi

# 2. Clean stale locks from previous sessions
find "$HOME/.config" -name "Singleton*" -delete 2>/dev/null || true

# 3. Ensure D-Bus and Keyring daemon are active
sudo service dbus start 2>/dev/null || true
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    eval $(dbus-launch --sh-syntax)
    export DBUS_SESSION_BUS_ADDRESS
fi

if command -v gnome-keyring-daemon >/dev/null 2>&1; then
    eval $(gnome-keyring-daemon --start --components=secrets 2>/dev/null || true)
    echo -n "" | gnome-keyring-daemon --unlock 2>/dev/null || true
    export GNOME_KEYRING_CONTROL SSH_AUTH_SOCK
fi

# 4. Ensure XFCE desktop is running
if ! pgrep -f "xfce4-session" >/dev/null 2>&1; then
    echo "Starting XFCE Desktop on DISPLAY=$DISPLAY..."
    pkill -9 fluxbox 2>/dev/null || true
    sleep 1
    nohup startxfce4 > /tmp/xfce.log 2>&1 &
    sleep 2
fi

echo "===================================================================="
echo " ✅ Desktop is LIVE!"
echo " 👉 1. Open your browser tab on Port 6080 (noVNC)"
echo " 👉 2. Double-click Google Chrome or AgentGrid icon on the desktop"
echo " 👉 3. To launch AgentGrid from terminal: ./launch-agentgrid.sh"
echo "===================================================================="
