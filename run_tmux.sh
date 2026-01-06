#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

SESSION_NAME="rhythm_game"
VENV="$ROOT_DIR/.venv"

# Check tmux
if ! command -v tmux >/dev/null 2>&1; then
  echo "Error: 'tmux' is required but not found. Install tmux and re-run this script." >&2
  exit 1
fi

# Create session
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  echo "tmux session '$SESSION_NAME' already exists. Attach with: tmux attach -t $SESSION_NAME";
  exit 0
fi

# Start detached session
tmux new-session -d -s "$SESSION_NAME" -n python_game

# Pane 0: game.py (interactive OpenCV window)
CMD0="cd '$ROOT_DIR' && source '$VENV/bin/activate' && python3 game.py --source 0"
# Pane 1: threshold_optimizer (logs to file)
CMD1="cd '$ROOT_DIR' && source '$VENV/bin/activate' && python3 threshold_optimizer.py > logs/threshold_optimizer.log 2>&1"
# Pane 2: pose_judge_sim (logs to file)
CMD2="cd '$ROOT_DIR' && source '$VENV/bin/activate' && python3 pose_judge_sim.py > logs/pose_judge_sim.log 2>&1"
# Pane 3: generate_default_config (one-shot)
CMD3="cd '$ROOT_DIR' && source '$VENV/bin/activate' && python3 generate_default_config.py > logs/generate_default_config.log 2>&1"
# Pane 4: Flutter app
CMD4="cd '$ROOT_DIR/flutter_application_1' && flutter run -d linux"

# Send commands to panes
tmux send-keys -t $SESSION_NAME:0.0 "$CMD0" C-m
# split horizontally for pane 1
tmux split-window -h -t $SESSION_NAME:0.0
tmux send-keys -t $SESSION_NAME:0.1 "$CMD1" C-m
# split vertically pane 2 on left
tmux select-pane -t $SESSION_NAME:0.0
tmux split-window -v -t $SESSION_NAME:0.0
tmux send-keys -t $SESSION_NAME:0.2 "$CMD2" C-m
# split vertically pane 3 on right
tmux select-pane -t $SESSION_NAME:0.1
tmux split-window -v -t $SESSION_NAME:0.1
tmux send-keys -t $SESSION_NAME:0.3 "$CMD3" C-m
# create a new window for Flutter
tmux new-window -t $SESSION_NAME -n flutter
tmux send-keys -t $SESSION_NAME:flutter.0 "$CMD4" C-m

# Give user attach instructions
echo "Started tmux session '$SESSION_NAME' with panes:" 
echo " - pane 0: game (OpenCV window, interactive)"
echo " - pane 1: threshold_optimizer -> logs/threshold_optimizer.log"
echo " - pane 2: pose_judge_sim -> logs/pose_judge_sim.log"
echo " - pane 3: generate_default_config -> logs/generate_default_config.log"
echo " - window 'flutter': flutter run (desktop)"

echo "Attach with: tmux attach -t $SESSION_NAME"

echo "If you need to stop everything, attach to the session and send Ctrl-C in each pane, or kill the session: tmux kill-session -t $SESSION_NAME"