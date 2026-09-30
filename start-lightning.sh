#!/usr/bin/env bash

export DISPLAY=:1
PORT=${1:-6080}

echo "===================================================================="
echo " 🚀 Starting Linux Desktop GUI on Lightning AI (Port: $PORT)"
echo "===================================================================="

# Kill any existing sessions
killall -9 Xvfb fluxbox x11vnc websockify 2>/dev/null || true

# 1. Start Xvfb (Virtual Framebuffer)
echo "Starting Xvfb on DISPLAY=$DISPLAY..."
Xvfb :1 -screen 0 1600x900x24 > /tmp/xvfb.log 2>&1 &
sleep 1

# 2. Start Fluxbox Window Manager
echo "Starting Fluxbox window manager..."
fluxbox -display :1 > /tmp/fluxbox.log 2>&1 &
sleep 1

# 3. Start x11vnc server
echo "Starting VNC server on port 5901..."
x11vnc -display :1 -nopw -listen 0.0.0.0 -xkb -forever -shared -rfbport 5901 > /tmp/x11vnc.log 2>&1 &
sleep 1

# 4. Start noVNC (Web VNC)
echo "Starting noVNC web viewer on port $PORT..."
if [ -d "/usr/share/novnc" ]; then
    /usr/share/novnc/utils/launch.sh --vnc localhost:5901 --listen $PORT > /tmp/novnc.log 2>&1 &
elif command -v websockify >/dev/null 2>&1; then
    websockify --web /usr/share/novnc $PORT localhost:5901 > /tmp/novnc.log 2>&1 &
fi
sleep 2

# 5. Launch AgentGrid
echo "Launching AgentGrid GUI..."
nohup agentgrid-runner > /tmp/agentgrid.log 2>&1 &

echo ""
echo "===================================================================="
echo " 🎉 Linux Desktop & AgentGrid are running!"
echo "===================================================================="
echo " How to view your desktop in Lightning AI:"
echo ""
echo " Option A (Built-in Port Viewer):"
echo "   In Lightning AI Studio, open the Ports / Plugin panel and preview port: $PORT"
echo ""
echo " Option B (Instant Public HTTPS link via Cloudflare Tunnel - No signup needed):"
echo "   Run this command in a new terminal:"
echo "     curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /tmp/cloudflared && chmod +x /tmp/cloudflared"
echo "     /tmp/cloudflared tunnel --url http://localhost:$PORT"
echo "===================================================================="
