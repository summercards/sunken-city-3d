#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export GODOT="${GODOT:-$HOME/Applications/Godot.app/Contents/MacOS/Godot}"
bash verify_farming.sh
"$GODOT" --headless --path . --script res://tests/test_click_controls.gd > outputs/click-controls-tests.log 2>&1
cat outputs/click-controls-tests.log
if grep -Eq 'SCRIPT ERROR|ERROR:|FAIL' outputs/click-controls-tests.log; then exit 1; fi
if [[ "${1:-}" == "--visual" ]]; then
  for test in click_controls farm_cycle; do
    "$GODOT" --path . --resolution 1280x800 --fixed-fps 60 --script "res://tools/capture_${test}.gd" > "outputs/${test}-ui.log" 2>&1
    cat "outputs/${test}-ui.log"
    if grep -Eq 'SCRIPT ERROR|ERROR:|FAIL' "outputs/${test}-ui.log"; then exit 1; fi
  done
fi
