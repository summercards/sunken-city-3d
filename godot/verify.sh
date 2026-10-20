#!/bin/sh
# 一键验收：核心逻辑 parity + 场景/模型/海底自检 + 画面截图
# 用法：./verify.sh [--no-shot]
set -e
cd "$(dirname "$0")"

GODOT="${GODOT:-$HOME/Applications/Godot.app/Contents/MacOS/Godot}"

echo "== 1/3 核心逻辑 parity =="
"$GODOT" --headless --path . --script res://tests/test_core.gd 2>&1 | tail -3

echo "== 2/3 场景 / 模型 / 海底自检 =="
"$GODOT" --headless --path . -- --selftest 2>&1 | grep -E "FAIL|selftest\]"

if [ "$1" != "--no-shot" ]; then
  echo "== 3/3 画面截图 =="
  "$GODOT" --path . --resolution 1440x900 -- --capture --frames=110 2>&1 | grep -E "capture" || true
  cp outputs/godot-preview.png outputs/godot-preview-latest.png 2>/dev/null || true
  # 海底：入口 / 街区 / 海沟（--uwat 是调试传送，只影响截图）
  "$GODOT" --path . --resolution 1440x900 -- --dive --capture --frames=200 2>&1 | grep -E "capture" || true
  cp outputs/godot-preview.png outputs/underwater-overview.png 2>/dev/null || true
  "$GODOT" --path . --resolution 1440x900 -- --dive --uwat=-14,-6,20 --capture --frames=200 2>&1 | grep -E "capture" || true
  cp outputs/godot-preview.png outputs/underwater-neighborhood.png 2>/dev/null || true
  "$GODOT" --path . --resolution 1440x900 -- --dive --uwat=-2,-200,-120 --capture --frames=200 2>&1 | grep -E "capture" || true
  cp outputs/godot-preview.png outputs/underwater-trench.png 2>/dev/null || true
fi

echo "验收完成。截图：outputs/godot-preview.png（海底在 outputs/underwater-*.png）"
