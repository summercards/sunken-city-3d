"""登记已验收的 v003 运行资产；默认只读，--apply 才授权写入登记元数据。

不运行 Blender、Godot、测试或其他脚本，不修改 Blend、导出清单及运行资源。
--verification 必须为绝对 report.json 路径，可重复传入；所有报告均须成功，
合计覆盖 sunken-city 与 visual-sunken-city，且至少一份有成功的 asset_import。
原子性限于单文件：全部预暂存、输入 SHA256 并发检查、逐文件替换、异常回滚；
不宣称跨文件断电事务。默认 dry-run 不创建报告或临时文件。
"""

import argparse
import copy
import hashlib
import json
import math
import os
from pathlib import Path
import re
import struct
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[3]
SOURCE_DIR = ROOT / 'art_source/scenes/sunken_city/v003'
MASTER = SOURCE_DIR / 'sunken_city_v003.blend'
EXPORT = SOURCE_DIR / 'export/v003/export_manifest.json'
RUNTIME = ROOT / 'godot/assets/models/scenery/sunken_city/runtime_manifest.json'
ASSEMBLY = ROOT / 'godot/scenes/world/sunken_city.tscn'
MAIN = ROOT / 'godot/scenes/main.tscn'
PALETTE = ROOT / 'godot/assets/textures/shared/sea_cabin_timber_8x8_512.png'
ASSEMBLY_ID = 'SEA-SCENE-SCITY-ASSEMBLY'
RETIRED = {'SEA-SCENE-SCITY-T-JUNCTION', 'SEA-SCENE-SCITY-CANAL-END'}
STAGE = 'source_verified_runtime_verified'
SOURCE_FIELDS = ('asset_id', 'source', 'source_sha256', 'manifest')
PROTECTED_FIELDS = (*SOURCE_FIELDS, 'version', 'previous_sources', 'license',
                    'reference_provenance', 'commercial_rights_status',
                    'reference_rights_verified', 'reference_rights')
FALSE_FIELDS = (
    'collision', 'navigation', 'walk', 'interaction', 'shoreline', 'emission',
    'interactive', 'blocks_actor', 'blocks_water', 'walkable', 'has_landing',
    'navigation_obstacle', 'resource_output', 'gameplay_state', 'shoreline_source',
    'walk_areas', 'landing_points', 'water_shapes', 'navigation_obstacles',
    'interactions', 'production', 'save_fields', 'walk_surface', 'walkable_area',
    'actor_collision', 'boat_blocking', 'landing_point',
)
MATERIALS = {'SEA_Matte': 'matte', 'SEA_Metal': 'metal', 'SEA_Gloss': 'gloss'}
TEST_PATHS = ('godot/tests/test_sunken_city.gd', 'godot/tools/capture_sunken_city.gd')


def require(ok, message):
    if not ok:
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
    require(isinstance(value, str) and value and '\\' not in value,
            '工程路径必须为非空正斜杠路径：' + str(value))
    if value.startswith('res://'):
        value = 'godot/' + value[6:]
    path = (ROOT / value).resolve()
    require(path.is_relative_to(ROOT.resolve()), '路径越出工程：' + value)
    return path


def clean(data, label):
    require(isinstance(data, dict), label + ' 必须为对象')
    for key in ('errors', 'failures', 'unexpected_errors', 'failed_labels'):
        require(not data.get(key), label + ' 存在失败：' + key)
    for key in ('passed', 'matches_source', 'source_matches'):
        if key in data:
            require(data[key] is True, label + '：' + key + ' 不是 true')
    if 'exit_code' in data:
        require(type(data['exit_code']) is int and data['exit_code'] == 0,
                label + ' 原执行 exit_code 不是 0')


def passed(data, label):
    clean(data, label)
    require(data.get('passed') is True, label + ' 缺少 passed:true')


def exit_zero(data, label):
    clean(data, label)
    require(type(data.get('exit_code')) is int and data['exit_code'] == 0,
            label + ' 缺少原执行 exit_code:0')


def same_protected(before, after, label):
    for field in PROTECTED_FIELDS:
        require((field in before) == (field in after) and before.get(field) == after.get(field),
                label + ' 受保护字段被修改：' + field)


def pure_visual(data, label):
    require(data.get('building_class', 'underwater') == 'underwater', label + ' 非水下观赏资产')
    for field in FALSE_FIELDS:
        require(not data.get(field), label + ' 声明了禁止职责：' + field)


class Inputs:
    def __init__(self):
        self.hashes = {}
        self.raw = {}
        self.directories = {}

    def hashed(self, path):
        path = path.resolve()
        require(path.is_file(), '缺少输入文件：' + str(path))
        if path not in self.hashes:
            self.hashes[path] = sha(path)
        return self.hashes[path]

    def read(self, path):
        path = path.resolve()
        raw = path.read_bytes()
        digest = hashlib.sha256(raw).hexdigest()
        require(path not in self.hashes or self.hashes[path] == digest,
                '读取期间输入发生变化：' + str(path))
        self.hashes[path] = digest
        self.raw[path] = raw
        return raw

    def text(self, path):
        return self.read(path).decode('utf-8-sig').replace('\r\n', '\n')

    def json(self, path):
        return json.loads(self.read(path).decode('utf-8-sig'))

    def match(self, path, expected, label):
        require(isinstance(expected, str) and re.fullmatch('[0-9a-fA-F]{64}', expected),
                label + ' 缺少合法 SHA256')
        require(self.hashed(path) == expected.lower(), label + ' SHA256 不匹配')

    def listing(self, directory, pattern):
        directory = directory.resolve()
        entries = sorted(p.resolve() for p in directory.glob(pattern))
        self.directories[(directory, pattern)] = entries
        return entries

    def unchanged(self):
        for path, digest in self.hashes.items():
            require(path.is_file() and sha(path) == digest, '输入被并发修改：' + str(path))
        for (directory, pattern), entries in self.directories.items():
            require(sorted(p.resolve() for p in directory.glob(pattern)) == entries,
                    '目录内容被并发修改：' + str(directory))


def parameter(text, name, expected, label):
    values = re.findall(r'^\s*' + re.escape(name) + r'\s*=\s*(.*?)\s*$', text, re.M)
    require(values == [expected], label + ' 要求 ' + name + '=' + expected)


def glb_json(inputs, path):
    # 只读 JSON chunk，不把 GLB 二进制缓冲区驻留到元数据快照中。
    inputs.hashed(path)
    with path.open('rb') as stream:
        header = stream.read(20)
        require(len(header) == 20, 'GLB 头过短：' + str(path))
        magic, version, size, count, kind = struct.unpack('<4sIIII', header)
        require(magic == b'glTF' and version == 2 and size == path.stat().st_size
                and kind == 0x4E4F534A and count <= size - 20, 'GLB 头无效：' + str(path))
        return json.loads(stream.read(count).decode('utf-8'))


def validate_prefab(inputs, path, glb, document, entry):
    text = inputs.text(path)
    require('path=' + json.dumps('res://' + glb.relative_to(ROOT / 'godot').as_posix()) in text,
            entry['key'] + ' prefab 未引用对应 GLB')
    require(not re.search(r'type="(?:Script|.*Collision.*|.*Navigation.*|Area3D)"|^script\s*=', text, re.M),
            entry['key'] + ' prefab 含玩法脚本或碰撞/导航')
    material_refs = {}
    for line in text.splitlines():
        if line.startswith('[ext_resource '):
            fields = dict(re.findall(r'(\w+)="([^"]*)"', line))
            if fields.get('type') in ('Material', 'StandardMaterial3D'):
                material_refs[fields['id']] = fields['path']
    used = []
    for block in re.split(r'(?=^\[node )', text, flags=re.M):
        overrides = re.findall(r'^surface_material_override/(\d+)\s*=\s*ExtResource\("([^"]+)"\)\s*$', block, re.M)
        if not overrides:
            continue
        heading = block.splitlines()[0]
        node_name = re.search(r'name="([^"]+)"', heading)
        require(node_name is not None, '材质覆盖缺少节点名：' + entry['key'])
        candidates = [node for node in document.get('nodes', [])
                      if node.get('name') == node_name.group(1) and 'mesh' in node]
        if node_name.group(1) == 'Visual' and not candidates:
            candidates = [document['nodes'][i] for i in document['scenes'][0]['nodes']
                          if 'mesh' in document['nodes'][i]]
        require(len(candidates) == 1, entry['key'] + ' 材质覆盖节点无法唯一对应 GLB')
        primitives = document['meshes'][candidates[0]['mesh']]['primitives']
        require(sorted(int(i) for i, _ in overrides) == list(range(len(primitives))),
                entry['key'] + ' 未逐 surface 序列化材质')
        for index, resource_id in overrides:
            primitive = primitives[int(index)]
            role = document['materials'][primitive['material']]['name']
            require(role in MATERIALS and material_refs.get(resource_id)
                    == 'res://assets/materials/sunken_city/' + MATERIALS[role] + '.tres',
                    entry['key'] + ' 序列化材质角色不匹配')
            used.append(role)
    count = sum(len(mesh['primitives']) for mesh in document.get('meshes', []))
    require(len(used) == count and set(used) == set(entry['material_roles']),
            entry['key'] + ' 材质绑定覆盖不完整')


def validate_reports(inputs, paths, master_hash, runtime_files):
    covered, evidence, imports = set(), [], 0
    for supplied in paths:
        require(supplied.is_absolute() and supplied.name == 'report.json',
                '--verification 必须为绝对 report.json 路径')
        path = supplied.resolve()
        require(path.as_posix() not in evidence, '重复 verification：' + str(path))
        report = inputs.json(path)
        clean(report, str(path))
        results = report.get('results')
        require(isinstance(results, dict) and results, 'runner 报告没有 results：' + str(path))
        run_dir = Path(report.get('run_dir', ''))
        require(run_dir.is_absolute() and run_dir.resolve() == path.parent,
                'runner run_dir 必须对应原始报告目录')
        for name, result in results.items():
            passed(result, name)
            exit_zero(result, name)
            require(result.get('completion_marker') is True, name + ' 缺少完成标记')
            log = Path(result.get('log', ''))
            require(log.is_absolute() and log.resolve().parent == run_dir.resolve(), name + ' 日志路径越界')
            text = inputs.text(log)
            require(not re.search(r'SCRIPT ERROR|SHADER ERROR|ERROR:|\bFAIL\b', text), name + ' 原日志存在错误')
            if name not in ('sunken-city', 'visual-sunken-city'):
                continue
            marker = r'\[sunken-city\] [1-9]\d* checks, 0 failures' if name == 'sunken-city' else r'\[sunken-city-render\] [1-9]\d* checks, 0 failures'
            require(re.search(marker, text), name + ' 原日志没有成功结束标记')
            if name.startswith('visual-'):
                require(result.get('renderer') == 'real' and '--headless' not in result.get('command', []),
                        'visual-sunken-city 必须使用真实渲染器')
            # 隔离 runner 复制的场景与测试必须仍对应本轮文件，不用旧通过记录冒充新输出。
            isolated = run_dir / 'project'
            for current in runtime_files:
                counterpart = isolated / current.relative_to(ROOT / 'godot')
                inputs.match(counterpart, inputs.hashed(current), name + '/' + relative(current))
            if name == 'sunken-city':
                source_evidence = inputs.json(isolated / 'outputs/sunken-city-structure.json')
                clean(source_evidence, '结构证据')
                require(source_evidence.get('source_master_sha256') == master_hash,
                        '结构证据不匹配当前 source master')
                require(source_evidence.get('failures') == 0 and type(source_evidence.get('checks')) is int
                        and source_evidence['checks'] > 0, '结构证据不完整')
            covered.add(name)
        if 'asset_import' in report:
            imported = report['asset_import']
            exit_zero(imported, 'asset_import')
            log = Path(imported.get('log', ''))
            require(log.is_absolute() and log.resolve().parent == run_dir.resolve(), 'asset_import 日志路径越界')
            require(not re.search(r'SCRIPT ERROR|SHADER ERROR|ERROR:', inputs.text(log)), '原 import_assets 日志存在错误')
            imports += 1
        evidence.append(path.as_posix())
    require(covered == {'sunken-city', 'visual-sunken-city'}, '报告合计必须覆盖两个检查且 passed:true、exit_code:0')
    require(imports > 0, '至少一份 runner 报告必须包含成功的 --import-assets 记录')
    return evidence


def atomic_apply(inputs, changes):
    staged, committed = {}, []

    def temporary(path, payload):
        require(path.parent.is_dir(), '写入父目录不存在：' + str(path.parent))
        with tempfile.NamedTemporaryFile(dir=path.parent, prefix=path.name + '.', suffix='.tmp', delete=False) as stream:
            target = Path(stream.name)
            staged[path] = target
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        return target

    try:
        for path, payload in changes.items():
            temporary(path, payload)
        inputs.unchanged()
        for path, payload in changes.items():
            before = inputs.raw.get(path)
            require((before is None and not path.exists()) or
                    (before is not None and path.is_file() and sha(path) == inputs.hashes[path]),
                    '写入目标被并发修改：' + str(path))
            os.replace(staged[path], path)
            committed.append((path, payload, before))
    except BaseException:
        for path, payload, before in reversed(committed):
            if not path.is_file() or sha(path) != hashlib.sha256(payload).hexdigest():
                print('回滚停止，目标已被其他写入者修改：' + str(path), file=sys.stderr)
                continue
            if before is None:
                path.unlink()
            else:
                os.replace(temporary(path, before), path)
        raise
    finally:
        for path in staged.values():
            if path.exists():
                path.unlink()


def register(args):
    inputs = Inputs()
    work = args.report_dir.resolve()
    require(work.is_dir() and not work.is_relative_to(ROOT.resolve()), '报告目录必须已存在且位于工程外')
    export = inputs.json(EXPORT)
    runtime = inputs.json(RUNTIME)
    passed(export, 'export_manifest')
    require(export.get('suite') == runtime.get('suite') == 'sunken_city'
            and export.get('version') == runtime.get('version') == 'v003', '清单版本或套件错误')
    require(runtime.get('pure_visual') is True and project_path(runtime['assembly']) == ASSEMBLY.resolve(),
            '运行清单不是纯观赏稳定总装')
    require(len(runtime.get('instances', [])) == 388, '运行实例数不是 388')
    master_hash = inputs.hashed(MASTER)
    require(runtime.get('source_master_sha256') == master_hash, '运行清单主源 SHA256 不匹配')
    protected = export.get('protected_sources')
    require(isinstance(protected, dict) and protected.get(relative(MASTER)) == master_hash,
            'export_manifest 缺少主源保护记录')
    for name, expected in protected.items():
        inputs.match(project_path(name), expected, '受保护源 ' + name)
    source_report_path = work.parent / 'source_verification.json'
    source_report = inputs.json(source_report_path)
    passed(source_report, 'source_verification')
    exit_zero(source_report, 'source_verification')
    hash_fields = ('source_sha256', 'source_master_sha256', 'master_sha256',
                   'source_sha256_before', 'source_sha256_after')
    hashes = [source_report[k] for k in hash_fields if k in source_report]
    require(hashes and all(value == master_hash for value in hashes), 'source 报告不匹配当前主源')
    require(('source_sha256_before' in source_report) == ('source_sha256_after' in source_report),
            'source 报告 before/after 必须成对')
    require(source_report.get('components') == 50 and source_report.get('instances') == 388,
            'source 报告组件或实例数量错误')
    source_name = source_report.get('file', source_report.get('source'))
    if source_name:
        require(Path(source_name).resolve() == MASTER.resolve(), 'source 报告不是当前主源')
    fidelity_path = work / 'fidelity_verification.json'
    fidelity = inputs.json(fidelity_path)
    passed(fidelity, 'fidelity_verification')
    require(fidelity.get('source_protected') is True and fidelity.get('visual_review') == 'passed',
            '保真必须 source_protected:true 且父审美 visual_review=passed')
    require(set(fidelity.get('views', [])) >= {'game_angle', 'front', 'back', 'side'}, '保真缺少四视角')

    index = inputs.json(ROOT / 'assets/registry/ledger_index.json')
    books, seen = {}, set()
    for domain, route in index['domains'].items():
        books[domain] = inputs.json(project_path(route['ledger']))
        for row in books[domain][route['asset_key']]:
            require(row['asset_id'] not in seen, '全域账本重复 AssetID：' + row['asset_id'])
            seen.add(row['asset_id'])
    route = index['domains']['scenes']
    ledger_path = project_path(route['ledger'])
    book = books['scenes']
    updated_book = copy.deepcopy(book)
    rows = {row['asset_id']: row for row in updated_book[route['asset_key']]}
    suite = {row['asset_id']: row for row in book[route['asset_key']]
             if row.get('suite') == 'sunken_city' or row['asset_id'].startswith('SEA-SCENE-SCITY-')}
    entries = export.get('components', [])
    runtime_entries = runtime.get('components', [])
    require(len(entries) == len(runtime_entries) == 50, '两份清单必须各有 50 个组件')
    by_key = {row['key']: row for row in runtime_entries}
    ids = {row['asset_id'] for row in entries}
    require(len(by_key) == len(ids) == len({row['key'] for row in entries}) == 50, '组件 key/ID 重复')
    current_ids = ids | {ASSEMBLY_ID}
    require(len(suite) == 53 and set(suite) == current_ids | RETIRED, '账本必须为 51 个当前源及两个保留旧源')
    for aid in current_ids:
        require(suite[aid].get('suite') == 'sunken_city' and suite[aid].get('version') == 'v003',
                aid + ' 必须先完成 v003 源登记；本脚本不升级或重写源')
        pure_visual(suite[aid], aid)
        require(suite[aid].get('commercial_rights_status') == 'pending'
                and suite[aid].get('reference_rights_verified') is False, aid + ' 商业授权必须仍为 pending')
    for aid in RETIRED:
        require(suite[aid].get('version') == 'v002', aid + ' 必须保留 v002')

    inventory_files = {}
    tested_files = [MAIN, ASSEMBLY, RUNTIME] + [ROOT / name for name in TEST_PATHS]
    manifests = {}
    total_before = total_after = 0
    for entry in entries:
        key, aid = entry['key'], entry['asset_id']
        require(re.fullmatch('[a-z0-9_]+', key), '非法组件 key')
        rec = by_key.get(key)
        require(rec and rec['asset_id'] == aid, key + ' 运行清单 ID 不一致')
        require(set(rec.get('roles', [])) == set(entry.get('material_roles', []))
                and rec.get('bounds_blender') == entry.get('bounds_blender'),
                key + ' 两份清单的材质角色或包围盒不一致')
        row = rows[aid]
        source, optimized, glb = (project_path(entry[k]) for k in ('source', 'optimized_source', 'glb'))
        expected_source = SOURCE_DIR / 'component_packages' / key / (key + '.blend')
        require(source == expected_source.resolve() and project_path(row['source']) == source,
                aid + ' 当前源路径与账本不一致')
        require(optimized != source and optimized.is_relative_to((SOURCE_DIR / 'export/v003').resolve())
                and optimized.suffix == '.blend' and 'optimized' in optimized.stem, aid + ' 优化源必须独立另存')
        require(glb == (ROOT / f'godot/assets/models/scenery/sunken_city/{key}/{key}.glb').resolve()
                and project_path(rec['glb']) == glb, key + ' 不是稳定 GLB 路径')
        source_hash = entry['source_sha256_before']
        require(source_hash == entry['source_sha256_after'] == row['source_sha256']
                == rec['source_sha256'] == protected.get(relative(source)), aid + ' 源保护摘要不一致')
        require(entry.get('source_preserved') is True, aid + ' 缺少源保护结论')
        inputs.match(source, source_hash, aid + '/source')
        inputs.match(optimized, entry['optimized_sha256'], aid + '/optimized')
        inputs.match(glb, entry['glb_sha256'], aid + '/GLB')
        require(rec['glb_sha256'] == entry['glb_sha256'], aid + ' 两份清单 GLB SHA256 不一致')
        before, after, ratio = (entry[k] for k in ('triangles_before', 'triangles_after', 'reduction_ratio'))
        require(type(before) is int and type(after) is int and before >= after >= 0
                and rec['triangles'] == after and entry.get('exported_triangles') == after,
                aid + ' 三角面统计不一致')
        require((before == 0 and ratio is None) or (before > 0 and type(ratio) in (int, float)
                and math.isfinite(ratio) and math.isclose(ratio, (before - after) / before, abs_tol=1e-12)),
                aid + ' reduction_ratio 错误')
        require(isinstance(entry.get('operations'), dict) and entry['operations'], aid + ' 缺少优化操作记录')
        total_before += before
        total_after += after
        prefab = ROOT / f'godot/scenes/components/scenery/sunken_city/{key}.tscn'
        require(project_path(rec['prefab']) == prefab.resolve(), aid + ' 不是稳定 prefab 路径')
        inputs.match(prefab, rec['prefab_sha256'], aid + '/prefab')
        document = glb_json(inputs, glb)
        require(not document.get('images') and not document.get('textures'), aid + ' GLB 包含图片/纹理')
        validate_prefab(inputs, prefab, glb, document, entry)
        importer = Path(str(glb) + '.import')
        parameter(inputs.text(importer), 'gltf/embedded_image_handling', '0', relative(importer))
        for path in (glb, importer, prefab):
            inventory_files[path.resolve()] = aid
        tested_files.append(prefab)
        manifest_path = project_path(row['manifest'])
        require(manifest_path == (source.parent / 'asset_manifest.json').resolve(), aid + ' 源 manifest 路径错误')
        manifest = inputs.json(manifest_path)
        require(manifest.get('asset_ledger') == route['ledger'] + '#' + aid
                and manifest.get('source_sha256') == source_hash
                and manifest.get('source_master_sha256') == master_hash, aid + ' manifest 来源/账本链接错误')
        pure_visual(manifest, aid + '/manifest')
        export_info = {k: copy.deepcopy(entry[k]) for k in (
            'optimized_source', 'optimized_sha256', 'triangles_before', 'triangles_after',
            'reduction_ratio', 'operations', 'bounds_blender')}
        export_info.update(runtime_path=relative(glb), runtime_sha256=inputs.hashed(glb),
                           prefab=relative(prefab), prefab_sha256=inputs.hashed(prefab),
                           export_manifest=relative(EXPORT), source_verified=True, runtime_verified=True)
        manifests[manifest_path] = (manifest, export_info)
        row.update(export_info)

    material_dir = ROOT / 'godot/assets/materials/sunken_city'
    material_paths = inputs.listing(material_dir, '*.tres')
    require(set(material_paths) == {(material_dir / (name + '.tres')).resolve() for name in MATERIALS.values()},
            '旧城必须恰好三个持久材质')
    for path in material_paths:
        text = inputs.text(path)
        require('type="StandardMaterial3D"' in text and 'res://assets/textures/shared/sea_cabin_timber_8x8_512.png' in text,
                '材质不是指定 StandardMaterial3D/公共色盘：' + str(path))
        for name, value in (('texture_filter', '0'), ('texture_repeat', 'false'), ('emission_enabled', 'false')):
            parameter(text, name, value, relative(path))
        inventory_files[path] = ASSEMBLY_ID
        tested_files.append(path)
    palette_import = Path(str(PALETTE) + '.import')
    palette_text = inputs.text(palette_import)
    parameter(palette_text, 'compress/mode', '0', '色盘导入')
    parameter(palette_text, 'mipmaps/generate', 'false', '色盘导入')
    source_palette = project_path(rows[ASSEMBLY_ID]['palette'])
    inputs.match(source_palette, rows[ASSEMBLY_ID]['palette_sha256'], '源色盘')
    inputs.match(PALETTE, inputs.hashed(source_palette), '运行色盘')

    build = inputs.json(work / 'runtime_build.json')
    passed(build, 'runtime_build')
    backup = work / 'main_before_sunken_city.tscn'
    inputs.match(backup, build['main_sha256_before'], '主场景接入前备份')
    main = inputs.text(MAIN)
    resource = '[ext_resource type="PackedScene" path="res://scenes/world/sunken_city.tscn" id="38_sunken_city"]\n'
    restore_path = work / 'depth_restore_verification.json'
    if restore_path.is_file():
        restore = inputs.json(restore_path)
        passed(restore, '用户确认的根深度恢复')
        require(restore.get('user_confirmed') == '恢复原水下深度（推荐）', '根高度恢复缺用户确认')
        latest_before = inputs.read(work / 'main_before_depth_restore.tscn')
        old_depth = b'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 38.04888, 0)'
        new_depth = b'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0)'
        require(hashlib.sha256(latest_before).hexdigest() == restore['before_sha256']
                and latest_before.count(old_depth) == 1
                and latest_before.replace(old_depth, new_depth) == inputs.read(MAIN)
                and inputs.hashed(MAIN) == restore['after_sha256'], '恢复超出用户批准的单行根Y修改')
        node_pattern = r'^\[node name="SunkenCity" parent="World"(?: unique_id=\d+)? instance=ExtResource\("38_sunken_city"\)\]\n(?:transform = Transform3D\(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0\)\n)?\n?'
        require(main.count(resource) == 1 and len(re.findall(node_pattern, main, re.M)) == 1, '街区引用重复或根变换不恒等')
        rest = re.sub(node_pattern, '', main, flags=re.M).replace(resource, '')
        def editor_semantics(text):
            text = re.sub(r' unique_id=\d+', '', text)
            text = re.sub(r' uid="uid://[^"]+"', '', text)
            text = re.sub(r'ArrayMesh_[A-Za-z0-9_]+', 'ArrayMesh_EDITOR_ID', text)
            return '\n'.join(line for line in text.splitlines() if line.strip())
        require(editor_semantics(rest) == editor_semantics(inputs.text(backup)),
                '编辑器保存除UID/资源ID/空白外改变了未授权主场景语义')
    else:
        inputs.match(MAIN, build['main_sha256_after'], '主场景本轮输出')
        node = '[node name="SunkenCity" parent="World" instance=ExtResource("38_sunken_city")]\n\n'
        require(main.count(resource) == main.count(node) == 1, '主场景接入必须恰好一个资源和 World/SunkenCity 节点')
        require(main.replace(resource, '').replace(node, '') == inputs.text(backup),
                '主场景逆向差异包含本轮接入以外的修改')

    evidence = validate_reports(inputs, args.verification, master_hash, tested_files)
    assembly_row = rows[ASSEMBLY_ID]
    require(project_path(assembly_row['source']) == MASTER.resolve() and assembly_row['source_sha256'] == master_hash,
            '总装账本主源不一致')
    assembly_manifest_path = project_path(assembly_row['manifest'])
    require(assembly_manifest_path == (SOURCE_DIR / 'asset_manifest.json').resolve(), '总装源 manifest 路径错误')
    assembly_manifest = inputs.json(assembly_manifest_path)
    require(assembly_manifest.get('asset_ledger') == route['ledger'] + '#' + ASSEMBLY_ID
            and assembly_manifest.get('source_sha256') == master_hash
            and set(assembly_manifest.get('dependencies', [])) == ids, '总装 manifest 来源或依赖不一致')
    pure_visual(assembly_manifest, '总装 manifest')
    assembly_info = dict(runtime_path=relative(ASSEMBLY), runtime_sha256=inputs.hashed(ASSEMBLY),
                         prefab=relative(ASSEMBLY), prefab_sha256=inputs.hashed(ASSEMBLY),
                         export_manifest=relative(EXPORT), source_verified=True, runtime_verified=True,
                         triangles_before=total_before, triangles_after=total_after,
                         reduction_ratio=(total_before - total_after) / total_before if total_before else None,
                         component_count=50, instance_count=388,
                         optimized_sources=[{'asset_id': e['asset_id'], 'optimized_source': e['optimized_source'],
                                             'optimized_sha256': e['optimized_sha256']} for e in entries])
    assembly_row.update(assembly_info)
    manifests[assembly_manifest_path] = (assembly_manifest, assembly_info)
    outputs = {}
    for aid in current_ids:
        row = rows[aid]
        old = suite[aid]
        row.update(stage=STAGE, maintenance_status=STAGE, runtime_status='verified', prefab_status='verified',
                   runtime_validation='sunken-city_and_visual-sunken-city_passed', runtime_integrated=True,
                   responsibility='visual_only', source_verified=True, runtime_verified=True)
        row.update({field: False for field in FALSE_FIELDS})
        row['runtime_verification'] = evidence
        row['fidelity_verification'] = fidelity_path.as_posix()
        same_protected(old, row, aid)
    for path, (old, info) in manifests.items():
        new = copy.deepcopy(old)
        new.update(exported=True, runtime_integrated=True)
        new['runtime_export'] = dict(info, verification=evidence, fidelity_verification=fidelity_path.as_posix())
        require(new.get('asset_ledger') == old.get('asset_ledger'), 'manifest 账本链接被破坏')
        same_protected(old, new, str(path))
        outputs[path] = new
    # 未授权域、退役行及行顺序保持原样；只读重建 source index 投影。
    for old, new in zip(book[route['asset_key']], updated_book[route['asset_key']]):
        require(old['asset_id'] == new['asset_id'], '账本行顺序发生变化')
        if old['asset_id'] not in current_ids:
            require(old == new, '修改了非当前 v003 行')
    outputs[ledger_path] = updated_book
    source_index_path = ROOT / 'assets/registry/current_source_index.json'
    source_index = inputs.json(source_index_path)
    updated_index = copy.deepcopy(source_index)
    updated_index['sources'] = [
        {field: row[field] for field in SOURCE_FIELDS}
        for domain, domain_route in index['domains'].items()
        for row in (updated_book if domain == 'scenes' else books[domain])[domain_route['asset_key']]
    ]
    require(source_index.get('sources') == updated_index['sources'], 'current_source_index 已漂移；先完成独立源登记，不在运行登记中掩盖')
    outputs[source_index_path.resolve()] = updated_index

    inventory_path = project_path(index['runtime_inventory'])
    inventory = inputs.json(inventory_path)
    updated_inventory = copy.deepcopy(inventory)
    inventory_by_path = {item['path']: item for item in updated_inventory['resources']}
    require(len(inventory_by_path) == len(updated_inventory['resources']), 'runtime inventory 路径重复')
    for path in (ASSEMBLY, RUNTIME, MAIN, *(ROOT / name for name in TEST_PATHS)):
        inventory_files[path.resolve()] = ASSEMBLY_ID
    runner = ROOT / 'scripts/run_verification.py'
    if relative(runner) in inventory_by_path:
        inventory_files[runner.resolve()] = None
    existing_main = inventory_by_path.get(relative(MAIN))
    if existing_main:
        baseline = inputs.read(backup)
        allowed_main_hashes = {inputs.hashed(MAIN), hashlib.sha256(baseline).hexdigest(),
                               hashlib.sha256(baseline.replace(b'\r\n', b'\n')).hexdigest(), build['main_sha256_after']}
        require(existing_main['sha256'] in allowed_main_hashes,
                '主场景已有未登记的第三方漂移；拒绝顺带刷新')
    added = refreshed = 0
    for path, aid in sorted(inventory_files.items(), key=lambda item: relative(item[0])):
        name = relative(path)
        previous = inventory_by_path.get(name)
        item = copy.deepcopy(previous) if previous is not None else {'path': name, 'asset_id': aid, 'status': STAGE}
        item.update(sha256=inputs.hashed(path), bytes=path.stat().st_size)
        if previous is None:
            updated_inventory['resources'].append(item)
            added += 1
        elif item != previous:
            previous.update(item)
            refreshed += 1
    for old, new in zip(inventory['resources'], updated_inventory['resources']):
        if old['path'] not in {relative(p) for p in inventory_files}:
            require(old == new, '修改了白名单以外的 runtime inventory 记录')
    require(not set(outputs).intersection(inventory_files), '元数据写入目标与运行资源白名单冲突')
    outputs[inventory_path] = updated_inventory
    changes = {}
    for path, value in outputs.items():
        path = path.resolve()
        require(path in inputs.raw, '登记目标缺少原始快照：' + str(path))
        if json.loads(inputs.raw[path].decode('utf-8-sig')) == value:
            continue
        newline = '\r\n' if b'\r\n' in inputs.raw[path] else '\n'
        changes[path] = (json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + '\n').replace('\n', newline).encode('utf-8')
    report_path = (work / 'runtime_registration.json').resolve()
    require(report_path not in outputs and report_path not in inputs.hashes, '报告路径与输入冲突')
    if report_path.exists():
        inputs.read(report_path)
    summary = dict(passed=True, suite='sunken_city', version='v003', applied=bool(args.apply),
                   current_records=51, retained_v002_records=2, components=50, instances=388,
                   updated_ledger_rows=sum(a != b for a, b in zip(book[route['asset_key']], updated_book[route['asset_key']])),
                   updated_manifests=sum(path.resolve() in changes for path in manifests),
                   runtime_inventory_added=added, runtime_inventory_updated=refreshed,
                   source_index_unchanged=source_index == updated_index,
                   source_master_sha256=master_hash, source_protected=True, commercial_rights_status='pending',
                   verification=evidence, fidelity_verification=fidelity_path.as_posix(),
                   changed_files=[relative(path) for path in changes],
                   runtime_inventory_allowlist=[relative(path) for path in sorted(inventory_files)],
                   atomicity='single_file_replace_with_preflight_input_sha256_and_best_effort_rollback')
    inputs.unchanged()
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    if not args.apply:
        print('DRY-RUN：无写入；全部门禁通过后，用同一命令添加 --apply 才登记。')
        return 0
    require(not report_path.exists() or report_path in inputs.raw, '报告被并发创建')
    changes[report_path] = (json.dumps(summary, ensure_ascii=False, indent=2, allow_nan=False) + '\n').encode('utf-8')
    atomic_apply(inputs, changes)
    print(f'APPLIED：原子替换 {len(changes)} 个登记/报告文件；运行文件及全部 Blend 未修改。')
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--verification', action='append', required=True, type=Path,
                        help='原始 runner 的绝对 report.json 路径；支持重复传入合并两个检查')
    parser.add_argument('--report-dir', type=Path, default=ROOT.parent / 'sea-work/sunken_city/v003/import',
                        help='工程外 import 证据目录 W；读取 fidelity/runtime_build，在 --apply 后写 runtime_registration.json')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--apply', action='store_true', help='明确授权：通过门禁后写入登记及报告')
    mode.add_argument('--dry-run', action='store_true', help='只读校验并显示计划（默认）')
    args = parser.parse_args()
    try:
        return register(args)
    except (OSError, ValueError, KeyError, TypeError, IndexError, struct.error) as exc:
        print('拒绝登记：' + str(exc), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
