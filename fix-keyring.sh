#!/usr/bin/env bash
set -e

echo "===================================================================="
echo " 🔑 Fixing OS Keychain & Keyring for AgentGrid"
echo "===================================================================="

# Install gnome-keyring and dbus
sudo apt-get update -y
sudo apt-get install -y --no-install-recommends gnome-keyring dbus-x11 libsecret-1-0 libsecret-tools

# Start dbus session if not active
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    eval $(dbus-launch --sh-syntax)
    export DBUS_SESSION_BUS_ADDRESS
    echo "DBUS started: $DBUS_SESSION_BUS_ADDRESS"
fi

# Unlock and start gnome-keyring daemon
eval $(echo -n "" | gnome-keyring-daemon --unlock --components=secrets 2>/dev/null || true)
eval $(gnome-keyring-daemon --start --components=secrets 2>/dev/null || true)
export GNOME_KEYRING_CONTROL

echo "✅ Keyring is unlocked and active!"
echo "Restarting AgentGrid..."
bash launch-agentgrid.sh
