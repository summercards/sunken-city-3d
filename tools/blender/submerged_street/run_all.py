"""One-shot final pass: build -> verify -> package/export -> register -> water layer -> contracts.

Order matters: register.py rewrites this kit's ledger rows from scratch, so the water-layer
fields must be re-applied afterwards (apply_water_layer.py is idempotent).
Set SEA_SKIP_BUILD=1 to reuse the existing master, SEA_SKIP_EXPORT=1 to reuse packages/GLBs.
"""
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
TOOLS = ROOT / 'tools/blender/submerged_street'
PY = sys.executable
# `blender` on this machine is a POSIX shell shim; Windows CreateProcess cannot launch it,
# so resolve the real executable explicitly instead of relying on PATH.
BLENDER = os.environ.get('BLENDER') or r'D:/blender-5.2/blender.exe'
if not Path(BLENDER).is_file():
    sys.exit('blender executable not found: ' + BLENDER + ' (set BLENDER=...)')


def run(cmd, label):
    print('\n== %s ==' % label, flush=True)
    r = subprocess.run([str(c) for c in cmd], cwd=str(ROOT))
    if r.returncode != 0:
        sys.exit('%s failed with %d' % (label, r.returncode))
    return r


if not os.environ.get('SEA_SKIP_BUILD'):
    run([BLENDER, '--background', '--factory-startup', '--python', str(TOOLS / 'build.py'), ], 'build')
run([BLENDER, '--background', '--factory-startup', '--python', str(TOOLS / 'verify.py')], 'verify')
if not os.environ.get('SEA_SKIP_EXPORT'):
    run([BLENDER, '--background', '--factory-startup', '--python', str(TOOLS / 'package_export.py')], 'package/export')
run([PY, '-X', 'utf8', str(TOOLS / 'register.py')], 'register')
run([PY, '-X', 'utf8', str(ROOT / 'tools/apply_water_layer.py')], 'water layer')
run([PY, '-X', 'utf8', str(ROOT / 'scripts/check_feature_contracts.py'), '--sync'], 'contracts sync')
run([PY, '-X', 'utf8', str(ROOT / 'scripts/check_feature_contracts.py')], 'contracts check')
print('\nALL STEPS PASSED')
