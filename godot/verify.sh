#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# 材质参数契约（秒级静态检查）：ShaderMaterial 被编辑器保存时可能整批丢参数且不报错，
# 丢了 palette 就是白模。先挡住，再跑贵的运行验证。
python3 "$ROOT/scripts/check_material_params.py"
python3 "$ROOT/scripts/run_verification.py" core
if [[ "${1:-}" != "--no-shot" ]]; then
  python3 "$ROOT/scripts/run_verification.py" visual-management
fi
