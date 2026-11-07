"""通过统一 run_verification 执行住所专项；不改写 runner 注册表文件。"""
import importlib.util
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('run_verification', ROOT / 'scripts/run_verification.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
for name in ['residence', 'visual-residence']:
    runner.TESTS[name] = ('tests/test_residence.gd', r'\[residence\] \d+ checks, 0 failures')
if len(sys.argv) == 1:
    sys.argv.extend(['residence', '--label', 'residence'])
raise SystemExit(runner.main())
