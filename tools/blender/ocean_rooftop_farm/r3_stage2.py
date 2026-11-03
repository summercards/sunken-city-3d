import bpy, math, random, json
from mathutils import Vector
random.seed(20261103)
scene=bpy.context.scene
if not scene.name.startswith('海上巨型楼顶农场_重制_v002'): scene=max([s for s in bpy.data.scenes if s.name.startswith('海上巨型楼顶农场_重制_v002')], key=lambda s: len(s.objects))
bpy.context.window.scene=scene
root=next((c for c in scene.collection.children if c.name.startswith('海上巨型楼顶农场_v002_资产总根')),None)
def getc(s):
 for c in root.children:
  if c.name.startswith('02_游戏输出_独立资产包_v002/'+s): return c
 return root
c_struct=getc('01_建筑结构'); c_fac=getc('02_屋顶固定设施'); c_ag=getc('03_农业设施与作物'); c_veg=getc('04_草皮青苔与藤蔓'); c_sup=getc('05_附属设备')
roles={n:bpy.data.materials.get(n) for n in ['01_精工金属_紫色骨架','02_细腻哑光_青绿大面','03_清漆反光_紫粉点缀','04_柔和自发光_UI灯光']}
# palette helper uses existing material, preserves UV contract
def finish(o,cell='gray',r='02_细腻哑光_青绿大面',bev=.04,smooth=False):
 if hasattr(o.data,'materials'):
  o.data.materials.clear(); o.data.materials.append(roles[r]);
  for p in o.data.polygons:p.use_smooth=smooth
  if not o.data.uv_layers:
   uv=o.data.uv_layers.new(name='PaletteUV')
  else: uv=o.data.uv_layers.get('PaletteUV') or o.data.uv_layers.new(name='PaletteUV')
  uv.active_render=True
 if bev and o.type=='MESH': b=o.modifiers.new('项目柔和边角','BEVEL'); b.width=bev; b.segments=2
 return o
def mv(o,t):
 for cc in list(o.users_collection):cc.objects.unlink(o)
 t.objects.link(o);return o
def cube(name,loc,size,cell='gray',r='02_细腻哑光_青绿大面',bev=.04,rot=None,t=c_struct):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.name=name;o.dimensions=size;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 if rot:o.rotation_euler=rot
 mv(o,t);return finish(o,cell,r,bev)
def cyl(name,loc,rad,depth,cell='steel',r='01_精工金属_紫色骨架',verts=20,rot=None,t=c_fac,bev=.025,r2=None):
 if r2 is None:bpy.ops.mesh.primitive_cylinder_add(vertices=verts,radius=rad,depth=depth,location=loc)
 else:bpy.ops.mesh.primitive_cone_add(vertices=verts,radius1=rad,radius2=r2,depth=depth,location=loc)
 o=bpy.context.object;o.name=name
 if rot:o.rotation_euler=rot
 mv(o,t);return finish(o,cell,r,bev,True)
def sphere(name,loc,scale,cell='leaf',r='02_细腻哑光_青绿大面',t=c_veg):
 bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=1,location=loc);o=bpy.context.object;o.name=name;o.scale=scale;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);mv(o,t);return finish(o,cell,r,0,True)
def rod(name,a,b,rad,cell='steel',r='01_精工金属_紫色骨架',t=c_fac):
 a=Vector(a);b=Vector(b);o=cyl(name,(a+b)/2,rad,(b-a).length,cell,r,verts=10,t=t,bev=.008);o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler();return o
def tube(name,pts,rad,cell='steel',r='01_精工金属_紫色骨架',t=c_fac):
 cu=bpy.data.curves.new(name,'CURVE');cu.dimensions='3D';cu.bevel_depth=rad;cu.bevel_resolution=1;sp=cu.splines.new('POLY');sp.points.add(len(pts)-1)
 for p,co in zip(sp.points,pts):p.co=(*co,1)
 o=bpy.data.objects.new(name,cu);t.objects.link(o);bpy.context.view_layer.objects.active=o;o.select_set(True);bpy.ops.object.convert(target='MESH');return finish(o,cell,r,0,True)
def emp(name,loc=(0,0,0),t=root):o=bpy.data.objects.new(name,None);t.objects.link(o);o.location=loc;return o
def par(o,p):mw=o.matrix_world.copy();o.parent=p;o.matrix_world=mw
# beds with crops
def bed(name,x,y,w,d,rot=0):
 cube(name+'_土壤',(x,y,51.15),(w,d,.28),'bark',bev=.06,rot=(0,0,rot),t=c_ag)
 cube(name+'_木框前',(x,y-d/2,51.32),(w,.22,.48),'wood_mid',bev=.045,rot=(0,0,rot),t=c_ag);cube(name+'_木框后',(x,y+d/2,51.32),(w,.22,.48),'wood_mid',bev=.045,rot=(0,0,rot),t=c_ag)
 for i in range(max(2,int(w/1.2))):
  for j in range(max(2,int(d/1.0))):sphere(name+'_作物叶簇',(x-w/2+.7+i*1.0+random.uniform(-.1,.1),y-d/2+.65+j*.95+random.uniform(-.1,.1),51.55),(random.uniform(.16,.28),random.uniform(.2,.34),.1),random.choice(['leaf','leaf_light','leaf_mid']),t=c_ag)
# roof zones based on reference
bed('前排大菜畦_01',6,-9,13,6,.02);bed('前排大菜畦_02',18,-7,7,6,-.02);bed('中排高架菜畦',-3,-4,7,4,.04);bed('后排育苗畦',-1,4,5,4,-.05)
for x in [1.5,4.5,7.5,10.5]:
 rod('菜畦灌溉主管',(x,-12,51.65),(x,12,51.65),.035,'steel',t=c_ag)
 for y in [-9,-6,-3,0,3,6,9]:rod('下垂支管',(x,y,51.62),(x+.1,y,51.38),.018,'steel',t=c_ag)
for x in [-6.5,-2.5,1.5]:
 rod('攀爬架立杆',(x,5,51.2),(x,5,53.5),.045,'wood_dark','02_细腻哑光_青绿大面',c_ag)
 for z in [52,52.7,53.35]:rod('攀爬架横杆',(x-.7,5,z),(x+.7,5,z),.03,'wood_mid','02_细腻哑光_青绿大面',c_ag)
 for j in range(4):sphere('攀爬作物叶子',(x+random.uniform(-.6,.6),5+random.uniform(-.25,.25),52+j*.35),(.25,.18,.12),'leaf_dark',t=c_ag)
# paths and weeds
for i in range(17):cube(f'错落步道石板_{i:02d}',(-10+random.uniform(-.25,.25),-13+i*1.55,51.13),(1.8,1.05,.16),'cloud',bev=.12,rot=(0,0,random.uniform(-.12,.12)),t=c_fac)
for i in range(13):cube(f'中央横向石板_{i:02d}',(-8+i*1.4,0,51.13),(1.1,1.45,.16),'stone',bev=.12,rot=(0,0,random.uniform(-.15,.15)),t=c_fac)
for i in range(52):
 x=random.uniform(-21,21);y=random.uniform(-13,13)
 for j in range(2):rod('步道缝隙野草',(x+random.uniform(-.15,.15),y+random.uniform(-.12,.12),51.15),(x+random.uniform(-.25,.25),y+random.uniform(-.18,.18),51.15+random.uniform(.18,.5)),.018,random.choice(['leaf_dark','forest','moss']),'02_细腻哑光_青绿大面',c_veg)
# greenhouse frame and panels, right side, slight tilt
pivot=emp('温室_整体向右倾斜3度',(7,5,51.1),c_ag);pivot.rotation_euler[1]=math.radians(-3)
def g(o):par(o,pivot);return o
for x in [-3,3]:
 for y in [-2,0,2]:g(rod('温室锈蚀立柱',(7+x,5+y,51.1),(7+x,5+y,54.2),.06,'steel',t=c_ag));g(rod('温室斜屋脊肋',(7+x,5+y,54.2),(7,5+y,56.2),.055,'silver',t=c_ag))
for x in [-1.5,1.5]:g(cube('温室透明板',(7+x,5,52.7),(2.9,4.2,.05),'palegreen','03_清漆反光_紫粉点缀',.01,rot=(0,math.radians(34 if x>0 else -34),0),t=c_ag))
for x in [-2.96,2.96]:g(cube('温室侧墙玻璃',(7+x,5,52.65),(.05,4.1,2.9),'ice','03_清漆反光_紫粉点缀',.01,t=c_ag))
cube('温室木门',(7,2.92,52.65),(1.35,.1,2.8),'wood_dark',bev=.04,t=c_ag)
for x in [6.45,7.55]:rod('温室门框',(x,2.84,51.2),(x,2.84,54.1),.05,'silver',t=c_ag)
for x in [5.4,6.2,7,7.8,8.6]:
 for y in [4.1,5,5.9]:sphere('温室幼苗',(x,y,51.7),(.18,.25,.26),'leaf_light',t=c_ag)
# red shed and leaning ladder
cube('红色工具棚墙体',(-9,8,52.25),(5,3.8,3.2),'sage_gray',bev=.08,rot=(0,0,.03),t=c_fac);cube('工具棚门',(-9,6.05,52),(1.25,.12,2.25),'darkwood',bev=.035,t=c_fac)
for side in [-1,1]:cube('红色波浪铁皮屋顶',(-9+side*1.35,8,54),(2.9,4.2,.16),'red_dark','01_精工金属_紫色骨架',.045,rot=(0,side*math.radians(20),0),t=c_fac)
for x in [-10.8,-10.2,-9.6,-9,-8.4,-7.8,-7.2]:rod('铁皮屋顶波纹',(x,5.95,53.48),(x,10.05,54.55),.035,'coral','01_精工金属_紫色骨架',c_fac)
for x in [-16,-15.2]:rod('斜靠木梯轨道',(x,5.7,51.2),(x+.8,5.7,55.1),.07,'wood_dark','02_细腻哑光_青绿大面',c_sup)
for i in range(6):rod('木梯踏板',(-16,5.7,51.9+i*.55),(-15.2,5.7,51.9+i*.55),.045,'wood_light','02_细腻哑光_青绿大面',c_sup)
# empty blue coop
coop=emp('空蓝色鸡舍_整体向前倾斜',(-17,-8,51.2),c_fac);coop.rotation_euler[0]=math.radians(-5)
for o in [cube('蓝色鸡舍主体',(-17,-8,52),(3.4,2.4,1.7),'teal',bev=.06,t=c_fac),cube('鸡舍翘曲顶板',(-17,-8,53.05),(3.8,2.8,.18),'blue','01_精工金属_紫色骨架',.04,rot=(.1,0,.02),t=c_fac)]:par(o,coop)
cube('鸡舍空门洞',(-17,-9.23,51.8),(1,.06,1.1),'darkwood',bev=.06,t=c_fac)
for x in [-19,-17.5,-16,-14.5]:rod('鸡舍歪斜围栏',(x,-10.1,51.2),(x+.18,-10.2,52.25),.035,'wood_dark','02_细腻哑光_青绿大面',c_fac)
rod('鸡舍围栏上梁',(-19,-10.1,52.15),(-14.2,-10.2,52.25),.04,'wood_mid','02_细腻哑光_青绿大面',c_fac)
# compost and pots
cube('变形堆肥箱',(-4,10,51.8),(2.6,1.8,1.5),'wood_mid',bev=.08,rot=(0,.04,-.08),t=c_ag)
for i,(x,y) in enumerate([(-2,11),(-1,10),(3,9),(12,10),(21,7),(-20,1)]):
 cyl(f'崩缺盆栽_{i}',(x,y,51.6),.42,.65,'coral','02_细腻哑光_青绿大面',20,t=c_ag,bev=.035,r2=.34);sphere(f'盆栽叶簇_{i}',(x,y,52.15),(.38,.35,.42),'leaf_mid',t=c_veg)
print(json.dumps({'stage':2,'objects':len(scene.objects),'meshes':sum(o.type=='MESH' for o in scene.objects)},ensure_ascii=False))
