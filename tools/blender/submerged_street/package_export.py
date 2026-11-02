"""Independent packages + GLB export for submerged_street v001.

Every building is reopened from the saved master, re-validated, saved as its own .blend,
reopened again to prove it stands alone, then exported as a GLB with no embedded images.
A separate optimized derivative is produced (merge doubles / drop degenerate + loose) so
the authored master is never rewritten. Renders source vs optimized from the same camera
and reports the mean pixel difference.

Run: blender --background --factory-startup --python tools/blender/submerged_street/package_export.py
"""
import bpy
import bmesh
import hashlib
import json
import math
import os
import struct
from pathlib import Path
from mathutils import Vector

R = Path(__file__).resolve().parents[3]
D = R / 'art_source/scenes/submerged_street/v001'
W = Path(os.environ.get('SEA_WORK_ROOT', R.parent / 'sea-work')) / 'submerged_street_v001'
OUT = W / 'package_renders'
OUT.mkdir(parents=True, exist_ok=True)
P = json.loads((D / 'component_plan.json').read_text(encoding='utf-8'))
CAT = json.loads((D / 'catalog.json').read_text(encoding='utf-8'))['components']
SOURCE = D / 'submerged_street.blend'
OPT = D / 'export/v001/submerged_street_optimized.blend'
PAL = R / P['palette']
ROLES = {'SEA_Matte', 'SEA_Metal', 'SEA_Gloss'}


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def write(p, v):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(v, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def check_mesh(o, tag):
    assert o.matrix_world == o.matrix_world.Identity(4), tag + ': transform not identity'
    assert len(o.modifiers) == 0, tag + ': unapplied modifiers'
    me = o.data
    me.calc_loop_triangles()
    tris = len(me.loop_triangles)
    assert tris > 0, tag + ': empty mesh'
    assert len(me.uv_layers) == 1, tag + ': uv layer count %d' % len(me.uv_layers)
    uvl = me.uv_layers.active
    assert uvl.name == 'PaletteUV' and uvl.active_render, tag + ': PaletteUV not active/render'
    for f in me.polygons:
        pts = [tuple(uvl.data[li].uv) for li in f.loop_indices]
        cells = {(int(p[0] * 8), int(p[1] * 8)) for p in pts}
        assert len(cells) == 1, tag + ': face spans cells'
        area = sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1]
                   for i in range(len(pts)))
        assert abs(area) > 1e-7, tag + ': zero-area uv island'
        for p in pts:
            assert 0.015625 < p[0] % 0.125 < 0.109375 and 0.015625 < p[1] % 0.125 < 0.109375, \
                tag + ': uv outside safe margin'
    assert {m.name for m in me.materials} <= ROLES, tag + ': invalid material roles'
    for m in me.materials:
        tex = next(n for n in m.node_tree.nodes if n.type == 'TEX_IMAGE')
        assert tex.interpolation == 'Closest' and tex.image.packed_file is None
        assert Path(bpy.path.abspath(tex.image.filepath)).resolve() == PAL.resolve()
    for v in me.vertices:
        assert abs(v.co.z) >= -1e-6
    return tris


bpy.context.preferences.filepaths.save_version = 0
protected = {str(SOURCE): sha(SOURCE), str(PAL): sha(PAL)}
rows = []

for item in CAT:
    key = item['key']
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    col = bpy.data.collections[item['asset_id']]
    assert tuple(col.instance_offset) == (0, 0, 0)
    o = col.objects[0]
    before = check_mesh(o, key)
    pkg = D / 'component_packages' / key
    pkg.mkdir(parents=True, exist_ok=True)
    # package = one scene holding only this building's collection
    sc = bpy.data.scenes.new(item['name'])
    sc.unit_settings.system = 'METRIC'
    sc.collection.children.link(col)
    bpy.context.window.scene = sc
    for other in list(bpy.data.scenes):
        if other is not sc:
            bpy.data.scenes.remove(other)
    bpy.data.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)
    path = pkg / (key + '.blend')
    bpy.ops.wm.save_as_mainfile(filepath=str(path), compress=True)
    # proof the package stands alone
    bpy.ops.wm.open_mainfile(filepath=str(path))
    assert len(bpy.data.scenes) == 1, key + ': package has extra scenes'
    assert len([x for x in bpy.data.objects if x.type == 'MESH']) == 1, key + ': package object count'
    tris = check_mesh(bpy.data.objects[key], key + '/package')
    assert tris == before, key + ': triangle count changed on reopen'
    ledger_path = json.loads((R / 'assets/registry/ledger_index.json').read_text(encoding='utf-8'))['domains']['scenes']['ledger']
    write(pkg / 'asset_manifest.json', dict(
        asset_id=item['asset_id'], name=item['name'], suite='submerged_street', version='v001',
        asset_ledger=ledger_path + '#' + item['asset_id'],
        source=(pkg / (key + '.blend')).relative_to(R).as_posix(),
        source_sha256=sha(pkg / (key + '.blend')),
        master=SOURCE.relative_to(R).as_posix(), master_sha256=protected[str(SOURCE)],
        palette=P['palette'], palette_sha256=protected[str(PAL)],
        building_class='underwater', category='underwater_scenic_building',
        stage='source_verified_export_pending_runtime_integration',
        triangles=tris, triangle_budget=item['triangle_budget'],
        material_roles=sorted({m.name for m in bpy.data.objects[key].data.materials}),
        emission=False, collision=False, interactive=False,
        license=P['reference_license'],
        note='Purely decorative sunken-street building. No collision, walk area, landing, interaction, production or save field.'))
    rows.append(dict(item, triangles_before=before, triangles_after=tris,
                     package=(pkg / (key + '.blend')).relative_to(R).as_posix(),
                     package_sha256=sha(pkg / (key + '.blend'))))

# ---- optimized derivative: same geometry, only welding and degenerate cleanup
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
cleanup = []
for item in CAT:
    key = item['key']
    o = bpy.data.objects[key]
    before = check_mesh(o, key + '/optimize-in')
    bm = bmesh.new()
    bm.from_mesh(o.data)
    v0, f0 = len(bm.verts), len(bm.faces)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-6)
    bmesh.ops.dissolve_degenerate(bm, edges=list(bm.edges), dist=1e-7)
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context='VERTS')
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(o.data)
    bm.free()
    o.data.update()
    after = check_mesh(o, key + '/optimize-out')
    cleanup.append(dict(key=key, triangles_before=before, triangles_after=after,
                        vertices_before=v0, vertices_after=len(o.data.vertices),
                        faces_before=f0, faces_after=len(o.data.polygons)))
OPT.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(OPT), compress=True)

# ---- render source vs optimized from the same camera, then measure the difference
def render_set(blend, tag):
    bpy.ops.wm.open_mainfile(filepath=str(blend))
    S = bpy.data.scenes['沉没街道_参考布局']
    bpy.context.window.scene = S
    S.render.engine = 'CYCLES'
    S.cycles.samples = 24
    S.cycles.use_denoising = True
    S.view_settings.view_transform = 'Standard'
    S.view_settings.exposure = -0.15
    S.world.node_tree.nodes['Background'].inputs[0].default_value = (0.075, 0.165, 0.205, 1)
    S.world.node_tree.nodes['Background'].inputs[1].default_value = 1.15
    STAGE = bpy.data.collections['展示支持_不导出']
    for x in [x for x in STAGE.objects if x.type == 'LIGHT']:
        bpy.data.objects.remove(x, do_unlink=True)
    for nm, rot, e in (('a', (math.radians(50), 0, math.radians(34)), 3.0),
                       ('b', (math.radians(66), 0, math.radians(196)), 1.35),
                       ('c', (math.radians(74), 0, math.radians(96)), 0.7)):
        d = bpy.data.lights.new(nm, 'SUN')
        d.energy = e
        d.angle = 0.2
        lo = bpy.data.objects.new(nm, d)
        STAGE.objects.link(lo)
        lo.rotation_euler = rot
    cam = S.camera
    cam.data.type = 'ORTHO'
    S.render.resolution_x, S.render.resolution_y = 1000, 800
    S.render.film_transparent = False
    for name, pos, tgt, scale in (('front', (24, -62, 28), (-42, 12, 7), 74),
                                  ('top', (-42, 13, 96), (-42, 13, 0), 72)):
        cam.location = Vector(pos)
        cam.rotation_euler = (Vector(tgt) - cam.location).to_track_quat('-Z', 'Y').to_euler()
        cam.data.ortho_scale = scale
        S.render.filepath = str(OUT / ('%s_%s.png' % (tag, name)))
        bpy.ops.render.render(write_still=True)


render_set(SOURCE, 'source')
render_set(OPT, 'optimized')


def mean_rgb(path):
    import zlib
    d = Path(path).read_bytes()
    i, idat, w, h, ct = 8, b'', 0, 0, 6
    while i < len(d):
        ln = struct.unpack('>I', d[i:i + 4])[0]
        typ = d[i + 4:i + 8]
        if typ == b'IHDR':
            w, h, _, ct = struct.unpack('>IIBB', d[i + 8:i + 18])
        elif typ == b'IDAT':
            idat += d[i + 8:i + 8 + ln]
        i += 12 + ln
    raw = zlib.decompress(idat)
    bpp = 4 if ct == 6 else 3
    stride = w * bpp
    prev = bytearray(stride)
    pos = 0
    tot = [0, 0, 0]
    n = 0
    for _ in range(h):
        f = raw[pos]
        pos += 1
        line = bytearray(raw[pos:pos + stride])
        pos += stride
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            if f == 1:
                line[x] = (line[x] + a) & 255
            elif f == 2:
                line[x] = (line[x] + b) & 255
            elif f == 3:
                line[x] = (line[x] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[x] = (line[x] + pr) & 255
        for x in range(0, stride, bpp):
            tot[0] += line[x]
            tot[1] += line[x + 1]
            tot[2] += line[x + 2]
            n += 1
        prev = line
    return [t / n / 255.0 for t in tot]


fidelity = []
for name in ('front', 'top'):
    a = mean_rgb(OUT / ('source_%s.png' % name))
    b = mean_rgb(OUT / ('optimized_%s.png' % name))
    fidelity.append(dict(view=name, source_mean_rgb=[round(v, 6) for v in a],
                         optimized_mean_rgb=[round(v, 6) for v in b],
                         max_channel_delta=round(max(abs(x - y) for x, y in zip(a, b)) * 255, 4)))
assert all(f['max_channel_delta'] < 0.5 for f in fidelity), 'optimized render drifted: %s' % fidelity

# ---- GLB export straight from each independent package (one scene, one object each)
targets = {}
for item in CAT:
    key = item['key']
    bpy.ops.wm.open_mainfile(filepath=str(D / 'component_packages' / key / (key + '.blend')))
    assert len(bpy.data.scenes) == 1, key + ': package scene count'
    o = bpy.data.objects[key]
    assert len([x for x in bpy.data.objects if x.type == 'MESH']) == 1, key + ': package is not isolated'
    check_mesh(o, key + '/export')
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    target = R / 'godot/assets/models/scenery/submerged_street' / key / (key + '.glb')
    target.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(target), export_format='GLB', use_selection=True,
                              export_yup=True, export_animations=False, export_image_format='NONE',
                              export_texcoords=True, export_normals=True, export_materials='EXPORT',
                              export_cameras=False, export_lights=False)
    data = target.read_bytes()
    jlen = struct.unpack_from('<I', data, 12)[0]
    gl = json.loads(data[20:20 + jlen])
    assert not gl.get('images') and not gl.get('textures'), key + ': GLB embeds images'
    prims = [(m, p) for m in gl['meshes'] for p in m['primitives']]
    assert len(gl['meshes']) == 1, key + ': GLB has %d meshes' % len(gl['meshes'])
    assert all('TEXCOORD_0' in p['attributes'] for _, p in prims), key + ': PaletteUV not UV0'
    count = sum(gl['accessors'][p['indices']]['count'] // 3 for _, p in prims)
    assert count == item['triangles'], '%s: GLB triangles %d != catalog %d' % (key, count, item['triangles'])
    assert count <= item['triangle_budget'], key + ': GLB over budget'
    targets[key] = dict(runtime_path=target.relative_to(R).as_posix(),
                        runtime_sha256=sha(target), exported_triangles=count,
                        glb_bytes=len(data))

for row in rows:
    row.update(targets[row['key']])

assert all(sha(Path(p)) == h for p, h in protected.items()), 'protected source or palette changed'
write(D / 'export_manifest.json', dict(
    schema='sea.scene_export_manifest', kit='submerged_street', version='v001',
    source=SOURCE.relative_to(R).as_posix(), source_sha256=sha(SOURCE),
    optimized_source=OPT.relative_to(R).as_posix(), optimized_sha256=sha(OPT),
    palette=P['palette'], palette_sha256=sha(PAL),
    protected_sources_unchanged=True,
    cleanup_operations=['merge duplicate vertices at 1e-6 m', 'dissolve degenerate edges at 1e-7 m',
                        'remove isolated vertices', 'recalculate outward normals'],
    cleanup=cleanup, fidelity=fidelity, components=rows,
    note='Optimization only welds and cleans; it does not decimate. Triangle counts are reported before and after, and equal counts are expected, not a failure.'))

print('\n=== EXPORT ===')
for row in rows:
    print('%-26s %5d tris  glb %7d B  %s' % (row['key'], row['exported_triangles'],
                                             row['glb_bytes'], row['runtime_path']))
print('FIDELITY', fidelity)
print('EXPORT_DONE', sum(r['exported_triangles'] for r in rows), 'triangles', flush=True)
