import bpy, math, json
from mathutils import Vector
scene=bpy.context.scene
if not scene.name.startswith('海上巨型楼顶农场_重制_v002'): scene=max([s for s in bpy.data.scenes if s.name.startswith('海上巨型楼顶农场_重制_v002')], key=lambda s: len(s.objects))
bpy.context.window.scene=scene
root=next((c for c in bpy.data.collections if c.name.startswith('海上巨型楼顶农场_v002_资产总根')),None)
def getc(s):
 for c in bpy.data.collections:
  if c.name.split('.')[0].endswith(s): return c
c_fac=getc('02_屋顶固定设施'); c_ag=getc('03_农业设施与作物'); c_veg=getc('04_草皮青苔与藤蔓'); c_sup=getc('05_附属设备')
roles={n:bpy.data.materials.get(n) for n in ['01_精工金属_紫色骨架','02_细腻哑光_青绿大面','03_清漆反光_紫粉点缀','04_柔和自发光_UI灯光']}
def finish(o,cell='gray',r='02_细腻哑光_青绿大面',bev=.04,smooth=False):
 if hasattr(o.data,'materials'):
  o.data.materials.clear();o.data.materials.append(roles[r])
  if not o.data.uv_layers:o.data.uv_layers.new(name='PaletteUV')
  # Blender 4.5 keeps active layer through the active UV layer pointer
  for p in o.data.polygons:p.use_smooth=smooth
 if bev and o.type=='MESH':b=o.modifiers.new('项目柔和边角','BEVEL');b.width=bev;b.segments=2
 return o
def mv(o,t):
 for cc in list(o.users_collection):cc.objects.unlink(o)
 t.objects.link(o);return o
def cube(name,loc,size,cell='gray',r='02_细腻哑光_青绿大面',bev=.04,rot=None,t=c_fac):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.name=name;o.dimensions=size;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 if rot:o.rotation_euler=rot
 mv(o,t);return finish(o,cell,r,bev)
def cyl(name,loc,rad,depth,cell='steel',r='01_精工金属_紫色骨架',verts=20,rot=None,t=c_sup,bev=.025,r2=None):
 if r2 is None:bpy.ops.mesh.primitive_cylinder_add(vertices=verts,radius=rad,depth=depth,location=loc)
 else:bpy.ops.mesh.primitive_cone_add(vertices=verts,radius1=rad,radius2=r2,depth=depth,location=loc)
 o=bpy.context.object;o.name=name
 if rot:o.rotation_euler=rot
 mv(o,t);return finish(o,cell,r,bev,True)
def rod(name,a,b,rad,cell='steel',r='01_精工金属_紫色骨架',t=c_sup):
 a=Vector(a);b=Vector(b);o=cyl(name,(a+b)/2,rad,(b-a).length,cell,r,verts=10,t=t,bev=.008);o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler();return o
def sphere(name,loc,scale,cell='leaf',r='02_细腻哑光_青绿大面',t=c_veg):
 bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=1,location=loc);o=bpy.context.object;o.name=name;o.scale=scale;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);mv(o,t);return finish(o,cell,r,0,True)
def tube(name,pts,rad,cell='steel',r='01_精工金属_紫色骨架',t=c_sup):
 cu=bpy.data.curves.new(name,'CURVE');cu.dimensions='3D';cu.bevel_depth=rad;cu.bevel_resolution=1;sp=cu.splines.new('POLY');sp.points.add(len(pts)-1)
 for p,co in zip(sp.points,pts):p.co=(*co,1)
 o=bpy.data.objects.new(name,cu);t.objects.link(o);bpy.context.view_layer.objects.active=o;o.select_set(True);bpy.ops.object.convert(target='MESH');return finish(o,cell,r,0,True)
def emp(name,loc=(0,0,0),t=root):o=bpy.data.objects.new(name,None);t.objects.link(o);o.location=loc;return o
def par(o,p):mw=o.matrix_world.copy();o.parent=p;o.matrix_world=mw
# solar groups on right, deliberately two sagging
def solar(x,y,rz=0,sag=0):
 base=emp('太阳能板组_锈蚀支架',(x,y,51.2),c_sup);base.rotation_euler[2]=rz
 for sx in [-.9,.9]:
  o=rod('太阳能板锈蚀支腿',(x+sx,y-.45,51.2),(x+sx,y-.12,52.1+sag),.045,'steel',t=c_sup);par(o,base)
 panel=cube('太阳能深蓝面板',(x,y,52.1+sag),(2.2,1.3,.1),'deepblue','03_清漆反光_紫粉点缀',.035,rot=(math.radians(28),0,0),t=c_sup);par(panel,base)
 for xx in [-.5,0,.5]:
  o=cube('太阳能分格条',(x+xx,y-.02,52.18+sag),(.025,1.12,.03),'silver','01_精工金属_紫色骨架',.005,rot=(math.radians(28),0,0),t=c_sup);par(o,base)
for a in [(15,-5,.04,0),(19,-4,-.04,-.15),(15,-1,0,-.12),(19,0,.07,0)]:solar(*a)
# water tower with left lean
wt=emp('水塔_整体向左倾斜4度',(18,10,51.2),c_sup);wt.rotation_euler[1]=math.radians(-4)
for x,y in [(16.5,8.5),(19.5,8.5),(16.5,11.5),(19.5,11.5)]:par(rod('水塔腐朽木支柱',(x,y,51.2),(x,y,56.1),.13,'wood_dark','02_细腻哑光_青绿大面',c_sup),wt)
for a,b in [((16.5,8.5,51.5),(19.5,11.5,55.8)),((19.5,8.5,51.5),(16.5,11.5,55.8))]:par(rod('水塔锈蚀斜撑',a,b,.055,'steel',t=c_sup),wt)
for o in [cyl('钢制储水罐',(18,10,57.2),1.65,3.2,'gray','01_精工金属_紫色骨架',32,t=c_sup,bev=.09),cyl('储水罐锈蚀底环',(18,10,55.62),1.72,.16,'ochre','01_精工金属_紫色骨架',32,t=c_sup),cyl('储水罐顶盖',(18,10,58.85),1.75,.18,'red_dark','01_精工金属_紫色骨架',32,t=c_sup),cyl('储水罐锥形盖',(18,10,59.35),1.72,.85,'gray','01_精工金属_紫色骨架',32,r2=.16,t=c_sup,bev=.04)]:par(o,wt)
for i in range(7):par(cube('水塔下半部锈穿片',(18+1.66*math.sin(-1.1+i*.34),10-1.66*math.cos(-1.1+i*.34),56.3),(.25,.05,.75),'red_dark','02_细腻哑光_青绿大面',.015,rot=(0,0,-1.1+i*.34),t=c_sup),wt)
for i in range(8):sphere('水塔基座厚青苔',(18+(-2+i*.55),10+(-1+i%3*.9),51.3),(.55,.4,.15),'forest',t=c_veg)
# windmill near greenhouse
rod('小风车歪斜支架',(11,2,51.2),(11.25,2,55),.055,'steel',t=c_sup);cyl('小风车轮毂',(11.25,1.92,55),.13,.24,'ochre',t=c_sup,rot=(math.pi/2,0,0))
for i in range(6):
 a=i*math.tau/6;cube('小风车不对称叶片',(11.25+math.sin(a)*.72,1.88,55+math.cos(a)*.72),(.18,.08,.95),'cream','01_精工金属_紫色骨架',.02,rot=(0,a+(.08 if i%2 else 0),0),t=c_sup)
# facade ladders and clothes lines
for x in [-21,21]:
 for dx in [-.35,.35]:rod('外挂锈蚀爬梯轨道',(x+dx,-18.2,4),(x+dx,-18.2,15),.05,'steel',t=c_sup)
 for z in [5,7,9,11,13]:rod('外挂爬梯横档',(x-.35,-18.2,z),(x+.35,-18.2,z),.035,'silver',t=c_sup)
for x in [-18,-13]:
 rod('阳台晾衣架',(x,-19,28),(x,-19,31),.04,'steel',t=c_sup);tube('晾衣绳',[(x,-19,30.7),(x+2,-19,30.4),(x+4,-19,30.8)],.018,'wood_dark','02_细腻哑光_青绿大面',c_sup);cube('橙色晾晒衣物',(x+1,-19.04,29.9),(.65,.06,1.1),'red','02_细腻哑光_青绿大面',.03,rot=(0,.08,.03),t=c_sup)
# extra moss and vines on facade corners
for x in [-23,-20,20,23]:
 for z in [8,18,28,38,48]:
  tube('墙角匍匐藤蔓',[(x,-16.5,z),(x+random.uniform(-.3,.3),-16.55,z+.8),(x+random.uniform(-.5,.5),-16.58,z+1.3)],.025,'forest','02_细腻哑光_青绿大面',c_veg)
print(json.dumps({'stage':3,'objects':len(scene.objects),'meshes':sum(o.type=='MESH' for o in scene.objects)},ensure_ascii=False))
