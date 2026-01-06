#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

# 1) Setup env
echo "Running setup..."
./setup_env.sh

# 2) Start tmux session to run services
echo "Starting tmux session to launch services..."
./run_tmux.sh

echo "All done. Use 'tmux attach -t rhythm_game' to view the sessions."