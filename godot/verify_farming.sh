#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
GODOT="${GODOT:-$HOME/Applications/Godot.app/Contents/MacOS/Godot}"
mkdir -p outputs
"$GODOT" --headless --path . --script res://tests/test_farming.gd > outputs/farming-tests.log 2>&1
cat outputs/farming-tests.log
if grep -Eq 'SCRIPT ERROR|ERROR:|FAIL' outputs/farming-tests.log; then exit 1; fi
bash verify_surface.sh
"$GODOT" --headless --path . --script res://tests/test_core.gd > outputs/farming-core.log 2>&1
tail -3 outputs/farming-core.log
if grep -Eq 'SCRIPT ERROR|ERROR:|FAIL' outputs/farming-core.log; then exit 1; fi
