#!/usr/bin/env bash
# Build a module (MODULE env, default module_1) into build/<module>/.
# Emits build/<module>/compile_commands.json for clangd-based editors.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
exec arduino-cli compile \
  --libraries "$LIBRARIES_DIR" \
  --build-path "$BUILD_DIR" \
  "$SKETCH_DIR" "$@"
