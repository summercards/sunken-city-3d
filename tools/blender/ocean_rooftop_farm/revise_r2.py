import bpy, math, json, hashlib, random
from pathlib import Path
from mathutils import Vector

R = Path(r'D:/projects/sea')
D = R / 'art_source/scenes/ocean_rooftop_farm/v001'
W = R.parent / 'sea-work/ocean_rooftop_farm/v001'
W.mkdir(parents=True, exist_ok=True)
# Save the safety copy only after the in-memory revision has saved successfully.
sc = bpy.data.scenes['海上屋顶农场_制作与装配_v001']
random.seed(81102)
plan_path = D / 'component_plan.json'
plan = json.loads(plan_path.read_text(encoding='utf-8'))
removed = {'solar_panel', 'leaf_row', 'seedling_row', 'vine_row'}
new_specs = [
    ('roof_tiles', '大块破损屋顶地砖', 'structure', 'roof_tile'),
    ('damaged_column', '剥落露筋混凝土结构柱', 'structure', 'building_damage'),
    ('broken_window', '破裂玻璃与木板封窗', 'fixture', 'facade_damage'),
    ('facade_weathering', '楼体大面积剥落裂缝与水渍', 'structure', 'building_damage')
]
components_plan = [x for x in plan['components'] if x['key'] not in removed]
existing_keys = {x['key'] for x in components_plan}
for key, name, category, family in new_specs:
    if key in existing_keys:
        continue
    components_plan.append({'key': key, 'asset_id': 'SEA-SCENE-ORF-' + key.upper().replace('_', '-'), 'name': name, 'category': category, 'component_family': family, 'origin': 'bottom_center', 'front_axis': 'Blender -Y / Godot +Z', 'allowed_rotation': 'full Euler XYZ on instances', 'scope': 'scene_local', 'collision': 'visual source only; future facility assembly owns projection', 'budget_triangles': 60000, 'budget_source': 'task-authored component ceiling, not a user-supplied cap'})
assert len(components_plan) == 44, 'component plan count changed; revise idempotently without adding duplicate specs'
plan['components'] = components_plan
plan['status'] = 'r2_revised_before_reverification'
plan['revision'] = 'r2_user_2026-11-02: eight floors, no crops or solar panels, large damaged roof tiles and building weathering'
plan['dimension_contract']['visible_floors'] = 8
plan['dimension_contract']['roof_top_z_m'] = 25.6
plan['excluded'] = sorted(set(plan['excluded'] + ['all crop plants and planted crop rows', 'all solar panels']))
plan['roof_surface'] = {'tile_nominal_m': [3, 3], 'tile_thickness_m': 0.10, 'details': ['chipped corners', 'wide cracks', 'large stains', 'exposed substrate', 'subtle height variation']}
plan_path.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
specs = {x['key']: x for x in components_plan}
pal = R / 'art_source/shared/palettes/sea_cabin_timber_8x8_512.png'
colors = {x['name']: x for x in json.loads(pal.with_suffix('.json').read_text(encoding='utf-8'))['cells']}
roles = {n: bpy.data.materials[n] for n in ['SEA_Matte', 'SEA_Metal', 'SEA_Gloss', 'SEA_Emission']}
image = next(im for im in bpy.data.images if 'sea_cabin_timber' in im.name)
image.filepath = str(pal)
image.reload()

# Remove deleted component collections and all current instances; masters are retained for edited families.
for key in removed:
    aid = 'SEA-SCENE-ORF-' + key.upper().replace('_', '-')
    col = bpy.data.collections.get(aid)
    if col:
        for o in list(col.objects):
            bpy.data.objects.remove(o, do_unlink=True)
        bpy.data.collections.remove(col)
for o in list(sc.objects):
    if o.instance_type == 'COLLECTION':
        bpy.data.objects.remove(o, do_unlink=True)


def place_uv(o, cell):
    for old in list(o.data.uv_layers):
        o.data.uv_layers.remove(old)
    uv = o.data.uv_layers.new(name='PaletteUV')
    c = colors[cell]
    u0 = c['column'] / 8
    v0 = 1 - (c['row'] + 1) / 8
    coords = [(.28, .28), (.72, .28), (.72, .72), (.28, .72)]
    for p in o.data.polygons:
        for j, li in enumerate(p.loop_indices):
            uv.data[li].uv = (u0 + coords[j % 4][0] / 8, v0 + coords[j % 4][1] / 8)
    o.data.uv_layers.active = uv
    uv.active_render = True


def finish(o, cell='cream', role='SEA_Matte', bev=.025, smooth=False):
    o.data.materials.clear()
    o.data.materials.append(roles[role])
    place_uv(o, cell)
    for p in o.data.polygons:
        p.material_index = 0
        p.use_smooth = smooth
    if bev:
        m = o.modifiers.new('实体柔边', 'BEVEL')
        m.width = bev
        m.segments = 2 if bev < .06 else 3
    return o


def cube(name, loc, size, cell='cream', role='SEA_Matte', bev=.025, rot=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.object
    o.name = name
    o.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if rot:
        o.rotation_euler = rot
    return finish(o, cell, role, bev)


def cyl(name, loc, r, depth, cell='gray', role='SEA_Metal', verts=20, r2=None, rot=None, bev=.02):
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=loc)
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=r2, depth=depth, location=loc)
    o = bpy.context.object
    o.name = name
    if rot:
        o.rotation_euler = rot
    return finish(o, cell, role, bev, True)


def mesh_obj(name, verts, faces, cell='cream', role='SEA_Matte', bev=0):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    o = bpy.data.objects.new(name, me)
    sc.collection.objects.link(o)
    return finish(o, cell, role, bev)


def tube(name, pts, radius, cell='steel', role='SEA_Metal', resolution=1):
    cu = bpy.data.curves.new(name, 'CURVE')
    cu.dimensions = '3D'
    cu.resolution_u = 1
    cu.bevel_depth = radius
    cu.bevel_resolution = resolution
    sp = cu.splines.new('POLY')
    sp.points.add(len(pts) - 1)
    for p, co in zip(sp.points, pts):
        p.co = (*co, 1)
    o = bpy.data.objects.new(name, cu)
    sc.collection.objects.link(o)
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.convert(target='MESH')
    o = bpy.context.object
    return finish(o, cell, role, 0, True)


def rod(name, a, b, radius, cell='steel', role='SEA_Metal', verts=10):
    a = Vector(a)
    b = Vector(b)
    o = cyl(name, (a + b) / 2, radius, (b - a).length, cell, role, verts, bev=.006)
    o.rotation_euler = (b - a).to_track_quat('Z', 'Y').to_euler()
    return o


def prism(name, coords, z0, z1, cell='stone', bev=.025):
    n = len(coords)
    verts = [(x, y, z0) for x, y in coords] + [(x, y, z1) for x, y in coords]
    faces = [tuple(range(n - 1, -1, -1)), tuple(range(n, 2 * n))]
    faces += [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
    return mesh_obj(name, verts, faces, cell, bev=bev)


def wall_patch(name, center, width, height, cell='stone', side='front'):
    x, y, z = center
    shape = [(-.50, -.32), (-.30, -.50), (.22, -.46), (.50, -.20), (.43, .22), (.20, .50), (-.25, .43), (-.48, .15)]
    if side == 'front':
        verts = [(x + a * width, y, z + b * height) for a, b in shape]
    else:
        verts = [(x, y + a * width, z + b * height) for a, b in shape]
    return mesh_obj(name, verts, [tuple(range(len(verts)))], cell)


def clear_component(key):
    aid = specs[key]['asset_id']
    col = bpy.data.collections.get(aid)
    if col is None:
        col = bpy.data.collections.new(aid)
    for o in list(col.objects):
        if o.type != 'EMPTY':
            bpy.data.objects.remove(o, do_unlink=True)
    root = next((o for o in col.objects if o.type == 'EMPTY'), None)
    if root is None:
        root = bpy.data.objects.new(key + '_组件根', None)
        col.objects.link(root)
    root.location = (0, 0, 0)
    root.rotation_euler = (0, 0, 0)
    root.scale = (1, 1, 1)
    return col, root


def rebuild(key, fn):
    col, root = clear_component(key)
    before = set(sc.objects)
    fn()
    objs = [o for o in sc.objects if o not in before]
    for o in objs:
        for c in list(o.users_collection):
            c.objects.unlink(o)
        col.objects.link(o)
        mw = o.matrix_world.copy()
        o.parent = root
        o.matrix_world = mw
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    pts = []
    for o in objs:
        if o.type == 'MESH':
            ev = o.evaluated_get(deps)
            me = ev.to_mesh()
            pts.extend(o.matrix_world @ v.co for v in me.vertices)
            ev.to_mesh_clear()
    lo = Vector([min(v[i] for v in pts) for i in range(3)])
    hi = Vector([max(v[i] for v in pts) for i in range(3)])
    ctr = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
    for o in objs:
        o.matrix_parent_inverse.identity()
        o.location -= ctr
    col.instance_offset = (0, 0, 0)
    print('REVISED_COMPONENT', key, len(objs), flush=True)

# Eight-storey shell and repeated facade parts.
def shell():
    cube('八层混凝土主体', (0, 0, 12.69), (35.6, 23.6, 25.38), 'lightgray', bev=.08)
    for i in range(1, 8):
        z = i * 3.2 - .08
        cube('正面水平层线', (0, -11.86, z), (35.9, .20, .18), 'cloud', bev=.035)
        cube('右侧水平层线', (17.86, 0, z), (.20, 23.8, .18), 'cloud', bev=.035)
rebuild('building_shell', shell)

def column():
    cube('八层外挑主柱', (0, 0, 12.69), (1.8, .90, 25.38), 'lightgray', bev=.075)
    for z in [3.15, 9.55, 18.95]:
        cube('柱身施工缝', (0, -.465, z), (1.65, .035, .075), 'gray', bev=.012)
rebuild('facade_column', column)

def damaged_column():
    cube('八层破损主柱', (0, 0, 12.69), (1.8, .90, 25.38), 'lightgray', bev=.075)
    for z, w, h in [(4.2, 1.35, 2.1), (13.8, 1.25, 2.8), (22.3, 1.40, 1.9)]:
        wall_patch('柱身混凝土剥落', (0, -.468, z), w, h, 'slate')
        for dx in [-.38, 0, .38]:
            rod('外露竖向钢筋', (dx, -.51, z - h * .38), (dx + .05, -.51, z + h * .42), .032, 'wood_dark')
        for dz in [-.45, .30]:
            rod('外露横向钢筋', (-w * .42, -.535, z + dz), (w * .42, -.535, z + dz + .04), .025, 'wood_dark')
        tube('柱身斜裂', [(-.7, -.48, z + h * .55), (-.35, -.49, z + h * .32), (-.45, -.49, z + h * .1)], .022, 'slate', 'SEA_Matte')
rebuild('damaged_column', damaged_column)

def window():
    cube('窗外混凝土框', (0, 0, .78), (2.15, .18, 1.70), 'cloud', bev=.045)
    cube('窗户深蓝玻璃', (0, -.115, .80), (1.82, .055, 1.38), 'deepblue', 'SEA_Gloss', .02)
    cube('窗横梃', (0, -.155, .80), (1.85, .055, .075), 'seafoam', 'SEA_Metal', .01)
    cube('窗竖梃', (0, -.155, .80), (.075, .055, 1.40), 'seafoam', 'SEA_Metal', .01)
    cube('窗台', (0, -.19, .06), (2.28, .40, .14), 'plaster', bev=.025)
    wall_patch('窗台墙皮缺损', (.65, -.105, .04), .65, .20, 'gray')
rebuild('facade_window', window)

def broken_window():
    cube('破窗混凝土框', (0, 0, .78), (2.15, .18, 1.70), 'stone', bev=.045)
    cube('破窗深色内洞', (0, -.105, .80), (1.84, .06, 1.40), 'rubber', bev=.015)
    mesh_obj('残留缺角玻璃', [(-.89, -.15, .12), (.86, -.15, .12), (.86, -.15, .70), (.25, -.15, .93), (-.15, -.15, 1.47), (-.89, -.15, 1.47)], [(0, 1, 2, 3, 4, 5)], 'deepblue', 'SEA_Gloss')
    cube('破窗横梃', (0, -.17, .80), (1.85, .055, .075), 'gray', 'SEA_Metal', .01)
    cube('封窗旧木板', (0, -.22, .83), (2.0, .10, .26), 'wood_mid', bev=.025, rot=(0, -.20, 0))
    tube('窗框裂纹', [(-1.0, -.12, 1.55), (-.75, -.13, 1.30), (-.86, -.13, 1.10)], .018, 'slate', 'SEA_Matte')
rebuild('broken_window', broken_window)

def balcony():
    cube('阳台厚底板', (0, 0, .11), (5.0, 1.25, .22), 'cloud', bev=.045)
    cube('阳台前栏板', (0, -.55, .52), (4.85, .20, .72), 'lightgray', bev=.045)
    cube('阳台左栏板', (-2.35, 0, .52), (.20, 1.10, .72), 'lightgray', bev=.04)
    cube('阳台右栏板', (2.35, 0, .52), (.20, 1.10, .72), 'lightgray', bev=.04)
    wall_patch('阳台栏板剥落', (-.85, -.66, .52), 1.35, .48, 'stone')
    tube('阳台边缘裂缝', [(1.65, -.665, .85), (1.45, -.67, .63), (1.62, -.67, .40)], .018, 'slate', 'SEA_Matte')
rebuild('balcony', balcony)

# Weathered rooms and roof details.
def upper_room():
    cube('上层小间墙身', (0, 0, 1.20), (3.5, 3, 2.4), 'plaster', bev=.065)
    cube('上层小间平屋顶', (0, 0, 2.43), (3.75, 3.25, .20), 'cloud', bev=.045)
    cube('小间正面门', (-.85, -1.515, .95), (.85, .08, 1.9), 'teal', bev=.03)
    cube('小间窗框', (.75, -1.53, 1.35), (1.25, .10, 1.0), 'cloud', bev=.03)
    cube('小间蓝窗', (.75, -1.59, 1.35), (1.05, .035, .80), 'sky', 'SEA_Gloss', .015)
    wall_patch('小间大片墙皮剥落', (1.15, -1.512, .48), .85, .75, 'gray')
    wall_patch('小间侧墙剥落', (1.758, .55, 1.25), 1.05, 1.25, 'stone', 'side')
    tube('小间屋顶裂缝', [(-1.55, -1.53, 2.30), (-1.25, -1.54, 2.02), (-1.35, -1.54, 1.72), (-1.1, -1.54, 1.5)], .020, 'slate', 'SEA_Matte')
    for x in [-1.3, 1.25]:
        cube('小间屋顶女儿墙', (x, 1.30, 2.67), (.65, .22, .32), 'lightgray', bev=.035)
rebuild('upper_room', upper_room)

def tool_shed():
    cube('工具房墙身', (0, 0, 1.52), (4.5, 3.5, 3.04), 'sage_gray', bev=.055)
    cube('工具房正面木板', (0, -1.77, 1.45), (4.25, .10, 2.85), 'seafoam', bev=.02)
    cube('工具房木门框', (-.55, -1.85, 1.05), (1.18, .12, 2.12), 'darkwood', bev=.025)
    cube('工具房蓝木门', (-.55, -1.925, 1.02), (.94, .08, 1.95), 'teal', bev=.025)
    cyl('门把手', (-.22, -1.99, 1.03), .05, .07, 'honey', 'SEA_Metal', 12, rot=(math.pi / 2, 0, 0), bev=.005)
    cube('工具房侧窗框', (2.27, .35, 1.65), (.10, 1.35, 1.10), 'cloud', bev=.025)
    cube('工具房侧窗', (2.33, .35, 1.65), (.035, 1.15, .90), 'deepblue', 'SEA_Gloss', .015)
    wall_patch('工具房门旁墙皮脱落', (1.15, -1.832, 1.05), 1.55, 1.85, 'gray')
    for z in [.48, .82, 1.16, 1.50]:
        cube('剥落处外露木板', (1.18, -1.85, z), (1.12, .045, .20), 'wood_mid', bev=.012)
    wall_patch('工具房侧墙破损', (2.263, -1.0, .72), .85, 1.10, 'stone', 'side')
    tube('工具房正面裂口', [(-1.9, -1.84, 2.85), (-1.55, -1.85, 2.55), (-1.65, -1.85, 2.20), (-1.35, -1.85, 1.92)], .025, 'slate', 'SEA_Matte')
    cube('工具房生锈门牌', (.95, -1.88, 2.35), (.62, .055, .28), 'wood_dark', 'SEA_Metal', .02, rot=(0, .05, 0))
rebuild('tool_shed', tool_shed)

def shed_roof():
    angle = math.atan2(.9, 2.25)
    for side in [-1, 1]:
        cube('红褐波纹屋顶', (side * 1.12, 0, .48), (2.48, 3.95, .13), 'red_dark', 'SEA_Metal', .03, rot=(0, side * angle, 0))
        for y in [-1.65, -1.1, -.55, 0, .55, 1.1, 1.65]:
            rod('屋顶瓦楞', (side * .03, y, .96), (side * 2.30, y, .04), .032, 'coral', 'SEA_Metal', 10)
        for i in range(5):
            x = side * (.35 + i * .36)
            z = .96 - abs(x) * .4 + .075
            cube('屋顶长条锈蚀', (x, -.35 + (i % 3) * .45, z), (.16 + (i % 2) * .12, 1.10, .025), 'wood_dark' if i % 2 else 'gray', 'SEA_Metal', .008, rot=(0, side * angle, 0))
    rod('屋脊厚压条', (0, -2.02, .96), (0, 2.02, .96), .075, 'red', 'SEA_Metal', 14)
rebuild('shed_roof', shed_roof)

def lean_to():
    cube('小棚屋墙身', (0, 0, .95), (3, 2.5, 1.9), 'wood_mid', bev=.045)
    cube('小棚屋门', (0, -1.28, .83), (.85, .09, 1.65), 'darkwood', bev=.025)
    cube('蓝色斜棚顶', (0, 0, 2.10), (3.35, 2.85, .16), 'teal', 'SEA_Metal', .035, rot=(.16, 0, 0))
    for x in [-1.2, -.6, 0, .6, 1.2]:
        rod('棚顶瓦楞', (x, -1.40, 1.90), (x, 1.40, 2.34), .032, 'aqua', 'SEA_Metal', 10)
    for x in [-1.15, .95]:
        cube('棚屋破损外板', (x, -1.275, .62), (.38, .07, 1.05), 'wood_dark', bev=.015, rot=(0, .04 if x < 0 else -.05, 0))
    for x in [-.8, .55]:
        cube('棚顶铁锈痕', (x, .2, 2.26), (.24, 1.50, .025), 'wood_dark', 'SEA_Metal', .008, rot=(.16, 0, 0))
rebuild('small_lean_to', lean_to)

# Close greenhouse gables and add a worn framed door; no plants inside.
def greenhouse_panels():
    angle = math.atan2(1.8, 2.5)
    for side in [-1, 1]:
        cube('温室斜顶透明板', (side * 1.25, 0, 2.90), (3.10, 8.90, .035), 'seafoam', 'SEA_Gloss', .006, rot=(0, side * angle, 0))
        cube('温室侧墙透明板', (side * 2.46, 0, 1.0), (.035, 8.85, 1.90), 'palegreen', 'SEA_Gloss', .006)
    cube('温室后墙透明板', (0, 4.43, 1.0), (4.85, .035, 1.90), 'seafoam', 'SEA_Gloss', .006)
    for x in [-1.48, 1.48]:
        cube('温室入口旁透明板', (x, -4.43, 1.0), (1.82, .035, 1.90), 'palegreen', 'SEA_Gloss', .006)
        cube('温室入口蓝色护板', (x, -4.46, .43), (1.82, .07, .82), 'teal', 'SEA_Metal', .015)
    for y in [-4.44, 4.44]:
        mesh_obj('温室三角形山墙', [(-2.44, y, 2.0), (2.44, y, 2.0), (0, y, 3.76)], [(0, 1, 2)], 'seafoam', 'SEA_Gloss')
    cube('温室旧木门', (0, -4.47, .96), (.94, .10, 1.88), 'wood_mid', bev=.025)
    cube('温室门小玻璃', (0, -4.535, 1.30), (.64, .035, .72), 'deepblue', 'SEA_Gloss', .015)
    wall_patch('温室门剥漆', (.22, -4.53, .45), .38, .55, 'gray')
rebuild('greenhouse_panels', greenhouse_panels)

# Large roof pavers, each with real thickness and selected physical cracks/chips.
def roof_tiles():
    for ix in range(12):
        for iy in range(8):
            cx = -16.5 + ix * 3.0
            cy = -10.5 + iy * 3.0
            w = 2.92
            h = 2.92
            chip = (ix * 7 + iy * 11) % 9 == 0
            if chip:
                coords = [(cx - w/2, cy - h/2), (cx + w/2 - .55, cy - h/2), (cx + w/2, cy - h/2 + .48), (cx + w/2, cy + h/2), (cx - w/2, cy + h/2)]
            else:
                coords = [(cx - w/2, cy - h/2), (cx + w/2, cy - h/2), (cx + w/2, cy + h/2), (cx - w/2, cy + h/2)]
            cell = ['cloud', 'stone', 'lightgray', 'plaster', 'stone'][(ix * 3 + iy * 5) % 5]
            z = .08 + ((ix + iy) % 4) * .006
            prism('三米旧地砖', coords, 0, z, cell, .025)
            if (ix + iy * 2) % 4 == 0:
                pts = [(cx - 1.10, cy - .85, z + .018), (cx - .45, cy - .25, z + .018), (cx - .62, cy + .28, z + .018), (cx + .15, cy + .95, z + .018)]
                tube('地砖宽裂缝', pts, .018, 'slate', 'SEA_Matte')
                tube('地砖裂缝支叉', [(cx - .46, cy - .24, z + .02), (cx + .12, cy - .36, z + .02), (cx + .55, cy - .12, z + .02)], .012, 'gray', 'SEA_Matte')
            if (ix * 5 + iy) % 7 == 0:
                wall = [(cx - .95, cy - .65, z + .012), (cx - .25, cy - .88, z + .012), (cx + .70, cy - .35, z + .012), (cx + .48, cy + .42, z + .012), (cx - .45, cy + .62, z + .012)]
                mesh_obj('地砖大片磨损失色', wall, [(0, 1, 2, 3, 4)], 'gray' if ix % 2 else 'sage_gray')
    for i in range(14):
        x = random.uniform(-17, 17)
        y = random.choice([-11.45, 11.45]) + random.uniform(-.15, .15)
        cube('地砖破损碎块', (x, y, .09), (random.uniform(.18, .45), random.uniform(.12, .35), .12), 'stone', bev=.025, rot=(0, 0, random.uniform(-.5, .5)))
rebuild('roof_tiles', roof_tiles)

# Unique large-scale facade damage: visible between windows and columns.
def facade_weathering():
    for x, z, w, h in [(-15.1, 2.1, 2.0, 2.8), (-7.0, 5.2, 2.2, 1.7), (1.1, 9.0, 2.6, 3.5), (14.8, 13.1, 2.0, 3.0), (-14.5, 18.4, 2.8, 2.0), (-6.5, 23.2, 2.1, 3.2), (7.2, 21.1, 2.0, 2.5)]:
        wall_patch('正面大片剥落', (x, -11.825, z), w, h, 'stone' if int(z) % 2 else 'gray')
        tube('正面主裂缝', [(x - w*.35, -11.85, z + h*.65), (x - w*.1, -11.85, z + h*.25), (x - w*.22, -11.85, z - h*.1), (x + w*.18, -11.85, z - h*.45)], .022, 'slate', 'SEA_Matte')
    for y, z, w, h in [(-9.5, 3.4, 2.0, 2.8), (-2.8, 8.6, 2.5, 3.4), (5.4, 15.0, 2.3, 2.6), (9.6, 22.0, 2.1, 3.3)]:
        wall_patch('右侧大片剥落', (17.825, y, z), w, h, 'stone', 'side')
        tube('右侧裂缝', [(17.85, y - w*.35, z + h*.55), (17.85, y, z + h*.18), (17.85, y - w*.2, z - h*.35)], .022, 'slate', 'SEA_Matte')
    for x in [-14, -6, 3, 11]:
        wall_patch('顶部雨水流痕', (x, -11.83, 24.5), .65, 1.65, 'sage_gray')
    wall_patch('露筋混凝土破损区', (1.0, -11.84, 16.2), 2.4, 1.65, 'slate')
    for x in [.25, .75, 1.25, 1.75]:
        rod('墙面外露钢筋', (x, -11.89, 15.65), (x + .06, -11.89, 16.78), .03, 'wood_dark')
rebuild('facade_weathering', facade_weathering)

# Existing component collections lookup after additions.
components = {x['key']: bpy.data.collections[x['asset_id']] for x in components_plan}
old_layout = json.loads((D / 'component_instances.json').read_text(encoding='utf-8'))['instances']
base = []
for item in old_layout:
    key = item['key']
    if key in removed or key in {'floor_slab', 'facade_window', 'balcony'}:
        continue
    item = {'key': key, 'position': list(item['position']), 'rotation_euler_xyz': list(item['rotation_euler_xyz']), 'scale': list(item['scale'])}
    if item['position'][2] >= 9.38:
        item['position'][2] += 16.0
    if key == 'facade_column' and abs(item['position'][0]) in {8.3} and item['position'][1] < -12:
        item['key'] = 'damaged_column'
    base.append(item)
for i in range(8):
    base.append({'key': 'floor_slab', 'position': [0, 0, i * 3.2], 'rotation_euler_xyz': [0, 0, 0], 'scale': [1, 1, 1]})
    for x in [-12.2, -4.1, 4.1, 12.2]:
        key = 'broken_window' if (i, x) in [(1, 4.1), (4, -12.2), (6, 12.2)] else 'facade_window'
        base.append({'key': key, 'position': [x, -11.91, .72 + i * 3.2], 'rotation_euler_xyz': [0, 0, 0], 'scale': [1, 1, 1]})
        base.append({'key': 'balcony', 'position': [x, -12.35, .18 + i * 3.2], 'rotation_euler_xyz': [0, 0, 0], 'scale': [1, 1, 1]})
    for side in [-1, 1]:
        for y in [-7.0, 0, 7.0]:
            key = 'broken_window' if (i, side, y) == (5, 1, 0) else 'facade_window'
            base.append({'key': key, 'position': [side * 17.88, y, .75 + i * 3.2], 'rotation_euler_xyz': [0, 0, side * math.pi / 2], 'scale': [1, 1, 1]})
base.append({'key': 'roof_tiles', 'position': [0, 0, 25.60], 'rotation_euler_xyz': [0, 0, 0], 'scale': [1, 1, 1]})
base.append({'key': 'facade_weathering', 'position': [0, 0, 0], 'rotation_euler_xyz': [0, 0, 0], 'scale': [1, 1, 1]})

groups = {n: bpy.data.collections[n] for n in ['01_建筑结构', '02_固定设施', '03_花草植被']}
layout = []
counts = {}
for item in base:
    key = item['key']
    counts[key] = counts.get(key, 0) + 1
    name = key + '_' + str(counts[key]).zfill(2)
    o = bpy.data.objects.new(name, None)
    o.instance_type = 'COLLECTION'
    o.instance_collection = components[key]
    o.location = item['position']
    o.rotation_euler = item['rotation_euler_xyz']
    o.scale = item['scale']
    category = specs[key]['category']
    group = groups['03_花草植被'] if category == 'flora' else groups['01_建筑结构'] if category == 'structure' else groups['02_固定设施']
    group.objects.link(o)
    layout.append({'name': name, 'key': key, 'asset_id': specs[key]['asset_id'], 'position': item['position'], 'rotation_euler_xyz': item['rotation_euler_xyz'], 'scale': item['scale'], 'category': category})

# Refresh catalog with actual local bounds and geometry fingerprints.
bpy.context.view_layer.update()
deps = bpy.context.evaluated_depsgraph_get()
cat = {'schema': 'sea.scene.component_catalog', 'components': []}
for key, col in components.items():
    root = next(o for o in col.objects if o.type == 'EMPTY')
    pts = []
    for o in col.objects:
        if o.type == 'MESH':
            ev = o.evaluated_get(deps)
            me = ev.to_mesh()
            pts.extend(o.matrix_world @ v.co for v in me.vertices)
            ev.to_mesh_clear()
    lo = Vector([min(v[i] for v in pts) for i in range(3)])
    hi = Vector([max(v[i] for v in pts) for i in range(3)])
    geom = ';'.join(o.name + ':' + ','.join(str(round(c, 4)) for v in o.data.vertices for c in v.co) for o in col.objects if o.type == 'MESH')
    entry = dict(specs[key])
    entry.update({'collection': col.name, 'root': root.name, 'bounds_size': list(hi-lo), 'component_source': 'art_source/scenes/ocean_rooftop_farm/v001/component_packages/' + key + '/' + key + '.blend', 'geometry_fingerprint': hashlib.sha256(geom.encode()).hexdigest(), 'instances': sum(x['key'] == key for x in layout), 'materials': ['SEA_Matte', 'SEA_Metal', 'SEA_Gloss', 'SEA_Emission'], 'collision_owner': 'future above-water facility assembly; source visual only'})
    cat['components'].append(entry)
(D / 'component_catalog.json').write_text(json.dumps(cat, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
(D / 'component_instances.json').write_text(json.dumps({'schema': 'sea.scene.instances', 'up_axis': 'Z', 'front_axis': '-Y', 'godot_mapping': '(x,y,z)->(x,z,-y)', 'revision': 'r2', 'instances': layout}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

# Full eight-storey composition, plus a dedicated roof camera for detail checks.
cam = sc.camera
cam.location = (48, -62, 59)
cam.rotation_euler = (Vector((0, 0, 13.0)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
cam.data.ortho_scale = 67
sc.render.resolution_x = 1440
sc.render.resolution_y = 1100
sc.render.filepath = str(W / 'beauty_r2.png')
for o in sc.objects:
    if o.type == 'LIGHT':
        o.data.energy *= 1.18
bg = next(n for n in sc.world.node_tree.nodes if n.type == 'BACKGROUND')
bg.inputs[1].default_value = .75
for im in bpy.data.images:
    if im.source == 'FILE' and 'sea_cabin_timber' in im.name:
        im.filepath = bpy.path.relpath(str(pal), start=str(D))
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(D / 'ocean_rooftop_farm.blend'), compress=True)
bpy.ops.wm.save_as_mainfile(filepath=str(W / 'before_r2_revision.blend'), copy=True)
bpy.ops.render.render(write_still=True, scene=sc.name)
print(json.dumps({'revision': 'r2', 'floors': 8, 'components': len(components), 'instances': len(layout), 'removed': sorted(removed), 'render': sc.render.filepath}, ensure_ascii=False), flush=True)
