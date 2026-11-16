import sys
import os

path = "/usr/local/novnc/noVNC-1.6.0/app/ui.js"
if not os.path.exists(path):
    sys.exit(0)

with open(path, "r", encoding="utf-8") as f:
    content = f.read()

if "BIDIRECTIONAL SYNC BRIDGE" in content:
    sys.exit(0)

target1 = """    addClipboardHandlers() {
        document.getElementById("noVNC_clipboard_button")
            .addEventListener('click', UI.toggleClipboardPanel);
        document.getElementById("noVNC_clipboard_text")
            .addEventListener('change', UI.clipboardSend);
    },"""

replacement1 = """    addClipboardHandlers() {
        document.getElementById("noVNC_clipboard_button")
            .addEventListener('click', UI.toggleClipboardPanel);
        document.getElementById("noVNC_clipboard_text")
            .addEventListener('change', UI.clipboardSend);

        // --- BIDIRECTIONAL SYNC BRIDGE ---
        window.addEventListener('focus', async () => {
            try {
                if (navigator.clipboard && navigator.clipboard.readText && UI.connected && UI.rfb) {
                    const text = await navigator.clipboard.readText();
                    const el = document.getElementById('noVNC_clipboard_text');
                    if (text && el && text !== el.value) {
                        el.value = text;
                        UI.rfb.clipboardPasteFrom(text);
                    }
                }
            } catch (err) {}
        });

        window.addEventListener('keydown', async (e) => {
            if ((e.ctrlKey || e.metaKey) && (e.key === 'v' || e.key === 'V')) {
                if (!UI.connected || !UI.rfb) return;
                try {
                    if (navigator.clipboard && navigator.clipboard.readText) {
                        const text = await navigator.clipboard.readText();
                        if (text) {
                            const el = document.getElementById('noVNC_clipboard_text');
                            if (el) el.value = text;
                            UI.rfb.clipboardPasteFrom(text);
                            if (!e.shiftKey) {
                                setTimeout(() => {
                                    if (UI.connected && UI.rfb) {
                                        UI.rfb.sendKey(0xffe1, 'ShiftLeft', true);
                                        UI.rfb.sendKey(0xff63, 'Insert', true);
                                        UI.rfb.sendKey(0xff63, 'Insert', false);
                                        UI.rfb.sendKey(0xffe1, 'ShiftLeft', false);
                                    }
                                }, 30);
                            }
                        }
                    }
                } catch (err) {}
            }
        }, true);
    },"""

if target1 in content:
    content = content.replace(target1, replacement1, 1)

target2 = """    clipboardReceive(e) {
        Log.Debug(">> UI.clipboardReceive: " + e.detail.text.substr(0, 40) + "...");
        document.getElementById('noVNC_clipboard_text').value = e.detail.text;
        Log.Debug("<< UI.clipboardReceive");
    },"""

replacement2 = """    clipboardReceive(e) {
        Log.Debug(">> UI.clipboardReceive: " + e.detail.text.substr(0, 40) + "...");
        document.getElementById('noVNC_clipboard_text').value = e.detail.text;
        if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(e.detail.text).catch(() => {});
        }
        Log.Debug("<< UI.clipboardReceive");
    },"""

if target2 in content:
    content = content.replace(target2, replacement2, 1)

with open(path, "w", encoding="utf-8") as f:
    f.write(content)
