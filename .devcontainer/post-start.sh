#!/usr/bin/env bash

# Ensure Desktop directory exists and sync extension folder
mkdir -p "$HOME/Desktop"
if [ -d "/workspaces/linux-gui/myoutube" ]; then
    cp -rn "/workspaces/linux-gui/myoutube" "$HOME/Desktop/" 2>/dev/null || true
    ln -sf "/workspaces/linux-gui/myoutube" "$HOME/Desktop/myoutube-linked" 2>/dev/null || true
fi

# Setup desktop shortcut if directory exists
if [ -d "$HOME/Desktop" ]; then
    cat << 'EOF' > "$HOME/Desktop/AgentGrid.desktop"
[Desktop Entry]
Name=AgentGrid
Comment=Infinite Canvas for AI Coding Agents
Exec=/usr/local/bin/agentgrid-runner
Icon=utilities-terminal
Terminal=false
Type=Application
Categories=Development;IDE;
StartupWMClass=AgentGrid
EOF
    chmod +x "$HOME/Desktop/AgentGrid.desktop" 2>/dev/null || true
fi

# Update Fluxbox menu if available
if [ -f "$HOME/.fluxbox/menu" ]; then
    if ! grep -q "agentgrid-runner" "$HOME/.fluxbox/menu"; then
        sed -i '/\[submenu\] (Applications)/a \      [exec] (AgentGrid) {/usr/local/bin/agentgrid-runner}' "$HOME/.fluxbox/menu" 2>/dev/null || true
    fi
fi

# Switch to XFCE if installed
if [ -f "start.sh" ]; then
    bash start.sh
elif command -v startxfce4 >/dev/null 2>&1 && pgrep -f fluxbox >/dev/null 2>&1; then
    pkill -9 fluxbox 2>/dev/null || true
    nohup startxfce4 > /tmp/xfce.log 2>&1 &
fi

# Configure permanent full noVNC with autoconnect and redirect vnc_lite
if [ -d "/usr/local/novnc/noVNC-1.6.0" ]; then
    cat << 'EOF' | sudo tee "/usr/local/novnc/noVNC-1.6.0/mandatory.json" >/dev/null
{
  "autoconnect": true,
  "password": "vscode",
  "resize": "scale"
}
EOF
    cat << 'EOF' | sudo tee "/usr/local/novnc/noVNC-1.6.0/vnc_lite.html" >/dev/null
<!DOCTYPE html>
<html>
<head>
  <meta http-equiv="refresh" content="0; url=vnc.html">
  <script>window.location.replace("vnc.html");</script>
</head>
<body>
  <p>Loading full Ubuntu desktop...</p>
</body>
</html>
EOF
fi

# Run safe clipboard daemon
if [ -f "/workspaces/linux-gui/enable-auto-clipboard.sh" ]; then
    bash "/workspaces/linux-gui/enable-auto-clipboard.sh" 2>/dev/null || true
fi

echo ""
echo "===================================================================="
echo " 🌐 Cloud Desktop is ready on Port 6080 (noVNC)!"
echo "===================================================================="
echo ""
