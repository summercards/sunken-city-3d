"""Build the sea `solar_flower_house` v004 source (2026-10-24 attachment).

Reference: two-storey ivory block on a stilted quay plate, open solar pavilion with a
bright orange stage, twin pale-timber piers with white rim boards and cream-capped
posts, a yellow fishing boat. Isometric diorama on a white backdrop.

Run:
  Blender --background --factory-startup --python build_v004.py -- [--render] [--quick]
Writes only art_source/scenes/solar_flower_house/v004 and sea-work previews.
Never writes runtime Godot resources.
"""
import bpy, math, random, json, hashlib, os, sys
from pathlib import Path
from mathutils import Vector, Matrix, Euler

R = Path(__file__).resolve().parents[3]
D = R / 'art_source/scenes/solar_flower_house/v004'
W = Path(os.environ.get('SEA_WORK_ROOT', R.parent / 'sea-work')) / 'solar_flower_house_v004'
if R == W or R in W.parents:
    raise RuntimeError('SEA_WORK_ROOT must stay outside the repository')
W.mkdir(parents=True, exist_ok=True)
(W / 'previews').mkdir(exist_ok=True)

plan = json.loads((D / 'component_plan.json').read_text())
assert plan['status'] == 'frozen_before_geometry'
assert len(plan['components']) <= 50
assert plan['reference_sha256'] == hashlib.sha256((D / 'reference.png').read_bytes()).hexdigest()

OUT = D / 'solar_flower_house.blend'
if OUT.exists() and '--replace-generated' not in sys.argv:
    raise RuntimeError('Existing v004 source: pass --replace-generated to re-export this candidate')

bpy.ops.wm.read_factory_settings(use_empty=True)
random.seed(4242)
pi = math.pi

scene = bpy.context.scene
scene.name = '太阳能花屋v004_参考装配'
scene.unit_settings.system = 'METRIC'

lib = bpy.data.scenes.new('组件母版_建筑与花草')
lib.unit_settings.system = 'METRIC'
masters = bpy.data.collections.new('01_制作组件')
lib.collection.children.link(masters)
mb = bpy.data.collections.new('建筑_母版')
mf = bpy.data.collections.new('花草_母版')
masters.children.link(mb)
masters.children.link(mf)
out = bpy.data.collections.new('02_参考装配_仅组件实例')
scene.collection.children.link(out)
building = bpy.data.collections.new('建筑_实例')
flora = bpy.data.collections.new('花草_实例')
out.children.link(building)
out.children.link(flora)
support = bpy.data.collections.new('90_展示环境_不导出')
scene.collection.children.link(support)

# ---------------------------------------------------------------- palette + roles
palette_path = R / 'art_source/shared/palettes/sea_cozy_8x8_512.png'
img = bpy.data.images.load(str(palette_path))
img.name = 'SEA_公共色板_8x8'
img.colorspace_settings.name = 'sRGB'
cells = {c['name']: c for c in json.loads(palette_path.with_suffix('.json').read_text())['cells']}

materials = {}
for role, metal, rough in [('Matte', 0, .74), ('Metal', .65, .28), ('Gloss', .1, .22), ('Emission', 0, .4)]:
    m = bpy.data.materials.new('SEA_' + role)
    m.use_nodes = True
    n = m.node_tree.nodes
    n.clear()
    p = n.new('ShaderNodeBsdfPrincipled')
    p.inputs['Metallic'].default_value = metal
    p.inputs['Roughness'].default_value = rough
    t = n.new('ShaderNodeTexImage')
    t.image = img
    t.interpolation = 'Closest'
    t.extension = 'EXTEND'
    uv = n.new('ShaderNodeUVMap')
    uv.uv_map = 'PaletteUV'
    o = n.new('ShaderNodeOutputMaterial')
    m.node_tree.links.new(uv.outputs['UV'], t.inputs['Vector'])
    m.node_tree.links.new(t.outputs['Color'], p.inputs['Base Color'])
    m.node_tree.links.new(p.outputs[0], o.inputs[0])
    if role == 'Gloss':
        p.inputs['Coat Weight'].default_value = .3
    materials[role] = m

current = None
components = {}
records = []


def activate(o):
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o


def finish(o, name, color='cream', role='Matte', bevel=0.0, seg=2, smooth=True):
    o.name = name
    for c in list(o.users_collection):
        c.objects.unlink(o)
    current.objects.link(o)
    activate(o)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 1e-5:
        mod = o.modifiers.new('柔和倒角', 'BEVEL')
        mod.width = bevel
        mod.segments = seg
        mod.limit_method = 'ANGLE'
        bpy.ops.object.modifier_apply(modifier=mod.name)
    for p in o.data.polygons:
        p.use_smooth = smooth
    if bevel > 1e-5:
        mod = o.modifiers.new('平面加权法线', 'WEIGHTED_NORMAL')
        mod.keep_sharp = True
        mod.weight = 50
        try:
            bpy.ops.object.modifier_apply(modifier=mod.name)
        except RuntimeError:
            o.modifiers.remove(mod)
    o.data.transform(o.matrix_world)
    o.matrix_world = Matrix.Identity(4)
    o.data.materials.clear()
    o.data.materials.append(materials[role])
    for old in list(o.data.uv_layers):
        o.data.uv_layers.remove(old)
    uv = o.data.uv_layers.new(name='PaletteUV')
    uv.active_render = True
    cell = cells[color]
    cx = (cell['column'] + .5) / 8
    cy = 1 - (cell['row'] + .5) / 8
    for p in o.data.polygons:
        count = len(p.loop_indices)
        for k, li in enumerate(p.loop_indices):
            a = 2 * pi * k / count
            uv.data[li].uv = (cx + .022 * math.cos(a), cy + .022 * math.sin(a))
    o['palette_color'] = color
    o['soft_edge'] = 'bevel_%d_segments' % seg if bevel > 1e-5 else 'curved_surface'
    return o


def box(n, loc, size, col='cream', bev=.03, role='Matte', rot=None, seg=2, smooth=True):
    size = tuple(size)
    bev = min(bev, min(size) * .34)
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.object
    o.scale = size
    if rot:
        o.rotation_euler = rot
    return finish(o, n, col, role, bev, seg, smooth)


def cyl(n, loc, radius, depth, col='wood', role='Matte', rot=None, verts=24, r2=None, seg=1):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=radius,
                                    radius2=radius if r2 is None else r2,
                                    depth=depth, location=loc)
    o = bpy.context.object
    if rot:
        o.rotation_euler = rot
    return finish(o, n, col, role, min(.02, radius * .16), seg, False)


def ball(n, loc, scale, col='leaf', role='Matte', rot=None, seg=14, ring=8):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=ring, location=loc)
    o = bpy.context.object
    o.scale = scale
    if rot:
        o.rotation_euler = rot
    return finish(o, n, col, role, 0, 1, True)


def blade(n, base, tip, width, thick, col, role='Matte'):
    """Rounded oval leaf / petal: an ellipsoid stretched from base towards tip."""
    base = Vector(base)
    tip = Vector(tip)
    d = tip - base
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=6, location=(base + tip) / 2)
    o = bpy.context.object
    o.scale = (width, thick, max(d.length / 2, 1e-4))
    o.rotation_euler = d.to_track_quat('Z', 'Y').to_euler()
    return finish(o, n, col, role, 0, 1, True)


def mesh(n, verts, faces, col, bev=0.0, seg=2, out_normals=True):
    me = bpy.data.meshes.new(n)
    me.from_pydata(verts, [], faces)
    me.validate()
    me.update()
    o = bpy.data.objects.new(n, me)
    scene.collection.objects.link(o)
    activate(o)
    if out_normals:
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.mesh.normals_make_consistent(inside=False)
        bpy.ops.object.mode_set(mode='OBJECT')
    return finish(o, n, col, 'Matte', bev, seg, True)


def plate(n, xz, y0, y1, col, bev=.008):
    k = len(xz)
    verts = [(x, y0, z) for x, z in xz] + [(x, y1, z) for x, z in xz]
    faces = [tuple(range(k - 1, -1, -1)), tuple(range(k, 2 * k))]
    for i in range(k):
        j = (i + 1) % k
        faces.append((i, j, k + j, k + i))
    return mesh(n, verts, faces, col, bev)


def loft(n, bottom, z0, top, z1, col, bev=0.0):
    k = len(top)
    verts = [(x, y, z0) for x, y in bottom] + [(x, y, z1) for x, y in top]
    faces = [(i, (i + 1) % k, k + (i + 1) % k, k + i) for i in range(k)]
    faces.append(tuple(range(k - 1, -1, -1)))
    faces.append(tuple(range(k, 2 * k)))
    return mesh(n, verts, faces, col, bev)


def wire(n, pts, r=.012, col='lightgray'):
    curve = bpy.data.curves.new(n, 'CURVE')
    curve.dimensions = '3D'
    curve.resolution_u = 8
    curve.bevel_depth = r
    curve.bevel_resolution = 2
    sp = curve.splines.new('BEZIER')
    sp.bezier_points.add(len(pts) - 1)
    for p, co in zip(sp.bezier_points, pts):
        p.co = co
        p.handle_left_type = 'AUTO'
        p.handle_right_type = 'AUTO'
    o = bpy.data.objects.new(n, curve)
    scene.collection.objects.link(o)
    activate(o)
    bpy.ops.object.convert(target='MESH')
    return finish(bpy.context.object, n, col)


def start(slug):
    global current
    item = next(c for c in plan['components'] if c['slug'] == slug)
    current = bpy.data.collections.new(item['component_id'])
    (mf if item['category'] == 'flora' else mb).children.link(current)
    scene.collection.children.link(current)
    current['component_id'] = item['component_id']
    current['category'] = item['category']
    current.instance_offset = (0, 0, 0)
    return current


def end(slug):
    global current
    objs = list(current.objects)
    assert objs, slug
    verts = [o.matrix_world @ v.co for o in objs for v in o.data.vertices]
    lo = Vector(tuple(min(v[i] for v in verts) for i in range(3)))
    hi = Vector(tuple(max(v[i] for v in verts) for i in range(3)))
    anchor = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
    for o in objs:
        o.data.transform(Matrix.Translation(-anchor))
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    o = bpy.context.object
    o.name = slug + '_body'
    o.data.name = o.name + '_mesh'
    root = bpy.data.objects.new('ROOT_' + slug, None)
    current.objects.link(root)
    o.parent = root
    components[slug] = {'collection': current, 'anchor': anchor,
                        'bounds': list(hi - lo), 'meshes': [o]}
    scene.collection.children.unlink(current)


def inst(slug, loc=(0, 0, 0), rot=(0, 0, 0), scale=1.0):
    c = components[slug]
    o = bpy.data.objects.new(slug + '_instance', None)
    o.instance_type = 'COLLECTION'
    o.instance_collection = c['collection']
    (flora if c['collection']['category'] == 'flora' else building).objects.link(o)
    o.rotation_euler = rot
    o.scale = (scale,) * 3
    o.location = Vector(loc) + o.rotation_euler.to_matrix() @ (c['anchor'] * scale)
    item = next(x for x in plan['components'] if x['slug'] == slug)
    o['component_id'] = item['component_id']
    records.append({'component_id': item['component_id'], 'instance_id': o.name,
                    'position_m': list(o.location), 'rotation_euler_xyz_rad': list(o.rotation_euler),
                    'scale': list(o.scale), 'source_object': o.name})
    return o


# ================================================================ geometry
# Layout contract (metres, +X right, +Y back, front = -Y):
#   base plate top z=0 | pier deck z=.60 | orange stage z=.95
#   ground floor 0..2.40 | level-2 slab 2.40..2.60 | upper volume 2.60..4.40
#   roof terrace 4.40..4.58 | roof room 4.58..6.08 + hip 6.08..6.34
#   level-2 volume y -1.35..2.95 leaves a 1.37 m terrace strip in front of it.

TILT = math.radians(10.5)

# --- platform -------------------------------------------------------------
start('base_slab')
box('台面白框', (0, 0, -.11), (5.65, 6.00, .22), 'white', .045)
box('薄荷铺面', (0, 0, -.01), (5.49, 5.84, .045), 'mint_white', .02)
box('青绿腰线', (0, 0, -.235), (5.67, 6.02, .045), 'sky', .012)
box('下沿白板', (0, 0, -.285), (5.63, 5.98, .065), 'white', .018)
for x in (-2.55, 0.55):
    for y in (-2.55, 2.65):
        box('梁托', (x, y, -.33), (.30, .30, .07), 'white', .016)
end('base_slab')

start('stilt')
cyl('桩身', (0, 0, -.68), .24, 1.24, 'bark', verts=4, r2=.20, seg=1)
box('白帽箍', (0, 0, -.03), (.50, .50, .11), 'cream', .025)
end('stilt')

start('stage_base')
box('台基座', (0, 0, .40), (3.20, 2.70, .80), 'cream', .05)
box('台基腰线', (0, 0, .795), (3.26, 2.76, .07), 'white', .02)
box('台基底线', (0, 0, .045), (3.26, 2.76, .09), 'sand', .02)
for x in (-1.40, 0, 1.40):
    box('台基壁柱', (x, -1.37, .42), (.18, .09, .70), 'cream', .02)
end('stage_base')

# --- house shell ----------------------------------------------------------
start('wall_ground')
box('一层墙体', (0, 0, 1.20), (5.00, 5.60, 2.40), 'white', .035)
box('一层青腰线', (0, 0, .09), (5.03, 5.63, .18), 'seafoam', .02)
box('檐口白带', (0, 0, 2.345), (5.10, 5.70, .11), 'white', .025)
box('墙角护板', (-2.52, -2.82, .55), (.10, .10, 1.10), 'white', .02)
end('wall_ground')

start('wall_upper')
box('二层墙体', (0, 0, .90), (5.00, 4.30, 1.80), 'white', .035)
box('二层压顶', (0, 0, 1.83), (5.10, 4.40, .10), 'white', .025)
box('二层青腰线', (0, 0, .07), (5.03, 4.33, .14), 'seafoam', .02)
end('wall_upper')

start('floor_slab')
box('楼板', (0, 0, .10), (5.15, 5.75, .20), 'white', .04)
box('楼面铺装', (0, 0, .205), (5.00, 5.60, .03), 'mint_white', .012)
box('板下腰线', (0, 0, .015), (5.17, 5.77, .03), 'seafoam', .01)
end('floor_slab')

start('roof_terrace')
box('露台板', (0, 0, .09), (5.15, 4.475, .18), 'white', .04)
box('露台铺装', (0, 0, .185), (5.00, 4.325, .03), 'mint_white', .012)
box('板下腰线', (0, 0, .012), (5.17, 4.495, .025), 'seafoam', .01)
end('roof_terrace')

# --- columns --------------------------------------------------------------
for slug, h in (('column_short', 1.50), ('column_tall', 2.00)):
    start(slug)
    box('柱身', (0, 0, h / 2), (.26, .26, h), 'cream', .022)
    box('柱础', (0, 0, .06), (.32, .32, .12), 'white', .022)
    box('柱头', (0, 0, h - .05), (.31, .31, .10), 'white', .022)
    end(slug)

# --- railings -------------------------------------------------------------
start('parapet')
box('边框柱', (-.56, 0, .50), (.155, .155, 1.0), 'cream', .02)
box('柱帽', (-.56, 0, 1.035), (.195, .195, .065), 'white', .018)
box('上横梁', (0, 0, .94), (1.12, .09, .075), 'cream', .015)
box('实心板', (.11, 0, .60), (.60, .045, .50), 'cream', .014)
end('parapet')

start('railing_open')
box('边框柱', (-.56, 0, .43), (.145, .145, .86), 'cream', .018)
box('柱帽', (-.56, 0, .885), (.185, .185, .055), 'white', .015)
box('上横梁', (0, 0, .78), (1.12, .075, .06), 'cream', .012)
box('下横梁', (0, 0, .19), (1.12, .05, .04), 'cream', .01)
end('railing_open')

start('parapet_post')
box('端柱', (0, 0, .52), (.18, .18, 1.04), 'cream', .022)
box('端柱帽', (0, 0, 1.075), (.22, .22, .07), 'white', .02)
end('parapet_post')

start('handrail_wire')
box('钢丝', (0, -.055, 0), (1.50, .016, .016), 'silver', .005)
box('左卡扣', (-.72, 0, -.03), (.045, .07, .10), 'white', .012)
box('右卡扣', (.72, 0, -.03), (.045, .07, .10), 'white', .012)
end('handrail_wire')

# --- porch roof -----------------------------------------------------------
start('roof_slab')
box('坡屋面板', (0, 0, .10), (3.70, 3.05, .20), 'plaster', .05)
box('前檐白边', (0, -1.50, .055), (3.74, .13, .18), 'cream', .025)
box('右檐白边', (1.82, 0, .055), (.13, 3.05, .18), 'cream', .025)
box('左檐白边', (-1.82, 0, .055), (.13, 3.05, .18), 'cream', .025)
box('檐口托梁', (0, -1.41, -.06), (3.60, .17, .11), 'cream', .018)
box('后檐梁', (0, 1.38, .03), (3.60, .17, .20), 'cream', .02)
end('roof_slab')

start('roof_room')
box('小屋墙体', (0, 0, .75), (2.50, 2.90, 1.50), 'white', .03)
box('小屋腰部', (0, 0, .08), (2.53, 2.93, .16), 'seafoam', .02)
end('roof_room')

start('hip_roof')
box('顶板', (0, 0, .09), (2.78, 3.16, .18), 'plaster', .05)
loft('收分面', [(-1.39, -1.58), (1.39, -1.58), (1.39, 1.58), (-1.39, 1.58)], .17,
     [(-.92, -1.10), (.92, -1.10), (.92, 1.10), (-.92, 1.10)], .34, 'plaster', .045)
box('顶压条', (0, 0, .345), (1.86, 2.22, .05), 'plaster', .02)
end('hip_roof')

# --- windows --------------------------------------------------------------
start('window_cross')
box('青框底', (0, 0, .55), (1.50, .12, 1.10), 'sky', .02)
box('玻璃', (0, -.038, .55), (1.30, .05, .92), 'deepblue', .006)
box('中竖框', (0, -.07, .55), (.038, .022, .92), 'butter', .006)
box('中横框', (0, -.07, .55), (1.30, .022, .038), 'butter', .006)
box('上冒头', (0, -.055, 1.155), (1.54, .15, .09), 'cream', .018)
end('window_cross')

start('window_louver')
box('青框底', (0, 0, .55), (1.10, .12, 1.10), 'sky', .02)
box('玻璃', (0, -.036, .55), (.92, .05, .92), 'deepblue', .006)
for i in range(3):
    box('竖棂', (-.23 + i * .23, -.066, .55), (.05, .022, .94), 'butter', .006)
end('window_louver')

# --- fixtures -------------------------------------------------------------
start('vent_panel')
box('紫面板', (0, 0, .52), (.80, .30, 1.04), 'berry', .025)
box('上开口', (0, -.075, .74), (.60, .17, .30), 'rubber', .012)
box('下开口', (0, -.075, .34), (.60, .17, .26), 'rubber', .012)
for z in (.88, .66, .30, .14):
    ball('薄荷钮', (-.35, -.16, z), (.048, .048, .048), 'seafoam', seg=10, ring=6)
end('vent_panel')

start('cabinet')
box('柜体', (0, 0, .52), (.74, .62, 1.04), 'red', .025)
box('柜顶板', (0, 0, 1.055), (.80, .68, .07), 'coral', .02)
for i in range(5):
    box('百叶', (0, -.315, .20 + i * .135), (.58, .035, .085), 'coral', .012)
box('木托', (0, 0, .035), (.82, .70, .07), 'wood_mid', .015)
end('cabinet')

# --- solar array ----------------------------------------------------------
start('solar_panel')
box('白色底台', (0, 0, .032), (3.34, 2.76, .064), 'white', .016)
box('蓝色托盘', (0, 0, .082), (3.42, 2.84, .08), 'blue', .02)
box('白色电池床', (0, 0, .122), (3.22, 2.64, .02), 'white', .006)
for i in range(4):
    x = -.84 + i * .56
    box('框梁', (x, 0, .128), (.05, 2.84, .05), 'blue', .012)
box('边框-前', (0, -1.40, .128), (3.42, .05, .05), 'blue', .012)
box('边框-后', (0, 1.40, .128), (3.42, .05, .05), 'blue', .012)
for i in range(4):
    for j in range(3):
        x = -1.235 + i * .823
        y = -.92 + j * .92
        box('电池片', (x, y, .134), (.755, .855, .012), 'solar', .004)
end('solar_panel')

start('panel_board')
mesh('木板', [(-.60, -.38, 0), (.56, -.30, 0), (.60, .32, 0), (-.56, .40, 0),
              (-.60, -.38, .04), (.56, -.30, .04), (.60, .32, .04), (-.56, .40, .04)],
     [(0, 1, 2, 3), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)],
     'wood', .012)
end('panel_board')

# --- awning ---------------------------------------------------------------
start('awning')
box('挂杆', (0, 0, .026), (2.16, .062, .055), 'cream', .014)
for i in range(6):
    x0 = -1.02 + i * .34
    x1 = x0 + .34
    col = 'gold' if i % 2 == 0 else 'sand'
    plate('旗布', [(x0, 0), (x1, 0), (x1, -.27), (x0 + .17, -.40), (x0, -.27)],
          -.028, .028, col, .01)
box('蓝端帘', (-1.12, 0, -.20), (.10, .06, .40), 'blue', .008)
end('awning')

# --- porch deck -----------------------------------------------------------
start('porch_plank')
box('橙板', (0, 0, .025), (3.20, .315, .05), 'coral', .01)
end('porch_plank')

start('porch_step')
box('阶面', (0, 0, .07), (1.30, .34, .14), 'coral', .015)
box('阶侧', (0, .17, .07), (1.30, .045, .14), 'cream', .012)
end('porch_step')

start('clamp_block')
box('卡块', (0, 0, .10), (.16, .16, .20), 'darkwood', .015)
box('卡块顶', (0, 0, .205), (.19, .19, .03), 'wood_mid', .01)
end('clamp_block')

start('tire')
bpy.ops.mesh.primitive_torus_add(major_segments=26, minor_segments=9,
                                 major_radius=.24, minor_radius=.088,
                                 location=(0, 0, .32), rotation=(pi / 2, 0, 0))
finish(bpy.context.object, '蓝圈', 'blue', 'Matte', 0, 1, True)
box('内芯', (0, -.01, .32), (.22, .05, .22), 'ocean', .02)
end('tire')

# --- pier kit -------------------------------------------------------------
start('pier_plank')
box('浅木板', (0, 0, .028), (1.50, .338, .055), 'honey', .014)
end('pier_plank')

start('pier_rim')
box('白包边', (0, 0, .085), (1.50, .13, .19), 'white', .022)
box('包边压条', (0, 0, .19), (1.50, .15, .025), 'cream', .01)
end('pier_rim')

start('dock_post')
cyl('桩身', (0, 0, .40), .105, .84, 'bark', verts=4, r2=.09, seg=1)
box('白帽', (0, 0, .85), (.245, .245, .115), 'white', .028)
box('帽顶', (0, 0, .912), (.20, .20, .028), 'cream', .012)
end('dock_post')

# --- containers -----------------------------------------------------------
start('crate_grid')
box('箱体', (0, 0, .17), (.62, .46, .34), 'darkwood', .018)
box('箱盖框', (0, 0, .345), (.63, .47, .03), 'darkwood', .01)
for i in range(3):
    box('分格竖', (-.20 + i * .20, 0, .355), (.045, .45, .03), 'darkwood', .008)
for j in range(2):
    box('分格横', (0, -.115 + j * .23, .355), (.60, .045, .03), 'darkwood', .008)
box('底板', (0, 0, .012), (.58, .42, .025), 'darkwood', .008)
end('crate_grid')

start('crate_lattice')
box('箱身', (0, 0, .19), (.56, .56, .38), 'wood', .015)
box('上口框', (0, 0, .385), (.60, .60, .045), 'wood_light', .015)
box('内胆', (0, 0, .375), (.40, .40, .03), 'bark', .008)
for s in (-1, 1):
    for ang in (0.62, -0.62):
        box('斜撑', (0, s * .285, .19), (.55, .03, .05), 'wood_mid', .008, rot=(ang, 0, pi / 2))
        box('斜撑侧', (s * .285, 0, .19), (.55, .03, .05), 'wood_mid', .008, rot=(ang, 0, 0))
end('crate_lattice')

start('barrel')
cyl('桶身', (0, 0, .21), .17, .42, 'slate', verts=20, r2=.155, seg=2)
cyl('桶口', (0, 0, .425), .16, .04, 'steel', verts=20, seg=1)
box('提梁', (0, .17, .30), (.19, .04, .04), 'slate', .012)
end('barrel')

# --- planters -------------------------------------------------------------
start('planter_square')
box('箱底', (0, 0, .035), (.62, .36, .07), 'wood', .012)
for s in (-1, 1):
    box('侧板', (0, s * .155, .19), (.62, .05, .31), 'wood', .012)
    box('前后板', (s * .29, 0, .19), (.05, .36, .31), 'wood', .012)
box('上口左', (-.29, 0, .335), (.055, .40, .04), 'wood_light', .01)
box('上口右', (.29, 0, .335), (.055, .40, .04), 'wood_light', .01)
box('上口前', (0, -.155, .335), (.62, .045, .04), 'wood_light', .01)
box('上口后', (0, .155, .335), (.62, .045, .04), 'wood_light', .01)
box('土面', (0, 0, .30), (.52, .26, .05), 'darkwood', .01)
for s in (-1, 1):
    box('斜撑', (s * .30, 0, .19), (.44, .028, .038), 'wood', .006, rot=(.26, 0, 0))
end('planter_square')

start('planter_cream')
box('箱体', (0, 0, .18), (.50, .50, .36), 'cream', .02)
box('内口', (0, 0, .345), (.40, .40, .04), 'wood_mid', .01)
box('腰线', (0, 0, .30), (.53, .53, .045), 'sand', .012)
end('planter_cream')

start('planter_round')
cyl('盆身', (0, 0, .16), .21, .32, 'wood_mid', verts=20, r2=.17, seg=2)
cyl('盆口', (0, 0, .325), .215, .05, 'wood', verts=20, seg=1)
cyl('土面', (0, 0, .345), .165, .03, 'darkwood', verts=16, seg=1)
end('planter_round')

start('bench')
for s in (-1, 1):
    box('凳腿', (s * .42, 0, .19), (.07, .34, .38), 'white', .012)
box('凳面', (0, 0, .40), (.98, .36, .055), 'white', .012)
for i in range(3):
    box('橙板', (0, -.10 + i * .10, .44), (.92, .075, .035), 'coral', .01)
box('靠背', (0, .17, .60), (.92, .05, .34), 'white', .012)
for i in range(2):
    box('背橙板', (0, .145, .52 + i * .12), (.86, .03, .07), 'coral', .008)
end('bench')

# --- boat -----------------------------------------------------------------
start('boat')
top = [(-1.32, -.36), (-1.32, .36), (-.45, .50), (.35, .52), (1.02, .30), (1.34, 0),
       (1.02, -.30), (.35, -.52), (-.45, -.50)]
cen = Vector((0.02, 0))
inner = []
for x, y in top:
    v = Vector((x, y))
    d = (v - cen)
    inner.append(tuple(v - d.normalized() * .075))
bott = []
for x, y in top:
    v = Vector((x, y))
    d = (v - cen)
    bott.append(tuple(v - d * .17 + Vector((-.04, 0))))
binner = []
for x, y in bott:
    v = Vector((x, y))
    d = (v - cen)
    binner.append(tuple(v - d.normalized() * .065))
k = len(top)
verts = ([(x, y, .42) for x, y in top] + [(x, y, .42) for x, y in inner] +
         [(x, y, .035) for x, y in bott] + [(x, y, .095) for x, y in binner])
faces = []
for i in range(k):
    j = (i + 1) % k
    faces.append((i, j, k + j, k + i))
    faces.append((k + i, k + j, 3 * k + j, 3 * k + i))
    faces.append((2 * k + i, 2 * k + j, j, i))
faces.append(tuple(range(3 * k, 4 * k)))
faces.append(tuple(range(2 * k, 2 * k + k)))
mesh('船壳', verts, faces, 'gold', .012)
box('船底橙面', (-.05, 0, .115), (1.55, .62, .035), 'wood_light', .01)
box('艏台面', (-1.02, 0, .43), (.52, .70, .035), 'gold', .012)
box('艏舱口', (-1.02, 0, .42), (.30, .28, .03), 'wood_light', .008)
for i in range(3):
    box('紫肋板', (-.28 + i * .38, 0, .27), (.05, .52, .28), 'lavender', .008)
box('尾横板', (1.16, 0, .27), (.06, .44, .28), 'lavender', .008)
end('boat')

start('outboard')
box('机身', (0, 0, .20), (.20, .22, .40), 'lilac', .02)
box('机顶', (0, 0, .42), (.22, .24, .06), 'white', .012)
box('杆', (0, 0, -.07), (.09, .10, .18), 'steel', .012)
box('鳍', (0, .05, -.02), (.05, .20, .10), 'lilac', .01)
end('outboard')

start('oar')
cyl('杆', (0, 0, .015), .026, 1.70, 'wood_mid', verts=10, seg=1)
box('桨叶', (0, 0, 0), (.42, .11, .035), 'wood', .012)
end('oar')

start('fisherman')
box('躯干', (0, 0, .28), (.24, .16, .34), 'jade', .02)
box('肩', (0, 0, .43), (.26, .18, .06), 'jade', .015)
for s in (-1, 1):
    box('手臂', (s * .15, -.02, .28), (.065, .075, .28), 'peach', .012, rot=(0, s * .28, 0))
ball('头', (0, 0, .50), (.078, .07, .078), 'peach', seg=12, ring=8)
cyl('帽檐', (0, 0, .555), .195, .032, 'sand', verts=18, seg=1)
cyl('帽冠', (0, 0, .60), .115, .085, 'sand', verts=18, r2=.085, seg=1)
box('腰带', (0, 0, .17), (.25, .17, .05), 'jade', .012)
end('fisherman')

start('figure_white')
box('底座', (0, 0, .03), (.20, .17, .06), 'mint_white', .01)
cyl('裙摆', (0, 0, .17), .11, .24, 'sage_gray', verts=14, r2=.085, seg=1)
box('上身', (0, 0, .32), (.13, .11, .12), 'white', .012)
ball('头', (0, 0, .41), (.05, .048, .05), 'white', seg=10, ring=6)
cyl('尖帽', (0, 0, .48), .092, .13, 'rubber', verts=12, r2=.008, seg=1)
for s in (-1, 1):
    box('手', (s * .085, -.02, .30), (.04, .04, .12), 'white', .008)
end('figure_white')

start('buoy_float')
cyl('底座', (0, 0, .03), .16, .06, 'sky', verts=16, seg=2)
ball('浮球', (0, 0, .12), (.13, .13, .10), 'pink', seg=14, ring=8)
cyl('顶圈', (0, 0, .205), .05, .03, 'white', verts=12, seg=1)
end('buoy_float')

# --- flora ----------------------------------------------------------------
start('leaf_cluster')
LEAVES = [(-.42, .30, .125, 'leaf'), (.30, .40, .13, 'leaf_mid'),
          (-.18, -.40, .12, 'leaf'), (.26, -.34, .115, 'leaf_light'),
          (.02, .10, .14, 'leaf_mid'), (-.34, -.10, .105, 'leaf_light'),
          (.42, .04, .115, 'leaf'), (-.04, .44, .105, 'leaf_light'),
          (.14, -.14, .12, 'leaf'), (-.24, .22, .10, 'leaf_mid'),
          (.22, -.18, .105, 'leaf')]
for dx, dy, w, col in LEAVES:
    base = Vector((dx * .10, dy * .10, .085))
    tip = Vector((dx * 1.18, dy * 1.18, .085 + .11 + abs(dx) * .06))
    blade('阔叶', base, tip, w, .052, col)
cyl('叶柄', (0, 0, .07), .032, .14, 'leaf_dark', verts=8, seg=1)
end('leaf_cluster')

start('vine')
wire('藤茎', [(0, 0, .02), (.02, .01, -.18), (-.02, 0, -.34), (0, .01, -.50)], .009, 'leaf_dark')
for i in range(7):
    z = -.02 - i * .072
    s = 1 if i % 2 == 0 else -1
    ball('藤叶', (s * .055, 0, z), (.052, .034, .066), 'leaf' if i % 2 else 'leaf_mid', seg=10, ring=6)
for z in (-.14, -.30, -.45):
    ball('粉点', (0, -.045, z), (.032, .028, .032), 'pink', seg=8, ring=5)
end('vine')


def bloom(slug, col, center, count, pw, pl, th):
    start(slug)
    for i in range(count):
        a = 2 * pi * i / count + .3
        d = Vector((math.cos(a), math.sin(a), .16)).normalized()
        base = Vector((math.cos(a), math.sin(a), 0)) * .055
        tip = base + d * pl
        blade('花瓣', base, tip, pw, .026, col)
    ball('花心', (0, 0, .026), (th * 1.5, th * 1.5, th), center, seg=10, ring=6)
    ball('花托', (0, 0, -.04), (.042, .042, .03), 'leaf', seg=8, ring=5)
    end(slug)


bloom('cosmos', 'pink', 'rose', 5, .078, .175, .048)
bloom('daisy', 'white', 'butter', 6, .068, .160, .042)

start('goldflower')
ball('花苞', (0, 0, .10), (.058, .058, .052), 'butter', seg=10, ring=6)
for i in range(3):
    a = 2 * pi * i / 3
    blade('萼片', (0, 0, .03), (math.cos(a) * .095, math.sin(a) * .095, .09), .042, .018, 'leaf_mid')
cyl('花梗', (0, 0, .015), .012, .05, 'leaf_dark', verts=8, seg=1)
end('goldflower')

# ================================================================ assembly
ZP = 0.60  # pier deck top

# house block
inst('base_slab', (-1.475, .05, -.43))
for x in (-3.60, -2.10, -.60, .70):
    for y in (-2.38, 2.55):
        inst('stilt', (x, y, -1.40))

inst('wall_ground', (-1.55, .15, .0))
inst('floor_slab', (-1.55, .15, 2.40))
inst('wall_upper', (-1.55, .80, 2.60))
inst('roof_terrace', (-1.55, .7875, 4.40))

inst('window_cross', (-4.06, -.55, .62), rot=(0, 0, -pi / 2))
inst('window_cross', (-.85, -2.66, .62))
inst('window_cross', (-3.36, -2.66, .62), scale=.8)
inst('window_cross', (-4.06, 1.85, .62), rot=(0, 0, -pi / 2), scale=.8)
inst('vent_panel', (-4.07, 1.35, 2.72), rot=(0, 0, -pi / 2))
inst('window_louver', (-4.06, 2.35, 2.78), rot=(0, 0, -pi / 2), scale=.85)
inst('cabinet', (-2.45, -2.33, 0.0))
inst('crate_lattice', (-1.62, -2.20, 0.0))
inst('crate_lattice', (-3.05, -2.22, 0.0), rot=(0, 0, .35), scale=.85)
inst('barrel', (-3.42, -1.15, 0.0))

# level-2 terrace planting strip + open railing
for i in range(4):
    inst('railing_open', (-3.42 + i * 1.12, -2.68, 2.60))
inst('parapet_post', (.98, -2.68, 2.60))
for i in range(2):
    inst('railing_open', (-4.10, -2.10 + i * 1.12, 2.60), rot=(0, 0, pi / 2))
    inst('parapet_post', (-4.10, -1.40 + i * 1.12, 2.60), rot=(0, 0, pi / 2))

# roof parapet on the terrace edges
for i in range(4):
    inst('parapet', (-3.42 + i * 1.12, -1.40, 4.58))
inst('parapet_post', (.98, -1.40, 4.58))
for i in range(2):
    inst('parapet', (-4.10, -.84 + i * 1.12, 4.58), rot=(0, 0, pi / 2))
inst('parapet', (1.00, -.84, 4.58), rot=(0, 0, -pi / 2))
inst('parapet_post', (-4.10, 1.40, 4.58), rot=(0, 0, pi / 2))
inst('parapet_post', (1.00, .28, 4.58), rot=(0, 0, -pi / 2))

# roof room + hip roof + louvre windows
inst('roof_room', (-2.53, 1.40, 4.58))
inst('hip_roof', (-2.53, 1.40, 6.08))
inst('window_louver', (-3.30, -.06, 4.72), scale=.9)
inst('window_louver', (-1.76, -.06, 4.72), scale=.9)
inst('window_louver', (-3.80, 1.30, 4.74), rot=(0, 0, -pi / 2), scale=.9)
inst('window_louver', (-3.80, 2.10, 4.74), rot=(0, 0, -pi / 2), scale=.9)

# pavilion stage + columns
inst('stage_base', (2.65, -1.72, .0))
for i in range(9):
    inst('porch_plank', (1.24 + i * .355, -1.72, .95), rot=(0, 0, pi / 2))
inst('porch_step', (2.65, -3.20, .81))
inst('porch_step', (2.65, -3.06, .60))
for x in (1.20, 3.70):
    inst('column_short', (x, -2.40, .95), scale=1.0)
    inst('column_tall', (x, -.40, .95))

# porch roof + solar array (tilted whole assembly)
roof_c = Vector((2.65, -1.35, 2.88))
inst('roof_slab', roof_c, rot=(TILT, 0, 0))
inst('solar_panel', roof_c + Vector((0, -.14, .235)), rot=(TILT, 0, 0))
inst('panel_board', roof_c + Vector((.04, .10, .40)), rot=(TILT, 0, .30))
inst('awning', (2.65, -2.90, 2.30))
inst('figure_white', (2.85, -1.95, .95), scale=.78)
for x, y in [(1.48, -2.96), (3.78, -2.90), (4.00, -.95)]:
    inst('tire', (x, y, .72), rot=(0, 0, pi / 2))
for x in (1.26, 2.30, 3.34, 4.00):
    inst('clamp_block', (x, -3.02, .95))
for x, y in [(1.60, -1.25), (3.90, -2.35)]:
    inst('planter_round', (x, y, .95))

# pier kit -----------------------------------------------------------------
PL = .375


def deck(x0, x1, y0, y1, z=ZP, sides=('S', 'E', 'N', 'W'), along='x', post_pitch=1.5):
    w = abs(y1 - y0) if along == 'x' else abs(x1 - x0)
    assert abs(w - 1.5) < 1e-6, ('deck width must be 1.5', x0, x1, y0, y1)
    if along == 'x':
        n = int(round(abs(x1 - x0) / PL))
        step = (x1 - x0) / n
        for i in range(n):
            inst('pier_plank', (x0 + step * (i + .5), (y0 + y1) / 2, z), rot=(0, 0, pi / 2))
    else:
        n = int(round(abs(y1 - y0) / PL))
        step = (y1 - y0) / n
        for i in range(n):
            inst('pier_plank', ((x0 + x1) / 2, y0 + step * (i + .5), z))
    edges = {'S': ((x0, y0), (x1, y0), 0, (0, 1)),
             'N': ((x0, y1), (x1, y1), 0, (0, -1)),
             'W': ((x0, y0), (x0, y1), pi / 2, (1, 0)),
             'E': ((x1, y0), (x1, y1), pi / 2, (-1, 0))}
    for side in sides:
        a, b, rotz, inward = edges[side]
        length = math.dist(a, b)
        cnt = max(1, int(round(length / 1.5)))
        seg = length / cnt
        ux, uy = (b[0] - a[0]) / length, (b[1] - a[1]) / length
        for i in range(cnt):
            t = (i + .5) * seg
            inst('pier_rim', (a[0] + ux * t + inward[0] * .068,
                              a[1] + uy * t + inward[1] * .068, z - .025), rot=(0, 0, rotz))
        pn = max(1, int(round(length / post_pitch)))
        for i in range(pn + 1):
            t = i * (length / pn)
            inst('dock_post', (a[0] + ux * t - inward[0] * .11,
                               a[1] + uy * t - inward[1] * .11, z - .025))


# main pier east to the boat
deck(3.30, 7.05, -4.15, -2.65, sides=('S', 'E', 'N'))
# foreground pier in front of the stage
deck(1.05, 2.55, -6.40, -2.30, along='y', sides=('E', 'W', 'N'))
# left spur crossing it
deck(-1.95, 1.05, -5.75, -4.25, sides=('S', 'N', 'W'))
# end bay turning west at the bottom
deck(-.45, 2.55, -7.90, -6.40, sides=('S', 'W', 'N'))

# handrail cables along the foreground pier
for i in range(3):
    inst('handrail_wire', (2.46, -5.9 + i * 1.5, ZP + .60), rot=(0, 0, pi / 2))
for i in range(2):
    inst('handrail_wire', (4.5 + i * 1.5, -4.28, ZP + .60))
    inst('handrail_wire', (4.5 + i * 1.5, -2.55, ZP + .60))

# pier props
inst('crate_grid', (-.05, -7.30, ZP), rot=(0, 0, .12))
inst('planter_cream', (1.05, -7.30, ZP), rot=(0, 0, .1))
inst('planter_round', (-1.60, -5.05, ZP))
inst('crate_lattice', (1.75, -6.55, ZP), rot=(0, 0, -.2), scale=.9)
inst('bench', (-1.15, -4.62, ZP), rot=(0, 0, pi / 2))

# boat alongside the pier head
inst('boat', (7.90, -4.95, .16), rot=(0, 0, math.radians(-8)))
inst('outboard', (9.17, -5.02, .44), rot=(0, 0, math.radians(78)))
inst('oar', (7.70, -4.75, .78), rot=(0, math.radians(74), math.radians(20)))
inst('oar', (7.97, -5.20, .78), rot=(0, math.radians(-66), math.radians(12)))
inst('fisherman', (7.77, -4.92, .50))
inst('buoy_float', (7.40, -5.15, .48))
inst('barrel', (7.25, -5.35, .44), rot=(0, 0, .4))

# flora --------------------------------------------------------------------
# level-2 terrace: a dense planter row behind the open railing
for i, x in enumerate([-3.66, -3.00, -2.34, -1.68, -1.02, -.36]):
    y = -2.36
    inst('planter_square', (x, y, 2.62), rot=(0, 0, .03 * i))
    inst('leaf_cluster', (x, y + .02, 2.90), rot=(0, 0, i * 1.3), scale=.9)
    inst('cosmos', (x - .19, y - .10, 3.10), rot=(.26, 0, i), scale=1.05)
    inst('daisy', (x + .17, y - .06, 3.12), rot=(.26, 0, i * 2), scale=1.0)
    inst('cosmos', (x + .02, y + .10, 3.16), rot=(.26, 0, i * 2.4), scale=.9)
    inst('daisy', (x - .02, y - .18, 3.08), rot=(.26, 0, i * 3), scale=.85)
    inst('cosmos', (x + .20, y + .12, 3.14), rot=(.26, 0, i * 1.1), scale=.8)
    inst('daisy', (x - .22, y + .06, 3.12), rot=(.26, 0, i * 2.8), scale=.8)
    if i % 2 == 0:
        inst('goldflower', (x + .12, y - .16, 3.02), rot=(.26, 0, i * 3), scale=.8)

# roof terrace: planters along the front parapet
for i, x in enumerate([-3.66, -2.98, -2.30, -1.62, -.94, -.30]):
    y = -1.24
    inst('planter_square', (x, y, 4.58), rot=(0, 0, -.04 * i))
    inst('leaf_cluster', (x, y + .02, 4.86), rot=(0, 0, i * .9), scale=.88)
    inst('cosmos', (x - .16, y - .10, 5.06), rot=(.26, 0, i * 1.7), scale=1.0)
    inst('daisy', (x + .16, y - .05, 5.08), rot=(.26, 0, i), scale=.95)
    inst('cosmos', (x + .04, y + .08, 5.10), rot=(.26, 0, i * 2.2), scale=.85)
    inst('daisy', (x - .04, y + .12, 5.12), rot=(.26, 0, i * 3), scale=.82)

# blooms spilling over the level-2 railing
for i, x in enumerate([-3.36, -2.02, -.68]):
    inst('cosmos', (x, -2.74, 3.06), rot=(.26, 0, i * 1.3), scale=.9)
    inst('daisy', (x + .34, -2.74, 3.04), rot=(.26, 0, i * 2.1), scale=.85)

# wall-hung window box under the left window
inst('planter_square', (-4.40, -.55, .30), rot=(0, 0, pi / 2))
inst('leaf_cluster', (-4.42, -.55, .60), scale=.9)
inst('cosmos', (-4.50, -.72, .80), rot=(.26, 0, .4), scale=1.0)
inst('daisy', (-4.46, -.38, .82), rot=(.26, 0, 1.1), scale=.95)
inst('cosmos', (-4.44, -.55, .86), rot=(.26, 0, 1.9), scale=.85)

# eave garland on the porch roof front edge
for i in range(14):
    x = 1.00 + i * .26
    z = 2.76
    inst('leaf_cluster', (x, -2.82, z), rot=(0, 0, i * .8), scale=.55)
    inst('cosmos' if i % 2 == 0 else 'daisy', (x - .02, -2.86, z + .14), rot=(.26, 0, i * 1.7), scale=.72)
    if i % 3 == 0:
        inst('goldflower', (x + .07, -2.84, z + .10), scale=.7)

# hanging vines down the left face and slab edges
for i, (x, y, z, s) in enumerate([(-4.10, -2.52, 2.44, 1.15), (-4.10, -1.92, 2.44, 1.0),
                                  (-4.10, -.30, 2.44, .95), (-4.10, 1.10, 4.42, 1.15),
                                  (-4.10, 1.80, 4.42, 1.05), (-2.70, -1.42, 4.40, 1.0),
                                  (-1.30, -1.42, 4.40, .95), (-2.00, -2.74, 2.60, .95),
                                  (-1.10, -2.74, 2.60, .9), (-3.20, -2.74, 2.60, 1.0)]):
    inst('vine', (x, y, z), rot=(0, 0, i * .7), scale=s)

# pot clusters on the stage
for x, y, z in [(1.62, -1.02, .95), (3.60, -1.98, .95), (2.05, -2.38, .95)]:
    inst('planter_round', (x, y, z))
    inst('leaf_cluster', (x, y, z + .30), rot=(0, 0, x), scale=.72)
    inst('cosmos', (x, y - .05, z + .42), rot=(.26, 0, x), scale=.85)

# ================================================================ display env
current = support
box('展示地平面', (0, 0, -2.4), (200, 200, .1), 'ice', .01).hide_render = True

world = bpy.data.worlds.new('纯白棚拍')
scene.world = world
world.use_nodes = True
wn = world.node_tree.nodes
wl = world.node_tree.links
bg = wn['Background']
bg.inputs[0].default_value = (.95, .96, .97, 1)
bg.inputs[1].default_value = .30
cam_bg = wn.new('ShaderNodeBackground')
cam_bg.inputs[0].default_value = (1, 1, 1, 1)
cam_bg.inputs[1].default_value = 2.0 ** -0.10
lp = wn.new('ShaderNodeLightPath')
mix = wn.new('ShaderNodeMixShader')
wl.new(lp.outputs['Is Camera Ray'], mix.inputs[0])
wl.new(bg.outputs[0], mix.inputs[1])
wl.new(cam_bg.outputs[0], mix.inputs[2])
wl.new(mix.outputs[0], wn['World Output'].inputs[0])


def aim(obj, point):
    obj.rotation_euler = (Vector(point) - obj.location).to_track_quat('-Z', 'Y').to_euler()


LIGHTS = [('主光', (-9, -11, 15), 900, 11, (1, .96, .89)),
          ('侧补光', (11, -6, 9), 260, 10, (.90, .95, 1)),
          ('轮廓光', (-3, 11, 13), 300, 9, (1, .97, .90)),
          ('门廊补光', (2.6, -4.4, 1.9), 80, 2.6, (1, .95, .86))]
for name, loc, power, size, col in LIGHTS:
    data = bpy.data.lights.new(name, 'AREA')
    data.energy = power
    data.shape = 'DISK'
    data.size = size
    data.color = col
    o = bpy.data.objects.new(name, data)
    support.objects.link(o)
    o.location = loc
    aim(o, (1.2, -1.5, 2.2))

sun_data = bpy.data.lights.new('主太阳', 'SUN')
sun_data.energy = 2.6
sun_data.angle = math.radians(22)
sun_data.color = (1, .95, .86)
sun = bpy.data.objects.new('主太阳', sun_data)
support.objects.link(sun)
sun.location = (-9, -11, 16)
aim(sun, (1.0, -1.0, 1.6))

cam_data = bpy.data.cameras.new('参考图等距镜头')
cam = bpy.data.objects.new('参考图等距镜头', cam_data)
support.objects.link(cam)
cam_data.type = 'ORTHO'
scene.camera = cam
cam.location = (-26, -26, 26)
aim(cam, (0, 0, 2.2))

# frame the diorama by projecting the instance bounds into camera space
cmap = {c['collection']['component_id']: c for c in components.values()}
pts = []
for r in records:
    c = cmap[r['component_id']]
    b = c['bounds']
    s = r['scale'][0]
    m = (Matrix.Translation(Vector(r['position_m'])) @
         Euler(r['rotation_euler_xyz_rad'], 'XYZ').to_matrix().to_4x4() @
         Matrix.Scale(s, 4))
    for sx in (-.5, .5):
        for sy in (-.5, .5):
            for sz in (0, 1):
                pts.append(m @ Vector((sx * b[0], sy * b[1], sz * b[2])))
if pts:
    right = cam.rotation_euler.to_matrix() @ Vector((1, 0, 0))
    up = cam.rotation_euler.to_matrix() @ Vector((0, 1, 0))
    xs = [(p - cam.location).dot(right) for p in pts]
    ys = [(p - cam.location).dot(up) for p in pts]
    aspect = 1440 / 1080
    wspan = max(xs) - min(xs)
    hspan = max(ys) - min(ys)
    margin = float(os.environ.get('SEA_FRAME_MARGIN', 1.02))
    cam_data.ortho_scale = max(wspan, hspan * aspect) * margin
    dx = (max(xs) + min(xs)) / 2
    dy = (max(ys) + min(ys)) / 2
    cam.location = cam.location + right * dx + up * dy
    aim(cam, cam.location - cam.rotation_euler.to_matrix() @ Vector((0, 0, 1)) * 10)
    print('FRAME', round(wspan, 2), round(hspan, 2), 'ortho', round(cam_data.ortho_scale, 2))

scene.render.engine = 'CYCLES'
scene.cycles.samples = 24 if '--quick' in sys.argv else 64
scene.cycles.use_denoising = True
scene.cycles.max_bounces = 6
scene.render.resolution_x = 960 if '--quick' in sys.argv else 1440
scene.render.resolution_y = 720 if '--quick' in sys.argv else 1080
scene.render.resolution_percentage = 100
scene.view_settings.view_transform = 'Standard'
scene.view_settings.look = 'None'
scene.view_settings.exposure = -.10
scene.render.film_transparent = True
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'

# Warm studio grade applied to the geometry only; the plate's backdrop stays pure white.
GRADE = (1.0, .945, .82)   # linear per-channel gain for R, G, B
ng = bpy.data.node_groups.new('SEA_成片暖调', 'CompositorNodeTree')
ng.interface.new_socket(name='Image', in_out='OUTPUT', socket_type='NodeSocketColor')
scene.compositing_node_group = ng
scene.use_nodes = True
rl = ng.nodes.new('CompositorNodeRLayers')
cur = ng.nodes.new('CompositorNodeCurveRGB')
cm = cur.mapping
cm.initialize()
for ch, top in ((1, GRADE[0]), (2, GRADE[1]), (3, GRADE[2])):
    cm.curves[ch].points[1].location = (1.0, top)
cm.update()
over = ng.nodes.new('CompositorNodeAlphaOver')
over.inputs['Background'].default_value = (2.0 ** 0.10,) * 3 + (1,)
gout = ng.nodes.new('NodeGroupOutput')
ng.links.new(rl.outputs['Image'], cur.inputs['Image'])
ng.links.new(cur.outputs['Image'], over.inputs['Foreground'])
ng.links.new(over.outputs['Image'], gout.inputs[0])

for screen in bpy.data.screens:
    for a in screen.areas:
        if a.type == 'VIEW_3D':
            a.spaces.active.region_3d.view_perspective = 'CAMERA'
            a.spaces.active.shading.type = 'MATERIAL'

# ================================================================ packages
route = json.loads((R / 'assets/registry/ledger_index.json').read_text())['domains']['scenes']['ledger']
catalog = []
for item in plan['components']:
    slug = item['slug']
    c = components[slug]
    dest = D / 'component_packages' / slug
    dest.mkdir(parents=True, exist_ok=True)
    filepath = dest / (slug + '.blend')
    geometry = []
    for o in c['meshes']:
        geometry.append({'vertices': [[round(float(v), 5) for v in p.co] for p in o.data.vertices],
                         'polygons': [list(p.vertices) for p in o.data.polygons]})
    fingerprint = hashlib.sha256(json.dumps(geometry, sort_keys=True).encode()).hexdigest()
    entry = {**item,
             'collection': c['collection'].name,
             'root_object': 'ROOT_' + slug,
             'component_blend': str(filepath.relative_to(R)),
             'bounds_size_m': [round(v, 5) for v in c['bounds']],
             'local_origin': [0, 0, 0],
             'source_anchor_shift_m': [round(v, 5) for v in c['anchor']],
             'instance_count': sum(r['component_id'] == item['component_id'] for r in records),
             'palette_uv_layer': 'PaletteUV',
             'palette_path': str(palette_path.relative_to(R)),
             'material_roles': [m.name for m in materials.values()],
             'collision_owner': 'godot_wrapper_pending',
             'geometry_fingerprint': fingerprint,
             'source_sha256': None,
             'asset_ledger': route + '#' + item['component_id'],
             'license': 'pending_user_reference_rights_review',
             'runtime_status': 'not_integrated',
             'source_package_meshes': [o.name for o in c['meshes']]}
    (dest / 'asset_manifest.json').write_text(json.dumps(entry, ensure_ascii=False, indent=2) + '\n')
    catalog.append(entry)

# Standalone packages are produced afterwards by finalize_packages.py --version v004.
(D / 'component_catalog.json').write_text(
    json.dumps({'schema': 'sea.scene.component_catalog', 'components': catalog},
               ensure_ascii=False, indent=2) + '\n')
(D / 'component_instances.json').write_text(
    json.dumps({'schema': 'sea.scene.component_instances',
                'source_blend': 'solar_flower_house.blend',
                'coordinate_contract': {'source_space': 'blender_scene_local', 'plane': 'XY',
                                        'up': '+Z', 'rotation': 'Euler XYZ radians; includes solar roof tilt',
                                        'godot_mapping': '(x,y,z) -> (x,z,-y)',
                                        'deck_top_z_m': 0.95, 'pier_top_z_m': 0.60,
                                        'scale_policy': 'uniform only; pier rims tile on a 1.5 m module, no stretched architecture'},
                'instances': records}, ensure_ascii=False, indent=2) + '\n')
(D / 'component_tree.txt').write_text(
    '\n'.join(x['category'] + ' / ' + x['slug'] + ' / ' + str(x['instance_count']) + ' instances'
              for x in catalog) + '\n')

bpy.context.window.scene = scene
img.filepath = bpy.path.relpath(str(palette_path), start=str(D))
scene['feature_id'] = 'SEA-ASSET'
scene['source_stage'] = 'source_created_runtime_pending'
scene['reference_sha256'] = plan['reference_sha256']
bpy.ops.wm.save_as_mainfile(filepath=str(OUT), compress=True)
print('SEA_SOURCE_BUILT', len(catalog), 'components', len(records), 'instances', flush=True)
if '--render' in sys.argv:
    scene.render.filepath = str(W / ('previews/build_%s.png' % ('quick' if '--quick' in sys.argv else 'full')))
    bpy.ops.render.render(write_still=True)
print('SEA_BUILD_COMPLETE', flush=True)
