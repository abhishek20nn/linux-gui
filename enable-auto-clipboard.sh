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
autocutsel -fork || true
autocutsel -selection PRIMARY -fork || true

echo "[3/4] Creating terminal 'clip' helper tool..."
sudo tee /usr/local/bin/clip > /dev/null << 'EOF'
#!/bin/bash
export DISPLAY="${DISPLAY:-:1}"
if [ -n "$*" ]; then
    echo -n "$*" | xclip -selection clipboard
    echo -n "$*" | xclip -selection primary
    echo "✅ Text copied to Desktop Clipboard!"
else
    echo "Paste your text below (Ctrl+V) and press Enter, then Ctrl+D:"
    TEXT=$(cat)
    echo -n "$TEXT" | xclip -selection clipboard
    echo -n "$TEXT" | xclip -selection primary
    echo "✅ Text copied to Desktop Clipboard!"
fi
EOF
sudo chmod +x /usr/local/bin/clip

echo "[4/4] Injecting Seamless Auto-Clipboard Bridge into noVNC web client..."
VNC_FILES=$(find /usr -type f \( -name "vnc.html" -o -name "index.html" \) 2>/dev/null | grep -E "novnc|vnc" || true)

for vf in $VNC_FILES; do
    if [ -f "$vf" ]; then
        # Remove old script if present
        sudo sed -i '/<!-- Auto-Sync Windows PC Clipboard to noVNC Desktop -->/,/<\/script>/d' "$vf" 2>/dev/null || true
        sudo sed -i '/<!-- Seamless Bidirectional Clipboard Bridge -->/,/<\/script>/d' "$vf" 2>/dev/null || true

        echo "Patching $vf..."
        sudo sed -i '/<\/body>/i \
<!-- Seamless Bidirectional Clipboard Bridge (PC <-> Ubuntu) -->\
<script>\
(function() {\
    let lastFromPC = "";\
    let lastFromVNC = "";\
    function sendTextToVNC(text) {\
        if (!text || text === lastFromVNC) return;\
        lastFromPC = text;\
        try {\
            if (window.UI && window.UI.rfb && typeof window.UI.rfb.clipboardPasteFrom === "function") {\
                window.UI.rfb.clipboardPasteFrom(text);\
            }\
            const clipArea = document.getElementById("noVNC_clipboard_text");\
            if (clipArea) {\
                clipArea.value = text;\
                if (window.UI && typeof window.UI.clipboardPaste === "function") {\
                    window.UI.clipboardPaste();\
                }\
            }\
        } catch(e) {}\
    }\
    function copyTextToPC(text) {\
        if (!text || text === lastFromPC || text === lastFromVNC) return;\
        lastFromVNC = text;\
        if (navigator.clipboard && navigator.clipboard.writeText) {\
            navigator.clipboard.writeText(text).then(function() {\
                showToast("📋 Copied from Ubuntu to PC!");\
            }).catch(function() {});\
        }\
    }\
    function showToast(msg) {\
        let toast = document.getElementById("clip-toast");\
        if (!toast) {\
            toast = document.createElement("div");\
            toast.id = "clip-toast";\
            toast.style.cssText = "position:fixed;bottom:20px;right:20px;background:rgba(20,20,20,0.85);color:#4ade80;padding:8px 16px;border-radius:6px;font-family:sans-serif;font-size:13px;z-index:999999;box-shadow:0 4px 12px rgba(0,0,0,0.4);pointer-events:none;transition:opacity 0.3s;opacity:0;";\
            document.body.appendChild(toast);\
        }\
        toast.textContent = msg;\
        toast.style.opacity = "1";\
        setTimeout(function() { toast.style.opacity = "0"; }, 2000);\
    }\
    function initRFBHook() {\
        if (window.UI && window.UI.rfb) {\
            try {\
                window.UI.rfb.addEventListener("clipboard", function(e) {\
                    if (e && e.detail && e.detail.text) {\
                        copyTextToPC(e.detail.text);\
                    }\
                });\
            } catch(e) {}\
        } else {\
            setTimeout(initRFBHook, 500);\
        }\
    }\
    initRFBHook();\
    setInterval(function() {\
        const clipArea = document.getElementById("noVNC_clipboard_text");\
        if (clipArea && clipArea.value && clipArea.value !== lastFromPC && clipArea.value !== lastFromVNC) {\
            copyTextToPC(clipArea.value);\
        }\
    }, 500);\
    window.addEventListener("paste", function(e) {\
        let text = (e.clipboardData || window.clipboardData)?.getData("text");\
        if (text) {\
            sendTextToVNC(text);\
            showToast("📥 Pasted from PC into Ubuntu!");\
        }\
    });\
    async function checkPCClipboard() {\
        try {\
            if (document.hasFocus() && navigator.clipboard && navigator.clipboard.readText) {\
                const text = await navigator.clipboard.readText();\
                if (text && text !== lastFromPC && text !== lastFromVNC) {\
                    sendTextToVNC(text);\
                }\
            }\
        } catch(e) {}\
    }\
    window.addEventListener("focus", checkPCClipboard);\
    document.addEventListener("click", checkPCClipboard);\
    window.addEventListener("DOMContentLoaded", function() {\
        const btn = document.createElement("button");\
        btn.id = "quick-clip-btn";\
        btn.innerHTML = "📋 Sync PC Clipboard";\
        btn.title = "Click to instantly paste your PC clipboard into Ubuntu Desktop";\
        btn.style.cssText = "position:fixed;bottom:12px;left:12px;background:#2563eb;color:#fff;border:none;padding:6px 12px;border-radius:6px;font-family:sans-serif;font-size:12px;cursor:pointer;z-index:999999;box-shadow:0 2px 8px rgba(0,0,0,0.3);font-weight:500;opacity:0.85;";\
        btn.onmouseover = function() { btn.style.opacity = "1"; };\
        btn.onmouseout = function() { btn.style.opacity = "0.85"; };\
        btn.onclick = async function() {\
            try {\
                const text = await navigator.clipboard.readText();\
                if (text) {\
                    sendTextToVNC(text);\
                    showToast("📥 PC Clipboard Synced to Ubuntu!");\
                }\
            } catch(e) {\
                alert("Please click the lock icon next to the URL in Chrome and allow Clipboard permission.");\
            }\
        };\
        document.body.appendChild(btn);\
    });\
})();\
</script>' "$vf" 2>/dev/null || true
    fi
done

echo "===================================================================="
echo " 🎉 Auto-Clipboard Bridge is now INSTALLED and ACTIVE!"
echo "===================================================================="
