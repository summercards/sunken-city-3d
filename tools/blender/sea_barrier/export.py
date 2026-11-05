"""把 sea_barrier 的 18 个独立包导出成 Godot 可用的 GLB。

只做三件事：按材质角色合并成一个 surface、另存优化源、导出无内嵌贴图的 GLB。
不写任何 .tscn，不碰正式场景 —— 那一步在 package.py，便于分开审阅差异。

用法：
  blender -b --python tools/blender/sea_barrier/export.py
"""
import hashlib
import json
import os
import struct
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[3]
D = ROOT / 'art_source/scenes/sea_barrier/v001'
OUT = D / 'export/v001'
RUNTIME = ROOT / 'godot/assets/models/barrier'
PLAN = json.loads((D / 'component_plan.json').read_text(encoding='utf8'))
CATALOG = json.loads((D / 'component_catalog.json').read_text(encoding='utf8'))['components']
OUT.mkdir(parents=True, exist_ok=True)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def triangles(objects):
    for obj in objects:
        obj.data.calc_loop_triangles()
    return sum(len(obj.data.loop_triangles) for obj in objects)


def limits(objects):
    coords = [v.co for obj in objects for v in obj.data.vertices]
    return [[round(f(v[i] for v in coords), 5) for i in range(3)] for f in (min, max)]


def glb_document(path):
    data = path.read_bytes()
    size = struct.unpack_from('<I', data, 12)[0]
    return json.loads(data[20:20 + size])


protected = [D / 'sea_barrier.blend', ROOT / PLAN['palette']]
initial = {p: sha(p) for p in protected}
records = []
for item in CATALOG:
    key = item['key']
    original = D / 'component_packages' / key / f'{key}.blend'
    manifest = json.loads((original.parent / 'asset_manifest.json').read_text(encoding='utf8'))
    digest = sha(original)
    # 独立包哈希必须与登记时一致：建模脚本重跑过就要重新登记，不能拿旧行顶替。
    assert digest == manifest['source_sha256'], (key, '独立包在登记后被改过，先重跑 register.py')

    bpy.ops.wm.open_mainfile(filepath=str(original))
    bpy.context.preferences.filepaths.save_version = 0
    collection = bpy.data.collections[item['collection']]
    # 独立包是纯数据块（libraries.write 不带场景），打开时 collection 处于孤儿状态、
    # 不进视图层，select_set 会直接报错。先挂进当前场景，几何才能被导出。
    if collection.name not in [c.name for c in bpy.context.scene.collection.children]:
        bpy.context.scene.collection.children.link(collection)
    objects = [o for o in collection.all_objects if o.type == 'MESH']
    before = triangles(objects)
    bounds_before = limits(objects)

    # 直接导出 GLB，不合并几何：合并会把「哪块是墙、哪块是树」的层次压平，
    # 白盒下一轮还要按对象加细节。节点数不多（单件最多 105 个），
    # 同一材质在 Godot 里会被合批，不值得为几个 draw call 丢掉可编辑性。
    derived = OUT / f'{key}_optimized.blend'
    bpy.ops.wm.save_as_mainfile(filepath=str(derived), compress=True)
    bpy.ops.wm.open_mainfile(filepath=str(derived))
    assert triangles(bpy.data.collections[item['collection']].all_objects) == before, key
    assert limits(bpy.data.collections[item['collection']].all_objects) == bounds_before, key

    target = RUNTIME / key / f'{key}.glb'
    target.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(target), export_format='GLB', export_image_format='NONE',
        export_yup=True, export_animations=False, export_attributes=False,
        export_texcoords=True, export_normals=True, export_tangents=False)
    document = glb_document(target)
    assert not document.get('images') and not document.get('textures'), key + ': 不许内嵌贴图'
    exported = sum(document['accessors'][p['indices']]['count'] // 3
                   for mesh in document['meshes'] for p in mesh['primitives']
                   if 'indices' in p)
    assert exported == before, (key, exported, before)
    assert sha(original) == digest, key + ': 导出过程改动了源'

    records.append({
        'key': key,
        'asset_id': item['asset_id'],
        'source': original.relative_to(ROOT).as_posix(),
        'source_sha256': digest,
        'optimized_source': derived.relative_to(ROOT).as_posix(),
        'optimized_sha256': sha(derived),
        'glb': target.relative_to(ROOT).as_posix(),
        'glb_sha256': sha(target),
        'glb_bytes': target.stat().st_size,
        'triangles': exported,
        'mesh_objects': len(objects),
        'mesh_nodes': len(document['meshes']),
        'bounds': bounds_before,
        'embedded_images': 0,
    })
    print('BARRIER_EXPORT', key, exported, len(document['meshes']), flush=True)

assert all(sha(p) == d for p, d in initial.items()), '受保护源文件被改动'
(OUT / 'export_manifest.json').write_text(
    json.dumps({'suite': 'sea_barrier', 'version': 'v001',
                'protected_sources': {p.relative_to(ROOT).as_posix(): h for p, h in initial.items()},
                'components': records}, ensure_ascii=False, indent=2) + '\n', encoding='utf8')
print('EXPORTED', len(records), 'components')
