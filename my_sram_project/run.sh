#!/usr/bin/env bash
# =============================================================================
#  run.sh — Run OpenRAM with sram_config.py
#
#  Usage:
#    chmod +x run.sh
#    ./run.sh
#
#  Optionally pass a different config file:
#    ./run.sh my_other_config.py
# =============================================================================

set -euo pipefail

CONFIG="${1:-sram_config.py}"

# Check env
if [[ -z "${OPENRAM_HOME:-}" ]]; then
    echo "[✘] OPENRAM_HOME is not set."
    echo "    Run:  source ~/.bashrc  (or source ~/.zshrc)"
    exit 1
fi

if [[ ! -f "$CONFIG" ]]; then
    echo "[✘] Config file not found: $CONFIG"
    exit 1
fi

echo "[▶] Running OpenRAM with: $CONFIG"
echo ""
python3 "$OPENRAM_HOME/../sram_compiler.py" "$CONFIG"
