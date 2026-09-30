#!/usr/bin/env bash
set -e

echo "===================================================================="
echo " 📋 Installing Seamless Auto-Clipboard Bridge (PC ⇄ Linux Desktop)"
echo "===================================================================="

export DISPLAY="${DISPLAY:-:1}"

echo "[1/4] Installing clipboard tools (autocutsel, xclip, xsel)..."
sudo apt-get update -y
sudo apt-get install -y --no-install-recommends autocutsel xclip xsel

echo "[2/4] Starting autocutsel daemon for bidirectional X11 clipboard sync..."
pkill -9 autocutsel 2>/dev/null || true
autocutsel -fork
autocutsel -selection PRIMARY -fork

echo "[3/4] Creating terminal 'clip' helper tool..."
# Allows instantly pasting or piping text from terminal into desktop clipboard
sudo tee /usr/local/bin/clip > /dev/null << 'EOF'
#!/bin/bash
export DISPLAY="${DISPLAY:-:1}"
if [ -n "$*" ]; then
    echo -n "$*" | xclip -selection clipboard
    echo -n "$*" | xclip -selection primary
    echo "✅ Text copied to Desktop Clipboard! Right-click -> Paste in AgentGrid."
else
    echo "Paste your text below (Ctrl+V) and press Enter, then Ctrl+D:"
    TEXT=$(cat)
    echo -n "$TEXT" | xclip -selection clipboard
    echo -n "$TEXT" | xclip -selection primary
    echo "✅ Copied $(echo -n "$TEXT" | wc -c) characters to Desktop Clipboard! Right-click -> Paste in AgentGrid."
fi
EOF
sudo chmod +x /usr/local/bin/clip

echo "[4/4] Injecting Auto-Clipboard synchronization into noVNC web client..."
# Find all vnc.html instances on system
VNC_FILES=$(find /usr -name "vnc.html" 2>/dev/null || true)

for vf in $VNC_FILES; do
    if [ -f "$vf" ]; then
        if ! grep -q "Auto-Sync Windows PC Clipboard" "$vf"; then
            echo "Patching $vf..."
            sudo sed -i '/<\/body>/i \
<!-- Auto-Sync Windows PC Clipboard to noVNC Desktop -->\
<script>\
(function() {\
    let lastCopied = "";\
    async function syncClip() {\
        try {\
            if (navigator.clipboard && navigator.clipboard.readText) {\
                const text = await navigator.clipboard.readText();\
                if (text && text !== lastCopied && window.UI && window.UI.rfb) {\
                    lastCopied = text;\
                    window.UI.rfb.clipboardPasteFrom(text);\
                }\
            }\
        } catch(e) {}\
    }\
    window.addEventListener("focus", syncClip);\
    document.addEventListener("click", syncClip);\
    window.addEventListener("paste", async function(e) {\
        let text = (e.clipboardData || window.clipboardData)?.getData("text");\
        if (!text && navigator.clipboard) {\
            try { text = await navigator.clipboard.readText(); } catch(err) {}\
        }\
        if (text && window.UI && window.UI.rfb) {\
            lastCopied = text;\
            window.UI.rfb.clipboardPasteFrom(text);\
        }\
    });\
})();\
</script>' "$vf" 2>/dev/null || true
        fi
    fi
done

echo "===================================================================="
echo " 🎉 Auto-Clipboard Bridge is now INSTALLED!"
echo "===================================================================="
echo " 👉 Refresh your noVNC tab (Port 6080)."
echo " 👉 When browser asks 'Allow clipboard access', click ALLOW."
echo " 👉 Now whatever you copy on your Windows PC (Ctrl+C)"
echo "    will AUTOMATICALLY be ready to paste in Linux via:"
echo "    - Right-click -> Paste"
echo "    - or Ctrl + Shift + V"
echo "===================================================================="
