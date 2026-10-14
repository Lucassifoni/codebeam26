#!/usr/bin/env bash
# List connected boards / serial ports, to discover or confirm the upload port.
set -euo pipefail
cd "$(dirname "$0")/.."
exec arduino-cli board list "$@"
