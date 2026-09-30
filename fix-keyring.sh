#!/usr/bin/env bash
set -e

echo "===================================================================="
echo " 🔑 Complete OS Keychain & D-Bus Session Unification Fix"
echo "===================================================================="

# 1. Install required secret service and D-Bus packages
echo "[1/6] Installing Secret Service & D-Bus packages..."
sudo apt-get update -y
sudo apt-get install -y --no-install-recommends \
    gnome-keyring \
    dbus-x11 \
    libsecret-1-0 \
    libsecret-tools \
    python3-secretstorage

# 2. Terminate all stale/isolated AgentGrid, Keyring & D-Bus processes
echo "[2/6] Stopping stale processes..."
pkill -9 -f "Agent Grid" 2>/dev/null || true
pkill -9 -f "agent-grid" 2>/dev/null || true
pkill -9 -f "AgentGrid" 2>/dev/null || true
pkill -9 -f "gnome-keyring-daemon" 2>/dev/null || true
pkill -9 -f "dbus-daemon --session" 2>/dev/null || true
sleep 1

# 3. Ensure keyrings directory is a physical folder with 0700 permissions
echo "[3/6] Ensuring physical keyrings directory with strict 0700 permissions..."
if [ -L "$HOME/.local/share/keyrings" ]; then
    REAL_DEST="$(readlink -f "$HOME/.local/share/keyrings")"
    rm -f "$HOME/.local/share/keyrings"
    mkdir -p "$HOME/.local/share/keyrings"
    if [ -d "$REAL_DEST" ]; then
        cp -a "$REAL_DEST/." "$HOME/.local/share/keyrings/" 2>/dev/null || true
    fi
else
    mkdir -p "$HOME/.local/share/keyrings"
fi
chmod 700 "$HOME/.local/share/keyrings"
find "$HOME/.config" -name "Singleton*" -delete 2>/dev/null || true

# 4. Start ONE Unified D-Bus Session Bus and persist it
echo "[4/6] Spawning unified D-Bus session bus..."
sudo service dbus start 2>/dev/null || true
eval $(dbus-launch --sh-syntax)

# Save D-Bus session environment so all future scripts, tabs, and apps share the exact same bus
cat << EOF > /tmp/dbus-session.env
export DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS"
export DBUS_SESSION_BUS_PID="$DBUS_SESSION_BUS_PID"
export DISPLAY="${DISPLAY:-:1}"
EOF
chmod 644 /tmp/dbus-session.env

# Export to current shell and ~/.bashrc
export DBUS_SESSION_BUS_ADDRESS
if ! grep -q "/tmp/dbus-session.env" "$HOME/.bashrc" 2>/dev/null; then
    cat << 'EOF' >> "$HOME/.bashrc"
if [ -f "/tmp/dbus-session.env" ]; then
    source "/tmp/dbus-session.env"
fi
EOF
fi

# 5. Start GNOME Keyring Daemon on this exact D-Bus bus
echo "[5/6] Starting GNOME Keyring Daemon on unified D-Bus..."
eval $(gnome-keyring-daemon --start --components=secrets 2>/dev/null || true)
export GNOME_KEYRING_CONTROL SSH_AUTH_SOCK

# Unlock default keyring with blank password
echo -n "" | gnome-keyring-daemon --unlock 2>/dev/null || true

# Pre-initialize Default Keyring collection via Python secretstorage so it NEVER prompts
python3 -c "
import secretstorage
try:
    bus = secretstorage.dbus_init()
    try:
        c = secretstorage.get_default_collection(bus)
        if c.is_locked():
            c.unlock()
        print('  -> Default keyring collection exists and is unlocked.')
    except Exception:
        c = secretstorage.create_collection(bus, 'Default keyring', alias='default')
        c.unlock()
        print('  -> Created fresh unlocked Default keyring collection.')
except Exception as e:
    print('  -> Keyring note:', e)
" 2>/dev/null || true

# Verify with secret-tool
echo "[6/6] Verifying Secret Service API..."
if command -v secret-tool >/dev/null 2>&1; then
    printf "test1234" | secret-tool store --label="agentgrid-verify" service agentgrid 2>/dev/null || true
    VAL=$(secret-tool lookup service agentgrid 2>/dev/null || true)
    if [ "$VAL" = "test1234" ]; then
        echo "  -> ✅ SUCCESS: OS Keychain is fully functional & storing credentials!"
        secret-tool clear service agentgrid 2>/dev/null || true
    else
        echo "  -> ⚠️ Secret storage test returned: '$VAL'"
    fi
fi

# Also update /tmp/dbus-session.env with GNOME_KEYRING_CONTROL
cat << EOF >> /tmp/dbus-session.env
export GNOME_KEYRING_CONTROL="$GNOME_KEYRING_CONTROL"
export SSH_AUTH_SOCK="$SSH_AUTH_SOCK"
EOF

echo "===================================================================="
echo " 🚀 Launching AgentGrid with unified OS Keychain..."
echo "===================================================================="
bash launch-agentgrid.sh
