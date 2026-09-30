#!/usr/bin/env bash

# Setup desktop shortcut if directory exists
if [ -d "$HOME/Desktop" ]; then
    mkdir -p "$HOME/Desktop"
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
if command -v startxfce4 >/dev/null 2>&1 && pgrep -f fluxbox >/dev/null 2>&1; then
    pkill -9 fluxbox 2>/dev/null || true
    nohup startxfce4 > /tmp/xfce.log 2>&1 &
fi

echo ""
echo "===================================================================="
echo " 🌐 AgentGrid Linux Desktop GUI is ready!"
echo "===================================================================="
echo " 1. Open the 'Ports' tab in VS Code / Codespaces (bottom panel)."
echo " 2. Click the 'Open in Browser' icon next to Port 6080 (noVNC)."
echo " 3. In the browser tab, you will see your Linux GUI desktop."
echo " 4. To start AgentGrid, run in this terminal:"
echo "      ./launch-agentgrid.sh"
echo "    or double-click the AgentGrid icon on the desktop."
echo "===================================================================="
echo ""
