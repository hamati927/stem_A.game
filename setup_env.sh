#!/usr/bin/env bash
set -euo pipefail

# Setup Python virtual environment and install dependencies for rhythm_game
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

VENV_DIR="$ROOT_DIR/.venv"
if [ -d "$VENV_DIR" ]; then
  echo "Using existing venv at $VENV_DIR"
else
  echo "Creating virtualenv at $VENV_DIR"
  python3 -m venv "$VENV_DIR"
fi

# Activate and install
# shellcheck source=/dev/null
source "$VENV_DIR/bin/activate"

python -m pip install --upgrade pip
if [ -f "$ROOT_DIR/requirements.txt" ]; then
  pip install -r "$ROOT_DIR/requirements.txt"
fi
# ensure common scientific deps
pip install numpy matplotlib

# Create logs and configs directories if not exist
mkdir -p "$ROOT_DIR/logs"
mkdir -p "$ROOT_DIR/configs"

# Report flutter availability
if command -v flutter >/dev/null 2>&1; then
  echo "Flutter found: $(flutter --version | head -n 1)"
else
  echo "Warning: 'flutter' command not found. Install Flutter if you plan to run the Flutter app (flutter_application_1)."
fi

echo "Setup complete. To activate the venv: source $VENV_DIR/bin/activate"