#!/usr/bin/env bash
set -e

echo "===================================================================="
echo " 🔊 Instant Audio Test & Chrome Audio Linker"
echo "===================================================================="

# 1. Install missing ALSA-PulseAudio plugins if not present
if ! dpkg -l | grep -q "libasound2-plugins"; then
    echo "Installing libasound2-plugins..."
    sudo apt-get update -y && sudo apt-get install -y --no-install-recommends libasound2-plugins
fi

# 2. Unmute all sinks and sources
echo "[1/4] Unmuting PulseAudio and setting 100% volume..."
pactl set-sink-mute auto_null 0 2>/dev/null || true
pactl set-sink-volume auto_null 65536 2>/dev/null || true
pactl set-source-mute auto_null.monitor 0 2>/dev/null || true
pactl set-source-volume auto_null.monitor 65536 2>/dev/null || true

pactl -s 127.0.0.1:4713 set-sink-mute auto_null 0 2>/dev/null || true
pactl -s 127.0.0.1:4713 set-sink-volume auto_null 65536 2>/dev/null || true
pactl -s 127.0.0.1:4713 set-source-mute auto_null.monitor 0 2>/dev/null || true
pactl -s 127.0.0.1:4713 set-source-volume auto_null.monitor 65536 2>/dev/null || true

# 3. Play a test chime right now!
echo "[2/4] 🎵 Playing 2-second loud test chime directly into auto_null..."
python3 -c "
import math, struct, subprocess
sample_rate = 44100
tones = [(523.25, 0.35), (659.25, 0.35), (783.99, 0.35), (1046.50, 0.8)]
data = bytearray()
for freq, dur in tones:
    n = int(sample_rate * dur)
    for i in range(n):
        val = int(32767.0 * 0.8 * math.sin(2.0 * math.pi * freq * i / sample_rate))
        data.extend(struct.pack('<hh', val, val))
for target in ['auto_null', None]:
    try:
        cmd = ['paplay', '--raw', '--rate=44100', '--channels=2', '--format=s16le']
        if target:
            cmd.extend(['-d', target])
        p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stderr=subprocess.DEVNULL)
        p.communicate(input=bytes(data))
        break
    except Exception:
        continue
" 2>/dev/null || true

# 4. Check active audio streams
echo "[3/4] Active audio streams inside PulseAudio:"
SINK_INPUTS=$(pactl list sink-inputs short 2>/dev/null || echo "")
if [ -n "$SINK_INPUTS" ]; then
    echo "$SINK_INPUTS"
else
    echo "⚠️ No application is currently sending sound to PulseAudio."
fi

# 5. Restart Chrome with full PulseAudio link
echo "[4/4] Restarting Google Chrome with PulseAudio link..."
pkill -f "chrome" 2>/dev/null || true
pkill -f "google-chrome" 2>/dev/null || true
sleep 1

export DISPLAY="${DISPLAY:-:1}"
export PULSE_SERVER="127.0.0.1:4713"
export ALSA_CARD=pulse

nohup /usr/bin/google-chrome-stable \
    --no-sandbox \
    --disable-dev-shm-usage \
    --test-type \
    --autoplay-policy=no-user-gesture-required \
    --alsa-output-device=pulse \
    https://www.youtube.com > /tmp/chrome.log 2>&1 &

echo "===================================================================="
echo " 🚀 Google Chrome has been restarted on your desktop with YouTube!"
echo " 👉 1. Switch to your browser tab on Port 6081 (Cloud Desktop Audio)."
echo "       Check if the volume meter moved during the test chime!"
echo " 👉 2. On Port 6080 (Desktop), play any video in the newly opened Chrome."
echo " 👉 IMPORTANT: Ensure the YouTube video player itself is UNMUTED 🔊!"
echo "===================================================================="
