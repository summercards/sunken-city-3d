"""带重试地跑封闭：GLB 偶发被 Godot 导入扫描占用，写入失败就换下一轮重跑该组件。"""
import json
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
BLENDER = r"D:\Program Files\Blender Foundation\Blender 4.5\blender.exe"
SCRIPT = REPO / 'tools/blender/sunken_city/seal_components.py'


def slugs(version):
    cat = json.loads((REPO / 'art_source/scenes/sunken_city' / version /
                      'component_catalog.json').read_text(encoding='utf-8'))['components']
    return [c['slug'] for c in cat if c['category'] == 'architecture']


def run(version, out_version, runtime, slug=None, dry=False, tries=6):
    args = [BLENDER, '-b', '--python', str(SCRIPT), '--',
            '--version', version, '--out-version', out_version, '--runtime', runtime]
    if slug:
        args += ['--slug', slug]
    if dry:
        args += ['--dry-run']
    for attempt in range(1, tries + 1):
        proc = subprocess.run(args, cwd=str(REPO), capture_output=True, text=True,
                              encoding='utf-8', errors='replace')
        lines = [l for l in proc.stdout.splitlines() if l.startswith('SEAL')]
        ok = any(l.startswith('SEAL ') for l in lines)
        if ok or dry:
            return lines
        if attempt < tries:
            time.sleep(1.5)
    return [l for l in proc.stdout.splitlines() if l.startswith('SEAL_FAIL')]


def main():
    version = sys.argv[1] if len(sys.argv) > 1 else 'v005'
    out_version = sys.argv[2] if len(sys.argv) > 2 else 'v006'
    runtime = sys.argv[3] if len(sys.argv) > 3 else 'godot/assets/models/scenery/sunken_city'
    pending = slugs(version)
    failures = []
    for slug in pending:
        lines = run(version, out_version, runtime, slug)
        for line in lines:
            print(line, flush=True)
        if not any(line.startswith('SEAL ') for line in lines):
            failures.append(slug)
    print('RUN_ALL_DONE failures=%d %s' % (len(failures), failures), flush=True)


main()
