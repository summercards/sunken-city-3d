#!/usr/bin/env python3
"""Run the facility access audit in an isolated project copy.

Usage: python scripts/audit_facility_access.py [label]
"""
import datetime as dt
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import run_verification as rv  # noqa: E402


def main():
    label = re.sub(r'[^A-Za-z0-9_-]', '_', sys.argv[1] if len(sys.argv) > 1 else 'facility')
    exe = os.environ.get('GODOT') or shutil.which('godot') or str(
        Path.home() / 'Applications/Godot.app/Contents/MacOS/Godot')
    if not Path(exe).is_file():
        raise SystemExit('Godot executable unavailable; set GODOT')
    work = Path(os.environ.get('SEA_WORK_ROOT', str(ROOT.parent / 'sea-work'))).resolve()
    run_dir = work / 'diag' / (dt.datetime.now().strftime('%Y%m%d-%H%M%S') + '-' + label)
    run_dir.mkdir(parents=True)
    project, user_name = rv.isolated_project(run_dir)
    script = 'res://tools/audit_facility_access.gd'
    extra = []
    if len(sys.argv) > 2:
        script = 'res://tools/' + sys.argv[2]
        extra = sys.argv[3:]
    cmd = [exe, '--path', str(project)]
    if script.endswith('audit_facility_access.gd'):
        cmd.append('--headless')
    else:
        cmd += ['--resolution', '1280x800']
    cmd += ['--script', script, '--', '--skip-title'] + extra
    print(' '.join(cmd), flush=True)
    log = run_dir / 'audit.log'
    with log.open('w', encoding='utf-8') as fh:
        code = subprocess.run(cmd, stdout=fh, stderr=subprocess.STDOUT, timeout=1800).returncode
    data = project / 'outputs' / 'facility-access-audit.json'
    if data.is_file():
        shutil.copy2(data, run_dir / 'facility-access-audit.json')
    for pattern in ('access-*.png', 'overlay-*.png'):
        for png in (project / 'outputs').glob(pattern):
            shutil.copy2(png, run_dir / png.name)
    print('exit', code, 'run_dir', run_dir)
    print('json', run_dir / 'facility-access-audit.json')
    if code != 0:
        text = log.read_text(encoding='utf-8', errors='replace')
        print(text[-3000:])
    return code


if __name__ == '__main__':
    raise SystemExit(main())
