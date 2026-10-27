#!/usr/bin/env python3
"""Run sea checks with isolated user data, full logs and unmasked exit codes."""
import argparse
import datetime as dt
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[1]
GODOT_ROOT = ROOT / 'godot'
TESTS = {
    'modules': ('tests/test_feature_modules.gd', r'\[modules\] \d+ checks, 0 failures'),
    'parity': ('tests/test_core.gd', r'\d+ checks, 0 failures'),
    'farming': ('tests/test_farming.gd', r'\[farming\] \d+ checks, 0 failed'),
    'surface': ('tests/test_surface_movement.gd', r'\[surface\].*failures=0'),
    'click': ('tests/test_click_controls.gd', r'\[click-controls\] \d+ checks, 0 failures'),
    'management': ('tests/test_management_loop.gd', r'\[management\] \d+ checks, 0 failed'),
    'camera': ('tests/test_camera_follow.gd', r'\[camera-follow\].*failures=0'),
    'ocean': ('tests/test_ocean.gd', r'\[ocean\].*failures=0'),
    'selftest': (None, r'\[selftest\] \d+ passed, 0 failed'),
}
CORE = list(TESTS)
TESTS.update({
    'save-corrupt-seed': ('tests/test_save_corrupt_seed.gd', r'\[save-corrupt-seed\] complete'),
    'save-protection': ('tests/test_save_protection.gd', r'\[save-protection\] ok=true'),
    'visual-weather': ('tools/capture_world_weather.gd', r'\[visual-weather\] complete'),
    'framework-modules': ('tests/test_framework_modules.gd', r'\[framework-modules\].*0 failures'),
    'save-seed': ('tests/test_save_seed.gd', r'\[save-seed\] ok=true'),
    'framework-integration': ('tests/test_framework_integration.gd', r'\[framework-integration\].*0 failures'),
    'solar-components': ('tests/test_solar_components.gd', r'\[solar-components\].*failures=0'),
    'visual-solar-cabin': ('tests/test_solar_cabin_asset.gd', r'\[solar-cabin\].*failures=0'),
    'visual-sea-style': ('tools/capture_sea_style.gd', r'\[sea-style\] complete'),
    'visual-farming': ('tools/capture_farm_cycle.gd', r'\[farm-ui\] failures=0'),
    'visual-management': ('tools/capture_management_loop.gd', r'\[management-ui\].*0 failed'),
    'visual-click': ('tools/capture_click_controls.gd', r'\[click-ui\] failures=0'),
    'visual-underwater-depth': ('tests/test_underwater_depth.gd', r'\[uw-depth\] double_sided_lighting.*PASS'),
    'visual-underwater-capture': ('tools/capture_underwater_suite.gd', r'\[uw-suite\] surface_environment_restored=true'),
    'visual-paper-fit': ('tools/check_paper_fit.gd', r'\[paper-fit\] \d+ checks, 0 failures'),
    'visual-world-text': ('tools/check_world_text.gd', r'\[world-text\] \d+ checks, 0 failures'),
    'visual-blockers': ('tools/verify_blockers.gd', r'\[blockers-check\] OK failures=0'),
    # P 面板「光照」页：清单对账（属性名/范围）与端到端写入探针。
    # 两项都不进 core，跟其它参数工具一起按需跑。
    'lighting-params': ('tools/check_light_params.gd', r'\[lighting-params\] \d+ checks, 0 failures'),
    'lighting-panel': ('tools/probe_light_panel.gd', r'\[light-probe\] \d+ checks, 0 failures'),
})
EXPECTED_JSON_ERROR = 'ERROR: Parse JSON failed. Error at line 0: Expected key'


def inspect_log(name, code, text, marker):
    expected = []
    errors = []
    for line in text.splitlines():
        if name == 'selftest' and line.strip() == EXPECTED_JSON_ERROR:
            expected.append(line)
        elif re.search(r'SCRIPT ERROR|SHADER ERROR|ERROR:|\bFAIL\b', line):
            errors.append(line)
    ok = code == 0 and not errors and len(expected) <= 1 and re.search(marker, text) is not None
    return {'exit_code': code, 'passed': ok, 'expected_errors': expected,
            'unexpected_errors': errors, 'completion_marker': bool(re.search(marker, text))}


def mount_readonly(target, source):
    """把只读输入挂进隔离工程，尽量不复制。

    Windows 上 `Path.symlink_to` 在没权限时**不抛异常**，而是留下一个空目录 /
    空文件。测试于是读不到 `res://assets/...`，全线报错却看着像代码回归
    （2026-10-24 踩到：ocean 测试挂在 `Cannot call method
    'get_shader_parameter' on a null value`，其实是 water.tres 根本没加载）。
    所以目录优先用目录联接（junction，不需要管理员权限），挂上后必须验一下
    里面有东西，否则退回老实复制。
    """
    if not source.is_dir():
        shutil.copy2(source, target)
        return
    if os.name == 'nt':
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


def isolated_project(run_dir):
    project = run_dir / 'project'
    project.mkdir()
    for name in ['src', 'scripts', 'scenes', 'tests', 'tools', 'shaders']:
        source = GODOT_ROOT / name
        if source.exists():
            shutil.copytree(source, project / name, ignore=shutil.ignore_patterns('__pycache__'))
    # Assets and imported binary cache are read-only inputs to test scripts.
    mount_readonly(project / 'assets', GODOT_ROOT / 'assets')
    mount_readonly(project / 'icon.svg', GODOT_ROOT / 'icon.svg')
    cache = project / '.godot'
    cache.mkdir()
    (cache / '.gdignore').touch()
    if (GODOT_ROOT / '.godot/imported').exists():
        mount_readonly(cache / 'imported', GODOT_ROOT / '.godot/imported')
    classes = GODOT_ROOT / '.godot/global_script_class_cache.cfg'
    if classes.exists():
        shutil.copy2(classes, cache / classes.name)
    uid_cache = GODOT_ROOT / '.godot/uid_cache.bin'
    if uid_cache.exists():
        shutil.copy2(uid_cache, cache / uid_cache.name)
    text = (GODOT_ROOT / 'project.godot').read_text()
    # Applied BEFORE Godot starts and before any Autoload is constructed.
    user_name = 'sea-verification/' + run_dir.name
    text = re.sub(r'^config/name=.*$', 'config/name="' + user_name + '"', text, flags=re.M)
    text = re.sub(r'^config/(?:use_custom_user_dir|custom_user_dir_name)=.*\n?', '', text, flags=re.M)
    text = text.replace('[application]', '[application]\nconfig/use_custom_user_dir=true\n'
                        + 'config/custom_user_dir_name="' + user_name + '"')
    (project / 'project.godot').write_text(text)
    (project / 'outputs').mkdir()
    camera_baseline = GODOT_ROOT / 'outputs/uw-standard-web-cameras.json'
    if camera_baseline.is_file():
        shutil.copy2(camera_baseline, project / 'outputs' / camera_baseline.name)
    return project, user_name


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('checks', nargs='*', default=['core'])
    parser.add_argument('--label', default='verification')
    parser.add_argument('--timeout', type=int, default=180)
    parser.add_argument('--visual', action='store_true')
    args = parser.parse_args()
    checks = CORE if args.checks == ['core'] else args.checks
    if 'framework-integration' in checks and 'save-seed' not in checks:
        checks = list(checks)
        checks.insert(checks.index('framework-integration'), 'save-seed')
    if 'save-protection' in checks and 'save-corrupt-seed' not in checks:
        checks = list(checks)
        checks.insert(checks.index('save-protection'), 'save-corrupt-seed')
    unknown = set(checks) - set(TESTS)
    if unknown:
        parser.error('unknown checks: ' + ', '.join(sorted(unknown)))
    exe = os.environ.get('GODOT') or shutil.which('godot') or str(Path.home() / 'Applications/Godot.app/Contents/MacOS/Godot')
    if not Path(exe).is_file():
        parser.error('Godot executable unavailable; set GODOT')
    work = Path(os.environ.get('SEA_WORK_ROOT', str(ROOT.parent / 'sea-work'))).resolve()
    if work == ROOT or ROOT in work.parents:
        parser.error('SEA_WORK_ROOT must be outside the repository')
    label = re.sub(r'[^A-Za-z0-9_-]', '_', args.label)
    run_dir = work / 'verification' / (dt.datetime.now().strftime('%Y%m%d-%H%M%S') + '-' + label + '-' + uuid.uuid4().hex[:6])
    run_dir.mkdir(parents=True)
    project, user_name = isolated_project(run_dir)
    full_config = (project / 'project.godot').read_text()
    report = {'label': label, 'run_dir': str(run_dir), 'user_data_name': user_name,
              'head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
              'working_tree': subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True),
              'renderer': 'per check; visual-* always use real renderer', 'results': {}}
    print('Evidence:', run_dir, flush=True)
    for name in checks:
        config = re.sub(r'\[autoload\].*?(?=\n\[|\Z)', '', full_config, flags=re.S) if name in ['modules','framework-modules'] else full_config
        # Only intentional cross-process cases share a slot. Every other check starts fresh.
        group = ('restart' if name in ['save-seed', 'framework-integration'] else
                 'protection' if name in ['save-corrupt-seed', 'save-protection'] else name)
        check_user_name = user_name + '/' + group
        config = re.sub(r'^config/custom_user_dir_name=.*$',
                        'config/custom_user_dir_name="' + check_user_name + '"', config, flags=re.M)
        (project / 'project.godot').write_text(config)
        script, marker = TESTS[name]
        cmd = [exe, '--path', str(project)]
        is_visual = args.visual or name.startswith('visual-')
        if not is_visual:
            cmd.append('--headless')
        else:
            cmd += ['--resolution', '1280x800', '--fixed-fps', '60']
        if script:
            cmd += ['--script', 'res://' + script]
        else:
            cmd += ['--', '--selftest', '--nosave']
        log = run_dir / (name + '.log')
        with log.open('w') as output:
            try:
                code = subprocess.run(cmd, stdout=output, stderr=subprocess.STDOUT, timeout=args.timeout).returncode
            except subprocess.TimeoutExpired:
                code = 124
        text = log.read_text(errors='replace')
        result = inspect_log(name, code, text, marker)
        result['log'] = str(log)
        result['user_data_name'] = check_user_name
        result['renderer'] = 'real' if is_visual else 'headless'
        result['command'] = cmd
        report['results'][name] = result
        print(name, 'PASS' if result['passed'] else 'FAIL', 'exit=' + str(code), flush=True)
        if not result['passed']:
            print('\n'.join(text.splitlines()[-18:]), flush=True)
        (run_dir / 'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if all(x['passed'] for x in report['results'].values()) else 1


if __name__ == '__main__':
    raise SystemExit(main())
