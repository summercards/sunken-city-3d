import bpy, math, json, random, os, hashlib
from pathlib import Path
from mathutils import Vector

random.seed(20261103)
ROOT = Path('D:/projects/sea')
OUT = ROOT / 'art_source/scenes/ocean_rooftop_farm/v002'
WORK = ROOT.parent / 'sea-work/ocean_rooftop_farm/v002'
OUT.mkdir(parents=True, exist_ok=True)
WORK.mkdir(parents=True, exist_ok=True)
PALETTE = ROOT / 'art_source/shared/palettes/sea_cabin_timber_8x8_512.png'
PAL_JSON = ROOT / 'art_source/shared/palettes/sea_cabin_timber_8x8_512.json'

# Fresh task scene; do not use the previous rooftop-farm master.
scene = bpy.data.scenes.new('海上巨型楼顶农场_重制_v002')
bpy.context.window.scene = scene
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1.0
scene.render.engine = 'BLENDER_EEVEE_NEXT'
scene.render.resolution_x = 1500
scene.render.resolution_y = 1050
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.render.film_transparent = False
scene.view_settings.look = 'AgX - Medium High Contrast'

# Collections follow project output boundaries.
root = bpy.data.collections.new('海上巨型楼顶农场_v002_资产总根')
scene.collection.children.link(root)
def col(name, parent=root):
    c = bpy.data.collections.new(name)
    parent.children.link(c)
    return c
c_struct = col('02_游戏输出_独立资产包_v002/01_建筑结构')
c_fac = col('02_游戏输出_独立资产包_v002/02_屋顶固定设施')
c_ag = col('02_游戏输出_独立资产包_v002/03_农业设施与作物')
c_veg = col('02_游戏输出_独立资产包_v002/04_草皮青苔与藤蔓')
c_sup = col('02_游戏输出_独立资产包_v002/05_附属设备')
c_qa = col('90_展示与验收_灯光相机')
c_src = col('01_制作组件_按设施拆分')
c_src.hide_viewport = True
c_src.hide_render = True

cells = {x['name']: x for x in json.loads(PAL_JSON.read_text(encoding='utf-8'))['cells']}
image = bpy.data.images.load(str(PALETTE), check_existing=True)
image.filepath = str(PALETTE)
roles = {}
def make_role(name, metallic, rough, coat=0.0, emission=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    n = m.node_tree.nodes; l = m.node_tree.links
    n.clear()
    out = n.new('ShaderNodeOutputMaterial')
    bs = n.new('ShaderNodeBsdfPrincipled')
    uv = n.new('ShaderNodeUVMap'); uv.uv_map = 'PaletteUV'
    tx = n.new('ShaderNodeTexImage'); tx.image = image; tx.interpolation = 'Closest'
    l.new(uv.outputs['UV'], tx.inputs['Vector'])
    l.new(tx.outputs['Color'], bs.inputs['Base Color'])
    l.new(bs.outputs['BSDF'], out.inputs['Surface'])
    bs.inputs['Metallic'].default_value = metallic
    bs.inputs['Roughness'].default_value = rough
    if 'Coat Weight' in bs.inputs: bs.inputs['Coat Weight'].default_value = coat
    if emission:
        l.new(tx.outputs['Color'], bs.inputs['Emission Color'])
        bs.inputs['Emission Strength'].default_value = emission
    roles[name] = m
make_role('01_精工金属_紫色骨架', 0.86, 0.28, 0.18)
make_role('02_细腻哑光_青绿大面', 0.03, 0.72)
make_role('03_清漆反光_紫粉点缀', 0.16, 0.16, 0.68)
make_role('04_柔和自发光_UI灯光', 0.0, 0.38, 0.0, 1.1)

def palette_uv(o, cell):
    for old in list(o.data.uv_layers):
        o.data.uv_layers.remove(old)
    uv = o.data.uv_layers.new(name='PaletteUV')
    c = cells[cell]
    u0 = c['column'] / 8.0; v0 = 1.0 - (c['row'] + 1) / 8.0
    q = [(0.28,0.28),(0.72,0.28),(0.72,0.72),(0.28,0.72)]
    for p in o.data.polygons:
        for j, li in enumerate(p.loop_indices):
            uv.data[li].uv = (u0 + q[j % 4][0] / 8.0, v0 + q[j % 4][1] / 8.0)
    o.data.uv_layers.active = uv; uv.active_render = True

def finish(o, cell='gray', role='02_细腻哑光_青绿大面', bevel=0.04, smooth=False):
    if hasattr(o.data, 'materials'):
        o.data.materials.clear(); o.data.materials.append(roles[role])
        palette_uv(o, cell)
        for p in o.data.polygons: p.material_index = 0; p.use_smooth = smooth
    if bevel and o.type == 'MESH':
        b = o.modifiers.new('项目柔和边角', 'BEVEL'); b.width = bevel; b.segments = 2
    return o

def move(o, target):
    for cc in list(o.users_collection): cc.objects.unlink(o)
    target.objects.link(o); return o

def cube(name, loc, size, cell='gray', role='02_细腻哑光_青绿大面', bevel=0.04, rot=None, target=c_struct):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o=bpy.context.object; o.name=name; o.dimensions=size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if rot: o.rotation_euler=rot
    move(o,target); return finish(o,cell,role,bevel)

def cyl(name, loc, radius, depth, cell='steel', role='01_精工金属_紫色骨架', verts=20, rot=None, target=c_fac, bevel=0.025, r2=None):
    if r2 is None: bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth, location=loc)
    else: bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=radius, radius2=r2, depth=depth, location=loc)
    o=bpy.context.object; o.name=name
    if rot: o.rotation_euler=rot
    move(o,target); return finish(o,cell,role,bevel,True)

def sphere(name, loc, scale, cell='leaf', role='02_细腻哑光_青绿大面', target=c_veg):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1, location=loc)
    o=bpy.context.object; o.name=name; o.scale=scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    move(o,target); return finish(o,cell,role,0,True)

def rod(name,a,b,r,cell='steel',role='01_精工金属_紫色骨架',target=c_fac):
    a=Vector(a); b=Vector(b); d=b-a
    o=cyl(name,(a+b)/2,r,d.length,cell,role,12,target=target,bevel=0.008)
    o.rotation_euler=d.to_track_quat('Z','Y').to_euler(); return o

def tube(name, pts, r, cell='steel', role='01_精工金属_紫色骨架', target=c_fac):
    cu=bpy.data.curves.new(name,'CURVE'); cu.dimensions='3D'; cu.bevel_depth=r; cu.bevel_resolution=2
    sp=cu.splines.new('POLY'); sp.points.add(len(pts)-1)
    for p,co in zip(sp.points,pts): p.co=(*co,1)
    o=bpy.data.objects.new(name,cu); target.objects.link(o)
    bpy.context.view_layer.objects.active=o; o.select_set(True); bpy.ops.object.convert(target='MESH')
    return finish(o,cell,role,0,True)

def empty(name, loc=(0,0,0), target=root):
    o=bpy.data.objects.new(name,None); target.objects.link(o); o.location=loc; return o

def parent(o,p):
    mw=o.matrix_world.copy(); o.parent=p; o.matrix_world=mw

# Building shell: 48 x 32 m, ten dense floors to roof at 51 m.
W=48.0; D=32.0; FLOOR=5.0; ROOF=50.6
cube('建筑主体_灰色混凝土_48x32x50m',(0,0,25.0),(W,D,50.0),'lightgray',bevel=.22)
# floor slabs and edge bands
for i in range(1,10):
    z=i*FLOOR
    cube(f'楼板外露接缝_{i:02d}',(0,0,z),(48.6,32.5,.28),'cloud',bevel=.06)
    for x in [-23.6,23.6]: cube(f'侧面楼板阴影_{i:02d}_{x}',(x,0,z),(0.28,32.2,.34),'gray',bevel=.03)
# front facade windows, balconies and crooked rails
for floor in range(10):
    z=2.2+floor*FLOOR
    for x in [-19,-11.4,-3.8,3.8,11.4,19]:
        cube(f'正立面窗框_{floor:02d}_{x}',(x,-16.12,z),(5.1,.22,3.1),'cloud',bevel=.08)
        cube(f'深蓝封闭窗_{floor:02d}_{x}',(x,-16.27,z),(4.35,.06,2.35),'deepblue','03_清漆反光_紫粉点缀',.025)
        if (floor+x) % 3 == 0:
            cube(f'破损木板封窗_{floor:02d}_{x}',(x-.4,-16.33,z),(2.0,.08,.16),'wood_dark',bevel=.015,rot=(0,.12,.18),target=c_fac)
    for x in [-15.2,-5.1,5.1,15.2]:
        cube(f'外凸阳台板_{floor:02d}_{x}',(x,-17.2,z-.35),(8.2,2.1,.32),'cloud',bevel=.10)
        cube(f'阳台前栏板_{floor:02d}_{x}',(x,-18.05,z+.35),(7.8,.18,1.05),'gray',bevel=.06,rot=(0,0,random.uniform(-.035,.035)))
        for px in [x-3.6,x,x+3.6]: rod(f'阳台锈栏杆_{floor:02d}_{px}',(px,-18.15,z-.1),(px+random.uniform(-.12,.12),-18.15,z+1.1),.055,'steel',target=c_fac)
# side facade windows and occasional balconies
for floor in range(10):
    z=2.2+floor*FLOOR
    for y in [-11,-3,5,13]:
        cube(f'东侧窗框_{floor:02d}_{y}',(24.12,y,z),(.22,5.1,3.0),'cloud',bevel=.08)
        cube(f'东侧玻璃_{floor:02d}_{y}',(24.27,y,z),(.06,4.3,2.3),'deepblue','03_清漆反光_紫粉点缀',.02)
# structural braces/columns
for x in [-20,-10,0,10,20]:
    cube(f'前立面结构柱_{x}',(x,-16.3,25.0),(1.0,.85,50.0),'gray',bevel=.13)
for y in [-12,-4,4,12]:
    cube(f'侧立面结构柱_{y}',(24.1,y,25.0),(.9,1.0,50.0),'gray',bevel=.13)
# facade weathering: exposed aggregate chips, rust drips, cracks and moss ledges
for i in range(56):
    x=random.uniform(-22.2,22.2); z=random.uniform(1,49); w=random.uniform(.45,2.7); h=random.uniform(.18,.75)
    cube(f'混凝土剥落斑_{i:02d}',(x,-16.48,z),(w,.06,h),random.choice(['stone','cloud','lightgray']),bevel=.03,target=c_fac)
for i in range(22):
    x=random.choice([-20,-10,0,10,20])+random.uniform(-1.0,1.0); z=random.uniform(2,48)
    tube(f'锈黄纵向水渍_{i:02d}',[(x,-16.53,z+1.6),(x+random.uniform(-.2,.2),-16.54,z),(x+random.uniform(-.45,.45),-16.54,z-.8)],.035,'ochre','02_细腻哑光_青绿大面',c_fac)
for i in range(22):
    x=random.uniform(-22,22); z=random.uniform(1,49)
    tube(f'立面交错裂纹_{i:02d}',[(x,-16.55,z),(x+.35,-16.56,z+.5),(x+.7,-16.56,z+.85)],.018,'slate','01_精工金属_紫色骨架',c_fac)
for x in [-23.9,-15.9,-7.9,.1,8.1,16.1,23.9]:
    cube(f'阴面厚青苔带_{x}',(x,-16.62,random.uniform(1,48)),(2.5,.05,.18),'forest',bevel=.04,target=c_veg)
# roof deck + parapet + metal rail
cube('楼顶混凝土平台',(0,0,50.55),(48.0,32.0,.5),'stone',bevel=.12)
# grass base, intentionally irregular blobs
for i in range(22):
    x=random.uniform(-20,20); y=random.uniform(-12,12)
    sphere(f'楼顶野生草皮_{i:02d}',(x,y,50.88),(random.uniform(2,4),random.uniform(1.5,3),.18),random.choice(['moss','sage','forest']),target=c_veg)
# parapet segments all around with moss top
for x in range(-22,23,4):
    cube(f'女儿墙前段_{x}',(x,-15.65,51.25),(3.8,1.1,1.1),'lightgray',bevel=.09)
    cube(f'女儿墙后段_{x}',(x,15.65,51.25),(3.8,1.1,1.1),'lightgray',bevel=.09)
    cube(f'女儿墙前青苔_{x}',(x,-15.08,51.7),(3.1,.06,.13),'forest',bevel=.025,target=c_veg)
    cube(f'女儿墙后青苔_{x}',(x,15.08,51.7),(3.1,.06,.13),'forest',bevel=.025,target=c_veg)
for y in range(-12,13,4):
    cube(f'女儿墙左段_{y}',(-23.65,y,51.25),(1.1,3.8,1.1),'gray',bevel=.09)
    cube(f'女儿墙右段_{y}',(23.65,y,51.25),(1.1,3.8,1.1),'gray',bevel=.09)
    cube(f'女儿墙右青苔_{y}',(23.08,y,51.7),(.06,3.1,.13),'forest',bevel=.025,target=c_veg)
# rooftop safety rails on parapet
for y in [-15.95,15.95]:
    rod('屋顶边缘锈蚀顶栏',(-22,y,52.25),(22,y,52.25),.06,'steel',target=c_sup)
    for x in range(-22,23,4): rod('屋顶边缘立柱',(x,y,51.5),(x,y,52.25),.045,'steel',target=c_sup)
for x in [-23.95,23.95]:
    rod('侧边锈蚀顶栏',(x,-14,52.25),(x,14,52.25),.06,'steel',target=c_sup)
    for y in range(-14,15,4): rod('侧边立柱',(x,y,51.5),(x,y,52.25),.045,'steel',target=c_sup)

# Raised garden beds and crop rows.
def bed(name,x,y,w,d,rot=0):
    cube(name+'_土壤',(x,y,51.15),(w,d,.28),'bark',bevel=.06,rot=(0,0,rot),target=c_ag)
    # crooked timber border
    for sx,sy,sz in [(0,-d/2,w), (0,d/2,w),(-w/2,0,.18),(w/2,0,.18)]:
        size=(sz,.22,.48) if sy else (.22, d, .48)
        cube(name+'_老化木框',(x+sx,y+sy,51.32),size,'wood_mid',bevel=.045,rot=(0,0,rot),target=c_ag)
    for i in range(max(2,int(w/1.2))):
        px=x-w/2+.7+i*1.0
        for j in range(max(2,int(d/1.0))):
            py=y-d/2+.65+j*.95
            sphere(name+'_作物叶簇',(px+random.uniform(-.12,.12),py+random.uniform(-.12,.12),51.55),(random.uniform(.16,.28),random.uniform(.20,.34),.10),random.choice(['leaf','leaf_light','leaf_mid']),target=c_ag)
# front/right crop layout
bed('前排大菜畦_01',7,-9,13,6,.02)
bed('前排大菜畦_02',19,-7,7,6,-.02)
bed('中排高架菜畦',-3,-4,7,4,.04)
bed('后排育苗畦',-1,4,5,4,-.05)
# trellis and irrigation pipes
for x in [1.5,4.5,7.5,10.5]:
    rod('菜畦灌溉主管',(x,-12,51.65),(x,12,51.65),.035,'steel',target=c_ag)
    for y in [-9,-6,-3,0,3,6,9]: rod('下垂支管',(x,y,51.62),(x+.10,y,51.38),.018,'steel',target=c_ag)
for x in [-6.5,-2.5,1.5]:
    rod('攀爬架立杆',(x,5,51.2),(x,5,53.5),.045,'wood_dark','02_细腻哑光_青绿大面',c_ag)
    for z in [52.0,52.7,53.35]: rod('攀爬架横杆',(x-.7,5,z),(x+.7,5,z),.03,'wood_mid','02_细腻哑光_青绿大面',c_ag)
    for j in range(4): sphere('攀爬作物叶子',(x+random.uniform(-.6,.6),5+random.uniform(-.25,.25),52.0+j*.35),(.25,.18,.12),'leaf_dark',target=c_ag)

# irregular stepping paths
for i in range(17):
    y=-13+i*1.55
    cube(f'错落步道石板_{i:02d}',(-10+random.uniform(-.25,.25),y,51.13),(1.8,1.05,.16),'cloud',bevel=.12,rot=(0,0,random.uniform(-.12,.12)),target=c_fac)
for i in range(13):
    x=-8+i*1.4
    cube(f'中央横向石板_{i:02d}',(x,0,51.13),(1.1,1.45,.16),'stone',bevel=.12,rot=(0,0,random.uniform(-.15,.15)),target=c_fac)
# grass tufts around paths and beds
for i in range(48):
    x=random.uniform(-21,21); y=random.uniform(-13,13)
    if abs(x)>20 or abs(y)>14: continue
    h=random.uniform(.18,.55)
    for j in range(3):
        rod('步道缝隙野草',(x+random.uniform(-.15,.15),y+random.uniform(-.12,.12),51.15),(x+random.uniform(-.25,.25),y+random.uniform(-.18,.18),51.15+h),.018,random.choice(['leaf_dark','forest','moss']), '02_细腻哑光_青绿大面', c_veg)

# Greenhouse at right, tilted 3 degrees toward +X.
gh=empty('温室_整体向右倾斜3度',(7,5,51.1),c_ag); gh.rotation_euler[1]=math.radians(-3)
def ghpart(o): parent(o,gh); return o
# local-ish geometry built at world then parent preserving transform; tilt is visual pivot around base
for x in [-3,3]:
    for y in [-2,0,2]:
        ghpart(rod('温室锈蚀立柱',(7+x,5+y,51.1),(7+x,5+y,54.2),.06,'steel',target=c_ag))
        ghpart(rod('温室斜屋脊肋',(7+x,5+y,54.2),(7,5+y,56.2),.055,'silver',target=c_ag))
for y in [-2,0,2]: ghpart(rod('温室屋脊',(7,5+y,56.2),(7,5+y,56.2),.055,'seafoam',target=c_ag))
# glass panels, some missing by design
for x in [-1.5,1.5]: ghpart(cube('温室透明玻璃面',(7+x,5,52.7),(2.9,4.2,.05),'palegreen','03_清漆反光_紫粉点缀',.01,rot=(0,math.radians(34 if x>0 else -34),0),target=c_ag))
for x in [-2.96,2.96]: ghpart(cube('温室侧墙玻璃',(7+x,5,52.65),(.05,4.1,2.9),'ice','03_清漆反光_紫粉点缀',.01,target=c_ag))
# front door
cube('温室木门',(7,2.92,52.65),(1.35,.10,2.8),'wood_dark',bevel=.04,target=c_ag)
for x in [6.45,7.55]: rod('温室门框',(x,2.84,51.2),(x,2.84,54.1),.05,'silver',target=c_ag)
# seedlings inside
for x in [5.4,6.2,7.0,7.8,8.6]:
    for y in [4.1,5.0,5.9]: sphere('温室幼苗',(x,y,51.7),( .18,.25,.26),'leaf_light',target=c_ag)
# windmill beside greenhouse
rod('小风车歪斜支架',(11,2,51.2),(11.25,2,55.0),.055,'steel',target=c_sup)
cyl('小风车轮毂',(11.25,1.92,55.0),.13,.24,'ochre',target=c_sup,rot=(math.pi/2,0,0))
for i in range(6):
    a=i*math.tau/6; cube('小风车不对称叶片',(11.25+math.sin(a)*.72,1.88,55.0+math.cos(a)*.72),(.18,.08,.95),'cream','01_精工金属_紫色骨架',.02,rot=(0,a+(.08 if i%2 else 0),0),target=c_sup)

# Red roof shed left/back.
cube('红色工具棚墙体',(-9,8,52.25),(5.0,3.8,3.2),'sage_gray',bevel=.08,rot=(0,0,.03),target=c_fac)
cube('工具棚门',(-9,6.05,52.0),(1.25,.12,2.25),'darkwood',bevel=.035,target=c_fac)
# two sloped roof panels
for side in [-1,1]: cube('红色波浪铁皮屋顶',(-9+side*1.35,8,54.0),(2.9,4.2,.16),'red_dark','01_精工金属_紫色骨架',.045,rot=(0,side*math.radians(20),0),target=c_fac)
for x in [-10.8,-10.2,-9.6,-9.0,-8.4,-7.8,-7.2]: rod('铁皮屋顶波纹',(x,5.95,53.48),(x,10.05,54.55),.035,'coral','01_精工金属_紫色骨架',c_fac)
# leaning wooden ladder and tool rack
for x in [-16,-15.2]: rod('斜靠木梯轨道',(x,5.7,51.2),(x+.8,5.7,55.1),.07,'wood_dark','02_细腻哑光_青绿大面',c_sup)
for i in range(6): rod('木梯踏板',( -16+i*.0,5.7,51.9+i*.55),(-15.2,5.7,51.9+i*.55),.045,'wood_light','02_细腻哑光_青绿大面',c_sup)
# left blue chicken coop, empty
coop=empty('空蓝色鸡舍_整体向前倾斜',( -17,-8,51.2),c_fac); coop.rotation_euler[0]=math.radians(-5)
for o in [cube('蓝色鸡舍主体',(-17,-8,52.0),(3.4,2.4,1.7),'teal',bevel=.06,target=c_fac), cube('鸡舍翘曲顶板',(-17,-8,53.05),(3.8,2.8,.18),'blue','01_精工金属_紫色骨架',.04,rot=(.1,0,.02),target=c_fac)]: parent(o,coop)
cube('鸡舍空门洞',(-17,-9.23,51.8),(1.0,.06,1.1),'darkwood',bevel=.06,target=c_fac)
for x in [-19,-17.5,-16,-14.5]: rod('鸡舍歪斜围栏',(x,-10.1,51.2),(x+.18, -10.2,52.25),.035,'wood_dark','02_细腻哑光_青绿大面',c_fac)
rod('鸡舍围栏上梁',(-19,-10.1,52.15),(-14.2,-10.2,52.25),.04,'wood_mid','02_细腻哑光_青绿大面',c_fac)

# Solar panels in groups on right side; two visibly sagging.
def solar_group(x,y,rz=0,sag=0):
    base=empty('太阳能板组_锈蚀支架',(x,y,51.2),c_sup); base.rotation_euler[2]=rz
    for sx in [-.9,.9]:
        o=rod('太阳能板锈蚀支腿',(x+sx,y-.45,51.2),(x+sx,y-.12,52.1+sag),.045,'steel',target=c_sup); parent(o,base)
        o=rod('太阳能板后支腿',(x+sx,y+.45,51.2),(x+sx,y+.45,51.6+sag),.04,'steel',target=c_sup); parent(o,base)
    panel=cube('太阳能深蓝面板',(x,y,52.1+sag),(2.2,1.3,.10),'deepblue','03_清漆反光_紫粉点缀',.035,rot=(math.radians(28),0,0),target=c_sup); parent(panel,base)
    for xx in [-.5,0,.5]:
        bar=cube('太阳能分格条',(x+xx,y-.02,52.18+sag),(.025,1.12,.03),'silver','01_精工金属_紫色骨架',.005,rot=(math.radians(28),0,0),target=c_sup); parent(bar,base)
for args in [(15,-5,.04,0),(19,-4,-.04,-.15),(15,-1,.0,-.12),(19,0,.07,0.0)]: solar_group(*args)

# Water tower back-right, tank top close to 60m, leaning 4 degrees left.
wt=empty('水塔_整体向左倾斜4度',(18,10,51.2),c_sup); wt.rotation_euler[1]=math.radians(-4)
for x,y in [(16.5,8.5),(19.5,8.5),(16.5,11.5),(19.5,11.5)]:
    o=rod('水塔腐朽木支柱',(x,y,51.2),(x,y,56.1),.13,'wood_dark','02_细腻哑光_青绿大面',c_sup); parent(o,wt)
for a,b in [((16.5,8.5,51.5),(19.5,11.5,55.8)),((19.5,8.5,51.5),(16.5,11.5,55.8))]:
    o=rod('水塔锈蚀斜撑',a,b,.055,'steel',target=c_sup); parent(o,wt)
# tank cylinder and cap
for o in [cyl('钢制储水罐',(18,10,57.2),1.65,3.2,'gray','01_精工金属_紫色骨架',32,target=c_sup,bevel=.09), cyl('储水罐锈蚀底环',(18,10,55.62),1.72,.16,'ochre','01_精工金属_紫色骨架',32,target=c_sup), cyl('储水罐顶盖',(18,10,58.85),1.75,.18,'red_dark','01_精工金属_紫色骨架',32,target=c_sup), cyl('储水罐锥形盖',(18,10,59.35),1.72,.85,'gray','01_精工金属_紫色骨架',32,r2=.16,target=c_sup,bevel=.04)]: parent(o,wt)
for i in range(7):
    a=-1.1+i*.34
    o=cube('水塔下半部锈穿片',(18+1.66*math.sin(a),10-1.66*math.cos(a),56.3+random.uniform(-.2,.4)),(.25,.05,.75),'red_dark','02_细腻哑光_青绿大面',.015,rot=(0,0,a),target=c_sup); parent(o,wt)
# moss base around tank
for i in range(8): sphere('水塔基座厚青苔',(18+random.uniform(-2,2),10+random.uniform(-2,2),51.3),(random.uniform(.4,1),random.uniform(.3,.7),.15),'forest',target=c_veg)

# Compost, pots and utility pipes.
cube('变形堆肥箱',(-4,10,51.8),(2.6,1.8,1.5),'wood_mid',bevel=.08,rot=(0,.04,-.08),target=c_ag)
for i,(x,y) in enumerate([(-2,11),(-1,10),(3,9),(12,10),(21,7),(-20,1)]):
    cyl(f'崩缺盆栽_{i}',(x,y,51.6),.42,.65,'coral','02_细腻哑光_青绿大面',20,target=c_ag,bevel=.035,r2=.34)
    sphere(f'盆栽叶簇_{i}',(x,y,52.15),(.38,.35,.42),'leaf_mid',target=c_veg)
tube('屋顶老化灌溉总管',[(-7,10,51.4),(-7,7,52.1),(-2,7,52.1),(4,6,51.6),(10,6,51.6)],.07,'steel','01_精工金属_紫色骨架',c_sup)

# facade ladders/clotheslines on front
for x in [-21,21]:
    for dx in [-.35,.35]: rod('外挂锈蚀爬梯轨道',(x+dx,-18.2,4),(x+dx,-18.2,15),.05,'steel',target=c_sup)
    for z in [5,7,9,11,13]: rod('外挂爬梯横档',(x-.35,-18.2,z),(x+.35,-18.2,z),.035,'silver',target=c_sup)
for x in [-18,-13]:
    rod('阳台晾衣架',(x,-19,28),(x,-19,31),.04,'steel',target=c_sup)
    tube('晾衣绳',[(x,-19,30.7),(x+2,-19,30.4),(x+4,-19,30.8)],.018,'wood_dark','02_细腻哑光_青绿大面',c_sup)
    cube('橙色晾晒衣物',(x+1,-19.04,29.9),(.65,.06,1.1),'red','02_细腻哑光_青绿大面',.03,rot=(0,.08,.03),target=c_sup)

# Metadata markers.
meta=empty('ASSET_META_海上巨型楼顶农场_v002',target=c_src)
meta['asset_id']='SEA-SCENE-ORF-ROOFTOP-FARM-V002'; meta['building_class']='above_water'; meta['water_layer']='surface'; meta['reference']='user supplied rooftop farm image'; meta['dimensions_m']='48x32 roof; 50.6 roof deck; 60m tower top'; meta['excluded']='animals, people, ocean, distant buildings, background geometry'; meta['palette_path']='art_source/shared/palettes/sea_cabin_timber_8x8_512.png'

# Studio presentation (no ocean/background geometry).
world=bpy.data.worlds.new('中性展示世界'); world.use_nodes=True
world.node_tree.nodes['Background'].inputs['Color'].default_value=(.055,.09,.12,1)
world.node_tree.nodes['Background'].inputs['Strength'].default_value=.28
scene.world=world
for name,loc,energy,size,color,target in [
    ('主光',(-30,-40,65),5200,22,(1.0,.76,.52),(0,0,30)),
    ('冷侧光',(35,10,45),4000,18,(.42,.70,1.0),(0,0,30)),
    ('顶光',(0,20,80),3200,20,(.75,1.0,.86),(0,0,50))]:
    ld=bpy.data.lights.new(name,'AREA'); ld.energy=energy; ld.shape='DISK'; ld.size=size; ld.color=color
    lo=bpy.data.objects.new(name,ld); c_qa.objects.link(lo); lo.location=loc; lo.rotation_euler=(Vector(target)-lo.location).to_track_quat('-Z','Y').to_euler()
camd=bpy.data.cameras.new('参考全景相机'); cam=bpy.data.objects.new('参考全景相机',camd); c_qa.objects.link(cam)
cam.location=(67,-78,67); cam.rotation_euler=(Vector((0,0,30))-cam.location).to_track_quat('-Z','Y').to_euler(); camd.type='ORTHO'; camd.ortho_scale=76; scene.camera=cam
scene.render.filepath=str(WORK/'rooftop_farm_r3_full.png')
# roof close-up camera saved as second camera object
cam2d=bpy.data.cameras.new('屋顶俯视验收相机'); cam2=bpy.data.objects.new('屋顶俯视验收相机',cam2d); c_qa.objects.link(cam2)
cam2.location=(0,-2,105); cam2.rotation_euler=(0,0,0); cam2.rotation_euler=(0,0,0); cam2.rotation_euler=(0,0,0)
cam2.rotation_euler=(Vector((0,0,51))-cam2.location).to_track_quat('-Z','Y').to_euler(); cam2d.type='ORTHO'; cam2d.ortho_scale=56
# set all objects visible in output and use active scene.
for o in scene.objects: o.select_set(False)
# save and render full view
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'ocean_rooftop_farm_r3.blend'), compress=True)
bpy.ops.render.render(write_still=True)
# render top view
scene.camera=cam2; scene.render.filepath=str(WORK/'rooftop_farm_r3_roof.png'); bpy.ops.render.render(write_still=True)
scene.camera=cam
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'ocean_rooftop_farm_r3.blend'), compress=True)
# simple inspection output
mesh_count=sum(1 for o in scene.objects if o.type=='MESH')
print(json.dumps({'scene':scene.name,'filepath':bpy.data.filepath,'objects':len(scene.objects),'mesh_objects':mesh_count,'materials':[m.name for m in roles.values()],'roof_dimensions_m':[48,32],'roof_z':50.6,'tower_top_m':60.0,'excluded':'animals/background/ocean/people','preview_full':str(WORK/'rooftop_farm_r3_full.png'),'preview_roof':str(WORK/'rooftop_farm_r3_roof.png')},ensure_ascii=False))
