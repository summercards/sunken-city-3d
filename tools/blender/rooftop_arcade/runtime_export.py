"""Build an independent, render-equivalent runtime derivative; never save the open source.

Blender --background --disable-autoexec --python-exit-code 1 --python runtime_export.py -- prepare|export|before|after
"""
import hashlib
import json
import os
from pathlib import Path
import struct
import sys
from collections import defaultdict

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import finish as rac

DEST = rac.EXPORT / 'rooftop_arcade_runtime_optimized_v001.blend'
WORK = rac.work_dir() / 'runtime'
RECORD = rac.EXPORT / 'runtime_export_manifest.json'


def sources():
    return [rac.SOURCE, rac.PALETTE, *sorted((rac.FOLDER / 'components').glob('*.blend'))]


def snapshot():
    return [rac.file_record(p) for p in sources()]


def role_payload(collection, graph):
    buffers = defaultdict(lambda: [[], [], [], [], []])
    scanned = 0
    skipped = 0
    for obj in sorted(collection.objects, key=lambda node: node.name):
        ev = obj.evaluated_get(graph)
        mesh = ev.to_mesh()
        try:
            mesh.calc_loop_triangles()
            assert mesh.uv_layers.active.name == 'PaletteUV', obj.name
            uv = mesh.uv_layers.active.data
            for role in set(mesh.materials):
                item = buffers[role.name]
                offset = len(item[0])
                local = {}
                faces = set()
                for tri in mesh.loop_triangles:
                    if mesh.materials[tri.material_index] != role:
                        continue
                    scanned += 1
                    indices = tuple(tri.vertices)
                    loops = tuple(tri.loops)
                    coords = [tuple(mesh.vertices[k].co) for k in indices]
                    normal = [tuple(mesh.corner_normals[k].vector) for k in loops]
                    palette = [tuple(uv[k].uv) for k in loops]
                    key = tuple(sorted(zip(coords, normal, palette)))
                    if tri.area == 0 or key in faces:
                        skipped += 1
                        continue
                    faces.add(key)
                    face = []
                    for ix, co in zip(indices, coords):
                        if ix not in local:
                            local[ix] = offset + len(local)
                            item[0].append(co)
                        face.append(local[ix])
                    item[1].append(face)
                    item[2].extend(normal)
                    item[3].extend(palette)
                    item[4].append(key)
        finally:
            ev.to_mesh_clear()
    return buffers, scanned, skipped


def fingerprint(buffers):
    # Custom split normals are internally quantized by Blender; vertices and UVs remain exact.
    h = hashlib.sha256()
    for role, (_, _, _, _, keys) in sorted(buffers.items()):
        h.update(role.encode())
        for tri in sorted(tuple(sorted((co, uv) for co, _, uv in key)) for key in keys):
            for co, uv in tri:
                h.update(struct.pack('<5f', *co, *uv))
    return h.hexdigest()


def prepare():
    before = snapshot()
    data, components, images = rac.inspect_source(rac.read_json(rac.PLAN), rac.SOURCE)
    rac.checks_pass(data['errors'])
    assert not bpy.data.libraries, 'Unexpected externally linked Blender library'
    report = []
    with rac.active_scene(bpy.data.scenes[rac.MASTER]):
        for key, coll in sorted(components.items()):
            old = list(coll.objects)
            buffers, scanned, removed = role_payload(coll, bpy.context.evaluated_depsgraph_get())
            for role, (verts, faces, normals, uvs, _) in sorted(buffers.items()):
                if not faces:
                    continue
                mesh = bpy.data.meshes.new(f'{key}_{role}')
                mesh.from_pydata(verts, [], faces)
                mesh.materials.append(bpy.data.materials[role])
                mesh.update()
                mesh.polygons.foreach_set('use_smooth', [True] * len(faces))
                layer = mesh.uv_layers.new(name='PaletteUV')
                layer.active_render = True
                layer.uv.foreach_set('vector', [coord for uv in uvs for coord in uv])
                mesh.normals_split_custom_set(normals)
                node = bpy.data.objects.new(mesh.name, mesh)
                coll.objects.link(node)
            for node in old:
                bpy.data.objects.remove(node, do_unlink=True)
            report.append({'asset_id': coll.name, 'asset_key': key, 'version': rac.VERSION,
                           'objects_before': len(old), 'objects_after': len(coll.objects),
                           'triangles_before': scanned, 'triangles_after': scanned - removed,
                           'reduction_ratio': removed / scanned, 'budget': None,
                           'position_uv_role_sha256': fingerprint(buffers)})
    for kind in ('meshes', 'curves'):
        blocks = getattr(bpy.data, kind)
        for value in list(blocks):
            if not value.users:
                blocks.remove(value)
    assert not DEST.exists(), f'Already exists: {DEST}'
    with rac.output_palette_paths(images, DEST):
        assert bpy.ops.wm.save_as_mainfile(filepath=str(DEST), compress=True, copy=True,
                                           relative_remap=False) == {'FINISHED'}
    assert before == snapshot()
    rac.write_json(WORK / 'prepared.json', {'sources': before, 'components': report,
                   'optimization': ['evaluated mesh triangles', 'merge within each component by material role',
                                    'remove exact same-material face duplicates and zero-area faces; omit unused vertices',
                                    'retain enclosed faces and silhouette detail when impact is not proven'],
                   'optimized_blend': rac.file_record(DEST), 'role': 'optimized'})


def export():
    report = rac.read_json(WORK / 'prepared.json')
    assert Path(bpy.data.filepath).resolve() == DEST.resolve()
    assert report['optimized_blend'] == rac.file_record(DEST)
    assert report['sources'] == snapshot()
    errors = []
    master = bpy.data.scenes[rac.MASTER]
    stage = WORK / 'glb'
    stage.mkdir(exist_ok=True)
    for row in report['components']:
        key = row['asset_key']
        coll = bpy.data.collections[row['asset_id']]
        with rac.active_scene(master):
            buffers, scanned, removed = role_payload(coll, bpy.context.evaluated_depsgraph_get())
            assert scanned == row['triangles_after'] and not removed, key
            assert fingerprint(buffers) == row['position_uv_role_sha256'], key
            rac.inspect_component(coll, errors, False)
            rac.palette_images(coll.objects, DEST, errors, True)
        rac.checks_pass(errors)
        scene = bpy.data.scenes.new('Export_' + key)
        scene.unit_settings.system = 'METRIC'
        scene.collection.children.link(coll)
        path = stage / f'{key}.glb'
        try:
            with rac.active_scene(scene):
                assert bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', use_active_scene=True,
                    export_texcoords=True, export_normals=True, export_image_format='NONE',
                    export_materials='EXPORT', export_animations=False, export_yup=True,
                    export_apply=True, export_cameras=False, export_lights=False) == {'FINISHED'}
        finally:
            bpy.data.scenes.remove(scene)
        rac.inspect_glb(path)
        raw = path.read_bytes()
        size = struct.unpack_from('<I', raw, 12)[0]
        data = json.loads(raw[20:20+size])
        triangles = sum(data['accessors'][p['indices']]['count'] // 3
                        for mesh in data['meshes'] for p in mesh['primitives'])
        assert triangles == row['triangles_after'], (key, triangles, row['triangles_after'])
        row.update(glb_sha256=rac.sha256(path), glb_triangles=triangles)
    assert report['sources'] == snapshot()
    report['source_unchanged_after_export'] = True
    rac.write_json(WORK / 'export.json', report)


def render(label, source):
    for im in bpy.data.images:
        if im.source == 'FILE' and rac.image_path(im, source) == rac.PALETTE.resolve():
            im.filepath = str(rac.PALETTE)
    scene = bpy.data.scenes[rac.STATIC]
    rac.set_render_samples(scene, 16)
    scene.render.resolution_percentage = 60
    with rac.active_scene(scene):
        for name in ('Front', 'Back', 'Right', 'Hero'):
            path = WORK / f'{label}_{name.lower()}.png'
            if path.is_file() and path.read_bytes().endswith(b'IEND\xaeB`\x82'):
                continue
            scene.camera = scene.objects[name]
            scene.render.filepath = str(path)
            assert bpy.ops.render.render(write_still=True) == {'FINISHED'}


mode = sys.argv[sys.argv.index('--') + 1]
source = DEST if mode in ('after', 'export') else rac.SOURCE
WORK.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(source), use_scripts=False)
if mode == 'prepare':
    prepare()
elif mode == 'export':
    export()
elif mode in ('before', 'after'):
    render(mode, source)
else:
    raise ValueError(mode)
