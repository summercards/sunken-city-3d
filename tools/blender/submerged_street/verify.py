"""Self-check and multi-view renders for submerged_street v001, entirely inside Blender.

Reopens the saved source, re-validates every face's PaletteUV, material roles, origin,
transform identity, triangle budget and purely-visual responsibility, then renders
per-building 3/4 + top views plus street overviews. Writes a machine report.

Run: blender --background --factory-startup --python tools/blender/submerged_street/verify.py
"""
import bpy
import hashlib
import json
import math
import os
import sys
from pathlib import Path
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view

R = Path(__file__).resolve().parents[3]
D = R / 'art_source/scenes/submerged_street/v001'
W = Path(os.environ.get('SEA_WORK_ROOT', R.parent / 'sea-work')) / 'submerged_street_v001'
P = json.loads((D / 'component_plan.json').read_text(encoding='utf-8'))
CAT = json.loads((D / 'catalog.json').read_text(encoding='utf-8'))['components']
BLEND = D / 'submerged_street.blend'
PAL = R / P['palette']
OUT = W / 'renders'
OUT.mkdir(parents=True, exist_ok=True)

IVORY = {'white', 'plaster', 'cream', 'sand', 'snow', 'cloud'}
GLASS = {'solar', 'ocean', 'deepblue', 'aqua', 'sky', 'ice'}
DARK = {'rubber', 'slate', 'steel', 'gray', 'deepgreen', 'forest'}
ROLE_NAMES = {'SEA_Matte', 'SEA_Metal', 'SEA_Gloss'}
PAL_JSON = json.loads(PAL.with_suffix('.json').read_text(encoding='utf-8'))
CELL = {c['name']: (c['row'], c['column']) for c in PAL_JSON['cells']}
LUM = {}
for c in PAL_JSON['cells']:
    h = c['hex'].lstrip('#')
    r, g, b = (int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    LUM[c['name']] = 0.2126 * r + 0.7152 * g + 0.0722 * b
DARK_FACE_AREA_LIMIT = 2.0      # m2
DARK_LUMINANCE_LIMIT = 0.34     # below this a colour reads near-black under shade
BLACK_PIXEL_LIMIT = 0.0015      # 0.15% of a render may be pure black (antialiasing only)
BLACK_SHARES = {}


fails = []
notes = []


def check(cond, msg):
    if not cond:
        fails.append(msg)
    return cond


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


bpy.ops.wm.open_mainfile(filepath=str(BLEND))
MASTER = bpy.data.scenes['独立建筑母版']
LAYOUT_S = bpy.data.scenes['沉没街道_参考布局']
IMG_OK = []

report = {
    'schema': 'sea.asset_selfcheck',
    'kit': 'submerged_street',
    'version': 'v001',
    'source': str(BLEND.relative_to(R)).replace('\\', '/'),
    'source_sha256': sha(BLEND),
    'palette': P['palette'],
    'palette_sha256': sha(PAL),
    'blender_version': bpy.app.version_string,
    'buildings': [],
    'checks': {},
    'renders': [],
}

# ---- global structure
cols = [c for c in bpy.data.collections if c.name.startswith('SEA-SCENE-SUBMERGED-STREET-')]
check(len(cols) == 10, 'expected 10 building collections, found %d' % len(cols))
check(len(bpy.data.scenes) == 2, 'expected master + layout scene only')
check(all(m.name in ROLE_NAMES for m in bpy.data.materials if m.users),
      'stray materials: %s' % [m.name for m in bpy.data.materials if m.users and m.name not in ROLE_NAMES])
check(all('.' not in m.name for m in bpy.data.materials), 'duplicate material datablocks present')
emissive = [m.name for m in bpy.data.materials if m.use_nodes and
            any(n.type in ('EMISSION', 'BSDF_PRINCIPLED') and
                ((n.type == 'EMISSION') or (n.inputs.get('Emission Strength') and n.inputs['Emission Strength'].default_value > 0))
                for n in m.node_tree.nodes)]
check(not emissive, 'unexpected emissive material: %s' % emissive)

# ---- palette image is external and shared
for m in bpy.data.materials:
    if not m.users:
        continue
    tex = next((n for n in m.node_tree.nodes if n.type == 'TEX_IMAGE'), None)
    check(tex is not None, '%s has no palette texture node' % m.name)
    if tex:
        check(tex.interpolation == 'Closest', '%s interpolation is %s' % (m.name, tex.interpolation))
        check(tex.image is not None and tex.image.packed_file is None, '%s palette is packed' % m.name)
        if tex.image:
            check(Path(bpy.path.abspath(tex.image.filepath)).resolve() == PAL.resolve(),
                  '%s palette path is %s' % (m.name, bpy.path.abspath(tex.image.filepath)))

# ---- per building
for item in CAT:
    key = item['key']
    entry = {'key': key, 'asset_id': item['asset_id'], 'name': item['name'], 'failures': []}
    col = bpy.data.collections.get(item['asset_id'])
    if not check(col is not None, '%s: collection missing' % key):
        report['buildings'].append(entry)
        continue
    check(tuple(col.instance_offset) == (0.0, 0.0, 0.0), '%s: collection offset not zero' % key)
    check(len(col.objects) == 1, '%s: expected exactly one joined object, got %d' % (key, len(col.objects)))
    o = col.objects[0]
    check(o.name == key, '%s: object name is %s' % (key, o.name))
    check(o.matrix_world == o.matrix_world.Identity(4), '%s: object transform not identity' % key)
    check(len(o.modifiers) == 0, '%s: unapplied modifiers' % key)
    me = o.data
    me.calc_loop_triangles()
    tris = len(me.loop_triangles)
    check(tris == item['triangles'], '%s: triangle count drifted %d != %d' % (key, tris, item['triangles']))
    check(tris <= item['triangle_budget'], '%s: over budget %d > %d' % (key, tris, item['triangle_budget']))
    check(len(me.polygons) > 0 and len(me.vertices) > 0, '%s: empty geometry' % key)
    # materials
    slots = [m.name for m in me.materials]
    check(set(slots) <= ROLE_NAMES, '%s: invalid material roles %s' % (key, slots))
    check(len(slots) == len(set(slots)), '%s: duplicate material slot' % key)
    # uv layers
    check(len(me.uv_layers) == 1, '%s: expected a single UV layer, got %d' % (key, len(me.uv_layers)))
    uvl = me.uv_layers.active
    check(uvl is not None and uvl.name == 'PaletteUV', '%s: active UV layer is not PaletteUV' % key)
    check(uvl.active_render, '%s: PaletteUV is not the render layer' % key)
    uv = uvl.data
    area_by_cell = {}
    dark_faces = []
    tiny = 0
    outside = 0
    multi = 0
    for f in me.polygons:
        pts = [tuple(uv[li].uv) for li in f.loop_indices]
        cell = {(int(p[0] * 8), int(p[1] * 8)) for p in pts}
        if len(cell) != 1:
            multi += 1
            continue
        a = 0.0
        for j in range(len(pts)):
            q, r = pts[j], pts[(j + 1) % len(pts)]
            a += q[0] * r[1] - r[0] * q[1]
        if abs(a) < 1e-7:
            tiny += 1
        for p in pts:
            if not (0.015625 < p[0] % 0.125 < 0.109375 and 0.015625 < p[1] % 0.125 < 0.109375):
                outside += 1
                break
        key_cell = (min(7, max(0, int((1 - pts[0][1]) * 8))), min(7, max(0, int(pts[0][0] * 8))))
        area_by_cell[key_cell] = area_by_cell.get(key_cell, 0.0) + f.area
        if f.area > DARK_FACE_AREA_LIMIT:
            dark_cell = (min(7, max(0, int((1 - pts[0][1]) * 8))), min(7, max(0, int(pts[0][0] * 8))))
            dark_name = {(c['row'], c['column']): c['name'] for c in PAL_JSON['cells']}.get(dark_cell, '?')
            if LUM.get(dark_name, 1.0) < DARK_LUMINANCE_LIMIT:
                dark_faces.append((round(f.area, 2), dark_name))
    check(multi == 0, '%s: %d faces span more than one palette cell' % (key, multi))
    check(tiny == 0, '%s: %d faces with zero-area UV island' % (key, tiny))
    check(outside == 0, '%s: %d faces outside the 8px safe margin' % (key, outside))
    check(not dark_faces, '%s: %d faces over %.1f m2 read near-black, e.g. %s'
          % (key, len(dark_faces), DARK_FACE_AREA_LIMIT, dark_faces[:3]))
    # Coincident coplanar faces z-fight and render as black slivers. This was a real defect
    # found on the broken viaduct (a second cap sitting on the cut face), so it is guarded.
    zfight = []
    buckets = {}
    for f in me.polygons:
        c = f.center
        k = (round(c.x, 2), round(c.y, 2), round(c.z, 2))
        buckets.setdefault(k, []).append(f.index)
    for k, idxs in buckets.items():
        if len(idxs) > 1:
            ref = me.polygons[idxs[0]].normal
            if all(me.polygons[i].normal.dot(ref) > 0.985 for i in idxs[1:]):
                if me.polygons[idxs[0]].area > 0.05:
                    zfight.append((list(k), len(idxs), round(me.polygons[idxs[0]].area, 2)))
    check(not zfight, '%s: %d coplanar coincident face groups (z-fighting), e.g. %s'
          % (key, len(zfight), zfight[:3]))
    # color shares
    total = sum(area_by_cell.values()) or 1.0
    name_of = {(c['row'], c['column']): c['name'] for c in PAL_JSON['cells']}
    # tone bands are measured by luminance, not by hand-picked colour names
    shares = {'ivory': 0.0, 'mid': 0.0, 'dark': 0.0, 'glass': 0.0, 'warm': 0.0, 'green': 0.0}
    per_cell = []
    WARM_NAMES = {'coral', 'peach', 'ochre', 'gold', 'yellow', 'red', 'red_dark', 'pink', 'blush',
                  'wood_dark', 'wood_mid', 'wood', 'bark', 'honey', 'wood_light', 'wood_edge'}
    GREEN_NAMES = {'leaf', 'leaf_dark', 'leaf_mid', 'leaf_light', 'lime', 'leaf_yellow', 'jade',
                   'forest', 'moss', 'sage', 'moss_light', 'spring', 'fern', 'palegreen', 'deepgreen'}
    for rc, a in sorted(area_by_cell.items(), key=lambda kv: -kv[1]):
        n = name_of.get(rc, '?')
        per_cell.append({'cell': list(rc), 'name': n, 'share': round(a / total, 4),
                         'luminance': round(LUM.get(n, 0.0), 3)})
        if n in GLASS:
            shares['glass'] += a / total
        elif n in WARM_NAMES:
            shares['warm'] += a / total
        elif n in GREEN_NAMES:
            shares['green'] += a / total
        lum = LUM.get(n, 0.5)
        if lum >= 0.70:
            shares['ivory'] += a / total
        elif lum < DARK_LUMINANCE_LIMIT:
            shares['dark'] += a / total
        else:
            shares['mid'] += a / total
    shares = {k: round(v, 4) for k, v in shares.items()}
    # origin at bottom centre of the real envelope
    pts = [v.co for v in me.vertices]
    lo = [min(p[i] for p in pts) for i in range(3)]
    hi = [max(p[i] for p in pts) for i in range(3)]
    check(abs(lo[2]) < 1e-4, '%s: bottom is not at z=0 (%.4f)' % (key, lo[2]))
    check(abs((lo[0] + hi[0]) / 2) < 0.02 and abs((lo[1] + hi[1]) / 2) < 0.02,
          '%s: not centred on X/Y (%.3f, %.3f)' % (key, (lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2))
    check(o.get('building_class') == 'underwater', '%s: building_class is not underwater' % key)
    check(o.get('interactive') is False, '%s: marked interactive' % key)
    check(o.get('collision') == 'none', '%s: declares collision' % key)
    check(not any(m.type in ('COLLISION', 'NAVIGATION') for m in o.modifiers), '%s: collision modifier' % key)
    entry.update(triangles=tris, polygons=len(me.polygons), triangle_budget=item['triangle_budget'],
                 material_roles=sorted(slots), uv_layers=[l.name for l in me.uv_layers],
                 bounds_min=[round(v, 4) for v in lo], bounds_max=[round(v, 4) for v in hi],
                 size=[round(hi[i] - lo[i], 3) for i in range(3)],
                 plan_size=item['size_blender_xyz'], rotation_y_degrees=item['rotation_y_degrees'],
                 color_shares=shares, color_cells=per_cell[:8],
                 faces_multi_cell=multi, faces_zero_area_uv=tiny, faces_outside_margin=outside,
                 near_black_large_faces=dark_faces, coincident_face_groups=len(zfight),
                 emission=False, collision=False, interactive=False)
    report['buildings'].append(entry)

# ---- kit-level tone band, measured against the sunken base (0.82 ivory / 0.07 glass / 0.02 warm)
kit = {'ivory': 0, 'mid': 0, 'dark': 0, 'glass': 0, 'warm': 0, 'green': 0}
tot_tris = 0
for b in report['buildings']:
    w = b['triangles']
    tot_tris += w
    for k in kit:
        kit[k] += b['color_shares'][k] * w
kit = {k: round(v / max(1, tot_tris), 4) for k, v in kit.items()}
report['kit_tone'] = dict(kit, total_triangles=tot_tris,
                          base_reference={'ivory': 0.823, 'glass': 0.072, 'warm': 0.020, 'steel': 0.010})
check(0.45 <= kit['ivory'] <= 0.9, 'kit ivory share out of band: %.3f' % kit['ivory'])
check(kit['glass'] <= 0.25, 'kit glass share too high: %.3f' % kit['glass'])
check(kit['warm'] <= 0.25, 'kit warm accent share too high: %.3f' % kit['warm'])
check(kit['dark'] <= 0.14, 'kit near-black share too high: %.3f' % kit['dark'])

# ---- renders (layout scene only: the ten collection instances + stage lights)
bpy.context.window.scene = LAYOUT_S
S = LAYOUT_S
S.render.engine = 'CYCLES'
S.cycles.samples = 20
S.cycles.use_denoising = True
S.render.resolution_percentage = 100
S.render.film_transparent = False
S.view_settings.view_transform = 'Standard'
S.view_settings.look = 'None'
S.view_settings.exposure = -0.15
world = S.world
world.use_nodes = True
bg = world.node_tree.nodes['Background']
bg.inputs[0].default_value = (0.075, 0.165, 0.205, 1)
bg.inputs[1].default_value = 1.15
cam = S.camera
instances = {o.instance_collection.name: o for o in bpy.data.collections['参考布局_建筑实例'].objects}

# uniform rig: identical exposure for every shot, so colour comparison stays fair
for o in [o for o in bpy.data.collections['展示支持_不导出'].objects if o.type == 'LIGHT']:
    bpy.data.objects.remove(o, do_unlink=True)
for name, rot, energy, angle in (('主阳', (math.radians(50), 0, math.radians(34)), 3.0, 0.12),
                                 ('侧补', (math.radians(66), 0, math.radians(196)), 1.35, 0.35),
                                 ('背补', (math.radians(74), 0, math.radians(96)), 0.7, 0.5),
                                 ('正面补', (math.radians(80), 0, 0), 0.85, 0.6)):
    d = bpy.data.lights.new(name, 'SUN')
    d.energy = energy
    d.angle = angle
    lo_ = bpy.data.objects.new(name, d)
    bpy.data.collections['展示支持_不导出'].objects.link(lo_)
    lo_.rotation_euler = rot


def look(pos, target):
    cam.location = Vector(pos)
    cam.rotation_euler = (Vector(target) - Vector(pos)).to_track_quat('-Z', 'Y').to_euler()


def fit_scale(width, height, res, margin=1.06):
    """Smallest ortho width that keeps the whole subject inside the frame with margin."""
    aspect = res[0] / res[1]
    return max(width, height * aspect) * margin


def black_share(path):
    """Fraction of pure-black pixels in the rendered subject.

    Face-level audit cannot catch two panels that are coplanar in a *different* plane:
    the L-apartment entrance had a window pane 0.3 m in front of the door, which renders
    as a solid black rectangle while every palette/UV check still passes. Reading the
    actual pixels is the only way to catch that, so each shot is screened here.
    """
    img = bpy.data.images.load(str(path))
    w, h = img.size
    px = img.pixels[:]
    dark = sum(1 for i in range(0, len(px), 4) if max(px[i], px[i + 1], px[i + 2]) < 0.02)
    bpy.data.images.remove(img)
    return dark / float(w * h)


def shoot(name, pos, target, scale, res=(1200, 900)):
    S.render.resolution_x, S.render.resolution_y = res
    cam.data.type = 'ORTHO'
    cam.data.ortho_scale = scale
    look(pos, target)
    path = OUT / (name + '.png')
    S.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    share = black_share(path)
    BLACK_SHARES[name] = round(share, 5)
    check(share <= BLACK_PIXEL_LIMIT, '%s: %.3f%% of the frame is pure black (limit %.2f%%)'
          % (name, share * 100, BLACK_PIXEL_LIMIT * 100))
    report['renders'].append(path.relative_to(W.parent).as_posix())
    return path


for b in report['buildings']:
    inst = instances[b['asset_id']]
    base = inst.matrix_world.translation.copy()
    sx, sy, sz = b['size']
    for other in instances.values():
        other.hide_render = (other is not inst)
    target = base + Vector((0, 0, sz * 0.46))
    # Frame each building from its own front-left, not from the world axis: the street
    # placement turns some pieces (sign 90 deg, truck/light 12-24 deg), and a world-fixed
    # camera then photographs them nearly edge-on — the gantry read as a leaning billboard.
    yaw = math.radians(float(b.get('rotation_y_degrees', 0.0)))
    # The pieces face -Y locally. Turn the camera 24 deg off that face normal so the
    # elevation stays readable; a wider swing flattens the gantry into a diagonal sliver.
    fx, fy = math.sin(yaw), -math.cos(yaw)
    a = math.radians(-24.0)
    off = Vector((fx * math.cos(a) - fy * math.sin(a),
                  fx * math.sin(a) + fy * math.cos(a), 0.42)).normalized()
    scale = fit_scale(max(sx, sy) * 1.10 + 1.0, sz * 1.10 + 1.0, (1200, 900))
    shoot(b['key'] + '_three_quarter', target + off * 80, target, scale)
    shoot(b['key'] + '_top', base + Vector((0.001, 0.001, 80)), base,
          fit_scale(sx * 1.1, sy * 1.1, (1200, 900)))
for other in instances.values():
    other.hide_render = False

# street shots: Blender layout is (godot x, -godot z, godot y); south row sits at low Y
xs = [b['placement_godot'][0] for b in CAT]
zs = [b['placement_godot'][2] for b in CAT]
cx, cz = (min(xs) + max(xs)) / 2, (min(zs) + max(zs)) / 2
span_x = max(xs) - min(xs) + 18
span_y = max(zs) - min(zs) + 16
centre = Vector((cx, -cz, 7.0))
shoot('street_overview', centre + Vector((44, -66, 46)), centre,
      fit_scale(span_x, span_y, (1500, 1000), 1.20))
shoot('street_plan', centre + Vector((0.001, -0.001, 90)), Vector((cx, -cz, 0)),
      fit_scale(span_x - 6, span_y - 4, (1400, 1000), 1.16))
# Eye-level views are shot in two halves. The street now runs about 67 m, and one 30 mm
# frame cannot hold that from street level without turning the buildings into scenery —
# so each half gets its own camera, and each half is independently checked for framing.
def instance_bounds(objs):
    pts = []
    for o in objs:
        pts.extend([o.matrix_world @ Vector(c) for c in o.instance_collection.objects[0].bound_box])
    lo = Vector([min(p[i] for p in pts) for i in range(3)])
    hi = Vector([max(p[i] for p in pts) for i in range(3)])
    return lo, hi


west = [o for k, o in instances.items() if any(t in k for t in ('VIADUCT', 'L-APARTMENT', 'HIGHRISE'))]
east = [o for k, o in instances.items()
        if any(t in k for t in ('MCDONALDS', 'FOOD-TRUCK', 'TRAFFIC-LIGHT', 'UTILITY-POLES', 'HIGHWAY-SIGN',
                                'CONSTRUCTION', 'WALKUP'))]
cam.data.type = 'PERSP'
cam.data.lens = 30
S.render.resolution_x, S.render.resolution_y = 1500, 800
for name, objs in (('street_low', west), ('street_low_east', east)):
    for o in instances.values():
        o.hide_render = (o not in objs)
    blo_, bhi_ = instance_bounds(objs)
    bc_ = (blo_ + bhi_) / 2
    cam.location = Vector((bc_.x + 4.0, blo_.y - 34.0, 4.2))
    aim = Vector((bc_.x, bc_.y, bhi_.z * 0.40))
    cam.rotation_euler = (aim - cam.location).to_track_quat('-Z', 'Y').to_euler()
    bpy.context.view_layer.update()
    probes = [Vector((x, y, z)) for x in (blo_.x, bhi_.x) for y in (blo_.y, bhi_.y) for z in (blo_.z, bhi_.z)]
    for probe in probes[::2] + [Vector((bc_.x, bc_.y, bhi_.z))]:
        ndc = world_to_camera_view(S, cam, probe)
        check(-0.06 <= ndc.x <= 1.06 and 0.02 <= ndc.y <= 1.02,
              '%s framing misses point %s at %s'
              % (name, tuple(round(v, 1) for v in probe), tuple(round(v, 3) for v in ndc)))
    S.render.filepath = str(OUT / (name + '.png'))
    bpy.ops.render.render(write_still=True)
    share = black_share(OUT / (name + '.png'))
    BLACK_SHARES[name] = round(share, 5)
    check(share <= BLACK_PIXEL_LIMIT, '%s: %.3f%% of the frame is pure black (limit %.2f%%)'
          % (name, share * 100, BLACK_PIXEL_LIMIT * 100))
    report['renders'].append((OUT / (name + '.png')).relative_to(W.parent).as_posix())
for o in instances.values():
    o.hide_render = False

shoot('street_reverse', centre + Vector((-40, 52, 30)), centre,
      fit_scale(span_x, span_y, (1500, 1000), 1.20))

report['checks'] = {'failures': fails, 'failure_count': len(fails), 'passed': not fails,
                    'notes': notes, 'black_pixel_share': BLACK_SHARES,
                    'black_pixel_limit': BLACK_PIXEL_LIMIT}
W.mkdir(parents=True, exist_ok=True)
(W / 'selfcheck_report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print('\n=== SELF CHECK ===')
for b in report['buildings']:
    print('%-26s %5d tris  ivory %.2f mid %.2f dark %.2f glass %.2f warm %.2f  size %s' %
          (b['key'], b['triangles'], b['color_shares']['ivory'], b['color_shares']['mid'],
           b['color_shares']['dark'], b['color_shares']['glass'], b['color_shares']['warm'], b['size']))
print('KIT', report['kit_tone'])
print('FAILURES', len(fails))
for f in fails:
    print('  -', f)
print('RENDERS', len(report['renders']))
print('SELFCHECK_DONE', 'PASS' if not fails else 'FAIL', flush=True)
