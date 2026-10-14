#!/usr/bin/env bash
# Shared helpers sourced by the other scripts. Resolves the repo root, the
# target module (arg or MODULE env, default module_1), and common paths.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIBRARIES_DIR="$ROOT/lib"

MODULE="${MODULE:-module_1}"
SKETCH_DIR="$ROOT/modules/$MODULE"
BUILD_DIR="$ROOT/build/$MODULE"

if [[ ! -d "$SKETCH_DIR" ]]; then
  echo "error: module '$MODULE' not found at $SKETCH_DIR" >&2
  echo "available modules: $(ls "$ROOT/modules" 2>/dev/null | tr '\n' ' ')" >&2
  exit 1
fi
