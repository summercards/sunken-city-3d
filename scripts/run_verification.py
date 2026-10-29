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
    # 作物品种与四阶段形态：隔离运行，不加载 main.tscn（SEA-CROP-R05 的证据）。
    'crops': ('tests/test_crops.gd', r'\[crops\] \d+ checks, 0 failed'),
    # 作物 12 阶段真实渲染：正视图 + 俯视图，作为 SEA-CROP-R06 的渲染证据。
    # 必须以 visual- 开头，harness 才会给真实渲染器；headless 下截不了图（会挂住）。
    'visual-crops': ('tools/capture_crops.gd', r'\[crops-render\] \d+ checks, 0 failures'),
    'surface': ('tests/test_surface_movement.gd', r'\[surface\].*failures=0'),
    'click': ('tests/test_click_controls.gd', r'\[click-controls\] \d+ checks, 0 failures'),
    'management': ('tests/test_management_loop.gd', r'\[management\] \d+ checks, 0 failed'),
    'camera': ('tests/test_camera_follow.gd', r'\[camera-follow\].*failures=0'),
    # 交互热区必须跟着物体走：出货箱曾偏 2.07 米，看得见却点不到。
    'interact-focus': ('tests/test_interact_focus.gd', r'\[interact-focus\] \d+ checks, 0 failures'),
    # 走不到的地方点开操作菜单：图标贴边可命中、菜单钉住、逐项写明原因。
    # 交互热区按模型本体算：土箱之间的甲板缝不能被吞，否则点地面走不了路。
    'pick-mesh': ('tests/test_pick_mesh.gd', r'\[pick-mesh\] \d+ checks, 0 failures'),
    'visual-pick-mesh': ('tools/capture_pick_mesh.gd', r'\[shot\] done'),
    'unreachable-menu': ('tests/test_unreachable_menu.gd', r'\[unreachable-menu\] \d+ checks, 0 failures'),
    # 点船 = 上船；靠岸图标随「点击会干什么」换宿主（岸上贴船、船上贴码头）。
    'board-click': ('tests/test_board_by_click.gd', r'\[board-click\] \d+ checks, 0 failures'),
    'ocean': ('tests/test_ocean.gd', r'\[ocean\].*failures=0'),
    'selftest': (None, r'\[selftest\] \d+ passed, 0 failed'),
}
CORE = list(TESTS)
TESTS.update({
    'walk-facing': ('tests/test_walk_facing.gd', r'\[walk-facing\] \d+ checks, 0 failures'),
    # 码头栈桥两处围栏缺口：矩形越界点必须拒绝、甲板自身必须仍可走（SEA-MOVE-R01）。
    'walk-deck-fit': ('tests/test_walk_deck_fit.gd', r'\[walk-deck-fit\] \d+ checks, 0 failures'),
    'visual-walk-facing': ('tests/test_walk_facing.gd', r'\[walk-facing\] \d+ checks, 0 failures'),
    'visual-building-fit': ('tools/capture_building_fit.gd', r'\[building-fit\] \d+ checks, 0 failures'),
    'boat-water-contact': ('tests/test_boat_water_contact.gd', r'\[boat-water-contact\] \d+ checks, 0 failures'),
    'visual-boat-water-contact': ('tests/test_boat_water_contact.gd', r'\[boat-water-contact\] \d+ checks, 0 failures'),
    'building-seed': ('tests/test_building_restart.gd', r'\[building-restart\] \d+ checks, 0 failures'),
    'building-restart': ('tests/test_building_restart.gd', r'\[building-restart\] \d+ checks, 0 failures'),
    'building': ('tests/test_building.gd', r'\[building\] \d+ checks, 0 failures'),
    'building-integration': ('tests/test_building_integration.gd', r'\[building-integration\] \d+ checks, 0 failures'),
    # 建造要先走过去：点远处虚影只排队，站定了才扣材料开工。
    'building-approach': ('tests/test_building_approach.gd', r'\[building-approach\] \d+ checks, 0 failures'),
    # Diagnostic reproduction, not acceptance of the documented construction guarantees.
    'building-boundary-audit': ('tools/probe_building_boundary_audit.gd', r'\[building-boundary-audit\] \d+ checks, 0 failures'),
    'visual-building-boundary-audit': ('tools/probe_building_boundary_audit.gd', r'\[building-boundary-audit\] \d+ checks, 0 failures'),
    # 浮层进度条：拾取/建造共用一份自绘细条，且拾取条只在最后约 2 秒航程出现。
    # 这两点都不会报错，只会在画面上"看起来不对"，必须显式断言。
    'progress-bars': ('tools/check_progress_bars.gd', r'\[progress-bars\] \d+ checks, 0 failures'),
    # 拾取进度条的真实渲染证据：航行段不画条、贴近目标才画。
    'visual-pickup-progress': ('tools/capture_pickup_progress.gd', r'\[pickup-progress\] \d+ checks, 0 failures'),
    'visual-building': ('tests/test_building_visual.gd', r'\[visual-building\] \d+ checks, 0 failures'),
    'visual-build-approach': ('tools/capture_build_approach.gd', r'\[shot\] done'),
    'visual-submerged-water-light': ('tests/test_submerged_water_light.gd', r'\[submerged-water-light\] \d+ checks, 0 failures'),
    'submerged-neighborhood': ('tests/test_submerged_neighborhood.gd', r'\[submerged-neighborhood\] \d+ checks, 0 failures'),
    'visual-submerged-neighborhood': ('tests/test_submerged_neighborhood.gd', r'\[submerged-neighborhood\] \d+ checks, 0 failures'),
    'reference-skiff': ('tests/test_reference_skiff.gd', r'\[reference-skiff\] \d+ checks, 0 failures'),
    'visual-reference-skiff': ('tests/test_reference_skiff.gd', r'\[reference-skiff\] \d+ checks, 0 failures'),
	'visual-corner-notebook': ('tests/test_corner_notebook.gd', r'\[corner-notebook\] \d+ checks, 0 failures'),
    'title-clock-seed': ('tests/seed_title_clock.gd', r'\[title-clock-seed\] ok=true'),
    'visual-title-screen-day': ('tests/test_title_saved_time.gd', r'\[title-saved\] \d+ checks, 0 failures'),
    'visual-title-screen-night': ('tests/test_title_saved_time.gd', r'\[title-saved\] \d+ checks, 0 failures'),
    'visual-title-screen-dawn': ('tests/test_title_saved_time.gd', r'\[title-saved\] \d+ checks, 0 failures'),
    'visual-boat-lamp': ('tests/test_boat_navigation_lamp.gd', r'\[boat-navigation-lamp\] \d+ checks, 0 failures'),
    'visual-atmosphere': ('tests/test_atmosphere.gd', r'\[atmosphere\] \d+ checks, 0 failures'),
    'water-params': ('tools/check_water_params.gd', r'\[water-params\] PASS 吸收式'),
    'visual-home-lighting': ('tests/test_home_lighting.gd', r'\[home-lighting\] \d+ checks, 0 failures'),
    'pocket-services': ('tests/test_pocket_services.gd', r'\[pocket-services\].*0 failures'),
    'visual-pocket-services': ('tests/test_pocket_services.gd', r'\[pocket-services\].*0 failures'),
    'visual-cabin-dayparts': ('tests/test_cabin_dayparts.gd', r'\[cabin-dayparts\] \d+ checks, 0 failures'),
    'pocket-bubbles': ('tests/test_pocket_bubbles.gd', r'\[pocket-bubbles\].*0 failures'),
    # 口袋拖拽整理 + 购买数量 +/−：顺序要持久化、买多份要原子。
    'pocket-drag-buy': ('tools/check_pocket_drag_buy.gd', r'\[pocket-drag-buy\] \d+ checks, 0 failures'),
    # 拖拽整理与购买数量的真实渲染：数量选择器长什么样、拖拽手感如何。
    'visual-pocket-drag-buy': ('tools/capture_pocket_drag_buy.gd', r'\[pocket-ui\] \d+ checks, 0 failures'),
    'visual-pocket-bubbles': ('tests/test_pocket_bubbles.gd', r'\[pocket-bubbles\].*0 failures'),
    'sleep-cycle': ('tests/test_sleep_cycle.gd', r'\[sleep-cycle\].*0 failures'),
    'visual-sleep-cycle': ('tests/test_sleep_cycle.gd', r'\[sleep-cycle\].*0 failures'),
    'visual-plot-shipping': ('tests/test_plot_shipping_loop.gd', r'\[plot-shipping\].*0 failures'),
    'title-screen': ('tests/test_title_screen.gd', r'\[title-screen\].*0 failures'),
    'visual-title-screen': ('tests/test_title_screen.gd', r'\[title-screen\].*0 failures'),
    'minimum-loop': ('tests/test_minimum_loop.gd', r'\[minimum-loop\].*0 failures'),
    'visual-minimum-loop': ('tests/test_minimum_loop.gd', r'\[minimum-loop\].*0 failures'),
    'decorations': ('tests/test_scene_decorations.gd', r'\[decorations\].*failures=0'),
    'visual-decorations': ('tests/test_scene_decorations.gd', r'\[decorations\].*failures=0'),
    'save-corrupt-seed': ('tests/test_save_corrupt_seed.gd', r'\[save-corrupt-seed\] complete'),
    'save-protection': ('tests/test_save_protection.gd', r'\[save-protection\] ok=true'),
    'visual-weather': ('tools/capture_world_weather.gd', r'\[visual-weather\] complete'),
    # 昼夜光照：真实光照替代屏幕蒙版。断言正午等于基准、夜里太阳落、
    # 水面的天空反射与太阳高光跟着走，且屏幕层不再出现全屏填充。
    'daylight': ('tests/test_daylight_rig.gd', r'\[daylight\] \d+ checks, 0 failures'),
    'framework-modules': ('tests/test_framework_modules.gd', r'\[framework-modules\].*0 failures'),
    'save-seed': ('tests/test_save_seed.gd', r'\[save-seed\] ok=true'),
    'framework-integration': ('tests/test_framework_integration.gd', r'\[framework-integration\].*0 failures'),
    'solar-components': ('tests/test_solar_components.gd', r'\[solar-components\].*failures=0'),
    'visual-solar-cabin': ('tests/test_solar_cabin_asset.gd', r'\[solar-cabin\].*failures=0'),
    'visual-sea-style': ('tools/capture_sea_style.gd', r'\[sea-style\] complete'),
    # 鱼群专项：模型/动画/配色/单群散布 + 近景渲染证据。
    'visual-fish-schools': ('tools/capture_fish_schools.gd', r'\[fish-schools\] \d+ checks, failures=0'),
    'visual-birds': ('tools/capture_birds.gd', r'\[birds\] \d+ checks, failures=0'),
    'visual-farming': ('tools/capture_farm_cycle.gd', r'\[farm-ui\] failures=0'),
    'visual-management': ('tools/capture_management_loop.gd', r'\[management-ui\].*0 failed'),
    'visual-click': ('tools/capture_click_controls.gd', r'\[click-ui\] failures=0'),
    # 航线水纹：航路虚线已移除，落点改成贴浪面的扩散波纹。
    'visual-route-ripple': ('tools/capture_route_ripple.gd', r'\[route-ripple\] checks done, failures=0'),
    'visual-underwater-depth': ('tests/test_underwater_depth.gd', r'\[uw-depth\] double_sided_lighting.*PASS'),
    'visual-underwater-capture': ('tools/capture_underwater_suite.gd', r'\[uw-suite\] surface_environment_restored=true'),
    'visual-paper-fit': ('tools/check_paper_fit.gd', r'\[paper-fit\] \d+ checks, 0 failures'),
    'visual-world-text': ('tools/check_world_text.gd', r'\[world-text\] \d+ checks, 0 failures'),
    'visual-blockers': ('tools/verify_blockers.gd', r'\[blockers-check\] OK failures=0'),
    # SEA-MOVE-R01：可行走矩形必须落在真实甲板上。
    # 走路不走物理碰撞，站得住是因为 surface_y 把脚贴到那个高度 ——
    # 矩形越过甲板边缘时人物会站在水面上，不报错、不崩，只能靠量。
    'visual-walk-deck': ('tools/verify_walk_deck.gd', r'\[walk-deck\] \d+ checks, 0 failures'),
    # P 面板「光照」页：清单对账（属性名/范围）与端到端写入探针。
    # 两项都不进 core，跟其它参数工具一起按需跑。
    'lighting-params': ('tools/check_light_params.gd', r'\[lighting-params\] \d+ checks, 0 failures'),
    'lighting-panel': ('tools/probe_light_panel.gd', r'\[light-probe\] \d+ checks, 0 failures'),
    'visual-plot-menu': ('tools/capture_plot_menu.gd', r'\[visual-plot-menu\] complete'),
    'visual-salvage': ('tools/capture_salvage.gd', r'\[visual-salvage\] complete'),
    'dock-seed': ('tests/test_dock_and_seed.gd', r'\[dock-seed\] \d+ checks, 0 failures'),
    # 出货箱与码头缆绳的间距：箱子落点在场景，缆绳在组件 GLB 里，改任一边都可能重新穿模。
    'dock-rope-clearance': ('tools/verify_box_rope.gd', r'\[dock-rope\] complete'),
    # SEA-NAV-R11：150m 可航区横跨可航区常量、几何硬界、相机范围、存档回位四处，
    # 单独改任一处都不会报错，只会让「船能开多远」在雷达图和实际上不一致。
    'sail-bounds': ('tests/test_sail_bounds.gd', r'\[sail-bounds\] \d+ checks, 0 failures'),
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
    parser.add_argument('--lighting-profile', type=Path, help='Stage only lighting cfg fixtures for visual atmosphere captures')
    parser.add_argument('--import-assets', action='store_true', help='Import new art in the isolated project before checks')
    parser.add_argument('--full-world', action='store_true', help='Explicit legacy/development scope; default is the minimum playable loop')
    args = parser.parse_args()
    checks = CORE if args.checks == ['core'] else args.checks
    title_cases = ['visual-title-screen-day', 'visual-title-screen-night', 'visual-title-screen-dawn']
    if any(name in checks for name in title_cases) and 'title-clock-seed' not in checks:
        checks = list(checks)
        checks.insert(next(i for i, name in enumerate(checks) if name in title_cases), 'title-clock-seed')
    if 'framework-integration' in checks and 'save-seed' not in checks:
        checks = list(checks)
        checks.insert(checks.index('framework-integration'), 'save-seed')
    if 'save-protection' in checks and 'save-corrupt-seed' not in checks:
        checks = list(checks)
        checks.insert(checks.index('save-protection'), 'save-corrupt-seed')
    if 'building-restart' in checks and 'building-seed' not in checks:
        checks = list(checks)
        checks.insert(checks.index('building-restart'), 'building-seed')
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
    if args.import_assets:
        import_log = run_dir / 'asset-import.log'
        import_cmd = [exe, '--headless', '--editor', '--path', str(project), '--import']
        with import_log.open('w', encoding='utf-8') as output:
            try:
                import_code = subprocess.run(import_cmd, stdout=output, stderr=subprocess.STDOUT, timeout=args.timeout).returncode
            except subprocess.TimeoutExpired:
                import_code = 124
        import_text = import_log.read_text(encoding='utf-8', errors='replace')
        import_errors = [line for line in import_text.splitlines() if re.search(r'SCRIPT ERROR|SHADER ERROR|ERROR:', line)]
        report['asset_import'] = {'exit_code': import_code, 'log': str(import_log), 'unexpected_errors': import_errors}
        print('asset-import', 'PASS' if import_code == 0 and not import_errors else 'FAIL', 'exit=' + str(import_code), flush=True)
        if import_code != 0 or import_errors:
            (run_dir / 'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
            print('\n'.join(import_text.splitlines()[-20:]), flush=True)
            return 1
    for name in checks:
        config = re.sub(r'\[autoload\].*?(?=\n\[|\Z)', '', full_config, flags=re.S) if name in ['modules','framework-modules','building'] else full_config
        # Only intentional cross-process cases share a slot. Every other check starts fresh.
        group = ('building-restart' if name in ['building-seed','building-restart'] else
                 'title-clock' if name == 'title-clock-seed' or name in title_cases else
                 'restart' if name in ['save-seed', 'framework-integration'] else
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
        if 'title-screen' not in name:
            if '--' not in cmd: cmd.append('--')
            cmd.append('--skip-title')
        if name in title_cases:
            if '--' not in cmd: cmd.append('--')
            cmd.append('--title-fixture=' + name.rsplit('-', 1)[-1])
        if name == 'building-seed':
            if '--' not in cmd: cmd.append('--')
            cmd.append('--building-seed')
        if args.full_world:
            if '--' not in cmd: cmd.append('--')
            cmd.append('--full-world')
        log = run_dir / (name + '.log')
        with log.open('w') as output:
            try:
                check_env = os.environ.copy()
                if args.lighting_profile:
                    check_env['SEA_CAPTURE_LIGHTING_PROFILE'] = str(args.lighting_profile.resolve())
                code = subprocess.run(cmd, stdout=output, stderr=subprocess.STDOUT, timeout=args.timeout, env=check_env).returncode
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
