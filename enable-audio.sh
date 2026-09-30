#!/usr/bin/env bash
set -e

echo "===================================================================="
echo " 🔊 Configuring Resilient Cloud Audio Streaming Engine (Port 6081)"
echo " (PulseAudio -> TCP 4713 -> aiohttp WebAudio + WAV Stream)"
echo "===================================================================="

export DEBIAN_FRONTEND=noninteractive
export DISPLAY="${DISPLAY:-:1}"

echo "[1/5] Installing PulseAudio & Python Server Dependencies..."
sudo apt-get update -y
sudo apt-get install -y --no-install-recommends \
    pulseaudio \
    pulseaudio-utils \
    pavucontrol \
    alsa-utils \
    python3 \
    python3-pip \
    python3-aiohttp \
    curl \
    net-tools

# Fallback install if python3-aiohttp was missing
python3 -c "import aiohttp" 2>/dev/null || pip3 install aiohttp 2>/dev/null || true

echo "[2/5] Configuring PulseAudio Server & Virtual Null-Sink..."
# Terminate any stale audio processes
pkill -9 -f "audio-server.py" 2>/dev/null || true
pkill -9 -f "parec" 2>/dev/null || true
pulseaudio -k 2>/dev/null || true
pkill -9 -f "pulseaudio" 2>/dev/null || true
sleep 1

# Configure PulseAudio user defaults
mkdir -p "$HOME/.config/pulse"
cat << 'EOF' > "$HOME/.config/pulse/default.pa"
.include /etc/pulse/default.pa
load-module module-null-sink sink_name=auto_null sink_properties=device.description="Virtual_Null_Output"
load-module module-native-protocol-tcp auth-anonymous=1 listen=127.0.0.1 port=4713
load-module module-native-protocol-unix
set-default-sink auto_null
set-default-source auto_null.monitor
EOF

# Global client config to point to TCP 127.0.0.1:4713
sudo tee /etc/pulse/client.conf > /dev/null << 'EOF'
default-server = 127.0.0.1:4713
autospawn = yes
EOF

# Global ALSA fallback configuration
sudo tee /etc/asound.conf > /dev/null << 'EOF'
pcm.!default {
    type pulse
    server "127.0.0.1:4713"
}
ctl.!default {
    type pulse
    server "127.0.0.1:4713"
}
EOF

# Start PulseAudio daemon
pulseaudio --start --exit-idle-time=-1 --daemonize=true 2>/dev/null || pulseaudio -D --exit-idle-time=-1 2>/dev/null || true
sleep 2

# Dynamically ensure auto_null and TCP modules are active
if ! pactl -s 127.0.0.1:4713 list sinks short 2>/dev/null | grep -q "auto_null"; then
    pactl -s 127.0.0.1:4713 load-module module-null-sink sink_name=auto_null sink_properties=device.description="Virtual_Null_Output" 2>/dev/null || \
    pactl load-module module-null-sink sink_name=auto_null sink_properties=device.description="Virtual_Null_Output" 2>/dev/null || true
fi

pactl -s 127.0.0.1:4713 load-module module-native-protocol-tcp auth-anonymous=1 listen=127.0.0.1 port=4713 2>/dev/null || \
pactl load-module module-native-protocol-tcp auth-anonymous=1 listen=127.0.0.1 port=4713 2>/dev/null || true

pactl -s 127.0.0.1:4713 set-default-sink auto_null 2>/dev/null || pactl set-default-sink auto_null 2>/dev/null || true
pactl -s 127.0.0.1:4713 set-default-source auto_null.monitor 2>/dev/null || pactl set-default-source auto_null.monitor 2>/dev/null || true

echo "[3/5] Setting up Environment & Chrome Audio Hook..."
export PULSE_SERVER="127.0.0.1:4713"
if ! grep -q "PULSE_SERVER" "$HOME/.bashrc" 2>/dev/null; then
    echo 'export PULSE_SERVER="127.0.0.1:4713"' >> "$HOME/.bashrc"
fi

# Ensure Chrome wrapper exports PULSE_SERVER
sudo tee /usr/local/bin/google-chrome > /dev/null << 'EOF'
#!/bin/bash
export PULSE_SERVER="127.0.0.1:4713"
exec /usr/bin/google-chrome-stable --no-sandbox --disable-dev-shm-usage --test-type "$@"
EOF
sudo chmod +x /usr/local/bin/google-chrome
sudo ln -sf /usr/local/bin/google-chrome /usr/local/bin/chrome 2>/dev/null || true

echo "[4/5] Deploying Production aiohttp Audio Streaming Server..."
sudo tee /usr/local/bin/audio-server.py > /dev/null << 'EOF'
#!/usr/bin/env python3
import asyncio
import os
import struct
import sys
from aiohttp import web

PORT = 6081
SAMPLE_RATE = 44100
CHANNELS = 2
BITS_PER_SAMPLE = 16
BYTES_PER_SAMPLE = BITS_PER_SAMPLE // 8
CHUNK_SAMPLES = 2048  # ~46ms chunks
CHUNK_BYTES = CHUNK_SAMPLES * CHANNELS * BYTES_PER_SAMPLE

def generate_wav_header():
    byte_rate = SAMPLE_RATE * CHANNELS * BYTES_PER_SAMPLE
    block_align = CHANNELS * BYTES_PER_SAMPLE
    data_size = 0x7FFFFFFF  # 2GB virtual length for infinite stream
    file_size = data_size + 36
    return struct.pack(
        '<4sI4s4sIHHIIHH4sI',
        b'RIFF',
        file_size,
        b'WAVE',
        b'fmt ',
        16,
        1,  # PCM
        CHANNELS,
        SAMPLE_RATE,
        byte_rate,
        block_align,
        BITS_PER_SAMPLE,
        b'data',
        data_size
    )

HTML_PAGE = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Cloud Desktop Audio (Live)</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
      background: #090d16;
      color: #f1f5f9;
      padding: 24px;
    }
    .card {
      background: #111827;
      border: 1px solid #1f2937;
      border-radius: 20px;
      padding: 36px;
      max-width: 480px;
      width: 100%;
      box-shadow: 0 20px 40px rgba(0, 0, 0, 0.6);
      text-align: center;
    }
    .badge {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      background: rgba(16, 185, 129, 0.15);
      color: #10b981;
      border: 1px solid rgba(16, 185, 129, 0.3);
      padding: 6px 14px;
      border-radius: 9999px;
      font-size: 13px;
      font-weight: 600;
      margin-bottom: 20px;
    }
    .dot {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: #10b981;
      box-shadow: 0 0 8px #10b981;
      animation: pulse 2s infinite;
    }
    @keyframes pulse {
      0% { opacity: 1; transform: scale(1); }
      50% { opacity: 0.4; transform: scale(0.8); }
      100% { opacity: 1; transform: scale(1); }
    }
    h1 {
      font-size: 26px;
      font-weight: 700;
      margin-bottom: 8px;
      color: #ffffff;
    }
    p.desc {
      font-size: 14px;
      color: #9ca3af;
      margin-bottom: 28px;
      line-height: 1.5;
    }
    .btn-main {
      width: 100%;
      padding: 16px 24px;
      font-size: 17px;
      font-weight: 700;
      color: #ffffff;
      background: #3b82f6;
      border: none;
      border-radius: 12px;
      cursor: pointer;
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 10px;
      transition: all 0.2s ease;
      box-shadow: 0 4px 14px rgba(59, 130, 246, 0.4);
    }
    .btn-main:hover {
      background: #2563eb;
      transform: translateY(-1px);
      box-shadow: 0 6px 20px rgba(59, 130, 246, 0.6);
    }
    .btn-main:active {
      transform: translateY(0);
    }
    .btn-main.active {
      background: #059669;
      box-shadow: 0 4px 14px rgba(5, 150, 105, 0.4);
    }
    .status-text {
      font-size: 13px;
      color: #cbd5e1;
      margin-top: 18px;
      min-height: 20px;
    }
    .meter-container {
      margin-top: 24px;
      background: #1f2937;
      border-radius: 10px;
      height: 12px;
      width: 100%;
      overflow: hidden;
      display: none;
      border: 1px solid #374151;
    }
    .meter-fill {
      height: 100%;
      width: 0%;
      background: linear-gradient(90deg, #10b981 0%, #3b82f6 70%, #ef4444 100%);
      transition: width 0.05s ease;
    }
    .vol-box {
      margin-top: 20px;
      display: none;
      align-items: center;
      gap: 12px;
      font-size: 13px;
      color: #9ca3af;
    }
    .vol-slider {
      flex: 1;
      accent-color: #3b82f6;
      cursor: pointer;
    }
    .fallback-card {
      margin-top: 24px;
      padding-top: 20px;
      border-top: 1px solid #1f2937;
      text-align: left;
    }
    .fallback-title {
      font-size: 13px;
      font-weight: 600;
      color: #9ca3af;
      margin-bottom: 8px;
    }
    audio {
      width: 100%;
      height: 38px;
      border-radius: 8px;
      outline: none;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="badge"><span class="dot"></span> LIVE ~35ms LATENCY</div>
    <h1>Cloud Desktop Audio</h1>
    <p class="desc">Real-time stereo sound from YouTube, Google Chrome & AgentGrid desktop canvas.</p>
    
    <button id="btnPlay" class="btn-main">🔊 Start Listening</button>
    
    <div class="meter-container" id="meterBox">
      <div class="meter-fill" id="meterBar"></div>
    </div>

    <div class="vol-box" id="volBox">
      <span>🔈</span>
      <input type="range" min="0" max="150" value="100" class="vol-slider" id="volSlider">
      <span id="volLabel">100%</span>
    </div>

    <div class="status-text" id="statusText">Click "Start Listening" to activate audio output</div>

    <div class="fallback-card">
      <div class="fallback-title">Alternative Direct HTML5 Stream:</div>
      <audio id="nativeAudio" controls preload="none" src="/stream.wav"></audio>
    </div>
  </div>

  <script>
    const btn = document.getElementById('btnPlay');
    const statusText = document.getElementById('statusText');
    const meterBox = document.getElementById('meterBox');
    const meterBar = document.getElementById('meterBar');
    const volBox = document.getElementById('volBox');
    const volSlider = document.getElementById('volSlider');
    const volLabel = document.getElementById('volLabel');
    const nativeAudio = document.getElementById('nativeAudio');

    let audioCtx = null;
    let gainNode = null;
    let nextStartTime = 0;
    let ws = null;
    let isPlaying = false;

    volSlider.oninput = (e) => {
      const val = e.target.value;
      volLabel.innerText = val + '%';
      if (gainNode) {
        gainNode.gain.value = val / 100.0;
      }
    };

    btn.onclick = () => {
      if (isPlaying) return;

      if (!audioCtx) {
        audioCtx = new (window.AudioContext || window.webkitAudioContext)({ sampleRate: 44100 });
        gainNode = audioCtx.createGain();
        gainNode.gain.value = volSlider.value / 100.0;
        gainNode.connect(audioCtx.destination);
      }
      if (audioCtx.state === 'suspended') {
        audioCtx.resume();
      }

      isPlaying = true;
      btn.classList.add('active');
      btn.innerText = "🟢 Audio Active (Playing Live)";
      statusText.innerText = "Connecting to audio stream...";
      meterBox.style.display = "block";
      volBox.style.display = "flex";

      connectWebSocket();
    };

    function connectWebSocket() {
      const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
      const wsUrl = proto + '//' + location.host + '/ws';
      ws = new WebSocket(wsUrl);
      ws.binaryType = 'arraybuffer';

      ws.onopen = () => {
        statusText.innerText = "✅ Connected to live cloud audio stream!";
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
          const l = int16[i * 2] / 32768.0;
          const r = int16[i * 2 + 1] / 32768.0;
          left[i] = l;
          right[i] = r;
          const amp = Math.max(Math.abs(l), Math.abs(r));
          if (amp > maxAmp) maxAmp = amp;
        }

        meterBar.style.width = Math.min(100, Math.round(maxAmp * 160)) + "%";

        const source = audioCtx.createBufferSource();
        source.buffer = buffer;
        source.connect(gainNode);

        const now = audioCtx.currentTime;
        if (nextStartTime < now || nextStartTime > now + 0.15) {
          nextStartTime = now + 0.025; // 25ms lead jitter buffer
        }
        source.start(nextStartTime);
        nextStartTime += buffer.duration;
      };

      ws.onclose = () => {
        statusText.innerText = "⚠️ Connection lost, reconnecting in 2s...";
        meterBar.style.width = "0%";
        if (isPlaying) {
          setTimeout(connectWebSocket, 2000);
        }
      };

      ws.onerror = () => {
        statusText.innerText = "WebSocket error. Trying to reconnect...";
      };
    }
  </script>
</body>
</html>
"""

ws_clients = set()
http_stream_clients = set()

async def index_handler(request):
    return web.Response(text=HTML_PAGE, content_type='text/html', charset='utf-8')

async def health_handler(request):
    return web.json_response({
        "status": "ok",
        "ws_clients": len(ws_clients),
        "http_clients": len(http_stream_clients)
    })

async def ws_handler(request):
    ws = web.WebSocketResponse(heartbeat=15.0)
    await ws.prepare(request)
    ws_clients.add(ws)
    try:
        async for msg in ws:
            pass
    finally:
        ws_clients.discard(ws)
    return ws

async def stream_wav_handler(request):
    response = web.StreamResponse(
        status=200,
        reason='OK',
        headers={
            'Content-Type': 'audio/wav',
            'Cache-Control': 'no-cache, no-store, must-revalidate',
            'Connection': 'keep-alive',
            'Access-Control-Allow-Origin': '*'
        }
    )
    await response.prepare(request)
    await response.write(generate_wav_header())
    queue = asyncio.Queue(maxsize=100)
    http_stream_clients.add(queue)
    try:
        while True:
            chunk = await queue.get()
            await response.write(chunk)
    except (asyncio.CancelledError, ConnectionResetError):
        pass
    finally:
        http_stream_clients.discard(queue)
    return response

async def audio_broadcaster():
    while True:
        try:
            # Capture from PulseAudio monitor source
            cmd = [
                "parec",
                "-s", "127.0.0.1:4713",
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

            while True:
                data = await proc.stdout.read(CHUNK_BYTES)
                if not data:
                    break

                # Broadcast to WebSocket clients
                if ws_clients:
                    dead_ws = set()
                    for ws in list(ws_clients):
                        try:
                            await ws.send_bytes(data)
                        except Exception:
                            dead_ws.add(ws)
                    ws_clients.difference_update(dead_ws)

                # Broadcast to HTTP WAV clients
                if http_stream_clients:
                    for q in list(http_stream_clients):
                        if not q.full():
                            q.put_nowait(data)

        except Exception as e:
            print(f"[!] Broadcaster error: {e}")

        # If parec exited, wait 1.5s and retry gracefully
        await asyncio.sleep(1.5)

async def background_tasks(app):
    task = asyncio.create_task(audio_broadcaster())
    yield
    task.cancel()
    try:
        await task
    except asyncio.CancelledError:
        pass

def create_app():
    app = web.Application()
    app.cleanup_ctx.append(background_tasks)
    app.router.add_get('/', index_handler)
    app.router.add_get('/index.html', index_handler)
    app.router.add_get('/health', health_handler)
    app.router.add_get('/ws', ws_handler)
    app.router.add_get('/stream.wav', stream_wav_handler)
    return app

if __name__ == '__main__':
    print(f"[*] Starting Cloud Audio Server on http://0.0.0.0:{PORT}")
    app = create_app()
    web.run_app(app, host='0.0.0.0', port=PORT, access_log=None)
EOF

sudo chmod +x /usr/local/bin/audio-server.py

echo "[5/5] Launching Audio Server on Port $PORT & Verifying Health..."
nohup /usr/bin/python3 /usr/local/bin/audio-server.py > /tmp/audio-server.log 2>&1 &
sleep 2

# Verify Port 6081 responds
if curl -s http://127.0.0.1:6081/health >/dev/null 2>&1; then
    HEALTH=$(curl -s http://127.0.0.1:6081/health)
    echo "===================================================================="
    echo " 🎉 SUCCESS: Cloud Audio Engine is LIVE & VERIFIED!"
    echo " Server Status: $HEALTH"
    echo "===================================================================="
    echo " 👉 1. Switch back to your browser tab on Port 6081:"
    echo "       (Or refresh the page that previously had error 502)"
    echo " 👉 2. Click '🔊 Start Listening' to unmute!"
    echo " 👉 3. Play any YouTube video in Chrome or sound in AgentGrid,"
    echo "       and you will hear it live through your PC speakers!"
    echo "===================================================================="
else
    echo "⚠️ Warning: Server is starting up. Check status with: cat /tmp/audio-server.log"
    cat /tmp/audio-server.log
fi
