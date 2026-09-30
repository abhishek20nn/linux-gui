#!/usr/bin/env bash
set -e

# Determine workspace directory
WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$WORKSPACE_DIR/.persistent_state"

mkdir -p "$STATE_DIR/keyrings"
mkdir -p "$STATE_DIR/google-chrome"
mkdir -p "$STATE_DIR/AgentGrid"
mkdir -p "$STATE_DIR/Agent Grid"

# 1. If any old symlinks exist from previous run, convert them back to real directories
for d in "$HOME/.local/share/keyrings" "$HOME/.config/google-chrome" "$HOME/.config/Agent Grid" "$HOME/.config/AgentGrid"; do
    if [ -L "$d" ]; then
        target="$(readlink -f "$d")"
        rm -f "$d"
        mkdir -p "$d"
        if [ -d "$target" ]; then
            cp -a "$target/." "$d/" 2>/dev/null || true
        fi
    fi
done

# 2. Ensure real physical directories exist with strict permissions
mkdir -p "$HOME/.local/share/keyrings"
chmod 700 "$HOME/.local/share/keyrings"
mkdir -p "$HOME/.config/google-chrome"
mkdir -p "$HOME/.config/Agent Grid"
mkdir -p "$HOME/.config/AgentGrid"

# 3. Restore saved state from persistent storage into physical directories
if [ -d "$STATE_DIR/keyrings" ] && [ "$(ls -A "$STATE_DIR/keyrings" 2>/dev/null)" ]; then
    cp -au "$STATE_DIR/keyrings/." "$HOME/.local/share/keyrings/" 2>/dev/null || true
    chmod 700 "$HOME/.local/share/keyrings"
fi

if [ -d "$STATE_DIR/google-chrome" ] && [ "$(ls -A "$STATE_DIR/google-chrome" 2>/dev/null)" ]; then
    cp -au "$STATE_DIR/google-chrome/." "$HOME/.config/google-chrome/" 2>/dev/null || true
fi

if [ -d "$STATE_DIR/Agent Grid" ] && [ "$(ls -A "$STATE_DIR/Agent Grid" 2>/dev/null)" ]; then
    cp -au "$STATE_DIR/Agent Grid/." "$HOME/.config/Agent Grid/" 2>/dev/null || true
fi

# 4. Clean temporary singleton lock files
find "$HOME/.config" -name "Singleton*" -delete 2>/dev/null || true

# 5. Background sync daemon: continuously mirrors session data back to .persistent_state
if ! pgrep -f "sync-persistence-daemon" >/dev/null 2>&1; then
    nohup bash -c '
    exec -a sync-persistence-daemon bash -c "
    while true; do
        sleep 45
        cp -au \"$HOME/.local/share/keyrings/.\" \"'"$STATE_DIR"'\"/keyrings/ 2>/dev/null || true
        cp -au \"$HOME/.config/google-chrome/.\" \"'"$STATE_DIR"'\"/google-chrome/ 2>/dev/null || true
        cp -au \"$HOME/.config/Agent Grid/.\" \"'"$STATE_DIR"'\"/Agent Grid/ 2>/dev/null || true
    done
    "
    ' > /dev/null 2>&1 &
fi
