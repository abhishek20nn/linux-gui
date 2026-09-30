#!/usr/bin/env bash
set -e

echo "===================================================================="
echo " 🔑 Complete OS Keychain & D-Bus Fix (dbus-run-session approach)"
echo "===================================================================="

# 1. Install required secret service and D-Bus packages
echo "[1/5] Installing Secret Service & D-Bus packages..."
sudo apt-get update -y
sudo apt-get install -y --no-install-recommends \
    gnome-keyring \
    dbus-x11 \
    libsecret-1-0 \
    libsecret-tools \
    python3-secretstorage

# 2. Terminate all stale/isolated AgentGrid, Keyring & D-Bus session processes
echo "[2/5] Stopping stale processes..."
pkill -9 -f "Agent Grid" 2>/dev/null || true
pkill -9 -f "agent-grid" 2>/dev/null || true
pkill -9 -f "AgentGrid" 2>/dev/null || true
pkill -9 -f "gnome-keyring-daemon" 2>/dev/null || true
sleep 1

# 3. Ensure keyrings directory is a physical folder with 0700 permissions
echo "[3/5] Ensuring physical keyrings directory..."
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

# 4. Ensure system D-Bus is running (required base)
echo "[4/5] Starting system D-Bus..."
sudo service dbus start 2>/dev/null || true

# 5. Create the wrapper script that runs INSIDE dbus-run-session
echo "[5/5] Creating AgentGrid wrapper and launching..."

cat << 'WRAPPER_EOF' > /tmp/agentgrid-with-keyring.sh
#!/usr/bin/env bash
# This script runs INSIDE dbus-run-session, so DBUS_SESSION_BUS_ADDRESS
# is already set and valid for this entire process tree.

export DISPLAY="${DISPLAY:-:1}"
export PULSE_SERVER="${PULSE_SERVER:-127.0.0.1:4713}"

echo "[wrapper] D-Bus address: $DBUS_SESSION_BUS_ADDRESS"

# Start gnome-keyring-daemon on THIS D-Bus session
eval $(gnome-keyring-daemon --start --components=secrets 2>/dev/null || true)
export GNOME_KEYRING_CONTROL SSH_AUTH_SOCK
echo "[wrapper] GNOME_KEYRING_CONTROL: $GNOME_KEYRING_CONTROL"

# Unlock with blank password
echo -n "" | gnome-keyring-daemon --unlock 2>/dev/null || true

# Pre-initialize Default Keyring collection
python3 -c "
import secretstorage
try:
    bus = secretstorage.dbus_init()
    try:
        c = secretstorage.get_default_collection(bus)
        if c.is_locked():
            c.unlock()
        print('[wrapper] Default keyring collection exists and is unlocked.')
    except Exception:
        c = secretstorage.create_collection(bus, 'Default keyring', alias='default')
        c.unlock()
        print('[wrapper] Created fresh unlocked Default keyring collection.')
except Exception as e:
    print('[wrapper] Keyring note:', e)
" 2>/dev/null || true

# Verify keyring is working
if command -v secret-tool >/dev/null 2>&1; then
    printf "test1234" | secret-tool store --label="agentgrid-verify" service agentgrid 2>/dev/null || true
    VAL=$(secret-tool lookup service agentgrid 2>/dev/null || true)
    if [ "$VAL" = "test1234" ]; then
        echo "[wrapper] ✅ Keychain VERIFIED working inside dbus-run-session!"
        secret-tool clear service agentgrid 2>/dev/null || true
    else
        echo "[wrapper] ⚠️ Keychain test returned: '$VAL'"
    fi
fi

# Save this D-Bus session env so other scripts (persistence, etc.) can join
cat << EOF > /tmp/dbus-session.env
export DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS"
export GNOME_KEYRING_CONTROL="$GNOME_KEYRING_CONTROL"
export SSH_AUTH_SOCK="$SSH_AUTH_SOCK"
export DISPLAY="$DISPLAY"
EOF

# Find AgentGrid binary
AGENT_BIN=""
for candidate in \
    "/opt/Agent Grid/agent-grid" \
    "/opt/Agent Grid/Agent Grid" \
    "/opt/agent-grid/agent-grid" \
    "/opt/AgentGrid/AgentGrid" \
    "/usr/bin/agent-grid" \
    "/usr/bin/agentgrid"; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
        AGENT_BIN="$candidate"
        break
    fi
done

# Fallback: dpkg
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

# Fallback: find
if [ -z "$AGENT_BIN" ]; then
    AGENT_BIN=$(find /opt /usr/bin -iname "*agent*grid*" -type f -perm /111 2>/dev/null | grep -v "runner" | grep -v "sandbox" | head -n 1 || true)
fi

if [ -z "$AGENT_BIN" ] || [ ! -x "$AGENT_BIN" ]; then
    echo "[wrapper] ❌ Could not locate AgentGrid binary!"
    exit 1
fi

echo "[wrapper] Found AgentGrid: $AGENT_BIN"
echo "[wrapper] Launching AgentGrid... (this process stays alive to keep D-Bus session)"

# Run AgentGrid as a FOREGROUND process inside dbus-run-session
# (nohup wraps the entire dbus-run-session, not just AgentGrid)
exec "$AGENT_BIN" --no-sandbox --disable-gpu-sandbox --disable-dev-shm-usage --password-store=gnome-libsecret
WRAPPER_EOF

chmod +x /tmp/agentgrid-with-keyring.sh

# Ensure session persistence is active
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/setup-persistence.sh" ]; then
    bash "$SCRIPT_DIR/setup-persistence.sh" || true
fi

# Clean stale Electron singleton locks
find "$HOME/.config" -name "Singleton*" -delete 2>/dev/null || true
find "$SCRIPT_DIR/.persistent_state" -name "Singleton*" -delete 2>/dev/null || true

echo "===================================================================="
echo " 🚀 Launching AgentGrid inside dbus-run-session..."
echo "===================================================================="

# THE KEY FIX: dbus-run-session creates a DEDICATED D-Bus session bus,
# starts gnome-keyring INSIDE it, then runs AgentGrid INSIDE it.
# All three (D-Bus, gnome-keyring, AgentGrid) share the SAME bus.
# nohup wraps the ENTIRE thing so it survives terminal close.
nohup dbus-run-session -- bash /tmp/agentgrid-with-keyring.sh > /tmp/agentgrid.log 2>&1 &
BG_PID=$!

echo "Background PID: $BG_PID"
sleep 3

# Check if it's running
if pgrep -f "Agent Grid" > /dev/null 2>&1 || pgrep -f "agent-grid" > /dev/null 2>&1; then
    echo "===================================================================="
    echo " ✅ AgentGrid is running with OS Keychain support!"
    echo " 👉 Open Port 6080 (noVNC) to see it."
    echo " 👉 View logs: tail -f /tmp/agentgrid.log"
    echo "===================================================================="
else
    echo "⚠️ Checking startup log..."
    tail -n 20 /tmp/agentgrid.log
fi
