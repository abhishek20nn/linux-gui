#!/usr/bin/env bash
set -e

echo "=========================================================="
echo " Starting AgentGrid Installation for Cloud Linux Desktop   "
echo "=========================================================="

# Ensure script is run with appropriate permissions
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "Error: Need root or sudo permissions to install packages."
        exit 1
    fi
fi

# Detect system architecture
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)
    DEB_ARCH="amd64"
    APPIMAGE_ARCH="x86_64"
    ;;
  aarch64|arm64)
    DEB_ARCH="arm64"
    APPIMAGE_ARCH="arm64"
    ;;
  *)
    echo "Warning: Unrecognized architecture $ARCH. Defaulting to amd64."
    DEB_ARCH="amd64"
    APPIMAGE_ARCH="x86_64"
    ;;
esac

echo "[1/4] Architecture detected: $ARCH (deb: $DEB_ARCH, AppImage: $APPIMAGE_ARCH)"

# Install necessary GUI and Electron runtime dependencies
echo "[2/4] Installing GUI dependencies and runtime libraries..."
export DEBIAN_FRONTEND=noninteractive
$SUDO apt-get update -y
$SUDO apt-get install -y --no-install-recommends \
    curl \
    wget \
    jq \
    ca-certificates \
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
    xdg-utils \
    libsecret-1-0 \
    libsecret-tools \
    gnome-keyring \
    dbus-x11 \
    menu || true

# Determine download URL for latest AgentGrid .deb package
echo "[3/4] Resolving AgentGrid download URL..."
DOWNLOAD_DIR="/tmp/agentgrid-install"
mkdir -p "$DOWNLOAD_DIR"
DEB_FILE="$DOWNLOAD_DIR/agentgrid-$DEB_ARCH.deb"

DOWNLOAD_URL=""

# Strategy A: Try GitHub Releases API
if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    echo "Querying GitHub Releases API for latest build..."
    DOWNLOAD_URL=$(curl -sL https://api.github.com/repos/agent-grid/agent-grid-releases/releases/latest | \
        jq -r ".assets[] | select(.name | endswith(\"${DEB_ARCH}.deb\")) | .browser_download_url" 2>/dev/null || true)
fi

# Strategy B: If GitHub API query empty or rate limited, try official redirect endpoint
if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ]; then
    echo "Checking official website redirect endpoint..."
    if [ "$DEB_ARCH" = "amd64" ]; then
        DOWNLOAD_URL="https://agentgrid.sh/api/download/linux-deb"
    else
        DOWNLOAD_URL="https://github.com/agent-grid/agent-grid-releases/releases/latest/download/AgentGrid-latest-arm64.deb"
    fi
fi

# Strategy C: Hardcoded fallback to verified stable release v2.9.2
FALLBACK_URL="https://github.com/agent-grid/agent-grid-releases/releases/download/v2.9.2/AgentGrid-2.9.2-${DEB_ARCH}.deb"

echo "Downloading AgentGrid from: $DOWNLOAD_URL"
if ! curl -f -L -o "$DEB_FILE" "$DOWNLOAD_URL"; then
    echo "Primary download failed, falling back to: $FALLBACK_URL"
    curl -f -L -o "$DEB_FILE" "$FALLBACK_URL"
fi

# Install the Debian package
echo "[4/4] Installing AgentGrid package..."
if $SUDO dpkg -i "$DEB_FILE"; then
    echo "AgentGrid installed successfully via dpkg."
else
    echo "Fixing missing dependencies via apt-get -f..."
    $SUDO apt-get update -y
    $SUDO apt-get install -f -y
fi

# Clean up temporary installer
rm -rf "$DOWNLOAD_DIR"

# Locate the installed AgentGrid executable
AGENTGRID_BIN=""

# Check standard paths (both capitalized and lowercase)
for candidate in \
    /opt/AgentGrid/AgentGrid \
    /opt/AgentGrid/agentgrid \
    /opt/agentgrid/AgentGrid \
    /opt/agentgrid/agentgrid \
    /usr/bin/AgentGrid \
    /usr/bin/agentgrid \
    /opt/agent-grid/agent-grid \
    /usr/local/bin/agentgrid-bin; do
    if [ -x "$candidate" ]; then
        AGENTGRID_BIN="$candidate"
        break
    fi
done

# If not found in standard paths, inspect dpkg installed files
if [ -z "$AGENTGRID_BIN" ]; then
    PKG_NAME=$(dpkg -l 2>/dev/null | grep -i "agentgrid" | awk '{print $2}' | head -n 1 || true)
    if [ -n "$PKG_NAME" ]; then
        for f in $(dpkg -L "$PKG_NAME" 2>/dev/null); do
            if [ -f "$f" ] && [ -x "$f" ] && [[ "$f" == *"/opt/"* || "$f" == *"/bin/"* ]]; then
                case "$(basename "$f")" in
                    *agentgrid*|*AgentGrid*)
                        AGENTGRID_BIN="$f"
                        break
                        ;;
                esac
            fi
        done
    fi
fi

# Fallback: case-insensitive filesystem search
if [ -z "$AGENTGRID_BIN" ]; then
    FOUND=$(find /opt /usr -iname "*agentgrid*" -type f -perm /111 2>/dev/null | grep -v "agentgrid-runner" | head -n 1 || true)
    if [ -n "$FOUND" ]; then
        AGENTGRID_BIN="$FOUND"
    fi
fi

echo "AgentGrid binary located at: ${AGENTGRID_BIN:-Not found}"

# Create hardened wrapper script with --no-sandbox (required for Chromium/Electron inside Docker/Codespaces)
$SUDO tee /usr/local/bin/agentgrid-runner > /dev/null << 'EOF'
#!/usr/bin/env bash
export DISPLAY="${DISPLAY:-:1}"

# Find AgentGrid binary
EXEC_BIN=""
for path in \
    /opt/AgentGrid/AgentGrid \
    /opt/AgentGrid/agentgrid \
    /opt/agentgrid/AgentGrid \
    /opt/agentgrid/agentgrid \
    /usr/bin/AgentGrid \
    /usr/bin/agentgrid \
    /opt/agent-grid/agent-grid \
    /usr/local/bin/agentgrid-bin; do
    if [ -x "$path" ]; then
        EXEC_BIN="$path"
        break
    fi
done

if [ -z "$EXEC_BIN" ]; then
    # Search via dpkg
    PKG_NAME=$(dpkg -l 2>/dev/null | grep -i "agentgrid" | awk '{print $2}' | head -n 1 || true)
    if [ -n "$PKG_NAME" ]; then
        for f in $(dpkg -L "$PKG_NAME" 2>/dev/null); do
            if [ -f "$f" ] && [ -x "$f" ] && [[ "$f" == *"/opt/"* || "$f" == *"/bin/"* ]]; then
                case "$(basename "$f")" in
                    *agentgrid*|*AgentGrid*)
                        EXEC_BIN="$f"
                        break
                        ;;
                esac
            fi
        done
    fi
fi

if [ -z "$EXEC_BIN" ]; then
    EXEC_BIN=$(find /opt /usr -iname "*agentgrid*" -type f -perm /111 2>/dev/null | grep -v "agentgrid-runner" | head -n 1 || true)
fi

if [ -z "$EXEC_BIN" ] || [ ! -x "$EXEC_BIN" ]; then
    echo "Error: AgentGrid binary not found. Please run: bash .devcontainer/install-agentgrid.sh" >&2
    exit 1
fi

echo "Starting AgentGrid with DISPLAY=$DISPLAY and --no-sandbox flag from $EXEC_BIN..."
# Disable Chromium GPU and sandbox restrictions common to unprivileged container environments
exec "$EXEC_BIN" --no-sandbox --disable-gpu-sandbox --disable-dev-shm-usage "$@"
EOF

$SUDO chmod +x /usr/local/bin/agentgrid-runner

# Make agentgrid command use the runner
if [ -n "$AGENTGRID_BIN" ] && [ "$AGENTGRID_BIN" != "/usr/local/bin/agentgrid" ]; then
    $SUDO ln -sf /usr/local/bin/agentgrid-runner /usr/local/bin/agentgrid
fi

# Create desktop entry and menu item for Fluxbox / XFCE
DESKTOP_ENTRY_DIR="/etc/skel/Desktop"
[ -d "/home/vscode/Desktop" ] && DESKTOP_ENTRY_DIR="/home/vscode/Desktop"
mkdir -p "$DESKTOP_ENTRY_DIR"

tee /tmp/agentgrid.desktop > /dev/null << 'EOF'
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

$SUDO cp /tmp/agentgrid.desktop "$DESKTOP_ENTRY_DIR/agentgrid.desktop" 2>/dev/null || true
$SUDO cp /tmp/agentgrid.desktop /usr/share/applications/agentgrid.desktop 2>/dev/null || true
$SUDO chmod +x "$DESKTOP_ENTRY_DIR/agentgrid.desktop" 2>/dev/null || true
rm -f /tmp/agentgrid.desktop

# Add AgentGrid to Fluxbox menu if fluxbox is installed
FLUXBOX_MENU="/home/vscode/.fluxbox/menu"
if [ -f "$FLUXBOX_MENU" ]; then
    if ! grep -q "agentgrid-runner" "$FLUXBOX_MENU"; then
        sed -i '/\[submenu\] (Applications)/a \      [exec] (AgentGrid) {/usr/local/bin/agentgrid-runner}' "$FLUXBOX_MENU" 2>/dev/null || true
    fi
fi

echo "=========================================================="
echo " AgentGrid Installation Completed Successfully!           "
echo " You can launch it using:                                 "
echo "   1) agentgrid-runner                                    "
echo "   2) ./launch-agentgrid.sh                               "
echo "   3) Desktop icon or Applications Menu in noVNC browser  "
echo "=========================================================="
