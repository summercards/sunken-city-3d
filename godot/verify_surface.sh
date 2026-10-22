#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
GODOT="${GODOT:-$HOME/Applications/Godot.app/Contents/MacOS/Godot}"
mkdir -p outputs
"$GODOT" --headless --path . --script res://tests/test_surface_movement.gd > outputs/surface-tests.log 2>&1
cat outputs/surface-tests.log
if grep -Eq 'SCRIPT ERROR|ERROR:|FAIL' outputs/surface-tests.log; then exit 1; fi
"$GODOT" --headless --path . -- --selftest > outputs/surface-selftest.log 2>&1
tail -3 outputs/surface-selftest.log
# 存档测试刻意传入坏 JSON，允许它的精确负例诊断。
if grep -Ev '^ERROR: Parse JSON failed\. Error at line 0: Expected key$' outputs/surface-selftest.log | grep -Eq 'SCRIPT ERROR|ERROR:|FAIL'; then exit 1; fi
echo '地面 / 泊位 / 种植 / 航行验收通过。'
