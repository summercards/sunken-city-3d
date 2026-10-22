#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
GODOT="${GODOT:-$HOME/Applications/Godot.app/Contents/MacOS/Godot}"
mkdir -p outputs
"$GODOT" --headless --path . --script res://tests/test_management_loop.gd > outputs/management-tests.log 2>&1
cat outputs/management-tests.log
if grep -Eq 'SCRIPT ERROR|ERROR:|FAIL' outputs/management-tests.log; then exit 1; fi
if [[ "${1:-}" == "--visual" ]]; then
  "$GODOT" --path . --resolution 1600x1000 --script res://tools/capture_management_loop.gd > outputs/management-ui.log 2>&1
  cat outputs/management-ui.log
  if grep -Eq 'SCRIPT ERROR|ERROR:|FAIL' outputs/management-ui.log; then exit 1; fi
fi
