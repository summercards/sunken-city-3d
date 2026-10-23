#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 "$ROOT/scripts/run_verification.py" management
if [[ "${1:-}" == "--visual" ]]; then
  python3 "$ROOT/scripts/run_verification.py" visual-management
fi
