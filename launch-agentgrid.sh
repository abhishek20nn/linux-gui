#!/usr/bin/env bash
set -e

# Target X11 Display (desktop-lite uses :1)
export DISPLAY="${DISPLAY:-:1}"

echo "===================================================================="
echo " 🚀 Launching AgentGrid Desktop GUI on DISPLAY=$DISPLAY"
echo "===================================================================="

# Check if AgentGrid runner exists
if ! command -v agentgrid-runner >/dev/null 2>&1; then
    echo "AgentGrid is not installed yet. Running installer..."
    if [ -f ".devcontainer/install-agentgrid.sh" ]; then
        bash .devcontainer/install-agentgrid.sh
    elif [ -f "install.sh" ]; then
        bash install.sh
    else
        echo "Error: Installer script not found!"
        exit 1
    fi
fi

# Check if X server is responsive on DISPLAY
if command -v xdpyinfo >/dev/null 2>&1; then
    if ! xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then
        echo "Warning: Display $DISPLAY is not currently reachable."
        echo "If desktop-lite is starting up, please wait a moment or verify port 6080."
    fi
fi

echo "Starting AgentGrid in background..."
nohup agentgrid-runner "$@" > /tmp/agentgrid.log 2>&1 &
PID=$!

sleep 2

if ps -p $PID > /dev/null; then
    echo "✅ AgentGrid is running successfully (PID: $PID)!"
    echo "👉 Switch to your browser tab on Port 6080 (noVNC) to interact with the GUI."
    echo "👉 View logs anytime with: tail -f /tmp/agentgrid.log"
else
    echo "⚠️ Process exited early. Checking log output:"
    cat /tmp/agentgrid.log
fi
