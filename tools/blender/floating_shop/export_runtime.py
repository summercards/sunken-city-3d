"""Export the floating shop v002 assembly to a runtime GLB (source file is never saved).

Reads `art_source/scenes/floating_shop/v002/floating_shop.blend`, bakes the 248
Collection Instances that live under the two display collections, merges them by
material role and writes a single GLB whose origin is the assembly origin
(deck axis, 0 = the model's own Z=0). Display support (camera/lights/ground) is
excluded. The source .blend is opened read-only: this script never saves it.
"""
import bpy, json, hashlib, os
from pathlib import Path
from mathutils import Vector

R = Path('D:/projects/sea')
SRC = R / 'art_source/scenes/floating_shop/v002/floating_shop.blend'
OUT_DIR = R / 'godot/assets/models/facilities/floating_shop'
OUT = OUT_DIR / 'floating_shop.glb'
MANIFEST = R / 'art_source/scenes/floating_shop/v002/export/v001/export_manifest.json'
ALLOW = {'FSH_建筑与固定设施', 'FSH_植物附件'}
ROLES = ['SEA_Matte', 'SEA_Metal', 'SEA_Gloss', 'SEA_Emission']


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


bpy.ops.wm.open_mainfile(filepath=str(SRC))
src_scene = bpy.data.scenes['海上悬浮商铺_v002']
palette = R / 'art_source/shared/palettes/sea_cozy_8x8_512.png'

export_scene = bpy.data.scenes.new('EXPORT_RUNTIME')
export_scene.unit_settings.system = 'METRIC'
link = export_scene.collection
bpy.context.window_manager.windows[0].scene = export_scene
bpy.context.view_layer.update()

by_role = {r: [] for r in ROLES}
unknown = {}
skipped = []
instances = 0

for ob in list(src_scene.objects):
    if ob.type != 'EMPTY' or ob.instance_type != 'COLLECTION' or not ob.instance_collection:
        continue
    if not any(c.name in ALLOW for c in ob.users_collection):
        skipped.append(ob.name)
        continue
    instances += 1
    for m in ob.instance_collection.all_objects:
        if m.type != 'MESH' or m.hide_render:
            continue
        mat = m.data.materials[0].name if m.data.materials else 'NONE'
        if mat not in by_role:
            unknown[mat] = unknown.get(mat, 0) + 1
            continue
        copy = m.copy()
        copy.data = m.data.copy()
        copy.parent = None
        link.objects.link(copy)
        copy.matrix_world = ob.matrix_world @ m.matrix_world
        by_role[mat].append(copy)

if unknown:
    raise RuntimeError('unmapped materials: ' + json.dumps(unknown))

dg = bpy.context.evaluated_depsgraph_get()
merged = {}
tri_total = 0
for role, objects in by_role.items():
    # Bake modifiers (bevels) and world transforms into single meshes.
    baked = []
    for ob in objects:
        dg.update()
        ev = ob.evaluated_get(dg)
        me = bpy.data.meshes.new_from_object(ev)
        ob.modifiers.clear()
        ob.data = me
        me.transform(ob.matrix_world)
        ob.matrix_world.identity()
        me.calc_loop_triangles()
        if len(me.loop_triangles) == 0 or len(me.polygons) == 0:
            bpy.data.objects.remove(ob, do_unlink=True)
            continue
        baked.append(ob)
    bpy.ops.object.select_all(action='DESELECT')
    for ob in baked:
        ob.select_set(True)
    target = baked[0]
    bpy.context.view_layer.objects.active = target
    if len(baked) > 1:
        bpy.ops.object.join()
    target = bpy.context.view_layer.objects.active
    target.name = 'FSH_' + role
    target.data.name = 'FSH_' + role
    # One slot per role: drop duplicates the source may carry.
    for slot in list(target.material_slots):
        pass
    target.data.materials.clear()
    src_mat = bpy.data.materials.get(role)
    target.data.materials.append(src_mat)
    for poly in target.data.polygons:
        poly.material_index = 0
    target.data.calc_loop_triangles()
    merged[role] = {'triangles': len(target.data.loop_triangles),
                    'vertices': len(target.data.vertices),
                    'polygons': len(target.data.polygons)}
    tri_total += len(target.data.loop_triangles)

# Surface order is material-slot order; keep it deterministic for the Godot overrides.
order = [r for r in ROLES if r in merged]
for i, ob in enumerate(export_scene.objects):
    ob['surface_role'] = ob.name.replace('FSH_', '')

lo = [1e9] * 3
hi = [-1e9] * 3
for ob in export_scene.objects:
    for v in ob.data.vertices:
        p = ob.matrix_world @ v.co
        for i in range(3):
            lo[i] = min(lo[i], p[i])
            hi[i] = max(hi[i], p[i])

OUT_DIR.mkdir(parents=True, exist_ok=True)
# The glTF exporter walks every scene in the .blend; the display scene (ground plane)
# and the default startup scene must not reach the runtime file. Nothing is saved,
# so dropping them here cannot touch the source.
bpy.ops.object.select_all(action='SELECT')
for other in list(bpy.data.scenes):
    if other != export_scene:
        bpy.data.scenes.remove(other)
bpy.ops.export_scene.gltf(
    filepath=str(OUT), export_format='GLB', use_selection=True, export_yup=True,
    export_materials='EXPORT', export_image_format='NONE', export_texcoords=True,
    export_normals=True, export_cameras=False, export_lights=False, export_extras=True,
    export_apply=False)

manifest = {
    'schema': 'sea.scene.runtime_export',
    'asset_id': 'SEA-SCENE-FSH-ASSEMBLY',
    'version': 'v002',
    'source': 'art_source/scenes/floating_shop/v002/floating_shop.blend',
    'source_sha256': sha(SRC),
    'palette': 'art_source/shared/palettes/sea_cozy_8x8_512.png',
    'palette_sha256': sha(palette),
    'runtime_path': 'godot/assets/models/facilities/floating_shop/floating_shop.glb',
    'runtime_sha256': sha(OUT),
    'runtime_bytes': OUT.stat().st_size,
    'instances_baked': instances,
    'display_support_excluded': skipped,
    'surfaces': [{'index': i, 'role': r, **merged[r]} for i, r in enumerate(order)],
    'triangles': tri_total,
    'vertices': sum(v['vertices'] for v in merged.values()),
    'bounds_blender': {'min': [round(x, 4) for x in lo], 'max': [round(x, 4) for x in hi],
                       'size': [round(hi[i] - lo[i], 4) for i in range(3)]},
    'mapping': 'Blender(x,y,z) -> Godot(x,z,-y); front is Blender -Y = Godot +Z',
    'textures': 'none embedded; Godot overrides each surface with the shared palette material',
    'modifiers': 'bevels baked via depsgraph before merge',
}
MANIFEST.parent.mkdir(parents=True, exist_ok=True)
MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print('EXPORT_OK ' + json.dumps({'tris': tri_total, 'bytes': manifest['runtime_bytes'],
                                 'surfaces': manifest['surfaces'], 'bounds': manifest['bounds_blender']},
                                ensure_ascii=False))
