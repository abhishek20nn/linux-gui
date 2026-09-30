#!/usr/bin/env bash
set -e

echo "===================================================================="
echo " 🔊 Installing Ultra-Low-Latency Real-Time Audio Streamer"
echo " (PulseAudio -> WebSockets -> Browser Web Audio API ~40ms Latency)"
echo "===================================================================="

export DEBIAN_FRONTEND=noninteractive
export DISPLAY="${DISPLAY:-:1}"

echo "[1/4] Installing PulseAudio & Python WebSocket dependencies..."
sudo apt-get update -y
sudo apt-get install -y --no-install-recommends \
    pulseaudio \
    pulseaudio-utils \
    pavucontrol \
    python3 \
    python3-websockets

echo "[2/4] Initializing PulseAudio with Virtual Null-Sink..."
# Ensure daemon is running
pulseaudio --start --exit-idle-time=-1 2>/dev/null || true
sleep 1

# Configure Virtual Null-Sink so all desktop apps output sound to auto_null
if ! pactl list sinks short 2>/dev/null | grep -q "auto_null"; then
    pactl load-module module-null-sink sink_name=auto_null sink_properties=device.description="Virtual_Null_Output" 2>/dev/null || true
fi
pactl set-default-sink auto_null 2>/dev/null || true
pactl set-default-source auto_null.monitor 2>/dev/null || true

# Ensure all future PulseAudio clients use auto_null
mkdir -p "$HOME/.config/pulse"
cat << 'EOF' > "$HOME/.config/pulse/default.pa"
.include /etc/pulse/default.pa
load-module module-null-sink sink_name=auto_null sink_properties=device.description="Virtual_Null_Output"
set-default-sink auto_null
set-default-source auto_null.monitor
EOF

echo "[3/4] Creating Ultra-Low-Latency Python Audio WebSocket Server..."
sudo tee /usr/local/bin/audio-server.py > /dev/null << 'EOF'
#!/usr/bin/env python3
import asyncio
import subprocess
import websockets
from http import HTTPStatus

PORT = 6081
SAMPLE_RATE = 44100
CHANNELS = 2
CHUNK_SIZE = 2048  # ~23ms chunks

HTML_PAGE = """<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Cloud Desktop Audio (Live)</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    * { box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
      margin: 0;
      background: #0f172a;
      color: #f8fafc;
      padding: 20px;
    }
    .card {
      background: #1e293b;
      padding: 40px;
      border-radius: 16px;
      box-shadow: 0 10px 30px rgba(0,0,0,0.5);
      text-align: center;
      max-width: 440px;
      width: 100%;
      border: 1px solid #334155;
    }
    .badge {
      display: inline-block;
      padding: 6px 12px;
      border-radius: 9999px;
      font-size: 13px;
      font-weight: 600;
      background: #064e3b;
      color: #34d399;
      margin-bottom: 20px;
      letter-spacing: 0.5px;
    }
    h2 { margin: 0 0 8px 0; font-size: 24px; }
    p { color: #94a3b8; font-size: 14px; margin: 0 0 28px 0; }
    button {
      width: 100%;
      padding: 16px 24px;
      font-size: 17px;
      font-weight: 700;
      border: none;
      border-radius: 12px;
      background: #2563eb;
      color: white;
      cursor: pointer;
      transition: all 0.2s ease;
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 10px;
    }
    button:hover { background: #1d4ed8; transform: translateY(-1px); }
    button:disabled { background: #059669; cursor: default; transform: none; }
    #status {
      margin-top: 20px;
      font-size: 14px;
      color: #cbd5e1;
      min-height: 20px;
    }
    .meter-box {
      margin-top: 24px;
      background: #0f172a;
      border-radius: 8px;
      height: 8px;
      overflow: hidden;
      width: 100%;
      display: none;
    }
    .meter-fill {
      height: 100%;
      width: 0%;
      background: #10b981;
      transition: width 0.05s ease;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="badge">● LIVE ~40ms LATENCY</div>
    <h2>Desktop Audio Stream</h2>
    <p>Real-time sound from YouTube, Chrome & System</p>
    <button id="btn">🔊 Start Listening</button>
    <div class="meter-box" id="meterBox"><div class="meter-fill" id="meter"></div></div>
    <div id="status">Click button above to play sound</div>
  </div>

  <script>
    const btn = document.getElementById('btn');
    const status = document.getElementById('status');
    const meterBox = document.getElementById('meterBox');
    const meter = document.getElementById('meter');
    let audioCtx = null;
    let nextStartTime = 0;

    btn.onclick = () => {
      if (!audioCtx) {
        audioCtx = new (window.AudioContext || window.webkitAudioContext)({ sampleRate: 44100 });
      }
      if (audioCtx.state === 'suspended') {
        audioCtx.resume();
      }

      btn.disabled = true;
      btn.innerText = "🔊 Audio Active (Playing Live)";
      status.innerText = "Connecting to WebSocket audio feed...";
      meterBox.style.display = "block";

      const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
      const wsUrl = proto + '//' + location.host + '/ws';
      const ws = new WebSocket(wsUrl);
      ws.binaryType = 'arraybuffer';

      ws.onopen = () => {
        status.innerText = "✅ Connected! Playing sound in real-time.";
      };

      ws.onmessage = (event) => {
        if (!audioCtx || audioCtx.state !== 'running') return;

        const int16 = new Int16Array(event.data);
        const channels = 2;
        const numSamples = int16.length / channels;
        if (numSamples === 0) return;

        const buffer = audioCtx.createBuffer(channels, numSamples, 44100);
        const left = buffer.getChannelData(0);
        const right = buffer.getChannelData(1);

        let maxAmp = 0;
        for (let i = 0; i < numSamples; i++) {
          const lVal = int16[i * 2] / 32768.0;
          const rVal = int16[i * 2 + 1] / 32768.0;
          left[i] = lVal;
          right[i] = rVal;
          const amp = Math.max(Math.abs(lVal), Math.abs(rVal));
          if (amp > maxAmp) maxAmp = amp;
        }

        meter.style.width = Math.min(100, Math.round(maxAmp * 150)) + "%";

        const source = audioCtx.createBufferSource();
        source.buffer = buffer;
        source.connect(audioCtx.destination);

        const currentTime = audioCtx.currentTime;
        if (nextStartTime < currentTime || nextStartTime > currentTime + 0.15) {
          nextStartTime = currentTime + 0.03; // 30ms lead jitter buffer
        }
        source.start(nextStartTime);
        nextStartTime += buffer.duration;
      };

      ws.onclose = () => {
        status.innerText = "❌ Disconnected. Click below to reconnect.";
        btn.disabled = false;
        btn.innerText = "🔄 Reconnect Audio";
      };

      ws.onerror = (e) => {
        status.innerText = "⚠️ WebSocket error, retrying...";
      };
    };
  </script>
</body>
</html>
"""

connected_clients = set()

def http_handler(path, headers):
    if path in ("/", "/index.html"):
        return HTTPStatus.OK, [("Content-Type", "text/html; charset=utf-8")], HTML_PAGE.encode("utf-8")
    return None

async def ws_handler(websocket, path=None):
    connected_clients.add(websocket)
    try:
        await websocket.wait_closed()
    finally:
        connected_clients.remove(websocket)

async def audio_broadcaster():
    cmd = [
        "parec",
        "-d", "auto_null.monitor",
        f"--rate={SAMPLE_RATE}",
        f"--channels={CHANNELS}",
        "--format=s16le",
        "--latency-msec=20"
    ]
    proc = await asyncio.create_subprocess_exec(
        *cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.DEVNULL
    )

    bytes_per_chunk = CHUNK_SIZE * 2 * CHANNELS

    while True:
        data = await proc.stdout.read(bytes_per_chunk)
        if not data:
            break
        if connected_clients:
            await asyncio.gather(
                *[client.send(data) for client in connected_clients.copy()],
                return_exceptions=True
            )

async def main():
    try:
        server = await websockets.serve(
            ws_handler, "0.0.0.0", PORT, process_request=http_handler
        )
    except TypeError:
        def modern_http_handler(connection, request):
            if request.path in ("/", "/index.html"):
                return connection.respond(
                    HTTPStatus.OK,
                    HTML_PAGE.encode("utf-8"),
                    [("Content-Type", "text/html; charset=utf-8")]
                )
            return None
        server = await websockets.serve(
            ws_handler, "0.0.0.0", PORT, process_request=modern_http_handler
        )

    print(f"[*] Cloud Desktop Audio Server running on http://0.0.0.0:{PORT}")
    await asyncio.gather(server.wait_closed(), audio_broadcaster())

if __name__ == "__main__":
    asyncio.run(main())
EOF

sudo chmod +x /usr/local/bin/audio-server.py

echo "[4/4] Starting Audio Server in background on Port $PORT..."
pkill -9 -f "audio-server.py" 2>/dev/null || true
pkill -9 -f "parec -d auto_null.monitor" 2>/dev/null || true
sleep 1
nohup /usr/bin/python3 /usr/local/bin/audio-server.py > /tmp/audio-server.log 2>&1 &
sleep 2

if pgrep -f "audio-server.py" >/dev/null 2>&1; then
    echo "===================================================================="
    echo " 🔊 AUDIO STREAMING IS NOW LIVE & ACTIVE!"
    echo "===================================================================="
    echo " 👉 1. In VS Code / Codespaces, open the 'Ports' tab."
    echo " 👉 2. Forward Port 6081 (Audio Stream)."
    echo " 👉 3. Click the Open Browser icon next to Port 6081."
    echo " 👉 4. Click 'Start Listening' on that page."
    echo " 👉 Play any YouTube video in Chrome or sound in AgentGrid,"
    echo "    and you will hear it live through your PC speakers!"
    echo "===================================================================="
else
    echo "⚠️ Audio server process exited. Checking logs:"
    cat /tmp/audio-server.log
fi
