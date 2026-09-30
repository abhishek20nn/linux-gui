#!/usr/bin/env bash
set -e

echo "===================================================================="
echo " 🔑 Configuring Persistent Headless Keyring for AgentGrid"
echo "===================================================================="

# Install dependencies
sudo apt-get update -y
sudo apt-get install -y --no-install-recommends gnome-keyring dbus-x11 libsecret-1-0 libsecret-tools

# 1. Clean any corrupted keyring dummy files
rm -rf "$HOME/.local/share/keyrings"
mkdir -p "$HOME/.local/share/keyrings"
chmod 700 "$HOME/.local/share/keyrings"

# 2. Start DBUS session if not present
sudo service dbus start 2>/dev/null || true
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    eval $(dbus-launch --sh-syntax)
    export DBUS_SESSION_BUS_ADDRESS
fi

# 3. Stop stale daemons and start fresh keyring daemon
pkill -9 -f "gnome-keyring-daemon" 2>/dev/null || true
sleep 1
eval $(gnome-keyring-daemon --start --components=secrets 2>/dev/null || true)
export GNOME_KEYRING_CONTROL SSH_AUTH_SOCK DBUS_SESSION_BUS_ADDRESS

# 4. Unlock default keyring
echo -n "" | gnome-keyring-daemon --unlock 2>/dev/null || true

# 5. Verify secret storage with secret-tool
echo "Verifying secret storage with secret-tool..."
if printf "ok" | secret-tool store --label="test" test key 2>/dev/null; then
    echo "✅ Secret Service Keyring verified and active!"
    secret-tool clear test key 2>/dev/null || true
else
    echo "⚠️ Keyring initialized (testing returned code $?). Proceeding..."
fi

# 6. Persist DBUS and Keyring environment to ~/.bashrc
if ! grep -q "DBUS_SESSION_BUS_ADDRESS" "$HOME/.bashrc" 2>/dev/null; then
    cat << 'EOF' >> "$HOME/.bashrc"
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ] && command -v dbus-launch >/dev/null 2>&1; then
    eval $(dbus-launch --sh-syntax)
    export DBUS_SESSION_BUS_ADDRESS
fi
if command -v gnome-keyring-daemon >/dev/null 2>&1; then
    eval $(gnome-keyring-daemon --start --components=secrets 2>/dev/null || true)
    export GNOME_KEYRING_CONTROL
fi
EOF
fi

# 7. Restart AgentGrid
echo "Restarting AgentGrid..."
bash launch-agentgrid.sh

