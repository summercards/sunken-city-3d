import bpy, math, json
from mathutils import Vector
scene=bpy.context.scene
root=next((c for c in bpy.data.collections if c.name.startswith('海上巨型楼顶农场_v002_资产总根')),None)
def getc(s):
 for c in bpy.data.collections:
  if c.name.split('.')[0].endswith(s) and any(o.name in scene.objects for o in c.objects): return c
 return next(c for c in bpy.data.collections if c.name.split('.')[0].endswith(s))
c_fac=getc('02_屋顶固定设施'); c_veg=getc('04_草皮青苔与藤蔓'); c_sup=getc('05_附属设备')
roles={n:bpy.data.materials.get(n) for n in ['01_精工金属_紫色骨架','02_细腻哑光_青绿大面','03_清漆反光_紫粉点缀','04_柔和自发光_UI灯光']}
def finish(o,cell='gray',r='02_细腻哑光_青绿大面',bev=.04):
 if hasattr(o.data,'materials'):
  o.data.materials.clear();o.data.materials.append(roles[r]);
  if not o.data.uv_layers:o.data.uv_layers.new(name='PaletteUV')
  o.data.uv_layers.active_index=0
 if bev and o.type=='MESH':b=o.modifiers.new('项目柔和边角','BEVEL');b.width=bev;b.segments=2
 return o
def mv(o,t):
 for cc in list(o.users_collection):cc.objects.unlink(o)
 t.objects.link(o);return o
def cube(name,loc,size,cell='gray',r='02_细腻哑光_青绿大面',bev=.04,rot=None,t=c_sup):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.name=name;o.dimensions=size;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 if rot:o.rotation_euler=rot
 mv(o,t);return finish(o,cell,r,bev)
def cyl(name,loc,rad,depth,cell='steel',r='01_精工金属_紫色骨架',verts=12,rot=None,t=c_sup,bev=.01):
 bpy.ops.mesh.primitive_cylinder_add(vertices=verts,radius=rad,depth=depth,location=loc);o=bpy.context.object;o.name=name
 if rot:o.rotation_euler=rot
 mv(o,t);return finish(o,cell,r,bev)
def rod(name,a,b,rad,cell='steel',r='01_精工金属_紫色骨架',t=c_sup):
 a=Vector(a);b=Vector(b);o=cyl(name,(a+b)/2,rad,(b-a).length,cell,r,t=t);o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler();return o
# ladders and drying frames, meshes only
for x in [-21,21]:
 for dx in [-.35,.35]:rod('外挂锈蚀爬梯轨道',(x+dx,-18.2,4),(x+dx,-18.2,15),.05,'steel',t=c_sup)
 for z in [5,7,9,11,13]:rod('外挂爬梯横档',(x-.35,-18.2,z),(x+.35,-18.2,z),.035,'silver',t=c_sup)
for x in [-18,-13]:
 rod('晾衣架立杆',(x,-19,28),(x,-19,31),.04,'steel',t=c_sup)
 rod('晾衣架横杆',(x,-19,30.7),(x+4,-19,30.7),.025,'steel',t=c_sup)
 for j in range(3):cube('橙红晾晒衣物',(x+1.1+j*1.1,-19.04,29.9+(.12 if j==1 else 0)),(.65,.06,1.1 if j!=1 else .75),'red' if j!=1 else 'cream',bev=.03,rot=(0,.08,.03),t=c_sup)
# vines and moss around corners
for x in [-23,-20,20,23]:
 for z in [8,18,28,38,48]:
  for j in range(3):
   rod('墙角匍匐藤蔓',(x,-16.5,z+j*.2),(x+(-.3 if j%2 else .3),-16.55,z+.8+j*.2),.025,'forest','02_细腻哑光_青绿大面',c_veg)
print(json.dumps({'stage':'3b','objects':len(scene.objects),'meshes':sum(o.type=='MESH' for o in scene.objects)},ensure_ascii=False))
