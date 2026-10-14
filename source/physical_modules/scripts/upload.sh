#!/usr/bin/env bash
# Compile + flash a module (MODULE env, default module_1).
# Port: PORT env overrides; otherwise sketch.yaml default_port is used.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

args=(--libraries "$LIBRARIES_DIR" --build-path "$BUILD_DIR" --upload)
if [[ -n "${PORT:-}" ]]; then
  args+=(--port "$PORT")
fi

exec arduino-cli compile "${args[@]}" "$SKETCH_DIR" "$@"
