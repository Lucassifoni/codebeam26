#!/usr/bin/env bash
# Compile-only sanity check for a module (MODULE env, default module_1).
# Extra args pass through to arduino-cli (e.g. --warnings all).
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
exec arduino-cli compile --libraries "$LIBRARIES_DIR" "$SKETCH_DIR" "$@"
