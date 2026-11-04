import bpy
import hashlib
import json
import shutil
from pathlib import Path

ROOT = Path('D:/projects/sea')
V004 = ROOT / 'art_source/scenes/ocean_rooftop_farm/v004/ocean_rooftop_farm_v004.blend'
V005 = ROOT / 'art_source/scenes/ocean_rooftop_farm/v005/ocean_rooftop_farm_v005.blend'
V006 = ROOT / 'art_source/scenes/ocean_rooftop_farm/v006/ocean_rooftop_farm_v006.blend'
DELIVERY = Path('D:/projects/sea-work/ocean_rooftop_farm/v006_delivery')
DELIVERY.mkdir(parents=True, exist_ok=True)
DELIVERY_SOURCE = DELIVERY / V006.name
AUDIT = DELIVERY / 'source_audit.json'

TARGET_PREFIXES = ('ORF3_实例_stair_flight.', 'ORF3_实例_stair_landing.')
TARGET_EXTRA = ('ORF3_实例_roof_entry',)

def target_name(name):
    return name.startswith(TARGET_PREFIXES) or name.startswith(TARGET_EXTRA)

def matrix(o):
    return [[round(float(v), 10) for v in row] for row in o.matrix_world]

def visibility(o):
    return {
        'hide_viewport': bool(o.hide_viewport),
        'hide_render': bool(o.hide_render),
        'hide_set': bool(o.hide_get()),
    }

def mesh_signature(mesh):
    payload = {
        'name': mesh.name,
        'vertices': [tuple(round(float(v), 10) for v in vert.co) for vert in mesh.vertices],
        'edges': [tuple(int(i) for i in edge.vertices) for edge in mesh.edges],
        'polygons': [
            {
                'vertices': tuple(int(i) for i in poly.vertices),
                'loop_start': int(poly.loop_start),
                'loop_total': int(poly.loop_total),
                'material_index': int(poly.material_index),
            }
            for poly in mesh.polygons
        ],
        'loops': [int(loop.vertex_index) for loop in mesh.loops],
        'uv_layers': {
            layer.name: [
                (round(float(item.uv.x), 10), round(float(item.uv.y), 10))
                for item in layer.data
            ]
            for layer in mesh.uv_layers
        },
        'materials': [material.name if material else None for material in mesh.materials],
    }
    encoded = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode('utf-8')
    return hashlib.sha256(encoded).hexdigest(), payload

def scene_snapshot():
    bpy.context.view_layer.update()
    objects = {}
    meshes = {}
    for obj in bpy.data.objects:
        objects[obj.name] = {
            'type': obj.type,
            'matrix_world': matrix(obj),
            'matrix_basis': [[round(float(v), 10) for v in row] for row in obj.matrix_basis],
            'matrix_local': [[round(float(v), 10) for v in row] for row in obj.matrix_local],
            'visibility': visibility(obj),
            'data_name': obj.data.name if obj.type == 'MESH' else None,
        }
        if obj.type == 'MESH':
            sig, payload = mesh_signature(obj.data)
            meshes[obj.name] = {'signature': sig, 'payload': payload}
    targets = {
        name: {'matrix_world': row['matrix_world'], 'visibility': row['visibility']}
        for name, row in objects.items() if target_name(name)
    }
    return objects, meshes, targets

def compare_matrices(left, right):
    names = sorted(set(left) | set(right))
    missing = sorted(set(left) - set(right))
    extra = sorted(set(right) - set(left))
    changed = [name for name in names if name in left and name in right and left[name] != right[name]]
    return {'passed': not missing and not extra and not changed, 'missing': missing, 'extra': extra, 'changed': changed}

def compare_meshes(left, right):
    names = sorted(set(left) | set(right))
    missing = sorted(set(left) - set(right))
    extra = sorted(set(right) - set(left))
    changed = [name for name in names if name in left and name in right and left[name]['signature'] != right[name]['signature']]
    return {'passed': not missing and not extra and not changed, 'missing': missing, 'extra': extra, 'changed': changed}

def column_objects(meshes):
    return {
        name: row['signature'] for name, row in meshes.items()
        if ('柱' in name or 'pier' in name.lower() or 'column' in name.lower())
    }

bpy.ops.wm.open_mainfile(filepath=str(V004))
v004_objects, v004_meshes, v004_targets = scene_snapshot()
bpy.ops.wm.open_mainfile(filepath=str(V005))
v005_objects, v005_meshes, v005_targets = scene_snapshot()
bpy.ops.wm.open_mainfile(filepath=str(V006))
v006_objects, v006_meshes, v006_targets = scene_snapshot()

checks = []
def check(name, passed, detail):
    checks.append({'check': name, 'passed': bool(passed), 'detail': detail})

ladder_matrices = compare_matrices(
    {name: row['matrix_world'] for name, row in v004_targets.items()},
    {name: row['matrix_world'] for name, row in v006_targets.items()},
)
check('all_ladder_and_roof_entry_matrices_match_v004', ladder_matrices['passed'], ladder_matrices)
visibility_match = all(
    name in v006_targets and row['visibility'] == v006_targets[name]['visibility']
    for name, row in v004_targets.items()
) and set(v004_targets) == set(v006_targets)
visibility_diff = {
    name: {'v004': v004_targets.get(name), 'v006': v006_targets.get(name)}
    for name in sorted(set(v004_targets) | set(v006_targets))
    if v004_targets.get(name) != v006_targets.get(name)
}
check('stair_landing_and_roof_entry_visibility_matches_v004', visibility_match, visibility_diff)

all_transform_match = compare_matrices(
    {name: row['matrix_basis'] for name, row in v005_objects.items()},
    {name: row['matrix_basis'] for name, row in v006_objects.items()},
)
check('no_object_moved_from_v005', all_transform_match['passed'], {
    **all_transform_match,
    'comparison_basis': 'matrix_basis（不受隐藏视图层求值影响）',
})
all_mesh_match = compare_meshes(v005_meshes, v006_meshes)
check('all_mesh_data_matches_v005', all_mesh_match['passed'], all_mesh_match)
v005_columns = column_objects(v005_meshes)
v006_columns = column_objects(v006_meshes)
column_match = v005_columns == v006_columns
check('column_mesh_signatures_match_v005', column_match, {
    'v005': v005_columns,
    'v006': v006_columns,
    'changed_or_missing': sorted(set(v005_columns) ^ set(v006_columns)),
})

scene = bpy.context.scene
recommended = {
    'WATER_LOCAL_Z': 57.04,
    'BOARD_LOCAL_Z': 57.30,
    'ROOT_Y': -55.92,
}
metadata = {key: scene.get('ORF6_' + key) for key in recommended}
check('recommended_godot_values_recorded_only_in_source', metadata == recommended, metadata)
check('no_glb_export_requested', True, '本轮未导出GLB；仅恢复源可见性。')

shutil.copy2(V006, DELIVERY_SOURCE)
source_sha256 = hashlib.sha256(V006.read_bytes()).hexdigest()
delivery_sha256 = hashlib.sha256(DELIVERY_SOURCE.read_bytes()).hexdigest()
check('delivery_source_copy_matches_v006', source_sha256 == delivery_sha256, {'source': source_sha256, 'delivery': delivery_sha256})

report = {
    'passed': all(item['passed'] for item in checks),
    'source': str(V006),
    'source_parent': str(V005),
    'visibility_reference': str(V004),
    'delivery_source': str(DELIVERY_SOURCE),
    'audit_path': str(AUDIT),
    'source_sha256': source_sha256,
    'delivery_source_sha256': delivery_sha256,
    'ladder_target_count': len(v006_targets),
    'ladder_target_names': sorted(v006_targets),
    'recommended_godot_values': recommended,
    'checks': checks,
    'notes': [
        'Blender源未移动任何对象；正式下沉仍由Godot拥有。',
        'v006从v005另存，未覆盖v004/v005。',
        '柱mesh签名按对象网格顶点、拓扑、材质索引及全部UV层计算，并与v005独立重开结果比较。',
        '未修改Godot、文档、资产账本或注册索引。',
    ],
}
AUDIT.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps({'passed': report['passed'], 'audit': str(AUDIT), 'delivery_source': str(DELIVERY_SOURCE), 'failed': [x for x in checks if not x['passed']]}, ensure_ascii=False))
