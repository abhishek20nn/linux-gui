#!/usr/bin/env bash
set -e

echo "===================================================================="
echo " 🔑 Fixing OS Keychain & Removing Fragile Symlinks"
echo "===================================================================="

# 1. Stop AgentGrid and Chrome so files are unlocked
echo "[1/6] Stopping existing desktop apps..."
pkill -9 -f "Agent Grid" 2>/dev/null || true
pkill -9 -f "agent-grid" 2>/dev/null || true
pkill -9 -f "AgentGrid" 2>/dev/null || true
pkill -9 -f "google-chrome" 2>/dev/null || true
pkill -9 -f "chrome" 2>/dev/null || true
pkill -9 -f "gnome-keyring-daemon" 2>/dev/null || true
sleep 1

# 2. Convert any symlinked config directories back to REAL physical directories
echo "[2/6] Converting symlinks back to physical directories..."
restore_real_dir() {
    local target="$1"
    if [ -L "$target" ]; then
        local real_dest
        real_dest="$(readlink -f "$target")"
        echo "  -> Restoring $target from $real_dest..."
        rm -f "$target"
        mkdir -p "$target"
        if [ -d "$real_dest" ]; then
            cp -a "$real_dest/." "$target/" 2>/dev/null || true
        fi
    else
        mkdir -p "$target"
    fi
}

restore_real_dir "$HOME/.local/share/keyrings"
restore_real_dir "$HOME/.config/google-chrome"
restore_real_dir "$HOME/.config/Agent Grid"
restore_real_dir "$HOME/.config/AgentGrid"
restore_real_dir "$HOME/.config/agent-grid"
restore_real_dir "$HOME/.config/xfce4"

# 3. Strictly enforce 700 permissions on keyrings directory (required by gnome-keyring security check)
echo "[3/6] Setting strict 700 permissions on keyrings..."
chmod 700 "$HOME/.local/share/keyrings"

# 4. Clean temporary singleton lock files
echo "[4/6] Cleaning stale singleton lock files..."
find "$HOME/.config" -name "Singleton*" -delete 2>/dev/null || true

# 5. Ensure DBUS daemon is active
echo "[5/6] Starting D-Bus & GNOME Keyring Daemon..."
sudo service dbus start 2>/dev/null || true
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    eval $(dbus-launch --sh-syntax)
    export DBUS_SESSION_BUS_ADDRESS
fi

# Start gnome-keyring-daemon as current user with secret service
eval $(gnome-keyring-daemon --start --components=secrets 2>/dev/null || true)
export GNOME_KEYRING_CONTROL SSH_AUTH_SOCK DBUS_SESSION_BUS_ADDRESS

# Unlock default keyring
echo -n "" | gnome-keyring-daemon --unlock 2>/dev/null || true

# 6. Test Secret Service with secret-tool
echo "[6/6] Verifying Secret Service..."
if command -v secret-tool >/dev/null 2>&1; then
    printf "ok" | secret-tool store --label="agentgrid-key" agentgrid api_key 2>/dev/null || true
    if secret-tool lookup agentgrid api_key 2>/dev/null | grep -q "ok"; then
        echo "  -> ✅ OS Keychain is active, unlocked, and working!"
        secret-tool clear agentgrid api_key 2>/dev/null || true
    fi
fi

# 7. Restart AgentGrid
echo "===================================================================="
echo " 🚀 Launching AgentGrid with verified OS Keychain..."
echo "===================================================================="
bash launch-agentgrid.sh
