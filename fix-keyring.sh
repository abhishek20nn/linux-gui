#!/usr/bin/env bash
set -e

echo "===================================================================="
echo " 🔑 Configuring Persistent Headless Keyring for AgentGrid"
echo "===================================================================="

# Install dependencies
sudo apt-get update -y
sudo apt-get install -y --no-install-recommends gnome-keyring dbus-x11 libsecret-1-0 libsecret-tools

# 1. Create default login keyring with empty password
mkdir -p "$HOME/.local/share/keyrings"
chmod 700 "$HOME/.local/share/keyrings"

cat << 'EOF' > "$HOME/.local/share/keyrings/login.keyring"
[keyring]
display-name=login
ctime=0
mtime=0
lock-on-idle=false
lock-after=false
EOF

cat << 'EOF' > "$HOME/.local/share/keyrings/default"
login
EOF

# 2. Start DBUS session
killall -9 gnome-keyring-daemon 2>/dev/null || true
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    eval $(dbus-launch --sh-syntax)
    export DBUS_SESSION_BUS_ADDRESS
fi

# 3. Unlock and start keyring daemon
eval $(echo -n "" | gnome-keyring-daemon --unlock --components=secrets 2>/dev/null || true)
eval $(gnome-keyring-daemon --start --components=secrets 2>/dev/null || true)
export GNOME_KEYRING_CONTROL

echo "✅ Keyring is unlocked and active!"

# 4. Restart AgentGrid so it connects to the active keyring
echo "Restarting AgentGrid..."
killall -9 "Agent Grid" agent-grid agentgrid 2>/dev/null || true
sleep 1
bash launch-agentgrid.sh
