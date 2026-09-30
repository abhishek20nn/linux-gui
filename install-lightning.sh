#!/usr/bin/env bash
set -e

echo "===================================================================="
echo " ⚡ Lightning AI - AgentGrid & Linux Desktop Installation"
echo "===================================================================="

# Check sudo
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "Error: Need sudo permissions to install desktop packages."
        exit 1
    fi
fi

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) DEB_ARCH="amd64" ;;
  aarch64|arm64) DEB_ARCH="arm64" ;;
  *) DEB_ARCH="amd64" ;;
esac

echo "[1/4] Architecture: $ARCH ($DEB_ARCH)"

# Update and install headless desktop + VNC + noVNC + Electron requirements
echo "[2/4] Installing X11, Fluxbox, x11vnc, noVNC, and Electron libraries..."
export DEBIAN_FRONTEND=noninteractive
$SUDO apt-get update -y
$SUDO apt-get install -y --no-install-recommends \
    curl \
    wget \
    jq \
    ca-certificates \
    xvfb \
    fluxbox \
    x11vnc \
    novnc \
    websockify \
    net-tools \
    libfuse2 \
    libnss3 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libxkbcommon0 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxrandr2 \
    libgbm1 \
    libasound2 \
    libpango-1.0-0 \
    libcairo2 \
    libx11-xcb1 \
    libxss1 \
    xdg-utils || true

# Download AgentGrid
echo "[3/4] Downloading AgentGrid package..."
TMP_DIR="/tmp/agentgrid-lightning"
mkdir -p "$TMP_DIR"
DEB_FILE="$TMP_DIR/agentgrid.deb"

DOWNLOAD_URL=""
if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    DOWNLOAD_URL=$(curl -sL https://api.github.com/repos/agent-grid/agent-grid-releases/releases/latest | \
        jq -r ".assets[] | select(.name | endswith(\"${DEB_ARCH}.deb\")) | .browser_download_url" 2>/dev/null || true)
fi

if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ]; then
    DOWNLOAD_URL="https://agentgrid.sh/api/download/linux-deb"
fi

FALLBACK_URL="https://github.com/agent-grid/agent-grid-releases/releases/download/v2.9.2/AgentGrid-2.9.2-${DEB_ARCH}.deb"

echo "Downloading from: $DOWNLOAD_URL"
if ! curl -f -L -o "$DEB_FILE" "$DOWNLOAD_URL"; then
    curl -f -L -o "$DEB_FILE" "$FALLBACK_URL"
fi

# Install AgentGrid
echo "[4/4] Installing AgentGrid..."
$SUDO dpkg -i "$DEB_FILE" || ($SUDO apt-get update -y && $SUDO apt-get install -f -y)
rm -rf "$TMP_DIR"

# Create runner wrapper
$SUDO tee /usr/local/bin/agentgrid-runner > /dev/null << 'EOF'
#!/usr/bin/env bash
export DISPLAY="${DISPLAY:-:1}"
EXEC_BIN="/opt/AgentGrid/agentgrid"
if [ ! -x "$EXEC_BIN" ]; then
    EXEC_BIN=$(command -v agentgrid || true)
fi
exec "$EXEC_BIN" --no-sandbox --disable-gpu-sandbox --disable-dev-shm-usage "$@"
EOF
$SUDO chmod +x /usr/local/bin/agentgrid-runner

echo ""
echo "===================================================================="
echo " ✅ Lightning AI installation complete!"
echo " Next step: Run 'bash start-lightning.sh' to start desktop & AgentGrid"
echo "===================================================================="
