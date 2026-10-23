#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 "$ROOT/scripts/run_verification.py" parity selftest
if [[ "${1:-}" != "--no-shot" ]]; then
  python3 "$ROOT/scripts/run_verification.py" visual-underwater-depth visual-underwater-capture
fi
