#!/bin/bash
# GPU 验收需要图形会话；任何失败或脚本/着色器错误均返回非零。
set -euo pipefail
cd "$(dirname "$0")"
GODOT="${GODOT:-$HOME/Applications/Godot.app/Contents/MacOS/Godot}"
mkdir -p outputs
run_check() {
  local label="$1"
  shift
  if ! "$GODOT" --path . "$@" > "outputs/uw-${label}.log" 2>&1; then
    cat "outputs/uw-${label}.log"
    return 1
  fi
  cat "outputs/uw-${label}.log"
  # 自检刻意向存档解析器输入坏 JSON；只允许这一条已知负例诊断。
  local expected='^$'
  if [ "$label" = selftest ]; then
    expected='^ERROR: Parse JSON failed\. Error at line 0: Expected key$'
  fi
  if grep -Ev "$expected" "outputs/uw-${label}.log" | grep -Eq 'SCRIPT ERROR|SHADER ERROR|ERROR:|FAIL'; then
    return 1
  fi
}
run_check core --headless --script res://tests/test_core.gd
run_check selftest --headless -- --selftest
run_check depth --resolution 400x300 --script res://tests/test_underwater_depth.gd
if [ ! -f outputs/uw-standard-web-cameras.json ]; then
  echo '缺少网页版相机基线，请先运行 tools/capture_underwater_ref.cjs uw-standard-web。' >&2
  exit 2
fi
run_check capture --resolution 1440x900 --script res://tools/capture_underwater_suite.gd
echo '水下验收通过：outputs/uw-*.log 与 outputs/uw-standard-godot-*.png'
