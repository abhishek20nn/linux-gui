#!/usr/bin/env bash
set -e

# Target X11 Display (desktop-lite uses :1)
export DISPLAY="${DISPLAY:-:1}"

echo "===================================================================="
echo " 🚀 Launching AgentGrid Desktop GUI on DISPLAY=$DISPLAY"
echo "===================================================================="

# 1. Locate the AgentGrid executable
AGENT_BIN=""

# Check direct commands and standard paths
for candidate in \
    "$(command -v agent-grid 2>/dev/null || true)" \
    "$(command -v agentgrid 2>/dev/null || true)" \
    "$(command -v AgentGrid 2>/dev/null || true)" \
    "/opt/Agent Grid/agent-grid" \
    "/opt/Agent Grid/Agent Grid" \
    "/opt/agent-grid/agent-grid" \
    "/opt/AgentGrid/AgentGrid" \
    "/opt/AgentGrid/agentgrid" \
    "/usr/bin/agent-grid" \
    "/usr/bin/agentgrid" \
    "/usr/bin/AgentGrid" \
    "/usr/local/bin/agentgrid-runner"; do
    if [ -n "$candidate" ] && [ -x "$candidate" ] && [ "$candidate" != "/usr/local/bin/agentgrid-runner" ]; then
        AGENT_BIN="$candidate"
        break
    fi
done

# Check dpkg installed files if not found yet
if [ -z "$AGENT_BIN" ]; then
    PKG=$(dpkg -l 2>/dev/null | grep -i -E "agent-grid|agentgrid" | awk '{print $2}' | head -n 1 || true)
    if [ -n "$PKG" ]; then
        while IFS= read -r f; do
            if [ -f "$f" ] && [ -x "$f" ]; then
                case "$f" in
                    *chrome-sandbox*) continue ;;
                    */bin/*|*/opt/*)
                        AGENT_BIN="$f"
                        break
                        ;;
                esac
            fi
        done < <(dpkg -L "$PKG" 2>/dev/null)
    fi
fi

# Fallback: filesystem search
if [ -z "$AGENT_BIN" ]; then
    AGENT_BIN=$(find /opt /usr/bin -iname "*agent*grid*" -type f -perm /111 2>/dev/null | grep -v "runner" | grep -v "sandbox" | head -n 1 || true)
fi

# If still not found, run installer
if [ -z "$AGENT_BIN" ]; then
    echo "AgentGrid binary not found yet. Running installer..."
    if [ -f ".devcontainer/install-agentgrid.sh" ]; then
        bash .devcontainer/install-agentgrid.sh
    elif [ -f "install.sh" ]; then
        bash install.sh
    fi
    # Re-check after install
    AGENT_BIN=$(find /opt /usr/bin -iname "*agent*grid*" -type f -perm /111 2>/dev/null | grep -v "runner" | grep -v "sandbox" | head -n 1 || true)
fi

if [ -z "$AGENT_BIN" ] || [ ! -x "$AGENT_BIN" ]; then
    echo "❌ Error: Could not locate AgentGrid executable."
    echo "Please check installed files with: dpkg -L agent-grid"
    exit 1
fi

echo "Found AgentGrid binary at: $AGENT_BIN"

# Check if X server is responsive on DISPLAY
if command -v xdpyinfo >/dev/null 2>&1; then
    if ! xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then
        echo "Warning: Display $DISPLAY is not currently reachable."
        echo "If desktop-lite is starting up, please wait a moment or verify port 6080."
    fi
fi

# Forcefully terminate any previous stuck AgentGrid or keyring instances
echo "Stopping any existing instances..."
pkill -9 -f "Agent Grid" 2>/dev/null || true
pkill -9 -f "agent-grid" 2>/dev/null || true
pkill -9 -f "agentgrid" 2>/dev/null || true
pkill -9 -f "gnome-keyring-daemon" 2>/dev/null || true
sleep 1

# Remove stale Electron singleton locks left over from killed processes
echo "Cleaning stale singleton locks..."
find "$HOME/.config" -name "Singleton*" -delete 2>/dev/null || true

# Clean any corrupted dummy keyring files and ensure dir exists
rm -rf "$HOME/.local/share/keyrings"
mkdir -p "$HOME/.local/share/keyrings"
chmod 700 "$HOME/.local/share/keyrings"

# Ensure D-Bus session bus is running
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    if command -v dbus-launch >/dev/null 2>&1; then
        eval $(dbus-launch --sh-syntax)
        export DBUS_SESSION_BUS_ADDRESS
    fi
fi

# Start gnome-keyring-daemon with secret service support
if command -v gnome-keyring-daemon >/dev/null 2>&1; then
    eval $(gnome-keyring-daemon --start --components=secrets 2>/dev/null || true)
    export GNOME_KEYRING_CONTROL SSH_AUTH_SOCK
    echo -n "" | gnome-keyring-daemon --unlock 2>/dev/null || true
fi

echo "Starting AgentGrid with --no-sandbox in background..."
nohup "$AGENT_BIN" --no-sandbox --disable-gpu-sandbox --disable-dev-shm-usage > /tmp/agentgrid.log 2>&1 &
PID=$!

sleep 2

if ps -p $PID > /dev/null 2>&1 || pgrep -f "$(basename "$AGENT_BIN")" > /dev/null 2>&1; then
    echo "===================================================================="
    echo " ✅ AgentGrid is running successfully (PID: $PID)!"
    echo " 👉 Open your browser tab on Port 6080 (fluxbox - noVNC) to see it!"
    echo " 👉 View logs with: tail -f /tmp/agentgrid.log"
    echo "===================================================================="
else
    echo "⚠️ Process exited early. Checking log output:"
    tail -n 30 /tmp/agentgrid.log
fi

