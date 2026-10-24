"""Build the new sea solar flower house source only. Never writes runtime scenes.
Run with Blender --background --factory-startup --python this_file -- [--render]
Existing source refuses overwrite unless --replace-generated is supplied.
"""
import bpy, math, random, json, hashlib, os, sys
from pathlib import Path
from mathutils import Vector, Matrix
R=Path(__file__).resolve().parents[3]
D=R/'art_source/scenes/solar_flower_house/v001'
W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'solar_flower_house'
if R==W or R in W.parents: raise RuntimeError('SEA_WORK_ROOT must be outside repository')
W.mkdir(parents=True,exist_ok=True); (W/'previews').mkdir(exist_ok=True)
plan=json.loads((D/'component_plan.json').read_text())
assert plan['status']=='frozen_before_geometry' and len(plan['components'])<=50
OUT=D/'solar_flower_house.blend'
if OUT.exists() and '--replace-generated' not in sys.argv: raise RuntimeError('Existing source: use an explicit new version or --replace-generated for this generated candidate')
bpy.ops.wm.read_factory_settings(use_empty=True)
random.seed(71)
scene=bpy.context.scene; scene.name='太阳能花屋_参考装配'
scene.unit_settings.system='METRIC'
lib=bpy.data.scenes.new('组件母版_建筑与花草')
lib.unit_settings.system='METRIC'
masters=bpy.data.collections.new('01_制作组件'); lib.collection.children.link(masters)
mb=bpy.data.collections.new('建筑_母版'); mf=bpy.data.collections.new('花草_母版'); masters.children.link(mb); masters.children.link(mf)
out=bpy.data.collections.new('02_参考装配_仅组件实例'); scene.collection.children.link(out)
building=bpy.data.collections.new('建筑_实例'); flora=bpy.data.collections.new('花草_实例'); out.children.link(building);out.children.link(flora)
support=bpy.data.collections.new('90_展示环境_不导出');scene.collection.children.link(support)
palette_path=R/'art_source/shared/palettes/sea_cozy_8x8_512.png'
img=bpy.data.images.load(str(palette_path));img.name='SEA_公共色板_8x8';img.colorspace_settings.name='sRGB'
cells={x['name']:x for x in json.loads(palette_path.with_suffix('.json').read_text())['cells']}
materials={}
for role,metal,rough in [('Matte',0,.72),('Metal',.65,.3),('Gloss',.1,.23),('Emission',0,.4)]:
 m=bpy.data.materials.new('SEA_'+role);m.use_nodes=True
 n=m.node_tree.nodes; n.clear();p=n.new('ShaderNodeBsdfPrincipled');p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough
 t=n.new('ShaderNodeTexImage');t.image=img;t.interpolation='Closest';t.extension='EXTEND'
 uv=n.new('ShaderNodeUVMap');uv.uv_map='PaletteUV';o=n.new('ShaderNodeOutputMaterial')
 m.node_tree.links.new(uv.outputs['UV'],t.inputs['Vector']);m.node_tree.links.new(t.outputs['Color'],p.inputs['Base Color']);m.node_tree.links.new(p.outputs[0],o.inputs[0])
 if role=='Gloss':p.inputs['Coat Weight'].default_value=.25
 if role=='Emission':m.node_tree.links.new(t.outputs['Color'],p.inputs['Emission Color']);p.inputs['Emission Strength'].default_value=.65
 materials[role]=m
current=None; components={}; records=[]
def activate(o):
 bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o

def finish(o,name,color='cream',role='Matte',bevel=0,smooth=True):
 o.name=name
 for c in list(o.users_collection):c.objects.unlink(o)
 current.objects.link(o)
 # The working collection is temporarily linked to the active scene.
 activate(o)
 bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 if bevel:
  mod=o.modifiers.new('柔和倒角_三段','BEVEL');mod.width=bevel;mod.segments=3
  bpy.ops.object.modifier_apply(modifier=mod.name)
 for p in o.data.polygons:p.use_smooth=smooth
 if bevel:
  mod=o.modifiers.new('平面加权法线','WEIGHTED_NORMAL');mod.keep_sharp=True;mod.weight=50
  try:bpy.ops.object.modifier_apply(modifier=mod.name)
  except RuntimeError:o.modifiers.remove(mod)
 o.data.transform(o.matrix_world);o.matrix_world=Matrix.Identity(4)
 o.data.materials.clear();o.data.materials.append(materials[role])
 for old_uv in list(o.data.uv_layers):o.data.uv_layers.remove(old_uv)
 uv=o.data.uv_layers.new(name='PaletteUV');uv.active_render=True
 cell=cells[color];cx=(cell['column']+.5)/8;cy=1-(cell['row']+.5)/8
 for p in o.data.polygons:
  count=len(p.loop_indices)
  for k,li in enumerate(p.loop_indices):
   a=2*math.pi*k/count;uv.data[li].uv=(cx+.022*math.cos(a),cy+.022*math.sin(a))
 o['palette_color']=color;o['soft_edge']='beveled_3_segments' if bevel else 'curved_surface'
 return o

def box(n,loc,size,col='cream',bev=.04,role='Matte',rot=None):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.scale=size
 if rot:o.rotation_euler=rot
 return finish(o,n,col,role,bev)
def uvball(n,loc,scale,col='leaf',role='Matte',rot=None):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=16,ring_count=10,location=loc);o=bpy.context.object;o.scale=scale
 if rot:o.rotation_euler=rot
 return finish(o,n,col,role)
def cyl(n,loc,radius,depth,col='wood',role='Matte',rot=None,vertices=32,r2=None):
 bpy.ops.mesh.primitive_cone_add(vertices=vertices,radius1=radius,radius2=radius if r2 is None else r2,depth=depth,location=loc)
 o=bpy.context.object
 if rot:o.rotation_euler=rot
 return finish(o,n,col,role,min(.025,radius*.13))
def torus(n,loc,major,minor,col='wood',rot=None,role='Matte'):
 bpy.ops.mesh.primitive_torus_add(major_segments=48,minor_segments=12,location=loc,major_radius=major,minor_radius=minor)
 o=bpy.context.object
 if rot:o.rotation_euler=rot
 return finish(o,n,col,role)
def line(n,pts,r=.025,col='wood',role='Matte'):
 curve=bpy.data.curves.new(n,'CURVE');curve.dimensions='3D';curve.resolution_u=16;curve.bevel_depth=r;curve.bevel_resolution=3
 sp=curve.splines.new('BEZIER');sp.bezier_points.add(len(pts)-1)
 for p,co in zip(sp.bezier_points,pts):p.co=co;p.handle_left_type='AUTO';p.handle_right_type='AUTO'
 o=bpy.data.objects.new(n,curve);scene.collection.objects.link(o);activate(o);bpy.ops.object.convert(target='MESH');return finish(bpy.context.object,n,col,role)
def mesh(n,verts,faces,col,bev=0):
 me=bpy.data.meshes.new(n);me.from_pydata(verts,[],faces);me.update();o=bpy.data.objects.new(n,me);scene.collection.objects.link(o);return finish(o,n,col,bevel=bev)
def leaf(n,base,tip,width,col):
 base=Vector(base);tip=Vector(tip);d=tip-base;side=d.cross(Vector((0,0,1))).normalized()
 if side.length<.1:side=Vector((1,0,0))
 v=[]
 for i in range(9):
  t=i/8;c=base+d*t+Vector((0,0,math.sin(t*math.pi)*d.length*.16));w=max(.006,math.sin(math.pi*t)**.85*width)
  v.extend([tuple(c-side*w),tuple(c+Vector((0,0,w*.22))),tuple(c+side*w)])
 faces=[]
 for i in range(8):
  for j in range(2):a=i*3+j;faces.append((a,a+3,a+4,a+1))
 o=mesh(n,v,faces,col);activate(o)
 mod=o.modifiers.new('叶片厚度','SOLIDIFY');mod.thickness=.012;bpy.ops.object.modifier_apply(modifier=mod.name)
 # Remap UV after solidify so rim faces also have nonzero islands.
 return finish(o,n,col)
def start(slug):
 global current
 item=next(c for c in plan['components'] if c['slug']==slug)
 current=bpy.data.collections.new(item['component_id']);(mf if item['category']=='flora' else mb).children.link(current);scene.collection.children.link(current)
 current['component_id']=item['component_id'];current['category']=item['category'];current.instance_offset=(0,0,0)
 return current

def end(slug):
 global current
 objs=list(current.objects)
 assert objs
 # Normalize each finished package to bottom center; bake every object transform.
 verts=[o.matrix_world@v.co for o in objs for v in o.data.vertices]
 lo=Vector(tuple(min(v[i] for v in verts) for i in range(3)));hi=Vector(tuple(max(v[i] for v in verts) for i in range(3)))
 anchor=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
 for o in objs:o.data.transform(Matrix.Translation(-anchor))
 # Consolidate nonemissive surfaces, keep the luminous mesh separate.
 final=[]
 groups={e:[o for o in objs if any(m.name=='SEA_Emission' for m in o.data.materials)==e] for e in [False,True]}
 for emissive,group in groups.items():
  if not group:continue
  bpy.ops.object.select_all(action='DESELECT')
  for o in group:o.select_set(True)
  bpy.context.view_layer.objects.active=group[0];
  if len(group)>1:bpy.ops.object.join()
  o=bpy.context.object
  o.name=slug+('_emissive' if emissive else '_body');o.data.name=o.name+'_mesh';o['soft_edges']='bevel_3_segments_and_smooth_curves';final.append(o)
 root=bpy.data.objects.new('ROOT_'+slug,None);current.objects.link(root)
 for o in final:o.parent=root
 components[slug]={'collection':current,'anchor':anchor,'bounds':list(hi-lo),'meshes':final}
 scene.collection.children.unlink(current)

def inst(slug,loc=(0,0,0),rot=(0,0,0),scale=1):
 c=components[slug];o=bpy.data.objects.new(slug+'_instance',None);o.instance_type='COLLECTION';o.instance_collection=c['collection']
 (flora if c['collection']['category']=='flora' else building).objects.link(o)
 o.rotation_euler=rot;o.scale=(scale,)*3;o.location=Vector(loc)+o.rotation_euler.to_matrix()@(c['anchor']*scale)
 item=next(x for x in plan['components'] if x['slug']==slug)
 o['component_id']=item['component_id']
 records.append({'component_id':item['component_id'],'instance_id':o.name,'position_m':list(o.location),'rotation_euler_xyz_rad':list(o.rotation_euler),'scale':list(o.scale),'source_object':o.name})
 return o
pi=math.pi
# --- Architecture ---
start('pier')
box('石墩',(0,0,.92),(.72,.72,1.84),'sand',.10)
box('石墩基座',(0,0,.09),(.82,.82,.18),'sage_gray',.065)
for i in range(22):
 z=random.uniform(.06,1.65);x=random.uniform(-.27,.27)
 box('风化浅斑',(x,-.365,z),(random.uniform(.06,.19),.014,random.uniform(.05,.15)),random.choice(['mint_white','moss','stone','cream']),.015)
end('pier')
start('foundation')
for x in [-3.5,3.5]:box('石框',(x,0,0),(.28,6.5,.30),'cream',.07)
for y in [-3.1,3.1]:box('石框',(0,y,0),(7.25,.32,.30),'sand',.07)
for x in [-3,-1,1,3]:box('底梁',(x,0,-.13),(.18,6.15,.22),'wood_dark',.035)
end('foundation')
start('deck_plank')
box('圆角木板',(0,0,0),(.338,1.55,.145),'wood_light',.035)
for y in [-.63,.63]:
 for x in [-.10,.10]:cyl('木钉',(x,y,.075),.016,.007,'wood_dark',vertices=12)
for x in [-.085,.06]:line('柔和木纹',[(x,-.51,.074),(x+.025,-.15,.076),(x-.01,.35,.076)],.005,'wood')
end('deck_plank')
start('wall_shell')
# Four walls with actual openings cut into the plaster.
w=box('正面灰泥墙',(0,-1.05,1.37),(4.8,.23,2.74),'cream',.065)
def cut_box(target,loc,size):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc);c=bpy.context.object;c.scale=size;activate(c);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 activate(target);m=target.modifiers.new('真实门洞','BOOLEAN');m.operation='DIFFERENCE';m.object=c;bpy.ops.object.modifier_apply(modifier=m.name);bpy.data.objects.remove(c,do_unlink=True)
 # Boolean creates faces: reset the palette islands using the shared material.
 finish(target,target.name,'cream',bevel=.025)
cut_box(w,(.91,-1.05,.98),(1.30,.6,2.08))
bpy.ops.mesh.primitive_cylinder_add(vertices=64,radius=.49,depth=.8,location=(-1.18,-1.05,1.45),rotation=(pi/2,0,0));c=bpy.context.object;activate(w);m=w.modifiers.new('圆窗真洞','BOOLEAN');m.object=c;m.operation='DIFFERENCE';bpy.ops.object.modifier_apply(modifier=m.name);bpy.data.objects.remove(c,do_unlink=True);finish(w,w.name,'cream',bevel=.02)
w=box('侧面灰泥墙',(-2.28,.65,1.37),(.23,3.6,2.74),'cream',.065)
cut_box(w,(-2.28,.45,.90),(.7,1.05,1.85))
box('侧面灰泥墙',(2.28,.65,1.37),(.23,3.6,2.74),'cream',.065)
box('背面灰泥墙',(0,2.34,1.37),(4.8,.23,2.74),'plaster',.065)
box('室内木地板',(0,.65,.04),(4.35,3.2,.1),'wood',.025)
for i in range(40):
 x=random.uniform(-2.2,2.2);z=random.uniform(.15,2.6)
 if .2<x<1.65 and z<2.1:continue
 if (x+1.18)**2+(z-1.45)**2<.6**2:continue
 box('灰泥细碎斑',(x,-1.175,z),(random.uniform(.025,.09),.008,random.uniform(.025,.10)),random.choice(['sand','white','mint_white']),.01)
end('wall_shell')
start('roof_terrace')
box('露台基板',(0,.65,0),(5.0,3.8,.22),'wood',.055)
for i in range(15):box('屋顶铺板',(-2.32+i*.331,.65,.15),(.316,3.72,.10),'wood_light',.025)
end('roof_terrace')
start('parapet')
box('花台墙',(0,0,.18),(1.6,.27,.36),'cream',.055);box('花台墙顶',(0,0,.39),(1.65,.32,.12),'sand',.045)
end('parapet')
start('solar_panel')
box('白色软边边框',(0,0,0),(1.42,1.55,.13),'snow',.065)
box('蓝色光伏玻璃',(0,0,.072),(1.27,1.4,.026),'solar',.018,'Gloss')
for x in range(7):box('电池竖栅',(-.57+x*.19,0,.09),(.012,1.36,.008),'ice',.004)
for y in range(9):box('电池横栅',(0,-.65+y*.163,.092),(1.24,.009,.008),'ice',.003)
for x in [-.65,.65]:
 for y in [-.71,.71]:cyl('安装钉',(x,y,.071),.026,.025,'steel','Metal',vertices=16)
end('solar_panel')
start('roof_beam')
box('圆角屋架木梁',(0,0,0),(.15,3.8,.18),'wood',.055)
for y in [-1.75,1.75]:box('箍带',(0,y,0),(.18,.13,.20),'gold',.025,'Metal')
end('roof_beam')
start('ladder')
for x in [-.32,.32]:box('梯柱',(x,0,1.5),(.13,.15,3.0),'wood',.045)
for i in range(10):box('梯阶',(0,-.035,.12+i*.298),(.7,.17,.10),'wood_light',.035)
end('ladder')
start('door_arch')
# Wooden side door, round top made from a polygon extrusion.
vs=[(-.48,0,0),(.48,0,0)]+[(.48*math.cos(a),0,1.45+.48*math.sin(a)) for a in [i*pi/16 for i in range(17)]]
vs=vs[:2]+vs[2:];n=len(vs);v=vs+[(x,.09,z) for x,y,z in vs];f=[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
mesh('拱门木芯',v,f,'wood_mid',.035)
pts=[(-.53,-.05,.02),(-.53,-.05,1.45)]+[(.53*math.cos(pi-i*pi/16),-.05,1.45+.53*math.sin(pi-i*pi/16)) for i in range(17)]+[(.53,-.05,.02)]
line('金色门框',pts,.07,'ochre')
for x in [-.28,0,.28]:box('门板压条',(x,-.055,.7),(.025,.024,1.35),'wood_dark',.01)
box('门窗玻璃',(0,-.07,1.43),(.45,.03,.42),'deepblue',.06,'Gloss')
for x in [-.12,.12]:box('门窗分格',(x,-.10,1.43),(.024,.035,.42),'wood_light',.01)
uvball('黄铜把手',(.29,-.16,.82),(.045,.045,.045),'gold','Metal');end('door_arch')
start('door_shutter')
box('青色门扇',(0,0,.95),(.63,.11,1.9),'teal',.04)
for x in [-.25,.25]:box('门边框',(x,-.065,.95),(.07,.04,1.82),'aqua',.02)
for z in [.1,.7,1.75]:box('横档',(0,-.075,z),(.57,.06,.06),'aqua',.02)
for z in [1.0,1.14,1.28,1.42,1.56]:box('百叶',(0,-.075,z),(.48,.06,.08),'ocean',.02)
uvball('门把手',(-.19,-.14,.79),(.035,.03,.045),'gold','Metal');end('door_shutter')
start('porthole')
cyl('海蓝窗玻璃',(0,0,0),.465,.045,'deepblue','Gloss',rot=(pi/2,0,0))
torus('圆窗金框',(0,-.06,0),.485,.065,'gold',rot=(pi/2,0,0))
box('窗十字',(0,-.105,0),(.052,.035,.88),'wood_edge',.014);box('窗十字',(0,-.105,0),(.88,.035,.052),'wood_edge',.014);end('porthole')
start('awning')
# Curved striped canvas, broad front scallops, rolled mounting bar.
for j in range(9):
 x=-.99+j*.247;v=[]
 for i in range(9):
  t=i/8;y=-t;z=.04-.35*t+.12*math.sin(pi*t)
  v.extend([(x-.121,y,z),(x+.121,y,z)])
 f=[(2*i,2*i+1,2*i+3,2*i+2) for i in range(8)]
 o=mesh('布棚条纹',v,f,'butter' if j%2 else 'yellow');activate(o);s=o.modifiers.new('帆布厚度','SOLIDIFY');s.thickness=.025;bpy.ops.object.modifier_apply(modifier=s.name);finish(o,o.name,'butter' if j%2 else 'yellow')
 box('圆润垂边',(x,-1.01,-.42),(.244,.045,.20),'butter' if j%2 else 'yellow',.075)
line('顶轴',[(-1.18,0,0),(1.18,0,0)],.06,'ochre')
for x in [-1.05,1.05]:line('棚支架',[(x,-.03,-.6),(x,-1,-.37)],.027,'wood')
end('awning')
start('shade_sail')
v=[]
for j in range(13):
 for i in range(13):
  u=i/12;t=j/12;x=(u-.5)*1.60;y=(t-.5)*1.95;z=-.40*math.sin(pi*u)*math.sin(pi*t)+.18*t
  v.append((x,y,z))
f=[]
for j in range(12):
 for i in range(12):a=j*13+i;f.append((a,a+1,a+14,a+13))
o=mesh('柔软帆布',v,f,'butter');activate(o);s=o.modifiers.new('帆厚','SOLIDIFY');s.thickness=.018;bpy.ops.object.modifier_apply(modifier=s.name);finish(o,o.name,'butter')
for k in [0,12]:line('帆边缝线',[v[k*13+i] for i in range(13)],.014,'gold')
for k in [0,12]:line('帆边缝线',[v[j*13+k] for j in range(13)],.014,'gold')
end('shade_sail')
start('post')
cyl('木桩',(0,0,.5),.13,1,'wood_mid',vertices=12);cyl('桩帽',(0,0,1.01),.145,.10,'wood_light',vertices=12)
for z in [.74,.8,.86]:torus('绳圈',(0,0,z),.14,.022,'sand')
for a in [0,1.3,2.6,4]:line('木桩纹',[(.13*math.cos(a),.13*math.sin(a),.13),(.13*math.cos(a+.03),.13*math.sin(a+.03),.63)],.006,'wood_dark')
end('post')
start('sail_mast')
cyl('细木帆杆',(0,0,1.15),.085,2.30,'wood_mid',vertices=16)
cyl('帆杆顶帽',(0,0,2.30),.105,.09,'wood_light',vertices=16)
for z in [2.10,2.14,2.18]:torus('帆绳结',(0,0,z),.09,.016,'sand')
end('sail_mast')
start('rope_span')
pts=[(-1.10,0,.1),(-.6,0,-.13),(0,0,-.22),(.6,0,-.13),(1.10,0,.1)]
line('柔软麻绳',pts,.036,'sand')
for strand in range(3):
 pts=[]
 for i in range(81):
  t=i/80;x=-1.1+2.2*t;a=t*48*pi+strand*2*pi/3;z=.1-.32*math.sin(pi*t)
  pts.append((x,.031*math.cos(a),z+.031*math.sin(a)))
 line('麻绳股',pts,.008,'cream' if strand==0 else 'wood_edge')
end('rope_span')
start('tire')
torus('柔软轮胎',(0,0,0),.37,.14,'rubber',rot=(pi/2,0,0));torus('胎侧凸线',(0,-.11,0),.37,.028,'slate',rot=(pi/2,0,0))
for i in range(36):
 a=2*pi*i/36;box('胎纹',(.47*math.sin(a),0,.47*math.cos(a)),(.035,.16,.025),'slate',.012,rot=(0,a,0))
line('吊索',[(0,-.13,-.15),(-.04,-.18,.28),(0,-.08,.69),(.07,.06,.74)],.027,'sand');end('tire')
start('lifebuoy')
for j in range(8):
 pts=[(.43*math.cos((j+i/12)*pi/4),0,.43*math.sin((j+i/12)*pi/4)) for i in range(13)]
 line('救生圈分段',pts,.105,'coral' if j%2==0 else 'snow')
torus('救生圈外绳',(0,0,0),.565,.018,'sand',rot=(pi/2,0,0));end('lifebuoy')
start('lantern')
cyl('灯脚',(0,0,.06),.17,.09,'wood_dark','Metal',vertices=6)
cyl('灯芯_emissive',(0,0,.27),.12,.32,'butter','Emission',vertices=6)
for a in [i*pi/3 for i in range(6)]:line('灯框',[(.145*math.cos(a),.145*math.sin(a),.08),(.145*math.cos(a),.145*math.sin(a),.45)],.014,'darkwood','Metal')
cyl('尖顶',(0,0,.49),.22,.15,'wood_dark','Metal',vertices=6,r2=.07);uvball('灯尖',(0,0,.60),(.04,.04,.07),'gold','Metal')
torus('提环',(0,0,.7),.065,.013,'darkwood',rot=(pi/2,0,0),role='Metal');end('lantern')
start('bench')
for x in [-.55,.55]:
 for y in [-.23,.23]:box('椅腿',(x,y,.28),(.09,.10,.56),'wood',.03)
box('椅座',(0,0,.52),(1.3,.65,.11),'wood_light',.04)
box('椅背',(0,.27,.87),(1.3,.10,.60),'wood',.045,rot=(-.12,0,0))
box('蓝色软坐垫',(0,-.015,.62),(1.15,.52,.14),'aqua',.085)
for x,c,a in [(-.32,'yellow',.15),(.28,'butter',-.2)]:box('柔软靠枕',(x,.16,.94),(.43,.16,.42),c,.095,rot=(.08,a,0))
end('bench')
start('shelf')
for x in [-.48,.48]:box('书架竖板',(x,0,.88),(.075,.35,1.76),'wood',.025)
for z in [.1,.65,1.23,1.73]:box('书架层板',(0,0,z),(1.02,.4,.08),'wood_light',.025)
for i,c in enumerate(['blue','coral','cream','leaf','ochre']):box('彩色书本',(-.32+i*.14,-.04,.83),(.105,.24,.28),c,.013,rot=(0,random.uniform(-.1,.1),0))
box('下层靠垫',(0,0,.25),(.65,.32,.18),'aqua',.08);end('shelf')
start('planter_round')
cyl('陶盆',(0,0,.23),.24,.46,'plaster',vertices=32,r2=.30);torus('盆口',(0,0,.45),.29,.035,'sand');cyl('土壤',(0,0,.45),.26,.012,'darkwood');end('planter_round')
start('planter_square')
box('方盆',(0,0,.28),(.66,.66,.56),'sand',.065);box('盆沿',(0,0,.55),(.71,.71,.10),'cream',.04);box('盆土',(0,0,.605),(.55,.55,.02),'darkwood',.035);end('planter_square')
start('crate')
for x in [-.34,.34]:
 for y in [-.27,.27]:box('木箱角柱',(x,y,.31),(.07,.07,.62),'wood',.02)
for z in [.1,.27,.44]:
 for y in [-.28,.28]:box('蓝色箱板',(0,y,z),(.74,.065,.13),'aqua',.02)
 for x in [-.35,.35]:box('蓝色箱板',(x,0,z),(.065,.57,.13),'blue',.02)
box('箱底',(0,0,.04),(.7,.55,.08),'wood',.02);end('crate')
start('boiler')
cyl('蓝色锅炉',(0,0,.53),.42,.93,'blue','Gloss');cyl('奶白炉盖',(0,0,1.03),.45,.15,'snow');cyl('炉底座',(0,0,.08),.44,.12,'steel','Metal')
cyl('弯烟管',(.16,.13,1.37),.075,.64,'wood_dark','Metal');line('烟管弯头',[(.16,.13,1.65),(.16,.13,1.77),(.09,.13,1.82)],.08,'wood_dark','Metal')
cyl('小排气嘴',(-.18,-.07,1.2),.06,.24,'cloud','Metal');box('标签',(0,-.417,.65),(.25,.022,.23),'peach',.025)
for x in [-.44,.44]:line('提手',[(x,0,.88),(x*1.2,0,.94),(x*1.2,0,.72)],.035,'gold','Metal')
end('boiler')
start('rug')
box('地毯',(0,0,0),(1.45,.86,.035),'cream',.025);box('蓝色织面',(0,0,.022),(1.34,.75,.012),'aqua',.02)
for x in [-.62,.62]:box('毯边细纹',(x,0,.032),(.016,.69,.006),'snow',.003)
for y in [-.32,.32]:box('毯边细纹',(0,y,.032),(1.24,.016,.006),'snow',.003)
for x in [-.74,.74]:
 for i in range(16):line('流苏',[(x,-.38+i*.05,0),(x+(.08 if x>0 else -.08),-.38+i*.05,.005)],.008,'cream')
end('rug')
start('gutter')
line('圆弯排水管',[(0,0,.10),(0,0,.40),(-.15,0,.52),(-.65,0,.52),(-.83,.10,.52)],.075,'snow')
for x in [-.23,-.61]:torus('管接环',(x,0,.52),.078,.016,'lightgray',rot=(0,pi/2,0))
end('gutter')
start('cup')
cyl('水杯',(0,0,.13),.1,.26,'aqua');torus('杯口',(0,0,.26),.1,.014,'ice');cyl('杯内',(0,0,.265),.075,.008,'deepblue');torus('把手',(.115,0,.14),.065,.018,'aqua',rot=(pi/2,0,0));end('cup')
start('table')
for x in [-.4,.4]:
 for y in [-.24,.24]:box('桌腿',(x,y,.40),(.075,.075,.8),'wood',.025)
box('工作台面',(0,0,.83),(1.0,.67,.10),'wood_light',.035);box('台下层板',(0,0,.23),(.86,.55,.07),'wood',.02)
box('工具书',(-.21,0,.91),(.29,.34,.06),'teal',.01);end('table')
# --- Botanicals: distinct packages, never embedded in the house or pots ---
start('leaf_cluster')
for i in range(22):
 a=i*2.399;r=random.uniform(.3,.57);z=random.uniform(.23,.65);base=(random.uniform(-.09,.09),random.uniform(-.09,.09),0)
 leaf('柔软阔叶',base,(r*math.cos(a),r*math.sin(a),z),random.uniform(.075,.14),random.choice(['leaf','leaf_mid','lime','leaf_yellow','leaf_light']))
end('leaf_cluster')
start('vine')
for s in range(4):
 x=(s-1.5)*.14;length=random.uniform(1.2,1.85)
 line('藤茎',[(x,0,.1),(x+.10,-.06,-length*.4),(x-.04,-.03,-length)],.014,'leaf_dark')
 for j in range(13):
  t=j/13;z=-length*t;side=1 if j%2 else -1
  leaf('心形藤叶',(x,-.02,z),(x+side*random.uniform(.16,.29),-.08,z-.18),.09,random.choice(['leaf','lime','leaf_mid','leaf_yellow']))
end('vine')
def flower_cluster(slug,petals,palette):
 start(slug)
 for k in range(5):
  a=k*2.399;cx=.25*math.cos(a);cy=.25*math.sin(a);z=random.uniform(.38,.75)
  line('花茎',[(0,0,0),(cx*.7,cy*.7,z*.5),(cx,cy,z)],.012,'leaf_dark')
  for j in range(3):
   zz=z*(.18+j*.15);side=(-1)**j
   leaf('花叶',(cx*.5,cy*.5,zz),(cx*.5+side*.21,cy*.5+.1,zz+.12),.06,random.choice(['leaf','leaf_yellow','lime']))
  # Tilt the daisy heads slightly toward front camera so petal silhouettes read clearly.
  for i in range(petals):
   a=i*2*pi/petals;rr=.135 if slug!='goldflower' else .10
   uvball('圆润花瓣',(cx+rr*math.cos(a),cy+rr*.80*math.sin(a),z+.035*math.sin(a)),(.105 if slug!='goldflower' else .075,.052,.027),palette[k%len(palette)],rot=(.20,0,a))
  uvball('花蕊',(cx,cy,z+.027),(.066,.066,.04),'gold')
 end(slug)
flower_cluster('daisy',8,['snow','cream'])
flower_cluster('cosmos',5,['pink','rose','pink_light'])
flower_cluster('goldflower',6,['yellow','butter'])
start('palm')
line('棕榈茎',[(0,0,0),(.08,0,.65),(.03,.02,1.4)],.065,'leaf_dark')
for i in range(11):
 a=i*2.399;length=random.uniform(.9,1.55);root=Vector((.03,0,1.25));tip=Vector((math.cos(a)*length,math.sin(a)*length,1.35+random.uniform(.1,.8)))
 line('棕榈叶脉',[root,root+(tip-root)*.5+Vector((0,0,.45)),tip],.022,'leaf_yellow')
 for j in range(9):
  t=.13+j*.09;c=root+(tip-root)*t+Vector((0,0,math.sin(pi*t)*.42));side=Vector((-math.sin(a),math.cos(a),0));ww=.26*math.sin(pi*t)
  for sign in [-1,1]:leaf('棕榈裂叶',c,c+side*ww*sign+(tip-root)*.18-Vector((0,0,.10)),.065,random.choice(['lime','leaf','leaf_yellow','leaf_mid']))
end('palm')
# --- Reference composition ---
inst('foundation',(0,0,1.44))
for x in [-3.12,0,3.12]:
 for y in [-2.9,2.8]:inst('pier',(x,y,-.55))
for ix in range(21):
 for iy in range(4):inst('deck_plank',(-3.45+ix*.345,-2.36+iy*1.57,1.64),rot=(0,0,pi if (ix+iy)%2 else 0))
inst('wall_shell',(0,0,1.71));inst('roof_terrace',(0,0,4.47))
for x in [-1.66,0,1.66]:inst('parapet',(x,-1.19,4.59))
for x in [-2.43,2.43]:
 for y in [-.35,1.29]:inst('parapet',(x,y,4.59),rot=(0,0,pi/2))
slope=math.radians(31)
for x in [-1.53,0,1.53]:
 for y in [-.33,1.13]:
  z=4.9+(y+.33)*math.tan(slope);inst('solar_panel',(x,y,z),rot=(slope,0,0))
for x in [-2.33,-.77,.77,2.33]:inst('roof_beam',(x,.4,5.34),rot=(slope,0,0))
inst('roof_beam',(0,2.02,6.28),rot=(0,0,pi/2),scale=1.25)
inst('door_arch',(-2.42,.44,1.74),rot=(0,0,-pi/2));inst('porthole',(-1.18,-1.185,3.16))
inst('door_shutter',(1.75,-1.35,1.74),rot=(0,0,.43));inst('shelf',(.87,-.67,1.77))
inst('awning',(.65,-1.24,4.05));inst('ladder',(2.31,-1.36,1.72),rot=(-.08,0,0))
inst('lifebuoy',(-2.44,-.75,3.10),rot=(0,0,-pi/2))
inst('bench',(-1.11,-1.86,1.72));inst('rug',(.87,-2.26,1.73))
inst('crate',(-2.68,-1.65,1.72));inst('table',(2.65,-1.85,1.72));inst('boiler',(2.65,-2.7,1.72))
inst('gutter',(2.37,-.75,4.85))
inst('shade_sail',(2.63,-2.08,4.0))
# Tall sail spars built by reusing post geometry at a documented uniform scale.
inst('sail_mast',(3.40,-3.02,1.71))
inst('sail_mast',(3.40,-1.10,1.89))
for x in [-3.3,-1.1,1.1,3.3]:inst('post',(x,-3.1,1.72))
for x in [-3.3,3.3]:
 for y in [-.9,1.3,3.0]:inst('post',(x,y,1.72))
for x in [-2.2,0,2.2]:inst('rope_span',(x,-3.1,2.45))
for x in [-3.3,3.3]:
 for y in [-2.0,.2]:inst('rope_span',(x,y,2.45),rot=(0,0,pi/2))
for x in [-2.2,0,2.2]:inst('tire',(x,-3.37,1.12),rot=(0,.07,0))
for loc,rot in [((-.05,-1.34,3.06),(0,0,0)),((0,2.10,6.37),(0,0,0))]:inst('lantern',loc,rot)
for x,y,kind in [(-2.84,.2,'planter_round'),(-2.75,-2.58,'planter_square'),(-.16,-1.70,'planter_square'),(1.85,-2.15,'planter_round'),(-1.95,-2.1,'planter_round'),(2.70,.3,'planter_round')]:
 inst(kind,(x,y,1.72));h=.46 if kind=='planter_round' else .61
 inst('leaf_cluster',(x,y,1.72+h),rot=(0,0,random.uniform(0,6.28)),scale=.7)
 if x<-2.5:inst('goldflower',(x,y,1.72+h),scale=.8)
inst('cup',(-2.73,.0,2.35));inst('cup',(.65,-.83,4.73))
for x,y in [(-.15,-.75),(1.1,-.65)]:
 inst('planter_round',(x,y,4.73),scale=.64);inst('leaf_cluster',(x,y,5.02),scale=.55)
# Lush roof border with broad leaves, multiple flower species and hanging tendrils.
for i in range(10):
 x=-2.36+i*.51;y=-1.08
 if .15<x<1.7:continue # keep panels and lower terrace readable
 inst('leaf_cluster',(x,y,4.86),rot=(0,0,i*.6),scale=.83)
 inst('cosmos' if i%2 else 'daisy',(x,y,5.02),rot=(0,0,i),scale=.9)
for side in [-1,1]:
 for j in range(7):
  x=side*2.29;y=-.8+j*.48
  inst('leaf_cluster',(x,y,4.86),rot=(0,0,j),scale=.85)
  inst(['daisy','cosmos','goldflower'][j%3],(x,y,5.02),rot=(0,0,j*.7),scale=.92)
 for j in range(5):
  inst('vine',(side*2.43,-.8+j*.7,4.90),rot=(0,0,side*pi/2),scale=.85)
for x in [-1.95,-1.45,-.85]:inst('vine',(x,-1.28,4.96),scale=.67)
for x in [-1.5,-.6,.65,1.6]:
 inst('leaf_cluster',(x,2.24,5.0));inst('cosmos',(x,2.25,5.25))
inst('palm',(-1.62,2.10,5.02),rot=(0,0,.6),scale=1.0)
inst('palm',(-.35,2.35,5.04),rot=(0,0,2.6),scale=.78)
# Trailing greenery at the stone platform corners, leaving the entrance clear.
for x,y in [(-3.38,-2.78),(-3.38,1.8),(3.3,2.7),(-1.1,-3.1),(3.3,-.6)]:
 inst('leaf_cluster',(x,y,1.76),rot=(0,0,y),scale=.9)
 inst('goldflower',(x,y,1.92),scale=.8)
 inst('vine',(x,y-.12,1.8),rot=(0,0,x),scale=1.1)
# Small side step formed from the same deck plank definition.
for y,z in [(-.4,1.39),(-.4,1.13)]:
 for i in range(3):inst('deck_plank',(-3.75-(1.39-z)*1.8,-.5+i*.34,z),rot=(0,0,pi/2),scale=.85)
# Display only.
current=support
ground=box('展示地平面',(0,0,-.73),(200,200,.1),'ice',.01);ground.hide_render=True
world=bpy.data.worlds.new('薄荷天光');scene.world=world;world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.58,.84,.85,1);world.node_tree.nodes['Background'].inputs[1].default_value=.40
wn=world.node_tree.nodes;wl=world.node_tree.links;bg=wn['Background'];camera_bg=wn.new('ShaderNodeBackground');camera_bg.inputs[0].default_value=(.4,.95,1.0,1);camera_bg.inputs[1].default_value=1.4;lp=wn.new('ShaderNodeLightPath');mix=wn.new('ShaderNodeMixShader');wl.new(lp.outputs['Is Camera Ray'],mix.inputs[0]);wl.new(bg.outputs[0],mix.inputs[1]);wl.new(camera_bg.outputs[0],mix.inputs[2]);wl.new(mix.outputs[0],wn['World Output'].inputs[0])

def aim(obj,point):obj.rotation_euler=(Vector(point)-obj.location).to_track_quat('-Z','Y').to_euler()
for name,loc,power,size,col in [('暖阳',(-4,-6,12),1650,7,(1,.86,.68)),('海面柔光',(5,-1,8),1100,6,(.69,.9,1)),('轮廓柔光',(-2,7,10),1900,5,(1,.97,.82))]:
 data=bpy.data.lights.new(name,'AREA');data.energy=power*.8;data.shape='DISK';data.size=size;data.color=col;o=bpy.data.objects.new(name,data);support.objects.link(o);o.location=loc;aim(o,(0,0,2.6))
cam_data=bpy.data.cameras.new('参考图正交镜头');cam=bpy.data.objects.new('参考图正交镜头',cam_data);support.objects.link(cam);cam.location=(-10,-14,11);aim(cam,(0,0,3.1));cam_data.type='ORTHO';cam_data.ortho_scale=11.9;scene.camera=cam
scene.render.engine='CYCLES';scene.cycles.samples=48;scene.cycles.use_denoising=True
scene.render.resolution_x=1400;scene.render.resolution_y=1400;scene.render.resolution_percentage=100
scene.view_settings.view_transform='Standard';scene.view_settings.look='None';scene.view_settings.exposure=-.65
scene.render.image_settings.file_format='PNG';scene.render.film_transparent=False
# Set a useful saved viewport.
for screen in bpy.data.screens:
 for a in screen.areas:
  if a.type=='VIEW_3D':
   a.spaces.active.region_3d.view_perspective='CAMERA';a.spaces.active.shading.type='MATERIAL'
# Produce standalone source packages with the same external palette.
route=json.loads((R/'assets/registry/ledger_index.json').read_text())['domains']['scenes']['ledger']
catalog=[]
for item in plan['components']:
 slug=item['slug'];c=components[slug];dest=D/'component_packages'/slug;dest.mkdir(parents=True,exist_ok=True)
 filepath=dest/(slug+'.blend')
 geometry=[]
 for o in c['meshes']:
  geometry.append({'vertices':[[round(float(v),5) for v in p.co] for p in o.data.vertices],'polygons':[list(p.vertices) for p in o.data.polygons]})
 fingerprint=hashlib.sha256(json.dumps(geometry,sort_keys=True).encode()).hexdigest()
 entry={**item,'collection':c['collection'].name,'root_object':'ROOT_'+slug,'component_blend':str(filepath.relative_to(R)),'bounds_size_m':c['bounds'],'local_origin':[0,0,0],'source_anchor_shift_m':list(c['anchor']),'instance_count':sum(r['component_id']==item['component_id'] for r in records),'palette_uv_layer':'PaletteUV','palette_path':str(palette_path.relative_to(R)),'material_roles':[m.name for m in materials.values()],'collision_owner':'godot_wrapper_pending','geometry_fingerprint':fingerprint,'source_sha256':None,'asset_ledger':route+'#'+item['component_id'],'license':'pending_user_reference_rights_review','runtime_status':'not_integrated','source_package_meshes':[o.name for o in c['meshes']]}
 (dest/'asset_manifest.json').write_text(json.dumps(entry,ensure_ascii=False,indent=2)+'\n');catalog.append(entry)
(D/'component_catalog.json').write_text(json.dumps({'schema':'sea.scene.component_catalog','components':catalog},ensure_ascii=False,indent=2)+'\n')
(D/'component_instances.json').write_text(json.dumps({'schema':'sea.scene.component_instances','source_blend':'solar_flower_house.blend','coordinate_contract':{'source_space':'blender_scene_local','plane':'XY','up':'+Z','rotation':'Euler XYZ radians; includes solar roof tilt','godot_mapping':'(x,y,z) -> (x,z,-y)','deck_top_z_m':1.7125,'scale_policy':'uniform decorative size variation; never nonuniform architectural correction'},'instances':records},ensure_ascii=False,indent=2)+'\n')
(D/'component_tree.txt').write_text('\n'.join(x['category']+' / '+x['slug']+' / '+str(x['instance_count'])+' instances' for x in catalog)+'\n')
bpy.context.window.scene=scene
img.filepath=bpy.path.relpath(str(palette_path),start=str(D))
scene['feature_id']='SEA-ASSET';scene['source_stage']='source_created_runtime_pending';scene['reference_sha256']=plan['reference_sha256']
bpy.ops.wm.save_as_mainfile(filepath=str(OUT),compress=True)
print('SEA_SOURCE_BUILT',len(catalog),'components',len(records),'instances',flush=True)
if '--render' in sys.argv:
 scene.render.filepath=str(W/'previews/solar_flower_house_beauty.png');bpy.ops.render.render(write_still=True)
print('SEA_BUILD_COMPLETE',flush=True)
