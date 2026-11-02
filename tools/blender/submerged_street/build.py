"""Author the submerged_street v001 kit: ten independent purely decorative sunken-street buildings.

Never touches existing Godot scenes. Color is PaletteUV only; surface feel is role only.
Run: blender --background --factory-startup --python tools/blender/submerged_street/build.py
"""
import bpy
import bmesh
import hashlib
import json
import math
import os
from pathlib import Path
from mathutils import Euler, Matrix, Vector

R = Path(__file__).resolve().parents[3]
D = R / 'art_source/scenes/submerged_street/v001'
W = Path(os.environ.get('SEA_WORK_ROOT', R.parent / 'sea-work')) / 'submerged_street_v001'
P = json.loads((D / 'component_plan.json').read_text(encoding='utf-8'))
PAL_PATH = R / P['palette']
PAL = json.loads(PAL_PATH.with_suffix('.json').read_text(encoding='utf-8'))


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def write(p, v):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(v, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


assert P['status'] == 'frozen_before_geometry', 'plan must be frozen before geometry'
assert sha(D / P['reference']) == P['reference_sha256'], 'design brief changed after freeze'
assert sha(PAL_PATH) == P['palette_sha256'], 'public palette changed'
assert (os.environ.get('SEA_BUILD_FORCE') or not (D / 'submerged_street.blend').exists()), \
    'preserve authored source; bump version'

CELL = {c['name']: (c['row'], c['column']) for c in PAL['cells']}
MISSING = set()

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.preferences.filepaths.save_version = 0
SCENE = bpy.context.scene
SCENE.name = '沉没街道_参考布局'
SCENE.unit_settings.system = 'METRIC'
MASTER = bpy.data.scenes.new('独立建筑母版')
MASTER.unit_settings.system = 'METRIC'
BODY = bpy.data.collections.new('建筑_独立纯景观')
MASTER.collection.children.link(BODY)
LAYOUT = bpy.data.collections.new('参考布局_建筑实例')
SCENE.collection.children.link(LAYOUT)
STAGE = bpy.data.collections.new('展示支持_不导出')
SCENE.collection.children.link(STAGE)

IMG = bpy.data.images.load(str(PAL_PATH))
IMG.name = 'SEA_公共方格色板'


def make_material(name, metallic, roughness, coat=0.0, alpha=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nodes = m.node_tree.nodes
    nodes.clear()
    bsdf = nodes.new('ShaderNodeBsdfPrincipled')
    bsdf.inputs['Metallic'].default_value = metallic
    bsdf.inputs['Roughness'].default_value = roughness
    if 'Coat Weight' in bsdf.inputs:
        bsdf.inputs['Coat Weight'].default_value = coat
    if alpha < 1.0:
        bsdf.inputs['Alpha'].default_value = alpha
        m.surface_render_method = 'DITHERED'
    tex = nodes.new('ShaderNodeTexImage')
    tex.image = IMG
    tex.interpolation = 'Closest'
    uvn = nodes.new('ShaderNodeUVMap')
    uvn.uv_map = 'PaletteUV'
    out = nodes.new('ShaderNodeOutputMaterial')
    link = m.node_tree.links.new
    link(uvn.outputs['UV'], tex.inputs['Vector'])
    link(tex.outputs['Color'], bsdf.inputs['Base Color'])
    link(bsdf.outputs[0], out.inputs[0])
    return m


MATS = {
    'matte': make_material('SEA_Matte', 0.0, 0.74),
    'metal': make_material('SEA_Metal', 0.86, 0.27, 0.16),
    'gloss': make_material('SEA_Gloss', 0.18, 0.12, 0.62),
}

CUR = [None]
COUNT = [0]
PARTS = []


def _cell_uv(color):
    if color not in CELL:
        MISSING.add(color)
        raise KeyError(color)
    r, c = CELL[color]
    return (c + 0.5) / 8.0, 1.0 - (r + 0.5) / 8.0


def add(name, verts, faces, color, role='matte', bevel=0.0, seg=1, recalc=True):
    """Create an identity-transform object in the current collection with PaletteUV."""
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], [tuple(f) for f in faces])
    me.update()
    if recalc:
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        bm.to_mesh(me)
        bm.free()
    o = bpy.data.objects.new(name, me)
    CUR[0].objects.link(o)
    if bevel > 0:
        mod = o.modifiers.new('实体倒角', 'BEVEL')
        mod.width = bevel
        mod.segments = seg
        mod.limit_method = 'ANGLE'
        mod.angle_limit = math.radians(35)
        mod.use_clamp_overlap = True
        bpy.ops.object.select_all(action='DESELECT')
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier=mod.name)
    me = o.data
    me.materials.clear()
    me.materials.append(MATS[role])
    for layer in list(me.uv_layers):
        me.uv_layers.remove(layer)
    uvl = me.uv_layers.new(name='PaletteUV')
    uvl.active_render = True
    me.uv_layers.active_index = 0
    cx, cy = _cell_uv(color)
    for f in me.polygons:
        n = len(f.loop_indices)
        for j, li in enumerate(f.loop_indices):
            # corners go round the cell centre in loop order: a convex island, never a bow-tie
            a = math.tau * j / n
            uvl.data[li].uv = (cx + 0.016 * math.cos(a), cy + 0.016 * math.sin(a))
    COUNT[0] += 1
    me.calc_loop_triangles()
    PARTS.append((len(me.loop_triangles), name))
    return o


_ROT = {}


def rot3(euler):
    key = tuple(euler)
    if key not in _ROT:
        _ROT[key] = Euler(euler, 'XYZ').to_matrix()
    return _ROT[key]


def bx(name, center, size, color, role='matte', bevel=0.0, seg=1, rot=(0, 0, 0)):
    sx, sy, sz = (s / 2.0 for s in size)
    base = [(-sx, -sy, -sz), (sx, -sy, -sz), (sx, sy, -sz), (-sx, sy, -sz),
            (-sx, -sy, sz), (sx, -sy, sz), (sx, sy, sz), (-sx, sy, sz)]
    m = rot3(rot)
    c = Vector(center)
    verts = [m @ Vector(v) + c for v in base]
    faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    return add(name, verts, faces, color, role, bevel, seg)


def cy(name, center, r, h, color, role='matte', n=12, axis='Z', r2=None, cap=True, rot=(0, 0, 0)):
    r2 = r if r2 is None else r2
    ang = [math.tau * k / n for k in range(n)]
    if axis == 'Z':
        a = [Vector((math.cos(t) * r, math.sin(t) * r, -h / 2)) for t in ang]
        b = [Vector((math.cos(t) * r2, math.sin(t) * r2, h / 2)) for t in ang]
    elif axis == 'Y':
        a = [Vector((math.cos(t) * r, -h / 2, math.sin(t) * r)) for t in ang]
        b = [Vector((math.cos(t) * r2, h / 2, math.sin(t) * r2)) for t in ang]
    else:
        a = [Vector((-h / 2, math.cos(t) * r, math.sin(t) * r)) for t in ang]
        b = [Vector((h / 2, math.cos(t) * r2, math.sin(t) * r2)) for t in ang]
    m = rot3(rot)
    c = Vector(center)
    verts = [m @ v + c for v in a + b]
    faces = [(k, (k + 1) % n, (k + 1) % n + n, k + n) for k in range(n)]
    if cap:
        faces.append(tuple(range(n - 1, -1, -1)))
        faces.append(tuple(range(n, 2 * n)))
    return add(name, verts, faces, color, role)


def poly_tube(name, pts, r, color, role='matte', sides=4, cap=True):
    pts = [Vector(p) for p in pts]
    rings = []
    for i, p in enumerate(pts):
        if i == 0:
            t = pts[1] - pts[0]
        elif i == len(pts) - 1:
            t = pts[-1] - pts[-2]
        else:
            t = pts[i + 1] - pts[i - 1]
        t.normalize()
        up = Vector((0, 0, 1))
        if abs(t.dot(up)) > 0.94:
            up = Vector((0, 1, 0))
        u = t.cross(up).normalized()
        v = t.cross(u).normalized()
        rings.append([p + (u * math.cos(math.tau * k / sides) + v * math.sin(math.tau * k / sides)) * r
                      for k in range(sides)])
    verts = []
    faces = []
    for ring in rings:
        base = len(verts)
        verts.extend(ring)
        if base >= sides:
            for k in range(sides):
                k2 = (k + 1) % sides
                faces.append((base - sides + k, base - sides + k2, base + k2, base + k))
    if cap:
        faces.append(tuple(range(sides - 1, -1, -1)))
        faces.append(tuple(range(len(verts) - sides, len(verts))))
    return add(name, verts, faces, color, role)


def quad(name, center, u, w, h, color, role='matte', nrm=None):
    """Flat panel. u = horizontal unit direction inside the panel plane; v = +Z."""
    u = Vector((u[0], u[1], 0)).normalized()
    c = Vector(center)
    verts = [c - u * (w / 2) - Vector((0, 0, h / 2)), c + u * (w / 2) - Vector((0, 0, h / 2)),
             c + u * (w / 2) + Vector((0, 0, h / 2)), c - u * (w / 2) + Vector((0, 0, h / 2))]
    if nrm is not None:
        want = Vector(nrm)
        got = (verts[1] - verts[0]).cross(verts[2] - verts[1])
        if got.dot(want) < 0:
            verts = [verts[3], verts[2], verts[1], verts[0]]
    return add(name, verts, [(0, 1, 2, 3)], color, role, recalc=False)


def plate(name, outline, y0, y1, color, role='matte', bevel=0.0, seg=1):
    """Solid plate from a 2D outline in the XZ plane, extruded from y0 to y1.

    Used for torn/missing-corner signage: a notched outline stays watertight, so a
    break never opens a slot that renders as a black hole from an oblique camera.
    """
    N = len(outline)
    verts = [(x, y0, z) for x, z in outline] + [(x, y1, z) for x, z in outline]
    faces = [tuple(reversed(range(N))), tuple(range(N, 2 * N))]
    faces += [(i, (i + 1) % N, (i + 1) % N + N, i + N) for i in range(N)]
    return add(name, verts, faces, color, role, bevel, seg)


def prism(name, poly, z, h, color, role='matte', bevel=0.0, seg=1):
    N = len(poly)
    verts = [(x, y, z) for x, y in poly] + [(x, y, z + h) for x, y in poly]
    faces = [tuple(reversed(range(N))), tuple(range(N, 2 * N))]
    faces += [(i, (i + 1) % N, (i + 1) % N + N, i + N) for i in range(N)]
    return add(name, verts, faces, color, role, bevel, seg)


def win_row(name, a, b, nrm, z, floors, floor_h, cols, color, colors_alt=None,
            ww=1.35, wh=1.1, sill=0.4, role='gloss', skip=()):
    """Window band on the wall going from a to b (2D), outward normal nrm (2D)."""
    a = Vector((a[0], a[1], 0))
    b = Vector((b[0], b[1], 0))
    d = (b - a)
    L = d.length
    u = d.normalized()
    n = Vector((nrm[0], nrm[1], 0)).normalized()
    margin = 0.5
    span = max(0.1, L - 2 * margin)
    step = span / cols
    used = 0
    for f in range(floors):
        for c in range(cols):
            if (f, c) in skip:
                continue
            t = margin + step * (c + 0.5)
            p = a + u * t + n * 0.02 + Vector((0, 0, z + f * floor_h + sill + wh / 2))
            col = color
            if colors_alt and (f + c) % 3 == 0:
                col = colors_alt
            quad('%s_%d_%d' % (name, f, c), p, u, min(ww, step - 0.3), wh, col, role, n)
            used += 1
    return used


# ---------------------------------------------------------------- buildings

def build_broken_viaduct():
    """26 m elevated road, middle span collapsed, rebar and broken parapets."""
    shell, deckc, road = 'snow', 'cloud', 'gray'
    rail, rebar, pier = 'steel', 'coral', 'plaster'
    # piers + caps
    for sx, tx in ((-1, -8.6), (1, 8.6)):
        bx('桥墩_%d' % sx, (tx, 0, 2.35), (1.5, 5.8, 4.7), pier, bevel=0.09)
        bx('墩帽_%d' % sx, (tx, 0, 4.9), (2.3, 7.2, 0.55), shell, bevel=0.06)
        # spalled patches on the pier faces
        for i in range(3):
            quad('墩剥落_%d_%d' % (sx, i), (tx + 0.76, -2.2 + i * 1.7, 1.1 + i * 0.7),
                 (0, 1), 1.1, 0.9, 'sand', 'matte', (1, 0, 0))
    # deck: two intact arms and one collapsed span resting between them
    bx('桥面_左', (-8.0, 0, 5.95), (10.6, 7.6, 0.5), shell, bevel=0.09, seg=2)
    bx('桥面_右', (8.2, 0, 5.95), (9.6, 7.6, 0.5), shell, bevel=0.09, seg=2)
    bx('路面_左', (-7.95, 0, 6.21), (10.5, 7.36, 0.06), road)
    bx('路面_右', (8.65, 0, 6.21), (8.9, 7.36, 0.06), road)
    for i in range(5):
        x = -12.0 + i * 2.2
        bx('车道线', (x, 0, 6.26), (1.5, 0.14, 0.03), 'snow')
    bx('车道线_右', (10.4, 0, 6.26), (1.5, 0.14, 0.03), 'snow')
    # broken ends: slanted faces
    # A torn lip is built as protruding chunks, never as a second cap on the cut face:
    # two coincident faces there used to z-fight and render as a black slot.
    for j, (dx, dy, dz, hx, hy, hz) in enumerate((
            (0.14, -3.2, 0.0, 0.28, 0.9, 0.34), (0.10, -1.4, 0.06, 0.22, 0.7, 0.26),
            (0.16, 0.6, -0.04, 0.3, 0.85, 0.3), (0.09, 2.4, 0.05, 0.2, 0.8, 0.24))):
        bx('断口块_左_%d' % j, (-2.7 - dx, dy, 5.95 + dz), (hx * 2, hy * 2, hz * 2), shell,
           rot=(0, 0, 0.06 * (j + 1)))
    for j, (dx, dy, dz, hx, hy, hz) in enumerate((
            (0.15, 2.9, 0.02, 0.3, 0.85, 0.32), (0.10, 1.1, -0.05, 0.22, 0.7, 0.26),
            (0.13, -0.9, 0.04, 0.26, 0.9, 0.3), (0.08, -2.8, 0.0, 0.18, 0.75, 0.22))):
        bx('断口块_右_%d' % j, (3.3 + dx, dy, 5.95 + dz), (hx * 2, hy * 2, hz * 2), shell,
           rot=(0, 0, -0.05 * (j + 1)))
    bx('断口_左碎块', (-2.2, 1.2, 5.45), (1.1, 1.6, 0.6), shell, bevel=0.05, rot=(0.22, 0.1, 0.12))
    # collapsed middle span
    bx('塌落桥面', (0.4, 0.2, 2.9), (5.6, 7.2, 0.45), shell, bevel=0.09, rot=(0, 0.32, 0.06))
    bx('塌落路面', (0.4, 0.2, 3.15), (5.2, 7.0, 0.06), road, rot=(0, 0.32, 0.06))
    bx('塌落护栏', (0.3, -3.2, 3.55), (5.0, 0.2, 0.75), rail, rot=(0, 0.32, 0.06))
    # exposed rebar from both broken ends and the dropped slab
    for i in range(6):
        y = -3.0 + i * 1.2
        poly_tube('钢筋_左_%d' % i, [(-3.2, y, 6.05), (-1.9, y, 6.18), (-1.15, y + (0.1 if i % 2 else -0.1), 6.55)],
                  0.028, rebar, sides=4)
        poly_tube('钢筋_右_%d' % i, [(3.0, y, 6.05), (2.0, y, 6.2), (1.3, y, 6.6)], 0.028, rebar, sides=4)
    for i in range(4):
        poly_tube('钢筋_上层_%d' % i, [(2.6, 0.6, 6.1), (2.0, 0.6, 6.9), (1.5, 0.6, 7.05)], 0.032, rebar, sides=4)
    # parapets along intact arms, broken at the gap
    for side, sy in enumerate((-1, 1)):
        for arm, x0, x1 in (('左', -13.0, -2.8), ('右', 3.3, 13.0)):
            bx('护栏_%s%d' % (arm, side), ((x0 + x1) / 2, sy * 3.7, 6.55), (x1 - x0 - 0.4, 0.24, 0.9), shell, bevel=0.04)
            bx('护栏压顶_%s%d' % (arm, side), ((x0 + x1) / 2, sy * 3.7, 7.02), (x1 - x0 - 0.5, 0.3, 0.12), 'white')
        # one missing parapet run per side reads as damage
    bx('缺护栏残块', (-4.4, 3.55, 6.6), (0.9, 0.24, 0.85), shell, bevel=0.03, rot=(0, 0, 0.12))
    # deck underside beams, seen from below when swimming
    for i in range(4):
        bx('梁_%d' % i, (-9.4 + i * 4.2, 0, 5.56), (0.6, 7.4, 0.55), 'cloud')
    # road furniture: two lane posts, one fallen
    bx('车道柱直', (-11.4, 3.2, 6.55), (0.12, 0.12, 0.9), 'yellow')
    bx('车道柱倒', (-6.2, -3.0, 6.34), (0.12, 0.9, 0.12), 'yellow', rot=(0, 0, 0.4))
    # rubble in the gap
    for i, (x, y, s) in enumerate(((-1.4, 2.4, 0.9), (0.9, -2.6, 1.2), (1.8, 1.9, 0.7), (-0.6, -1.4, 0.6))):
        bx('瓦砾_%d' % i, (x, y, 0.45), (s, s * 0.8, s * 0.7), shell, bevel=0.04, rot=(0.3, 0, i * 0.5))


def build_l_apartment_fire_escape():
    """Five floors, L footprint, steel fire escape on the east face."""
    shell, trim, glass = 'plaster', 'cream', 'solar'
    glassd, steel, scar = 'deepblue', 'steel', 'coral'
    H, FH = 12.6, 2.6
    poly = [(-7.0, -6.5), (7.0, -6.5), (7.0, 1.6), (-1.0, 1.6), (-1.0, 6.5), (-7.0, 6.5)]
    prism('楼壳', poly, 0.0, H, shell, bevel=0.09, seg=2)
    for f in range(1, 6):
        z = f * FH
        prism('层间线脚_%d' % f, [(x * 1.02, y * 1.02) for x, y in poly], z - 0.06, 0.16, trim)
    prism('屋面', [(x * 1.03, y * 1.03) for x, y in poly], H, 0.22, 'snow', bevel=0.06)
    # parapet, with bites taken out of two runs
    edges = [(poly[i], poly[(i + 1) % len(poly)]) for i in range(len(poly))]
    for i, (a, b) in enumerate(edges):
        a, b = Vector((*a, 0)), Vector((*b, 0))
        v = b - a
        if v.length < 1.2 or i in (1, 4):
            continue
        c = (a + b) / 2
        ang = math.atan2(v.y, v.x)
        bx('女儿墙_%d' % i, (c.x, c.y, H + 0.36), (v.length - 0.3, 0.22, 0.5), trim, bevel=0.04, rot=(0, 0, ang))
    # windows: front (-Y), east (+X), north wing (+Y), west (-X)
    win_row('前窗', (-6.6, -6.5), (6.6, -6.5), (0, -1), 0.0, 5, FH, 7, glass, glassd, skip={(0, 2), (3, 5)})
    win_row('东窗', (7.0, -6.2), (7.0, 1.3), (1, 0), 0.0, 5, FH, 3, glass, glassd, skip={(2, 1)})
    win_row('北窗', (-1.2, 6.5), (-6.8, 6.5), (0, 1), 0.0, 5, FH, 3, glass, glassd)
    win_row('西窗', (-7.0, 6.2), (-7.0, -6.2), (-1, 0), 0.0, 5, FH, 6, glass, glassd, skip={(4, 4)})
    # corner piers keep the recessed windows reading
    for x, y in ((-7.0, -6.5), (7.0, -6.5), (7.0, 1.6), (-1.0, 1.6), (-1.0, 6.5), (-7.0, 6.5)):
        bx('转角柱', (x * 0.995, y * 0.995, H / 2), (0.42, 0.42, H), trim)
    # ground floor plinth
    prism('勒脚', [(x * 1.01, y * 1.01) for x, y in poly], 0.0, 0.5, 'sand')
    # fire escape on the east face
    z0 = 0.4
    for level in range(1, 5):
        z = level * FH
        bx('消防梯平台_%d' % level, (7.9, -2.4, z), (1.7, 8.2, 0.14), steel, bevel=0.02)
        bx('平台栏杆_%d' % level, (8.72, -2.4, z + 0.52), (0.06, 8.2, 0.06), steel)
        bx('平台立柱_%d' % level, (8.72, -6.4, z + 0.26), (0.07, 0.07, 0.55), steel)
        bx('平台立柱_%d' % level, (8.72, 1.55, z + 0.26), (0.07, 0.07, 0.55), steel)
        # zig-zag stair down to the level below
        x_in, x_out = 7.55, 8.35
        y_a, y_b = (-6.0 + level * 0.4), (0.9 + level * 0.4)
        drop = FH - 0.14
        steps = 7
        for s in range(steps):
            t = (s + 0.5) / steps
            y = y_a + (y_b - y_a) * t
            zz = z - drop * (s + 1) / steps
            bx('梯级_%d_%d' % (level, s), ((x_in + x_out) / 2, y, zz), (0.86, 0.62, 0.05), steel,
               rot=(0, 0, 0), bevel=0.0)
        for xx in (x_in, x_out):
            poly_tube('梯梁_%d_%d' % (level, int(xx * 10)), [(xx, y_a, z - 0.05), (xx, y_b, z - drop)], 0.045, steel, sides=4)
        bx('梯扶手_%d' % level, (8.45, (y_a + y_b) / 2, z - drop / 2 + 0.95), (0.05, abs(y_b - y_a), 0.05),
           steel, rot=(math.atan2(drop, y_b - y_a), 0, 0))
    # one broken tread and a hanging rail
    bx('断梯级', (7.95, 3.4, 4.9), (0.8, 0.5, 0.05), steel, rot=(0.5, 0, 0.2))
    poly_tube('断扶手', [(8.7, 5.4, 7.9), (8.85, 5.9, 7.2), (8.9, 6.1, 6.7)], 0.04, steel, sides=4)
    # ground hatch and door
    quad('底层门', (3.4, -6.52, 1.5), (1, 0), 1.6, 2.6, 'wood_mid', 'matte', (0, -1, 0))
    bx('门雨棚', (3.4, -6.9, 2.95), (2.4, 0.9, 0.12), trim, bevel=0.03)
    # damaged plaster islands and a blackened window
    for i in range(7):
        x = -6.0 + i * 1.9
        z = 1.1 + (i * 0.37 % 1) * 9.0
        quad('墙皮剥落_%d' % i, (x, -6.53, z), (1, 0), 0.6 + (i % 3) * 0.3, 0.5 + (i % 2) * 0.4,
             'sand' if i % 2 else scar, 'matte', (0, -1, 0))
    quad('烧黑窗', (-3.2, -6.53, 3.6), (1, 0), 1.1, 0.9, 'slate', 'matte', (0, -1, 0))


def build_food_truck():
    """Six-metre serving truck: cream body, coral stripe, aqua awning, one flat tyre."""
    body, stripe, awning = 'cream', 'coral', 'aqua'
    wheel, hub, glass, gold = 'rubber', 'steel', 'solar', 'gold'
    # chassis and axle
    bx('底盘', (0, 0, 0.82), (5.8, 2.1, 0.22), 'gray')
    bx('车架纵梁', (-0.1, 0.9, 0.72), (5.4, 0.12, 0.16), 'steel')
    bx('车架纵梁', (-0.1, -0.9, 0.72), (5.4, 0.12, 0.16), 'steel')
    # body, listed 3 degrees into the seabed
    tilt = (0, 0.05, 0)
    bx('车厢', (0.55, 0, 1.95), (4.3, 2.4, 2.0), body, bevel=0.06, seg=2)
    bx('驾驶室', (-2.15, 0, 1.72), (1.75, 2.3, 1.5), body, bevel=0.05)
    bx('前脸', (-3.02, 0, 1.6), (0.12, 2.1, 1.1), body, bevel=0.04)
    quad('挡风玻璃', (-3.06, 0, 2.0), (0, 1), 1.5, 0.75, glass, 'gloss', (-1, 0, 0))
    bx('保险杠', (-3.08, 0, 0.95), (0.2, 2.2, 0.22), 'steel')
    # coral waist stripe, four sides
    bx('腰线_右', (0.55, 1.22, 1.7), (4.3, 0.06, 0.34), stripe)
    bx('腰线_左', (0.55, -1.22, 1.7), (4.3, 0.06, 0.34), stripe)
    bx('腰线_前', (2.72, 0, 1.7), (0.06, 2.4, 0.34), stripe)
    bx('腰线_后', (-3.1, 0, 1.7), (0.06, 2.2, 0.34), stripe)
    # serving hatch on the street side (+Y)
    bx('窗口框', (0.9, 1.21, 2.2), (2.2, 0.1, 1.0), 'white')
    quad('售餐口', (0.9, 1.25, 2.18), (1, 0), 1.9, 0.75, 'slate', 'matte', (0, 1, 0))
    bx('窗口台面', (0.9, 1.42, 1.72), (2.3, 0.42, 0.08), 'white', bevel=0.02)
    # aqua awning: five slats spreading outward from the hatch header, one torn away
    for i in range(5):
        if i == 3:
            continue
        bx('雨棚_%d' % i, (0.9 + (i - 2) * 0.52, 1.68, 2.78), (0.5, 1.15, 0.05),
           awning if i % 2 == 0 else 'white', rot=(-0.34, 0, 0))
    bx('雨棚横杆', (0.9, 1.26, 2.62), (2.6, 0.07, 0.07), 'steel')
    for sx in (-0.28, 2.08):
        poly_tube('雨棚斜撑', [(sx, 1.26, 2.6), (sx, 2.02, 2.5)], 0.028, 'steel', sides=4)
    # roof signboard carried on two legs, and the menu board hung under the awning
    bx('招牌板', (0.9, 0.95, 3.34), (2.4, 0.1, 0.42), 'white', bevel=0.02)
    for i in range(3):
        bx('招牌字块_%d' % i, (0.28 + i * 0.62, 1.01, 3.34), (0.4, 0.03, 0.22), gold)
    for sx in (0.0, 1.8):
        bx('招牌腿_%d' % int(sx * 10), (sx, 0.95, 3.08), (0.07, 0.07, 0.22), 'steel')
    bx('菜单牌', (-1.05, 1.28, 2.35), (0.85, 0.05, 0.62), 'wood_mid', rot=(0, 0.1, 0))
    # wheels: three sound, one flat
    for x, y, flat in ((-2.1, 1.05, False), (-2.1, -1.05, False), (1.7, 1.05, True), (1.7, -1.05, False)):
        r = 0.3 if flat else 0.38
        cy('轮胎_%s' % ('瘪' if flat else str(x) + str(y)), (x, y, r * 0.92), r, 0.24, wheel, n=12, axis='Y')
        cy('轮毂_%s' % ('瘪' if flat else str(x) + str(y)), (x, y, r * 0.92), r * 0.45, 0.26, hub, role='metal', n=10, axis='Y')
    # rear detail
    bx('尾部箱体', (-3.12, 0.4, 1.35), (0.1, 0.7, 0.9), 'cream')
    cy('排气管', (-3.0, -0.85, 0.55), 0.07, 0.5, 'steel', role='metal', n=8)
    # roof vent and a torn corner plate
    cy('顶风口', (1.9, 0, 3.0), 0.3, 0.24, 'silver', role='metal', n=10)
    bx('侧板破口', (2.6, 1.24, 1.1), (0.7, 0.04, 0.35), 'sand', rot=(0, 0, 0.18))


def build_mcdonalds_restaurant():
    """Two storeys, red mansard roof, twin golden arch sign missing one leg."""
    shell, roof, arch = 'cream', 'red_dark', 'gold'
    glass, trim, scar = 'solar', 'white', 'coral'
    W_, D_ = 12.0, 9.0
    bx('基座', (0, 0, 0.1), (W_, D_, 0.2), 'snow', bevel=0.05)
    bx('一层体量', (0, 0, 1.7), (11.4, 8.4, 3.0), shell, bevel=0.09)
    bx('层间檐口', (0, 0, 3.28), (11.9, 8.9, 0.24), trim, bevel=0.05)
    bx('二层体量', (0, 0, 4.0), (11.0, 8.0, 1.2), shell, bevel=0.08)
    # upper-floor glazing split into panes so no single dark pane reads as a black slab
    for i in range(5):
        bx('二层窗_%d' % i, (-4.2 + i * 2.1, -4.02, 4.05), (1.6, 0.06, 0.85), 'deepblue')
        bx('二层窗梃_%d' % i, (-5.15 + i * 2.1, -4.04, 4.05), (0.12, 0.07, 0.9), trim)
    # mansard: frustum 12x9 -> 9.6x6.6
    b = [(-6.0, -4.5), (6.0, -4.5), (6.0, 4.5), (-6.0, 4.5)]
    t = [(-4.8, -3.3), (4.8, -3.3), (4.8, 3.3), (-4.8, 3.3)]
    verts = [(x, y, 4.6) for x, y in b] + [(x, y, 5.5) for x, y in t]
    faces = [(3, 2, 1, 0), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    add('芒萨尔屋面', verts, faces, roof, bevel=0.09, seg=2)
    bx('屋脊压顶', (0, 0, 5.52), (9.8, 6.8, 0.12), roof, bevel=0.03)
    # missing tile wedge: a bare patch high on the front slope
    quad('缺瓦露底', (2.4, -4.2, 4.95), (1, 0), 1.6, 1.0, 'snow', 'matte', (0, -1, 0.3))
    # glazed storefront with mullions
    quad('玻璃幕_前', (0, -4.24, 1.55), (1, 0), 9.0, 2.0, glass, 'gloss', (0, -1, 0))
    for i in range(6):
        bx('竖梃', (-4.5 + i * 1.8, -4.26, 1.55), (0.1, 0.08, 2.05), trim)
    bx('横梃', (0, -4.26, 2.5), (9.0, 0.08, 0.1), trim)
    # side glazing
    quad('玻璃幕_东', (5.72, 0, 1.55), (0, 1), 7.0, 1.8, glass, 'gloss', (1, 0, 0))
    quad('玻璃幕_西', (-5.72, 0, 1.55), (0, 1), 7.0, 1.8, glass, 'gloss', (-1, 0, 0))
    for sy in (-1, 1):
        for i in range(3):
            bx('侧竖梃_%d' % i, (sy * 5.73, -2.2 + i * 2.2, 1.55), (0.08, 0.1, 1.85), trim)
    # entrance with canopy
    bx('门厅', (-2.4, -4.3, 1.4), (2.2, 0.3, 2.8), 'wood_mid')
    bx('门斗雨棚', (-2.4, -4.9, 2.95), (3.0, 1.2, 0.16), trim, bevel=0.04)
    poly_tube('雨棚拉杆', [(-3.7, -4.35, 3.6), (-3.85, -4.85, 2.98)], 0.04, 'steel')
    poly_tube('雨棚拉杆', [(-1.1, -4.35, 3.6), (-0.95, -4.85, 2.98)], 0.04, 'steel')
    # twin arches standing on the mansard's flat top; the right one is missing its leg
    for i, cx in enumerate((-1.4, 1.4)):
        pts = []
        span, height = 1.6, 1.25
        n = 9
        for k in range(n + 1):
            t01 = k / n
            if i == 1 and t01 > 0.6:
                break
            x = cx - span / 2 + span * t01
            z = 5.62 + height * math.sin(math.pi * t01) * 0.98
            pts.append((x, -2.2, z))
        poly_tube('拱_%d' % i, pts, 0.1, arch, sides=6)
    bx('拱底座', (0, -2.2, 5.6), (3.9, 0.28, 0.14), arch, bevel=0.02)
    bx('招牌背板', (0, -2.34, 5.82), (3.7, 0.1, 0.44), 'white')
    bx('招牌腿左', (-1.55, -2.34, 5.62), (0.08, 0.08, 0.3), 'steel')
    bx('招牌腿右', (1.55, -2.34, 5.62), (0.08, 0.08, 0.3), 'steel')
    # roof plant + parapet returns
    bx('屋面机组', (-3.4, 1.6, 5.72), (1.6, 1.2, 0.5), 'silver', role='metal', bevel=0.03)
    cy('排风筒', (-3.4, 1.6, 6.05), 0.26, 0.3, 'steel', role='metal', n=10)
    # scars and a missing glass pane
    for i in range(5):
        x = -4.4 + i * 2.2
        quad('墙皮_%d' % i, (x, -4.55, 2.55 + (i % 2) * 0.5), (1, 0), 0.7, 0.45,
             scar if i % 2 else 'sand', 'matte', (0, -1, 0))
    quad('破窗', (3.6, -4.25, 1.6), (1, 0), 1.1, 1.2, 'slate', 'matte', (0, -1, 0))


def build_highrise_apartment():
    """Ten floors, ivory shell, deep-blue bands, top corner collapsed."""
    shell, band, glass = 'white', 'snow', 'deepblue'
    glass2, balcony, roofc = 'ocean', 'cream', 'steel'
    FH, FLOORS = 2.6, 10
    H = FH * FLOORS
    poly = [(-4.3, -4.3), (4.3, -4.3), (4.3, 4.3), (-4.3, 4.3)]
    prism('楼壳', poly, 0.0, H - 2 * FH, shell, bevel=0.09, seg=2)
    # top two floors with the north-east corner collapsed
    notch = [(-4.3, -4.3), (4.3, -4.3), (4.3, 2.1), (2.1, 2.1), (2.1, 4.3), (-4.3, 4.3)]
    prism('顶层残壳', notch, H - 2 * FH, 2 * FH, shell, bevel=0.09, seg=2)
    prism('屋面', [(x * 0.98, y * 0.98) for x, y in notch], H, 0.2, 'cloud', bevel=0.05)
    bx('角部塌块', (3.3, 3.3, H - 2.2), (1.5, 1.5, 1.0), shell, bevel=0.05, rot=(0.18, 0.12, 0.26))
    bx('塌块钢筋', (2.7, 2.7, H - 1.4), (0.06, 0.06, 1.1), 'coral', rot=(0.3, 0, 0))
    # floor bands
    for f in range(1, FLOORS):
        bx('层带_%d' % f, (0, 0, f * FH - 0.05), (8.7, 8.7, 0.16), band)
    # window bands on all four faces
    win_row('南窗', (-3.9, -4.3), (3.9, -4.3), (0, -1), 0.0, FLOORS - 2, FH, 3, glass, glass2)
    win_row('北窗', (-3.9, 4.3), (3.9, 4.3), (0, 1), 0.0, FLOORS - 2, FH, 3, glass, glass2,
            skip={(0, 1), (6, 2)})
    win_row('东窗', (4.3, -3.9), (4.3, 3.9), (1, 0), 0.0, FLOORS - 2, FH, 3, glass, glass2, skip={(3, 0)})
    win_row('西窗', (-4.3, 3.9), (-4.3, -3.9), (-1, 0), 0.0, FLOORS - 2, FH, 3, glass, glass2)
    # vertical corner piers
    for x, y in ((-4.3, -4.3), (4.3, -4.3), (4.3, 4.3), (-4.3, 4.3)):
        bx('角柱', (x, y, (H - 2 * FH) / 2), (0.5, 0.5, H - 2 * FH), band)
    # balconies on the south face, alternating
    for f in (1, 3, 5, 7):
        bx('阳台_%d' % f, (0, -4.85, f * FH + 0.1), (3.2, 1.1, 0.16), balcony, bevel=0.03)
        bx('阳台栏板_%d' % f, (0, -5.35, f * FH + 0.55), (3.2, 0.1, 0.8), balcony, bevel=0.02)
    # roof plant, aerial and a broken parapet
    bx('屋顶机房', (0.4, 1.2, H + 0.55), (2.6, 2.4, 1.1), shell, bevel=0.05)
    cy('天线', (-2.2, 2.6, H + 1.6), 0.05, 2.4, 'steel', role='metal', n=6)
    cy('水箱', (2.0, -2.4, H + 0.8), 0.55, 1.2, 'silver', role='metal', n=12)
    # water stains down the shell
    for i in range(6):
        x = -3.6 + i * 1.35
        quad('水渍_%d' % i, (x, -4.33, 6.0 + (i % 3) * 3.0), (1, 0), 0.35, 3.2, 'gray', 'matte', (0, -1, 0))
    # blown-out glazing on two floors
    for f, c in ((2, 1), (4, 0)):
        quad('爆窗_%d' % f, (-2.6 + c * 2.6, -4.33, f * FH + 0.9), (1, 0), 1.1, 0.95, 'slate', 'matte', (0, -1, 0))


def build_traffic_light():
    """Signal pole with a misted head, one hanging cable, cracked pedestrian lens."""
    pole, head, cable = 'lightgray', 'slate', 'slate'
    bx('基础', (-1.7, 0, 0.08), (0.62, 0.62, 0.16), 'snow', bevel=0.03)
    cy('灯杆', (-1.7, 0, 2.75), 0.12, 5.3, pole, role='metal', n=12)
    cy('杆帽', (-1.7, 0, 5.42), 0.16, 0.12, pole, role='metal', n=12)
    # mast arm to the right with a slight droop
    poly_tube('悬臂', [(-1.7, 0, 5.1), (-0.6, 0, 5.18), (0.9, 0, 5.14), (1.55, 0, 5.06)], 0.09, pole, sides=8)
    for xx in (-0.9, 0.35):
        poly_tube('悬臂斜撑', [(-1.7, 0, 4.55), (xx, 0, 5.12)], 0.035, pole)
    # signal head, tilted
    tilt = (0, 0.14, 0)
    bx('灯头壳', (1.5, 0, 4.35), (0.42, 0.34, 1.24), head, bevel=0.03, rot=tilt)
    bx('灯头顶', (1.5, 0, 5.0), (0.5, 0.42, 0.08), pole, rot=tilt)
    for i, (z, col) in enumerate(((4.72, 'red'), (4.34, 'yellow'), (3.96, 'leaf'))):
        cy('灯罩_%d' % i, (1.5 + 0.14 * 0.55, -0.19, z), 0.115, 0.05, col, n=12, axis='Y', rot=tilt)
        bx('遮光檐_%d' % i, (1.5, -0.22, z + 0.14), (0.3, 0.2, 0.04), head, rot=tilt)
    # pedestrian signal and controller on the pole
    bx('人行灯', (-1.7, -0.28, 3.2), (0.34, 0.16, 0.52), head, bevel=0.02)
    quad('人行绿灯', (-1.7, -0.37, 3.24), (1, 0), 0.2, 0.28, 'leaf_dark', 'matte', (0, -1, 0))
    bx('人行灯裂', (-1.62, -0.38, 3.32), (0.09, 0.02, 0.16), 'rubber', rot=(0, 0.3, 0))
    bx('控制箱', (-1.86, -0.3, 1.35), (0.34, 0.28, 0.7), 'gray', role='metal', bevel=0.02)
    # hanging cable from the mast to the head, then a free end
    poly_tube('电缆', [(-1.5, 0, 4.95), (-0.4, 0.02, 4.3), (0.6, 0.02, 4.4), (1.5, 0, 4.98)], 0.03, cable, sides=4)
    poly_tube('垂落电缆', [(-1.62, 0, 4.9), (-1.68, 0.05, 3.4), (-1.58, 0.1, 2.2)], 0.03, cable, sides=4)
    # base grime and a bent bracket
    bx('泥土痕', (-1.7, 0, 0.28), (0.7, 0.7, 0.1), 'sand', bevel=0.02)


def build_utility_poles():
    """Two wooden poles carrying three spans. Crossarms run across the street (Y), wires run
    along it (X), which is how the hardware actually works — the first pass had the arm and the
    wires on the same axis, so the wires could not land on an insulator."""
    pole, arm, insul = 'wood_dark', 'wood_mid', 'ice'
    trans, wire, plate = 'gray', 'slate', 'white'
    X = 4.6
    WIRE_Y = (-0.86, 0.0, 0.86)
    for i, sx in enumerate((-1, 1)):
        cy('电杆_%d' % i, (sx * X, 0, 4.12), 0.17, 8.16, pole, n=10, r2=0.13)
        bx('杆基_%d' % i, (sx * X, 0, 0.12), (0.6, 0.6, 0.24), 'sand')
        # the right pole lost its top crossarm; only the lower arm survives there
        if i == 0:
            bx('横担_顶_%d' % i, (sx * X, 0, 7.62), (0.15, 2.2, 0.16), arm)
            for k, y in enumerate(WIRE_Y + (1.0, -1.0)):
                cy('绝缘子_%d_%d' % (i, k), (sx * X, y, 7.76), 0.07, 0.16, insul, n=8)
        bx('横担_下_%d' % i, (sx * X, 0, 6.94), (0.14, 1.9, 0.14), arm)
        for k, y in enumerate(WIRE_Y):
            cy('绝缘子下_%d_%d' % (i, k), (sx * X, y, 7.06), 0.06, 0.14, insul, n=8)
        bx('杆号牌', (sx * X + 0.10, -0.06, 3.42), (0.06, 0.3, 0.48), plate, rot=(0, 0, 0.08))
    # transformer on the left pole, on a bracket that actually touches both pole and can
    bx('变压器支架', (-X + 0.18, 0, 5.02), (0.9, 0.24, 0.14), 'steel', role='metal')
    bx('支架吊臂', (-X + 0.18, 0, 5.28), (0.1, 0.1, 0.42), 'steel', role='metal')
    cy('变压器', (-X + 0.26, 0, 5.62), 0.32, 1.04, trans, role='metal', n=12, rot=(0, 0.1, 0))
    for k in range(3):
        cy('变压器套管_%d' % k, (-X + 0.12 + k * 0.16, -0.08, 6.14), 0.045, 0.16, 'ice', n=8)
    # three spans: left top arm (7.72) down to the right lower arm (7.02), landed on insulators
    for k, y in enumerate(WIRE_Y):
        pts = [(-X, y, 7.72)]
        for st in range(1, 6):
            t = st / 6
            pts.append((-X + 2 * X * t, y, 7.72 + (7.02 - 7.72) * t - 0.62 * math.sin(math.pi * t)))
        pts.append((X, y, 7.02))
        poly_tube('电线_%d' % k, pts, 0.028, wire, sides=3)
    # fourth span snapped: left pole to a loose end hanging near the right pole
    pts = [(-X, 0.0, 7.06)]
    for st in range(1, 3):
        t = st / 3
        pts.append((-X + (X + 1.1) * t, 0.0, 7.06 - 0.34 * math.sin(math.pi * t)))
    poly_tube('电线_下', pts, 0.026, wire, sides=3)
    poly_tube('断线_垂', [(-X + 4.1, 0.0, 6.8), (-X + 4.35, 0.08, 6.0), (-X + 4.2, 0.12, 5.2)], 0.024, wire, sides=3)
    poly_tube('断线_垂', [(X, -0.86, 7.06), (X + 0.16, -0.9, 6.0), (X + 0.05, -0.95, 5.1)], 0.024, wire, sides=3)
    # distribution cabinet strapped to the left pole
    poly_tube('杆上引下线', [(-X + 0.02, 0.16, 6.9), (-X + 0.0, 0.19, 5.2), (-X - 0.02, 0.2, 3.95)], 0.022, wire, sides=3)
    bx('接线箱', (-X - 0.02, 0.26, 3.6), (0.34, 0.24, 0.62), 'gray', role='metal')
    bx('箱固定带', (-X + 0.0, 0.02, 3.6), (0.16, 0.36, 0.1), 'steel', role='metal')


def build_highway_sign():
    """Overhead gantry, green panel with a missing corner, leaning right post."""
    post, panel, text = 'lightgray', 'sage', 'snow'
    border, rust = 'white', 'coral'
    # posts at +-4.2 m, right one leaning 4 degrees
    bx('立柱_左', (-4.2, 0, 3.53), (0.32, 0.32, 6.94), post, role='metal', bevel=0.02)
    bx('立柱_右', (4.2, 0, 3.48), (0.32, 0.32, 6.94), post, role='metal', bevel=0.02, rot=(0, -0.07, 0))
    bx('柱基_左', (-4.2, 0, 0.1), (0.9, 0.9, 0.2), 'snow', bevel=0.03)
    bx('柱基_右', (4.2, -0.22, 0.1), (0.9, 0.9, 0.2), 'snow', bevel=0.03)
    # trusses spanning the posts
    bx('上横梁', (0, 0, 6.32), (8.7, 0.28, 0.28), post, role='metal', bevel=0.02)
    bx('下横梁', (0, 0, 4.05), (8.7, 0.24, 0.24), post, role='metal', bevel=0.02)
    for i in range(4):
        poly_tube('斜撑_%d' % i, [(-3.6 + i * 2.4, 0, 4.1), (-2.8 + i * 2.4, 0, 6.28)], 0.05, post, sides=4)
    # main panel 7.4 m wide, with the top-right corner gone
    # one solid board whose top-right corner tore away: the notch is cut into the
    # outline itself, so the break never opens a see-through slot
    notch = [(-3.6, 4.15), (2.6, 4.15), (2.6, 5.2), (1.55, 5.2), (1.55, 6.05), (-3.6, 6.05)]
    outer = [(-3.7, 4.05), (2.7, 4.05), (2.7, 5.3), (1.45, 5.3), (1.45, 6.15), (-3.7, 6.15)]
    plate('牌框', outer, -0.02, 0.06, border)
    plate('主牌', notch, -0.17, -0.03, panel, bevel=0.03)
    # eroded lettering: pale blocks in two rows
    for i, (x, w) in enumerate(((-3.1, 1.3), (-1.6, 1.5), (0.0, 1.0))):
        bx('字块_上_%d' % i, (x, -0.19, 5.52), (w, 0.03, 0.3), text)
    for i, (x, w) in enumerate(((-2.9, 2.0), (-0.6, 1.2))):
        bx('字块_下_%d' % i, (x, -0.19, 4.95), (w, 0.03, 0.26), text)
    bx('右块字', (1.75, -0.19, 4.55), (0.9, 0.03, 0.22), text)
    # small lower panel and a bent bracket
    bx('附牌', (2.6, -0.1, 3.4), (2.2, 0.12, 0.9), panel, bevel=0.02)
    bx('附牌字', (2.6, -0.17, 3.43), (1.3, 0.03, 0.22), text)
    # rust streaks and a bent bracket
    for i in range(4):
        bx('锈痕_%d' % i, (-4.2 + (i % 2) * 8.4, -0.17, 2.2 + i * 1.1), (0.16, 0.04, 1.4), rust)
    poly_tube('弯支架', [(4.15, 0, 3.3), (4.5, 0.1, 2.9), (4.55, 0.15, 2.5)], 0.04, post, sides=4)


def build_construction_shell():
    """Five-level concrete frame: two floors without slabs, scaffold, torn netting, rebar."""
    frame, column, slab = 'plaster', 'snow', 'cloud'
    scaffold, tarp, rebar, core = 'ochre', 'aqua', 'coral', 'gray'
    FH = 3.0
    TOP = 15.0
    xs = (-5.6, 0.0, 5.6)
    ys = (-4.6, 0.0, 4.6)
    # columns on a 3x3 grid
    for i, x in enumerate(xs):
        for j, y in enumerate(ys):
            bx('柱_%d%d' % (i, j), (x, y, TOP / 2 + 0.03), (0.42, 0.42, TOP - 0.06), column, bevel=0.03)
    # shear core at the back-centre
    bx('核心筒', (1.6, 2.2, TOP / 2 + 0.04), (3.0, 2.4, TOP - 0.08), frame, bevel=0.06)
    quad('核心筒封板', (1.6, 1.0, 1.5), (1, 0), 1.6, 2.6, 'wood_mid', 'matte', (0, -1, 0))
    # slabs: full at 0/3.0/9.0/15.0, half slabs at 6.0 and 12.0
    for f in range(0, 6):
        z = f * FH
        if f in (2, 4):
            # half-built floor: only the north half has been poured
            bx('半楼板_%d' % f, (0, 2.3, z + 0.1), (11.6, 4.4, 0.2), slab, bevel=0.03)
            for k in range(4):
                poly_tube('板钢筋_%d_%d' % (f, k), [(-5.0 + k * 3.2, -0.2, z + 0.2), (-4.4 + k * 3.2, 0.7, z + 0.28),
                                                    (-4.1 + k * 3.2, 1.9, z + 0.22)], 0.022, rebar, sides=4)
        else:
            bx('楼板_%d' % f, (0, 0, z + 0.1), (11.6, 9.6, 0.2), slab, bevel=0.03)
    # parapet-less top: beam stubs and a rebar forest
    for k in range(9):
        x = -5.6 + (k % 3) * 5.6
        y = -4.6 + (k // 3) * 4.6
        bx('柱头_%d' % k, (x, y, TOP + 0.3), (0.44, 0.44, 0.6), column)
        for r in range(2):
            poly_tube('顶层钢筋_%d_%d' % (k, r),
                      [(x + (r - 0.5) * 0.16, y, TOP + 0.6), (x + (r - 0.5) * 0.16 + 0.05, y + 0.04, TOP + 1.1),
                       (x + (r - 0.5) * 0.16 - 0.04, y + 0.08, TOP + 1.5)], 0.024, rebar, sides=4)
    # infill walls on the lower two floors only
    bx('砌体_南', (-2.2, -4.55, 2.2), (4.6, 0.2, 4.4), frame, bevel=0.04)
    bx('砌体_东', (5.55, 1.0, 1.5), (0.2, 6.6, 3.0), frame, bevel=0.04)
    for k in range(4):
        quad('砌体窗洞_%d' % k, (-4.0 + k * 2.1, -4.67, 2.4), (1, 0), 1.2, 1.4, 'slate', 'matte', (0, -1, 0))
    # scaffolding on the street face
    for i in range(5):
        x = -5.4 + i * 2.7
        poly_tube('脚手架立杆_%d' % i, [(x, -5.5, 0.0), (x, -5.5, 12.2)], 0.05, scaffold, sides=4)
    for f in range(1, 5):
        z = f * 3.0
        poly_tube('脚手架横杆_%d' % f, [(-5.6, -5.5, z), (5.6, -5.5, z)], 0.045, scaffold, sides=4)
        bx('脚手板_%d' % f, (0, -5.2, z + 0.06), (10.8, 0.6, 0.06), scaffold)
    for i in range(4):
        poly_tube('斜拉_%d' % i, [(-5.4 + i * 2.7, -5.5, 0.2), (-2.7 + i * 2.7, -5.5, 6.0)], 0.04, scaffold, sides=4)
    # partially collapsed scaffold bay
    poly_tube('塌架立杆', [(3.7, -5.9, 9.0), (4.3, -6.3, 6.2), (4.1, -6.0, 3.4)], 0.05, scaffold, sides=4)
    # dust netting: two panels, one torn short
    quad('防尘网_1', (-3.0, -5.6, 8.6), (1, 0), 5.0, 5.2, tarp, 'matte', (0, -1, 0))
    quad('防尘网_2', (2.6, -5.6, 7.4), (1, 0), 4.0, 3.4, tarp, 'matte', (0, -1, 0))
    bx('网破口', (-0.4, -5.62, 9.6), (1.2, 0.04, 1.0), 'sand')
    # ground debris and a site barrier
    for i, (x, y, s) in enumerate(((-4.6, -5.6, 0.9), (-2.4, -5.9, 0.7), (1.7, -5.7, 1.1), (4.2, -5.8, 0.6))):
        bx('弃料_%d' % i, (x, y, s * 0.4), (s, s * 0.7, s * 0.5), slab, bevel=0.03, rot=(0, 0, i * 0.6))
    bx('围挡', (0, -6.3, 0.55), (7.4, 0.1, 1.1), tarp, rot=(0, 0, 0.04))
    bx('围挡斜撑', (-3.0, -6.05, 0.45), (0.09, 0.9, 0.09), scaffold, rot=(-0.55, 0, 0))
    bx('围挡斜撑', (2.6, -6.05, 0.45), (0.09, 0.9, 0.09), scaffold, rot=(-0.55, 0, 0))


def build_walkup_apartment():
    """Four floors, ivory shell, three balcony bays, hanging AC units."""
    shell, balcony, glass = 'white', 'cream', 'ocean'
    glass2, ac, roofc, rail = 'solar', 'silver', 'snow', 'steel'
    FH, FLOORS = 2.6, 4
    H = FH * FLOORS
    poly = [(-4.3, -3.8), (4.3, -3.8), (4.3, 3.8), (-4.3, 3.8)]
    prism('楼壳', poly, 0.0, H, shell, bevel=0.09, seg=2)
    for f in range(1, FLOORS):
        bx('层间线脚_%d' % f, (0, 0, f * FH - 0.04), (8.7, 7.7, 0.14), balcony)
    prism('屋面', [(x * 1.02, y * 1.02) for x, y in poly], H, 0.2, roofc, bevel=0.05)
    for i, (a, b) in enumerate((((-4.3, -3.9), (4.3, -3.9)), ((4.4, -3.8), (4.4, 3.8)),
                                ((4.3, 3.9), (-4.3, 3.9)), ((-4.4, 3.8), (-4.4, -3.8)))):
        if i == 0 and True:
            continue  # front parapet is replaced by balcony bays below
        c = Vector(((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, H + 0.32))
        L = math.hypot(b[0] - a[0], b[1] - a[1])
        bx('女儿墙_%d' % i, c, (L, 0.2, 0.44), balcony, bevel=0.03,
           rot=(0, 0, math.atan2(b[1] - a[1], b[0] - a[0])))
    # windows: rear and sides
    win_row('后窗', (-3.9, 3.8), (3.9, 3.8), (0, 1), 0.0, FLOORS, FH, 4, glass, glass2)
    win_row('东窗', (4.3, -3.4), (4.3, 3.4), (1, 0), 0.0, FLOORS, FH, 2, glass, glass2)
    win_row('西窗', (-4.3, 3.4), (-4.3, -3.4), (-1, 0), 0.0, FLOORS, FH, 2, glass, glass2, skip={(1, 0)})
    # front: three bays of balconies on floors 2-4, windows on floor 1
    win_row('前窗底', (-3.9, -3.8), (3.9, -3.8), (0, -1), 0.0, 1, FH, 4, glass, glass2)
    for f in (1, 2, 3):
        for c in (-2.6, 0.0, 2.6):
            bx('阳台板_%d_%d' % (f, int(c * 10)), (c, -4.35, f * FH + 0.08), (2.3, 1.2, 0.16), balcony)
            bx('阳台栏板_%d_%d' % (f, int(c * 10)), (c, -4.92, f * FH + 0.52), (2.3, 0.1, 0.8), balcony)
            bx('阳台侧板_%d_%d' % (f, int(c * 10)), (c - 1.12, -4.35, f * FH + 0.52), (0.1, 1.2, 0.8), balcony)
            bx('阳台侧板_%d_%d' % (f, int(c * 10)), (c + 1.12, -4.35, f * FH + 0.52), (0.1, 1.2, 0.8), balcony)
            quad('阳台窗_%d_%d' % (f, int(c * 10)), (c, -3.83, f * FH + 1.5), (1, 0), 1.5, 1.2,
                 glass if (f + int(c)) % 2 else glass2, 'gloss', (0, -1, 0))
    # drying rods and a bare frame
    for f in (1, 3):
        poly_tube('晾衣杆_%d' % f, [(-3.6, -4.9, f * FH + 1.75), (3.6, -4.9, f * FH + 1.72)], 0.025, rail, sides=4)
    poly_tube('空衣架', ([-0.5, -4.9, 4.4], [-0.5, -4.9, 4.85]), 0.04, rail, sides=4)
    # air conditioners, one hanging off its bracket
    for i, (x, z) in enumerate(((-3.4, 3.0), (1.4, 3.0), (3.4, 5.6), (-1.4, 8.2))):
        bx('空调外机_%d' % i, (x, -4.05, z), (0.66, 0.52, 0.46), ac, role='metal', bevel=0.02,
           rot=(0.3, 0, 0) if i == 3 else (0, 0, 0))
        cy('风扇_%d' % i, (x, -4.3, z), 0.17, 0.04, 'gray', role='metal', n=10, axis='Y')
    # entrance, canopy and mailboxes
    quad('单元门', (0.0, -3.82, 1.35), (1, 0), 1.5, 2.6, 'wood_mid', 'matte', (0, -1, 0))
    bx('门雨棚', (0.0, -4.3, 2.95), (2.6, 1.0, 0.14), balcony, bevel=0.03)
    bx('信箱', (2.2, -3.95, 1.15), (0.9, 0.18, 0.5), 'steel', role='metal', bevel=0.02)
    # damage: chipped soffits, a blackened window, stains
    for i in range(4):
        quad('阳台底面破损_%d' % i, (-2.6 + i * 2.2, -4.35, 2.52), (1, 0), 0.8, 0.24, 'sand', 'matte', (0, 0, -1))
    quad('烧黑窗', (3.4, -3.84, 6.9), (1, 0), 1.4, 1.1, 'slate', 'matte', (0, -1, 0))
    for i in range(3):
        bx('墙面水渍_%d' % i, (-3.2 + i * 2.4, -3.84, 6.2), (0.4, 0.03, 2.4), 'gray')


BUILDERS = {
    'broken_viaduct': build_broken_viaduct,
    'l_apartment_fire_escape': build_l_apartment_fire_escape,
    'food_truck': build_food_truck,
    'mcdonalds_restaurant': build_mcdonalds_restaurant,
    'highrise_apartment': build_highrise_apartment,
    'traffic_light': build_traffic_light,
    'utility_poles': build_utility_poles,
    'highway_sign': build_highway_sign,
    'construction_shell': build_construction_shell,
    'walkup_apartment': build_walkup_apartment,
}

bpy.context.window.scene = MASTER
catalog = []
collections = {}
for item in P['components']:
    key = item['key']
    cur = bpy.data.collections.new(item['asset_id'])
    BODY.children.link(cur)
    collections[key] = cur
    CUR[0] = cur
    COUNT[0] = 0
    PARTS.clear()
    BUILDERS[key]()
    objs = list(cur.objects)
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.object
    o.name = key
    o.data.name = key
    me = o.data
    # normalize: origin at bottom centre of the real envelope
    pts = [v.co for v in me.vertices]
    lo = Vector([min(p[i] for p in pts) for i in range(3)])
    hi = Vector([max(p[i] for p in pts) for i in range(3)])
    off = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
    me.transform(Matrix.Translation(-off))
    cur.instance_offset = (0, 0, 0)
    o['asset_id'] = item['asset_id']
    o['category'] = 'underwater_scenic_building'
    o['building_class'] = 'underwater'
    o['collision'] = 'none'
    o['interactive'] = False
    me.calc_loop_triangles()
    tris = len(me.loop_triangles)
    budget = item['triangle_budget']
    if os.environ.get('SEA_BUILD_DEBUG'):
        print('DBG %s parts %d' % (key, len(objs)), flush=True)
    if tris > budget:
        print('TOP PARTS %s:' % key, flush=True)
        for t, n in sorted(PARTS, reverse=True)[:14]:
            print('   %5d  %s' % (t, n), flush=True)
    assert tris <= budget, '%s over budget: %d > %d' % (key, tris, budget)
    for m in me.materials:
        assert m.name in ('SEA_Matte', 'SEA_Metal', 'SEA_Gloss'), m.name
    row = dict(item,
               polygons=len(me.polygons), triangles=tris,
               parts=COUNT[0],
               bounds_min=[round(v, 4) for v in (lo - off)],
               bounds_max=[round(v, 4) for v in (hi - off)],
               origin=[0, 0, 0], material_roles=sorted({m.name for m in me.materials}),
               collision='none', interactive=False, emission=False,
               collection=item['asset_id'])
    catalog.append(row)
    print('%-26s %4d parts %5d polys %5d tris  budget %5d  %s' %
          (key, COUNT[0], len(me.polygons), tris, budget, 'OK' if tris <= budget else 'OVER'), flush=True)

# reference layout: traceable only, the Godot TSCN owns runtime placement
instances = []
# AABB separation guard: a sunken street must read as ten separate buildings, not a pile.
boxes = []
for row in catalog:
    rot = math.radians(row['rotation_y_degrees'])
    cs, sn = abs(math.cos(rot)), abs(math.sin(rot))
    sx, sy = row['size_blender_xyz'][0], row['size_blender_xyz'][1]
    ex, ey = sx * cs + sy * sn, sx * sn + sy * cs
    px, _, pz = row['placement_godot']
    boxes.append((row['key'], px - ex / 2, px + ex / 2, pz - ey / 2, pz + ey / 2))
for i in range(len(boxes)):
    for j in range(i + 1, len(boxes)):
        a, b = boxes[i], boxes[j]
        gx = max(b[1] - a[2], a[1] - b[2])
        gz = max(b[3] - a[4], a[3] - b[4])
        gap = max(gx, gz)
        assert gap >= 1.0, '%s and %s overlap or are closer than 1.0 m (gap %.2f)' % (a[0], b[0], gap)
for row in catalog:
    x, y, z = row['placement_godot']
    o = bpy.data.objects.new(row['key'], None)
    LAYOUT.objects.link(o)
    o.instance_type = 'COLLECTION'
    o.instance_collection = collections[row['key']]
    o.location = (x, -z, y)
    o.rotation_euler = (0, 0, math.radians(row['rotation_y_degrees']))
    instances.append(dict(instance_id='submerged_street/' + row['key'], asset_id=row['asset_id'], key=row['key'],
                          position=[round(v, 3) for v in o.location],
                          rotation_euler_xyz=[0.0, 0.0, math.radians(row['rotation_y_degrees'])],
                          scale=[1, 1, 1]))

bpy.context.window.scene = SCENE
SCENE.render.engine = 'CYCLES'
SCENE.cycles.samples = 24
SCENE.cycles.use_denoising = True
SCENE.render.resolution_x = 1280
SCENE.render.resolution_y = 960
SCENE.render.resolution_percentage = 100
SCENE.view_settings.view_transform = 'Standard'
SCENE.view_settings.look = 'None'
SCENE.world = bpy.data.worlds.new('沉没街道_深蓝展示')
SCENE.world.use_nodes = True
bg = SCENE.world.node_tree.nodes['Background']
bg.inputs[0].default_value = (0.055, 0.135, 0.175, 1)
bg.inputs[1].default_value = 0.9
for name, loc, power, size in (('主光', (-22, -30, 46), 26000, 26), ('补光', (26, 14, 30), 12000, 22),
                               ('顶光', (2, 2, 62), 9000, 30)):
    data = bpy.data.lights.new(name, 'AREA')
    data.energy = power
    data.shape = 'DISK'
    data.size = size
    lo_ = bpy.data.objects.new(name, data)
    STAGE.objects.link(lo_)
    lo_.location = loc
    lo_.rotation_euler = (Vector((0, 0, 6)) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
cam = bpy.data.cameras.new('固定参考镜头')
cam_o = bpy.data.objects.new('固定参考镜头', cam)
STAGE.objects.link(cam_o)
SCENE.camera = cam_o
cam.type = 'ORTHO'
cam.ortho_scale = 60

IMG.filepath = bpy.path.relpath(str(PAL_PATH), start=str(D))
bpy.ops.wm.save_as_mainfile(filepath=str(D / 'submerged_street.blend'))
write(D / 'catalog.json', {'schema': 'sea.scene_catalog', 'version': 'v001', 'components': catalog})
write(D / 'component_instances.json', {
    'coordinate_contract': {'plane': 'XY', 'up': '+Z', 'rotation': 'Euler XYZ radians', 'godot': '(x,y,z) -> (x,z,-y)'},
    'note': 'Reference layout only; the formal Godot TSCN owns runtime placement.',
    'instances': instances})
print('SOURCE_COMPLETE', D, 'components', len(catalog),
      'triangles', sum(r['triangles'] for r in catalog), flush=True)
