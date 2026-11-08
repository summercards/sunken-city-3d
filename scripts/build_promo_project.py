#!/usr/bin/env python3
"""Build an isolated copy of the Godot project for promo recording.

Rules borrowed from scripts/run_verification.py:
  * user data must be redirected BEFORE any Autoload is constructed,
    otherwise recording overwrites the player's real save;
  * assets/terrain are read-only inputs mounted as junctions (no copy);
  * textures use the shared import cache.

Only the viewport size differs from the repo project.godot.
"""
import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GODOT_ROOT = ROOT / 'godot'


def mount_readonly(target: Path, source: Path) -> None:
    if not source.is_dir():
        shutil.copy2(source, target)
        return
    if sys.platform == 'win32':
        done = subprocess.run(['cmd', '/c', 'mklink', '/J', str(target), str(source)],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if done.returncode == 0 and any(target.iterdir()):
            return
        shutil.rmtree(target, ignore_errors=True)
    else:
        target.symlink_to(source, target_is_directory=True)
        if target.is_dir() and any(target.iterdir()):
            return
        target.unlink(missing_ok=True)
    shutil.copytree(source, target)


def build(run_dir: Path, width: int, height: int) -> Path:
    project = run_dir / 'project'
    if project.exists():
        shutil.rmtree(project)
    project.mkdir(parents=True)
    for name in ['src', 'scripts', 'scenes', 'tests', 'tools', 'shaders', 'data', 'addons']:
        source = GODOT_ROOT / name
        if source.exists():
            shutil.copytree(source, project / name,
                            ignore=shutil.ignore_patterns('__pycache__'))
    mount_readonly(project / 'assets', GODOT_ROOT / 'assets')
    mount_readonly(project / 'terrain', GODOT_ROOT / 'terrain')
    mount_readonly(project / 'icon.svg', GODOT_ROOT / 'icon.svg')
    cache = project / '.godot'
    cache.mkdir()
    (cache / '.gdignore').touch()
    for name in ['imported']:
        src = GODOT_ROOT / '.godot' / name
        if src.exists():
            mount_readonly(cache / name, src)
    for name in ['global_script_class_cache.cfg', 'uid_cache.bin', 'extension_list.cfg']:
        src = GODOT_ROOT / '.godot' / name
        if src.exists():
            shutil.copy2(src, cache / name)
    text = (GODOT_ROOT / 'project.godot').read_text()
    user_name = 'sea-promo/' + run_dir.name
    text = re.sub(r'^config/name=.*$', 'config/name="' + user_name + '"', text, flags=re.M)
    text = re.sub(r'^config/(?:use_custom_user_dir|custom_user_dir_name)=.*\n?', '', text, flags=re.M)
    text = text.replace('[application]', '[application]\nconfig/use_custom_user_dir=true\n'
                        + 'config/custom_user_dir_name="' + user_name + '"')
    text = re.sub(r'^window/size/viewport_width=.*$',
                  'window/size/viewport_width=%d' % width, text, flags=re.M)
    text = re.sub(r'^window/size/viewport_height=.*$',
                  'window/size/viewport_height=%d' % height, text, flags=re.M)
    (project / 'project.godot').write_text(text)
    (project / 'outputs').mkdir(exist_ok=True)
    meta = {'project': str(project), 'user_dir': user_name,
            'viewport': [width, height], 'repo_head': subprocess.check_output(
                ['git', 'rev-parse', 'HEAD'], cwd=str(ROOT), text=True).strip()}
    (run_dir / 'project.json').write_text(json.dumps(meta, indent=2, ensure_ascii=False))
    return project


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--run-dir', required=True)
    ap.add_argument('--width', type=int, default=1920)
    ap.add_argument('--height', type=int, default=1080)
    args = ap.parse_args()
    project = build(Path(args.run_dir).resolve(), args.width, args.height)
    print(project)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
