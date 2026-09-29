#!/usr/bin/env bash
set -e

# Run the installation script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/.devcontainer/install-agentgrid.sh" "$@"
