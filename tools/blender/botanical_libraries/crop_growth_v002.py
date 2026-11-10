"""Build SEA planting growth library v002. Source-only; never edits runtime or v001."""
import bpy, hashlib, json, math, os, sys
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[3]
PLAN_PATH = ROOT / 'art_source/crops/libraries/v002/component_plan.json'
OUT_DIR = ROOT / 'art_source/crops/libraries/v002'
BLEND_PATH = OUT_DIR / 'planting_library.blend'
MANIFEST_PATH = OUT_DIR / 'library_manifest.json'
WORK = Path('D:/projects/sea-work/botanical_growth/v002/crops')
PALETTE = ROOT / 'art_source/shared/palettes/sea_cozy_8x8_512.png'
PALETTE_JSON = ROOT / 'art_source/shared/palettes/sea_cozy_8x8_512.json'
FONT = Path('C:/Windows/Fonts/msyh.ttc')

PLANTS = [
    ('SEA-CROP-LETTUCE', '生菜', 'lettuce'),
    ('SEA-CROP-TOMATO', '番茄', 'tomato'),
    ('SEA-CROP-PUMPKIN', '南瓜', 'pumpkin'),
    ('SEA-CROP-FLOWER-BLUE', '蓝星花', 'blue'),
    ('SEA-CROP-FLOWER-SUN', '晨光花', 'sun'),
    ('SEA-CROP-FLOWER-CORAL', '珊瑚花', 'coral'),
]
GROWTH = [('small', '小'), ('medium', '中'), ('large', '大')]
# PaletteUV cells are resolved by the project's authoritative palette JSON.
PALETTE_DATA = json.loads(PALETTE_JSON.read_text(encoding='utf-8'))
PALETTE_CELLS = {cell['name']: (cell['row'], cell['column']) for cell in PALETTE_DATA['cells']}
for _required in ('leaf', 'leaf_mid', 'leaf_light', 'leaf_dark', 'red', 'coral', 'gold', 'blue', 'sky', 'pink', 'cream', 'ochre'):
    if _required not in PALETTE_CELLS:
        raise RuntimeError('公共色板缺少命名色格: ' + _required)
# Semantic names below are aliases to authoritative JSON cell names, never hand-coded rows/columns.
PALETTE_CELLS.update({
    'stem': PALETTE_CELLS['leaf_dark'],
    'fruit_red': PALETTE_CELLS['red'],
    'fruit_green': PALETTE_CELLS['leaf_mid'],
    'fruit_orange': PALETTE_CELLS['ochre'],
    'flower_blue': PALETTE_CELLS['blue'],
    'flower_yellow': PALETTE_CELLS['gold'],
    'flower_pink': PALETTE_CELLS['pink'],
    'flower_coral': PALETTE_CELLS['coral'],
    'center': PALETTE_CELLS['cream'],
})

PLAN = json.loads(PLAN_PATH.read_text(encoding='utf-8'))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def new_collection(name, parent=None):
    c = bpy.data.collections.new(name)
    (parent or bpy.context.scene.collection).children.link(c)
    c.instance_offset = (0.0, 0.0, 0.0)
    return c


def tag_collection(c, **props):
    for key, value in props.items():
        c[key] = value
    try:
        c.asset_mark()
    except Exception:
        pass
    try:
        c.asset_data.description = f"{props.get('display_name', c.name)} | SEA-CROP growth v002 | source-only"
        c.asset_data.author = 'sea'
        c.asset_data.tags.new('sea')
        c.asset_data.tags.new('crop')
        c.asset_data.tags.new('growth_v002')
    except Exception:
        pass


def material(name, cell, roughness, metallic=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    n = m.node_tree.nodes
    l = m.node_tree.links
    n.clear()
    out = n.new('ShaderNodeOutputMaterial')
    bs = n.new('ShaderNodeBsdfPrincipled')
    tex = n.new('ShaderNodeTexImage')
    uv = n.new('ShaderNodeUVMap')
    tex.image = bpy.data.images.load(str(PALETTE), check_existing=True)
    tex.interpolation = 'Closest'
    uv.uv_map = 'PaletteUV'
    l.new(uv.outputs['UV'], tex.inputs['Vector'])
    l.new(tex.outputs['Color'], bs.inputs['Base Color'])
    bs.inputs['Roughness'].default_value = roughness
    bs.inputs['Metallic'].default_value = metallic
    l.new(bs.outputs['BSDF'], out.inputs['Surface'])
    m['material_role'] = name
    m['palette_path'] = 'art_source/shared/palettes/sea_cozy_8x8_512.png'
    m['palette_sha256'] = sha(PALETTE)
    m['palette_cell'] = list(cell)
    return m


MAT_MATTE = None
MAT_GLOSS = None


def uv_for_cell(cell, flip=False):
    row, col = cell
    # Image origin is top-left; Blender UV origin is bottom-left.
    u0 = col / 8.0 + 8.0 / 512.0
    u1 = (col + 1) / 8.0 - 8.0 / 512.0
    v0 = 1.0 - (row + 1) / 8.0 + 8.0 / 512.0
    v1 = 1.0 - row / 8.0 - 8.0 / 512.0
    return [(u0, v0), (u1, v0), (u1, v1), (u0, v1)] if not flip else [(u1, v0), (u0, v0), (u0, v1), (u1, v1)]


def make_mesh(name, verts, faces, cell, smooth=True, mat=None, organ='leaf'):
    # 圆润实体的根部封盖不能越过统一的 Z=0 根平面。
    verts = [(x, y, max(0.0, z)) for x, y, z in verts]
    me = bpy.data.meshes.new(name + '_Mesh')
    me.from_pydata(verts, [], faces)
    me.update(calc_edges=True)
    uv = me.uv_layers.new(name='PaletteUV')
    quad = uv_for_cell(PALETTE_CELLS[cell])
    for poly in me.polygons:
        poly.use_smooth = smooth
        if len(poly.loop_indices) > 4:
            center_u = sum(p[0] for p in quad) / 4.0
            center_v = sum(p[1] for p in quad) / 4.0
            radius_u = (quad[1][0] - quad[0][0]) * 0.34
            radius_v = (quad[2][1] - quad[1][1]) * 0.34
            count = len(poly.loop_indices)
            for index, loop_idx in enumerate(poly.loop_indices):
                angle = 2.0 * math.pi * index / count
                uv.data[loop_idx].uv = (center_u + radius_u * math.cos(angle), center_v + radius_v * math.sin(angle))
        else:
            for li, loop_idx in enumerate(poly.loop_indices):
                uv.data[loop_idx].uv = quad[li % 4]
    me.materials.append(mat or MAT_MATTE)
    me['organ_type'] = organ
    me['palette_uv_contract'] = '8px_safe_in_cell'
    me['material_role'] = (mat or MAT_MATTE).name
    return me


def add_mesh(c, name, verts, faces, cell, organ='leaf', smooth=True, gloss=False):
    me = make_mesh(name, verts, faces, cell, smooth, MAT_GLOSS if gloss else MAT_MATTE, organ)
    ob = bpy.data.objects.new(name, me)
    c.objects.link(ob)
    ob['organ_type'] = organ
    ob['material_role'] = me['material_role']
    ob['source_transform_identity'] = True
    return ob


def add_ellipsoid(c, name, center, scale, cell, organ='fruit', segments=8, rings=5, gloss=False):
    verts = []
    faces = []
    for r in range(rings + 1):
        phi = math.pi * r / rings
        for s in range(segments):
            th = 2 * math.pi * s / segments
            verts.append((center[0] + scale[0] * math.sin(phi) * math.cos(th), center[1] + scale[1] * math.sin(phi) * math.sin(th), center[2] + scale[2] * math.cos(phi)))
    for r in range(rings):
        for s in range(segments):
            a = r * segments + s; b = r * segments + (s + 1) % segments
            c0 = (r + 1) * segments + (s + 1) % segments; d = (r + 1) * segments + s
            if r == 0: faces.append((a, c0, d))
            elif r == rings - 1: faces.append((a, b, c0))
            else: faces.extend(((a, b, c0), (a, c0, d)))
    return add_mesh(c, name, verts, faces, cell, organ, True, gloss)


def add_ridged_pumpkin(c, name, center, scale, cell='fruit_orange'):
    segments, rings = 10, 5
    verts = []
    faces = []
    for r in range(rings + 1):
        phi = math.pi * r / rings
        for s in range(segments):
            th = 2 * math.pi * s / segments
            ridge = 1.0 + 0.20 * math.cos(5 * th)
            verts.append((center[0] + scale[0] * ridge * math.sin(phi) * math.cos(th), center[1] + scale[1] * ridge * math.sin(phi) * math.sin(th), center[2] + scale[2] * math.cos(phi)))
    for r in range(rings):
        for s in range(segments):
            a = r * segments + s; b = r * segments + (s + 1) % segments
            c0 = (r + 1) * segments + (s + 1) % segments; d = (r + 1) * segments + s
            if r == 0: faces.append((a, c0, d))
            elif r == rings - 1: faces.append((a, b, c0))
            else: faces.extend(((a, b, c0), (a, c0, d)))
    return add_mesh(c, name, verts, faces, cell, 'fruit', True, True)


def add_stem(c, name, a, b, radius, cell='stem', organ='stem', sides=7, taper=0.58):
    a, b = Vector(a), Vector(b)
    axis = b - a
    q = axis.to_track_quat('Z', 'Y')
    verts = []
    for ring, p in enumerate((a, b)):
        ring_radius = radius if ring == 0 else radius * taper
        for i in range(sides):
            ang = 2 * math.pi * i / sides
            v = Vector((ring_radius * math.cos(ang), ring_radius * math.sin(ang), 0.0))
            verts.append(tuple(p + q @ v))
    faces = []
    for i in range(sides):
        j = (i + 1) % sides
        faces.extend(((i, j, sides + j), (i, sides + j, sides + i)))
    faces.append(tuple(range(sides - 1, -1, -1)))
    faces.append(tuple(range(sides, 2 * sides)))
    ob = add_mesh(c, name, verts, faces, cell, organ, True, False)
    ob['taper_ratio'] = taper
    return ob


def add_leaf(c, name, base, tip, width, thickness, cell='leaf', lean=0.0, longitudinal=4, across=4):
    base, tip = Vector(base), Vector(tip)
    axis = tip - base
    w = axis.normalized()
    # side.cross(w) is the actual sheet normal. Keep its upward component positive.
    side = w.cross(Vector((0, 0, 1)))
    if side.length < 0.05:
        side = w.cross(Vector((0, 1, 0)))
    side.normalize()
    normal = side.cross(w).normalized()
    if normal.z < 0:
        side = -side
        normal = side.cross(w).normalized()
    verts = []
    for i in range(longitudinal + 1):
        t = i / longitudinal
        curve = lean * math.sin(math.pi * t) + thickness * 0.55 * math.sin(math.pi * t)
        center = base + axis * t + normal * curve
        # Keep a rounded, non-zero tip and base instead of collapsing to zero-area caps.
        half = max(width * 0.055, width * (0.08 + 0.92 * math.sin(math.pi * t) ** 0.55))
        half_thickness = max(thickness * 0.42, thickness * (0.72 + 0.28 * math.sin(math.pi * t)))
        for j in range(across + 1):
            u = j / across * 2 - 1
            bulge = 0.72 + 0.28 * (1.0 - u * u)
            center_j = center + side * (half * u)
            verts.append(tuple(center_j + normal * (half_thickness * bulge)))
            verts.append(tuple(center_j - normal * (half_thickness * bulge)))
    faces = []
    stride = (across + 1) * 2
    top = lambda i, j: i * stride + j * 2
    bottom = lambda i, j: i * stride + j * 2 + 1
    for i in range(longitudinal):
        for j in range(across):
            a, b = top(i, j), top(i + 1, j)
            c0, d = top(i + 1, j + 1), top(i, j + 1)
            # Top and bottom winding are opposite; all are quads with non-zero UV islands.
            faces.append((a, d, c0, b))
            a, b = bottom(i, j), bottom(i + 1, j)
            c0, d = bottom(i + 1, j + 1), bottom(i, j + 1)
            faces.append((a, b, c0, d))
            if j == 0:
                faces.append((top(i, j), bottom(i, j), bottom(i + 1, j), top(i + 1, j)))
            if j == across - 1:
                faces.append((top(i, j + 1), top(i + 1, j + 1), bottom(i + 1, j + 1), bottom(i, j + 1)))
    for j in range(across):
        faces.append((top(0, j), bottom(0, j), bottom(0, j + 1), top(0, j + 1)))
        end = longitudinal
        faces.append((top(end, j + 1), bottom(end, j + 1), bottom(end, j), top(end, j)))
    return add_mesh(c, name, verts, faces, cell, 'leaf', True, False)


def add_petal(c, name, center, direction, length, width, thickness, cell, gloss=True):
    d = Vector(direction).normalized()
    base = Vector(center) - d * length * 0.45
    tip = Vector(center) + d * length * 0.55
    return add_leaf(c, name, base, tip, width, thickness, cell, lean=thickness * 0.25, longitudinal=2, across=2)


def flower(c, prefix, center, style, mature):
    if style == 'blue': count, length, width, cell = 5, 0.13 if mature else 0.075, 0.045 if mature else 0.026, 'flower_blue'
    elif style == 'sun': count, length, width, cell = 10, 0.15 if mature else 0.08, 0.050 if mature else 0.028, 'flower_yellow'
    else: count, length, width, cell = 6, 0.11 if mature else 0.07, 0.055 if mature else 0.034, 'flower_coral'
    if not mature:
        add_ellipsoid(c, prefix + '_花蕾', center, (width * 0.8, width * 0.8, length * 0.75), cell, 'flower', 7, 4, True)
        return
    for i in range(count):
        ang = 2 * math.pi * i / count
        direction = (math.cos(ang), math.sin(ang), 0.12 if style != 'coral' else 0.2)
        add_petal(c, f'{prefix}_花瓣{i+1:02}', center, direction, length, width, 0.012, cell, True)
    add_ellipsoid(c, prefix + '_花心', center, (width * 0.62, width * 0.62, width * 0.45), 'center', 'flower', 8, 4, True)


def make_plant(c, kind, growth, display):
    p = PLAN['plants'][next(i for i, x in enumerate(PLAN['plants']) if x['asset_id'] == c['asset_id'])]
    spec = p['growth_forms'][growth]
    h = spec['height_m']; cw, cd = spec['crown_m']
    organs = spec['organs']
    seed = {'small': 0, 'medium': 1, 'large': 2}[growth]
    if kind == 'lettuce':
        add_stem(c, '短茎', (0, 0, 0), (0, 0, h * 0.25), 0.025 + seed * 0.004)
        for i in range(organs['leaves']):
            ang = 2 * math.pi * i / organs['leaves'] + (0.16 if growth == 'medium' else 0.0)
            z0 = h * (0.10 + 0.025 * (i % 3))
            rad = (cw * 0.18 if growth == 'small' else cw * (0.27 + 0.025 * (i % 3)))
            tip = (math.cos(ang) * cw * 0.48, math.sin(ang) * cd * 0.48, h * (0.56 + 0.15 * math.sin(ang + 0.8)))
            add_leaf(c, f'菜叶{i+1:02}', (math.cos(ang) * 0.03, math.sin(ang) * 0.03, z0), tip, rad, 0.018 + seed * 0.004, 'leaf_light' if i % 3 == 0 else 'leaf')
        if growth == 'large': add_ellipsoid(c, '结球心', (0, 0, h * 0.52), (cw * 0.20, cd * 0.20, h * 0.22), 'leaf_light', 'leaf', 8, 5)
    elif kind == 'tomato':
        add_stem(c, '主茎', (0, 0, 0), (0.012, -0.008, h * 0.86), 0.022 + seed * 0.006, taper=0.48)
        branches = organs['stems'] - 1
        branch_ends = []
        for i in range(branches):
            ang = 2 * math.pi * i / max(1, branches) + 0.4
            z = h * (0.36 + (i % 3) * 0.16)
            end = (math.cos(ang) * cw * 0.42, math.sin(ang) * cd * 0.42, min(h * 0.82, z + h * 0.18))
            branch_ends.append(end)
            add_stem(c, f'侧枝{i+1:02}', (0, 0, z), end, 0.017 + seed * 0.003, taper=0.52)
        for i in range(organs['leaves']):
            ang = 2 * math.pi * i / organs['leaves'] + 0.3
            z = h * (0.22 + (i % 5) * 0.13)
            base = (0.0, 0.0, z)
            tip = (math.cos(ang) * cw * 0.55, math.sin(ang) * cd * 0.55, z + h * (0.08 + 0.04 * (i % 2)))
            if growth == 'small':
                tip = (math.cos(ang) * cw * 0.76, math.sin(ang) * cd * 0.76, z + h * (0.10 + 0.03 * (i % 2)))
            leaf_width = cw * (0.38 if growth == 'small' else 0.15 + 0.015 * seed)
            add_leaf(c, f'复叶{i+1:02}', base, tip, leaf_width, 0.022 + seed * 0.004, 'leaf_mid' if i % 2 else 'leaf')
        if growth == 'medium':
            bud = Vector((cw * 0.28, -cd * 0.18, h * 0.72))
            add_stem(c, '小花梗', (0, 0, h * 0.64), bud, 0.008, 'stem', 'flower_stem', 6, taper=0.62)
            flower(c, '小花', bud, 'sun', False)
            for i in range(2):
                ang = i * 2.7 + 0.4
                fruit = Vector((math.cos(ang) * cw * 0.30, math.sin(ang) * cd * 0.30, h * (0.54 + i * 0.11)))
                ped_base = min((Vector(p) for p in branch_ends), key=lambda p: (p.x - fruit.x) ** 2 + (p.y - fruit.y) ** 2 + (p.z - fruit.z) ** 2)
                add_stem(c, f'青果梗{i+1:02}', ped_base, fruit + Vector((0, 0, 0.018)), 0.009, 'stem', 'fruit_stem', 6, taper=0.62)
                add_ellipsoid(c, f'青果{i+1:02}', fruit, (0.048, 0.048, 0.058), 'fruit_green', 'fruit', 8, 5, True)
        if growth == 'large':
            for i in range(5):
                ang = 2 * math.pi * i / 5 + 0.3
                fruit = Vector((math.cos(ang) * cw * 0.38, math.sin(ang) * cd * 0.38, h * (0.32 + (i % 3) * 0.15)))
                ped_base = min((Vector(p) for p in branch_ends), key=lambda p: (p.x - fruit.x) ** 2 + (p.y - fruit.y) ** 2 + (p.z - fruit.z) ** 2)
                add_stem(c, f'红果梗{i+1:02}', ped_base, fruit + Vector((0, 0, 0.022)), 0.010, 'stem', 'fruit_stem', 6, taper=0.62)
                add_ellipsoid(c, f'红果{i+1:02}', fruit, (0.068, 0.068, 0.078), 'fruit_red', 'fruit', 8, 5, True)
    elif kind == 'pumpkin':
        segments = organs['stems']
        points = [(0, 0, 0.04)]
        for i in range(1, segments + 1):
            t = i / segments
            points.append(((-1 if i % 2 else 1) * cw * 0.43 * t, math.sin(i * 1.3) * cd * 0.30 * t, 0.04 + h * 0.18 * math.sin(math.pi * t)))
        for i in range(len(points) - 1):
            add_stem(c, f'藤节{i+1:02}', points[i], points[i+1], 0.014 + seed * 0.007, 'stem', 'stem', 7, taper=0.72)
        for i in range(organs['leaves']):
            t = (i + 1) / (organs['leaves'] + 1); base = points[min(len(points)-1, int(t * segments))]
            ang = 2 * math.pi * i / organs['leaves'] + 0.25
            tip = (base[0] + math.cos(ang) * cw * (0.34 if growth == 'small' else 0.30), base[1] + math.sin(ang) * cd * (0.34 if growth == 'small' else 0.30), h * (0.62 if growth == 'small' else 0.42 + 0.12 * (i % 2)))
            add_leaf(c, f'南瓜叶{i+1:02}', base, tip, cw * (0.24 if growth == 'small' else 0.19 + 0.014 * seed), 0.022 + seed * 0.004, 'leaf_mid' if i % 3 else 'leaf')
        if growth == 'large':
            fruit = Vector((cw * 0.22, -cd * 0.18, h * 0.32))
            add_ridged_pumpkin(c, '成熟南瓜', fruit, (0.18, 0.16, 0.14), 'fruit_orange')
            stalk_top = fruit + Vector((0.018, -0.012, 0.22))
            add_stem(c, '瓜蒂', fruit + Vector((0, 0, 0.11)), stalk_top, 0.028, 'stem', 'stem', 7, taper=0.62)
            connector_base = min((Vector(p) for p in points), key=lambda p: (p - stalk_top).length)
            add_stem(c, '瓜果连藤', connector_base, stalk_top, 0.018, 'stem', 'fruit_stem', 6, taper=0.62)
    else:
        base_style = kind
        add_stem(c, '花茎', (0, 0, 0), (0, 0, h * 0.82), 0.014 + seed * 0.004)
        branches = organs['stems'] - 1
        flower_ends = []
        for i in range(branches):
            ang = 2 * math.pi * i / max(1, branches) + 0.25
            z = h * (0.38 + i * 0.10)
            end = (math.cos(ang) * cw * 0.42, math.sin(ang) * cd * 0.42, h * (0.72 + 0.05 * (i % 2)))
            add_stem(c, f'花枝{i+1:02}', (0, 0, z), end, 0.011 + seed * 0.003)
            flower_ends.append(end)
        for i in range(organs['leaves']):
            ang = 2 * math.pi * i / organs['leaves'] + 0.4
            z = h * (0.18 + (i % 4) * 0.14)
            tip = (math.cos(ang) * cw * 0.50, math.sin(ang) * cd * 0.50, z + h * 0.08)
            add_leaf(c, f'花叶{i+1:02}', (0, 0, z), tip, cw * 0.14, 0.012 + seed * 0.002, 'leaf')
        if growth != 'small':
            flower(c, '花冠01', flower_ends[0], base_style, growth == 'large')
            if growth == 'large': flower(c, '花冠02', flower_ends[1], base_style, True)


def identity(o):
    return all(abs(o.matrix_world[i][j] - (1 if i == j else 0)) < 1e-6 for i in range(4) for j in range(4))


def bounds(c):
    points = [v.co.copy() for o in c.objects if o.type == 'MESH' for v in o.data.vertices]
    mn = Vector((min(v.x for v in points), min(v.y for v in points), min(v.z for v in points)))
    mx = Vector((max(v.x for v in points), max(v.y for v in points), max(v.z for v in points)))
    return [list(mn), list(mx)]


def fingerprint(c):
    payload = []
    for o in sorted([x for x in c.objects if x.type == 'MESH'], key=lambda x: x.name):
        me = o.data; me.calc_loop_triangles()
        payload.append({'name': o.name, 'organ': o.get('organ_type'), 'v': [[round(v.co[i], 6) for i in range(3)] for v in me.vertices], 'f': [list(p.vertices) for p in me.polygons], 'uv': [[round(u.uv[i], 7) for i in range(2)] for u in me.uv_layers['PaletteUV'].data]})
    return hashlib.sha256(json.dumps(payload, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def triangles(c):
    total = 0
    for o in c.objects:
        if o.type == 'MESH':
            o.data.calc_loop_triangles(); total += len(o.data.loop_triangles)
    return total


def organs(c):
    result = {'leaves': 0, 'stems': 0, 'flowers': 0, 'fruits': 0}
    for o in c.objects:
        key = o.get('organ_type')
        if key == 'leaf': result['leaves'] += 1
        elif key == 'stem': result['stems'] += 1
        elif key == 'flower': result['flowers'] += 1
        elif key == 'fruit': result['fruits'] += 1
    return result


def add_label(parent, text, location, size=0.13):
    cu = bpy.data.curves.new('中文标签曲线', 'FONT')
    cu.body = text; cu.align_x = 'CENTER'; cu.size = size; cu.extrude = 0.002
    if FONT.is_file(): cu.font = bpy.data.fonts.load(str(FONT))
    ob = bpy.data.objects.new('标签_' + text, cu); parent.objects.link(ob); ob.location = location
    # Face the comparison camera instead of lying flat on the ground plane.
    ob.rotation_euler = (math.pi * 0.5, 0.0, 0.0)
    cu.materials.append(MAT_MATTE)
    return ob


def setup_scene1(masters):
    scene = bpy.data.scenes.new('01_小中大对照')
    root = new_collection('01_小中大对照_CollectionInstance', scene.collection)
    support = new_collection('01_标签支持_非植物', scene.collection)
    for pi, (aid, display, kind) in enumerate(PLANTS):
        y = -pi * 1.65
        add_label(support, display, (-1.25, y, 0.02), 0.16)
        for gi, (growth, label) in enumerate(GROWTH):
            name = f'{display}_{label}__{aid}'
            src = bpy.data.collections.get(name)
            ob = bpy.data.objects.new('Instance_' + name, None); root.objects.link(ob)
            ob.instance_type = 'COLLECTION'; ob.instance_collection = src; ob.location = (gi * 1.25, y, 0)
            ob['asset_id'] = aid; ob['growth_key'] = growth; ob['display_name'] = display
            add_label(support, label, (gi * 1.25, y - 0.52, 0.02), 0.11)
    scene['scene_role'] = 'comparison_collection_instances'; scene['source_only'] = True
    return scene


def setup_scene2(master_root):
    scene = bpy.data.scenes.new('02_植物母版')
    scene.collection.children.link(master_root)
    scene['scene_role'] = 'plant_master_collections'; scene['source_only'] = True
    return scene


def camera_lights(scene, target, ortho, resolution=(1800, 1200)):
    world = bpy.data.worlds.new(scene.name + '_World'); world.use_nodes = True
    world.node_tree.nodes['Background'].inputs['Color'].default_value = (0.70, 0.78, 0.75, 1)
    world.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.55
    scene.world = world
    for i, (loc, energy, size) in enumerate([((2.5, -4, 5), 950, 4.0), ((-3, 2, 3), 600, 3.0)]):
        ld = bpy.data.lights.new(scene.name + '_柔光' + str(i), 'AREA'); ld.energy = energy; ld.shape = 'DISK'; ld.size = size
        ob = bpy.data.objects.new(ld.name, ld); scene.collection.objects.link(ob); ob.location = loc
        ob.rotation_euler = (Vector(target) - ob.location).to_track_quat('-Z', 'Y').to_euler()
    camd = bpy.data.cameras.new(scene.name + '_Camera'); camd.type = 'ORTHO'; camd.ortho_scale = ortho
    cam = bpy.data.objects.new(camd.name, camd); scene.collection.objects.link(cam); cam.location = (3.7, -7.0, 4.8)
    cam.rotation_euler = (Vector(target) - cam.location).to_track_quat('-Z', 'Y').to_euler(); scene.camera = cam
    scene.render.engine = 'BLENDER_EEVEE'; scene.render.resolution_x, scene.render.resolution_y = resolution; scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'; scene.render.film_transparent = False
    scene.view_settings.look = 'AgX - Medium High Contrast'
    return cam


def build():
    if not PALETTE.is_file(): raise RuntimeError('公共色板不存在: ' + str(PALETTE))
    if not PALETTE_JSON.is_file(): raise RuntimeError('公共色板命名JSON不存在: ' + str(PALETTE_JSON))
    if BLEND_PATH.exists():
        if not MANIFEST_PATH.is_file(): raise RuntimeError('拒绝覆盖已有blend：缺少manifest')
        old = json.loads(MANIFEST_PATH.read_text(encoding='utf-8'))
        if old.get('sha256') != sha(BLEND_PATH): raise RuntimeError('拒绝覆盖：已有v002 hash与manifest不一致')
        if '--rebuild-owned' not in sys.argv: raise RuntimeError('已有候选hash一致；需显式--rebuild-owned才修复')
    bpy.ops.wm.read_factory_settings(use_empty=True)
    global MAT_MATTE, MAT_GLOSS
    MAT_MATTE = material('SEA_Matte', PALETTE_CELLS['leaf'], 0.82)
    MAT_GLOSS = material('SEA_Gloss', PALETTE_CELLS['fruit_red'], 0.36)
    master_scene = bpy.context.scene; master_scene.name = '02_植物母版'
    master_root = new_collection('02_植物母版_父集合', master_scene.collection)
    members = []; leaf_cols = []
    for aid, display, kind in PLANTS:
        species = new_collection(display + '__' + aid, master_root)
        tag_collection(species, asset_id=aid, display_name=display, collection_role='species_parent', season_variants=False)
        for growth, label in GROWTH:
            name = f'{display}_{label}__{aid}'
            c = new_collection(name, species)
            tag_collection(c, asset_id=aid, growth_key=growth, display_name=display, growth_label=label, season_variants=False, root_anchor='[0,0,0]', source_only=True)
            c['component_asset'] = True; c['geometry_independent'] = True; c['runtime_integration'] = False
            make_plant(c, kind, growth, display)
            # Normalize only the plant's local root plane, never with object scaling.
            initial_bounds = bounds(c)
            root_offset = Vector(((initial_bounds[0][0] + initial_bounds[1][0]) * 0.5, (initial_bounds[0][1] + initial_bounds[1][1]) * 0.5, initial_bounds[0][2]))
            for o in c.objects:
                if o.type == 'MESH':
                    for v in o.data.vertices:
                        v.co -= root_offset
                    o.data.update()
            for o in c.objects:
                if o.type == 'MESH':
                    if not identity(o): raise RuntimeError('mesh transform non-identity: ' + o.name)
                    if min(v.co.z for v in o.data.vertices) < -1e-6: raise RuntimeError('mesh below root: ' + o.name)
            bb = bounds(c); size = [bb[1][i] - bb[0][i] for i in range(3)]
            if size[0] > 1.30 + 1e-5 or size[1] > 0.90 + 1e-5 or triangles(c) > 1600: raise RuntimeError(f'budget exceeded: {name} {size} {triangles(c)}')
            spec = next(x for x in PLAN['plants'] if x['asset_id'] == aid)['growth_forms'][growth]
            members.append({'asset_id': aid, 'display_name': display, 'growth_key': growth, 'growth_label': label, 'collection': name, 'parent_collection': species.name, 'bounds': bb, 'size_m': size, 'meshes': [{'object': o.name, 'vertices': len(o.data.vertices), 'polygons': len(o.data.polygons), 'triangles': (o.data.calc_loop_triangles() or len(o.data.loop_triangles)), 'organ_type': o.get('organ_type'), 'material_role': o.get('material_role'), 'uv_layers': [u.name for u in o.data.uv_layers]} for o in c.objects if o.type == 'MESH'], 'triangles': triangles(c), 'organ_counts': organs(c), 'geometry_fingerprint': fingerprint(c), 'uv_dependency': {'layer': 'PaletteUV', 'palette': 'art_source/shared/palettes/sea_cozy_8x8_512.png', 'safe_border_px': 8, 'nearest': True}, 'material_dependency': ['SEA_Matte', 'SEA_Gloss'], 'root_anchor': [0, 0, 0], 'instance_offset': [0, 0, 0], 'season_variants': False, 'primary_source_migration': False, 'runtime_integration': False, 'v001_reference': PLAN['v001_reference']['manifest'], 'budget_reference': spec['description']})
            leaf_cols.append(c)
    scene1 = setup_scene1(master_root)
    cam1 = camera_lights(scene1, (0.6, -4.1, 0.4), 10.4, (2000, 1500))
    # The factory scene is the single master scene; scene1 is the only additional scene.
    # Do not create a third duplicate master scene.
    camera_lights(master_scene, (0, 0, 0.35), 2.2, (1200, 1000))
    bpy.context.window.scene = scene1
    manifest = {'schema_version': 2, 'library_id': 'SEA-LIB-PLANTING-GROWTH-V002', 'path': 'art_source/crops/libraries/v002/planting_library.blend', 'sha256': None, 'primary_source_migration': False, 'season_variants': False, 'growth_axis': ['small', 'medium', 'large'], 'plants': [x[0] for x in PLANTS], 'plant_count': 6, 'members': members, 'member_count': len(members), 'scenes': ['01_小中大对照', '02_植物母版'], 'collection_count': len(leaf_cols), 'material_roles': ['SEA_Matte', 'SEA_Gloss'], 'material_count': 2, 'palette': {'path': 'art_source/shared/palettes/sea_cozy_8x8_512.png', 'sha256': sha(PALETTE), 'mapping_json': 'art_source/shared/palettes/sea_cozy_8x8_512.json', 'mapping_json_sha256': sha(PALETTE_JSON), 'mapping_by_name': True, 'safe_border_px': 8, 'uv_layer': 'PaletteUV', 'filter': 'Closest'}, 'font': str(FONT), 'runtime_integration': False, 'v001_protected_reference': 'art_source/crops/libraries/v001/library_manifest.json', 'external_output': 'D:/projects/sea-work/botanical_growth/v002/crops/', 'total_triangles_unique': sum(x['triangles'] for x in members), 'notes': ['18真实独立植物Collection，不是整体缩放副本', '不含土丘、种子、花盆、土框、土壤、平台、收获手持物', '原四阶段Godot行为不改；本库仅源级模型'], 'members_hash_basis': 'geometry_fingerprint_and_per_face_palette_uv'}
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH), check_existing=False)
    manifest['sha256'] = sha(BLEND_PATH)
    MANIFEST_PATH.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    WORK.mkdir(parents=True, exist_ok=True)
    (WORK / 'build_summary.json').write_text(json.dumps({'library_id': manifest['library_id'], 'blend': str(BLEND_PATH), 'manifest': str(MANIFEST_PATH), 'sha256': manifest['sha256'], 'members': 18, 'triangles': manifest['total_triangles_unique']}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('CROP_GROWTH_V002_BUILT ' + json.dumps({'blend': str(BLEND_PATH), 'sha256': manifest['sha256'], 'members': 18, 'triangles': manifest['total_triangles_unique']}, ensure_ascii=False))


if __name__ == '__main__':
    build()
