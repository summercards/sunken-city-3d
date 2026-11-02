import bpy, json, math, random
from pathlib import Path
from mathutils import Vector
R = Path(r'D:/projects/sea')
D = R / 'art_source/scenes/ocean_rooftop_farm/v001'
W = R.parent / 'sea-work/ocean_rooftop_farm/v001'
bpy.ops.wm.open_mainfile(filepath=str(D / 'ocean_rooftop_farm.blend'))
sc = bpy.data.scenes['海上屋顶农场_制作与装配_v001']
if bpy.context.window is not None:
    bpy.context.window.scene = sc
pal = R / 'art_source/shared/palettes/sea_cabin_timber_8x8_512.png'
colors = {x['name']: x for x in json.loads(pal.with_suffix('.json').read_text(encoding='utf-8'))['cells']}
roles = {n: bpy.data.materials[n] for n in ['SEA_Matte', 'SEA_Metal', 'SEA_Gloss', 'SEA_Emission']}
random.seed(228)


def uv(o, cell):
    for old in list(o.data.uv_layers):
        o.data.uv_layers.remove(old)
    layer = o.data.uv_layers.new(name='PaletteUV')
    c = colors[cell]
    u0 = c['column'] / 8
    v0 = 1 - (c['row'] + 1) / 8
    for p in o.data.polygons:
        for j, li in enumerate(p.loop_indices):
            co = [(.28,.28),(.72,.28),(.72,.72),(.28,.72)][j % 4]
            layer.data[li].uv = (u0 + co[0]/8, v0 + co[1]/8)
    o.data.uv_layers.active = layer
    layer.active_render = True


def finish(o, cell, role='SEA_Matte', bevel=0):
    o.data.materials.clear()
    o.data.materials.append(roles[role])
    uv(o, cell)
    if bevel:
        m = o.modifiers.new('破损柔边', 'BEVEL')
        m.width = bevel
        m.segments = 2
    return o


def patch(name, coords, cell):
    me = bpy.data.meshes.new(name)
    me.from_pydata(coords, [], [tuple(range(len(coords)))])
    me.update()
    o = bpy.data.objects.new(name, me)
    sc.collection.objects.link(o)
    return finish(o, cell)


def tube(name, points, radius, cell, role='SEA_Matte'):
    cu = bpy.data.curves.new(name, 'CURVE')
    cu.dimensions = '3D'
    cu.resolution_u = 1
    cu.bevel_depth = radius
    cu.bevel_resolution = 1
    sp = cu.splines.new('POLY')
    sp.points.add(len(points)-1)
    for p, co in zip(sp.points, points):
        p.co = (*co, 1)
    obj = bpy.data.objects.new(name, cu)
    sc.collection.objects.link(obj)
    deps = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(obj.evaluated_get(deps), depsgraph=deps)
    bpy.data.objects.remove(obj, do_unlink=True)
    result = bpy.data.objects.new(name, me)
    sc.collection.objects.link(result)
    return finish(result, cell, role)


def rod(name, a, b, r, cell, role='SEA_Metal'):
    a = Vector(a)
    b = Vector(b)
    axis = (b-a).normalized()
    u = axis.cross(Vector((0,0,1)))
    if u.length < .01:
        u = axis.cross(Vector((0,1,0)))
    u.normalize()
    v = axis.cross(u).normalized()
    verts = []
    for center in [a,b]:
        for i in range(10):
            theta = i*math.tau/10
            verts.append(center + r*(math.cos(theta)*u + math.sin(theta)*v))
    faces = [tuple(range(9,-1,-1)), tuple(range(10,20))]
    faces += [(i,(i+1)%10,(i+1)%10+10,i+10) for i in range(10)]
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    o = bpy.data.objects.new(name, me)
    sc.collection.objects.link(o)
    return finish(o, cell, role, .006)


def collect_into(key, objects):
    col = bpy.data.collections['SEA-SCENE-ORF-' + key.upper().replace('_','-')]
    root = next(o for o in col.objects if o.type == 'EMPTY')
    for o in objects:
        for c in list(o.users_collection):
            c.objects.unlink(o)
        col.objects.link(o)
        mw = o.matrix_world.copy()
        o.parent = root
        o.matrix_world = mw

# Enlarge and diversify existing facade weathering without changing component count.
col = bpy.data.collections['SEA-SCENE-ORF-FACADE-WEATHERING']
root = next(o for o in col.objects if o.type == 'EMPTY')
before = set(col.objects)
new = []
for x, z, w, h in [(-16.3, 6.2, 2.4, 3.8), (-2.0, 13.4, 2.6, 4.1), (14.5, 20.1, 2.5, 4.6), (-14.8, 24.0, 3.0, 1.8)]:
    shape = [(-.5,-.32),(-.25,-.50),(.20,-.45),(.48,-.12),(.40,.30),(.12,.50),(-.35,.38)]
    new.append(patch('加大的不规则墙皮剥落', [(x+a*w, -11.845, z+b*h) for a,b in shape], 'stone'))
    new.append(patch('剥落内部深色裸露层', [(x+a*w*.64, -11.852, z+b*h*.58) for a,b in shape], 'gray'))
for y, z, w, h in [(-10.2, 11.6, 2.8, 4.3), (3.6, 19.8, 2.8, 4.0)]:
    shape = [(-.5,-.32),(-.25,-.50),(.20,-.45),(.48,-.12),(.40,.30),(.12,.50),(-.35,.38)]
    new.append(patch('右侧加大的墙皮剥落', [(17.845, y+a*w, z+b*h) for a,b in shape], 'stone'))
# Broken parapet cap fragments and rusty runoff beneath selected roof edges.
for x in [-15, -7, 2, 11]:
    new.append(patch('屋顶压顶破损污迹', [(x-.9,-11.87,25.43),(x+.75,-11.87,25.45),(x+.48,-11.87,24.90),(x-.32,-11.87,24.72)], 'wood_mid'))
    new.append(tube('压顶向下裂纹', [(x,-11.89,25.5),(x-.18,-11.89,25.1),(x+.10,-11.89,24.75)], .023, 'slate'))
collect_into('facade_weathering', [o for o in col.objects if o not in before and o != root])

# Add hanging exterior pipework and damaged brackets to existing pipe component; keep local bottom center.
col = bpy.data.collections['SEA-SCENE-ORF-PIPE-RUN']
before = set(col.objects)
new = []
new.append(tube('附加外墙排水弯管', [(0,0,0),(0,0,3.5),(0,-.1,3.8),(0,-.55,3.9),(0,-.75,3.6)], .075, 'wood_dark', 'SEA_Metal'))
new.append(rod('附加管卡横杆', (-.26,0,2.8),(.26,0,2.8),.026,'steel'))
collect_into('pipe_run', [o for o in col.objects if o not in before])

# Long utility pipes on facade are separate transformed instances of that component.
layout_path = D / 'component_instances.json'
data = json.loads(layout_path.read_text(encoding='utf-8'))
group = bpy.data.collections['02_固定设施']
for idx, (x, z, sx, sz) in enumerate([(-17.2, .4, 1.2, 2.4), (16.7, 6.5, 1.0, 2.0), (-1.4, 15.0, .8, 1.6)]):
    name = 'pipe_run_facade_extra_' + str(idx+1)
    old = sc.objects.get(name)
    if old:
        bpy.data.objects.remove(old, do_unlink=True)
    o = bpy.data.objects.new(name, None)
    o.instance_type = 'COLLECTION'
    o.instance_collection = col
    o.location = (x, -12.0, z)
    o.scale = (sx, sx, sz)
    group.objects.link(o)
    data['instances'] = [i for i in data['instances'] if i['name'] != name]
    data['instances'].append({'name':name,'key':'pipe_run','asset_id':'SEA-SCENE-ORF-PIPE-RUN','position':list(o.location),'rotation_euler_xyz':[0,0,0],'scale':[sx,sx,sz],'category':'fixture'})
layout_path.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')

# Recompute catalog after local additions.
import hashlib
cat_path = D / 'component_catalog.json'
cat = json.loads(cat_path.read_text(encoding='utf-8'))
bpy.context.view_layer.update()
deps = bpy.context.evaluated_depsgraph_get()
for e in cat['components']:
    col = bpy.data.collections[e['collection']]
    pts = []
    for o in col.objects:
        if o.type == 'MESH':
            ev = o.evaluated_get(deps)
            me = ev.to_mesh()
            pts.extend(o.matrix_world @ v.co for v in me.vertices)
            ev.to_mesh_clear()
    lo = Vector([min(v[i] for v in pts) for i in range(3)])
    hi = Vector([max(v[i] for v in pts) for i in range(3)])
    e['bounds_size'] = list(hi-lo)
    geom = ';'.join(o.name+':'+','.join(str(round(c,4)) for v in o.data.vertices for c in v.co) for o in col.objects if o.type=='MESH')
    e['geometry_fingerprint'] = hashlib.sha256(geom.encode()).hexdigest()
    e['instances'] = sum(i['key']==e['key'] for i in data['instances'])
cat_path.write_text(json.dumps(cat, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')

# Render roof close-up and facade close-up to inspect damage at readable scale.
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(D / 'ocean_rooftop_farm.blend'), compress=True)
cam = sc.camera
views = [
    ('roof_detail_r2', (32,-38,53), (0,0,26.8), 43, (1440,1050)),
    ('facade_detail_r2', (21,-40,23), (0,-10,14), 32, (1200,1200)),
    ('beauty_r3', (48,-62,68), (0,0,13), 80, (1440,1100))
]
for name, pos, target, size, res in views:
    cam.location = pos
    cam.rotation_euler = (Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler()
    cam.data.ortho_scale = size
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.filepath = str(W/(name+'.png'))
    bpy.ops.render.render(write_still=True, scene=sc.name)
print(json.dumps({'views':[x[0] for x in views], 'instances':len(data['instances']), 'components':len(cat['components'])}, ensure_ascii=False))
