#!/usr/bin/env bash
set -e

echo "===================================================================="
echo " 📋 Starting Safe X11 Clipboard Synchronization"
echo "===================================================================="

export DISPLAY="${DISPLAY:-:1}"

echo "[1/2] Installing clipboard tools (autocutsel, xclip, xsel)..."
sudo apt-get update -y
sudo apt-get install -y --no-install-recommends autocutsel xclip xsel

echo "[2/2] Starting autocutsel daemon for X11 selection sync..."
pkill -9 autocutsel 2>/dev/null || true
autocutsel -fork || true
autocutsel -selection PRIMARY -fork || true

echo "✅ X11 Clipboard Sync is ACTIVE!"
