"""把 bedroom/v001 的 13 个独立包导出成 Godot 可用的 GLB。

只做三件事：另存优化副本、导出无内嵌贴图的 GLB、记录三角面与哈希。
不写任何 .tscn，不碰正式场景 —— 那一步在 package.py，便于分开审阅差异。

用法：
  blender -b --python tools/blender/bedroom/export.py
"""
import hashlib
import json
import os
import struct
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parents[3]
D = ROOT / 'art_source/rooms/bedroom/v001'
OUT = D / 'export/v001'
RUNTIME = ROOT / 'godot/assets/models/rooms/bedroom'
CATALOG = json.loads((D / 'component_catalog.json').read_text(encoding='utf8'))['components']
OUT.mkdir(parents=True, exist_ok=True)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def glb_document(path):
    data = Path(path).read_bytes()
    magic, _version, _length = struct.unpack('<III', data[:12])
    assert magic == 0x46546C67, 'not a GLB'
    offset, document = 12, None
    while offset < len(data):
        size, kind = struct.unpack('<II', data[offset:offset + 8])
        chunk = data[offset + 8:offset + 8 + size]
        if kind == 0x4E4F534A:
            document = json.loads(chunk.decode('utf-8'))
        offset += 8 + size + (-size % 4)
    return document


records = []
for item in CATALOG:
    key = item['key']
    source = D / 'component_packages' / key / (key + '.blend')
    assert source.is_file(), source
    digest = sha(source)
    bpy.ops.wm.open_mainfile(filepath=str(source))
    # 独立包只写了「集合 + 依赖」，包里没有场景链接；先把它挂回场景再导出，
    # 否则 open_mainfile 得到的是空场景，导出会静默少件。
    packages = [c for c in bpy.data.collections if c.users >= 0]
    assert packages, key + ': 包里没有集合'
    coll = packages[0]
    if coll.name not in bpy.context.scene.collection.children:
        bpy.context.scene.collection.children.link(coll)
    meshes = [o for o in coll.all_objects if o.type == 'MESH']
    assert meshes, key + ': 包内没有网格'
    before = 0
    for obj in meshes:
        obj.data.calc_loop_triangles()
        before += len(obj.data.loop_triangles)
    target = RUNTIME / key / (key + '.glb')
    target.parent.mkdir(parents=True, exist_ok=True)
    for obj in bpy.data.objects:
        obj.select_set(obj in meshes)
    bpy.ops.export_scene.gltf(
        filepath=str(target), export_format='GLB', export_image_format='NONE',
        use_selection=True, export_yup=True, export_animations=False,
        export_attributes=False, export_texcoords=True, export_normals=True,
        export_tangents=False)
    document = glb_document(target)
    assert not document.get('images') and not document.get('textures'), key + ': 不许内嵌贴图'
    exported = sum(document['accessors'][p['indices']]['count'] // 3
                   for mesh in document['meshes'] for p in mesh['primitives']
                   if 'indices' in p)
    assert exported == before, (key, exported, before)
    assert sha(source) == digest, key + ': 导出过程改动了源'
    materials = sorted({m for mesh in document['meshes'] for m in
                        [document['materials'][p['material']]['name'] for p in mesh['primitives']
                         if 'material' in p]})
    records.append({
        'key': key, 'asset_id': item['asset_id'], 'name': item['name'],
        'source': source.relative_to(ROOT).as_posix(), 'source_sha256': digest,
        'glb': target.relative_to(ROOT).as_posix(), 'glb_sha256': sha(target),
        'glb_bytes': target.stat().st_size,
        'triangles': exported, 'materials': materials,
    })

index = {'schema': 'sea.bedroom_export', 'version': 'v001',
         'glb_dir': RUNTIME.relative_to(ROOT).as_posix(),
         'triangles': sum(r['triangles'] for r in records), 'components': records}
(OUT / 'export_index.json').write_text(
    json.dumps(index, ensure_ascii=False, indent=2) + '\n', encoding='utf8')
print('[bedroom-export] %d glb, %d triangles, %d bytes' %
      (len(records), index['triangles'], sum(r['glb_bytes'] for r in records)))
