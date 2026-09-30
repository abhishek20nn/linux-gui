#!/usr/bin/env bash
set -e

echo "===================================================================="
echo " 🚀 Delegating to Unified AgentGrid Launcher (fix-keyring.sh)"
echo "===================================================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/fix-keyring.sh" ]; then
    bash "$SCRIPT_DIR/fix-keyring.sh"
else
    echo "❌ Error: fix-keyring.sh not found in $SCRIPT_DIR"
    exit 1
fi
