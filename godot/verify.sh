#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 "$ROOT/scripts/run_verification.py" core
if [[ "${1:-}" != "--no-shot" ]]; then
  python3 "$ROOT/scripts/run_verification.py" visual-management
fi
