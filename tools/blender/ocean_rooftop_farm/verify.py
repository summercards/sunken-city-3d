"""Reopen, validate and package the eight-storey ocean rooftop farm source kit."""
import bpy, json, hashlib, math
from pathlib import Path
from mathutils import Vector

R = Path(r'D:/projects/sea')
D = R / 'art_source/scenes/ocean_rooftop_farm/v001'
W = R.parent / 'sea-work/ocean_rooftop_farm/v001'
W.mkdir(parents=True, exist_ok=True)
pal = R / 'art_source/shared/palettes/sea_cabin_timber_8x8_512.png'
source = D / 'ocean_rooftop_farm.blend'
plan = json.loads((D / 'component_plan.json').read_text(encoding='utf-8'))
cat_path = D / 'component_catalog.json'
cat = json.loads(cat_path.read_text(encoding='utf-8'))
entries = cat['components']
errors = []
uv_faces = 0
checks = 0
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()

def req(value, message):
    global checks
    checks += 1
    if not value:
        errors.append(message)


def identity(m):
    return max(abs(m[i][j] - (1 if i == j else 0)) for i in range(4) for j in range(4)) < 1e-5


def inspect(entry, count=False):
    global uv_faces
    c = bpy.data.collections.get(entry['collection'])
    req(c is not None, entry['key'] + ' collection missing')
    if not c:
        return
    req(tuple(c.instance_offset) == (0, 0, 0), entry['key'] + ' collection offset')
    root = bpy.data.objects.get(entry['root'])
    req(root is not None and identity(root.matrix_world), entry['key'] + ' root transform')
    pts = []
    tris = 0
    for o in c.objects:
        if o.type != 'MESH':
            continue
        req(o.parent == root, entry['key'] + ' wrong parent ' + o.name)
        o.data.calc_loop_triangles()
        tris += len(o.data.loop_triangles)
        ev = o.evaluated_get(bpy.context.evaluated_depsgraph_get())
        me = ev.to_mesh()
        pts.extend(o.matrix_world @ v.co for v in me.vertices)
        ev.to_mesh_clear()
        uv = o.data.uv_layers.get('PaletteUV')
        req(uv is not None, o.name + ' UV missing')
        if not uv:
            continue
        req(len(o.data.uv_layers) == 1 and o.data.uv_layers.active == uv and uv.active_render, o.name + ' active UV')
        for f in o.data.polygons:
            p = [uv.data[i].uv for i in f.loop_indices]
            area = abs(sum(a.x*b.y - b.x*a.y for a,b in zip(p,p[1:]+p[:1]))) / 2
            req(area > 1e-9, o.name + ' point UV')
            req(len({(int(v.x*8), int(v.y*8)) for v in p}) == 1, o.name + ' UV crosses cells')
            req(all(.125 - 1e-5 <= (v[k]*8)%1 <= .875 + 1e-5 for v in p for k in [0,1]), o.name + ' UV unsafe margin')
            if count:
                uv_faces += 1
        for m in o.data.materials:
            req(m is not None and m.name in {'SEA_Matte','SEA_Metal','SEA_Gloss','SEA_Emission'}, o.name + ' material role')
            if not m:
                continue
            tx = [n for n in m.node_tree.nodes if n.type == 'TEX_IMAGE']
            req(len(tx) == 1, m.name + ' texture count')
            for n in tx:
                req(n.interpolation == 'Closest' and n.image and not n.image.packed_file, m.name + ' packed/interpolation')
                req(Path(bpy.path.abspath(n.image.filepath)).resolve() == pal.resolve(), m.name + ' palette path')
                req(n.inputs['Vector'].links and n.inputs['Vector'].links[0].from_node.uv_map == 'PaletteUV', m.name + ' UV input')
    req(bool(pts), entry['key'] + ' empty geometry')
    if not pts:
        return
    lo = [min(v[i] for v in pts) for i in range(3)]
    hi = [max(v[i] for v in pts) for i in range(3)]
    req(abs(lo[2]) < 1e-4 and abs(lo[0]+hi[0]) < 1e-4 and abs(lo[1]+hi[1]) < 1e-4, entry['key'] + ' origin ' + str(lo) + str(hi))
    for i in range(3):
        req(abs(hi[i]-lo[i]-entry['bounds_size'][i]) < .03, entry['key'] + ' bounds')
    entry['triangles'] = tris


bpy.ops.wm.open_mainfile(filepath=str(source))
sc = bpy.data.scenes['海上屋顶农场_制作与装配_v001']
if bpy.context.window:
    bpy.context.window.scene = sc
req(len(entries) == 44 and len(entries) <= 50, 'component count')
req(plan['dimension_contract']['visible_floors'] == 8, 'eight floors plan')
req(sha(D/'reference.jpg') == plan['reference']['sha256'], 'reference hash')
layout = json.loads((D/'component_instances.json').read_text(encoding='utf-8'))['instances']
actual = {o.name:o for o in sc.objects if o.instance_type == 'COLLECTION'}
req(len(actual) == len(layout), 'instance count')
instance_signatures = [(i['key'], tuple(round(v,5) for v in i['position']), tuple(round(v,5) for v in i['rotation_euler_xyz']), tuple(round(v,5) for v in i['scale'])) for i in layout]
req(len(set(instance_signatures)) == len(instance_signatures), 'exact duplicate instances')
for item in layout:
    o = actual.get(item['name'])
    req(o is not None, item['name'] + ' instance missing')
    if o:
        req(o.instance_collection.name == item['asset_id'], item['name'] + ' asset')
        for key, attr in [('position','location'),('rotation_euler_xyz','rotation_euler'),('scale','scale')]:
            req(max(abs(getattr(o,attr)[j]-item[key][j]) for j in range(3)) < 1e-5, item['name'] + ' ' + key)
for entry in entries:
    inspect(entry, True)
for key in ['solar_panel','leaf_row','seedling_row','vine_row']:
    req(not any(i['key'] == key for i in layout), 'removed asset remains ' + key)
    req(not any(e['key'] == key for e in entries), 'removed catalog entry ' + key)
req(sum(i['key']=='floor_slab' for i in layout) == 8, 'eight floor slabs')
req(sum(i['key'] in {'facade_window','broken_window'} for i in layout) == 80, '80 unique facade windows including side windows')
req(sum(i['key']=='balcony' for i in layout) == 32, '32 balconies')

deps = bpy.context.evaluated_depsgraph_get()
polys = triangles = 0
for inst in deps.object_instances:
    o = inst.object
    if o.type == 'MESH' and not o.hide_render:
        me = o.to_mesh()
        me.calc_loop_triangles()
        polys += len(me.polygons)
        triangles += len(me.loop_triangles)
        o.to_mesh_clear()
key_bounds = {}
for item in layout:
    o = actual[item['name']]
    pts = []
    for m in o.instance_collection.objects:
        if m.type != 'MESH':
            continue
        ev = m.evaluated_get(deps)
        me = ev.to_mesh()
        pts.extend(o.matrix_world @ m.matrix_local @ v.co for v in me.vertices)
        ev.to_mesh_clear()
    key_bounds[item['name']] = [min(v[i] for v in pts) for i in range(3)] + [max(v[i] for v in pts) for i in range(3)]
roof = key_bounds['roof_deck_01']
raised = key_bounds['raised_platform_01']
upper = key_bounds['upper_room_01']
tank = key_bounds['water_tank_01']
req(abs((roof[3]-roof[0])-36.10) < .02 and abs((roof[4]-roof[1])-24.05) < .02, 'roof 36x24 plus front cap')
req(abs(roof[2]+.22-25.60) < .02, 'roof walking surface 25.60')
req(abs(raised[2]-25.60) < .02 and abs(raised[5]-29.0) < .03, 'raised platform attached')
req(abs(upper[2]-29.0) < .02, 'upper room seated')
req(abs(tank[5]-34.50) < .03, 'water tower total height 8.9m within 9m nominal')
req(all(v[2] > -1 for v in key_bounds.values()), 'no detached or negative base geometry')

# Individually reopenable component packages, linked to the one shared palette.
for entry in entries:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    with bpy.data.libraries.load(str(source), link=False) as (a,b):
        b.collections = [entry['collection']]
    c = b.collections[0]
    bpy.context.scene.collection.children.link(c)
    bpy.context.scene.name = entry['name']
    bpy.context.scene.unit_settings.system = 'METRIC'
    p = R / entry['component_source']
    p.parent.mkdir(parents=True, exist_ok=True)
    for im in bpy.data.images:
        if im.source == 'FILE':
            im.filepath = bpy.path.relpath(str(pal), start=str(p.parent))
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(p), compress=True)
    entry['source_sha256'] = sha(p)
    entry['palette'] = str(pal.relative_to(R))
    entry['version'] = 'v001'
    entry['stage'] = 'source_verified_runtime_pending'
    entry['license'] = 'pending_user_reference_rights_review'
    entry['asset_ledger'] = 'assets/registry/ledgers/scenes.json#' + entry['asset_id']
    (p.parent/'asset_manifest.json').write_text(json.dumps(entry, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    bpy.ops.wm.open_mainfile(filepath=str(p))
    inspect(entry)
    print('REOPENED', entry['key'], flush=True)

report = {
    'schema': 'sea.scene.source_verification',
    'passed': not errors,
    'errors': sorted(set(errors)),
    'checks': checks,
    'source_sha256': sha(source),
    'palette_sha256': sha(pal),
    'reference_sha256': sha(D/'reference.jpg'),
    'metrics': {'components':len(entries),'instances':len(layout),'floors':8,'uv_faces_checked':uv_faces,'expanded_polygons':polys,'expanded_triangles':triangles},
    'standalone_packages_reopened':len(entries),
    'key_bounds': {k:key_bounds[k] for k in ['roof_deck_01','raised_platform_01','upper_room_01','water_tank_01','roof_tiles_01']},
    'source_only': True,
    'removed': ['all crop rows','all solar panels','people','animals','ocean/background'],
    'not_executed': ['Godot import/runtime/collision/navigation','reference commercial rights verification','user final art acceptance'],
    'views': []
}
(W/'verification.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
if errors:
    raise RuntimeError('\n'.join(sorted(set(errors))))
cat_path.write_text(json.dumps(cat, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')

bpy.ops.wm.open_mainfile(filepath=str(source))
sc = bpy.data.scenes['海上屋顶农场_制作与装配_v001']
if bpy.context.window:
    bpy.context.window.scene = sc
cam = sc.camera
sc.render.resolution_percentage = 100
views = [
    ('beauty', (48,-62,68), (0,0,13), 80, (1440,1100), None),
    ('roof_detail', (32,-38,53), (0,0,26.8), 43, (1440,1050), None),
    ('top', (0,-.01,70), (0,0,25.6), 43, (1200,1000), None),
    ('facade_detail', (21,-40,23), (0,-10,14), 32, (1200,1200), None),
    ('building_only', (40,-52,56), (0,0,13), 72, (1440,1100), 'building')
]
for name, pos, target, size, res, mode in views:
    hidden = []
    if mode == 'building':
        for cname in ['02_固定设施','03_花草植被']:
            for o in bpy.data.collections[cname].objects:
                hidden.append((o,o.hide_render))
                o.hide_render = True
    cam.location = pos
    cam.rotation_euler = (Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler()
    cam.data.ortho_scale = size
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.filepath = str(W/(name+'.png'))
    bpy.ops.render.render(write_still=True, scene=sc.name)
    report['views'].append({'name':name,'path':sc.render.filepath})
    for o, old in hidden:
        o.hide_render = old
(W/'verification.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
print('SOURCE_VERIFIED', json.dumps(report['metrics']), flush=True)
