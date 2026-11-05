"""登记 sunken_city 所选版本的 Blender 源；默认 dry-run，--apply 才落盘。

只写 ledger_index.json 的 domains.scenes 路由账本及 current_source_index.json。
不生成或修补 manifest，不写报告、views、runtime_inventory，不导入 Blender。
主 agent 必须另行准备组件及总装 asset_manifest.json，包含正确 asset_ledger。
登记后主 agent 用 tools/apply_water_layer.py 的现有逻辑刷新两类 views；
若该工具尚无 SEA-SCENE-SCITY- 分类规则，须先另行补规则，再执行及检查门禁。

SEA_SUNKEN_VERSION 选择 v001（默认）、v002 或 v003，仅允许同版重登或相邻升级。
v003 保留计划明确退役的两个 v002 源记录，不覆盖其源、摘要和历史；套件共 53 条。
报告目录默认 <工程同级>/sea-work/sunken_city/<版本>，可用 --report-dir 覆盖，
也支持 SEA_WORK_ROOT。三份报告必须显式 passed=true 或 checks.passed=true；
兼容 status=passed（无布尔结论时）。已提供的失败结论、非零退出码、
errors/failures 或失败 checks 均拒绝，绝不以 failures=0 单独认定通过。
源报告主源摘要支持 source_sha256 / source_master_sha256 / master_sha256，
以及 source_sha256_before+source_sha256_after；包和 skill 报告兼容
package_verify.py 当前字段，逐包核对 package_sha256 及 before/after。

用法：python -X utf8 tools/blender/sunken_city/register.py [--apply]
原子性限于单文件；双文件采用预暂存、并发改动检测和异常回滚，不宣称跨文件
断电事务。中断后可重新 dry-run / --apply 修复 derived index。
"""

import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[3]
VERSION = os.environ.get('SEA_SUNKEN_VERSION', 'v001')
if VERSION not in {'v001', 'v002', 'v003'}:
    raise ValueError('SEA_SUNKEN_VERSION 只支持 v001、v002 或 v003')
DIRECTORY = ROOT / 'art_source/scenes/sunken_city' / VERSION
MASTER = DIRECTORY / f'sunken_city_{VERSION}.blend'
PALETTE = ROOT / 'art_source/shared/palettes/sea_cabin_timber_8x8_512.png'
ASSEMBLY_ID = 'SEA-SCENE-SCITY-ASSEMBLY'
STAGE = 'source_verified_runtime_pending'
SOURCE_FIELDS = ('asset_id', 'source', 'source_sha256', 'manifest')
ROLES = {'SEA_Matte', 'SEA_Metal', 'SEA_Gloss'}
FORBIDDEN = (
    'collision', 'navigation', 'walk', 'interaction', 'shoreline', 'emission',
    'interactive', 'blocks_actor', 'blocks_water', 'walkable', 'has_landing',
    'navigation_obstacle', 'resource_output', 'gameplay_state', 'shoreline_source',
    'walk_areas', 'landing_points', 'water_shapes', 'navigation_obstacles',
    'interactions', 'production', 'save_fields', 'walk_surface', 'walkable_area',
    'actor_collision', 'boat_blocking', 'landing_point',
)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def relative(path):
    return path.resolve().relative_to(ROOT.resolve()).as_posix()


def project_path(value):
    require(isinstance(value, str) and bool(value), '缺少工程路径')
    path = (ROOT / value).resolve()
    require(path.is_relative_to(ROOT.resolve()), '路径越出工程：' + value)
    return path


def passed(data, label):
    require(isinstance(data, dict), label + '：报告必须是对象')
    conclusions = []
    if 'passed' in data:
        conclusions.append(data['passed'] is True)
    checks = data.get('checks', {})
    require(isinstance(checks, dict), label + '：checks 必须是对象')
    if 'passed' in checks:
        conclusions.append(checks['passed'] is True)
    if 'status' in data:
        conclusions.append(data['status'] == 'passed')
    require(bool(conclusions) and all(conclusions), label + '：未显式通过或结论冲突')
    if 'exit_code' in data:
        require(type(data['exit_code']) is int and data['exit_code'] == 0,
                label + '：exit_code 不是 0')
    require(not data.get('errors') and not data.get('failures'), label + '：存在 errors/failures')
    for name, check in checks.items():
        ok = check is True or isinstance(check, dict) and check.get('passed') is True
        require(ok, label + '：检查未通过 ' + name)


def match_hashes(data, fields, actual, label, required=True):
    present = [name for name in fields if name in data]
    require(present or not required, label + '：缺少摘要 ' + '/'.join(fields))
    for name in present:
        value = data[name]
        require(isinstance(value, str) and re.fullmatch(r'[0-9a-fA-F]{64}', value)
                and value.lower() == actual, label + '：摘要不匹配 ' + name)


def source_binding(data, actual, label):
    match_hashes(data, ('source_sha256', 'source_master_sha256', 'master_sha256',
                        'source_sha256_before', 'source_sha256_after'), actual, label)
    if 'source_sha256_before' in data or 'source_sha256_after' in data:
        require('source_sha256_before' in data and 'source_sha256_after' in data,
                label + '：before/after 摘要必须成对')
    for field in ('source', 'master', 'blend', 'file'):
        if field in data:
            require(project_path(data[field]) == MASTER.resolve(), label + '：不是最终主源 ' + field)


def visual_only(data, label):
    for field in FORBIDDEN:
        value = data.get(field)
        if field == 'collision' and isinstance(value, dict):
            require(not any(value.values()), label + '：collision 声明非空职责')
        else:
            require(not value, label + '：禁止声明 ' + field)
    require(data.get('building_class', 'underwater') == 'underwater', label + '：不是 underwater')
    require(not data.get('runtime_integrated') and not data.get('runtime_path')
            and not data.get('prefab') and not data.get('runtime_sha256'), label + '：不是纯源级记录')


def component_reports(report, entries, label):
    rows = report.get('components')
    require(isinstance(rows, list) and len(rows) == len(entries), label + '：组件数量不匹配')
    by_key = {}
    for row in rows:
        passed(row, label + '/' + str(row.get('key')))
        key = row.get('key')
        require(isinstance(key, str) and key not in by_key, label + '：组件 key 缺失或重复')
        by_key[key] = row
    require(set(by_key) == {entry['key'] for entry in entries}, label + '：组件集合不匹配')
    return by_key


def register(args):
    # 快照用于 --apply 前检测读过的输入是否被其他 agent 改动。
    snapshots = {}
    binary_hashes = {}

    def read(path):
        path = path.resolve()
        raw = path.read_bytes()
        snapshots[path] = raw
        return json.loads(raw.decode('utf-8-sig'))

    def hashed(path):
        path = path.resolve()
        if path not in binary_hashes:
            require(path.is_file() and path.stat().st_size > 0, '源文件缺失或为空：' + str(path))
            binary_hashes[path] = sha(path)
        return binary_hashes[path]

    work = args.report_dir.resolve()
    require(not work.is_relative_to(ROOT.resolve()), '报告目录必须位于工程外')
    catalog_path = DIRECTORY / 'component_catalog.json'
    catalog = read(catalog_path)
    entries = catalog['components']
    require(isinstance(entries, list) and 0 < len(entries) <= 50, 'catalog 组件数必须为 1..50')
    plan = read(DIRECTORY / 'component_plan.json')
    require(plan['component_budget']['planned'] == len(entries), '冻结计划与 catalog 组件数不一致')
    require(len(entries) <= plan['component_budget']['limit'] <= 50, '组件数超出冻结计划上限')
    require(project_path(plan['palette']) == PALETTE.resolve(), '计划不是指定公共色盘')
    retired = {}
    new_v003_ids = {'SEA-SCENE-SCITY-TERRAIN-RAMP', 'SEA-SCENE-SCITY-VIADUCT-CURVE'}
    if VERSION == 'v003':
        require(len(entries) == 50, 'v003 必须包含 50 个当前组件')
        planned = plan['components']
        require(len(planned) == 50 and len({row['component_id'] for row in planned}) == 50
                and len({row['key'] for row in planned}) == 50
                and {(row['component_id'], row['key']) for row in planned}
                == {(row['component_id'], row['key']) for row in entries},
                'v003 当前组件 ID/key 必须严格等于冻结计划')
        expected_retired = {'SEA-SCENE-SCITY-T-JUNCTION': 't_junction',
                            'SEA-SCENE-SCITY-CANAL-END': 'canal_end'}
        retired_rows = plan.get('retired_components')
        require(isinstance(retired_rows, list) and len(retired_rows) == 2,
                'v003 必须显式保留两个计划退役定义')
        for row in retired_rows:
            aid = row['component_id']
            require(aid in expected_retired and row['key'] == expected_retired[aid]
                    and aid not in retired, '不允许退役其他组件或重复退役：' + str(aid))
            require(row.get('retained_source') == 'v002' and row.get('not_in_current_layout') is True,
                    aid + '：退役定义必须明确保留 v002 源且不在当前布局')
            retired[aid] = row
        current_ids = {row['component_id'] for row in entries}
        require(not current_ids.intersection(retired) and new_v003_ids <= current_ids,
                'v003 当前定义包含退役组件或缺少两个新增组件')
    master_hash, palette_hash = hashed(MASTER), hashed(PALETTE)
    match_hashes(plan, ('palette_sha256',), palette_hash, '计划色盘')
    report_paths = [work / (name + '_verification.json') for name in ('source', 'package', 'skill')]
    source_report, package_report, skill_report = reports = [read(path) for path in report_paths]
    for name, report in zip(('source', 'package', 'skill'), reports):
        passed(report, name)
        require(report.get('suite', 'sunken_city') == 'sunken_city', name + '：报告套件不一致')
        source_binding(report, master_hash, name)
        match_hashes(report, ('palette_sha256', 'palette_sha256_before', 'palette_sha256_after'),
                     palette_hash, name + '/palette', required=False)
    match_hashes(package_report, ('catalog_sha256_after',), sha(catalog_path), '包报告/catalog')
    require(package_report.get('catalog_updated') is True, '包报告尚未提交 catalog')
    require(package_report.get('expected_package_count') == len(entries), '包报告预期数量不匹配')
    require(package_report.get('run_id') and package_report['run_id'] == skill_report.get('run_id'),
            '包报告与 skill 报告不是同一轮')
    package_rows = component_reports(package_report, entries, 'package')
    skill_rows = component_reports(skill_report, entries, 'skill')

    index = read(ROOT / 'assets/registry/ledger_index.json')
    route = index['domains']['scenes']
    ledger_path = project_path(route['ledger'])
    require(ledger_path == (ROOT / 'assets/registry/ledgers/scenes.json').resolve(),
            'scenes 路由已变化，拒绝越出本次授权写入范围')
    index_path = (ROOT / 'assets/registry/current_source_index.json').resolve()
    require(project_path(index['runtime_inventory']) not in (ledger_path, index_path),
            'runtime_inventory 路由与写入目标冲突')
    books = {}
    for domain, domain_route in index['domains'].items():
        path = project_path(domain_route['ledger'])
        books[domain] = read(path)
    book = books['scenes']
    source_index = read(index_path)
    evidence = [path.as_posix() for path in report_paths]
    used_ids, used_keys, used_paths, all_roles = set(), set(), set(), set()
    records = []

    def manifest(path, aid, expected_hash, component=False):
        data = read(path)
        require(data.get('asset_id', data.get('component_id')) == aid, aid + '：manifest ID 错误')
        require(data.get('asset_ledger') == route['ledger'] + '#' + aid,
                aid + '：manifest 缺少正确 asset_ledger；请主 agent 另行准备，本脚本不改 manifest')
        if component:
            match_hashes(data, ('source_sha256',), expected_hash, aid + '/manifest')
            match_hashes(data, ('source_master_sha256',), master_hash, aid + '/manifest 主源')
        else:
            require(project_path(data['source']) == MASTER.resolve(), aid + '：总装不是最终主源')
            match_hashes(data, ('source_sha256',), master_hash, aid + '/manifest')
        match_hashes(data, ('palette_sha256',), palette_hash, aid + '/manifest 色盘')
        require(project_path(data['palette']) == PALETTE.resolve(), aid + '：manifest 色盘错误')
        visual_only(data, aid + '/manifest')
        return data

    def common(aid, name, source, source_hash, manifest_path, roles):
        row = dict(
            asset_id=aid, name=name, domain='scenes', suite='sunken_city', version=VERSION,
            scope='scene_local', building_class='underwater', responsibility='visual_only',
            category='underwater_scenery_assembly' if aid == ASSEMBLY_ID else 'underwater_scenic_building',
            classification={'category': 'decoration', 'subcategory': 'underwater_buildings'},
            water_layer='submerged', water_layer_role='entity' if aid == ASSEMBLY_ID else 'part',
            source=relative(source), source_sha256=source_hash, manifest=relative(manifest_path),
            stage=STAGE, maintenance_status=STAGE, runtime_path=None, prefab=None,
            runtime_integrated=False, runtime_status='pending', prefab_status='pending',
            runtime_validation='not_executed_not_in_scope', material_roles=sorted(roles),
            palette=relative(PALETTE), palette_sha256=palette_hash,
            license='user_provided_reference_commercial_rights_pending',
            reference_provenance='user_provided', commercial_rights_status='pending',
            reference_rights_verified=False, consumer_features=['SEA-ASSET'], verification=evidence,
            note='水下纯观赏 Blender 源；未接 Godot，runtime/prefab pending；参考图由用户提供，商业权属待核验，不宣称原创授权通过。',
        )
        row.update({field: False for field in FORBIDDEN})
        return row

    for entry in entries:
        aid, key = entry['component_id'], entry['key']
        require(isinstance(aid, str) and re.fullmatch(r'SEA-SCENE-SCITY-[A-Z0-9]+(?:-[A-Z0-9]+)*', aid)
                and aid != ASSEMBLY_ID and aid not in used_ids, '非法或重复 component_id：' + str(aid))
        require(isinstance(key, str) and re.fullmatch(r'[a-z0-9_]+', key)
                and key not in used_keys, aid + '：非法或重复 key')
        used_ids.add(aid)
        used_keys.add(key)
        target = project_path(entry['component_blend'])
        require(target.is_relative_to((DIRECTORY / 'component_packages').resolve())
                and target.suffix.lower() == '.blend' and target not in used_paths,
                aid + '：独立包路径越界、重复或不是 blend')
        used_paths.add(target)
        require(project_path(entry['palette']) == PALETTE.resolve(), aid + '：catalog 色盘错误')
        roles = entry['material_roles']
        require(isinstance(roles, list) and bool(roles) and len(roles) <= 3
                and len(roles) == len(set(roles)) and set(roles) <= ROLES, aid + '：材质角色非法')
        all_roles.update(roles)
        visual_only(entry, aid + '/catalog')
        package, skill = package_rows[key], skill_rows[key]
        require(package.get('component_id') == aid, aid + '：包报告 ID 错误')
        package_hash = hashed(target)
        match_hashes(package, ('package_sha256',), package_hash, aid + '/package')
        match_hashes(skill, ('package_sha256_before', 'package_sha256_after'), package_hash, aid + '/skill')
        require('package_sha256_before' in skill and 'package_sha256_after' in skill,
                aid + '：skill 缺少包 before/after 摘要')
        match_hashes(entry, ('source_sha256',), package_hash, aid + '/catalog')
        appended = package['appended_audit']
        passed(appended, aid + '/载入审计')
        reopened = package['reopened_audit']
        passed(reopened, aid + '/重开审计')
        require(appended.get('geometry_fingerprint') == reopened.get('geometry_fingerprint'),
                aid + '：载入与重开几何指纹不一致')
        fingerprint = reopened.get('geometry_fingerprint')
        require(bool(fingerprint) and fingerprint == entry.get('geometry_fingerprint'), aid + '：几何指纹不一致')
        path = target.parent / 'asset_manifest.json'
        data = manifest(path, aid, package_hash, component=True)
        require(project_path(data['component_blend']) == target, aid + '：manifest 独立包路径错误')
        require(project_path(data['source']) == MASTER.resolve(), aid + '：manifest 主源错误')
        require(data.get('geometry_fingerprint') == fingerprint, aid + '：manifest 几何指纹错误')
        require(sorted(data['material_roles']) == sorted(roles) == sorted(reopened['material_roles']),
                aid + '：材质角色与验收不一致')
        row = common(aid, entry['name'], target, package_hash, path, roles)
        for field in ('key', 'collection', 'root_object', 'origin', 'front_axis', 'component_family'):
            if field in entry:
                row[field] = entry[field]
        for field in ('bounds_size_m', 'triangles', 'polygons', 'geometry_fingerprint'):
            row[field] = reopened[field]
        records.append(row)

    assembly_path = DIRECTORY / 'asset_manifest.json'
    assembly_manifest = manifest(assembly_path, ASSEMBLY_ID, master_hash)
    require(set(assembly_manifest.get('dependencies', [])) == used_ids,
            '总装 manifest dependencies 必须等于 catalog component_id 集合')
    require(set(assembly_manifest.get('material_roles', [])) == all_roles and len(all_roles) <= 3,
            '总装材质角色必须等于组件角色并集且最多三个')
    assembly = common(ASSEMBLY_ID, assembly_manifest.get('name', '沉没城市-总装'),
                      MASTER, master_hash, assembly_path, all_roles)
    assembly.update(dependencies=[row['asset_id'] for row in records],
                    component_catalog=relative(catalog_path), component_count=len(entries))
    records.append(assembly)
    fresh = {row['asset_id']: row for row in records}
    seen, existing_suite, retained = set(), set(), {}
    for domain, domain_route in index['domains'].items():
        for old in books[domain][domain_route['asset_key']]:
            aid = old['asset_id']
            require(aid not in seen, '既有账本重复 AssetID：' + aid)
            seen.add(aid)
            if old.get('suite') == 'sunken_city' or aid.startswith('SEA-SCENE-SCITY-'):
                require(domain == 'scenes' and old.get('suite') == 'sunken_city'
                        and (aid in fresh or aid in retired),
                        '存在 catalog 外旧记录，拒绝删除或忽略：' + aid)
                existing_suite.add(aid)
            if aid in retired:
                definition = retired[aid]
                key = definition['key']
                old_directory = ROOT / 'art_source/scenes/sunken_city/v002/component_packages' / key
                require(old.get('version') == 'v002' and old.get('key') == key
                        and project_path(old['source']) == (old_directory / (key + '.blend')).resolve()
                        and project_path(old['manifest']) == (old_directory / 'asset_manifest.json').resolve(),
                        aid + '：只能保留既有 v002 独立源记录')
                match_hashes(old, ('source_sha256',), hashed(project_path(old['source'])), aid + '/保留源')
                visual_only(old, aid + '/退役记录')
                row = copy.deepcopy(old)
                row.update(stage='source_retained_not_in_current_layout',
                           maintenance_status='source_retained_not_in_current_layout',
                           retired_from_layout_version='v003')
                row['superseded_by'] = copy.deepcopy(definition.get('superseded_by'))
                if not row['superseded_by']:
                    row['pending_reason'] = (definition.get('pending_reason')
                                             or definition.get('retirement_reason')
                                             or '退役源已保留，替代组件映射待确认')
                else:
                    row.pop('pending_reason', None)
                retained[aid] = row
            if aid in fresh:
                require(domain == 'scenes' and old.get('suite') == 'sunken_city',
                        'AssetID 已由其他记录占用：' + aid)
                require(old.get('version') == VERSION
                        or (old.get('version'), VERSION) in {('v001', 'v002'), ('v002', 'v003')},
                        '既有版本不允许降级或跳改：' + aid)
                visual_only(old, aid + '/既有记录')
    if VERSION == 'v003':
        require(set(retained) == set(retired), '两个退役定义必须已有 v002 账本源，不得新建或丢弃')
        require((set(fresh) - new_v003_ids) <= existing_suite,
                'v003 升级缺少既有组件或总装记录，不得伪装成新增')
        require(all(row['version'] == 'v003' for row in book[route['asset_key']]
                    if row['asset_id'] in new_v003_ids), '新增组件 ID 已被旧版本占用')

    updated_book = copy.deepcopy(book)
    remaining = dict(fresh)
    updated_rows = []
    for old in book[route['asset_key']]:
        if old['asset_id'] in remaining:
            row = old | remaining.pop(old['asset_id'])
            if any(old.get(field) != row.get(field)
                   for field in ('source', 'source_sha256', 'manifest', 'version')):
                previous = copy.deepcopy(old.get('previous_sources', []))
                original = {field: old[field] for field in ('source', 'source_sha256', 'manifest', 'version')}
                if original not in previous:
                    previous.append(original)
                row['previous_sources'] = previous
            updated_rows.append(row)
        else:
            updated_rows.append(retained.get(old['asset_id'], old))
    updated_rows.extend(remaining.values())
    if VERSION == 'v003':
        suite_rows = [row for row in updated_rows if row.get('suite') == 'sunken_city']
        require(len(suite_rows) == 53 and {row['asset_id'] for row in suite_rows} == set(fresh) | set(retired),
                'v003 账本必须保留 50 个当前组件 + 总装 + 两个旧源，共 53 条')
    updated_book[route['asset_key']] = updated_rows
    updated_index = copy.deepcopy(source_index)
    updated_index['sources'] = []
    # 严格遵从 domains 插入顺序和各账本行顺序，不排序，不重算其他资产哈希。
    for domain, domain_route in index['domains'].items():
        domain_book = updated_book if domain == 'scenes' else books[domain]
        updated_index['sources'].extend(
            {field: row[field] for field in SOURCE_FIELDS}
            for row in domain_book[domain_route['asset_key']])

    print(f'校验通过：{len(entries)} 个当前组件 + 1 个总装 + {len(retained)} 个保留旧源；stage={STAGE}')
    print('仅写入：' + relative(ledger_path) + '、' + relative(index_path))
    print('后续由主 agent 补齐 SCITY 水层规则（若缺失），再运行 tools/apply_water_layer.py 刷新两类 views。')
    if not args.apply:
        print('DRY-RUN：未写入任何文件；已授权落盘时添加 --apply。')
        return 0

    def unchanged():
        for path, before in snapshots.items():
            require(path.read_bytes() == before, '输入被并发修改，请重新运行：' + str(path))
        for path, before in binary_hashes.items():
            require(sha(path) == before, '已验收文件被并发修改，请重新验收：' + str(path))

    changes = []
    for path, value in ((ledger_path, updated_book), (index_path, updated_index)):
        if json.loads(snapshots[path].decode('utf-8-sig')) == value:
            continue
        newline = '\r\n' if b'\r\n' in snapshots[path] else '\n'
        payload = (json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + '\n').replace('\n', newline).encode('utf-8')
        changes.append((path, payload))
    staged, committed = {}, []
    try:
        for path, payload in changes:
            # 暂存文件与目标同目录，os.replace 不跨卷，flush/fsync 后才替换。
            with tempfile.NamedTemporaryFile(dir=path.parent, prefix=path.name + '.', suffix='.tmp', delete=False) as stream:
                staged[path] = Path(stream.name)
                stream.write(payload)
                stream.flush()
                os.fsync(stream.fileno())
        unchanged()
        for path, payload in changes:
            require(path.read_bytes() == snapshots[path], '目标被并发修改：' + str(path))
            os.replace(staged[path], path)
            committed.append((path, payload))
    except Exception:
        for path, payload in reversed(committed):
            if path.read_bytes() != payload:
                print('回滚停止：目标已被其他写入者修改：' + str(path), file=sys.stderr)
                continue
            with tempfile.NamedTemporaryFile(dir=path.parent, prefix=path.name + '.', suffix='.tmp', delete=False) as stream:
                rollback = Path(stream.name)
                staged[path] = rollback
                stream.write(snapshots[path])
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(rollback, path)
        raise
    finally:
        for temp in staged.values():
            if temp.exists():
                temp.unlink()
    print(f'APPLIED：原子替换 {len(changes)} 个文件；runtime_inventory、manifest、views 未修改。')
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--apply', action='store_true', help='已授权执行：校验通过后写入两个登记文件')
    mode.add_argument('--dry-run', action='store_true', help='仅校验和预览（默认）')
    parser.add_argument('--report-dir', type=Path,
                        default=Path(os.environ.get('SEA_WORK_ROOT', ROOT.parent / 'sea-work')) / 'sunken_city' / VERSION,
                        help='工程外三份 verification.json 所在目录')
    args = parser.parse_args()
    try:
        return register(args)
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print('拒绝登记：' + str(exc), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
