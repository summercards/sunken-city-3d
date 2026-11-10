"""WB003 v001 shared helpers. exec()'d by each build step inside the live Blender session."""
import bpy, bmesh, json, math, random, hashlib
from pathlib import Path
from mathutils import Vector, Matrix
R = Path('D:/projects/sea')
D = R / 'art_source/scenes/water_building_003/v001'
W = Path('D:/projects/sea-work/water_building_003/v001')
PAL = R / 'art_source/shared/palettes/sea_cabin_timber_8x8_512.png'
PREFIX = 'SEA-SCENE-WATER-BUILDING-003'
PX = 47.0          # reference px per metre (ground pitch 5.1 m == 240 px)
CX = 530.0
GY = 845.0


def X(px):
    return (px - CX) / PX


def Z(py):
    return (GY - py) / PX


def S(p):
    return p / PX


def scene():
    return bpy.data.scenes['WB003_v001']


def _init_scene():
    if 'WB003_v001' in bpy.data.scenes:
        return
    sc = bpy.data.scenes.new('WB003_v001')
    win = bpy.context.window or next(iter(bpy.context.window_manager.windows))
    win.scene = sc
    for s in list(bpy.data.scenes):
        if s != sc:
            bpy.data.scenes.remove(s)
    sc.unit_settings.system = 'METRIC'


_init_scene()
sc = scene()
cells = {c['name']: c for c in json.loads(PAL.with_suffix('.json').read_text(encoding='utf-8'))['cells']}
image = bpy.data.images.load(str(PAL), check_existing=True)
roles = {}
for role, rough, metal in [('SEA_Matte', .78, 0), ('SEA_Metal', .55, .25), ('SEA_Gloss', .3, 0)]:
    nm = 'WB003_' + role
    m = bpy.data.materials.get(nm)
    if m is None:
        m = bpy.data.materials.new(nm)
        m['semantic_role'] = role
        m.use_nodes = True
        bs = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
        bs.inputs['Roughness'].default_value = rough
        bs.inputs['Metallic'].default_value = metal
        uv = m.node_tree.nodes.new('ShaderNodeUVMap')
        uv.uv_map = 'PaletteUV'
        tx = m.node_tree.nodes.new('ShaderNodeTexImage')
        tx.image = image
        tx.interpolation = 'Closest'
        tx.extension = 'EXTEND'
        m.node_tree.links.new(uv.outputs['UV'], tx.inputs['Vector'])
        m.node_tree.links.new(tx.outputs['Color'], bs.inputs['Base Color'])
    roles[role] = m

top = {}
for key, name in [('structure', '01_Architecture'), ('furnishing', '02_Fixtures'), ('plant', '03_SeparateVegetation'), ('display', '90_DisplaySupport')]:
    cn = 'WB003_' + name
    c = bpy.data.collections.get(cn) or bpy.data.collections.new(cn)
    if c.name not in sc.collection.children:
        sc.collection.children.link(c)
    top[key] = c

if 'cols' not in bpy.app.driver_namespace:
    bpy.app.driver_namespace['cols'] = {}
    bpy.app.driver_namespace['catalog'] = []
    bpy.app.driver_namespace['instances'] = []
    bpy.app.driver_namespace['witness'] = []
cols = bpy.app.driver_namespace['cols']
catalog = bpy.app.driver_namespace['catalog']
instances = bpy.app.driver_namespace['instances']
witness = bpy.app.driver_namespace['witness']
_cur = {'c': None}
PLAN = json.loads((D / 'component_plan.json').read_text(encoding='utf-8'))
by = {c['key']: c for c in PLAN['components']}


def uvpaint(o, color, role, smooth=False):
    me = o.data
    assert color in cells, color
    cell = cells[color]
    cx = (cell['column'] + .5) / 8
    cy = 1 - (cell['row'] + .5) / 8
    for u in list(me.uv_layers):
        me.uv_layers.remove(u)
    u = me.uv_layers.new(name='PaletteUV')
    u.active_render = True
    for f in me.polygons:
        f.use_smooth = smooth
        for j, li in enumerate(f.loop_indices):
            a = 2 * math.pi * j / f.loop_total
            u.data[li].uv = (cx + .028 * math.cos(a), cy + .028 * math.sin(a))
    me.materials.clear()
    me.materials.append(roles[role])
    o['palette_color'] = color
    o['semantic_role'] = role
    return o


def make(name, vs, fs, color='plaster', role='SEA_Matte', bevel=0, rho=None, smooth=False, organic=False, seg=1, tilt=None):
    me = bpy.data.meshes.new('WB003_' + name)
    me.from_pydata(vs, [], fs)
    me.update()
    o = bpy.data.objects.new('WB003_' + name, me)
    _cur['c'].objects.link(o)
    if bevel:
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=seg, affect='EDGES', clamp_overlap=True)
        bm.to_mesh(me)
        bm.free()
        me.update()
    if not organic and rho:
        lo = Vector(tuple(min(v.co[a] for v in me.vertices) for a in range(3)))
        hi = Vector(tuple(max(v.co[a] for v in me.vertices) for a in range(3)))
        ext = hi - lo
        axis = max(range(3), key=lambda a: ext[a])
        cen = (lo + hi) * .5
        for v in me.vertices:
            t = (v.co[axis] - lo[axis]) / ext[axis]
            for j in range(3):
                if j != axis:
                    v.co[j] = cen[j] + (v.co[j] - cen[j]) * (1 - rho * t)
        o['actual_taper_axis'] = 'xyz'[axis]
        o['actual_rho'] = rho
    o['bevel_width_m'] = bevel
    o['bevel_segments'] = seg if bevel else 0
    me.update()
    return uvpaint(o, color, role, smooth)


def box(n, p, s, c='plaster', role='SEA_Matte', b=0, r=.02, seg=1, rot=None):
    """Axis box centred at p (centre), size s. rot=(rx,ry,rz) rotates about the box bottom-centre."""
    v = [(q[0] * s[0] / 2, q[1] * s[1] / 2, q[2] * s[2] / 2 + s[2] / 2) for q in
         [(-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1), (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]]
    # p is given as bottom-centre in z: p=(x,y,z_bottom)
    if rot:
        M = Matrix.Rotation(rot[2], 3, 'Z') @ Matrix.Rotation(rot[1], 3, 'Y') @ Matrix.Rotation(rot[0], 3, 'X')
        v = [tuple(M @ Vector(q)) for q in v]
    v = [(q[0] + p[0], q[1] + p[1], q[2] + p[2]) for q in v]
    return make(n, v, [(3, 2, 1, 0), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7), (4, 5, 6, 7)], c, role, b, r, seg=seg)


def tube(n, pts, rad, c='bark', sides=6, organic=True, taper=.65, role='SEA_Matte', rad_end=None):
    pts = [Vector(p) for p in pts]
    vs = []
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        up = Vector((0, 0, 1)) if abs(t.z) < .9 else Vector((0, 1, 0))
        u = t.cross(up).normalized()
        v = t.cross(u).normalized()
        f = i / (len(pts) - 1)
        rr = rad * (1 - taper * f) if rad_end is None else rad + (rad_end - rad) * f
        vs.extend(tuple(p + rr * (u * math.cos(2 * math.pi * j / sides) + v * math.sin(2 * math.pi * j / sides))) for j in range(sides))
    fs = [tuple(reversed(range(sides))), tuple((len(pts) - 1) * sides + j for j in range(sides))] + \
         [(i * sides + j, i * sides + (j + 1) % sides, (i + 1) * sides + (j + 1) % sides, (i + 1) * sides + j) for i in range(len(pts) - 1) for j in range(sides)]
    o = make(n, vs, fs, c, role, smooth=True, organic=True)
    o['d_ratio'] = (1 - taper) if rad_end is None else rad_end / rad
    return o


def blob(n, p, s, color='leaf_mid', detail=1, jitter=.13):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=detail, radius=1)
    vs = []
    for v in bm.verts:
        a = v.co
        f = 1 + random.uniform(-jitter, jitter)
        vs.append(tuple(p[j] + a[j] * s[j] * f for j in range(3)))
    fs = [tuple(v.index for v in f.verts) for f in bm.faces]
    bm.free()
    return make(n, vs, fs, color, smooth=True, organic=True)


def part(key, fn):
    e = by[key]
    if key in cols:
        raise RuntimeError('component exists ' + key)
    c = bpy.data.collections.new(e['asset_id'])
    c['asset_id'] = e['asset_id']
    c['kind'] = e['kind']
    _cur['c'] = c
    sc.collection.children.link(c)
    fn()
    obs = [o for o in c.objects if o.type == 'MESH']
    pts = [v.co for o in obs for v in o.data.vertices]
    lo = Vector(tuple(min(v[a] for v in pts) for a in range(3)))
    hi = Vector(tuple(max(v[a] for v in pts) for a in range(3)))
    pivot = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
    for o in obs:
        o.data.transform(Matrix.Translation(-pivot))
        o['component_key'] = key
        o['asset_id'] = e['asset_id']
    c.instance_offset = (0, 0, 0)
    sc.collection.children.unlink(c)
    cols[key] = c
    tri = 0
    h = hashlib.sha256()
    for o in obs:
        o.data.calc_loop_triangles()
        tri += len(o.data.loop_triangles)
        for v in o.data.vertices:
            h.update((','.join(format(float(x), '.6f') for x in v.co) + ';').encode())
    row = dict(e, collection=c.name, design_pivot=list(pivot), bounds_size=list(hi - lo), triangles=tri,
               polygons=sum(len(o.data.polygons) for o in obs), meshes=len(obs),
               material_roles=sorted({o['semantic_role'] for o in obs}), geometry_fingerprint=h.hexdigest(),
               component_source='art_source/scenes/water_building_003/v001/component_packages/%s/%s.blend' % (key, key))
    catalog.append(row)
    print('COMPONENT', key, tri, [round(x, 2) for x in (hi - lo)])


def put(k, p=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    e = next(x for x in catalog if x['key'] == k)
    n = sum(x['key'] == k for x in instances) + 1
    o = bpy.data.objects.new('WB003_I_%s_%03d' % (k, n), None)
    o.instance_type = 'COLLECTION'
    o.instance_collection = cols[k]
    o.rotation_euler = rot
    o.scale = scale
    o.location = Vector(p) + o.rotation_euler.to_matrix() @ Vector(e['design_pivot'])
    top[e['group']].objects.link(o)
    instances.append({'name': o.name, 'key': k, 'asset_id': e['asset_id'], 'position': list(o.location),
                      'rotation_euler_xyz': list(rot), 'scale': list(scale)})
    return o


def frustum(n, c, bot, top, z0, h, color='roof', role='SEA_Matte', b=0, r=.03, off=(0, 0), seg=1, thick=None):
    """Solid frustum: bottom rect `bot`=(sx,sy) at z0, top rect `top` at z0+h, centre c=(x,y). off shifts the top (for asymmetric slopes)."""
    def rect(sx, sy, z, ox):
        return [(c[0] + ox[0] - sx / 2, c[1] + ox[1] - sy / 2, z), (c[0] + ox[0] + sx / 2, c[1] + ox[1] - sy / 2, z),
                (c[0] + ox[0] + sx / 2, c[1] + ox[1] + sy / 2, z), (c[0] + ox[0] - sx / 2, c[1] + ox[1] + sy / 2, z)]
    vs = rect(bot[0], bot[1], z0, (0, 0)) + rect(top[0], top[1], z0 + h, off)
    fs = [(3, 2, 1, 0), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7), (4, 5, 6, 7)]
    return make(n, vs, fs, color, role, b, None, seg=seg)
