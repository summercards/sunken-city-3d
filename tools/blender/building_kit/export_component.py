"""Kit transfer contract: PaletteUV is the sole UV0; material roles survive export.

The GLB contains geometry and minimal named material slots. Godot binds the four
shared runtime materials, so this does not embed another palette image copy.
"""
import bpy
import json
import struct
import os
from pathlib import Path

ROLES = ['Matte', 'Metal', 'Gloss', 'Emission']


def normalize_palette_uv(collection):
    for obj in collection.objects:
        if obj.type != 'MESH':
            continue
        assert obj.data.uv_layers.get('PaletteUV'), obj.name
        for layer in list(obj.data.uv_layers):
            if layer.name != 'PaletteUV':
                obj.data.uv_layers.remove(layer)
        obj.data.uv_layers.active_index = 0
        obj.data.uv_layers['PaletteUV'].active_render = True
        assert len(obj.data.uv_layers) == 1


def export_component(collection, target):
    normalize_palette_uv(collection)
    previous_scene = bpy.context.window.scene
    transfer_scene = bpy.data.scenes.new('SEA_TRANSFER_' + collection.name)
    transfer_scene.collection.children.link(collection)
    bpy.context.window.scene = transfer_scene
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action='DESELECT')
    roles = {}
    for obj in collection.objects:
        if obj.type != 'MESH':
            continue
        obj.select_set(True)
        assert len(obj.data.materials) == 1, obj.name
        name = obj.data.materials[0].name
        role = next(role for role in ROLES if name == 'SEA_' + role)
        roles[obj.data.name] = role
    target = Path(target)
    target.parent.mkdir(parents=True, exist_ok=True)
    workspace = Path(os.environ.get('SEA_WORK_ROOT', Path(__file__).resolve().parents[4] / 'sea-work')) / 'building_kit_v001' / 'transfer'
    workspace.mkdir(parents=True, exist_ok=True)
    transfer_file = workspace / (target.stem + '.glb')
    bpy.ops.export_scene.gltf(filepath=str(transfer_file), export_format='GLB',
                             use_selection=True, use_active_scene=True,
                             export_materials='PLACEHOLDER', export_extras=True)
    bpy.context.window.scene = previous_scene
    bpy.data.scenes.remove(transfer_scene)
    raw = transfer_file.read_bytes()
    size = struct.unpack_from('<I', raw, 12)[0]
    doc = json.loads(raw[20:20 + size])
    blob = raw[28 + size:]
    # PLACEHOLDER intentionally strips glTF material records. Reattach named
    # semantic slots rather than guess a role from missing runtime materials.
    doc['materials'] = [{'name': 'SEA_' + role,
                         'pbrMetallicRoughness': {'metallicFactor': .6 if role == 'Metal' else 0,
                                                  'roughnessFactor': .8 if role == 'Matte' else .28}}
                        for role in ROLES]
    for mesh in doc['meshes']:
        assert mesh['name'] in roles, mesh['name']
        role = roles[mesh['name']]
        for primitive in mesh['primitives']:
            assert 'TEXCOORD_0' in primitive['attributes']
            assert 'TEXCOORD_1' not in primitive['attributes']
            primitive['material'] = ROLES.index(role)
    doc.setdefault('extras', {})['sea_palette_transfer'] = {
        'uv0': 'PaletteUV', 'palette': 'sea_cozy_8x8_512', 'roles': ROLES,
        'runtime_material_binding': 'KitVisual -> assets/materials/building_kit'}
    js = json.dumps(doc, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
    js += b' ' * (-len(js) % 4)
    blob += b'\0' * (-len(blob) % 4)
    result = struct.pack('<III', 0x46546C67, 2, 28 + len(js) + len(blob))
    result += struct.pack('<II', len(js), 0x4E4F534A) + js
    result += struct.pack('<II', len(blob), 0x004E4942) + blob
    output = target.with_suffix('.glb.tmp')
    output.write_bytes(result)
    os.replace(output, target)
