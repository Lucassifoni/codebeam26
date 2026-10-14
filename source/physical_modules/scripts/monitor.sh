#!/usr/bin/env bash
# Open the serial monitor. Override port/baud: PORT=... BAUD=... ./scripts/monitor.sh
# Quit with Ctrl-C.
set -euo pipefail
cd "$(dirname "$0")/.."
PORT="${PORT:-/dev/cu.usbserial-1240}"
BAUD="${BAUD:-115200}"
exec arduino-cli monitor --port "$PORT" --config "baudrate=$BAUD"
