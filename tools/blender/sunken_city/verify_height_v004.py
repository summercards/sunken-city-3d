"""独立只读验收 v003/v004 总源；唯一输出为指定 JSON 报告。"""
import hashlib
import json
import math
import sys
import traceback
import zipfile
from array import array
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / 'art_source/scenes/sunken_city'
REPORT = ROOT.parent / 'sea-work/sunken_city/v004/height_independent_verification.json'
LOCK = ROOT.parent / 'sea-work/sunken_city/v004/scope_lock.json'
ARCHIVE = SOURCE / 'v003/export/v003/runtime_preserved_before_v004.zip'
VERSIONS = ('v003', 'v004')
TOLERANCE = 0.002
result = {
    'schema': 'sea.sunken_city.height_independent_verification.v1',
    'started_at': datetime.now(timezone.utc).isoformat(),
    'blender_version': bpy.app.version_string,
    'background': bpy.app.background,
    'passed': False,
    'exit_code': 1,
    'checks': 0,
    'check_groups': {},
    'errors': [],
    'snapshots': {},
    'source_hashes': {},
    'method': {
        'geometry': '实际网格原始 float32/int32 字节；不量化、不读取旧验收结论',
        'fingerprint': 'co、边/loop/多边形拓扑、全部 UV 层及活动标记、材质槽/逐面角色',
        'instance_minz': 'mathutils: 实例 matrix_world @ collection offset逆变换 @ 定义对象 matrix_world @ 实际顶点',
        'grounding': '所有实例实际世界 minz 对比 v003；改楼仅允许平移 z，误差严格小于 0.002m',
        'writes': [str(REPORT)],
        'source_save': False,
    },
}


def check(ok, group, message, **details):
    result['checks'] += 1
    summary = result['check_groups'].setdefault(group, {'checks': 0, 'failures': 0})
    summary['checks'] += 1
    if not ok:
        summary['failures'] += 1
        result['errors'].append({'group': group, 'message': message, **details})
    return bool(ok)


def sha(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def matrix_rows(matrix):
    return [list(row) for row in matrix]


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode('utf-8')


def field_bytes(collection, name, code, width=1):
    values = array(code, [0]) * (len(collection) * width)
    collection.foreach_get(name, values)
    if sys.byteorder != 'little':
        values.byteswap()
    return values.tobytes()


def mesh_bytes(obj):
    mesh = obj.data
    uv_metadata = [
        {'name': layer.name, 'active_render': layer.active_render,
         'active_clone': layer.active_clone}
        for layer in mesh.uv_layers
    ]
    return {
        'co': field_bytes(mesh.vertices, 'co', 'f', 3),
        'edges': field_bytes(mesh.edges, 'vertices', 'i', 2),
        'loop_vertex': field_bytes(mesh.loops, 'vertex_index', 'i'),
        'loop_edge': field_bytes(mesh.loops, 'edge_index', 'i'),
        'polygon_start': field_bytes(mesh.polygons, 'loop_start', 'i'),
        'polygon_total': field_bytes(mesh.polygons, 'loop_total', 'i'),
        'polygon_material': field_bytes(mesh.polygons, 'material_index', 'i'),
        'uv_metadata': canonical({'layers': uv_metadata, 'active_index': mesh.uv_layers.active_index}),
        'uv': b''.join(field_bytes(layer.data, 'uv', 'f', 2) for layer in mesh.uv_layers),
        'matroles': canonical({
            'mesh_slots': [mat.name if mat else None for mat in mesh.materials],
            'object_slots': [(slot.link, slot.material.name if slot.material else None)
                             for slot in obj.material_slots],
        }),
    }


def fingerprint(parts):
    digest = hashlib.sha256()
    for name, data in sorted(parts.items()):
        label = name.encode('utf-8')
        digest.update(len(label).to_bytes(8, 'little'))
        digest.update(label)
        digest.update(len(data).to_bytes(8, 'little'))
        digest.update(data)
    return {
        'sha256': digest.hexdigest(),
        'parts': {name: {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
                  for name, data in parts.items()},
    }


def snapshot(version, catalog):
    path = SOURCE / version / f'sunken_city_{version}.blend'
    bpy.ops.wm.open_mainfile(filepath=str(path), load_ui=False, use_scripts=False)
    scene = bpy.data.scenes.get('沉没旧城_完整参考布局_' + version)
    if not check(scene is not None, 'structure', version + ' 实际布局场景存在'):
        return {}, {}
    if bpy.context.window:
        bpy.context.window.scene = scene
    bpy.context.view_layer.update()
    geometry, raw, definitions = {}, {}, {}
    collection_to_key = {}
    for entry in catalog:
        key = entry['key']
        collection = bpy.data.collections.get(entry['collection'])
        if not check(collection is not None, 'structure', version + ' 组件集合存在', key=key):
            continue
        collection_to_key[collection.name] = key
        meshes = sorted((obj for obj in collection.all_objects if obj.type == 'MESH'), key=lambda obj: obj.name)
        check(bool(meshes), 'geometry', version + ' 组件非空', key=key)
        parts, points, mesh_rows = {}, [], []
        for index, obj in enumerate(meshes):
            check(not obj.modifiers and not obj.data.shape_keys, 'geometry',
                  version + ' 原始顶点即实际网格，无未求值修改器或形态键', key=key, object=obj.name)
            data = mesh_bytes(obj)
            parts.update({f'mesh_{index}/{name}': value for name, value in data.items()})
            transformed = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
            points.extend(transformed)
            obj.data.calc_loop_triangles()
            mesh_rows.append({
                'name': obj.name, 'vertices': len(obj.data.vertices), 'edges': len(obj.data.edges),
                'loops': len(obj.data.loops), 'polygons': len(obj.data.polygons),
                'triangles': len(obj.data.loop_triangles), 'matrix_world': matrix_rows(obj.matrix_world),
                'uv_layers': [layer.name for layer in obj.data.uv_layers],
                'material_roles': [slot.material.name if slot.material else None for slot in obj.material_slots],
            })
        if not check(bool(points), 'geometry', version + ' 组件具有可测顶点', key=key):
            continue
        lo = [min(point[axis] for point in points) for axis in range(3)]
        hi = [max(point[axis] for point in points) for axis in range(3)]
        transforms = {obj.name: {'type': obj.type, 'parent': obj.parent.name if obj.parent else None,
                                'matrix_world': matrix_rows(obj.matrix_world),
                                'matrix_basis': matrix_rows(obj.matrix_basis)}
                      for obj in collection.all_objects}
        geometry[key] = {
            'category': entry['category'], 'collection': collection.name,
            'bounds': [lo, hi], 'height_m': hi[2] - lo[2],
            'fingerprint': fingerprint(parts), 'meshes': mesh_rows,
            'definition_transforms': transforms, 'instance_offset': list(collection.instance_offset),
        }
        raw[key] = parts
        offset = Matrix.Translation(-collection.instance_offset)
        definitions[key] = [offset @ point for point in points]
    instances = {}
    for obj in scene.objects:
        if obj.instance_type != 'COLLECTION' or obj.instance_collection is None:
            continue
        key = collection_to_key.get(obj.instance_collection.name)
        if not check(key in definitions, 'structure', version + ' 实例引用已知组件', instance=obj.name):
            continue
        matrix = obj.matrix_world.copy()
        minz = min((matrix @ point).z for point in definitions[key])
        instances[obj.name] = {
            'key': key, 'category': geometry[key]['category'],
            'matrix_world': matrix_rows(matrix), 'matrix_basis': matrix_rows(obj.matrix_basis),
            'location': list(obj.location), 'scale': list(obj.scale),
            'rotation_mode': obj.rotation_mode, 'rotation_euler': list(obj.rotation_euler),
            'rotation_quaternion': list(obj.rotation_quaternion),
            'rotation_axis_angle': list(obj.rotation_axis_angle),
            'urban_role': obj.get('urban_role', ''), 'minz_m': minz,
        }
    floor_keys = {'street_intact', 'street_split', 'junction', 'plaza_tile', 'canal_segment', 'terrain_ramp'}
    ground_tiles = {name: row for name, row in instances.items() if row['key'] in floor_keys}
    cells = []
    for name, row in ground_tiles.items():
        x, y = row['matrix_world'][0][3], row['matrix_world'][1][3]
        cell = (round((x + 108) / 24), round((y + 108) / 24))
        check(abs(x - (-108 + cell[0] * 24)) < 0.001
              and abs(y - (-108 + cell[1] * 24)) < 0.001,
              'ground_grid', version + ' 地砖位于实际 24m 网格中心', instance=name)
        cells.append(cell)
    check(len(cells) == 100 and set(cells) == {(x, y) for x in range(10) for y in range(10)},
          'ground_grid', version + ' 10×10 地砖完整、无重复无缺格')
    counts = {
        'definitions': len(geometry), 'instances': len(instances),
        'architecture_definitions': sum(row['category'] == 'architecture' for row in geometry.values()),
        'horizontal_role_instances': sum(row['urban_role'] == 'horizontal_road_wreck' for row in instances.values()),
        'curve_instances': sum(row['key'] == 'viaduct_curve' for row in instances.values()),
        'tram_instances': sum(row['key'] == 'tram_wreck' for row in instances.values()),
        'ground_instances': len(ground_tiles),
        'ground_category_instances_including_bridges_and_stairs': sum(row['category'] == 'ground' for row in instances.values()),
        'instances_by_key': dict(sorted(Counter(row['key'] for row in instances.values()).items())),
    }
    for name, expected in [('definitions', 50), ('instances', 388), ('architecture_definitions', 20),
                           ('horizontal_role_instances', 3), ('curve_instances', 4),
                           ('tram_instances', 3), ('ground_instances', 100)]:
        check(counts[name] == expected, 'counts', version + ' ' + name,
              actual=counts[name], expected=expected)
    snap = {'source': str(path), 'counts': counts, 'geometry': geometry, 'instances': instances}
    result['snapshots'][version] = snap
    print('HEIGHT_SNAPSHOT', version, json.dumps(counts, ensure_ascii=False), flush=True)
    return snap, raw


def verify():
    check(bpy.app.background, 'execution', '使用独立后台 Blender')
    check(REPORT.parent.is_dir(), 'execution', '指定报告父目录存在')
    catalogs, plans = {}, {}
    sources = set()
    for version in VERSIONS:
        directory = SOURCE / version
        for name in ('component_catalog.json', 'component_plan.json'):
            sources.add(directory / name)
        sources.add(directory / f'sunken_city_{version}.blend')
        catalogs[version] = json.loads((directory / 'component_catalog.json').read_text(encoding='utf-8'))['components']
        plans[version] = json.loads((directory / 'component_plan.json').read_text(encoding='utf-8'))
        sources.update(ROOT / entry['component_blend'] for entry in catalogs[version])
    lock = json.loads(LOCK.read_text(encoding='utf-8'))
    sources.update(ROOT / name for name in lock['protected_sources'])
    sources.add(LOCK)
    for path in sorted(sources):
        if check(path.is_file(), 'source_hash', '源文件存在', path=str(path)):
            result['source_hashes'][str(path)] = {'before': sha(path)}
    for name, expected in lock['protected_sources'].items():
        row = result['source_hashes'].get(str(ROOT / name), {})
        check(row.get('before') == expected, 'protected_source_baseline', 'v004 冻结保护源散列一致', path=name)
    check(ARCHIVE.is_file(), 'archive', 'v003 runtime archive 存在', path=str(ARCHIVE))
    if ARCHIVE.is_file():
        result['archive'] = {'path': str(ARCHIVE), 'before_sha256': sha(ARCHIVE)}
        with zipfile.ZipFile(ARCHIVE, 'r') as archive:
            bad = archive.testzip()
            names = archive.namelist()
            result['archive'].update(testzip_bad_member=bad, members=len(names))
            check(bad is None, 'archive', '只读 testzip CRC 检查通过', bad_member=bad)
            check(bool(names), 'archive', 'runtime archive 非空')
            missing = sorted(set(lock.get('runtime_before', {})) - set(names))
            check(not missing, 'archive', '封存包含冻结 runtime 全部成员', missing=missing)
        check(result['archive']['before_sha256'] == lock['archive_sha256'], 'archive', 'archive 冻结散列一致')
    old, old_raw = snapshot('v003', catalogs['v003'])
    new, new_raw = snapshot('v004', catalogs['v004'])
    if not old or not new:
        return
    check(set(old['geometry']) == set(new['geometry']), 'structure', '50 个定义 key 完整一致')
    arch = {key for key, row in old['geometry'].items() if row['category'] == 'architecture'}
    old_max = max(old['geometry'][key]['height_m'] for key in arch)
    cap = old_max / 4
    check(abs(old_max - 59.6591835) < 0.000001, 'height', '旧实际建筑最高值', actual=old_max, expected=59.6591835)
    check(abs(cap - 14.9147959) < 0.000001, 'height', '实际最高值除四得到统一 cap', actual=cap, expected=14.9147959)
    contract = plans['v004']['height_cap_contract']
    check(abs(contract['source_max_height_m'] - old_max) < 0.000001
          and abs(contract['height_cap_m'] - cap) < 0.000001,
          'height', '计划高度契约与独立实际测量一致')
    short = {key for key in arch if old['geometry'][key]['height_m'] <= cap}
    changed = arch - short
    check(short == {'workshop_shell', 'low_foundation'}, 'height', '低于 cap 的建筑恰为指定两件', actual=sorted(short))
    check(set(plans['v004']['scope_lock']['changed_keys']) == changed,
          'height', '允许改变的建筑按旧实际高度独立推导')
    preserved = []
    for key in sorted(set(old['geometry']) & set(new['geometry'])):
        before, after = old['geometry'][key], new['geometry'][key]
        check(before['category'] == after['category'], 'structure', '组件分类不变', key=key)
        check(before['definition_transforms'] == after['definition_transforms']
              and before['instance_offset'] == after['instance_offset'],
              'definition_transform', '组件定义变换与集合 offset 严格不变', key=key)
        if key in arch:
            check(math.isfinite(after['height_m']) and after['height_m'] <= cap,
                  'height', 'v004 实际建筑高度不超过 cap', key=key, actual=after['height_m'], cap=cap)
        equal = old_raw[key] == new_raw[key]
        if key not in changed:
            check(equal, 'geometry_bytes', '受保护组件 co/topology/UV/matroles 原始字节严格相同', key=key,
                  changed_parts=[part for part in set(old_raw[key]) | set(new_raw[key])
                                 if old_raw[key].get(part) != new_raw[key].get(part)])
            if equal:
                preserved.append(key)
        else:
            check(not equal, 'geometry_bytes', '超限建筑实际几何已修改', key=key)
    check(set(old['instances']) == set(new['instances']), 'structure', '388 个实际实例名称完整一致')
    comparisons = []
    for name in sorted(set(old['instances']) & set(new['instances'])):
        before, after = old['instances'][name], new['instances'][name]
        key = before['key']
        check(key == after['key'], 'instance_transform', '实例组件引用不变', instance=name)
        for field in ('scale', 'rotation_mode', 'rotation_euler', 'rotation_quaternion', 'rotation_axis_angle'):
            check(before[field] == after[field], 'instance_transform', '实例 ' + field + ' 严格不变', instance=name)
        check(before['location'][:2] == after['location'][:2], 'instance_transform', '实例 XY 严格不变', instance=name)
        check(before['urban_role'] == after['urban_role'], 'roles', '实例角色严格保留', instance=name)
        if key in changed:
            a, b = before['matrix_world'], after['matrix_world']
            check(all(a[i][j] == b[i][j] for i in range(4) for j in range(4) if (i, j) != (2, 3)),
                  'instance_transform', '改楼完整世界矩阵仅 z 平移项可变', instance=name)
        else:
            check(before['matrix_world'] == after['matrix_world'] and before['matrix_basis'] == after['matrix_basis'],
                  'instance_transform', '其余实例完整矩阵严格不变', instance=name)
        error = abs(after['minz_m'] - before['minz_m'])
        check(error < TOLERANCE, 'ground_contact', '实际变换所有顶点后的 minz 保留旧接地高程',
              instance=name, key=key, old_minz_m=before['minz_m'], new_minz_m=after['minz_m'], error_m=error)
        comparisons.append({'instance': name, 'key': key, 'changed_architecture': key in changed,
                            'old_minz_m': before['minz_m'], 'new_minz_m': after['minz_m'],
                            'error_m': error, 'z_translation_delta_m': after['matrix_world'][2][3] - before['matrix_world'][2][3]})
    horizontal = [name for name, row in old['instances'].items() if row['urban_role'] == 'horizontal_road_wreck']
    for name in horizontal:
        before, after = old['instances'][name], new['instances'].get(name)
        check(after is not None and after['urban_role'] == 'horizontal_road_wreck'
              and after['rotation_euler'] == before['rotation_euler']
              and max(abs(value) for value in before['rotation_euler'][:2]) > math.radians(45),
              'roles', '横躺角色与实际横倒朝向保留', instance=name)
    result['comparison'] = {
        'architecture_keys': sorted(arch), 'old_max_geometry_height_m': old_max, 'height_cap_m': cap,
        'new_max_geometry_height_m': max(new['geometry'][key]['height_m'] for key in arch),
        'below_cap_keys': sorted(short), 'changed_architecture_keys': sorted(changed),
        'byte_identical_protected_keys': preserved, 'horizontal_role_instances': horizontal,
        'checked_instances': len(comparisons),
        'checked_changed_architecture_instances': sum(row['changed_architecture'] for row in comparisons),
        'max_minz_error_m': max(row['error_m'] for row in comparisons),
        'max_changed_architecture_minz_error_m': max(row['error_m'] for row in comparisons if row['changed_architecture']),
        'instance_ground_contact': comparisons,
    }


def main():
    try:
        verify()
    except Exception:
        check(False, 'execution', '独立验收异常', traceback=traceback.format_exc())
    finally:
        for name, row in result['source_hashes'].items():
            try:
                row['after'] = sha(Path(name))
                row['unchanged'] = row['before'] == row['after']
                check(row['unchanged'], 'source_hash', '验收前后源 SHA256 相等', path=name)
            except Exception:
                check(False, 'source_hash', '无法重读源散列', path=name, traceback=traceback.format_exc())
        if 'archive' in result:
            try:
                result['archive']['after_sha256'] = sha(ARCHIVE)
                check(result['archive']['before_sha256'] == result['archive']['after_sha256'],
                      'archive', '只读检查前后 archive SHA256 相等')
            except Exception:
                check(False, 'archive', '无法重读 archive 散列', traceback=traceback.format_exc())
        result['passed'] = not result['errors']
        result['exit_code'] = 0 if result['passed'] else 1
        result['finished_at'] = datetime.now(timezone.utc).isoformat()
        REPORT.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        print('HEIGHT_INDEPENDENT_VERIFICATION', json.dumps({
            'passed': result['passed'], 'checks': result['checks'], 'errors': result['errors'],
            'exit_code': result['exit_code'], 'report': str(REPORT),
        }, ensure_ascii=False), flush=True)
    return result['exit_code']


if __name__ == '__main__':
    sys.exit(main())
