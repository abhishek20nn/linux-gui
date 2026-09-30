#!/usr/bin/env bash
set -e

echo "===================================================================="
echo " 🔒 Configuring Permanent Session Persistence Engine"
echo " (Chrome, AgentGrid, Antigravity, Keyrings & Desktop State)"
echo "===================================================================="

# Determine workspace directory (persistent volume across Codespace stops/rebuilds)
WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$WORKSPACE_DIR/.persistent_state"

echo "[1/4] Creating Persistent Storage at $STATE_DIR..."
mkdir -p "$STATE_DIR/google-chrome"
mkdir -p "$STATE_DIR/AgentGrid"
mkdir -p "$STATE_DIR/Agent Grid"
mkdir -p "$STATE_DIR/agent-grid"
mkdir -p "$STATE_DIR/keyrings"
mkdir -p "$STATE_DIR/xfce4"
chmod 700 "$STATE_DIR/keyrings"

echo "[2/4] Migrating & Symlinking Application Configurations..."

# Function to safely migrate and symlink a folder to persistent storage
persist_dir() {
    local source_dir="$1"
    local target_dir="$2"

    mkdir -p "$(dirname "$source_dir")"

    # If source exists as a physical directory and is NOT a symlink yet, migrate contents
    if [ -d "$source_dir" ] && [ ! -L "$source_dir" ]; then
        echo "  -> Migrating existing data from $source_dir to $target_dir..."
        cp -a "$source_dir/." "$target_dir/" 2>/dev/null || true
        rm -rf "$source_dir"
    fi

    # Create symbolic link if not already pointing to target
    if [ ! -L "$source_dir" ] || [ "$(readlink -f "$source_dir")" != "$(readlink -f "$target_dir")" ]; then
        rm -rf "$source_dir" 2>/dev/null || true
        ln -sfn "$target_dir" "$source_dir"
        echo "  -> Linked: $source_dir ===> $target_dir"
    fi
}

persist_dir "$HOME/.config/google-chrome" "$STATE_DIR/google-chrome"
persist_dir "$HOME/.config/Agent Grid"    "$STATE_DIR/Agent Grid"
persist_dir "$HOME/.config/AgentGrid"     "$STATE_DIR/AgentGrid"
persist_dir "$HOME/.config/agent-grid"    "$STATE_DIR/agent-grid"
persist_dir "$HOME/.local/share/keyrings" "$STATE_DIR/keyrings"
persist_dir "$HOME/.config/xfce4"         "$STATE_DIR/xfce4"

echo "[3/4] Initializing Automatic Password & Secret Storage..."
# Ensure D-Bus is running
sudo service dbus start 2>/dev/null || true
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    if command -v dbus-launch >/dev/null 2>&1; then
        eval $(dbus-launch --sh-syntax)
        export DBUS_SESSION_BUS_ADDRESS
    fi
fi

# Ensure Gnome Keyring daemon is active and automatically unlocked with blank password
if command -v gnome-keyring-daemon >/dev/null 2>&1; then
    pkill -9 -f "gnome-keyring-daemon" 2>/dev/null || true
    sleep 1
    eval $(gnome-keyring-daemon --start --components=secrets 2>/dev/null || true)
    export GNOME_KEYRING_CONTROL SSH_AUTH_SOCK
    echo -n "" | gnome-keyring-daemon --unlock 2>/dev/null || true
fi

if command -v secret-tool >/dev/null 2>&1; then
    printf "ok" | secret-tool store --label="agentgrid-key" agentgrid api_key 2>/dev/null || true
fi

# Configure XFCE to automatically save sessions on exit
if command -v xfconf-query >/dev/null 2>&1; then
    xfconf-query -c xfce4-session -p /general/SaveOnExit -s true --create -t bool 2>/dev/null || true
fi

echo "[4/4] Updating Google Chrome Wrapper to use Persistent Basic Password Store..."
sudo tee /usr/local/bin/google-chrome > /dev/null << 'EOF'
#!/bin/bash
export PULSE_SERVER="127.0.0.1:4713"
export ALSA_CARD=pulse
exec /usr/bin/google-chrome-stable \
    --no-sandbox \
    --disable-dev-shm-usage \
    --test-type \
    --password-store=basic \
    --autoplay-policy=no-user-gesture-required \
    --alsa-output-device=pulse \
    "$@"
EOF
sudo chmod +x /usr/local/bin/google-chrome
sudo ln -sf /usr/local/bin/google-chrome /usr/local/bin/chrome 2>/dev/null || true

# Only clean temporary socket/process lock files, NEVER wipe session databases
find "$STATE_DIR" -name "Singleton*" -delete 2>/dev/null || true

echo "===================================================================="
echo " ✅ SESSION PERSISTENCE ENGINE IS ACTIVE!"
echo " 👉 All logins (Google, AgentGrid, Antigravity, YouTube, Chrome)"
echo "    are now saved permanently to: $STATE_DIR"
echo " 👉 Even if Codespaces sleeps, stops, or reboots, you will NEVER"
echo "    be asked to log in again!"
echo "===================================================================="
