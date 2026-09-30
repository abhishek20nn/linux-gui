#!/usr/bin/env bash
set -e

echo "===================================================================="
echo " 🖥️ Upgrading to Full Modern XFCE Desktop + Google Chrome"
echo "===================================================================="

export DEBIAN_FRONTEND=noninteractive
export DISPLAY="${DISPLAY:-:1}"

echo "[1/6] Installing XFCE Desktop, File Manager, and Utilities..."
sudo apt-get update -y
sudo apt-get install -y --no-install-recommends \
    xfce4 \
    xfce4-terminal \
    xfce4-goodies \
    thunar \
    mousepad \
    dbus-x11 \
    libsecret-1-0 \
    libsecret-tools \
    gnome-keyring \
    fonts-liberation \
    xdg-utils \
    wget \
    curl \
    ca-certificates

echo "[2/6] Installing Google Chrome Browser..."
if ! command -v google-chrome-stable >/dev/null 2>&1; then
    wget -q "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb" -O /tmp/chrome.deb
    sudo dpkg -i /tmp/chrome.deb || sudo apt-get install -f -y
    rm -f /tmp/chrome.deb
fi

# Wrap Google Chrome to run inside Docker sandbox safely
sudo tee /usr/local/bin/google-chrome > /dev/null << 'EOF'
#!/bin/bash
exec /usr/bin/google-chrome-stable --no-sandbox --disable-dev-shm-usage --disable-gpu-sandbox "$@"
EOF
sudo chmod +x /usr/local/bin/google-chrome
sudo ln -sf /usr/local/bin/google-chrome /usr/local/bin/chrome 2>/dev/null || true

# Set Chrome as default browser
xdg-settings set default-web-browser google-chrome.desktop 2>/dev/null || true

echo "[3/6] Setting up Desktop Shortcuts..."
mkdir -p "$HOME/Desktop"
chmod 755 "$HOME/Desktop"

# Chrome Desktop shortcut
cat << 'EOF' > "$HOME/Desktop/google-chrome.desktop"
[Desktop Entry]
Version=1.0
Type=Application
Name=Google Chrome
Comment=Access the Internet
Exec=/usr/local/bin/google-chrome %U
Icon=google-chrome
Terminal=false
Categories=Network;WebBrowser;
StartupNotify=true
EOF
chmod +x "$HOME/Desktop/google-chrome.desktop"

# AgentGrid Desktop shortcut
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cat << EOF > "$HOME/Desktop/agentgrid.desktop"
[Desktop Entry]
Version=1.0
Type=Application
Name=AgentGrid
Comment=AgentGrid AI Canvas
Exec=$SCRIPT_DIR/launch-agentgrid.sh
Icon=utilities-terminal
Terminal=false
Categories=Development;
StartupNotify=true
EOF
chmod +x "$HOME/Desktop/agentgrid.desktop"

# Terminal shortcut
cat << 'EOF' > "$HOME/Desktop/terminal.desktop"
[Desktop Entry]
Version=1.0
Type=Application
Name=Terminal
Exec=xfce4-terminal
Icon=utilities-terminal
Terminal=false
StartupNotify=true
EOF
chmod +x "$HOME/Desktop/terminal.desktop"

echo "[4/6] Initializing Keyring & Secret Storage..."
sudo service dbus start 2>/dev/null || true
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    eval $(dbus-launch --sh-syntax)
    export DBUS_SESSION_BUS_ADDRESS
fi

rm -rf "$HOME/.local/share/keyrings"
mkdir -p "$HOME/.local/share/keyrings"
chmod 700 "$HOME/.local/share/keyrings"

find "$HOME/.config" -name "Singleton*" -delete 2>/dev/null || true

pkill -9 -f "gnome-keyring-daemon" 2>/dev/null || true
sleep 1
eval $(gnome-keyring-daemon --start --components=secrets 2>/dev/null || true)
echo -n "" | gnome-keyring-daemon --unlock 2>/dev/null || true
export GNOME_KEYRING_CONTROL SSH_AUTH_SOCK

echo "[5/6] Updating Startup Configuration for Persistent XFCE..."
# Ensure .bashrc has DBus and Keyring variables
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

# Patch desktop-init.sh if present to prefer startxfce4 over fluxbox
if [ -f "/usr/local/share/desktop-init.sh" ]; then
    sudo sed -i 's|fluxbox &|startxfce4 \&|g' /usr/local/share/desktop-init.sh 2>/dev/null || true
fi

echo "[6/6] Switching desktop to XFCE on DISPLAY=$DISPLAY..."
pkill -9 fluxbox 2>/dev/null || true
sleep 1

# Disable XFCE screen saver/lock
xfconf-query -c xfce4-session -p /startup/screensaver/Type -s 0 --create -t int 2>/dev/null || true
xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/blank-on-ac -s 0 --create -t int 2>/dev/null || true

nohup startxfce4 > /tmp/xfce.log 2>&1 &
sleep 2

echo "===================================================================="
echo " 🎉 Full Modern XFCE Desktop is now RUNNING!"
echo " 👉 Switch to your browser tab on Port 6080 (noVNC)!"
echo " 👉 You can now:"
echo "    1. Double-click Google Chrome on the desktop to browse"
echo "    2. Log in to agentgrid.sh / GitHub inside Chrome"
echo "    3. Double-click AgentGrid to launch your AI canvas"
echo "===================================================================="
