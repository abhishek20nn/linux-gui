#!/usr/bin/env bash
set -e

echo "===================================================================="
echo " 📋 Installing Safe Auto-Clipboard Bridge (PC ⇄ Linux Desktop)"
echo "===================================================================="

export DISPLAY="${DISPLAY:-:1}"

# Fix git credentials for private repo
if [ -n "$GITHUB_TOKEN" ]; then
    git remote set-url origin "https://x-access-token:${GITHUB_TOKEN}@github.com/abhishek20nn/linux-gui.git" 2>/dev/null || true
fi

echo "[1/3] Ensuring clipboard tools (autocutsel, xclip, xsel)..."
sudo apt-get update -y
sudo apt-get install -y --no-install-recommends autocutsel xclip xsel python3

echo "[2/3] Starting autocutsel daemon for bidirectional X11 sync..."
pkill -9 autocutsel 2>/dev/null || true
autocutsel -fork || true
autocutsel -selection PRIMARY -fork || true

echo "[3/3] Checking and repairing noVNC files..."
# Restore novnc if corrupted or empty
for test_file in "/usr/share/novnc/vnc.html" "/usr/share/novnc/index.html"; do
    if [ ! -s "$test_file" ]; then
        echo "Detected missing or empty $test_file. Reinstalling pristine novnc..."
        sudo apt-get install --reinstall -y novnc
        break
    fi
done

sudo python3 - << 'PYEOF'
import os, re

target = "/usr/share/novnc/vnc.html"
if os.path.islink(target):
    target = os.path.realpath(target)

if os.path.exists(target) and os.path.getsize(target) > 2000:
    with open(target, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()
    
    # Save clean backup
    orig = target + ".orig"
    if not os.path.exists(orig) and len(content) > 5000:
        with open(orig, "w", encoding="utf-8") as f:
            f.write(content)
            
    # Clean previous injected scripts
    content = re.sub(r'<!--\s*(Auto-Sync|Seamless)[\s\S]*?<\/script>', '', content)
    
    bridge_code = """<!-- Seamless Bidirectional Clipboard Bridge (PC <-> Ubuntu) -->
<script>
(function() {
    let lastPushedText = "";
    let lastReceivedFromVNC = "";

    function isRFBReady() {
        return !!(window.UI && window.UI.rfb && typeof window.UI.rfb.clipboardPasteFrom === "function");
    }

    function showToast(msg, isError) {
        try {
            let toast = document.getElementById("clip-toast");
            if (!toast) {
                toast = document.createElement("div");
                toast.id = "clip-toast";
                toast.style.cssText = "position:fixed;bottom:24px;right:24px;background:rgba(24,24,27,0.92);color:#4ade80;padding:10px 18px;border-radius:8px;font-family:Segoe UI,sans-serif;font-size:13px;z-index:9999999;box-shadow:0 10px 25px -5px rgba(0,0,0,0.5);pointer-events:none;transition:all 0.25s ease;opacity:0;transform:translateY(10px);border:1px solid rgba(255,255,255,0.1);font-weight:500;";
                document.body.appendChild(toast);
            }
            toast.style.color = isError ? "#f87171" : "#4ade80";
            toast.textContent = msg;
            toast.style.opacity = "1";
            toast.style.transform = "translateY(0)";
            clearTimeout(toast._timeout);
            toast._timeout = setTimeout(function() {
                toast.style.opacity = "0";
                toast.style.transform = "translateY(10px)";
            }, 2200);
        } catch(e) {}
    }

    function pushToVNC(text) {
        if (!text) return;
        lastPushedText = text;
        try {
            const clipArea = document.getElementById("noVNC_clipboard_text");
            if (clipArea) {
                clipArea.value = text;
            }
            if (isRFBReady()) {
                window.UI.rfb.clipboardPasteFrom(text);
            }
        } catch(e) {
            console.warn("[ClipboardBridge] push error:", e);
        }
    }

    function initRFB() {
        if (isRFBReady()) {
            try {
                window.UI.rfb.addEventListener("clipboard", function(e) {
                    if (e && e.detail && e.detail.text) {
                        const text = e.detail.text;
                        if (text === lastPushedText) return;
                        lastReceivedFromVNC = text;
                        if (navigator.clipboard && navigator.clipboard.writeText) {
                            navigator.clipboard.writeText(text).then(function() {
                                showToast("\uD83D\uDCCB Copied from Ubuntu to PC!");
                            }).catch(function() {});
                        }
                    }
                });
                if (lastPushedText) {
                    window.UI.rfb.clipboardPasteFrom(lastPushedText);
                }
            } catch(e) {}
        } else {
            setTimeout(initRFB, 500);
        }
    }
    initRFB();

    setInterval(function() {
        try {
            const clipArea = document.getElementById("noVNC_clipboard_text");
            if (clipArea && clipArea.value && clipArea.value !== lastPushedText && clipArea.value !== lastReceivedFromVNC) {
                lastReceivedFromVNC = clipArea.value;
                if (navigator.clipboard && navigator.clipboard.writeText) {
                    navigator.clipboard.writeText(clipArea.value).then(function() {
                        showToast("\uD83D\uDCCB Copied from Ubuntu to PC!");
                    }).catch(function() {});
                }
            }
        } catch(e) {}
    }, 600);

    window.addEventListener("keydown", async function(e) {
        if ((e.ctrlKey || e.metaKey) && (e.key === "v" || e.key === "V" || e.keyCode === 86)) {
            try {
                if (navigator.clipboard && navigator.clipboard.readText) {
                    const text = await navigator.clipboard.readText();
                    if (text) {
                        pushToVNC(text);
                        showToast("\uD83D\uDCE5 PC Clipboard sent to Ubuntu!");
                    }
                }
            } catch(err) {}
        }
    }, true);

    async function syncFromPC() {
        try {
            if (!isRFBReady()) return;
            if (navigator.clipboard && navigator.clipboard.readText) {
                const text = await navigator.clipboard.readText();
                if (text && text !== lastPushedText && text !== lastReceivedFromVNC) {
                    pushToVNC(text);
                }
            }
        } catch(e) {}
    }
    window.addEventListener("focus", syncFromPC);
    window.addEventListener("pointerdown", syncFromPC, true);

    function createPasteButton() {
        try {
            if (document.getElementById("btn-sync-pc-clip")) return;
            const btn = document.createElement("button");
            btn.id = "btn-sync-pc-clip";
            btn.innerHTML = "&#128203; Paste from PC";
            btn.style.cssText = "position:fixed;bottom:14px;left:14px;background:#2563eb;color:#ffffff;border:none;padding:8px 14px;border-radius:8px;font-family:Segoe UI,sans-serif;font-size:12px;font-weight:600;cursor:pointer;z-index:9999999;box-shadow:0 4px 14px rgba(37,99,235,0.4);transition:all 0.2s;display:flex;align-items:center;gap:6px;";
            btn.onmouseover = function() { btn.style.background = "#1d4ed8"; btn.style.transform = "scale(1.03)"; };
            btn.onmouseout = function() { btn.style.background = "#2563eb"; btn.style.transform = "scale(1)"; };
            btn.onclick = async function() {
                try {
                    const text = await navigator.clipboard.readText();
                    if (text) {
                        pushToVNC(text);
                        showToast("\uD83D\uDCE5 PC Clipboard Synced to Ubuntu!");
                    } else {
                        showToast("Clipboard is empty on PC!", true);
                    }
                } catch(e) {
                    const manual = prompt("Paste your PC text here (Ctrl+V) and click OK:", "");
                    if (manual) {
                        pushToVNC(manual);
                        showToast("\uD83D\uDCE5 Sent to Ubuntu!");
                    }
                }
            };
            document.body.appendChild(btn);
        } catch(e) {}
    }
    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", createPasteButton);
    } else {
        createPasteButton();
    }
})();
</script>"""

    if "</body>" in content and len(content) > 2000:
        content = content.replace("</body>", bridge_code + "\n</body>")
        with open(target, "w", encoding="utf-8") as f:
            f.write(content)
        print(f"Successfully patched {target}")
PYEOF

echo "===================================================================="
echo " 🎉 Safe Auto-Clipboard Bridge is now INSTALLED and ACTIVE!"
echo "===================================================================="
