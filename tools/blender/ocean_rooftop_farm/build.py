import bpy, math, json, hashlib, random
from pathlib import Path
from mathutils import Vector

R = Path(r'D:/projects/sea')
D = R / 'art_source/scenes/ocean_rooftop_farm/v001'
W = R.parent / 'sea-work/ocean_rooftop_farm/v001'
W.mkdir(parents=True, exist_ok=True)
random.seed(20261102)
scene_name = '海上屋顶农场_制作与装配_v001'
if scene_name in bpy.data.scenes:
    raise RuntimeError('Task scene already exists; refine the existing source instead of rebuilding over it.')
sc = bpy.data.scenes.new(scene_name)
bpy.context.window.scene = sc
sc.unit_settings.system = 'METRIC'
sc.unit_settings.scale_length = 1.0
plan = json.loads((D / 'component_plan.json').read_text(encoding='utf-8'))
specs = {x['key']: x for x in plan['components']}
pal = R / 'art_source/shared/palettes/sea_cabin_timber_8x8_512.png'
colors = {x['name']: x for x in json.loads(pal.with_suffix('.json').read_text(encoding='utf-8'))['cells']}
image = bpy.data.images.load(str(pal), check_existing=True)
image.filepath = str(pal)
roles = {}
for name, metal, rough in [('SEA_Matte', .02, .72), ('SEA_Metal', .68, .34), ('SEA_Gloss', .10, .18), ('SEA_Emission', 0, .38)]:
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    n = m.node_tree.nodes
    l = m.node_tree.links
    n.clear()
    out = n.new('ShaderNodeOutputMaterial')
    bs = n.new('ShaderNodeBsdfPrincipled')
    bs.inputs['Metallic'].default_value = metal
    bs.inputs['Roughness'].default_value = rough
    uv = n.new('ShaderNodeUVMap')
    uv.uv_map = 'PaletteUV'
    tx = n.new('ShaderNodeTexImage')
    tx.image = image
    tx.interpolation = 'Closest'
    l.new(uv.outputs['UV'], tx.inputs['Vector'])
    l.new(tx.outputs['Color'], bs.inputs['Base Color'])
    l.new(bs.outputs[0], out.inputs['Surface'])
    if name == 'SEA_Gloss':
        bs.inputs['Alpha'].default_value = .72
        bs.inputs['Transmission Weight'].default_value = .06
        try:
            m.surface_render_method = 'DITHERED'
        except Exception:
            pass
    if name == 'SEA_Emission':
        l.new(tx.outputs['Color'], bs.inputs['Emission Color'])
        bs.inputs['Emission Strength'].default_value = .85
    roles[name] = m


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


def finish(o, cell='cream', role='SEA_Matte', bev=.035, smooth=False):
    if o.data.materials:
        o.data.materials.clear()
    o.data.materials.append(roles[role])
    place_uv(o, cell)
    for p in o.data.polygons:
        p.material_index = 0
        p.use_smooth = smooth
    if bev:
        m = o.modifiers.new('实体柔边', 'BEVEL')
        m.width = bev
        m.segments = 3
    return o


def cube(name, loc, size, cell='cream', role='SEA_Matte', bev=.035, rot=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.object
    o.name = name
    o.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if rot:
        o.rotation_euler = rot
    return finish(o, cell, role, bev)


def cyl(name, loc, r, depth, cell='gray', role='SEA_Metal', verts=24, r2=None, rot=None, bev=.025):
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=loc)
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=r2, depth=depth, location=loc)
    o = bpy.context.object
    o.name = name
    if rot:
        o.rotation_euler = rot
    return finish(o, cell, role, bev, smooth=True)


def sphere(name, loc, scale, cell='leaf', role='SEA_Matte'):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, location=loc)
    o = bpy.context.object
    o.name = name
    o.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(o, cell, role, 0, smooth=True)


def mesh_obj(name, verts, faces, cell='cream', role='SEA_Matte', bev=.02):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    o = bpy.data.objects.new(name, me)
    sc.collection.objects.link(o)
    return finish(o, cell, role, bev)


def tube(name, pts, radius, cell='steel', role='SEA_Metal', resolution=2):
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
    return finish(o, cell, role, 0, smooth=True)


def rod(name, a, b, radius, cell='steel', role='SEA_Metal', verts=12):
    a = Vector(a)
    b = Vector(b)
    o = cyl(name, (a + b) / 2, radius, (b - a).length, cell, role, verts, bev=.008)
    o.rotation_euler = (b - a).to_track_quat('Z', 'Y').to_euler()
    return o


components = {}

def part(key, fn):
    col = bpy.data.collections.new(specs[key]['asset_id'])
    sc.collection.children.link(col)
    before = set(sc.objects)
    fn()
    objs = [o for o in sc.objects if o not in before]
    if not objs:
        raise RuntimeError('Empty component ' + key)
    root = bpy.data.objects.new(key + '_组件根', None)
    col.objects.link(root)
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
    ctr = Vector(((lo.x + max(v.x for v in pts)) / 2, (lo.y + max(v.y for v in pts)) / 2, lo.z))
    root.location = (0, 0, 0)
    for o in objs:
        o.matrix_parent_inverse.identity()
        o.location -= ctr
    col.instance_offset = (0, 0, 0)
    sc.collection.children.unlink(col)
    components[key] = col
    print('COMPONENT', key, len(objs), flush=True)


groups = {}
for name in ['01_建筑结构', '02_固定设施', '03_花草植被', '90_展示环境_不导出']:
    c = bpy.data.collections.new(name)
    sc.collection.children.link(c)
    groups[name] = c

layout = []

def inst(key, pos, rot=(0, 0, 0), scale=(1, 1, 1), suffix=None):
    idx = sum(x['key'] == key for x in layout) + 1
    name = key + '_' + (suffix or str(idx).zfill(2))
    o = bpy.data.objects.new(name, None)
    o.instance_type = 'COLLECTION'
    o.instance_collection = components[key]
    o.location = pos
    o.rotation_euler = rot
    o.scale = scale
    category = specs[key]['category']
    group = groups['03_花草植被'] if category == 'flora' else groups['01_建筑结构'] if category == 'structure' else groups['02_固定设施']
    group.objects.link(o)
    layout.append({'name': name, 'key': key, 'asset_id': specs[key]['asset_id'], 'position': list(pos), 'rotation_euler_xyz': list(rot), 'scale': list(scale), 'category': category})
    return o

# 1. Main building and facade.
def building_shell():
    cube('混凝土主体', (0, 0, 4.69), (35.6, 23.6, 9.38), 'lightgray', bev=.10)
    for z in [3.12, 6.32, 9.30]:
        cube('正面水平层线', (0, -11.86, z), (35.9, .20, .20), 'cloud', bev=.045)
        cube('右侧水平层线', (17.86, 0, z), (.20, 23.8, .20), 'cloud', bev=.045)
    for i in range(22):
        x = random.uniform(-16.8, 16.8)
        z = random.uniform(.5, 8.9)
        cube('墙面浅色修补斑', (x, -11.815, z), (random.uniform(.25, .85), .035, random.uniform(.12, .38)), 'stone' if i % 3 else 'sage_gray', bev=.025)
    for i in range(8):
        cube('右侧修补斑', (17.815, random.uniform(-10, 10), random.uniform(.6, 8.7)), (.035, random.uniform(.3, .8), random.uniform(.15, .4)), 'stone', bev=.02)
part('building_shell', building_shell)
part('floor_slab', lambda: cube('标准厚楼板', (0, 0, .11), (36, 24, .22), 'cloud', bev=.055))
part('facade_column', lambda: [cube('外挑主柱', (0, 0, 4.69), (1.8, .90, 9.38), 'lightgray', bev=.09), cube('柱脚加深色', (0, -.47, .55), (1.55, .055, 1.1), 'gray', bev=.025)])
part('facade_window', lambda: [cube('窗外混凝土框', (0, 0, .78), (2.15, .18, 1.70), 'cloud', bev=.055), cube('窗户深蓝玻璃', (0, -.115, .80), (1.82, .055, 1.38), 'deepblue', 'SEA_Gloss', .025), cube('窗横梃', (0, -.155, .80), (1.85, .055, .075), 'seafoam', 'SEA_Metal', .012), cube('窗竖梃', (0, -.155, .80), (.075, .055, 1.40), 'seafoam', 'SEA_Metal', .012), cube('窗台', (0, -.19, .06), (2.28, .40, .14), 'plaster', bev=.03)])
part('balcony', lambda: [cube('阳台厚底板', (0, 0, .11), (5.0, 1.25, .22), 'cloud', bev=.05), cube('阳台前栏板', (0, -.55, .52), (4.85, .20, .72), 'lightgray', bev=.055), cube('阳台左栏板', (-2.35, 0, .52), (.20, 1.10, .72), 'lightgray', bev=.045), cube('阳台右栏板', (2.35, 0, .52), (.20, 1.10, .72), 'lightgray', bev=.045)])
part('roof_deck', lambda: [cube('屋顶混凝土平台', (0, 0, .11), (36, 24, .22), 'stone', bev=.065), cube('屋顶前压顶', (0, -11.92, .20), (36.1, .26, .16), 'cloud', bev=.04)])
part('parapet', lambda: cube('四米女儿墙段', (0, 0, .275), (4.0, .30, .55), 'lightgray', bev=.055))
part('railing_segment', lambda: [rod('栏杆顶管', (-2, 0, 1.08), (2, 0, 1.08), .045, 'silver'), rod('栏杆中管', (-2, 0, .55), (2, 0, .55), .032, 'steel')] + [rod('栏杆立柱', (x, 0, 0), (x, 0, 1.1), .048, 'silver') for x in [-1.92, 0, 1.92]])
part('raised_platform', lambda: [cube('抬高平台厚板', (0, 0, 3.29), (8, 7, .22), 'cloud', bev=.065)] + [cube('平台承重柱', (x, y, 1.59), (.52, .52, 3.18), 'lightgray', bev=.055) for x, y in [(-3.5, -3), (3.5, -3), (-3.5, 3), (3.5, 3)]] + [cube('平台侧墙', (-3.72, 0, 1.55), (.28, 6.2, 3.1), 'stone', bev=.05)])

def upper_room():
    cube('上层小间墙身', (0, 0, 1.20), (3.5, 3, 2.4), 'plaster', bev=.075)
    cube('上层小间平屋顶', (0, 0, 2.43), (3.75, 3.25, .20), 'cloud', bev=.055)
    cube('小间正面门', (-.85, -1.515, .95), (.85, .08, 1.9), 'teal', bev=.035)
    cube('小间窗框', (.75, -1.53, 1.35), (1.25, .10, 1.0), 'cloud', bev=.035)
    cube('小间蓝窗', (.75, -1.59, 1.35), (1.05, .035, .80), 'sky', 'SEA_Gloss', .02)
part('upper_room', upper_room)
part('metal_ladder', lambda: [rod('爬梯左轨', (-.42, 0, 0), (-.42, 0, 3.65), .045, 'steel'), rod('爬梯右轨', (.42, 0, 0), (.42, 0, 3.65), .045, 'steel')] + [rod('爬梯横档', (-.42, -.02, .25 + i * .38), (.42, -.02, .25 + i * .38), .035, 'silver') for i in range(9)])
part('clothesline', lambda: [rod('晾衣左杆', (-1.5, 0, 0), (-1.5, 0, 2.2), .04, 'steel'), rod('晾衣右杆', (1.5, 0, 0), (1.5, 0, 2.2), .04, 'steel'), tube('晾衣绳', [(-1.5, 0, 2.1), (0, 0, 1.98), (1.5, 0, 2.1)], .018, 'darkwood'), cube('橙红衣片', (-.55, -.02, 1.5), (.72, .07, .90), 'red', bev=.04, rot=(0, .04, -.04)), cube('浅色衣片', (.5, -.02, 1.68), (.55, .065, .62), 'cream', bev=.035)])

def tool_shed():
    cube('工具房墙身', (0, 0, 1.52), (4.5, 3.5, 3.04), 'sage_gray', bev=.065)
    cube('工具房正面木板', (0, -1.77, 1.45), (4.25, .10, 2.85), 'seafoam', bev=.025)
    cube('工具房木门框', (-.55, -1.85, 1.05), (1.18, .12, 2.12), 'darkwood', bev=.03)
    cube('工具房蓝木门', (-.55, -1.925, 1.02), (.94, .08, 1.95), 'teal', bev=.03)
    cyl('门把手', (-.22, -1.99, 1.03), .055, .07, 'honey', 'SEA_Metal', 12, rot=(math.pi / 2, 0, 0), bev=.005)
    cube('工具房侧窗框', (2.27, .35, 1.65), (.10, 1.35, 1.10), 'cloud', bev=.03)
    cube('工具房侧窗', (2.33, .35, 1.65), (.035, 1.15, .90), 'deepblue', 'SEA_Gloss', .02)
part('tool_shed', tool_shed)

def shed_roof():
    angle = math.atan2(.9, 2.25)
    for side in [-1, 1]:
        cube('红褐波纹屋顶 panel', (side * 1.12, 0, .48), (2.48, 3.95, .13), 'red_dark', 'SEA_Metal', .035, rot=(0, side * angle, 0))
        for y in [-1.65, -1.1, -.55, 0, .55, 1.1, 1.65]:
            rod('圆润屋顶瓦楞', (side * .03, y, .96), (side * 2.30, y, .04), .035, 'coral', 'SEA_Metal', 10)
    rod('屋脊厚压条', (0, -2.02, .96), (0, 2.02, .96), .085, 'red', 'SEA_Metal', 16)
part('shed_roof', shed_roof)
part('small_lean_to', lambda: [cube('小棚屋墙身', (0, 0, .95), (3, 2.5, 1.9), 'wood_mid', bev=.055), cube('小棚屋门', (0, -1.28, .83), (.85, .09, 1.65), 'darkwood', bev=.03), cube('蓝色斜棚顶', (0, 0, 2.10), (3.35, 2.85, .16), 'teal', 'SEA_Metal', .04, rot=(.16, 0, 0))] + [rod('棚顶瓦楞', (x, -1.40, 1.90), (x, 1.40, 2.34), .035, 'aqua', 'SEA_Metal', 10) for x in [-1.2, -.6, 0, .6, 1.2]])

def greenhouse_frame():
    for x in [-2.45, 2.45]:
        for y in [-4.4, -2.2, 0, 2.2, 4.4]:
            rod('温室侧立柱', (x, y, 0), (x, y, 2.0), .045, 'silver')
            rod('温室斜顶肋', (x, y, 2.0), (0, y, 3.8), .04, 'silver')
    rod('温室屋脊', (0, -4.5, 3.8), (0, 4.5, 3.8), .055, 'seafoam')
    for x in [-2.45, 2.45]:
        rod('温室檐梁', (x, -4.5, 2.0), (x, 4.5, 2.0), .05, 'seafoam')
        rod('温室底梁', (x, -4.5, .08), (x, 4.5, .08), .045, 'seafoam')
    for x in [-.52, .52]:
        rod('入口门框', (x, -4.48, 0), (x, -4.48, 2.05), .055, 'cloud')
    rod('入口门楣', (-.55, -4.48, 2.05), (.55, -4.48, 2.05), .055, 'cloud')
    cube('温室门槛', (0, -4.48, .07), (1.15, .30, .14), 'wood_light', bev=.025)
part('greenhouse_frame', greenhouse_frame)

def greenhouse_panels():
    angle = math.atan2(1.8, 2.5)
    for side in [-1, 1]:
        cube('温室斜顶透明板', (side * 1.25, 0, 2.90), (3.10, 8.90, .035), 'seafoam', 'SEA_Gloss', .008, rot=(0, side * angle, 0))
        cube('温室侧墙透明板', (side * 2.46, 0, 1.0), (.035, 8.85, 1.90), 'palegreen', 'SEA_Gloss', .008)
    cube('温室后墙透明板', (0, 4.43, 1.0), (4.85, .035, 1.90), 'seafoam', 'SEA_Gloss', .008)
    for x in [-1.48, 1.48]:
        cube('温室入口旁透明板', (x, -4.43, 1.0), (1.82, .035, 1.90), 'palegreen', 'SEA_Gloss', .008)
part('greenhouse_panels', greenhouse_panels)
part('water_tank', lambda: [cyl('圆肚储水罐', (0, 0, 2.0), 1.75, 3.65, 'sage_gray', 'SEA_Metal', 32, bev=.11), cyl('水罐底环', (0, 0, .22), 1.82, .22, 'steel', 'SEA_Metal', 32, bev=.035), cyl('水罐顶环', (0, 0, 3.74), 1.82, .20, 'cloud', 'SEA_Metal', 32, bev=.035), cyl('锥形水塔盖', (0, 0, 4.12), 1.92, .76, 'wood_dark', 'SEA_Metal', 32, r2=.15, bev=.04)] + [cube('水罐锈蚀片', (math.sin(a) * 1.72, -math.cos(a) * 1.72, 1.0 + i * .45), (.22, .045, .45), 'wood_mid', bev=.02, rot=(0, 0, a)) for i, a in enumerate([-.8, -.25, .35, .9])])
part('water_tower_frame', lambda: [rod('水塔承重柱', (x, y, 0), (x * .90, y * .90, 4.5), .11, 'wood_dark') for x, y in [(-1.35, -1.35), (1.35, -1.35), (-1.35, 1.35), (1.35, 1.35)]] + [rod('水塔斜撑', (x, y, .4), (-x * .9, y * .9, 4.25), .055, 'steel') for x, y in [(-1.35, -1.35), (1.35, -1.35), (-1.35, 1.35), (1.35, 1.35)]] + [cube('水塔顶部承重台', (0, 0, 4.42), (3.45, 3.45, .18), 'steel', 'SEA_Metal', .035)])

def wind_pump():
    rod('风机立杆', (0, 0, 0), (0, 0, 3.55), .075, 'silver')
    cyl('风机轮毂', (0, -.08, 3.58), .18, .26, 'honey', 'SEA_Metal', 16, rot=(math.pi / 2, 0, 0))
    for i in range(8):
        a = i * math.tau / 8
        cube('饱满风机叶片', (math.sin(a) * .62, -.12, 3.58 + math.cos(a) * .62), (.20, .08, .88), 'cream', 'SEA_Metal', .025, rot=(0, a, 0))
    cube('风机尾翼', (0, .72, 3.50), (.12, .85, .55), 'red', 'SEA_Metal', .03, rot=(.1, 0, 0))
part('wind_pump', wind_pump)

def solar_panel():
    angle = math.radians(24)
    cube('太阳能厚外框', (0, 0, .67), (2.10, 1.30, .13), 'silver', 'SEA_Metal', .045, rot=(angle, 0, 0))
    cube('太阳能深蓝面板', (0, -.015, .72), (1.94, 1.14, .065), 'deepblue', 'SEA_Metal', .025, rot=(angle, 0, 0))
    for x in [-.64, 0, .64]:
        cube('太阳能分格条', (x, -.045, .755), (.025, 1.12, .025), 'aqua', 'SEA_Metal', .005, rot=(angle, 0, 0))
    for x in [-.75, .75]:
        rod('太阳能低支架', (x, -.35, 0), (x, -.35, .55), .045, 'steel')
        rod('太阳能斜撑', (x, .35, 0), (x, -.35, .55), .035, 'steel')
part('solar_panel', solar_panel)
part('equipment_box', lambda: [cube('设备箱主体', (0, 0, .42), (1.05, .75, .84), 'sage_gray', 'SEA_Metal', .065), cube('设备箱厚盖', (0, 0, .86), (1.12, .82, .12), 'cloud', 'SEA_Metal', .035), cube('设备箱扣', (0, -.40, .48), (.14, .06, .20), 'honey', 'SEA_Metal', .012)])

# Planting and paths.
part('raised_bed', lambda: [cube('菜床土壤', (0, 0, .20), (5.20, 3.70, .34), 'bark', bev=.055)] + [cube('菜床长木框', (0, y, .24), (5.5, .18, .48), 'wood_mid', bev=.04) for y in [-1.91, 1.91]] + [cube('菜床短木框', (x, 0, .24), (.18, 3.70, .48), 'wood_light', bev=.04) for x in [-2.66, 2.66]])
part('main_field', lambda: [cube('主农田土壤', (0, 0, .08), (11, 8, .16), 'bark', bev=.045)] + [cube('主田纵向土垄', (-4.65 + i * 1.55, 0, .16), (1.05, 7.45, .22), 'wood_dark', bev=.075) for i in range(7)] + [cube('主田边界木线', (x, 0, .13), (.10, 8.05, .16), 'wood_mid', bev=.02) for x in [-5.48, 5.48]])
part('small_field', lambda: [cube('小农田土壤', (0, 0, .08), (4, 5, .16), 'bark', bev=.045)] + [cube('小田土垄', (-1.35 + i * 1.35, 0, .16), (.88, 4.65, .22), 'wood_dark', bev=.065) for i in range(3)] + [cube('小田石块边界', (x, -2.48, .18), (.55, .30, .28), 'stone', bev=.06) for x in [-1.6, -.8, 0, .8, 1.6]])

def leaf_row():
    cube('叶菜行土基', (0, 0, .055), (.72, 6.4, .11), 'bark', bev=.03)
    for i in range(9):
        y = -2.8 + i * .70
        for side in [-1, 1]:
            o = sphere('宽厚叶菜', (side * .16, y, .29), (.27, .32, .28), 'leaf' if i % 3 else 'leaf_light')
            o.rotation_euler.z = side * .35
part('leaf_row', leaf_row)

def seedling_row():
    cube('幼苗行土基', (0, 0, .045), (.66, 6.4, .09), 'bark', bev=.025)
    for i in range(8):
        y = -2.8 + i * .8
        rod('幼苗茎', (0, y, .08), (0, y, .34), .025, 'leaf_dark', 'SEA_Matte', 8)
        sphere('幼苗圆叶', (-.10, y, .28), (.16, .11, .10), 'leaf_light')
        sphere('幼苗圆叶', (.10, y, .31), (.16, .11, .10), 'leaf')
part('seedling_row', seedling_row)

def vine_row():
    cube('藤蔓行土基', (0, 0, .05), (.76, 6.4, .10), 'bark', bev=.025)
    for i in range(5):
        y = -2.8 + i * 1.4
        rod('藤蔓支撑杆', (0, y, 0), (0, y, 1.45), .032, 'wood_light', 'SEA_Matte', 10)
        tube('攀爬主茎', [(0, y, .1), (.12, y + .1, .55), (-.08, y, 1.05), (.08, y, 1.35)], .035, 'leaf_dark', 'SEA_Matte')
        for z in [.45, .80, 1.15]:
            sphere('藤蔓宽叶', (-.16, y, z), (.24, .17, .15), 'leaf')
            sphere('藤蔓宽叶', (.18, y + .06, z + .12), (.24, .17, .15), 'leaf_mid')
        if i % 2 == 0:
            sphere('橙红果实', (.20, y - .08, .72), (.12, .12, .14), 'coral')
part('vine_row', vine_row)
part('grass_patch', lambda: [sphere('圆润草苔', (0, 0, .07), (1.65, 1.15, .14), 'moss'), sphere('草地深绿团', (-.65, .20, .10), (.85, .75, .16), 'sage'), sphere('草地浅绿团', (.72, -.15, .09), (.72, .62, .14), 'moss_light')])
part('stepping_stone', lambda: cube('不规则厚石板', (0, 0, .06), (.72, .52, .12), 'cloud', bev=.09, rot=(0, 0, .08)))
part('wood_walkway', lambda: [cube('步道厚木板', (0, 0, .11), (1.35, .72, .22), 'wood_light', bev=.045), cube('木板端部压纹', (-.48, 0, .225), (.035, .62, .018), 'wood_mid', bev=.005), cube('木板端部压纹', (.48, 0, .225), (.035, .62, .018), 'wood_mid', bev=.005)])

# Furniture, storage and roof utilities.
part('round_table', lambda: [cyl('圆桌厚桌面', (0, 0, .78), .62, .16, 'plaster', 'SEA_Matte', 32, bev=.045), cyl('圆桌底座', (0, 0, .10), .36, .20, 'wood_mid', 'SEA_Matte', 24, bev=.03), rod('圆桌支柱', (0, 0, .15), (0, 0, .73), .11, 'wood_dark', 'SEA_Matte', 16)])
part('chair', lambda: [cube('椅面', (0, 0, .48), (.62, .62, .14), 'wood_light', bev=.055), cube('椅背', (0, .26, .88), (.62, .13, .75), 'wood_mid', bev=.055, rot=(-.08, 0, 0))] + [rod('椅腿', (x, y, 0), (x, y, .45), .045, 'darkwood', 'SEA_Matte') for x, y in [(-.23, -.23), (.23, -.23), (-.23, .23), (.23, .23)]])
part('crate', lambda: [cube('木箱主体', (0, 0, .40), (.85, .75, .80), 'wood_mid', bev=.045)] + [cube('木箱加固条', (x, -.39, .40), (.10, .07, .76), 'wood_light', bev=.015) for x in [-.30, .30]] + [cube('木箱盖', (0, 0, .82), (.90, .80, .10), 'wood_light', bev=.025)])
part('barrel', lambda: [cyl('圆肚木桶', (0, 0, .52), .40, 1.0, 'wood_mid', 'SEA_Matte', 24, bev=.065), cyl('桶盖', (0, 0, 1.02), .41, .10, 'wood_light', 'SEA_Matte', 24, bev=.025)] + [cyl('桶铁箍', (0, 0, z), .415, .075, 'steel', 'SEA_Metal', 24, bev=.012) for z in [.22, .78]])
part('planter_pot', lambda: [cyl('陶土花盆', (0, 0, .26), .27, .50, 'coral', 'SEA_Matte', 24, r2=.34, bev=.035), cyl('花盆厚边', (0, 0, .50), .37, .13, 'peach', 'SEA_Matte', 24, bev=.025), cyl('盆中土壤', (0, 0, .54), .29, .06, 'bark', 'SEA_Matte', 24, bev=.01)])

def potted_plant():
    for i in range(7):
        a = i * math.tau / 7
        o = sphere('盆栽宽厚叶', (math.sin(a) * .22, math.cos(a) * .22, .78 + (i % 2) * .10), (.18, .36, .16), 'leaf' if i % 2 else 'leaf_light')
        o.rotation_euler = (0, .45, -a)
    rod('盆栽中心茎', (0, 0, .45), (0, 0, .95), .035, 'leaf_dark', 'SEA_Matte', 10)
part('potted_plant', potted_plant)
part('low_fence', lambda: [rod('低围栏顶线', (-1.5, 0, .68), (1.5, 0, .68), .027, 'steel'), rod('低围栏中线', (-1.5, 0, .34), (1.5, 0, .34), .022, 'steel')] + [rod('低围栏立柱', (x, 0, 0), (x, 0, .72), .035, 'silver') for x in [-1.45, 0, 1.45]])
part('pipe_run', lambda: [tube('弯曲主管', [(0, 0, 0), (0, 0, 2.2), (0, -.15, 2.45), (0, -.55, 2.60), (0, -.85, 2.45), (0, -.85, 1.9)], .095, 'wood_dark', 'SEA_Metal', 3), cyl('管道接口', (0, 0, .25), .14, .18, 'steel', 'SEA_Metal', 16, bev=.015)])
part('lamp_post', lambda: [rod('屋顶灯杆', (0, 0, 0), (0, 0, 2.35), .055, 'silver'), tube('弯臂灯架', [(0, 0, 2.35), (0, -.15, 2.52), (0, -.48, 2.58), (0, -.68, 2.43)], .045, 'silver'), cyl('灯罩', (0, -.68, 2.35), .20, .18, 'seafoam', 'SEA_Metal', 20, r2=.10, bev=.02), sphere('暖灯', (0, -.68, 2.25), (.11, .11, .09), 'butter', 'SEA_Emission')])
part('chicken_coop', lambda: [cube('空家禽棚舍', (0, 0, .65), (1.65, 1.35, 1.30), 'wood_mid', bev=.055), cube('棚舍入口暗洞', (0, -.69, .47), (.55, .06, .72), 'darkwood', bev=.07), cube('棚舍蓝斜顶', (0, 0, 1.42), (1.90, 1.60, .15), 'teal', 'SEA_Metal', .04, rot=(.16, 0, 0))] + [rod('棚舍支脚', (x, y, 0), (x, y, .22), .055, 'darkwood', 'SEA_Matte') for x, y in [(-.65, -.45), (.65, -.45), (-.65, .45), (.65, .45)]])
part('water_trough', lambda: [cube('灌溉水槽外壳', (0, 0, .26), (1.80, .65, .50), 'seafoam', 'SEA_Metal', .065), cube('灌溉水槽水面', (0, 0, .48), (1.58, .46, .055), 'aqua', 'SEA_Gloss', .025)])
part('trellis', lambda: [rod('攀爬架立杆', (x, 0, 0), (x, 0, 1.85), .035, 'wood_light', 'SEA_Matte') for x in [-.75, .75]] + [rod('攀爬架横档', (-.78, 0, z), (.78, 0, z), .028, 'wood_mid', 'SEA_Matte') for z in [.45, .95, 1.45, 1.80]])
part('roof_hatch', lambda: [cube('检修入口框', (0, 0, .18), (1.35, 1.10, .36), 'cloud', bev=.055), cube('检修入口盖', (0, 0, .39), (1.22, .97, .10), 'sage_gray', 'SEA_Metal', .035), rod('检修盖把手', (-.18, 0, .49), (.18, 0, .49), .025, 'steel')])

# Assembly: 36x24m roof, front=-Y, three visible 3.2m floors.
inst('building_shell', (0, 0, 0))
for z in [0, 3.2, 6.4]:
    inst('floor_slab', (0, 0, z))
inst('roof_deck', (0, 0, 9.38))
for x in [-16.5, -8.3, 0, 8.3, 16.5]:
    inst('facade_column', (x, -12.30, 0))
for side in [-1, 1]:
    inst('facade_column', (side * 18.05, 4.5, 0), (0, 0, math.pi / 2), (.75, 1, 1))
for z in [.72, 3.92, 7.12]:
    for x in [-12.2, -4.1, 4.1, 12.2]:
        inst('facade_window', (x, -11.91, z))
for z in [.18, 3.38, 6.58]:
    for x in [-12.2, -4.1, 4.1, 12.2]:
        inst('balcony', (x, -12.35, z))
for side in [-1, 1]:
    for z in [.75, 3.95, 7.15]:
        for y in [-7.0, 0, 7.0]:
            inst('facade_window', (side * 17.88, y, z), (0, 0, side * math.pi / 2))
for y in [-11.83, 11.83]:
    for x in [-16, -12, -8, -4, 0, 4, 8, 12, 16]:
        inst('parapet', (x, y, 9.60))
        inst('railing_segment', (x, y, 9.60))
for x in [-17.83, 17.83]:
    for y in [-10, -6, -2, 2, 6, 10]:
        inst('parapet', (x, y, 9.60), (0, 0, math.pi / 2))
        inst('railing_segment', (x, y, 9.60), (0, 0, math.pi / 2))

# Left-rear raised living platform.
inst('raised_platform', (-12, 7, 9.60))
inst('upper_room', (-12, 8, 13.0))
inst('metal_ladder', (-12, 3.28, 9.60))
inst('clothesline', (-14.6, 6.8, 13.0))
for x in [-14, -10]:
    inst('railing_segment', (x, 10.35, 13.0))
inst('railing_segment', (-8.15, 7, 13.0), (0, 0, math.pi / 2))
inst('railing_segment', (-15.85, 8.5, 13.0), (0, 0, math.pi / 2))
inst('solar_panel', (-9.25, 7.3, 13.0), (0, 0, .08))
inst('solar_panel', (-9.25, 5.5, 13.0), (0, 0, -.06))
inst('equipment_box', (-9.3, 9.3, 13.0))
inst('pipe_run', (-15.75, 3.55, 9.65))
inst('small_lean_to', (-14.4, 1.65, 9.60))

# Shed, rest area, greenhouse, water and energy.
inst('tool_shed', (-4.7, 7.4, 9.60))
inst('shed_roof', (-4.7, 7.4, 12.62))
inst('round_table', (-3.7, 3.65, 9.60))
inst('chair', (-4.65, 3.35, 9.60), (0, 0, -.55))
inst('chair', (-2.75, 3.85, 9.60), (0, 0, 1.85))
inst('greenhouse_frame', (6.0, 6.1, 9.60))
inst('greenhouse_panels', (6.0, 6.1, 9.60))
inst('water_tower_frame', (14, 8, 9.60))
inst('water_tank', (14, 8, 14.10))
inst('wind_pump', (10.6, 8.7, 9.60))
for y in [3.6, 1.85, .10]:
    inst('solar_panel', (13.1, y, 9.60), (0, 0, .04))
inst('equipment_box', (15.6, 5.1, 9.60))

# Crop beds and rows.
for y in [-3.8, -9.0]:
    inst('raised_bed', (-4.7, y, 9.60))
for x in [-6.15, -4.7, -3.25]:
    inst('leaf_row', (x, -3.8, 10.02), scale=(.85, .47, .72))
    inst('seedling_row', (x, -9.0, 10.02), scale=(.90, .47, .85))
inst('main_field', (8.0, -6.4, 9.60))
for i, x in enumerate([3.35, 4.90, 6.45, 8.0, 9.55, 11.10, 12.65]):
    key = ['seedling_row', 'leaf_row', 'leaf_row', 'vine_row', 'leaf_row', 'leaf_row', 'seedling_row'][i]
    inst(key, (x, -6.4, 9.78), scale=(.90, 1.03, .85 if key != 'vine_row' else .90))
inst('trellis', (2.35, -6.2, 9.60), (0, 0, math.pi / 2))
inst('water_trough', (14.7, -6.2, 9.60))
inst('small_field', (.1, 3.05, 9.60))
for i, x in enumerate([-1.25, .1, 1.45]):
    inst('vine_row' if i == 1 else 'leaf_row', (x, 3.05, 9.78), scale=(.78, .66, .72))
for x in [5.15, 6.85]:
    inst('leaf_row', (x, 6.2, 9.72), scale=(.72, 1.05, .82))

# Open left activity area, without animals or people.
inst('chicken_coop', (-14.3, -7.8, 9.60), (0, 0, -.18))
for x in [-15.5, -12.5, -9.5]:
    inst('low_fence', (x, -10.9, 9.60))
for y in [-8.8, -5.8, -2.8]:
    inst('low_fence', (-17.0, y, 9.60), (0, 0, math.pi / 2))
for x, y, sx, sy in [(-12, -5.2, 1.6, 1.4), (-15, -1.5, 1.0, 1.2), (-10.3, -9.0, 1.0, 1.0), (-9.8, .2, 1.2, .8), (15.4, -1.7, .7, 1.1), (1.0, 9.5, 1.1, .7), (-1.5, -1.0, .7, .8)]:
    inst('grass_patch', (x, y, 9.62), scale=(sx, sy, 1))

# Stepping-stone network and timber paths.
for i in range(13):
    inst('stepping_stone', (.0 + random.uniform(-.16, .16), -10.7 + i * .86, 9.62), (0, 0, random.uniform(-.22, .22)), (1.05, 1.10, 1))
for i in range(7):
    inst('stepping_stone', (-8.0 + i * .80, 1.1 + random.uniform(-.12, .12), 9.62), (0, 0, random.uniform(-.25, .25)))
for i in range(6):
    inst('stepping_stone', (1.1 + i * .72, .45 + random.uniform(-.1, .1), 9.62), (0, 0, random.uniform(-.22, .22)))
for i in range(5):
    inst('wood_walkway', (-8.15, -8.8 + i * .78, 9.60))
inst('roof_hatch', (-9.3, 1.0, 9.60))

# Storage and pots kept clear of primary paths.
for key, pos, rot in [
    ('crate', (-6.9, 5.2, 9.60), (0, 0, .12)), ('crate', (-7.0, 4.3, 9.60), (0, 0, -.08)),
    ('crate', (-15.7, .1, 9.60), (0, 0, .15)), ('barrel', (-6.9, 8.7, 9.60), (0, 0, 0)),
    ('barrel', (-13.5, .1, 9.60), (0, 0, 0)), ('barrel', (15.7, 9.8, 9.60), (0, 0, 0))]:
    inst(key, pos, rot)
for x, y in [(-6.5, 6.2), (-2.1, 6.4), (-13.5, -6.5), (-8.0, -2.0), (3.0, 1.0), (8.8, 1.0), (15.8, -10.5), (-16.3, 10.4)]:
    inst('planter_pot', (x, y, 9.60))
    inst('potted_plant', (x, y, 9.60))
for x, y, rz in [(-12.2, -12.35, .2), (4.1, -9.35, -.15), (12.2, -6.35, .1)]:
    inst('planter_pot', (x, y, 3.62), scale=(.8, .8, .8))
    inst('potted_plant', (x, y, 3.62), scale=(.8, .8, .8))
for pos, rz in [((-17.0, -10.6, 9.60), 0), ((17.0, -10.6, 9.60), 0), ((-17.0, 10.6, 9.60), math.pi), ((17.0, 10.6, 9.60), math.pi)]:
    inst('lamp_post', pos, (0, 0, rz))
inst('pipe_run', (17.95, -7.8, .2), (0, 0, math.pi / 2), (1.3, 1.3, 2.8))
inst('pipe_run', (-8.0, 3.6, 9.60), (0, 0, .2), (1, 1, 1.2))

# Catalog and stable instance transforms.
cat = {'schema': 'sea.scene.component_catalog', 'components': []}
bpy.context.view_layer.update()
deps = bpy.context.evaluated_depsgraph_get()
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
    entry.update({
        'collection': col.name,
        'root': root.name,
        'bounds_size': list(hi - lo),
        'component_source': 'art_source/scenes/ocean_rooftop_farm/v001/component_packages/' + key + '/' + key + '.blend',
        'geometry_fingerprint': hashlib.sha256(geom.encode()).hexdigest(),
        'instances': sum(x['key'] == key for x in layout),
        'materials': ['SEA_Matte', 'SEA_Metal', 'SEA_Gloss', 'SEA_Emission'],
        'collision_owner': 'future above-water facility assembly; source visual only'
    })
    cat['components'].append(entry)
(D / 'component_catalog.json').write_text(json.dumps(cat, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
(D / 'component_instances.json').write_text(json.dumps({'schema': 'sea.scene.instances', 'up_axis': 'Z', 'front_axis': '-Y', 'godot_mapping': '(x,y,z)->(x,z,-y)', 'instances': layout}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

# Neutral studio illumination only: no ocean, ground, animals or background geometry.
world = bpy.data.worlds.new('屋顶农场柔和展示世界')
world.use_nodes = True
world.node_tree.nodes.clear()
bg = world.node_tree.nodes.new('ShaderNodeBackground')
bg.inputs[0].default_value = (.32, .48, .58, 1)
bg.inputs[1].default_value = .65
wo = world.node_tree.nodes.new('ShaderNodeOutputWorld')
world.node_tree.links.new(bg.outputs[0], wo.inputs[0])
sc.world = world
for name, loc, power, size, color, target in [
    ('暖阳主光', (-18, -24, 36), 3200, 14, (1.0, .86, .68), (0, 0, 8)),
    ('柔和天光', (20, 10, 28), 2400, 12, (.66, .84, 1.0), (0, 0, 9)),
    ('正面补光', (4, -28, 15), 1000, 10, (.85, .94, 1.0), (0, 0, 6))]:
    data = bpy.data.lights.new(name, 'AREA')
    data.energy = power
    data.shape = 'DISK'
    data.size = size
    data.color = color
    o = bpy.data.objects.new(name, data)
    groups['90_展示环境_不导出'].objects.link(o)
    o.location = loc
    o.rotation_euler = (Vector(target) - o.location).to_track_quat('-Z', 'Y').to_euler()
camd = bpy.data.cameras.new('参考全景相机')
cam = bpy.data.objects.new('参考全景相机', camd)
groups['90_展示环境_不导出'].objects.link(cam)
cam.location = (43, -55, 43)
cam.rotation_euler = (Vector((0, 0, 8.0)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
camd.type = 'ORTHO'
camd.ortho_scale = 52
sc.camera = cam
sc.render.engine = 'CYCLES'
sc.cycles.samples = 40
sc.cycles.use_denoising = True
sc.render.resolution_x = 1440
sc.render.resolution_y = 1000
sc.render.resolution_percentage = 100
sc.render.image_settings.file_format = 'PNG'
sc.render.film_transparent = False
sc.view_settings.view_transform = 'Standard'
sc.view_settings.look = 'Medium High Contrast'
sc.render.filepath = str(W / 'beauty_v001.png')
for im in bpy.data.images:
    if im.source == 'FILE':
        im.filepath = bpy.path.relpath(str(pal))
for area in bpy.context.screen.areas:
    if area.type == 'VIEW_3D':
        area.spaces.active.region_3d.view_perspective = 'CAMERA'
        area.spaces.active.shading.type = 'MATERIAL'
        area.spaces.active.overlay.show_overlays = False
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(D / 'ocean_rooftop_farm.blend'), compress=True)
print(json.dumps({'source': str(D / 'ocean_rooftop_farm.blend'), 'scene': scene_name, 'components': len(components), 'instances': len(layout), 'excluded': plan['excluded']}, ensure_ascii=False), flush=True)
