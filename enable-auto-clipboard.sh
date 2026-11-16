#!/usr/bin/env bash
set -e

echo "===================================================================="
echo " 📋 Installing Seamless Auto-Clipboard Bridge (PC ⇄ Linux Desktop)"
echo "===================================================================="

export DISPLAY="${DISPLAY:-:1}"

echo "[1/4] Installing clipboard tools (autocutsel, xclip, xsel)..."
if [ -n "$GITHUB_TOKEN" ]; then
    git remote set-url origin "https://x-access-token:${GITHUB_TOKEN}@github.com/abhishek20nn/linux-gui.git" 2>/dev/null || true
fi
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
        # Remove old injected scripts cleanly
        sudo sed -i '/<!-- Auto-Sync Windows PC Clipboard to noVNC Desktop -->/,/<\/script>/d' "$vf" 2>/dev/null || true
        sudo sed -i '/<!-- Seamless Bidirectional Clipboard Bridge -->/,/<\/script>/d' "$vf" 2>/dev/null || true

        echo "Patching $vf..."
        sudo sed -i '/<\/body>/i \
<!-- Seamless Bidirectional Clipboard Bridge (PC <-> Ubuntu) -->\
<script>\
(function() {\
    let lastPushedText = "";\
    let lastReceivedFromVNC = "";\
    function showToast(msg, isError) {\
        let toast = document.getElementById("clip-toast");\
        if (!toast) {\
            toast = document.createElement("div");\
            toast.id = "clip-toast";\
            toast.style.cssText = "position:fixed;bottom:24px;right:24px;background:rgba(24,24,27,0.92);color:#4ade80;padding:10px 18px;border-radius:8px;font-family:Segoe UI,sans-serif;font-size:13px;z-index:9999999;box-shadow:0 10px 25px -5px rgba(0,0,0,0.5);pointer-events:none;transition:all 0.25s ease;opacity:0;transform:translateY(10px);border:1px solid rgba(255,255,255,0.1);font-weight:500;";\
            document.body.appendChild(toast);\
        }\
        toast.style.color = isError ? "#f87171" : "#4ade80";\
        toast.textContent = msg;\
        toast.style.opacity = "1";\
        toast.style.transform = "translateY(0)";\
        clearTimeout(toast._timeout);\
        toast._timeout = setTimeout(function() {\
            toast.style.opacity = "0";\
            toast.style.transform = "translateY(10px)";\
        }, 2200);\
    }\
    function pushToVNC(text) {\
        if (!text) return;\
        lastPushedText = text;\
        try {\
            if (window.UI && window.UI.rfb && typeof window.UI.rfb.clipboardPasteFrom === "function") {\
                window.UI.rfb.clipboardPasteFrom(text);\
            }\
            const clipArea = document.getElementById("noVNC_clipboard_text");\
            if (clipArea) {\
                clipArea.value = text;\
                clipArea.dispatchEvent(new Event("change", { bubbles: true }));\
                if (window.UI && typeof window.UI.clipboardSend === "function") {\
                    window.UI.clipboardSend();\
                }\
            }\
        } catch(e) {}\
    }\
    function initVNCListener() {\
        if (window.UI && window.UI.rfb) {\
            window.UI.rfb.addEventListener("clipboard", function(e) {\
                if (e && e.detail && e.detail.text) {\
                    const text = e.detail.text;\
                    if (text === lastPushedText) return;\
                    lastReceivedFromVNC = text;\
                    if (navigator.clipboard && navigator.clipboard.writeText) {\
                        navigator.clipboard.writeText(text).then(function() {\
                            showToast("📋 Copied from Ubuntu to PC!");\
                        }).catch(function() {});\
                    }\
                }\
            });\
        } else {\
            setTimeout(initVNCListener, 400);\
        }\
    }\
    initVNCListener();\
    setInterval(function() {\
        const clipArea = document.getElementById("noVNC_clipboard_text");\
        if (clipArea && clipArea.value && clipArea.value !== lastPushedText && clipArea.value !== lastReceivedFromVNC) {\
            lastReceivedFromVNC = clipArea.value;\
            if (navigator.clipboard && navigator.clipboard.writeText) {\
                navigator.clipboard.writeText(clipArea.value).then(function() {\
                    showToast("📋 Copied from Ubuntu to PC!");\
                }).catch(function() {});\
            }\
        }\
    }, 500);\
    window.addEventListener("keydown", async function(e) {\
        if ((e.ctrlKey || e.metaKey) && (e.key === "v" || e.key === "V" || e.keyCode === 86)) {\
            try {\
                if (navigator.clipboard && navigator.clipboard.readText) {\
                    const text = await navigator.clipboard.readText();\
                    if (text) {\
                        pushToVNC(text);\
                        showToast("📥 PC Clipboard sent to Ubuntu!");\
                    }\
                }\
            } catch(err) {}\
        }\
    }, true);\
    async function syncFromPC() {\
        try {\
            if (navigator.clipboard && navigator.clipboard.readText) {\
                const text = await navigator.clipboard.readText();\
                if (text && text !== lastPushedText && text !== lastReceivedFromVNC) {\
                    pushToVNC(text);\
                }\
            }\
        } catch(e) {}\
    }\
    window.addEventListener("focus", syncFromPC);\
    window.addEventListener("pointerdown", syncFromPC, true);\
    function createPasteButton() {\
        if (document.getElementById("btn-sync-pc-clip")) return;\
        const btn = document.createElement("button");\
        btn.id = "btn-sync-pc-clip";\
        btn.innerHTML = "📋 Paste PC Text to Ubuntu";\
        btn.style.cssText = "position:fixed;bottom:14px;left:14px;background:#2563eb;color:#ffffff;border:none;padding:8px 14px;border-radius:8px;font-family:Segoe UI,sans-serif;font-size:12px;font-weight:600;cursor:pointer;z-index:9999999;box-shadow:0 4px 14px rgba(37,99,235,0.4);transition:all 0.2s;display:flex;align-items:center;gap:6px;";\
        btn.onmouseover = function() { btn.style.background = "#1d4ed8"; btn.style.transform = "scale(1.03)"; };\
        btn.onmouseout = function() { btn.style.background = "#2563eb"; btn.style.transform = "scale(1)"; };\
        btn.onclick = async function() {\
            try {\
                const text = await navigator.clipboard.readText();\
                if (text) {\
                    pushToVNC(text);\
                    showToast("📥 PC Clipboard Synced to Ubuntu!");\
                } else {\
                    showToast("Clipboard is empty on PC!", true);\
                }\
            } catch(e) {\
                const manual = prompt("Paste your PC text here (Ctrl+V) and click OK:", "");\
                if (manual) {\
                    pushToVNC(manual);\
                    showToast("📥 Sent to Ubuntu!");\
                }\
            }\
        };\
        document.body.appendChild(btn);\
    }\
    if (document.readyState === "loading") {\
        document.addEventListener("DOMContentLoaded", createPasteButton);\
    } else {\
        createPasteButton();\
    }\
})();\
</script>' "$vf" 2>/dev/null || true
    fi
done

echo "===================================================================="
echo " 🎉 Auto-Clipboard Bridge is now INSTALLED and ACTIVE!"
echo "===================================================================="
