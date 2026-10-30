"""Repair this kit's PaletteUV channel/material transfer, preserving authored meshes."""
import bpy
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from export_component import export_component, normalize_palette_uv

ROOT = HERE.parents[2]
SOURCE = ROOT / 'art_source/scenes/ocean_building_kit/v001'
WORK = Path(os.environ.get('SEA_WORK_ROOT', ROOT.parent / 'sea-work')) / 'building_kit_v001'
MOTHER = SOURCE / 'building_kit.blend'
bpy.context.preferences.filepaths.save_version = 0
backup = WORK / 'before_uv_transfer_fix'
backup.mkdir(parents=True, exist_ok=True)
if not (backup / MOTHER.name).exists():
    shutil.copy2(MOTHER, backup / MOTHER.name)
bpy.ops.wm.open_mainfile(filepath=str(MOTHER))
scene = bpy.context.scene
catalog = json.loads((SOURCE / 'catalog.json').read_text(encoding='utf-8'))
report = []
for entry in catalog['components']:
    col = bpy.data.collections[entry['collection']]
    normalize_palette_uv(col)
    linked = col.name in scene.collection.children
    if not linked:
        scene.collection.children.link(col)
    bpy.context.view_layer.update()
    target = ROOT / 'godot/assets/models/building_kit' / entry['id'] / (entry['id'] + '.glb')
    before = hashlib.sha256(target.read_bytes()).hexdigest()
    export_component(col, target)
    raw = target.read_bytes()
    size = struct.unpack_from('<I', raw, 12)[0]
    doc = json.loads(raw[20:20 + size]); blob = raw[28 + size:]
    source_tiles = {}
    for obj in col.objects:
        if obj.type != 'MESH':
            continue
        uv = obj.data.uv_layers['PaletteUV']
        tiles = set()
        for face in obj.data.polygons:
            points = [uv.data[i].uv for i in face.loop_indices]
            area = abs(sum(points[i].x * points[(i + 1) % len(points)].y -
                           points[(i + 1) % len(points)].x * points[i].y
                           for i in range(len(points)))) * .5
            assert area > .00001, (obj.name, face.index)
            assert len({(int(p.x * 8), int(p.y * 8)) for p in points}) == 1
            tiles.update((int(p.x * 8), int((1 - p.y) * 8)) for p in points)
        source_tiles[obj.data.name] = tiles
    role_counts = {}
    for mesh in doc['meshes']:
        for primitive in mesh['primitives']:
            acc = doc['accessors'][primitive['attributes']['TEXCOORD_0']]
            view = doc['bufferViews'][acc['bufferView']]
            start = view.get('byteOffset', 0) + acc.get('byteOffset', 0)
            uv = [struct.unpack_from('<2f', blob, start + i * view.get('byteStride', 8))
                  for i in range(acc['count'])]
            assert {(int(p[0] * 8), int(p[1] * 8)) for p in uv} == source_tiles[mesh['name']]
            role = doc['materials'][primitive['material']]['name']
            role_counts[role] = role_counts.get(role, 0) + 1
    report.append({'id': entry['id'], 'meshes': len(doc['meshes']), 'roles': role_counts,
                   'uv0_palette_only': True, 'source_tiles_equal_export': True,
                   'before_glb_sha256': before, 'glb_sha256': hashlib.sha256(raw).hexdigest()})
    if not linked:
        scene.collection.children.unlink(col)
scene['kit_palette_uv0_transfer_v1'] = True
bpy.ops.wm.save_as_mainfile(filepath=str(MOTHER), compress=True)
for entry in catalog['components']:
    col = bpy.data.collections[entry['collection']]
    package = bpy.data.scenes.new('独立组件_' + entry['name'])
    package.collection.children.link(col); package.world = scene.world
    path = SOURCE / 'component_packages' / entry['id'] / (entry['id'] + '.blend')
    bpy.data.libraries.write(str(path), {package}, fake_user=True, compress=True)
    bpy.data.scenes.remove(package)
bpy.ops.wm.open_mainfile(filepath=str(MOTHER))
for entry in catalog['components']:
    col = bpy.data.collections[entry['collection']]
    assert all(len(o.data.uv_layers) == 1 and o.data.uv_layers[0].name == 'PaletteUV'
               for o in col.objects if o.type == 'MESH')
(WORK / 'uv_transfer_report.json').write_text(json.dumps({'status': 'pass', 'components': report},
                                                       ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print('KIT_PALETTE_UV0_ROLE_TRANSFER_PASS', len(report), flush=True)
