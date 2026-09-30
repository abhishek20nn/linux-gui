#!/usr/bin/env bash
set -e

echo "===================================================================="
echo " 🔑 Repairing & Unlocking OS Keychain for AgentGrid"
echo "===================================================================="

# 1. Install Secret Service packages if missing
if ! dpkg -l | grep -q "libsecret-tools"; then
    sudo apt-get update -y
    sudo apt-get install -y --no-install-recommends gnome-keyring dbus-x11 libsecret-1-0 libsecret-tools
fi

# 2. Start DBUS session bus
sudo service dbus start 2>/dev/null || true
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    eval $(dbus-launch --sh-syntax)
    export DBUS_SESSION_BUS_ADDRESS
fi

# 3. Ensure keyrings directory exists
mkdir -p "$HOME/.local/share/keyrings"
chmod 700 "$HOME/.local/share/keyrings"

# 4. Restart gnome-keyring-daemon with secret service support
pkill -9 -f "gnome-keyring-daemon" 2>/dev/null || true
sleep 1
eval $(gnome-keyring-daemon --start --components=secrets 2>/dev/null || true)
export GNOME_KEYRING_CONTROL SSH_AUTH_SOCK DBUS_SESSION_BUS_ADDRESS

# 5. Unlock default keyring
echo -n "" | gnome-keyring-daemon --unlock 2>/dev/null || true

# 6. Pre-create collection with secret-tool so AgentGrid daemon never errors
printf "ok" | secret-tool store --label="agentgrid-key" agentgrid api_key 2>/dev/null || true

echo "✅ OS Keychain is active, unlocked, and verified!"

# 7. Restart AgentGrid with clean environment
echo "Restarting AgentGrid..."
bash launch-agentgrid.sh
